//
//  ClinicalIndexSync.swift
//  OpenClinic
//
//  Decides what it takes to bring one patient's indexed chunks in line with
//  the chart. Embedding is the expensive step (about 190 ms a chunk in the
//  Simulator), so a chunk whose text was embedded before keeps its vector and
//  a patient whose chunks have not changed is not touched at all.
//

import Foundation

nonisolated enum ClinicalIndexSync {
    /// A chunk as the vector store holds it.
    struct StoredChunk: Sendable {
        let chunk: ClinicalChunk
        let embedding: [Float]
    }

    enum Plan: Sendable, Equatable {
        /// The index already holds exactly these chunks, embedded at the current dimension.
        case unchanged
        /// Replace the patient's chunks. `reused[i]` is the stored vector for `chunks[i]` when the same
        /// text was embedded before; nil means that chunk has to be embedded.
        case replace(reused: [[Float]?])

        /// How many chunks have to be embedded.
        var embedCount: Int {
            guard case .replace(let reused) = self else { return 0 }
            return reused.filter { $0 == nil }.count
        }
    }

    /// - Parameter dimension: the length of a vector from the embedding provider in use. A stored
    ///   vector of another length came from another provider and is never reused.
    static func plan(chunks: [ClinicalChunk], stored: [StoredChunk], dimension: Int) -> Plan {
        let usable = stored.filter { $0.embedding.count == dimension }
        if usable.count == stored.count,
           chunks.map(signature).sorted() == stored.map({ signature($0.chunk) }).sorted() {
            return .unchanged
        }

        var vectors: [String: [Float]] = [:]
        for entry in usable {
            vectors[entry.chunk.embeddableText] = entry.embedding
        }
        return .replace(reused: chunks.map { vectors[$0.embeddableText] })
    }

    /// Everything about a chunk except its identifier, which is new at every chunking.
    static func signature(_ chunk: ClinicalChunk) -> String {
        let metadata = chunk.metadata
        let date = metadata.dateRecorded.map { String($0.timeIntervalSince1970) } ?? "-"
        return [
            chunk.embeddableText,
            metadata.sourceType.rawValue,
            metadata.clinicalCategory.rawValue,
            metadata.sectionTitle,
            metadata.patientName,
            String(metadata.chunkIndex),
            String(metadata.wordCount),
            date,
        ].joined(separator: "\u{1F}")
    }
}
