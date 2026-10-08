import XCTest
@testable import OpenClinic

/// The vector store's file on disk. The launch load and the launch reindex run at the same time,
/// and the load must never bring back vectors the reindex has already replaced.
final class ClinicalVectorStoreTests: XCTestCase {
    private var fileURL: URL!

    override func setUp() {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClinicalVectorStoreTests-\(UUID().uuidString).bin")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func chunk(_ text: String, patient: UUID) -> ClinicalChunk {
        ClinicalChunk(
            patientId: patient,
            content: text,
            contextualPrefix: "",
            metadata: ChunkMetadata(
                chunkIndex: 0,
                sourceType: .clinicalRecord,
                sectionTitle: "History",
                dateRecorded: Date(timeIntervalSince1970: 1_780_000_000),
                clinicalCategory: .chiefComplaint,
                patientName: "Test Patient",
                wordCount: 2
            )
        )
    }

    private func savedStore(patient: UUID) async -> ClinicalVectorStore {
        let store = ClinicalVectorStore(persistenceURL: fileURL)
        await store.insertBatch(
            chunks: [chunk("plaque psoriasis", patient: patient), chunk("methotrexate weekly", patient: patient)],
            embeddings: [[1, 0, 0], [0, 1, 0]]
        )
        await store.saveToDisk()
        return store
    }

    func testAFreshStoreLoadsWhatWasSaved() async {
        let patient = UUID()
        _ = await savedStore(patient: patient)

        let reopened = ClinicalVectorStore(persistenceURL: fileURL)
        await reopened.loadFromDisk()

        let count = await reopened.count
        XCTAssertEqual(count, 2)
        let hits = await reopened.search(queryEmbedding: [1, 0, 0], topK: 1, patientScope: patient)
        XCTAssertEqual(hits.first?.chunk.content, "plaque psoriasis")
    }

    /// What happened at launch on 2026-10-07: the reindex cleared the store and began inserting, the
    /// load from disk finished 2.6 s later, and the saved index held every chunk twice.
    func testALoadThatLandsAfterAReindexHasStartedAddsNothing() async {
        let patient = UUID()
        _ = await savedStore(patient: patient)

        let reopened = ClinicalVectorStore(persistenceURL: fileURL)
        await reopened.clear()
        await reopened.insertBatch(
            chunks: [chunk("plaque psoriasis", patient: patient), chunk("methotrexate weekly", patient: patient)],
            embeddings: [[1, 0, 0], [0, 1, 0]]
        )
        await reopened.loadFromDisk()

        let count = await reopened.count
        XCTAssertEqual(count, 2, "The stale copy on disk must not be merged into a rebuilt index")
    }

    func testALoadAfterAClearLeavesTheStoreEmpty() async {
        _ = await savedStore(patient: UUID())

        let reopened = ClinicalVectorStore(persistenceURL: fileURL)
        await reopened.clear()
        await reopened.loadFromDisk()

        let count = await reopened.count
        XCTAssertEqual(count, 0)
    }

    func testReplacingOnePatientsChunksLeavesTheOthers() async {
        let first = UUID()
        let second = UUID()
        let store = ClinicalVectorStore(persistenceURL: fileURL)
        await store.insertBatch(
            chunks: [chunk("old first note", patient: first), chunk("second patient note", patient: second)],
            embeddings: [[1, 0, 0], [0, 1, 0]]
        )

        await store.replace(
            patientId: first,
            chunks: [chunk("new first note", patient: first), chunk("another first note", patient: first)],
            embeddings: [[0, 0, 1], [1, 1, 0]]
        )

        let firstEntries = await store.entries(for: first)
        XCTAssertEqual(Set(firstEntries.map(\.chunk.content)), ["new first note", "another first note"])
        XCTAssertEqual(firstEntries.first { $0.chunk.content == "new first note" }?.embedding, [0, 0, 1])
        let secondEntries = await store.entries(for: second)
        XCTAssertEqual(secondEntries.map(\.chunk.content), ["second patient note"])
        let patients = await store.patientIDs
        XCTAssertEqual(patients, [first, second])
        let all = await store.allChunks
        XCTAssertEqual(all.count, 3)
    }

    func testDeletingOnePatientLeavesTheOthers() async {
        let first = UUID()
        let second = UUID()
        let store = ClinicalVectorStore(persistenceURL: fileURL)
        await store.insertBatch(
            chunks: [chunk("first patient note", patient: first), chunk("second patient note", patient: second)],
            embeddings: [[1, 0, 0], [0, 1, 0]]
        )

        await store.deleteByPatient(first)

        let count = await store.count
        XCTAssertEqual(count, 1)
        let hits = await store.search(queryEmbedding: [0, 1, 0], topK: 5)
        XCTAssertEqual(hits.map(\.chunk.content), ["second patient note"])
    }
}
