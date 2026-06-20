//
//  ClinicalFTSService.swift
//  OpenClinic
//
//  SQLite FTS5 full-text search for clinical chunks.
//  Raw SQLite3 C API — SwiftData doesn't support FTS5 virtual tables.
//  Adapted from OpenIntelligence's SQLiteFullTextService.
//

import Foundation
import SQLite3
import os

// MARK: - FTS5 Search Result

/// A BM25-scored result from full-text search.
struct FTSSearchResult: Sendable {
    let chunkId: UUID
    let patientId: UUID
    let content: String
    let sectionTitle: String
    let clinicalCategory: String
    let bm25Score: Double
}

// MARK: - Clinical FTS Service

/// Actor-isolated SQLite FTS5 service for keyword-based clinical search.
actor ClinicalFTSService {
    private var database: OpaquePointer?
    private var isInitialized = false

    private var databasePath: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        let dir = appSupport.appendingPathComponent("OpenClinic/RAG", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("clinical_fts.sqlite")
    }

    // Need a stable pointer for SQLITE_TRANSIENT
    private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init() {
        // Lazy initialization — ensureInitialized() is called at every entry point
    }

    deinit {
        if let db = database { sqlite3_close(db) }
    }

    /// Total rows in FTS table.
    var rowCount: Int {
        ensureInitialized()
        guard let db = database else { return 0 }
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM clinical_meta", -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    // MARK: - Initialization

    private func ensureInitialized() {
        guard !isInitialized else { return }
        isInitialized = initializeDatabase()
    }

    private func initializeDatabase() -> Bool {
        let path = databasePath.path

        guard sqlite3_open(path, &database) == SQLITE_OK else {
            if let db = database {
                let err = String(cString: sqlite3_errmsg(db))
                AppLogger.ai.error("❌ FTS5 DB open failed: \(err)")
                sqlite3_close(db)
                database = nil
            }
            return false
        }

        execute("PRAGMA journal_mode=WAL")
        execute("PRAGMA busy_timeout=3000")

        // FTS5 virtual table:
        // Searchable columns: content, section_title, patient_name, clinical_category
        // UNINDEXED: chunk_id, patient_id, source_type, date_recorded
        let createFTS = """
            CREATE VIRTUAL TABLE IF NOT EXISTS clinical_chunks USING fts5(
                chunk_id UNINDEXED,
                patient_id UNINDEXED,
                source_type UNINDEXED,
                date_recorded UNINDEXED,
                content,
                section_title,
                patient_name,
                clinical_category,
                tokenize='porter unicode61'
            )
        """

        guard execute(createFTS) else {
            AppLogger.ai.error("❌ Failed to create FTS5 table")
            return false
        }

        // B-tree metadata table for fast lookups
        let createMeta = """
            CREATE TABLE IF NOT EXISTS clinical_meta (
                chunk_id TEXT PRIMARY KEY,
                patient_id TEXT NOT NULL,
                word_count INTEGER NOT NULL,
                source_type TEXT NOT NULL,
                created_at REAL NOT NULL
            )
        """
        execute(createMeta)

        AppLogger.ai.info("✅ FTS5 database initialized at \(path)")
        return true
    }

    // MARK: - Insert

    func insert(chunk: ClinicalChunk) {
        ensureInitialized()
        guard let db = database else { return }

        let ftsSQL = """
            INSERT INTO clinical_chunks (chunk_id, patient_id, source_type, date_recorded, content, section_title, patient_name, clinical_category)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, ftsSQL, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        let chunkIdStr = chunk.id.uuidString
        let patientIdStr = chunk.patientId.uuidString
        let sourceType = chunk.metadata.sourceType.rawValue
        let dateStr = chunk.metadata.dateRecorded.map { ISO8601DateFormatter().string(from: $0) } ?? ""
        let content = chunk.contextualPrefix.isEmpty ? chunk.content : "\(chunk.contextualPrefix) \(chunk.content)"
        let sectionTitle = chunk.metadata.sectionTitle
        let patientName = chunk.metadata.patientName
        let category = chunk.metadata.clinicalCategory.rawValue

        sqlite3_bind_text(stmt, 1, chunkIdStr, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 2, patientIdStr, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 3, sourceType, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 4, dateStr, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 5, content, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 6, sectionTitle, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 7, patientName, -1, sqliteTransient)
        sqlite3_bind_text(stmt, 8, category, -1, sqliteTransient)

        if sqlite3_step(stmt) != SQLITE_DONE {
            let err = String(cString: sqlite3_errmsg(db))
            AppLogger.ai.error("❌ FTS5 insert failed: \(err)")
            return
        }

        // Metadata row
        let metaSQL = "INSERT OR REPLACE INTO clinical_meta (chunk_id, patient_id, word_count, source_type, created_at) VALUES (?, ?, ?, ?, ?)"
        var metaStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, metaSQL, -1, &metaStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(metaStmt, 1, chunkIdStr, -1, sqliteTransient)
            sqlite3_bind_text(metaStmt, 2, patientIdStr, -1, sqliteTransient)
            sqlite3_bind_int64(metaStmt, 3, Int64(chunk.metadata.wordCount))
            sqlite3_bind_text(metaStmt, 4, sourceType, -1, sqliteTransient)
            sqlite3_bind_double(metaStmt, 5, Date().timeIntervalSince1970)
            sqlite3_step(metaStmt)
            sqlite3_finalize(metaStmt)
        }
    }

    /// Batch insert with transaction for performance.
    func insertBatch(chunks: [ClinicalChunk]) {
        ensureInitialized()
        guard let _ = database, !chunks.isEmpty else { return }
        execute("BEGIN TRANSACTION")
        for chunk in chunks { insert(chunk: chunk) }
        execute("COMMIT")
        AppLogger.ai.info("📝 FTS5 indexed \(chunks.count) chunks")
    }

    // MARK: - Search

    /// BM25-ranked full-text search across clinical chunks.
    /// Tries AND query first, falls back to OR if no results.
    func search(query: String, topK: Int = 10, patientScope: UUID? = nil) -> [FTSSearchResult] {
        ensureInitialized()
        guard let db = database else { return [] }

        let tokens = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
            .map { "\"\($0)\"" }
        guard !tokens.isEmpty else { return [] }

        // Try AND first for precision
        let andQuery = tokens.joined(separator: " AND ")
        var results = executeSearch(db: db, ftsQuery: andQuery, topK: topK, patientScope: patientScope)

        // Fall back to OR if AND returns nothing
        if results.isEmpty {
            let orQuery = tokens.joined(separator: " OR ")
            results = executeSearch(db: db, ftsQuery: orQuery, topK: topK, patientScope: patientScope)
        }

        return results
    }

    private func executeSearch(db: OpaquePointer, ftsQuery: String, topK: Int, patientScope: UUID?) -> [FTSSearchResult] {
        // BM25 scoring: weight content 2.0x, section_title 1.5x, patient_name 1.0x, category 1.0x
        // bm25 column order matches FTS5 column order (skip UNINDEXED columns)
        var sql = """
            SELECT chunk_id, patient_id, content, section_title, clinical_category,
                   bm25(clinical_chunks, 0, 0, 0, 0, 2.0, 1.5, 1.0, 1.0) as score
            FROM clinical_chunks
            WHERE clinical_chunks MATCH ?
        """

        if patientScope != nil {
            sql += " AND patient_id = ?"
        }

        sql += " ORDER BY score LIMIT ?"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            let err = String(cString: sqlite3_errmsg(db))
            AppLogger.ai.error("❌ FTS5 search prepare failed: \(err)")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var paramIdx: Int32 = 1
        sqlite3_bind_text(stmt, paramIdx, ftsQuery, -1, sqliteTransient)
        paramIdx += 1

        if let scope = patientScope {
            let scopeStr = scope.uuidString
            sqlite3_bind_text(stmt, paramIdx, scopeStr, -1, sqliteTransient)
            paramIdx += 1
        }
        sqlite3_bind_int(stmt, paramIdx, Int32(topK))

        var results: [FTSSearchResult] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let chunkIdCStr = sqlite3_column_text(stmt, 0),
                  let patientIdCStr = sqlite3_column_text(stmt, 1),
                  let contentCStr = sqlite3_column_text(stmt, 2),
                  let sectionCStr = sqlite3_column_text(stmt, 3),
                  let categoryCStr = sqlite3_column_text(stmt, 4),
                  let chunkId = UUID(uuidString: String(cString: chunkIdCStr)),
                  let patientId = UUID(uuidString: String(cString: patientIdCStr)) else { continue }

            results.append(FTSSearchResult(
                chunkId: chunkId,
                patientId: patientId,
                content: String(cString: contentCStr),
                sectionTitle: String(cString: sectionCStr),
                clinicalCategory: String(cString: categoryCStr),
                bm25Score: sqlite3_column_double(stmt, 5)
            ))
        }

        return results
    }

    // MARK: - Delete

    /// Remove all chunks for a patient.
    func deleteByPatient(_ patientId: UUID) {
        ensureInitialized()
        guard let db = database else { return }

        let pidStr = patientId.uuidString

        // Delete from FTS5 — must use rowid lookup since patient_id is UNINDEXED
        let deleteSQL = "DELETE FROM clinical_chunks WHERE rowid IN (SELECT rowid FROM clinical_chunks WHERE patient_id = ?)"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_text(stmt, 1, pidStr, -1, sqliteTransient)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }

        // Delete from meta
        let metaSQL = "DELETE FROM clinical_meta WHERE patient_id = ?"
        var metaStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, metaSQL, -1, &metaStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(metaStmt, 1, pidStr, -1, sqliteTransient)
            sqlite3_step(metaStmt)
            sqlite3_finalize(metaStmt)
        }
    }

    /// Clear all indexed data.
    func clear() {
        ensureInitialized()
        execute("DELETE FROM clinical_chunks")
        execute("DELETE FROM clinical_meta")
        AppLogger.ai.info("🗑️ FTS5 cleared all data")
    }

    // MARK: - Helpers

    @discardableResult
    private func execute(_ sql: String) -> Bool {
        guard let db = database else { return false }
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            AppLogger.ai.error("❌ SQL exec failed: \(msg)")
            sqlite3_free(errMsg)
            return false
        }
        return true
    }
}
