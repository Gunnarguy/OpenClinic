//
//  ClinicalRAGEngine.swift
//  OpenClinic
//
//  Post-retrieval processing: MMR diversity selection, cross-encoder reranking,
//  Lost-in-Middle context assembly, token budget management, and Deep Think
//  multi-pass reasoning.
//

import Foundation
import Accelerate
import CoreML
import os

// MARK: - Clinical RAG Engine

/// Transforms raw retrieved chunks into optimized LLM context.
final class ClinicalRAGEngine: @unchecked Sendable {
    private let embeddingService: ClinicalEmbeddingService
    private let vectorStore: ClinicalVectorStore

    // Cross-encoder (optional — falls back to heuristic scoring)
    private var rerankerModel: MLModel?
    private var rerankerTokenizer: BertWordPieceTokenizer?

    // Token budget for Apple Foundation Model (4K context window)
    private let systemTokenBudget = 400
    private let queryTokenBudget = 100
    private let outputTokenBudget = 800
    private var contextTokenBudget: Int { 4096 - systemTokenBudget - queryTokenBudget - outputTokenBudget }

    // MMR parameters
    private let mmrLambda: Float = 0.7  // 0.7 relevance, 0.3 diversity

    // Medical abbreviation glossary for context injection
    private let abbreviationGlossary = """
    Medical abbreviations: BCC=Basal Cell Carcinoma, SCC=Squamous Cell Carcinoma, BID=Twice Daily, \
    TID=Three Times Daily, QD=Once Daily, PRN=As Needed, PO=By Mouth, IM=Intramuscular, \
    SC/SQ=Subcutaneous, UV=Ultraviolet, SPF=Sun Protection Factor, NMSC=Non-Melanoma Skin Cancer, \
    ABCDE=Asymmetry/Border/Color/Diameter/Evolving, MRN=Medical Record Number, \
    HPI=History of Present Illness, ROS=Review of Systems, A&P=Assessment and Plan, \
    F/U=Follow-Up, Rx=Prescription, Dx=Diagnosis, Tx=Treatment, Hx=History
    """

    init(embeddingService: ClinicalEmbeddingService, vectorStore: ClinicalVectorStore) {
        self.embeddingService = embeddingService
        self.vectorStore = vectorStore
        loadReranker()
    }

    // MARK: - Reranker Setup

    private func loadReranker() {
        // Load TinyBERT cross-encoder if available
        if let url = Bundle.main.url(forResource: "ReRankerModel", withExtension: "mlmodelc") {
            do {
                let config = MLModelConfiguration()
                config.computeUnits = .all
                rerankerModel = try MLModel(contentsOf: url, configuration: config)
                AppLogger.ai.info("✅ ReRanker CoreML model loaded")
            } catch {
                AppLogger.ai.warning("⚠️ ReRanker model load failed: \(error.localizedDescription)")
            }
        }
        rerankerTokenizer = BertWordPieceTokenizer.fromBundle(resourceName: "reranker_vocab")
        if rerankerTokenizer != nil {
            AppLogger.ai.info("✅ ReRanker tokenizer loaded")
        }
    }

    // MARK: - Process Retrieved Chunks

    /// Full post-retrieval pipeline: rerank → MMR → Lost-in-Middle → token budget.
    func processChunks(
        query: String,
        candidates: [RetrievedChunk],
        maxChunks: Int = 8
    ) async -> (context: String, usedChunks: [RetrievedChunk]) {
        guard !candidates.isEmpty else {
            return (context: "No relevant clinical data found.", usedChunks: [])
        }

        // Step 1: Rerank candidates (cross-encoder or heuristic)
        let reranked = await rerank(query: query, candidates: candidates)

        // Step 1.5: Jaccard word-overlap deduplication (drop highly redundant chunks)
        let deduped = deduplicateChunks(chunks: reranked)

        // Step 2: MMR diversity selection
        let diverse = await mmrSelect(candidates: deduped, maxChunks: maxChunks)

        // Step 3: Token budget enforcement
        let budgeted = enforceTokenBudget(chunks: diverse)

        // Step 4: Lost-in-Middle reordering (best at start + end)
        let reordered = lostInMiddleReorder(chunks: budgeted)

        // Step 5: Assemble context string
        let context = assembleContext(chunks: reordered)

        return (context: context, usedChunks: reordered)
    }

