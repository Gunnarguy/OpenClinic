import XCTest
import SwiftData
@testable import OpenClinic

/// The demo panel's structured rows: coded problems, allergies, vital signs and
/// laboratory results. Every value a chart view shows for a demo patient comes
/// from one of these rows, and these tests hold the rows to the fixture.
final class DemoChartRowsTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let calendar = Calendar.current

    @MainActor
    override func setUp() async throws {
        container = try OpenClinicSchema.makeInMemoryContainer()
        context = ModelContext(container)
        suiteName = "DemoChartRowsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        context = nil
        container = nil
    }

    @MainActor
    private func seed(now: Date = .now) throws {
        try DemoDataSeeder.prepare(context: context, now: now, calendar: calendar, defaults: defaults, photoDirectory: nil)
    }

    @MainActor
    private func patient(_ mrn: String) throws -> PatientProfile {
        let all = try context.fetch(FetchDescriptor<PatientProfile>())
        return try XCTUnwrap(all.first { $0.medicalRecordNumber == mrn }, "No patient \(mrn)")
    }

    // MARK: - Fixture

    func testProblemsAreCodedAndDatedSensibly() throws {
        let panel = try DemoDataSeeder.loadPanel()
        let icd10 = try NSRegularExpression(pattern: #"^[A-Z][0-9]{2}(\.[0-9A-Z]{1,4})?$"#)
        var ids = Set<String>()

        for patient in panel.patients {
            for problem in patient.problems {
                XCTAssertTrue(ids.insert(problem.problemID).inserted, "Duplicate \(problem.problemID)")
                let range = NSRange(problem.icd10Code.startIndex..., in: problem.icd10Code)
                XCTAssertNotNil(icd10.firstMatch(in: problem.icd10Code, range: range), "\(problem.problemID) code \(problem.icd10Code)")
                XCTAssertTrue(["active", "resolved"].contains(problem.clinicalStatus), problem.problemID)
                XCTAssertEqual(problem.clinicalStatus == "resolved", problem.abatementDaysAgo != nil, "\(problem.problemID): a resolved problem needs a resolution date and an active one must not have one")
            }
        }
    }

    /// Vital signs exist for today only where the patient has been roomed. A patient still in the
    /// waiting room has not had them taken.
    func testTodaysVitalsExistOnlyForRoomedVisits() throws {
        let panel = try DemoDataSeeder.loadPanel()
        let roomedStatuses: Set<String> = ["Roomed", "In Exam", "Ready for Checkout", "Completed"]

        for patient in panel.patients {
            let today = try XCTUnwrap(patient.appointments.first(where: \.isToday), "\(patient.mrn) has no visit today")
            let hasTodaysVitals = patient.vitals.contains { $0.appointmentID == today.appointmentID }
            XCTAssertEqual(hasTodaysVitals, roomedStatuses.contains(today.status), "\(patient.mrn) is \(today.status)")
        }
    }

    func testVitalSignsArePhysiologicallyPlausible() throws {
        let panel = try DemoDataSeeder.loadPanel()
        for set in panel.patients.flatMap(\.vitals) {
            if let systolic = set.systolic, let diastolic = set.diastolic {
                XCTAssertTrue((90...160).contains(systolic) && (50...100).contains(diastolic) && systolic > diastolic, set.vitalsID)
            }
            if let heartRate = set.heartRate { XCTAssertTrue((50...110).contains(heartRate), set.vitalsID) }
            if let temperature = set.temperatureF { XCTAssertTrue((97.0...99.5).contains(temperature), set.vitalsID) }
            if let saturation = set.oxygenSaturation { XCTAssertTrue((94...100).contains(saturation), set.vitalsID) }
            if let pain = set.painScore { XCTAssertTrue((0...10).contains(pain), set.vitalsID) }
        }
    }

    /// The inbox says Catherine Hartley's LDL fell 22% on simvastatin. The results must say the same.
    func testLipidResultsAgreeWithTheInboxMessage() throws {
        let panel = try DemoDataSeeder.loadPanel()
        let catherine = try XCTUnwrap(panel.patients.first { $0.mrn == "OC-1001" })
        let ldl = catherine.labs.filter { $0.loinc == "18262-6" }.sorted { $0.daysAgo > $1.daysAgo }
        let before = try XCTUnwrap(ldl.first?.value)
        let after = try XCTUnwrap(ldl.last?.value)
        XCTAssertEqual(ldl.count, 2)

        let percentDrop = ((before - after) / before * 100).rounded()
        XCTAssertEqual(percentDrop, 22)
        XCTAssertTrue(panel.messages.contains { $0.preview.contains("22%") && $0.subject.contains("Catherine Hartley") })

        let simvastatin = try XCTUnwrap(catherine.medications.first { $0.genericName == "Simvastatin" })
        XCTAssertGreaterThan(try XCTUnwrap(ldl.first?.daysAgo), simvastatin.writtenDaysAgo, "The baseline panel predates the statin")
    }

    // MARK: - Seeding

    @MainActor
    func testSeedingCreatesOneRowPerFixtureFact() throws {
        try seed()
        let panel = try DemoDataSeeder.loadPanel()

        let problems = try context.fetch(FetchDescriptor<ChartProblem>())
        let allergies = try context.fetch(FetchDescriptor<ChartAllergy>())
        let observations = try context.fetch(FetchDescriptor<ChartObservation>())

        XCTAssertEqual(problems.count, panel.patients.reduce(0) { $0 + $1.problems.count })
        XCTAssertEqual(allergies.count, panel.patients.reduce(0) { $0 + $1.allergies.count })

        let labCount = panel.patients.reduce(0) { $0 + $1.labs.count }
        XCTAssertEqual(observations.filter { $0.category == "laboratory" }.count, labCount)

        let expectedVitals = panel.patients.flatMap(\.vitals).reduce(0) { total, set in
            total + [set.systolic != nil, set.heartRate != nil, set.temperatureF != nil, set.oxygenSaturation != nil,
                     set.weightKg != nil, set.heightCm != nil, set.painScore != nil].filter { $0 }.count
        }
        XCTAssertEqual(observations.filter { $0.category == "vital-signs" }.count, expectedVitals)

        for row in problems { XCTAssertNotNil(row.patient, row.qualifiedID) }
        for row in observations { XCTAssertNotNil(row.patient, row.qualifiedID) }
    }

    @MainActor
    func testPreparingAgainDoesNotDuplicateChartRows() throws {
        try seed()
        let before = try context.fetch(FetchDescriptor<ChartObservation>()).count
        try seed()
        try seed()
        XCTAssertEqual(try context.fetch(FetchDescriptor<ChartObservation>()).count, before)
    }

    @MainActor
    func testTodaysBloodPressureReadsAsTakenAtTheVisit() throws {
        try seed()
        let catherine = try patient("OC-1001")
        let series = VitalSigns.series(from: catherine.observations ?? [])
        let bloodPressure = try XCTUnwrap(series.first { $0.id == "bp" })

        XCTAssertEqual(bloodPressure.readings.count, 3)
        XCTAssertEqual(bloodPressure.latest?.displayValue, "128/78 mmHg")

        let visit = try XCTUnwrap((catherine.appointments ?? []).first { $0.appointmentID == "APT-001" })
        XCTAssertEqual(bloodPressure.latest?.effectiveDate, visit.scheduledTime)
        XCTAssertEqual(bloodPressure.numericPoints.map(\.value), [132, 126, 128], "Systolic values in time order")
    }

    @MainActor
    func testFlowsheetShowsNothingForAPatientWithNoVitals() throws {
        try seed()
        let helen = try patient("OC-2005")
        XCTAssertTrue(VitalSigns.series(from: helen.observations ?? []).isEmpty)
    }

    @MainActor
    func testNoKnownAllergiesIsAChartedNegativeNotAnAllergy() throws {
        try seed()
        let maria = try patient("OC-1002")
        let rows = maria.chartAllergies ?? []
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].isNoKnownAllergyAssertion)
        XCTAssertFalse(rows[0].isCurrent)

        let robert = try patient("OC-1003")
        XCTAssertEqual((robert.chartAllergies ?? []).filter(\.isCurrent).map(\.substance), ["Penicillin"])
    }

    @MainActor
    func testResultsCarryTheirReferenceRangeAndFlag() throws {
        try seed()
        let catherine = try patient("OC-1001")
        let ldl = (catherine.observations ?? [])
            .filter { $0.code == "18262-6" }
            .sorted { ($0.effectiveDate ?? .distantPast) < ($1.effectiveDate ?? .distantPast) }
        XCTAssertEqual(ldl.map(\.displayValue), ["142 mg/dL", "111 mg/dL"])
        XCTAssertEqual(ldl.map(\.interpretation), ["H", "N"])
        XCTAssertEqual(ldl.first?.referenceRange, "under 130 mg/dL")

        let thomas = try patient("OC-2001")
        let screening = try XCTUnwrap((thomas.observations ?? []).first { $0.category == "laboratory" })
        XCTAssertEqual(screening.displayValue, "Negative")
    }

    /// The problem list feeds panel questions, so a coded problem counts as a diagnosis.
    @MainActor
    func testProblemListEntriesCountAsDiagnosesInPanelQuestions() throws {
        try seed()
        let snapshot = PanelSnapshot(patients: try context.fetch(FetchDescriptor<PatientProfile>()))
        let parser = CohortQueryParser(vocabulary: PanelVocabulary(snapshot: snapshot))

        let helen = try XCTUnwrap(snapshot.patients.first { $0.mrn == "OC-2005" })
        XCTAssertEqual(helen.diagnoses.map(\.name), ["Hypothyroidism"])
        XCTAssertEqual(helen.diagnoses.first?.isNote, false)

        // A diagnosis the lexicon has no concept for is found by the name the charts give it.
        func matched(_ question: String) throws -> Set<String> {
            let query = try XCTUnwrap(parser.parse(question), "Not parsed: \(question)")
            return CohortEngine.run(query, on: snapshot).matchedMRNs
        }
        XCTAssertEqual(try matched("Who has hypothyroidism?"), ["OC-2005"])
        XCTAssertEqual(try matched("Which patients have hypertension?"), ["OC-2002"])
        XCTAssertEqual(try matched("Who has atrial fibrillation?"), ["OC-2003"])
        XCTAssertEqual(try matched("Who has asthma or hypertension?"), ["OC-1004", "OC-2002"])

        // A problem-list entry is not a note, so it never shows as awaiting a signature.
        XCTAssertEqual(try matched("Which notes are unsigned?"), ["OC-1001", "OC-1004", "OC-1005"])

        // A diagnosis nobody has is still refused, not answered with an empty list by accident.
        XCTAssertNil(parser.parse("Who has sarcoidosis?"))
    }

    func testObservationFormatting() {
        XCTAssertEqual(ObservationFormatting.format(86.50760936483023), "86.5")
        XCTAssertEqual(ObservationFormatting.format(133.0), "133")
        XCTAssertEqual(ObservationFormatting.format(0.9), "0.9")
        XCTAssertEqual(ObservationFormatting.format(6.25), "6.25")
        XCTAssertEqual(ObservationFormatting.displayUnit("mm[Hg]"), "mmHg")
        XCTAssertEqual(ObservationFormatting.displayUnit("10*3/uL"), "×10³/µL")
        XCTAssertEqual(ObservationFormatting.interpretationLabel("H"), "High")
        XCTAssertNil(ObservationFormatting.interpretationLabel("N"))
        XCTAssertEqual(
            ObservationFormatting.displayValue(code: ObservationCode.bodyTemperature, number: 98, unit: "[degF]", text: nil, boolean: nil, components: []),
            "98.0 °F"
        )
        // A source can send blood pressure with decimals. The chart reads whole numbers.
        let pressure = [
            ImportedComponent(code: ImportedCode(system: nil, code: ObservationCode.systolic, display: "Systolic"), value: .quantity(118.136, unit: "mm[Hg]")),
            ImportedComponent(code: ImportedCode(system: nil, code: ObservationCode.diastolic, display: "Diastolic"), value: .quantity(81.463, unit: "mm[Hg]")),
        ]
        XCTAssertEqual(ObservationFormatting.bloodPressure(from: pressure), "118/81 mmHg")
        XCTAssertNil(ObservationFormatting.displayUnit("{score}"))
        XCTAssertEqual(
            ObservationFormatting.displayValue(code: "72514-3", number: 2, unit: "{score}", text: nil, boolean: nil, components: []),
            "2"
        )
    }
}
