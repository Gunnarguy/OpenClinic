//
//  ClinicalRAGService.swift
//  OpenClinic
//
//  Top-level RAG orchestrator. Composes embedding, vector store, FTS5,
//  hybrid search, RAG engine, chunker, and verification gates into
//  a unified clinical retrieval-augmented generation pipeline.
//

import Foundation
import SwiftData
import Combine
import os

// MARK: - Clinical RAG Service

/// Singleton orchestrator for the full RAG pipeline.
@MainActor
final class ClinicalRAGService: ObservableObject {
    static let shared = ClinicalRAGService()

    // Sub-services
    let embeddingService: ClinicalEmbeddingService
    let vectorStore: ClinicalVectorStore
    let ftsService: ClinicalFTSService
    let hybridSearch: ClinicalHybridSearch
    let ragEngine: ClinicalRAGEngine
    let verificationGates: ClinicalVerificationGates

    // Status
    @Published var indexedChunkCount: Int = 0
    @Published var lastIndexTime: Date?
    @Published var isIndexing: Bool = false
    @Published var thinkingSteps: [ThinkingStep] = []

    /// Append a thinking step for live UI streaming.
    func addStep(_ phase: ThinkingPhase, _ title: String, _ detail: String = "", icon: String = "circle.fill", metrics: [String: String] = [:]) {
        thinkingSteps.append(ThinkingStep(phase: phase, title: title, detail: detail, icon: icon, metrics: metrics))
    }

    private func formatGateName(_ key: String) -> String {
        key.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized
    }

    private init() {
        embeddingService = ClinicalEmbeddingService()
        vectorStore = ClinicalVectorStore()
        ftsService = ClinicalFTSService()
        hybridSearch = ClinicalHybridSearch(
            vectorStore: vectorStore,
            ftsService: ftsService,
            embeddingService: embeddingService
        )
        ragEngine = ClinicalRAGEngine(
            embeddingService: embeddingService,
            vectorStore: vectorStore
        )
        verificationGates = ClinicalVerificationGates(embeddingService: embeddingService, vectorStore: vectorStore)
        AppLogger.ai.info("🚀 ClinicalRAGService initialized — embedding: \(self.embeddingService.providerName)")

        // Load persisted vectors from disk
        Task { [vectorStore] in
            await vectorStore.loadFromDisk()
            let count = await vectorStore.count
            await MainActor.run { self.indexedChunkCount = count }
        }
    }

    // MARK: - Indexing

    /// Full reindex of all clinical data. Fast for ~200 chunks.
    func indexAllData(modelContext: ModelContext) async {
        guard !isIndexing else {
            AppLogger.ai.info("⏳ Indexing already in progress — skipping")
            return
        }

        isIndexing = true
        let startTime = CFAbsoluteTimeGetCurrent()
        AppLogger.ai.info("📊 Starting full clinical data reindex…")

        do {
            // Fetch all patients
            let patients = try modelContext.fetch(FetchDescriptor<PatientProfile>(
                sortBy: [SortDescriptor(\.lastName)]
            ))

            // Clear existing indexes
            await vectorStore.clear()
            await ftsService.clear()

            var totalChunks = 0

            for patient in patients {
                let chunks = ClinicalChunker.chunkAllData(for: patient)
                guard !chunks.isEmpty else { continue }

                // Embed all chunks for this patient
                let texts = chunks.map { $0.embeddableText }
                let embeddings = try await embeddingService.embedBatch(texts: texts)

                // Index into vector store
                await vectorStore.insertBatch(chunks: chunks, embeddings: embeddings)

                // Index into FTS5
                await ftsService.insertBatch(chunks: chunks)

                totalChunks += chunks.count
                AppLogger.ai.info("  ✅ \(patient.fullName): \(chunks.count) chunks indexed")
            }

            // Persist vector store to disk
            await vectorStore.saveToDisk()

            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            indexedChunkCount = totalChunks
            lastIndexTime = Date()

            let ftsRows = await ftsService.rowCount
            AppLogger.ai.info("📊 Reindex complete: \(totalChunks) chunks, \(ftsRows) FTS rows, \(patients.count) patients — \(String(format: "%.0f", elapsed))ms")
        } catch {
            AppLogger.ai.error("❌ Reindex failed: \(error.localizedDescription)")
        }

        isIndexing = false
    }

    // MARK: - Query

