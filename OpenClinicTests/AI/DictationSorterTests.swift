import XCTest
@testable import OpenClinic

/// The note the app drafts when the model does not: the dictation's own sentences and nothing else.
final class DictationSorterTests: XCTestCase {
    private let dictation = "Patient returns for psoriasis follow up. Plaques on both elbows improved about fifty percent on methotrexate fifteen milligrams weekly. No nausea, no mouth sores. Exam shows thin pink plaques on bilateral elbows with minimal scale. Continue methotrexate, check CBC and CMP today, return in twelve weeks."

    func testEverySentenceLandsInTheSectionItsWordsPointTo() {
        let sections = DictationSorter.sort(dictation)

        XCTAssertEqual(sections.diagnosis, "Psoriasis")
        XCTAssertEqual(sections.history, dictation, "the history is the whole dictation, so a sentence the rules place badly is never lost")
        XCTAssertEqual(sections.symptoms, "No nausea, no mouth sores.")
        XCTAssertEqual(sections.exam, "Exam shows thin pink plaques on bilateral elbows with minimal scale.")
        XCTAssertEqual(sections.plan, "Continue methotrexate, check CBC and CMP today, return in twelve weeks.")
        XCTAssertEqual(sections.followUp, sections.plan, "a sentence that states the plan and the return visit is in both sections")
        XCTAssertEqual(sections.instructions, DictationSorter.notDictated)
    }

    /// The rule the sorter exists for: the app writes no clinical sentence of its own.
    func testNothingInTheDraftIsWrittenByTheApp() {
        let dictations = [
            dictation,
            "Skin check today.",
            "Itchy rash on both forearms for two weeks. Advised fragrance-free emollient. Recheck in one month",
            "",
        ]
        for text in dictations {
            let said = Set(DictationSorter.sentences(of: text))
            let sections = DictationSorter.sort(text)
            for section in [sections.history, sections.symptoms, sections.exam, sections.plan, sections.instructions, sections.followUp] {
                guard section != DictationSorter.notDictated else { continue }
                var rest = section
                for sentence in said.sorted(by: { $0.count > $1.count }) {
                    rest = rest.replacingOccurrences(of: sentence, with: "")
                }
                XCTAssertTrue(rest.trimmingCharacters(in: .whitespaces).isEmpty, "\"\(rest)\" is not from the dictation: \(text)")
            }
        }
        XCTAssertEqual(DictationSorter.sort("").history, DictationSorter.notDictated)
    }

    func testADiagnosisIsNamedOnlyInTheDictationsOwnWord() {
        XCTAssertEqual(DictationSorter.diagnosis(in: "Atopic dermatitis flare on the arms."), "Atopic dermatitis", "the longer term, not \"Dermatitis\"")
        XCTAssertEqual(DictationSorter.diagnosis(in: "Here for a wart on the left hand."), "Wart")
        XCTAssertEqual(DictationSorter.diagnosis(in: "Skin check today."), DictationSorter.diagnosisNotDictated)
        XCTAssertTrue(DictationSorter.isUndictated(diagnosis: DictationSorter.sort("Skin check today.").diagnosis))
        XCTAssertFalse(DictationSorter.isUndictated(diagnosis: "Wart"))
    }

    /// A condition the dictation denies is not the diagnosis.
    func testADeniedConditionIsNotTheDiagnosis() {
        XCTAssertEqual(DictationSorter.diagnosis(in: "Denies melanoma in the family."), DictationSorter.diagnosisNotDictated)
        XCTAssertEqual(DictationSorter.diagnosis(in: "No history of melanoma. Here for acne on the cheeks."), "Acne")
        XCTAssertEqual(DictationSorter.diagnosis(in: "Biopsy was negative for basal cell carcinoma."), DictationSorter.diagnosisNotDictated)
    }

    /// The rules match whole words. Each of these once put a sentence in the wrong section.
    func testAWordInsideAnotherWordIsNotACue() {
        let sentences = [
            "The mole on his back increased in size.",
            "Irregular border on the left forearm lesion.",
            "Plantar surface is clear.",
            "She prefers a cream to an ointment.",
            "Painless nodule for one year.",
        ]
        for sentence in sentences {
            let sections = DictationSorter.sort(sentence)
            XCTAssertEqual(sections.history, sentence)
            XCTAssertEqual(sections.plan, DictationSorter.notDictated, sentence)
            XCTAssertEqual(sections.followUp, DictationSorter.notDictated, sentence)
            XCTAssertEqual(sections.symptoms, DictationSorter.notDictated, sentence)
        }
        XCTAssertEqual(DictationSorter.sort("Return in six weeks.").followUp, "Return in six weeks.")
        XCTAssertEqual(DictationSorter.sort("See her back in three months.").followUp, "See her back in three months.")
    }

    /// A diagnosis is a whole word of the dictation, in a sentence that neither denies it nor is about a relative.
    func testADiagnosisIsNotReadOutOfAnotherWordADenialOrARelative() {
        for sentence in ["No melanoma.", "This is not melanoma.", "Mother had melanoma.", "Seen by Dr. Schwartz for a rash.",
                         "Acneiform eruption on the chest.", "Referred by Dr. Stewart."] {
            XCTAssertEqual(DictationSorter.diagnosis(in: sentence), DictationSorter.diagnosisNotDictated, sentence)
        }
        XCTAssertEqual(DictationSorter.diagnosis(in: "Cystic acne on the jaw."), "Acne", "not a cyst")
        XCTAssertEqual(DictationSorter.diagnosis(in: "Two warts on the right hand."), "Wart", "a plural is the same word")
    }
}
