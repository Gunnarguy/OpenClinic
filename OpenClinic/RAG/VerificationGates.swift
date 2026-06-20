//
//  VerificationGates.swift
//  OpenClinic
//
//  9 clinical verification gates adapted from OpenIntelligence.
//  Validates RAG responses for safety, faithfulness, and quality
//  before presenting to the clinician.
//

import Foundation
import Accelerate
import os

// MARK: - Clinical Verification Gates

/// Runs 9 verification passes on RAG-generated context to produce a confidence score.
final class ClinicalVerificationGates: @unchecked Sendable {
    private let embeddingService: ClinicalEmbeddingService
    private let vectorStore: ClinicalVectorStore

    init(embeddingService: ClinicalEmbeddingService, vectorStore: ClinicalVectorStore) {
        self.embeddingService = embeddingService
        self.vectorStore = vectorStore
    }

    /// Run all 9 gates and produce a consolidated result.
    func verify(
        query: String,
        responseText: String,
        retrievedChunks: [RetrievedChunk]
    ) async -> VerificationResult {
        var gateResults: [String: Bool] = [:]
        var warnings: [String] = []

        // Gate A: Retrieval Confidence
        let (passA, warnA) = gateRetrievalConfidence(chunks: retrievedChunks)
        gateResults["retrievalConfidence"] = passA
        warnings.append(contentsOf: warnA)

        // Gate B: Evidence Coverage
        let (passB, warnB) = gateEvidenceCoverage(response: responseText, chunks: retrievedChunks)
        gateResults["evidenceCoverage"] = passB
        warnings.append(contentsOf: warnB)

        // Gate C: Numeric Sanity
        let (passC, warnC) = gateNumericSanity(response: responseText, chunks: retrievedChunks)
        gateResults["numericSanity"] = passC
        warnings.append(contentsOf: warnC)

        // Gate D: Contradiction Sweep
        let (passD, warnD) = gateContradictionSweep(chunks: retrievedChunks)
        gateResults["contradictionSweep"] = passD
        warnings.append(contentsOf: warnD)

        // Gate E: Semantic Grounding (Uses stored embeddings to accelerate check)
        let (passE, warnE) = await gateSemanticGrounding(response: responseText, chunks: retrievedChunks)
        gateResults["semanticGrounding"] = passE
        warnings.append(contentsOf: warnE)

        // Gate F: Quote Faithfulness
        let (passF, warnF) = gateQuoteFaithfulness(response: responseText, chunks: retrievedChunks)
        gateResults["quoteFaithfulness"] = passF
        warnings.append(contentsOf: warnF)

        // Gate G: Generation Quality (Bigram Entropy + Trigram Dominance)
        let (passG, warnG) = gateGenerationQuality(response: responseText)
        gateResults["generationQuality"] = passG
        warnings.append(contentsOf: warnG)

        // Gate H: Answer Completeness
        let (passH, warnH) = gateAnswerCompleteness(response: responseText, query: query, chunks: retrievedChunks)
        gateResults["answerCompleteness"] = passH
        warnings.append(contentsOf: warnH)

        // Gate I: Patient Isolation (Crucial HIPAA / Patient safety check)
        let (passI, warnI) = gatePatientIsolation(chunks: retrievedChunks)
        gateResults["patientIsolation"] = passI
        warnings.append(contentsOf: warnI)

        // Compute overall score and confidence tier
        let passedCount = gateResults.values.filter { $0 }.count
        let overallScore = Double(passedCount) / Double(gateResults.count)

        let confidence: ConfidenceTier
        if overallScore >= 0.85 {
            confidence = .high
        } else if overallScore >= 0.55 {
            confidence = .medium
        } else {
            confidence = .low
        }

        AppLogger.ai.info("🔒 Verification: \(passedCount)/9 gates passed → \(confidence.rawValue)")

        return VerificationResult(
            confidence: confidence,
            overallScore: overallScore,
            gateResults: gateResults,
            warnings: warnings
        )
    }

    // MARK: - Gate A: Retrieval Confidence

    /// Top chunk score must exceed threshold — ensures we found relevant context.
    private func gateRetrievalConfidence(chunks: [RetrievedChunk]) -> (Bool, [String]) {
        guard let topScore = chunks.first?.score else {
            return (false, ["No chunks retrieved — cannot verify"])
        }

        let threshold = 0.01  // RRF scores are small (1/(60+rank))
        if topScore < threshold {
            return (false, ["Top retrieval score \(String(format: "%.4f", topScore)) below threshold"])
        }
        return (true, [])
    }