    // MARK: - Reranking

    /// Cross-encoder reranking if model available, else heuristic scoring.
    private func rerank(query: String, candidates: [RetrievedChunk]) async -> [RetrievedChunk] {
        if let model = rerankerModel, let tokenizer = rerankerTokenizer {
            return await crossEncoderRerank(query: query, candidates: candidates, model: model, tokenizer: tokenizer)
        }
        return heuristicRerank(query: query, candidates: candidates)
    }

    /// TinyBERT cross-encoder: scores query-chunk pairs directly.
    private func crossEncoderRerank(
        query: String,
        candidates: [RetrievedChunk],
        model: MLModel,
        tokenizer: BertWordPieceTokenizer
    ) async -> [RetrievedChunk] {
        var scored: [(RetrievedChunk, Double)] = []

        for candidate in candidates {
            let pairText = "\(query) [SEP] \(candidate.chunk.embeddableText)"
            let tokenIds = tokenizer.tokenize(pairText)

            let maxSeqLen = 512
            var inputIds = [BertWordPieceTokenizer.clsId] + Array(tokenIds.prefix(maxSeqLen - 2)) + [BertWordPieceTokenizer.sepId]
            var attentionMask = Array(repeating: 1, count: inputIds.count)
            let padLen = maxSeqLen - inputIds.count
            if padLen > 0 {
                inputIds.append(contentsOf: repeatElement(BertWordPieceTokenizer.padId, count: padLen))
                attentionMask.append(contentsOf: repeatElement(0, count: padLen))
            }
            let tokenTypeIds = Array(repeating: 0, count: maxSeqLen)

            do {
                let idsArray = try MLMultiArray(shape: [1, NSNumber(value: maxSeqLen)], dataType: .int32)
                let maskArray = try MLMultiArray(shape: [1, NSNumber(value: maxSeqLen)], dataType: .int32)
                let typesArray = try MLMultiArray(shape: [1, NSNumber(value: maxSeqLen)], dataType: .int32)

                idsArray.withUnsafeMutableBufferPointer(ofType: Int32.self) { ptr, _ in
                    for i in 0..<maxSeqLen { ptr[i] = Int32(inputIds[i]) }
                }
                maskArray.withUnsafeMutableBufferPointer(ofType: Int32.self) { ptr, _ in
                    for i in 0..<maxSeqLen { ptr[i] = Int32(attentionMask[i]) }
                }
                typesArray.withUnsafeMutableBufferPointer(ofType: Int32.self) { ptr, _ in
                    for i in 0..<maxSeqLen { ptr[i] = Int32(tokenTypeIds[i]) }
                }

                let inputs = try MLDictionaryFeatureProvider(dictionary: [
                    "input_ids": MLFeatureValue(multiArray: idsArray),
                    "attention_mask": MLFeatureValue(multiArray: maskArray),
                    "token_type_ids": MLFeatureValue(multiArray: typesArray),
                ])

                let output = try await model.prediction(from: inputs)
                // Cross-encoder outputs a relevance logit
                if let logits = output.featureValue(for: "logits")?.multiArrayValue {
                    let score = Double(logits[0].floatValue)
                    scored.append((candidate, score))
                } else {
                    scored.append((candidate, candidate.score))
                }
            } catch {
                scored.append((candidate, candidate.score))
            }
        }

        return scored.sorted { $0.1 > $1.1 }.map { chunk, score in
            var updated = chunk
            updated.score = score
            return updated
        }
    }

