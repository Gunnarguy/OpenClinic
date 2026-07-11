import XCTest
@testable import OpenClinic

final class ClinicalChunkerTests: XCTestCase {
    func testChunkRecordPatientBasic() {
        let patientId = UUID()
        let record = LocalClinicalRecord(
            recordID: "rec1",
            dateRecorded: Date(),
            conditionName: "Asthma",
            status: "Final",
            documentationStatus: "Signed",
            documentationSignedAt: Date(),
            sourceKind: "Manual",
            sourceSystemName: "Manual",
            sourceRecordIdentifier: "rec1",
            sourceOfTruth: true
        )
        record.clinicalNotes = """
        # Subjective
        Patient reports shortness of breath.
        # Objective
        Lungs clear to auscultation bilaterally.
        # Assessment
        Mild intermittent asthma.
        # Plan
        Albuterol inhaler.
        """

        let chunks = ClinicalChunker.chunkRecord(record, patientId: patientId, patientName: "Jane Doe")
        XCTAssertFalse(chunks.isEmpty)

        let sectionTitles = chunks.map { $0.metadata.sectionTitle }
        XCTAssertTrue(sectionTitles.contains("Subjective"))
        XCTAssertTrue(sectionTitles.contains("Objective"))
        XCTAssertTrue(sectionTitles.contains("Assessment"))
        XCTAssertTrue(sectionTitles.contains("Plan"))

        for chunk in chunks {
            XCTAssertEqual(chunk.patientId, patientId)
            XCTAssertEqual(chunk.metadata.patientName, "Jane Doe")
            XCTAssertTrue(chunk.wordCount > 0)
            XCTAssertFalse(chunk.content.isEmpty)
        }
    }
}
