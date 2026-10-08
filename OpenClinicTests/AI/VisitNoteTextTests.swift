import XCTest
@testable import OpenClinic

/// The plain-text form of a visit note, which the on-device model writes when it has declined to
/// fill the structured one.
final class VisitNoteTextTests: XCTestCase {
    func testLabeledSectionsAreReadIntoTheirFields() throws {
        let text = """
        Diagnosis: Plaque psoriasis, improving
        History: Returns for follow up. Plaques on both elbows improved about fifty percent.
        Symptoms: No nausea, no mouth sores.
        Exam: Thin pink plaques on bilateral elbows with minimal scale.
        Plan: Continue methotrexate 15 mg weekly.
        Instructions: Keep taking folic acid.
        Follow-up: Return in twelve weeks.
        Orders: CBC, CMP
        Medication changes: Methotrexate continued
        Body sites: left elbow; right elbow
        """
        let note = try XCTUnwrap(VisitNoteText.parse(text))

        XCTAssertEqual(note.diagnosis, "Plaque psoriasis, improving")
        XCTAssertEqual(note.plan, "Continue methotrexate 15 mg weekly.")
        XCTAssertEqual(note.followUp, "Return in twelve weeks.")
        XCTAssertEqual(note.orders, ["CBC", "CMP"])
        XCTAssertEqual(note.medicationChanges, ["Methotrexate continued"])
        XCTAssertEqual(note.bodySites, ["left elbow", "right elbow"])
    }

    func testDecoratedLabelsAndWrappedLinesAreRead() throws {
        let text = """
        **Diagnosis:** Rosacea
        ## History:
        Six weeks of facial redness,
        worse with heat.
        - Plan: Start metronidazole cream.
        Orders: None
        Follow-up: Not stated.
        """
        let note = try XCTUnwrap(VisitNoteText.parse(text))

        XCTAssertEqual(note.diagnosis, "Rosacea")
        XCTAssertEqual(note.history, "Six weeks of facial redness, worse with heat.")
        XCTAssertEqual(note.plan, "Start metronidazole cream.")
        XCTAssertTrue(note.orders.isEmpty, "\"None\" is the model leaving a section empty")
        XCTAssertEqual(note.followUp, "")
    }

    func testTextThatIsNotANoteIsRefused() {
        XCTAssertNil(VisitNoteText.parse("I can't help with that."))
        XCTAssertNil(VisitNoteText.parse("Orders: CBC"), "a note needs a diagnosis or a plan")
    }

    func testThePromptAsksForExactlyTheSectionsTheReaderAccepts() {
        for label in VisitNoteText.labels {
            XCTAssertTrue(VisitNoteText.request.contains("\(label):"), label)
        }
    }
}