    /// Standard RAG query: hybrid search → rerank → assemble context.
    func query(text: String, patientScope: UUID? = nil, topK: Int = 10) async throws -> RAGResponse {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Step 1: Hybrid search
        let searchStart = CFAbsoluteTimeGetCurrent()
        let candidates = try await hybridSearch.search(query: text, topK: topK, patientScope: patientScope)
        let searchMs = (CFAbsoluteTimeGetCurrent() - searchStart) * 1000

        // Step 2: RAG engine processing (rerank, MMR, token budget, lost-in-middle)
        let (context, usedChunks) = await ragEngine.processChunks(query: text, candidates: candidates)

        let totalMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        return RAGResponse(
            context: context,
            retrievedChunks: usedChunks,
            metadata: ResponseMetadata(
                retrievedChunkCount: candidates.count,
                usedChunkCount: usedChunks.count,
                embeddingTimeMs: 0,
                searchTimeMs: searchMs,
                totalTimeMs: totalMs,
                verification: nil,
                deepThinkPassesUsed: 1
            )
        )
    }

    /// Query with verification gates.
    func queryWithVerification(text: String, patientScope: UUID? = nil) async throws -> RAGResponse {
        let startTime = CFAbsoluteTimeGetCurrent()
        thinkingSteps = []

        addStep(.queryAnalysis, "Analyzing query", "Extracting clinical intent and key terms", icon: "magnifyingglass")

        let vectorCount = await vectorStore.count
        addStep(.vectorSearch, "Hybrid search", "Searching \(vectorCount) vectors + FTS5 index", icon: "arrow.triangle.branch")
        let searchStart = CFAbsoluteTimeGetCurrent()
        let candidates = try await hybridSearch.search(query: text, topK: 10, patientScope: patientScope)
        let searchMs = (CFAbsoluteTimeGetCurrent() - searchStart) * 1000

        let patientSet = Set(candidates.map { $0.chunk.patientId })
        addStep(.rrfFusion, "RRF fusion: \(candidates.count) candidates", "\(patientSet.count) patients, k=60 reciprocal rank", icon: "arrow.triangle.merge", metrics: ["candidates": "\(candidates.count)", "patients": "\(patientSet.count)", "search_ms": String(format: "%.0f", searchMs)])

        addStep(.reranking, "Reranking candidates", "Cross-encoder scoring + heuristic boosting", icon: "arrow.up.arrow.down")
        let (context, usedChunks) = await ragEngine.processChunks(query: text, candidates: candidates)
        addStep(.mmrDiversity, "\(usedChunks.count) chunks selected", "MMR \u{03BB}=0.7 diversity + token budget + Lost-in-Middle reorder", icon: "square.grid.3x3")

        addStep(.verification, "Running 9 verification gates", "Retrieval \u{00B7} Evidence \u{00B7} Numeric \u{00B7} Contradiction \u{00B7} Semantic \u{00B7} Faithfulness \u{00B7} Quality \u{00B7} Completeness \u{00B7} Isolation", icon: "checkmark.shield")
        let verification = await verificationGates.verify(query: text, responseText: context, retrievedChunks: usedChunks)

        let passedCount = verification.gateResults.values.filter { $0 }.count
        let gateDetail = verification.gateResults.sorted(by: { $0.key < $1.key }).map { "\($0.value ? "\u{2713}" : "\u{2717}") \(formatGateName($0.key))" }.joined(separator: " \u{00B7} ")
        addStep(.verification, "\(passedCount)/\(verification.gateResults.count) gates \u{2014} \(verification.confidence.rawValue.capitalized)", gateDetail, icon: verification.confidence == .high ? "checkmark.shield.fill" : "exclamationmark.shield")

        let totalMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        addStep(.complete, "Pipeline complete", String(format: "%.0fms", totalMs), icon: "checkmark.circle.fill")

        let summaries = usedChunks.map { ChunkSummary(from: $0) }

        return RAGResponse(
            context: context,
            retrievedChunks: usedChunks,
            metadata: ResponseMetadata(
                retrievedChunkCount: candidates.count,
                usedChunkCount: usedChunks.count,
                embeddingTimeMs: 0,
                searchTimeMs: searchMs,
                totalTimeMs: totalMs,
                verification: verification,
                deepThinkPassesUsed: 1,
                thinkingSteps: thinkingSteps,
                sourceChunks: summaries
            )
        )
    }

