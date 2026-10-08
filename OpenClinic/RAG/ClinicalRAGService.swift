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

    /// The load of the saved vectors that starts with the service.
    private var loadTask: Task<Void, Never>?

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

        // Load persisted vectors from disk. `syncIndex` waits for this, so the saved index is in
        // memory before anything decides what has to be embedded again.
        loadTask = Task { [vectorStore] in
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

    /// Brings the index in line with the store and embeds only what changed. A chunk whose text is
    /// already indexed keeps its vector, a patient whose chunks are unchanged is not touched, and a
    /// patient who is no longer in the store is removed. This is what runs at launch.
    /// Returns nil when another indexing run was in progress or the sync failed.
    @discardableResult
    func syncIndex(modelContext: ModelContext) async -> IndexSyncSummary? {
        guard !isIndexing else {
            AppLogger.ai.info("⏳ Indexing already in progress — skipping")
            return nil
        }
        isIndexing = true
        defer { isIndexing = false }
        let startTime = CFAbsoluteTimeGetCurrent()

        await loadTask?.value

        do {
            let patients = try modelContext.fetch(FetchDescriptor<PatientProfile>(sortBy: [SortDescriptor(\.lastName)]))
            let currentIDs = Set(patients.map(\.id))
            var unchanged = 0
            var updated = 0
            var embedded = 0
            var reused = 0

            for patient in patients {
                let result = try await syncPatient(patient)
                if result.changed { updated += 1 } else { unchanged += 1 }
                embedded += result.embedded
                reused += result.reused
            }

            var removed = 0
            for patientID in await vectorStore.patientIDs where !currentIDs.contains(patientID) {
                await vectorStore.deleteByPatient(patientID)
                await ftsService.deleteByPatient(patientID)
                removed += 1
            }

            // The keyword index is a second file. When it disagrees with the vectors (a deleted
            // file, an interrupted write), it is rebuilt from the chunks, which needs no embedding.
            // Ids are compared, not counts: two indexes of the same size can hold different chunks.
            let vectorCount = await vectorStore.count
            var ftsRebuilt = false
            let indexedChunks = await vectorStore.allChunks
            if await ftsService.chunkIDs != Set(indexedChunks.map(\.id.uuidString)) {
                await ftsService.clear()
                await ftsService.insertBatch(chunks: indexedChunks)
                ftsRebuilt = true
            }

            if updated > 0 || removed > 0 {
                await vectorStore.saveToDisk()
            }
            indexedChunkCount = vectorCount
            lastIndexTime = Date()

            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            AppLogger.ai.info("📊 Index sync: \(unchanged) patients unchanged, \(updated) updated, \(removed) removed; \(embedded) chunks embedded, \(reused) vectors reused; \(vectorCount) chunks in the index\(ftsRebuilt ? ", keyword index rebuilt" : ""); \(String(format: "%.0f", elapsed))ms")
            return IndexSyncSummary(
                patientsUnchanged: unchanged, patientsUpdated: updated, patientsRemoved: removed,
                chunksEmbedded: embedded, vectorsReused: reused, chunksInIndex: vectorCount, milliseconds: elapsed
            )
        } catch {
            AppLogger.ai.error("❌ Index sync failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Re-indexes one patient's chart and leaves every other patient's chunks in place.
    /// A record import uses this, so importing one chart does not re-embed the whole panel.
    func indexPatient(_ patient: PatientProfile) async {
        // A full reindex that began before this patient was saved read the store without the new rows.
        while isIndexing {
            if Task.isCancelled { return }
            try? await Task.sleep(for: .milliseconds(200))
        }

        isIndexing = true
        defer { isIndexing = false }
        let startTime = CFAbsoluteTimeGetCurrent()
        await loadTask?.value

        do {
            let result = try await syncPatient(patient)
            if result.changed {
                await vectorStore.saveToDisk()
            }
            indexedChunkCount = await vectorStore.count
            lastIndexTime = Date()
            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            AppLogger.ai.info("📊 Patient reindex complete: \(result.embedded) chunks embedded, \(result.reused) vectors reused, \(self.indexedChunkCount) in the index, \(String(format: "%.0f", elapsed))ms")
        } catch {
            AppLogger.ai.error("❌ Patient reindex failed: \(error.localizedDescription)")
        }
    }

    /// What one index sync did. Counts only; nothing from a chart.
    nonisolated struct IndexSyncSummary: Sendable {
        let patientsUnchanged: Int
        let patientsUpdated: Int
        let patientsRemoved: Int
        let chunksEmbedded: Int
        let vectorsReused: Int
        let chunksInIndex: Int
        let milliseconds: Double
    }

    private struct PatientSyncResult {
        var changed = false
        var embedded = 0
        var reused = 0
    }

    /// Chunks one patient's chart and replaces what the index holds for them when it differs.
    /// Embedding comes first: if it fails, the chunks already indexed stay as they were.
    private func syncPatient(_ patient: PatientProfile) async throws -> PatientSyncResult {
        let patientID = patient.id
        let chunks = ClinicalChunker.chunkAllData(for: patient)
        let stored = await vectorStore.entries(for: patientID)

        guard case .replace(let reusedVectors) = ClinicalIndexSync.plan(
            chunks: chunks, stored: stored, dimension: embeddingService.dimension
        ) else {
            return PatientSyncResult()
        }

        let missing = reusedVectors.indices.filter { reusedVectors[$0] == nil }
        let fresh = missing.isEmpty ? [] : try await embeddingService.embedBatch(texts: missing.map { chunks[$0].embeddableText })
        var embeddings = reusedVectors
        for (offset, index) in missing.enumerated() {
            embeddings[index] = fresh[offset]
        }

        await vectorStore.replace(patientId: patientID, chunks: chunks, embeddings: embeddings.compactMap { $0 })
        await ftsService.deleteByPatient(patientID)
        await ftsService.insertBatch(chunks: chunks)
        return PatientSyncResult(changed: true, embedded: missing.count, reused: chunks.count - missing.count)
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

        addStep(.verification, "Scoring retrieved context (9 checks)", "Retrieval \u{00B7} Evidence \u{00B7} Numeric \u{00B7} Contradiction \u{00B7} Semantic \u{00B7} Faithfulness \u{00B7} Quality \u{00B7} Completeness \u{00B7} Isolation", icon: "checkmark.shield")
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
        addStep(.verification, "Scoring retrieved context (9 checks)", "Retrieval checks on the assembled context", icon: "checkmark.shield")
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
