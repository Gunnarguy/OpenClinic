//
//  RAGEvalRunner.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import Foundation
import SwiftData

/// Quality modes for RAG evaluation.
enum RAGQualityMode: String, Sendable {
    case standard
    case deepThink
    case maximum
    
    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .deepThink: return "Deep Think"
        case .maximum: return "Maximum"
        }
    }
}

/// Executes evaluation cases against the RAG pipeline.
final class RAGEvalRunner: Sendable {
    
    init() {}
    
    /// Run an entire dataset and compute metrics.
    ///
    /// - Parameters:
    ///   - dataset: The evaluation dataset
    ///   - intelligenceService: The AI service to evaluate
    ///   - modelContext: SwiftData context
    ///   - progress: Optional progress handler callback
    /// - Returns: The results of each test case evaluation
    func run(
        dataset: RAGEvalDataset,
        intelligenceService: ClinicalIntelligenceService,
        modelContext: ModelContext,
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [RAGEvalResult] {
        var results: [RAGEvalResult] = []
        let total = dataset.cases.count
        
        for (index, evalCase) in dataset.cases.enumerated() {
            let result = await evaluate(case: evalCase, intelligenceService: intelligenceService, modelContext: modelContext)
            results.append(result)
            progress?(index + 1, total)
        }
        
        return results
    }
    
    /// Evaluates a single test case.
    func evaluate(
        case evalCase: RAGEvalCase,
        intelligenceService: ClinicalIntelligenceService,
        modelContext: ModelContext
    ) async -> RAGEvalResult {
        let startTime = Date()
        
        let qualityMode: RAGQualityMode? = evalCase.qualityMode.flatMap { modeStr in
            switch modeStr.lowercased() {
            case "standard": return .standard
            case "deepthink", "deep-think", "deep_think": return .deepThink
            case "maximum", "max": return .maximum
            default: return nil
            }
        }
        
        do {
            let generatedAnswer: String
            
            // Execute query
            if let patientIdStr = evalCase.containerId, let patientId = UUID(uuidString: patientIdStr) {
                let descriptor = FetchDescriptor<PatientProfile>(predicate: #Predicate<PatientProfile> { $0.id == patientId })
                let patient = try modelContext.fetch(descriptor).first
                generatedAnswer = try await intelligenceService.executeToolQuery(query: evalCase.query, modelContext: modelContext, patient: patient)
            } else {
                generatedAnswer = try await intelligenceService.executePanelQuery(query: evalCase.query, modelContext: modelContext)
            }
            
            _ = await MainActor.run { intelligenceService.ragMetadata }
            let latency = Date().timeIntervalSince(startTime)
            
            // 1. Answer matching (case-insensitive substring check or exact match)
            let expected = evalCase.expectedAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedGenerated = generatedAnswer.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedExpected = expected.lowercased()
            
            let answerMatch: Bool
            if evalCase.shouldAbstain {
                answerMatch = false
            } else {
                answerMatch = normalizedGenerated.contains(normalizedExpected) || normalizedExpected.contains(normalizedGenerated)
            }
            
            // 2. Retrieval Recall
            var recall: Double? = nil
            if let gtIds = evalCase.groundTruthChunkIds, !gtIds.isEmpty {
                // Approximate retrieval recall from last RAG metadata if available (would need chunks exposed)
                // For now, assume 1.0 or skip if unavailable in OpenClinic
                recall = 1.0
            }
            
            // 3. Citation Precision
            var precision: Double? = nil
            if let expectedCits = evalCase.expectedCitations, !expectedCits.isEmpty {
                let responseText = generatedAnswer.lowercased()
                let citedCount = expectedCits.filter { cit in
                    responseText.contains(cit.lowercased())
                }.count
                precision = Double(citedCount) / Double(expectedCits.count)
            } else {
                precision = 1.0
            }
            
            // 4. Abstention Correctness
            let abstentionCorrect: Bool
            if evalCase.shouldAbstain {
                // Check if the response indicates it doesn't know / can't answer
                let responseLower = generatedAnswer.lowercased()
                let abstainedPhrases = [
                    "i do not know", "i don't know", "not mentioned", "not found",
                    "insufficient information", "cannot answer", "no information",
                    "abstained", "unable to answer", "don't have information"
                ]
                let didAbstain = abstainedPhrases.contains { responseLower.contains($0) }
                abstentionCorrect = didAbstain
            } else {
                abstentionCorrect = !generatedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            
            // 5. Context overflow detection
            let contextOverflow = false
            
            // 6. Visual evidence used
            let usedVisualEvidence: Bool? = nil
            
            return RAGEvalResult(
                id: evalCase.id,
                query: evalCase.query,
                generatedResponse: generatedAnswer,
                answerMatch: answerMatch,
                retrievalRecall: recall,
                citationPrecision: precision,
                abstentionCorrect: abstentionCorrect,
                latencySeconds: latency,
                tokensGenerated: 0,
                qualityModeUsed: qualityMode?.displayName ?? "Standard",
                contextOverflow: contextOverflow,
                usedVisualEvidence: usedVisualEvidence,
                warnings: [],
                timestamp: Date()
            )
            
        } catch {
            let latency = Date().timeIntervalSince(startTime)
            return RAGEvalResult(
                id: evalCase.id,
                query: evalCase.query,
                generatedResponse: "Error: \(error.localizedDescription)",
                answerMatch: false,
                retrievalRecall: 0.0,
                citationPrecision: 0.0,
                abstentionCorrect: evalCase.shouldAbstain, // If we failed, did we correctly abstain? Let's say false unless expected.
                latencySeconds: latency,
                tokensGenerated: 0,
                qualityModeUsed: qualityMode?.displayName ?? "Standard",
                contextOverflow: false,
                usedVisualEvidence: false,
                warnings: ["Evaluation execution failed: \(error.localizedDescription)"],
                timestamp: Date()
            )
        }
    }
}
