import XCTest
@testable import OpenClinic

final class ClinicalFTSServiceTests: XCTestCase {
    var ftsService: ClinicalFTSService!

    override func setUp() async throws {
        ftsService = ClinicalFTSService()
        await ftsService.clear()
    }

    override func tearDown() async throws {
        await ftsService.clear()
    }

    func testSearchEscapingAndInjection() async {
        let patientId = UUID()
        let chunk = ClinicalChunk(
            patientId: patientId,
            content: "Patient has a history of severe asthma and hypertension. Needs follow up.",
            contextualPrefix: "",
            metadata: ChunkMetadata(
                chunkIndex: 0,
                sourceType: .clinicalRecord,
                sectionTitle: "History",
                dateRecorded: Date(),
                clinicalCategory: .chiefComplaint,
                patientName: "John Doe",
                wordCount: 12
            )
        )

        await ftsService.insertBatch(chunks: [chunk])

        // Normal search
        var results = await ftsService.search(query: "asthma")
        XCTAssertEqual(results.count, 1)

        // Punctuation should be safely ignored and not crash FTS5
        results = await ftsService.search(query: "asthma;")
        XCTAssertEqual(results.count, 1)

        // Malicious-looking keyword: AND
        // Since FTS tokens are quoted, "AND" is treated as the literal word "and".
        results = await ftsService.search(query: "history AND severe")
        XCTAssertEqual(results.count, 1)
        
        // OR keyword injection attempt and wildcards
        results = await ftsService.search(query: "asthma OR NOT hypertension *")
        XCTAssertEqual(results.count, 1)
        
        // Multi-token query
        results = await ftsService.search(query: "severe hypertension")
        XCTAssertEqual(results.count, 1)
        
        // Empty/short token queries
        results = await ftsService.search(query: "")
        XCTAssertEqual(results.count, 0)
        
        results = await ftsService.search(query: "a") // tokens <= 2 chars are ignored
        XCTAssertEqual(results.count, 0)
    }
}
