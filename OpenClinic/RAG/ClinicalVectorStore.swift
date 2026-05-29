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

    /// Number of stored vectors.
    var count: Int { entries.count }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        let dir = appSupport.appendingPathComponent("OpenClinic/RAG", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        persistenceURL = dir.appendingPathComponent("vectors.bin")
        // loadFromDisk() is called by the service after init
    }

    // MARK: - Insert

    /// Store a chunk with its embedding vector.
    func insert(chunk: ClinicalChunk, embedding: [Float]) {
        entries[chunk.id] = VectorEntry(chunk: chunk, embedding: embedding)
    }

    /// Batch insert multiple chunks + embeddings.
    func insertBatch(chunks: [ClinicalChunk], embeddings: [[Float]]) {
        precondition(chunks.count == embeddings.count)
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

    // MARK: - Delete

    /// Remove all chunks for a patient.
    func deleteByPatient(_ patientId: UUID) {
        entries = entries.filter { $0.value.chunk.patientId != patientId }
    }

    /// Clear all stored vectors.
    func clear() {
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

    /// Load from binary file.
    func loadFromDisk() {
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