    /// Heuristic reranking: keyword overlap + recency + metadata boost.
    private func heuristicRerank(query: String, candidates: [RetrievedChunk]) -> [RetrievedChunk] {
        let queryTokens = Set(query.lowercased().split(separator: " ").map(String.init))

        return candidates.map { candidate in
            var boostedScore = candidate.score

            // Keyword overlap boost
            let chunkTokens = Set(candidate.chunk.content.lowercased().split(separator: " ").map(String.init))
            let overlap = Double(queryTokens.intersection(chunkTokens).count) / Double(max(queryTokens.count, 1))
            boostedScore += overlap * 0.1

            // Recency boost (newer records score higher)
            if let date = candidate.chunk.metadata.dateRecorded {
                let daysAgo = abs(date.timeIntervalSinceNow) / 86400
                if daysAgo < 30 { boostedScore += 0.05 }
                else if daysAgo < 90 { boostedScore += 0.03 }
                else if daysAgo < 365 { boostedScore += 0.01 }
            }

            // Assessment & Plan boost (most clinically useful section)
            if candidate.chunk.metadata.clinicalCategory == .assessmentAndPlan {
                boostedScore += 0.04
            }

            var updated = candidate
            updated.score = boostedScore
            return updated
        }.sorted { $0.score > $1.score }
    }

    // MARK: - MMR Diversity Selection

    /// Maximal Marginal Relevance: λ*relevance - (1-λ)*max_similarity_to_selected
    private func mmrSelect(candidates: [RetrievedChunk], maxChunks: Int) async -> [RetrievedChunk] {
        guard candidates.count > maxChunks else { return candidates }

        // Get embeddings for pairwise similarity
        var embeddings: [UUID: [Float]] = [:]
        for candidate in candidates {
            if let emb = await vectorStore.embedding(for: candidate.chunk.id) {
                embeddings[candidate.chunk.id] = emb
            }
        }

        var selected: [RetrievedChunk] = []
        var remaining = candidates

        while selected.count < maxChunks, !remaining.isEmpty {
            var bestIdx = 0
            var bestMMR = -Double.infinity

            for (idx, candidate) in remaining.enumerated() {
                let relevance = candidate.score

                // Max similarity to already-selected chunks
                var maxSim: Double = 0
                if let candidateEmb = embeddings[candidate.chunk.id] {
                    for sel in selected {
                        if let selEmb = embeddings[sel.chunk.id] {
                            let dim = min(candidateEmb.count, selEmb.count)
                            var sim: Float = 0
                            vDSP_dotpr(candidateEmb, 1, selEmb, 1, &sim, vDSP_Length(dim))
                            maxSim = max(maxSim, Double(sim))
                        }
                    }
                }

                let mmr = Double(mmrLambda) * relevance - Double(1 - mmrLambda) * maxSim
                if mmr > bestMMR {
                    bestMMR = mmr
                    bestIdx = idx
                }
            }

            selected.append(remaining.remove(at: bestIdx))
        }

        return selected
    }

    // MARK: - Token Budget

    /// Trim chunks to fit within the context token budget.
    private func enforceTokenBudget(chunks: [RetrievedChunk]) -> [RetrievedChunk] {
        var result: [RetrievedChunk] = []
        var usedTokens = abbreviationGlossary.split(separator: " ").count + 20  // Glossary overhead

        for chunk in chunks {
            let chunkText = chunk.chunk.embeddableText
            let chunkTokens = embeddingService.countTokens(chunkText)

            if usedTokens + chunkTokens <= contextTokenBudget {
                usedTokens += chunkTokens
                result.append(chunk)
            } else {
                // Try to fit a truncated version if we can fit at least 50 tokens
                let remainingBudget = contextTokenBudget - usedTokens
                if remainingBudget >= 50 {
                    let rawContent = chunk.chunk.content
                    let wordsInContent = rawContent.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
                    let avgTokenPerWord = Double(chunkTokens) / Double(max(1, wordsInContent))
                    let maxAllowedWords = Int(Double(remainingBudget) / max(0.8, avgTokenPerWord))

                    if maxAllowedWords > 10 {
                        let truncatedContent = truncateAtSentence(rawContent, maxWords: maxAllowedWords)
                        let newChunk = ClinicalChunk(
                            id: chunk.chunk.id,
                            patientId: chunk.chunk.patientId,
                            content: truncatedContent,
                            contextualPrefix: chunk.chunk.contextualPrefix,
                            metadata: chunk.chunk.metadata
                        )
                        let updated = RetrievedChunk(
                            chunk: newChunk,
                            score: chunk.score,
                            vectorRank: chunk.vectorRank,
                            keywordRank: chunk.keywordRank
                        )
                        result.append(updated)
                        usedTokens += remainingBudget
                    }
                }
                break
            }
        }

        return result
    }

