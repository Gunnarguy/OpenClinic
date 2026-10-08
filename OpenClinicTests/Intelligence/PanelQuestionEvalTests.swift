import XCTest
import SwiftData
@testable import OpenClinic

/// Panel questions asked in plain language, scored against answers written by
/// hand from the demo fixture.
///
/// The expected sets below are literals on purpose. They are not derived from
/// the engine or the lexicon, so a defect in either one fails a case here
/// instead of agreeing with itself. A case passes only when the set of matched
/// patients equals the expected set exactly.
final class PanelQuestionEvalTests: XCTestCase {

    private struct Case {
        let question: String
        let expected: Set<String>
        var related: Set<String> = []
    }

    private static let everyone: Set<String> = [
        "OC-1001", "OC-1002", "OC-1003", "OC-1004", "OC-1005",
        "OC-2001", "OC-2002", "OC-2003", "OC-2004", "OC-2005",
    ]

    private static let cases: [Case] = [
        // Diagnoses
        Case(question: "Which patients have melanoma history?", expected: ["OC-1003"], related: ["OC-2005"]),
        Case(question: "Who has a history of skin cancer?", expected: ["OC-1001", "OC-1003", "OC-2003"], related: ["OC-2005"]),
        Case(question: "Which patients have basal cell carcinoma?", expected: ["OC-1001", "OC-2003"]),
        Case(question: "Show me patients with psoriasis", expected: ["OC-1003", "OC-2001"]),
        Case(question: "Who has eczema?", expected: ["OC-1004"]),
        Case(question: "How many patients have dermatitis?", expected: ["OC-1004"]),
        Case(question: "Which patients have rosacea?", expected: ["OC-1002", "OC-1005"]),
        Case(question: "Patients with actinic keratosis", expected: ["OC-1001", "OC-2004"]),
        Case(question: "Who has acne?", expected: ["OC-1002"]),

        // Medications
        Case(question: "Who is on biologics or immunosuppressants?", expected: ["OC-1003", "OC-1004", "OC-2001"]),
        Case(question: "Which patients are on a biologic?", expected: ["OC-1004", "OC-2001"]),
        Case(question: "Who is on immunosuppressants?", expected: ["OC-1003"]),
        Case(question: "Who is taking methotrexate?", expected: ["OC-1003"]),
        Case(question: "Is anyone on blood thinners?", expected: ["OC-2003"]),
        Case(question: "Which patients use topical steroids?", expected: ["OC-1003", "OC-1004", "OC-2001"]),
        Case(question: "Who is on a retinoid?", expected: ["OC-1001", "OC-1002"]),

        // Risk and social history
        Case(question: "List the smokers", expected: ["OC-1001", "OC-1005", "OC-2004"]),
        Case(question: "Smokers with high UV exposure risk?", expected: ["OC-1001", "OC-1005", "OC-2004"]),
        Case(question: "Who has UV exposure risk?", expected: ["OC-1001", "OC-1005", "OC-2002", "OC-2004"]),
        Case(question: "Who has a family history of melanoma?", expected: ["OC-2005"]),

        // Allergies
        Case(question: "Who is allergic to penicillin?", expected: ["OC-1003"]),
        Case(question: "Which patients have a nickel allergy?", expected: ["OC-1004"]),
        Case(question: "Who has a sulfa allergy?", expected: ["OC-1001"]),
        Case(question: "Which patients have no known allergies?", expected: ["OC-1002", "OC-1005", "OC-2001", "OC-2004"]),

        // Schedule
        Case(question: "Who's on today's schedule?", expected: everyone),
        Case(question: "Patients with follow-ups this week", expected: ["OC-1005", "OC-2003"]),

        // Demographics and documentation
        Case(question: "Which patients are over 65?", expected: ["OC-2002", "OC-2003"]),
        Case(question: "Which notes are unsigned?", expected: ["OC-1001", "OC-1004", "OC-1005"]),

        // Combined
        Case(question: "Which psoriasis patients are on a biologic?", expected: ["OC-2001"]),
        Case(question: "Female patients with skin cancer", expected: ["OC-1001", "OC-2003"]),
        Case(question: "Which smokers have rosacea?", expected: ["OC-1005"]),
    ]

    private var container: ModelContainer!
    private var context: ModelContext!
    private var defaults: UserDefaults!
    private var suiteName: String!

    @MainActor
    override func setUp() async throws {
        container = try OpenClinicSchema.makeInMemoryContainer()
        context = ModelContext(container)
        suiteName = "PanelQuestionEvalTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        // A nil photo folder skips the placeholder images, so the test writes no files.
        try DemoDataSeeder.prepare(context: context, now: .now, calendar: .current, defaults: defaults, photoDirectory: nil)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        defaults = nil
        context = nil
        container = nil
    }

    @MainActor
    private func demoSnapshot() throws -> PanelSnapshot {
        let patients = try context.fetch(FetchDescriptor<PatientProfile>())
        return PanelSnapshot(patients: patients)
    }

    @MainActor
    func testEveryPanelQuestionMatchesItsHandWrittenAnswer() throws {
        let snapshot = try demoSnapshot()
        XCTAssertEqual(Set(snapshot.patients.map(\.mrn)), Self.everyone, "The demo panel changed. Update the expected answers with it.")

        let parser = CohortQueryParser(vocabulary: PanelVocabulary(snapshot: snapshot))
        var passed = 0
        var failures: [String] = []

        for testCase in Self.cases {
            guard let query = parser.parse(testCase.question) else {
                failures.append("NOT PARSED  \(testCase.question)")
                continue
            }
            let result = CohortEngine.run(query, on: snapshot)
            if result.matchedMRNs == testCase.expected && result.relatedMRNs == testCase.related {
                passed += 1
            } else {
                failures.append(
                    "WRONG  \(testCase.question)\n"
                    + "    expected \(testCase.expected.sorted()) related \(testCase.related.sorted())\n"
                    + "    got      \(result.matchedMRNs.sorted()) related \(result.relatedMRNs.sorted())"
                )
            }
        }

        print("PANEL EVAL: \(passed)/\(Self.cases.count) set-exact")
        XCTAssertTrue(failures.isEmpty, "\(failures.count) of \(Self.cases.count) panel questions failed:\n" + failures.joined(separator: "\n"))
    }

    /// Every listed patient must be backed by at least one chart fact.
    @MainActor
    func testNoMatchIsReportedWithoutEvidence() throws {
        let snapshot = try demoSnapshot()
        let parser = CohortQueryParser(vocabulary: PanelVocabulary(snapshot: snapshot))
        for testCase in Self.cases {
            guard let query = parser.parse(testCase.question) else { continue }
            let result = CohortEngine.run(query, on: snapshot)
            for match in result.matches + result.related {
                XCTAssertFalse(match.evidence.isEmpty, "\(match.name) listed without evidence for: \(testCase.question)")
            }
        }
    }

    /// The service routes a set question to the engine, not to the language model.
    @MainActor
    func testServiceComputesTheMelanomaQuestion() async throws {
        let service = ClinicalIntelligenceService()
        let answer = try await service.answerPanelQuestion("Which patients have melanoma history?", modelContext: context)
        guard case .computed(let result) = answer else {
            return XCTFail("Expected a computed answer, got a generated one")
        }
        XCTAssertEqual(result.matchedMRNs, ["OC-1003"])
        XCTAssertEqual(result.matches.first?.name, "Robert Chen")
        XCTAssertEqual(result.relatedMRNs, ["OC-2005"])
    }
}
