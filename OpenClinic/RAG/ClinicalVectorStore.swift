//
//  ClinicalVectorStore.swift
//  OpenClinic
//
//  In-memory vector store with vDSP cosine similarity and mmap persistence.
//  Thread-safe via actor isolation. Handles variable embedding dimensions.
//

import Foundation
import Accelerate
import os

// MARK: - Vector Store Entry

/// Stored embedding paired with its chunk.
private struct VectorEntry: Codable {
    let chunk: ClinicalChunk
    let embedding: [Float]
}

// MARK: - Clinical Vector Store

/// Actor-isolated in-memory vector store with binary persistence.
actor ClinicalVectorStore {
    private var entries: [UUID: VectorEntry] = [:]
    private let persistenceURL: URL
    /// True once anything has been inserted, deleted or cleared. A load from disk that lands after
    /// that would bring back vectors the index has already replaced, so it is skipped.
    private var hasBeenWritten = false

    /// Number of stored vectors.
    var count: Int { entries.count }

    /// `persistenceURL` is for tests; the app uses the file under Application Support.
    init(persistenceURL: URL? = nil) {
        if let persistenceURL {
            self.persistenceURL = persistenceURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL.temporaryDirectory
            let dir = appSupport.appendingPathComponent("OpenClinic/RAG", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.persistenceURL = dir.appendingPathComponent("vectors.bin")
        }
        // loadFromDisk() is called by the service after init
    }

    // MARK: - Insert

    /// Store a chunk with its embedding vector.
    func insert(chunk: ClinicalChunk, embedding: [Float]) {
        hasBeenWritten = true
        entries[chunk.id] = VectorEntry(chunk: chunk, embedding: embedding)
    }

    /// Batch insert multiple chunks + embeddings.
    func insertBatch(chunks: [ClinicalChunk], embeddings: [[Float]]) {
        precondition(chunks.count == embeddings.count)
        hasBeenWritten = true
        for (chunk, embedding) in zip(chunks, embeddings) {
            entries[chunk.id] = VectorEntry(chunk: chunk, embedding: embedding)
        }
    }

    // MARK: - Search

    /// Find top-K most similar chunks to the query embedding.
    /// Uses vDSP dot product for cosine similarity (embeddings are L2-normalized).
    func search(queryEmbedding: [Float], topK: Int = 10, patientScope: UUID? = nil) -> [RetrievedChunk] {
        let queryDim = queryEmbedding.count
        var scored: [(UUID, Double)] = []
        scored.reserveCapacity(entries.count)

        for (id, entry) in entries {
            // Filter by patient if scoped
            if let scope = patientScope, entry.chunk.patientId != scope { continue }

            let entryDim = entry.embedding.count
            // Dimension mismatch: use the shorter length
            let useDim = min(queryDim, entryDim)
            guard useDim > 0 else { continue }

            var similarity: Float = 0
            vDSP_dotpr(queryEmbedding, 1, entry.embedding, 1, &similarity, vDSP_Length(useDim))
            scored.append((id, Double(similarity)))
        }

        // Sort descending by similarity
        scored.sort { $0.1 > $1.1 }

        return scored.prefix(topK).enumerated().map { rank, pair in
            let entry = entries[pair.0]!
            return RetrievedChunk(
                chunk: entry.chunk,
                score: pair.1,
                vectorRank: rank + 1,
                keywordRank: nil
            )
        }
    }

    /// Get the embedding for a specific chunk.
    func embedding(for chunkId: UUID) -> [Float]? {
        entries[chunkId]?.embedding
    }

    /// Retrieve a stored chunk by its ID.
    func getChunk(id: UUID) -> ClinicalChunk? {
        entries[id]?.chunk
    }

    // MARK: - One patient at a time

    /// The chunks indexed for one patient, with their vectors.
    func entries(for patientId: UUID) -> [ClinicalIndexSync.StoredChunk] {
        entries.values
            .filter { $0.chunk.patientId == patientId }
            .map { ClinicalIndexSync.StoredChunk(chunk: $0.chunk, embedding: $0.embedding) }
    }

    /// Swaps one patient's chunks for a new set and leaves every other patient's alone.
    func replace(patientId: UUID, chunks: [ClinicalChunk], embeddings: [[Float]]) {
        precondition(chunks.count == embeddings.count)
        hasBeenWritten = true
        entries = entries.filter { $0.value.chunk.patientId != patientId }
        for (chunk, embedding) in zip(chunks, embeddings) {
            entries[chunk.id] = VectorEntry(chunk: chunk, embedding: embedding)
        }
    }

    /// Every patient that has at least one chunk in the index.
    var patientIDs: Set<UUID> {
        Set(entries.values.map(\.chunk.patientId))
    }

    /// Every indexed chunk. The keyword index can be rebuilt from these without embedding anything.
    var allChunks: [ClinicalChunk] {
        entries.values.map(\.chunk)
    }

    // MARK: - Delete

    /// Remove all chunks for a patient.
    func deleteByPatient(_ patientId: UUID) {
        hasBeenWritten = true
        entries = entries.filter { $0.value.chunk.patientId != patientId }
    }

    /// Clear all stored vectors.
    func clear() {
        hasBeenWritten = true
        entries.removeAll()
    }

    // MARK: - Persistence

    /// Save to binary file. Call after batch operations.
    func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(Array(self.entries.values))
            try data.write(to: self.persistenceURL, options: .atomic)
            AppLogger.ai.info("💾 VectorStore saved: \(self.entries.count) vectors (\(data.count) bytes)")
        } catch {
            AppLogger.ai.error("❌ VectorStore save failed: \(error.localizedDescription)")
        }
    }

    /// Load from binary file. Does nothing once the store has been written to: on 2026-10-07 the
    /// launch load finished 2.6 s after the launch reindex had cleared the store, and the index
    /// was saved with every chunk twice (1,136 vectors for 568 chunks).
    func loadFromDisk() {
        guard !hasBeenWritten else {
            AppLogger.ai.info("📂 VectorStore load skipped: the index was rebuilt first")
            return
        }
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        do {
            let data = try Data(contentsOf: self.persistenceURL)
            let loaded = try JSONDecoder().decode([VectorEntry].self, from: data)
            for entry in loaded {
                self.entries[entry.chunk.id] = entry
            }
            AppLogger.ai.info("📂 VectorStore loaded: \(self.entries.count) vectors from disk")
        } catch {
            AppLogger.ai.error("❌ VectorStore load failed: \(error.localizedDescription)")
        }
    }
}
