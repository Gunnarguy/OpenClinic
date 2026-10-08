import XCTest
import SwiftData
@testable import OpenClinic

/// The path from a FHIR server's responses to chart rows, end to end: the captured
/// sandbox fixtures go through the mapper and the importer into an in-memory store.
final class ChartImportApplierTests: XCTestCase {
    private let serverBase = "https://r4.smarthealthit.org"
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

    // MARK: - Fixtures

    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"), "Missing fixture \(name).json")
        return try Data(contentsOf: url)
    }

    private func resources(_ names: String...) throws -> [FHIRR4RawResource] {
        try names.flatMap { try FHIRR4Bundle(data: fixtureData($0)).resources }
    }

    private func schroederPatient() throws -> FHIRR4RawResource {
        try FHIRR4RawResource(data: fixtureData("Patient.schroeder"))
    }

    private func schroederResources() throws -> [FHIRR4RawResource] {
        try resources(
            "Condition.schroeder", "MedicationRequest.schroeder", "Encounter.schroeder", "Procedure.schroeder",
            "Immunization.schroeder", "DiagnosticReport.schroeder", "Observation.schroeder.page1", "Observation.schroeder.page2"
        )
    }

    private func schroederChart(_ resources: [FHIRR4RawResource]? = nil) throws -> (chart: ImportedChart, sources: [FHIRR4RawResource]) {
        let patient = try schroederPatient()
        let rest = try resources ?? schroederResources()
        let chart = try FHIRR4ChartMapper.chart(patient: patient, resources: rest, serverBase: serverBase)
        return (chart, [patient] + rest)
    }

    @MainActor
    private func importedPatient() throws -> PatientProfile {
        let patients = try context.fetch(FetchDescriptor<PatientProfile>())
        return try XCTUnwrap(patients.first { $0.sourceKind == ClinicalSourceKind.smartFHIR.rawValue })
    }

    // MARK: - First import

    @MainActor
    func testImportBuildsTheWholeChart() throws {
        let (chart, sources) = try schroederChart()
        let summary = try ChartImportApplier(context: context).apply(chart, sourceResources: sources)

        let patient = try importedPatient()
        XCTAssertEqual(patient.fullName, "Elisha Schroeder")
        XCTAssertEqual(patient.gender, "Male")
        XCTAssertEqual(patient.sourceSystemName, serverBase)
        XCTAssertEqual(patient.sourceRecordIdentifier, "b8c71d92-a06b-4044-b053-64664e82f851")
        XCTAssertTrue(patient.sourceOfTruth)
        XCTAssertNotNil(patient.deceasedDate)
        XCTAssertEqual(patient.city, "Easton")

        XCTAssertEqual(patient.problems?.count, 5)
        XCTAssertEqual(patient.medications?.count, 3)
        XCTAssertEqual(patient.observations?.count, 79)
        XCTAssertEqual(patient.encounters?.count, 11)
        XCTAssertEqual(patient.procedures?.count, 6)
        XCTAssertEqual(patient.immunizations?.count, 11)
        XCTAssertEqual(patient.diagnosticReports?.count, 6)

        XCTAssertTrue(summary.createdNewPatient)
        XCTAssertEqual(summary.totalReceived, 121)
        XCTAssertEqual(summary.sourceResourceCount, 122, "121 resources and the Patient")
        XCTAssertEqual(summary.lines.first { $0.label == "Observations" }?.created, 79)

        XCTAssertEqual(try context.fetch(FetchDescriptor<FHIRResourceRecord>()).count, 122)
        let audit = try context.fetch(FetchDescriptor<AuditEvent>())
        XCTAssertEqual(audit.map(\.action), [AuditAction.recordImported.rawValue])
        XCTAssertEqual(audit.first?.patientID, patient.id)
    }

    @MainActor
    func testClinicalValuesSurviveTheTrip() throws {
        let (chart, sources) = try schroederChart()
        try ChartImportApplier(context: context).apply(chart, sourceResources: sources)
        let patient = try importedPatient()

        let stroke = try XCTUnwrap(patient.problems?.first { $0.display == "Stroke" })
        XCTAssertTrue(stroke.isActive)
        XCTAssertEqual(stroke.codeSystem, ChartCodeSystem.snomed)
        XCTAssertNil(stroke.icd10Code, "A SNOMED code is not an ICD-10 code")
        XCTAssertEqual(patient.problems?.filter { !$0.isActive }.count, 3)

        let clopidogrel = try XCTUnwrap(patient.medications?.first { $0.medicationName == "Clopidogrel 75 MG Oral Tablet" })
        XCTAssertEqual(clopidogrel.status, "Stopped")
        XCTAssertEqual(clopidogrel.writtenBy, "Not recorded at source", "The server gave a bare Practitioner reference. No name is invented.")

        let series = VitalSigns.series(from: patient.observations ?? [])
        let bloodPressure = try XCTUnwrap(series.first { $0.id == "bp" })
        XCTAssertEqual(bloodPressure.readings.count, 7)
        XCTAssertEqual(bloodPressure.latest?.displayValue, "118/81 mmHg")
        XCTAssertEqual(series.first { $0.id == "weight" }?.latest?.displayValue, "93.6 kg")

        // The latest smoking status is "Never smoker", and no allergy resource exists.
        XCTAssertFalse(patient.isSmoker)
        XCTAssertEqual(patient.allergies, [], "Nothing recorded is not the same as no known allergies")
    }

    @MainActor
    func testEveryImportedRowKeepsItsSourceResource() throws {
        let (chart, sources) = try schroederChart()
        try ChartImportApplier(context: context).apply(chart, sourceResources: sources)
        let patient = try importedPatient()

        let records = try context.fetch(FetchDescriptor<FHIRResourceRecord>())
        let stored = Set(records.map(\.qualifiedID))
        for problem in patient.problems ?? [] {
            XCTAssertTrue(stored.contains(problem.qualifiedID), problem.qualifiedID)
        }
        for observation in patient.observations ?? [] {
            XCTAssertTrue(stored.contains(observation.qualifiedID), observation.qualifiedID)
        }

        let stroke = try XCTUnwrap(patient.problems?.first { $0.display == "Stroke" })
        let source = try XCTUnwrap(records.first { $0.qualifiedID == stroke.qualifiedID })
        XCTAssertEqual(source.resourceType, "Condition")
        XCTAssertTrue(source.prettyPrintedJSON.contains("\"resourceType\" : \"Condition\""))
    }

    // MARK: - Later imports

    @MainActor
    func testImportingAgainChangesNothing() throws {
        let (chart, sources) = try schroederChart()
        let applier = ChartImportApplier(context: context)
        try applier.apply(chart, sourceResources: sources)
        let second = try applier.apply(chart, sourceResources: sources)

        XCTAssertFalse(second.createdNewPatient)
        XCTAssertEqual(second.lines.reduce(0) { $0 + $1.created }, 0)
        XCTAssertEqual(second.lines.reduce(0) { $0 + $1.updated }, 121)
        XCTAssertEqual(second.lines.reduce(0) { $0 + $1.removedAtSource }, 0)

        XCTAssertEqual(try context.fetch(FetchDescriptor<PatientProfile>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChartObservation>()).count, 79)
        XCTAssertEqual(try context.fetch(FetchDescriptor<FHIRResourceRecord>()).count, 122)
    }

    @MainActor
    func testARowTheServerStopsReturningIsKeptAndMarked() throws {
        let all = try schroederResources()
        let applier = ChartImportApplier(context: context)
        let first = try schroederChart(all)
        try applier.apply(first.chart, sourceResources: first.sources)

        let withoutStroke = all.filter { !($0.resourceType == "Condition" && $0.id.hasPrefix("98a60f67")) }
        XCTAssertEqual(withoutStroke.count, all.count - 1)
        let second = try schroederChart(withoutStroke)
        let summary = try applier.apply(second.chart, sourceResources: second.sources)

        let patient = try importedPatient()
        XCTAssertEqual(patient.problems?.count, 5, "Nothing is deleted")
        let stroke = try XCTUnwrap(patient.problems?.first { $0.display == "Stroke" })
        XCTAssertTrue(stroke.isRemovedAtSource)
        XCTAssertEqual(summary.lines.first { $0.label == "Problems" }?.removedAtSource, 1)

        let source = try XCTUnwrap(try context.fetch(FetchDescriptor<FHIRResourceRecord>()).first { $0.qualifiedID == stroke.qualifiedID })
        XCTAssertTrue(source.isRemovedAtSource)

        // If the server returns it again, the mark comes off.
        try applier.apply(first.chart, sourceResources: first.sources)
        XCTAssertFalse(stroke.isRemovedAtSource)
    }

    /// A search that failed returns no rows. That must never read as "the patient has none".
    @MainActor
    func testAFailedOrTruncatedSearchMarksNothingAsRemoved() throws {
        let applier = ChartImportApplier(context: context)
        let first = try schroederChart()
        try applier.apply(first.chart, sourceResources: first.sources)

        var failed = first.chart
        failed.observations = []
        failed.failedTypes = ["Observation"]
        failed.problems = Array(failed.problems.prefix(2))
        failed.truncatedTypes = ["Condition"]
        let sourcesWithoutObservations = first.sources.filter { $0.resourceType != "Observation" }
        let summary = try applier.apply(failed, sourceResources: sourcesWithoutObservations)

        let patient = try importedPatient()
        XCTAssertEqual(patient.observations?.filter(\.isRemovedAtSource).count, 0)
        XCTAssertEqual(patient.problems?.filter(\.isRemovedAtSource).count, 0)
        XCTAssertEqual(summary.lines.reduce(0) { $0 + $1.removedAtSource }, 0)

        let records = try context.fetch(FetchDescriptor<FHIRResourceRecord>())
        XCTAssertEqual(records.filter(\.isRemovedAtSource).count, 0)
    }

    /// A resource the app cannot decode is still on the server. Its row stays as it was.
    @MainActor
    func testAResourceThatCouldNotBeDecodedMarksNothingAsRemoved() throws {
        let applier = ChartImportApplier(context: context)
        let first = try schroederChart()
        try applier.apply(first.chart, sourceResources: first.sources)

        var second = first.chart
        second.problems = Array(second.problems.dropLast())
        second.unreadableTypes = ["Condition"]
        let summary = try applier.apply(second, sourceResources: first.sources)

        let patient = try importedPatient()
        XCTAssertEqual(patient.problems?.count, first.chart.problems.count)
        XCTAssertEqual(patient.problems?.filter(\.isRemovedAtSource).count, 0)
        XCTAssertEqual(summary.lines.reduce(0) { $0 + $1.removedAtSource }, 0)
    }

    // MARK: - Safety

    /// The sandbox patient "Rice" has an allergy marked entered-in-error. It must not reach the chart.
    @MainActor
    func testAnAllergyEnteredInErrorNeverReachesTheChart() throws {
        let allergies = try resources("AllergyIntolerance.rice")
        XCTAssertEqual(allergies.count, 3)
        let (chart, sources) = try schroederChart(allergies)
        try ChartImportApplier(context: context).apply(chart, sourceResources: sources)

        let patient = try importedPatient()
        XCTAssertEqual(Set((patient.chartAllergies ?? []).map(\.substance)), ["Peanut", "Shellfish"])
        XCTAssertEqual(patient.allergies, ["Peanut", "Shellfish"])
        XCTAssertFalse(chart.warnings.isEmpty, "Leaving a resource out is reported")
    }

    /// Imported appointments keep the server's time. The old importer moved them to today.
    @MainActor
    func testAppointmentsKeepTheServersTime() throws {
        let appointments = try resources("Appointment.rice")
        let (chart, sources) = try schroederChart(appointments)
        let summary = try ChartImportApplier(context: context).apply(chart, sourceResources: sources)

        let patient = try importedPatient()
        let booked = try XCTUnwrap((patient.appointments ?? []).first { $0.appointmentID.hasSuffix("/Appointment/4723149") })
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let parts = utc.dateComponents([.year, .month, .day, .hour, .minute], from: booked.scheduledTime)
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute], [2026, 6, 29, 5, 15])
        XCTAssertEqual(booked.status, "Scheduled")
        XCTAssertEqual(booked.durationMinutes, 15)

        // One sandbox appointment has a start time with no zone. It is imported and reported, not guessed.
        XCTAssertEqual(patient.appointments?.count, 4)
        XCTAssertTrue(summary.warnings.contains { $0.contains("no start time") }, "\(summary.warnings)")
    }

    @MainActor
    func testTwoLocalChartsForOnePatientStopTheImport() throws {
        let (chart, sources) = try schroederChart()
        for _ in 0..<2 {
            context.insert(PatientProfile(
                firstName: "Elisha", lastName: "Schroeder", dateOfBirth: .now, gender: "Male",
                sourceKind: ClinicalSourceKind.smartFHIR.rawValue,
                sourceSystemName: serverBase,
                sourceRecordIdentifier: chart.patient.source.resourceID
            ))
        }
        try context.save()

        XCTAssertThrowsError(try ChartImportApplier(context: context).apply(chart, sourceResources: sources)) { error in
            guard case ChartImportError.ambiguousPatient = error else { return XCTFail("Unexpected error \(error)") }
        }
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChartProblem>()).count, 0, "Nothing is written when the import stops")
        XCTAssertEqual(try context.fetch(FetchDescriptor<FHIRResourceRecord>()).count, 0)
    }

    @MainActor
    func testAnImportNeverTouchesTheDemoPanel() throws {
        let suiteName = "ChartImportApplierTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try DemoDataSeeder.prepare(context: context, now: .now, calendar: .current, defaults: defaults, photoDirectory: nil)
        let demoProblems = try context.fetch(FetchDescriptor<ChartProblem>()).count

        let (chart, sources) = try schroederChart()
        try ChartImportApplier(context: context).apply(chart, sourceResources: sources)

        XCTAssertEqual(try context.fetch(FetchDescriptor<PatientProfile>()).count, 11)
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChartProblem>()).count, demoProblems + 5)
        let demoRows = try context.fetch(FetchDescriptor<ChartProblem>()).filter { $0.sourceKind == ClinicalSourceKind.demoLocalCache.rawValue }
        XCTAssertEqual(demoRows.filter(\.isRemovedAtSource).count, 0)
    }

    // MARK: - Downstream

    /// An imported record answers panel questions and is indexed for retrieval like any other chart.
    @MainActor
    func testAnImportedRecordIsSearchable() throws {
        let (chart, sources) = try schroederChart()
        try ChartImportApplier(context: context).apply(chart, sourceResources: sources)
        let patient = try importedPatient()

        let snapshot = PanelSnapshot(patients: [patient])
        let parser = CohortQueryParser(vocabulary: PanelVocabulary(snapshot: snapshot))
        let query = try XCTUnwrap(parser.parse("Which patients have a stroke?"))
        let result = CohortEngine.run(query, on: snapshot)
        XCTAssertEqual(result.matches.map(\.name), ["Elisha Schroeder"])
        let citation = try XCTUnwrap(result.matches.first?.evidence.first?.sourceID)
        XCTAssertTrue(citation.hasPrefix("Condition/98a60f67"), "An imported problem is cited by its resource reference, got \(citation)")

        let chunks = ClinicalChunker.chunkAllData(for: patient)
        let text = chunks.map(\.content).joined(separator: "\n")
        XCTAssertTrue(text.contains("Problem list:"), "Problems are indexed")
        XCTAssertTrue(text.contains("Stroke: active"))
        XCTAssertTrue(text.contains("Blood Pressure: 118/81 mmHg"))
        XCTAssertTrue(text.contains("Tobacco smoking status NHIS: Never smoker"))
        XCTAssertTrue(chunks.contains { $0.metadata.clinicalCategory == .laboratory })
        XCTAssertTrue(chunks.allSatisfy { $0.patientId == patient.id })
    }
}