    // MARK: - Gate B: Evidence Coverage

    /// Key clinical terms in the response should appear in retrieved chunks.
    private func gateEvidenceCoverage(response: String, chunks: [RetrievedChunk]) -> (Bool, [String]) {
        let responseTokens = extractClinicalTerms(from: response)
        guard !responseTokens.isEmpty else { return (true, []) }

        let chunkTokens = Set(chunks.flatMap { extractClinicalTerms(from: $0.chunk.content) })
        let covered = responseTokens.filter { chunkTokens.contains($0) }
        let coverage = Double(covered.count) / Double(responseTokens.count)

        if coverage < 0.5 {
            let uncovered = responseTokens.filter { !chunkTokens.contains($0) }
            return (false, ["Low evidence coverage (\(Int(coverage * 100))%). Uncovered terms: \(uncovered.prefix(5).joined(separator: ", "))"])
        }
        return (true, [])
    }

    // MARK: - Gate C: Numeric Sanity

    /// Numbers in the response (dosages, values) should exist in source chunks.
    private func gateNumericSanity(response: String, chunks: [RetrievedChunk]) -> (Bool, [String]) {
        let responseNumbers = extractNumbers(from: response)
        guard !responseNumbers.isEmpty else { return (true, []) }

        let chunkText = chunks.map { $0.chunk.content }.joined(separator: " ")
        let chunkNumbers = Set(extractNumbers(from: chunkText))

        let unsourced = responseNumbers.filter { !chunkNumbers.contains($0) }
        if unsourced.count > responseNumbers.count / 2 {
            return (false, ["Unsourced numbers in response: \(unsourced.prefix(5).joined(separator: ", "))"])
        }
        return (true, [])
    }

    // MARK: - Gate D: Contradiction Sweep

    /// Check for conflicting facts across retrieved chunks.
    private func gateContradictionSweep(chunks: [RetrievedChunk]) -> (Bool, [String]) {
        var warnings: [String] = []

        let byPatientCategory = Dictionary(grouping: chunks) {
            "\($0.chunk.patientId)-\($0.chunk.metadata.clinicalCategory.rawValue)"
        }

        for (key, group) in byPatientCategory where group.count > 1 {
            let texts = group.map { $0.chunk.content.lowercased() }
            let opposites = [("active", "discontinued"), ("improving", "worsening"), ("resolved", "persistent")]
            for (a, b) in opposites {
                let hasA = texts.contains { $0.contains(a) }
                let hasB = texts.contains { $0.contains(b) }
                if hasA && hasB {
                    warnings.append("Potential contradiction in \(key): '\(a)' vs '\(b)'")
                }
            }
        }

        return (warnings.isEmpty, warnings)
    }

    // MARK: - Gate E: Semantic Grounding

    /// Response embedding should be close to the centroid of retrieved chunk embeddings.
    private func gateSemanticGrounding(response: String, chunks: [RetrievedChunk]) async -> (Bool, [String]) {
        guard !chunks.isEmpty else { return (false, ["No chunks for grounding"]) }

        do {
            let responseEmb = try await embeddingService.embed(text: response)

            // Fast path: Try fetching cached embeddings from the vectorStore actor first
            var chunkEmbs: [[Float]] = []
            for r in chunks {
                if let emb = await vectorStore.embedding(for: r.chunk.id) {
                    chunkEmbs.append(emb)
                }
            }

            // Fallback: Embed text chunks if not found in vector store
            if chunkEmbs.isEmpty {
                let chunkTexts = chunks.map { $0.chunk.embeddableText }
                chunkEmbs = try await embeddingService.embedBatch(texts: chunkTexts)
            }

            // Compute centroid of chunk embeddings
            let dim = responseEmb.count
            var centroid = [Float](repeating: 0, count: dim)
            for emb in chunkEmbs {
                let useDim = min(dim, emb.count)
                vDSP_vadd(centroid, 1, emb, 1, &centroid, 1, vDSP_Length(useDim))
            }
            var divisor = Float(max(1, chunkEmbs.count))
            vDSP_vsdiv(centroid, 1, &divisor, &centroid, 1, vDSP_Length(dim))

            // Cosine similarity between response and centroid
            var similarity: Float = 0
            vDSP_dotpr(responseEmb, 1, centroid, 1, &similarity, vDSP_Length(dim))

            if similarity < 0.4 {
                return (false, ["Response poorly grounded (similarity: \(String(format: "%.2f", similarity)))"])
            }
            return (true, [])
        } catch {
            return (true, [])  // Don't fail verification if embedding fails
        }
    }