    /// Deep Think: multi-pass retrieval with iterative refinement.
    func deepThink(text: String, patientScope: UUID? = nil, passes: Int = 3) async throws -> RAGResponse {
        let startTime = CFAbsoluteTimeGetCurrent()
        thinkingSteps = []

        addStep(.queryAnalysis, "Deep Think: \(passes)-pass retrieval", "Multi-pass search with iterative query refinement", icon: "brain.head.profile.fill")

        var allChunks: [RetrievedChunk] = []
        var queries = [text]

        for pass in 0..<passes {
            addStep(.deepThinkPass, "Pass \(pass + 1)/\(passes)", "Searching with \(queries.count) quer\(queries.count == 1 ? "y" : "ies")", icon: "arrow.clockwise")
            AppLogger.ai.info("🧠 Deep Think pass \(pass + 1)/\(passes)")

            for q in queries {
                let candidates = try await hybridSearch.search(query: q, topK: 8, patientScope: patientScope)
                allChunks.append(contentsOf: candidates)
            }

            let passPatients = Set(allChunks.map { $0.chunk.patientId }).count
            addStep(.rrfFusion, "Pass \(pass + 1): \(allChunks.count) total chunks", "\(passPatients) patients covered", icon: "arrow.triangle.merge")

            // Generate follow-up queries from current context (simple extraction)
            if pass < passes - 1 {
                queries = extractFollowUpQueries(from: allChunks, originalQuery: text)
                if !queries.isEmpty {
                    addStep(.followUpExtraction, "Follow-up queries", queries.joined(separator: ", "), icon: "text.magnifyingglass")
                }
            }
        }

        // Deduplicate by chunk ID
        var seen = Set<UUID>()
        let unique = allChunks.filter { seen.insert($0.chunk.id).inserted }
        addStep(.reranking, "Dedup: \(allChunks.count) → \(unique.count) unique", "Cross-encoder reranking \(unique.count) candidates", icon: "arrow.up.arrow.down")

        // Process all accumulated chunks
        let (context, usedChunks) = await ragEngine.processChunks(query: text, candidates: unique, maxChunks: 12)
        addStep(.mmrDiversity, "\(usedChunks.count) chunks selected", "MMR diversity + token budget + Lost-in-Middle reorder", icon: "square.grid.3x3")

        // Verify
        addStep(.verification, "Running 9 verification gates", "Full clinical verification pipeline", icon: "checkmark.shield")
        let verification = await verificationGates.verify(
            query: text,
            responseText: context,
            retrievedChunks: usedChunks
        )

        let passedCount = verification.gateResults.values.filter { $0 }.count
        let gateDetail = verification.gateResults.sorted(by: { $0.key < $1.key }).map { "\($0.value ? "✓" : "✗") \(formatGateName($0.key))" }.joined(separator: " · ")
        addStep(.verification, "\(passedCount)/\(verification.gateResults.count) gates — \(verification.confidence.rawValue.capitalized)", gateDetail, icon: verification.confidence == .high ? "checkmark.shield.fill" : "exclamationmark.shield")

        let totalMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        addStep(.complete, "Deep Think complete", String(format: "%d passes, %.0fms total", passes, totalMs), icon: "checkmark.circle.fill")

        let summaries = usedChunks.map { ChunkSummary(from: $0) }

        return RAGResponse(
            context: context,
            retrievedChunks: usedChunks,
            metadata: ResponseMetadata(
                retrievedChunkCount: unique.count,
                usedChunkCount: usedChunks.count,
                embeddingTimeMs: 0,
                searchTimeMs: 0,
                totalTimeMs: totalMs,
                verification: verification,
                deepThinkPassesUsed: passes,
                thinkingSteps: thinkingSteps,
                sourceChunks: summaries
            )
        )
    }

    // MARK: - Follow-Up Query Extraction

    /// Extract additional search queries from retrieved chunk content.
    private func extractFollowUpQueries(from chunks: [RetrievedChunk], originalQuery: String) -> [String] {
        // Pull unique condition names and medication names from chunks as follow-up queries
        var followUps = Set<String>()

        for chunk in chunks {
            let content = chunk.chunk.content.lowercased()

            // Extract medication names (capitalize first word of each line)
            if chunk.chunk.metadata.clinicalCategory == .medication {
                let lines = chunk.chunk.content.components(separatedBy: "\n")
                for line in lines {
                    if let medName = line.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first,
                       medName.count > 3 {
                        followUps.insert(medName)
                    }
                }
            }

            // Extract condition references
            let clinicalTerms = ["melanoma", "psoriasis", "eczema", "dermatitis", "rosacea",
                                 "basal cell", "squamous cell", "actinic keratosis", "biopsy",
                                 "excision", "cryotherapy", "phototherapy"]
            for term in clinicalTerms where content.contains(term) && !originalQuery.lowercased().contains(term) {
                followUps.insert(term)
            }
        }

        return Array(followUps.prefix(3))
    }
}
