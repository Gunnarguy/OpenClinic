import XCTest
@testable import OpenClinic

final class ClinicalChunkerTests: XCTestCase {
    func testChunkRecordPatientBasic() {
        let patient = PatientProfile(
            firstName: "Jane",
            lastName: "Doe",
            dateOfBirth: Date(),
            gender: "Female"
        )
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
        record.ccHPI = "Patient reports shortness of breath."
        record.examFindings = "Lungs clear to auscultation bilaterally."
        record.impressionsAndPlan = "Mild intermittent asthma. Albuterol inhaler."

        let chunks = ClinicalChunker.chunkRecord(record, patient: patient)
        XCTAssertFalse(chunks.isEmpty)

        let sectionTitles = chunks.map { $0.metadata.sectionTitle }
        XCTAssertTrue(sectionTitles.contains("Condition"))
        XCTAssertTrue(sectionTitles.contains("Chief Complaint & HPI"))
        XCTAssertTrue(sectionTitles.contains("Examination Findings"))
        XCTAssertTrue(sectionTitles.contains("Assessment & Plan"))

        for chunk in chunks {
            XCTAssertEqual(chunk.patientId, patient.id)
            XCTAssertEqual(chunk.metadata.patientName, "Jane Doe")
            XCTAssertTrue(chunk.metadata.wordCount > 0)
            XCTAssertFalse(chunk.content.isEmpty)
        }
    }
}
