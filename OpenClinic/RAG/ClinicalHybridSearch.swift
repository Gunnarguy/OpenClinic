//
//  ClinicalHybridSearch.swift
//  OpenClinic
//
//  Parallel vector + BM25 search with Reciprocal Rank Fusion (RRF).
//  Combines semantic similarity from ClinicalVectorStore with keyword
//  precision from ClinicalFTSService.
//

import Foundation
import os

// MARK: - Clinical Hybrid Search

/// Fuses vector (semantic) and FTS5 (keyword) search results using RRF.
final class ClinicalHybridSearch: Sendable {
    private let vectorStore: ClinicalVectorStore
    private let ftsService: ClinicalFTSService
    private let embeddingService: ClinicalEmbeddingService

    /// RRF constant — balances contribution of highly-ranked vs lower-ranked results.
    /// k=60 is the standard from Cormack et al. (2009).
    private let rrfK: Double = 60.0

    init(vectorStore: ClinicalVectorStore, ftsService: ClinicalFTSService, embeddingService: ClinicalEmbeddingService) {
        self.vectorStore = vectorStore
        self.ftsService = ftsService
        self.embeddingService = embeddingService
    }

    /// Execute parallel vector + keyword search, fuse with RRF.
    func search(query: String, topK: Int = 10, patientScope: UUID? = nil) async throws -> [RetrievedChunk] {
        // Embed the query for vector search
        let queryEmbedding = try await embeddingService.embed(text: query)

        // Parallel search: vector (semantic) + FTS5 (keyword)
        async let vectorResults = vectorStore.search(
            queryEmbedding: queryEmbedding,
            topK: topK * 2,  // Over-fetch for better fusion
            patientScope: patientScope
        )
        async let keywordResults = ftsService.search(
            query: query,
            topK: topK * 2,
            patientScope: patientScope
        )

        let vec = await vectorResults
        let kw = await keywordResults

        // Build rank maps
        var vectorRanks: [UUID: Int] = [:]
        for (rank, result) in vec.enumerated() {
            vectorRanks[result.chunk.id] = rank + 1
        }

        var keywordRanks: [UUID: Int] = [:]
        for (rank, result) in kw.enumerated() {
            keywordRanks[result.chunkId] = rank + 1
        }

        // Collect all unique chunk IDs
        var allChunkIds = Set(vectorRanks.keys)
        allChunkIds.formUnion(keywordRanks.keys)

        // RRF fusion: score = Σ(1 / (k + rank_i))
        var fusedScores: [(UUID, Double, Int?, Int?)] = []

        for chunkId in allChunkIds {
            var rrfScore: Double = 0
            let vRank = vectorRanks[chunkId]
            let kRank = keywordRanks[chunkId]

            if let vr = vRank {
                rrfScore += 1.0 / (rrfK + Double(vr))
            }
            if let kr = kRank {
                rrfScore += 1.0 / (rrfK + Double(kr))
            }

            fusedScores.append((chunkId, rrfScore, vRank, kRank))
        }

        // Sort by fused score descending
        fusedScores.sort { $0.1 > $1.1 }

        // Build RetrievedChunk results — resolve chunks from vector results first (they have full chunk data)
        var chunkLookup: [UUID: ClinicalChunk] = [:]
        for result in vec {
            chunkLookup[result.chunk.id] = result.chunk
        }

        // Fetch candidate list with FTS-only lookup support
        var rawResults: [RetrievedChunk] = []
        for (chunkId, score, vRank, kRank) in fusedScores.prefix(topK * 2) {
            if let chunk = chunkLookup[chunkId] {
                rawResults.append(RetrievedChunk(
                    chunk: chunk,
                    score: score,
                    vectorRank: vRank,
                    keywordRank: kRank
                ))
            } else if let chunk = await vectorStore.getChunk(id: chunkId) {
                // Resolved FTS-only chunk from vector database (Fixes the FTS-only discard bug!)
                rawResults.append(RetrievedChunk(
                    chunk: chunk,
                    score: score,
                    vectorRank: vRank,
                    keywordRank: kRank
                ))
            }
        }

        // Apply advanced boosts from OpenIntelligence
        let keywordBoosted = applyKeywordMatchBoost(query: query, results: rawResults)
        let structureBoosted = applyStructureTypeBoost(query: query, results: keywordBoosted)

        return Array(structureBoosted.prefix(topK))
    }

    // MARK: - Advanced Boosting Algorithms