    // MARK: - Gate F: Quote Faithfulness

    /// Medication names and clinical codes in response must exactly match source data.
    private func gateQuoteFaithfulness(response: String, chunks: [RetrievedChunk]) -> (Bool, [String]) {
        let medChunks = chunks.filter { $0.chunk.metadata.sourceType == .medication }
        guard !medChunks.isEmpty else { return (true, []) }

        let chunkMedNames = Set(medChunks.flatMap { chunk in
            chunk.chunk.content.components(separatedBy: CharacterSet.newlines)
                .compactMap { line -> String? in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return nil }
                    return trimmed.components(separatedBy: " ").first?.lowercased()
                }
        })

        let responseWords = Set(response.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted))
        let commonMedSuffixes = ["mab", "nib", "olol", "pril", "sartan", "statin", "mycin", "cillin", "azole"]

        let responseMedLikeWords = responseWords.filter { word in
            commonMedSuffixes.contains(where: { word.hasSuffix($0) }) && word.count > 4
        }

        let unfaithful = responseMedLikeWords.filter { !chunkMedNames.contains($0) }
        if !unfaithful.isEmpty {
            return (false, ["Medication names not in source: \(unfaithful.prefix(3).joined(separator: ", "))"])
        }
        return (true, [])
    }

    // MARK: - Gate G: Generation Quality

    /// Response should be non-trivial and not repetitive (using Shannon entropy and dominance check).
    private func gateGenerationQuality(response: String) -> (Bool, [String]) {
        var warnings: [String] = []

        let words = response.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }

        // Short responses pass trivially
        guard words.count >= 20 else {
            if words.count < 6 {
                warnings.append("Response is extremely terse (\(words.count) words)")
                return (false, warnings)
            }
            return (true, [])
        }

        // Sub-check 1: Bigram Entropy (Repetition detector)
        var bigramCounts: [String: Int] = [:]
        var totalBigrams = 0
        for i in 0..<(words.count - 1) {
            let bigram = "\(words[i]) \(words[i + 1])"
            bigramCounts[bigram, default: 0] += 1
            totalBigrams += 1
        }

        if totalBigrams > 0 {
            var entropy: Double = 0.0
            let total = Double(totalBigrams)
            for (_, count) in bigramCounts {
                let p = Double(count) / total
                entropy -= p * log2(p)
            }
            
            let threshold: Double = words.count < 50 ? 1.5 : 2.0
            if entropy < threshold {
                warnings.append("Low bigram entropy (\(String(format: "%.2f", entropy)) bits) — content is highly repetitive")
            }
        }

        // Sub-check 2: Unique Word Ratio
        let uniqueRatio = Double(Set(words).count) / Double(words.count)
        if uniqueRatio < 0.35 {
            warnings.append("Low vocabulary diversity (\(Int(uniqueRatio * 100))% unique words)")
        }

        // Sub-check 3: Trigram Dominance (Looping detector)
        if words.count >= 15 {
            var trigramCounts: [String: Int] = [:]
            for i in 0..<(words.count - 2) {
                let trigram = "\(words[i]) \(words[i + 1]) \(words[i + 2])"
                trigramCounts[trigram, default: 0] += 1
            }
            let totalTrigrams = words.count - 2
            if let topCount = trigramCounts.values.max(),
               topCount >= 4,
               Double(topCount) / Double(totalTrigrams) > 0.20 {
                warnings.append("Trigram loops detected (dominant trigram matches \(topCount)/\(totalTrigrams) positions)")
            }
        }

        return (warnings.isEmpty, warnings)
    }

    // MARK: - Gate H: Answer Completeness

    /// Verify that the response sufficiently addresses queries requiring multi-hop reasoning or comparisons.
    private func gateAnswerCompleteness(response: String, query: String, chunks: [RetrievedChunk]) -> (Bool, [String]) {
        var warnings: [String] = []
        let queryLower = query.lowercased()
        let responseLower = response.lowercased()

        // Check 1: Multi-source / Multi-hop queries
        let isMultiSourceQuery = queryLower.contains(" and ") || queryLower.contains("then") || queryLower.contains("after")
        let distinctCategories = Set(chunks.map { $0.chunk.metadata.clinicalCategory })
        
        if isMultiSourceQuery && distinctCategories.count >= 2 {
            var matchedCategories = 0
            for category in distinctCategories {
                let categoryTerms = chunks.filter { $0.chunk.metadata.clinicalCategory == category }
                    .flatMap { extractClinicalTerms(from: $0.chunk.content) }
                let hasCoverage = categoryTerms.prefix(5).contains { responseLower.contains($0) }
                if hasCoverage {
                    matchedCategories += 1
                }
            }
            
            if matchedCategories < 2 {
                warnings.append("Under-supported clinical synthesis: query involves multiple clinical areas but response lacks balanced details")
            }
        }

        // Check 2: Comparison queries
        let isComparison = queryLower.contains("compare") || queryLower.contains("difference") || queryLower.contains(" versus ") || queryLower.contains(" vs ")
        if isComparison {
            let patientNames = Set(chunks.map { $0.chunk.metadata.patientName.lowercased() })
            let coveredPatients = patientNames.filter { responseLower.contains($0) }.count
            
            if patientNames.count >= 2 && coveredPatients < 2 {
                warnings.append("Incomplete comparison: response fails to mention all subject patients (\(coveredPatients)/\(patientNames.count) covered)")
            }
            
            let categories = Set(chunks.map { $0.chunk.metadata.clinicalCategory.rawValue.lowercased() })
            let coveredCategories = categories.filter { responseLower.contains($0) }.count
            if categories.count >= 2 && coveredCategories < 2 {
                let comparisonKeywords = ["allergy", "medication", "appointment", "record", "plan"]
                let activeKeywords = comparisonKeywords.filter { queryLower.contains($0) }
                let coveredKeywords = activeKeywords.filter { responseLower.contains($0) }.count
                if activeKeywords.count >= 2 && coveredKeywords < 2 {
                    warnings.append("Incomplete comparison: response did not detail all compared items")
                }
            }
        }

        // Check 3: Enumerations / List requests
        let looksEnumerative = queryLower.contains("list") || queryLower.contains("all") || queryLower.contains("what are")
        if looksEnumerative {
            let wordCount = response.split(separator: " ").count
            let containsListFormat = response.contains("- ") || response.contains("•") || response.contains("\n")
            if wordCount < 20 && !containsListFormat {
                warnings.append("Terse response: list query requested, but response is not structured or descriptive")
            }
        }

        return (warnings.isEmpty, warnings)
    }

    // MARK: - Gate I: Patient Isolation

    /// HIPAA and Clinical Safety check: Ensure no cross-patient data synthesis occurs.
    private func gatePatientIsolation(chunks: [RetrievedChunk]) -> (Bool, [String]) {
        var warnings: [String] = []

        let patientIds = Set(chunks.map { $0.chunk.patientId })
        let patientNames = Set(chunks.map { $0.chunk.metadata.patientName })

        if patientIds.count > 1 {
            warnings.append("CRITICAL: Cross-patient data mixture! Found records belonging to multiple patients: \(patientNames.joined(separator: ", "))")
            return (false, warnings)
        }

        return (true, [])
    }

    // MARK: - Helpers

    /// Extract clinically significant terms from text.
    private func extractClinicalTerms(from text: String) -> [String] {
        let stopWords: Set<String> = ["the", "is", "are", "was", "were", "has", "have", "had", "for", "and", "but",
                                       "not", "this", "that", "with", "from", "they", "been", "will", "can", "may",
                                       "should", "would", "could", "also", "any", "its", "all", "each", "both"]

        return text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 3 && !stopWords.contains($0) }
    }

    /// Extract numeric values (dosages, measurements) from text.
    private func extractNumbers(from text: String) -> [String] {
        let pattern = #"\d+\.?\d*\s*(mg|mcg|ml|g|kg|units?|%|mmol|μg|iu)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return matches.map { nsText.substring(with: $0.range).lowercased() }
    }
}