    /// Truncate text at a sentence boundary, keeping complete sentences.
    private func truncateAtSentence(_ text: String, maxWords: Int) -> String {
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard words.count > maxWords else { return text }

        let truncatedWords = Array(words.prefix(maxWords))
        let truncatedText = truncatedWords.joined(separator: " ")

        let sentenceEnders: [Character] = [".", "!", "?", ";"]
        let searchRangeStart = Int(Double(truncatedText.count) * 0.7)
        if let lastEndIndex = truncatedText.suffix(truncatedText.count - searchRangeStart).lastIndex(where: { sentenceEnders.contains($0) }) {
            let endIdx = truncatedText.index(after: lastEndIndex)
            return String(truncatedText[..<endIdx])
        }

        return truncatedText + "…"
    }

    /// Dedup chunks using Jaccard word overlap to avoid duplicate boilerplate in LLM context.
    private func deduplicateChunks(chunks: [RetrievedChunk]) -> [RetrievedChunk] {
        var uniqueChunks: [RetrievedChunk] = []
        var usedWordSets: [Set<String>] = []

        for chunk in chunks {
            let content = chunk.chunk.content.lowercased()
            let words = Set(content.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 })

            if words.count >= 5 {
                let isDuplicate = usedWordSets.contains { existingWords in
                    let intersection = words.intersection(existingWords)
                    let union = words.union(existingWords)
                    guard !union.isEmpty else { return false }
                    let jaccard = Double(intersection.count) / Double(union.count)
                    return jaccard >= 0.75
                }
                if isDuplicate {
                    continue
                }
            }
            uniqueChunks.append(chunk)
            usedWordSets.append(words)
        }
        return uniqueChunks
    }

    // MARK: - Lost-in-Middle Mitigation

    /// Reorder chunks so the most relevant are at start AND end of context.
    /// LLMs attend poorly to middle positions (Liu et al., 2023).
    private func lostInMiddleReorder(chunks: [RetrievedChunk]) -> [RetrievedChunk] {
        guard chunks.count > 2 else { return chunks }

        // Already sorted by score descending. Interleave: odd-rank → start, even-rank → end
        var reordered: [RetrievedChunk] = []
        var tail: [RetrievedChunk] = []

        for (idx, chunk) in chunks.enumerated() {
            if idx % 2 == 0 {
                reordered.append(chunk)
            } else {
                tail.insert(chunk, at: 0)
            }
        }

        reordered.append(contentsOf: tail)
        return reordered
    }

    // MARK: - Context Assembly

    /// Build the final context string for the LLM prompt.
    func assembleContext(chunks: [RetrievedChunk]) -> String {
        guard !chunks.isEmpty else { return "No relevant clinical data found." }

        var lines: [String] = [abbreviationGlossary, ""]

        for (idx, chunk) in chunks.enumerated() {
            let prefix = chunk.chunk.contextualPrefix
            let section = chunk.chunk.metadata.sectionTitle
            let dateStr = chunk.chunk.metadata.dateRecorded?.formatted(date: .abbreviated, time: .omitted) ?? ""

            lines.append("--- Source \(idx + 1) [\(section)] \(dateStr) ---")
            if !prefix.isEmpty { lines.append(prefix) }
            lines.append(chunk.chunk.content)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
