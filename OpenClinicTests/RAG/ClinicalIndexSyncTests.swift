import XCTest
@testable import OpenClinic

/// What the launch sync decides for one patient. Embedding is the slow step, so the plan has to
/// leave an unchanged chart alone and embed only the text that is new.
final class ClinicalIndexSyncTests: XCTestCase {
    private let patient = UUID()

    private func chunk(_ text: String, index: Int = 0, section: String = "History", date: Date? = nil) -> ClinicalChunk {
        ClinicalChunk(
            patientId: patient,
            content: text,
            contextualPrefix: "",
            metadata: ChunkMetadata(
                chunkIndex: index,
                sourceType: .clinicalRecord,
                sectionTitle: section,
                dateRecorded: date,
                clinicalCategory: .chiefComplaint,
                patientName: "Test Patient",
                wordCount: text.split(separator: " ").count
            )
        )
    }

    private func stored(_ chunk: ClinicalChunk, _ embedding: [Float]) -> ClinicalIndexSync.StoredChunk {
        ClinicalIndexSync.StoredChunk(chunk: chunk, embedding: embedding)
    }

    func testTheSameChartChunkedAgainIsUnchanged() {
        // A second chunking gives every chunk a new identifier and may give them in another order.
        let indexed = [stored(chunk("plaque psoriasis", index: 0), [1, 0, 0]), stored(chunk("methotrexate weekly", index: 1), [0, 1, 0])]
        let again = [chunk("methotrexate weekly", index: 1), chunk("plaque psoriasis", index: 0)]

        XCTAssertEqual(ClinicalIndexSync.plan(chunks: again, stored: indexed, dimension: 3), .unchanged)
    }

    func testOnlyTheNewTextIsEmbedded() {
        let indexed = [stored(chunk("plaque psoriasis", index: 0), [1, 0, 0]), stored(chunk("methotrexate weekly", index: 1), [0, 1, 0])]
        let edited = [chunk("plaque psoriasis", index: 0), chunk("methotrexate weekly", index: 1), chunk("folic acid daily", index: 2)]

        let plan = ClinicalIndexSync.plan(chunks: edited, stored: indexed, dimension: 3)

        XCTAssertEqual(plan, .replace(reused: [[1, 0, 0], [0, 1, 0], nil]))
        XCTAssertEqual(plan.embedCount, 1)
    }

    func testAChunkThatOnlyMovedKeepsItsVector() {
        // A new first chunk shifts every index after it. The text of the others was embedded before.
        let indexed = [stored(chunk("methotrexate weekly", index: 0), [0, 1, 0])]
        let edited = [chunk("new allergy: penicillin", index: 0), chunk("methotrexate weekly", index: 1)]

        let plan = ClinicalIndexSync.plan(chunks: edited, stored: indexed, dimension: 3)

        XCTAssertEqual(plan, .replace(reused: [nil, [0, 1, 0]]))
    }

    func testAChangeOfDateWithTheSameTextNeedsNoEmbedding() {
        let before = Date(timeIntervalSince1970: 1_780_000_000)
        let indexed = [stored(chunk("follow-up visit", date: before), [1, 1, 0])]
        let redated = [chunk("follow-up visit", date: before.addingTimeInterval(86_400))]

        let plan = ClinicalIndexSync.plan(chunks: redated, stored: indexed, dimension: 3)

        XCTAssertEqual(plan, .replace(reused: [[1, 1, 0]]), "the stored chunk is replaced so its date is right, and its vector is kept")
        XCTAssertEqual(plan.embedCount, 0)
    }

    func testVectorsFromAnotherEmbeddingProviderAreNotReused() {
        // Stored at 512 dimensions; the provider in use gives 3.
        let indexed = [stored(chunk("plaque psoriasis"), [Float](repeating: 0.1, count: 512))]

        let plan = ClinicalIndexSync.plan(chunks: [chunk("plaque psoriasis")], stored: indexed, dimension: 3)

        XCTAssertEqual(plan, .replace(reused: [nil]))
    }

    func testAnEmptyChartClearsWhatWasIndexed() {
        let indexed = [stored(chunk("plaque psoriasis"), [1, 0, 0])]
        XCTAssertEqual(ClinicalIndexSync.plan(chunks: [], stored: indexed, dimension: 3), .replace(reused: []))
        XCTAssertEqual(ClinicalIndexSync.plan(chunks: [], stored: [], dimension: 3), .unchanged)
    }
}