    /// Boost chunks that contain EXACT matches of important query keywords with hit-rate scaling.
    private func applyKeywordMatchBoost(query: String, results: [RetrievedChunk]) -> [RetrievedChunk] {
        let queryKeywords = extractImportantKeywords(from: query)
        guard !queryKeywords.isEmpty, !results.isEmpty else { return results }

        let decayCeiling = 0.50  // hit rate at which boost reaches zero (corpus noise)
        let totalChunks = Double(results.count)
        var discriminativeKeywords: [(keyword: String, scaleFactor: Double)] = []

        for keyword in queryKeywords {
            let hitCount = results.filter { $0.chunk.content.lowercased().contains(keyword) }.count
            let hitRate = Double(hitCount) / totalChunks
            let scaleFactor = max(0.0, 1.0 - (hitRate / decayCeiling))
            if scaleFactor > 0.0 {
                discriminativeKeywords.append((keyword: keyword, scaleFactor: scaleFactor))
            }
        }

        guard !discriminativeKeywords.isEmpty else { return results }

        var boostedResults: [RetrievedChunk] = []

        for result in results {
            let contentLower = result.chunk.content.lowercased()
            var weightedMatchScore = 0.0

            for (keyword, scaleFactor) in discriminativeKeywords {
                if contentLower.contains(keyword) {
                    weightedMatchScore += 1.0 * scaleFactor
                    // Extra for exact word boundary matches
                    if contentLower.contains(" \(keyword) ") ||
                       contentLower.contains(" \(keyword).") ||
                       contentLower.contains(" \(keyword),") ||
                       contentLower.hasPrefix("\(keyword) ") ||
                       contentLower.hasSuffix(" \(keyword)") {
                        weightedMatchScore += 1.0 * scaleFactor
                    }
                }
            }

            if weightedMatchScore > 0 {
                let boost = min(0.20, weightedMatchScore * 0.05)
                var boosted = result
                boosted.score += boost
                boostedResults.append(boosted)
            } else {
                boostedResults.append(result)
            }
        }

        return boostedResults.sorted { $0.score > $1.score }
    }

    /// Extract important keywords from query (nouns, verbs - skip stopwords).
    private func extractImportantKeywords(from query: String) -> [String] {
        let stopwords: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "could", "should",
            "may", "might", "must", "shall", "can", "need", "dare", "ought", "used",
            "to", "of", "in", "for", "on", "with", "at", "by", "from", "as", "into",
            "through", "during", "before", "after", "above", "below", "between",
            "this", "that", "these", "those", "what", "which", "who", "whom", "whose",
            "where", "when", "why", "how", "all", "each", "every", "both", "few",
            "more", "most", "other", "some", "such", "no", "nor", "not", "only",
            "own", "same", "so", "than", "too", "very", "just", "also", "now",
            "i", "me", "my", "myself", "we", "our", "ours", "ourselves", "you", "your",
            "he", "him", "his", "she", "her", "it", "its", "they", "them", "their",
            "type", "kind", "sort", "take", "use", "get", "find",
            "tell", "know", "look", "want", "like", "make", "put", "give", "help",
            "work", "come", "thing", "about", "much", "many", "way", "long",
            "patient", "record", "clinic", "health", "care"
        ]

        let normalized = query.lowercased()
        let words = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var seen = Set<String>()
        let important = words.filter { token in
            token.count >= 3 && !stopwords.contains(token) && seen.insert(token).inserted
        }

        return important
    }

    /// Boost table/list chunks when query seeks specific data/specifications (domain-agnostic).
    private func applyStructureTypeBoost(query: String, results: [RetrievedChunk]) -> [RetrievedChunk] {
        let queryLower = query.lowercased()
        guard detectSpecificationQuery(queryLower) else { return results }

        var boostedResults: [RetrievedChunk] = []

        for result in results {
            var boostPoints = 0
            let content = result.chunk.content

            // Check if chunk has a Markdown table
            if content.contains("|") && content.components(separatedBy: "|").count >= 4 {
                boostPoints += 3
            }

            // Check if content has numeric measurements
            if content.rangeOfCharacter(from: .decimalDigits) != nil {
                boostPoints += 1
            }

            // Check for specific clinical measurement patterns
            let specPatterns = [
                #"\d+(?:\.\d+)?\s*(?:mg|mcg|ml|mL|g|kg|mEq|mmol|units)\b"#,
                #"\d+(?:\.\d+)?\s*(?:mmHg|bpm|F|C|%)\b"#,
                #"\d{1,3}/\d{1,3}\b"#
            ]

            for pattern in specPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)) != nil {
                    boostPoints += 2
                }
            }

            if boostPoints >= 3 {
                let boost = min(0.15, Double(boostPoints) * 0.03)
                var boosted = result
                boosted.score += boost
                boostedResults.append(boosted)
            } else {
                boostedResults.append(result)
            }
        }

        return boostedResults.sorted { $0.score > $1.score }
    }

    /// Detect if query is seeking specific data/specifications (domain-agnostic)
    private func detectSpecificationQuery(_ query: String) -> Bool {
        if query.hasPrefix("what is") || query.hasPrefix("what are") || query.hasPrefix("what's") ||
           query.hasPrefix("how much") || query.hasPrefix("how many") || query.hasPrefix("list") {
            return true
        }

        let specKeywords = [
            "dosage", "dose", "level", "levels", "bp", "blood pressure", "temp", "temperature",
            "heart rate", "pulse", "saturation", "lab", "labs", "value", "values", "reading", "readings",
            "mg", "ml", "mmHg", "date", "when", "last", "latest", "history", "trend"
        ]

        return specKeywords.contains { query.contains($0) }
    }
}
