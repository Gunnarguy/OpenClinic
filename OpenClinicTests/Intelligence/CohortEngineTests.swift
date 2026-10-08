import XCTest
@testable import OpenClinic

/// Parser and engine behavior on a small hand-built panel, independent of the
/// demo fixture.
final class CohortEngineTests: XCTestCase {

    private let calendar = Calendar.current
    private var now: Date { calendar.date(bySettingHour: 12, minute: 0, second: 0, of: Date())! }

    private func day(_ offset: Int, hour: Int = 9) -> Date {
        let start = calendar.startOfDay(for: now)
        let date = calendar.date(byAdding: .day, value: offset, to: start)!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date)!
    }

    private func patient(
        _ mrn: String,
        _ name: String,
        age: Int = 50,
        sex: String = "Female",
        smoker: Bool = false,
        allergies: [String] = ["No known drug allergies"],
        flags: [String] = [],
        diagnoses: [DiagnosisFact] = [],
        medications: [MedicationFact] = [],
        appointments: [AppointmentFact] = []
    ) -> PatientFacts {
        PatientFacts(
            id: UUID(), mrn: mrn, name: name, age: age, sex: sex, isSmoker: smoker,
            allergies: allergies, riskFlags: flags,
            diagnoses: diagnoses, medications: medications, appointments: appointments
        )
    }

    private func diagnosis(_ id: String, _ name: String, _ icd: String?, daysAgo: Int = 30, status: String = "signed") -> DiagnosisFact {
        DiagnosisFact(recordID: id, name: name, icd10: icd, date: day(-daysAgo), documentationStatus: status)
    }

    private func medication(_ id: String, _ name: String, generic: String? = nil, status: String? = "Active", route: String? = nil) -> MedicationFact {
        MedicationFact(rxID: id, name: name, genericName: generic, status: status, route: route)
    }

    private lazy var snapshot: PanelSnapshot = PanelSnapshot(
        patients: [
            patient("T-1", "Ada Alder", age: 70, smoker: true,
                    allergies: ["Penicillin"],
                    flags: ["High cumulative UV exposure"],
                    diagnoses: [diagnosis("R-1", "Melanoma In Situ", "D03.59")],
                    medications: [medication("M-1", "Dupilumab 300mg", generic: "Dupilumab", route: "Subcutaneous")],
                    appointments: [AppointmentFact(appointmentID: "A-1", time: day(0, hour: 10), reason: "Skin check", status: "Scheduled")]),
            patient("T-2", "Ben Birch", age: 40, sex: "Male",
                    flags: ["Family history of melanoma (father)"],
                    diagnoses: [diagnosis("R-2", "Plaque Psoriasis", "L40.0")],
                    medications: [
                        medication("M-2", "Methotrexate 15mg", generic: "Methotrexate", route: "Oral"),
                        medication("M-3", "Tacrolimus 0.1% Ointment", generic: "Tacrolimus", route: "Topical"),
                    ],
                    appointments: [AppointmentFact(appointmentID: "A-2", time: day(3), reason: "Lab review", status: "Scheduled")]),
            patient("T-3", "Cy Cedar", age: 30, sex: "Male", smoker: true,
                    allergies: [],
                    diagnoses: [
                        diagnosis("R-3", "Lesion, uncoded", nil),
                        diagnosis("R-4", "Atopic Dermatitis", "L20.89", status: "draft"),
                    ],
                    medications: [
                        medication("M-4", "Tacrolimus 0.1% Ointment", generic: "Tacrolimus"),
                        medication("M-5", "Adalimumab 40mg", generic: "Adalimumab", status: "Completed"),
                    ]),
        ],
        capturedAt: now
    )

    private var parser: CohortQueryParser {
        CohortQueryParser(vocabulary: PanelVocabulary(snapshot: snapshot))
    }

    private func matched(_ question: String, file: StaticString = #filePath, line: UInt = #line) -> Set<String>? {
        guard let query = parser.parse(question) else { return nil }
        return CohortEngine.run(query, on: snapshot, calendar: calendar).matchedMRNs
    }

    // MARK: Diagnoses

    func testDiagnosisMatchesByICDPrefixOrName() {
        XCTAssertEqual(matched("Which patients have melanoma?"), ["T-1"])
        XCTAssertEqual(matched("Who has psoriasis?"), ["T-2"])
        XCTAssertEqual(matched("Who has eczema?"), ["T-3"])
    }

    func testFamilyHistoryFlagIsRelatedAndNeverCounted() throws {
        let query = try XCTUnwrap(parser.parse("Which patients have melanoma history?"))
        let result = CohortEngine.run(query, on: snapshot, calendar: calendar)
        XCTAssertEqual(result.matchedMRNs, ["T-1"])
        XCTAssertEqual(result.relatedMRNs, ["T-2"])
    }

    func testEveryMatchCarriesTheRecordThatProducedIt() throws {
        let query = try XCTUnwrap(parser.parse("Which patients have melanoma?"))
        let result = CohortEngine.run(query, on: snapshot, calendar: calendar)
        let evidence = try XCTUnwrap(result.matches.first?.evidence.first)
        XCTAssertEqual(evidence.sourceID, "R-1")
        XCTAssertEqual(evidence.kind, .diagnosis)
        XCTAssertEqual(evidence.detail, "ICD-10 D03.59")
    }

    // MARK: Medications

    func testOnlyCurrentMedicationsCount() {
        // T-3's adalimumab is completed, so only T-1 is on a biologic.
        XCTAssertEqual(matched("Who is on a biologic?"), ["T-1"])
    }

    func testTopicalTacrolimusIsNotSystemicImmunosuppression() {
        XCTAssertEqual(matched("Who is on immunosuppressants?"), ["T-2"])
        XCTAssertEqual(matched("Who is on a calcineurin inhibitor?"), ["T-2", "T-3"])
    }

    func testMedicationNamedInTheChartIsUnderstood() {
        XCTAssertEqual(matched("Who is taking methotrexate?"), ["T-2"])
    }

    // MARK: Combining criteria

    func testOrBetweenSameKindWidensTheCohort() throws {
        let query = try XCTUnwrap(parser.parse("Who is on biologics or immunosuppressants?"))
        XCTAssertEqual(query.groups.count, 1)
        XCTAssertEqual(query.groups.first?.count, 2)
        XCTAssertEqual(CohortEngine.run(query, on: snapshot, calendar: calendar).matchedMRNs, ["T-1", "T-2"])
    }

    func testCriteriaOfDifferentKindsMustAllHold() throws {
        let query = try XCTUnwrap(parser.parse("Smokers with high UV exposure risk?"))
        XCTAssertEqual(query.groups.count, 2)
        XCTAssertEqual(CohortEngine.run(query, on: snapshot, calendar: calendar).matchedMRNs, ["T-1"])
    }

    func testOrBetweenTwoDifferentKindsMeansEither() {
        XCTAssertEqual(matched("Smokers or patients with psoriasis"), ["T-1", "T-2", "T-3"])
    }

    // MARK: Allergies

    func testAllergyQuestions() {
        XCTAssertEqual(matched("Who is allergic to penicillin?"), ["T-1"])
        // T-3 has no allergy status recorded, which is not the same as a charted negative.
        XCTAssertEqual(matched("Which patients have no known allergies?"), ["T-2"])
    }

    func testAllergyOverviewListsEveryPatient() throws {
        let query = try XCTUnwrap(parser.parse("Panel-wide allergy overview"))
        XCTAssertEqual(query.presentation, .allergyOverview)
        let result = CohortEngine.run(query, on: snapshot, calendar: calendar)
        XCTAssertEqual(result.matches.count, 3)
        XCTAssertEqual(CohortAnswerFormatter.headline(for: result), "1 of 3 patients have a documented allergy.")
    }

    // MARK: Schedule, age, documentation

    func testScheduleWindows() throws {
        XCTAssertEqual(matched("Who's on today's schedule?"), ["T-1"])
        XCTAssertEqual(matched("Patients with follow-ups this week"), ["T-2"])
        let query = try XCTUnwrap(parser.parse("Who's on today's schedule?"))
        XCTAssertEqual(query.presentation, .schedule)
    }

    func testAgeBounds() {
        XCTAssertEqual(matched("Which patients are over 65?"), ["T-1"])
        XCTAssertEqual(matched("Patients under 35"), ["T-3"])
        XCTAssertEqual(matched("Patients 40 and older"), ["T-1", "T-2"])
    }

    func testUnsignedNotes() {
        XCTAssertEqual(matched("Which notes are unsigned?"), ["T-3"])
    }

    // MARK: Refusing instead of guessing

    func testQuestionsOutsideTheGrammarAreNotAnswered() {
        let unanswerable = [
            "Which patients are not on a biologic?",
            "Who has no history of melanoma?",
            "Which psoriasis patients had elevated liver enzymes?",
            "Summarize the panel",
            "Who should be screened for melanoma?",
            "Patients with psoriasis and eczema or melanoma",
            "Who has skin cancer in the family?",
            "",
        ]
        for question in unanswerable {
            XCTAssertNil(parser.parse(question), "Should not be computed: \(question)")
        }
    }

    func testAllergenWordsAreOnlyReadAsAllergensInAllergyQuestions() {
        // "penicillin" with no allergy word is not understood as a medication
        // on this panel, so the question is refused instead of guessed.
        XCTAssertNil(parser.parse("Who is on penicillin?"))
    }

    // MARK: Text answer

    func testTextAnswerStatesTheComputationAndSources() throws {
        let query = try XCTUnwrap(parser.parse("Who is on biologics or immunosuppressants?"))
        let text = CohortAnswerFormatter.text(for: CohortEngine.run(query, on: snapshot, calendar: calendar))
        XCTAssertTrue(text.hasPrefix("2 of 3 patients match: current biologic OR current systemic immunosuppressant."), text)
        XCTAssertTrue(text.contains("Ada Alder (T-1): Dupilumab 300mg [M-1]"), text)
        XCTAssertTrue(text.contains("Ben Birch (T-2): Methotrexate 15mg [M-2]"), text)
        XCTAssertTrue(text.hasSuffix(CohortAnswerFormatter.provenanceLine), text)
    }
}
