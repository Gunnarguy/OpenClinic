import XCTest
import SwiftData
@testable import OpenClinic

/// Each chart model saves and reads back on its own. A model that cannot be saved fails here
/// by name, instead of deep inside an import.
final class ChartModelPersistenceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    @MainActor
    override func setUp() async throws {
        container = try OpenClinicSchema.makeInMemoryContainer()
        context = ModelContext(container)
    }

    override func tearDown() {
        context = nil
        container = nil
    }

    @MainActor
    func testProblemSaves() throws {
        context.insert(ChartProblem(qualifiedID: "t/problem", display: "Stroke", codeSystem: ChartCodeSystem.snomed, code: "230690007", onsetDate: .now))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChartProblem>()).first?.code, "230690007")
    }

    @MainActor
    func testAllergySaves() throws {
        context.insert(ChartAllergy(qualifiedID: "t/allergy", substance: "Peanut", categories: ["food"], reactions: ["Hives"]))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChartAllergy>()).first?.reactions, ["Hives"])
    }

    @MainActor
    func testObservationSaves() throws {
        let observation = ChartObservation(qualifiedID: "t/observation", category: "vital-signs", display: "Body Weight", code: "29463-7", effectiveDate: .now)
        observation.setValue(.quantity(93.6, unit: "kg"))
        context.insert(observation)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChartObservation>()).first?.displayValue, "93.6 kg")
    }

    @MainActor
    func testEncounterSaves() throws {
        context.insert(ChartEncounter(qualifiedID: "t/encounter", typeDisplay: "Encounter for symptom", encounterClass: "AMB", startDate: .now, endDate: .now))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChartEncounter>()).first?.classDisplay, "Ambulatory")
    }

    @MainActor
    func testProcedureSaves() throws {
        context.insert(ChartProcedure(qualifiedID: "t/procedure", display: "Documentation of current medications", code: "428191000124101", performedStart: .now))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChartProcedure>()).count, 1)
    }

    @MainActor
    func testImmunizationSaves() throws {
        context.insert(ChartImmunization(qualifiedID: "t/immunization", vaccine: "zoster", codeSystem: ChartCodeSystem.cvx, code: "121", occurrenceDate: .now, primarySource: true))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChartImmunization>()).first?.primarySource, true)
    }

    @MainActor
    func testDiagnosticReportSaves() throws {
        context.insert(ChartDiagnosticReport(qualifiedID: "t/report", display: "Lipid Panel", code: "57698-3", category: "LAB", effectiveDate: .now, resultReferences: ["Observation/1", "Observation/2"]))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChartDiagnosticReport>()).first?.resultReferences.count, 2)
    }

    @MainActor
    func testDocumentSaves() throws {
        context.insert(ChartDocument(qualifiedID: "t/document", typeDisplay: "Progress note", documentDate: .now, text: "Synthetic text."))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChartDocument>()).first?.text, "Synthetic text.")
    }

    @MainActor
    func testSourceResourceAndAuditEventSave() throws {
        context.insert(FHIRResourceRecord(qualifiedID: "t/Condition/1", serverBase: "t", resourceType: "Condition", resourceID: "1", versionID: "4", patientResourceID: "p", json: Data("{}".utf8)))
        context.insert(AuditEvent(action: .recordImported, entityType: "FHIRImport", entityID: "t/Patient/p", detail: "1 resource"))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<FHIRResourceRecord>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AuditEvent>()).first?.action, AuditAction.recordImported.rawValue)
    }

    @MainActor
    func testMedicationAndAppointmentSaveWithTheRemovedFlag() throws {
        let medication = LocalMedication(rxID: "t/rx", medicationName: "Clopidogrel 75 MG Oral Tablet", writtenBy: "Not recorded at source", writtenDate: .now, quantityInfo: "Not recorded at source", refills: 0)
        medication.isRemovedAtSource = true
        context.insert(medication)
        context.insert(Appointment(appointmentID: "t/appt", scheduledTime: .now, reasonForVisit: "Appointment", status: "Scheduled"))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<LocalMedication>()).first?.isRemovedAtSource, true)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Appointment>()).first?.isRemovedAtSource, false)
    }
}
