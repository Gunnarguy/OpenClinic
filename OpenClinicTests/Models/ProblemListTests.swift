import XCTest
import SwiftData
@testable import OpenClinic

/// The problem list a chart shows: charted problems first, then diagnoses that
/// only an encounter note names. The Summary tab's card and count and both
/// patient lists read it, so an imported patient's conditions are counted.
final class ProblemListTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var defaults: UserDefaults!
    private var suiteName: String!

    @MainActor
    override func setUp() async throws {
        container = try OpenClinicSchema.makeInMemoryContainer()
        context = ModelContext(container)
        suiteName = "ProblemListTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        context = nil
        container = nil
    }

    private func day(_ daysAgo: Int) -> Date {
        Date(timeIntervalSince1970: 1_780_000_000 - Double(daysAgo) * 86_400)
    }

    private func problem(
        _ id: String,
        _ display: String,
        icd10: String? = nil,
        snomed: String? = nil,
        status: String = "active",
        onsetDaysAgo: Int,
        removedAtSource: Bool = false
    ) -> ChartProblem {
        ChartProblem(
            qualifiedID: id,
            display: display,
            codeSystem: icd10 != nil ? ChartCodeSystem.icd10CM : (snomed != nil ? ChartCodeSystem.snomed : nil),
            code: icd10 ?? snomed,
            clinicalStatus: status,
            onsetDate: day(onsetDaysAgo),
            isRemovedAtSource: removedAtSource
        )
    }

    private func note(_ id: String, _ condition: String, icd10: String?, daysAgo: Int) -> LocalClinicalRecord {
        LocalClinicalRecord(recordID: id, dateRecorded: day(daysAgo), conditionName: condition, status: "Active", icd10Code: icd10)
    }

    // MARK: - Rules

    @MainActor
    func testAChartWithOnlyImportedConditionsCountsThem() {
        // The case the Summary tab got wrong: nine conditions imported, no notes, "0 Problems".
        let problems = [
            problem("https://fhir.example/Condition/1", "Hypertension", snomed: "38341003", onsetDaysAgo: 4000),
            problem("https://fhir.example/Condition/2", "Prediabetes", snomed: "15777000", onsetDaysAgo: 3000),
            problem("https://fhir.example/Condition/3", "Viral sinusitis (disorder)", snomed: "444814009", status: "resolved", onsetDaysAgo: 900)
        ]
        let entries = ProblemList.entries(problems: problems, notes: [])

        XCTAssertEqual(entries.map(\.title), ["Prediabetes", "Hypertension", "Viral sinusitis (disorder)"])
        XCTAssertEqual(entries.filter(\.isOpen).count, 2)
        XCTAssertEqual(entries.map(\.statusLabel), ["Active", "Active", "Resolved"])
        XCTAssertEqual(entries.first?.code, "15777000", "A problem with no ICD-10 code shows the code its source used")
        XCTAssertTrue(entries.allSatisfy { $0.origin == .charted && $0.noteCount == 0 })
    }

    @MainActor
    func testANoteAttachesToTheProblemWithItsCodeAndAddsNoSecondLine() {
        let problems = [problem("local/psoriasis", "Plaque psoriasis", icd10: "L40.0", onsetDaysAgo: 45)]
        let notes = [
            note("N1", "Plaque Psoriasis", icd10: "L40.0", daysAgo: 45),
            note("N2", "Psoriasis follow-up", icd10: " l40.0 ", daysAgo: 3)
        ]
        let entries = ProblemList.entries(problems: problems, notes: notes)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].noteCount, 2)
        XCTAssertEqual(entries[0].latestNote?.recordID, "N2")
        XCTAssertEqual(entries[0].origin, .charted)
    }

    @MainActor
    func testANoteWithNoCodeAttachesByNameIgnoringCaseAndTheSnomedTag() {
        let problems = [problem("https://fhir.example/Condition/9", "Viral sinusitis (disorder)", snomed: "444814009", onsetDaysAgo: 10)]
        let entries = ProblemList.entries(problems: problems, notes: [note("N1", "viral  Sinusitis", icd10: nil, daysAgo: 9)])

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].noteCount, 1)
    }

    @MainActor
    func testADiagnosisOnlyANoteNamesIsListedAndMarkedAsFromANote() {
        let problems = [
            problem("local/rosacea", "Rosacea, papulopustular", icd10: "L71.8", onsetDaysAgo: 21),
            problem("local/nevus", "Dysplastic nevus of trunk", icd10: "D22.5", status: "resolved", onsetDaysAgo: 500)
        ]
        let notes = [
            note("N1", "Atypical Pigmented Lesion", icd10: "D49.2", daysAgo: 0),
            note("N2", "Atypical pigmented lesion", icd10: "D49.2", daysAgo: 7)
        ]
        let entries = ProblemList.entries(problems: problems, notes: notes)

        XCTAssertEqual(entries.map(\.title), ["Rosacea, papulopustular", "Atypical Pigmented Lesion", "Dysplastic nevus of trunk"],
                       "Open charted problems, then note diagnoses, then resolved problems")
        let fromNote = entries[1]
        XCTAssertEqual(fromNote.origin, .note)
        XCTAssertNil(fromNote.statusLabel, "A note diagnosis has no clinical status to show")
        XCTAssertEqual(fromNote.noteCount, 2)
        XCTAssertEqual(fromNote.latestNote?.recordID, "N1")
        XCTAssertEqual(entries.filter(\.isOpen).count, 2)
    }

    @MainActor
    func testAnExaminationVisitIsNotAProblem() {
        let notes = [
            note("N1", "Annual Skin Exam", icd10: "Z12.83", daysAgo: 30),
            note("N2", "Routine adult exam", icd10: "Z00.00", daysAgo: 400),
            note("N3", "Personal history of melanoma", icd10: "Z85.820", daysAgo: 30)
        ]
        let entries = ProblemList.entries(problems: [], notes: notes)

        XCTAssertEqual(entries.map(\.title), ["Personal history of melanoma"],
                       "Z00 to Z13 are reasons for an examination visit; other Z codes can be problems")
    }

    @MainActor
    func testAProblemNoLongerAtItsSourceIsLeftOffTheList() {
        let problems = [
            problem("https://fhir.example/Condition/1", "Hypertension", snomed: "38341003", onsetDaysAgo: 100),
            problem("https://fhir.example/Condition/2", "Entered in error upstream", snomed: "1", onsetDaysAgo: 50, removedAtSource: true)
        ]
        XCTAssertEqual(ProblemList.entries(problems: problems, notes: []).map(\.title), ["Hypertension"])
    }

    // MARK: - The demo panel

    @MainActor
    func testDemoPanelProblemLists() throws {
        try DemoDataSeeder.prepare(context: context, now: .now, calendar: .current, defaults: defaults, photoDirectory: nil)
        let patients = try context.fetch(FetchDescriptor<PatientProfile>())
        func patient(_ mrn: String) throws -> PatientProfile {
            try XCTUnwrap(patients.first { $0.medicalRecordNumber == mrn }, "No patient \(mrn)")
        }

        // Robert Chen: two open problems and a resolved melanoma in situ that two notes are filed under.
        let chen = try patient("OC-1003").problemList
        XCTAssertEqual(chen.map(\.title), ["Plaque psoriasis", "Psoriatic arthritis, suspected", "Melanoma in situ of left scapular region"])
        XCTAssertEqual(try patient("OC-1003").openProblemCount, 2)
        XCTAssertEqual(chen.last?.noteCount, 2)
        XCTAssertEqual(chen.last?.statusLabel, "Resolved")

        // David Williams: today's draft note names a lesion that is not on his problem list.
        let williams = try patient("OC-1005").problemList
        let fromNotes = williams.filter { $0.origin == .note }
        XCTAssertEqual(fromNotes.map(\.title), ["Atypical Pigmented Lesion"])
        XCTAssertEqual(fromNotes.first?.code, "D49.2")
        XCTAssertEqual(try patient("OC-1005").openProblemCount, 4)

        // Catherine Hartley's annual skin exam is a visit, not a problem.
        let hartley = try patient("OC-1001").problemList
        XCTAssertFalse(hartley.contains { $0.title.localizedCaseInsensitiveContains("exam") })
        XCTAssertEqual(try patient("OC-1001").openProblemCount, 3)

        // Across the panel, that one lesion is the only diagnosis a note names without a charted problem.
        let noteOnly = patients.flatMap(\.problemList).filter { $0.origin == .note }
        XCTAssertEqual(noteOnly.count, 1)
    }

    /// A note sorted by the keyword rules from a dictation that named no diagnosis names no problem.
    @MainActor
    func testANoteWhoseDiagnosisWasNotDictatedIsNotAProblem() {
        let entries = ProblemList.entries(problems: [], notes: [
            note("N1", DictationSorter.diagnosisNotDictated, icd10: nil, daysAgo: 0),
            note("N2", "Rosacea", icd10: nil, daysAgo: 1),
        ])

        XCTAssertEqual(entries.map(\.title), ["Rosacea"])
    }

    /// The same note is no diagnosis for a panel question either, while it still counts as a note
    /// awaiting a signature.
    func testANoteWhoseDiagnosisWasNotDictatedMatchesNoDiagnosisQuestion() throws {
        let facts = PatientFacts(
            id: UUID(), mrn: "T-9", name: "Dee Draft", age: 40, sex: "Female", isSmoker: false,
            allergies: [], riskFlags: [],
            diagnoses: [DiagnosisFact(recordID: "N1", name: DictationSorter.diagnosisNotDictated, icd10: nil, date: Date(), documentationStatus: "draft")],
            medications: [], appointments: [])
        let snapshot = PanelSnapshot(patients: [facts])
        let vocabulary = PanelVocabulary(snapshot: snapshot)

        XCTAssertTrue(vocabulary.diagnosisTerms.isEmpty, "\(vocabulary.diagnosisTerms)")
        let parser = CohortQueryParser(vocabulary: vocabulary)
        if let named = parser.parse("Which patients have dictated?") {
            XCTAssertTrue(CohortEngine.run(named, on: snapshot).matches.isEmpty, "the placeholder is not a diagnosis a question can match")
        }
        let unsigned = try XCTUnwrap(parser.parse("Which notes are unsigned?"))
        XCTAssertEqual(CohortEngine.run(unsigned, on: snapshot).matchedMRNs, ["T-9"], "it is still a note that awaits a signature")
    }
}
