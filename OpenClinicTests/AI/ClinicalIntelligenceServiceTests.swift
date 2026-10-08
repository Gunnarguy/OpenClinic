import XCTest
import SwiftData
@testable import OpenClinic

final class ClinicalIntelligenceServiceTests: XCTestCase {
    var service: ClinicalIntelligenceService!
    var container: ModelContainer!
    var context: ModelContext!

    @MainActor
    override func setUp() async throws {
        let schema = Schema([
            PatientProfile.self,
            LocalClinicalRecord.self,
            LocalMedication.self,
            Appointment.self,
            ClinicalPhoto.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
        service = ClinicalIntelligenceService()
        // These tests cover the answers built from chart rows. With the model on, a Mac that has
        // Apple Intelligence would generate the reply instead: 25 seconds, and different each run.
        service.languageModelEnabled = false
        service.ragEnabled = false
    }

    override func tearDown() {
        service = nil
        context = nil
        container = nil
    }

    @MainActor
    func testExecuteFallbackQueryMedication() async throws {
        let patient = PatientProfile(
            firstName: "Jane",
            lastName: "Doe",
            dateOfBirth: Date(),
            gender: "Female"
        )
        context.insert(patient)

        let med = LocalMedication(
            rxID: "rx1",
            medicationName: "Lisinopril",
            writtenBy: "Dr. Smith",
            writtenDate: Date(),
            quantityInfo: "30 tablets",
            refills: 3,
            dose: "10mg",
            route: "Oral",
            frequency: "daily",
            status: "Active",
            sourceKind: "Manual",
            sourceSystemName: "Manual",
            sourceRecordIdentifier: "rx1",
            sourceOfTruth: true
        )
        med.patient = patient
        context.insert(med)
        patient.medications?.append(med)
        try context.save()

        let response = try await service.executeToolQuery(query: "What is patient's prescription refill history?", modelContext: context, patient: patient)
        XCTAssertTrue(response.contains("Lisinopril"), "Response was: \(response)")
        XCTAssertTrue(response.contains("10mg"))
        XCTAssertTrue(response.contains("daily"))
    }

    @MainActor
    func testExecuteFallbackQueryAppointments() async throws {
        let patient = PatientProfile(
            firstName: "Jane",
            lastName: "Doe",
            dateOfBirth: Date(),
            gender: "Female"
        )
        context.insert(patient)

        let appt = Appointment(
            appointmentID: "appt1",
            scheduledTime: Date().addingTimeInterval(3600),
            reasonForVisit: "Annual physical",
            status: "Booked",
            clinicianName: "Dr. House",
            sourceKind: "Manual",
            sourceSystemName: "Manual",
            sourceRecordIdentifier: "appt1",
            sourceOfTruth: true
        )
        appt.patient = patient
        context.insert(appt)
        patient.appointments?.append(appt)
        try context.save()

        let response = try await service.executeToolQuery(query: "Show me the next visit or scheduled appointment", modelContext: context, patient: patient)
        XCTAssertTrue(response.contains("Annual physical"))
    }

    @MainActor
    func testExecutePanelFallbackQueryToday() async throws {
        let patient1 = PatientProfile(
            firstName: "Jane",
            lastName: "Doe",
            dateOfBirth: Date(),
            gender: "Female"
        )
        let patient2 = PatientProfile(
            firstName: "John",
            lastName: "Smith",
            dateOfBirth: Date(),
            gender: "Male"
        )
        context.insert(patient1)
        context.insert(patient2)

        let appt1 = Appointment(
            appointmentID: "a1",
            scheduledTime: Date(),
            reasonForVisit: "Asthma check",
            status: "Booked",
            clinicianName: "Dr. Smith",
            sourceKind: "Manual",
            sourceSystemName: "Manual",
            sourceRecordIdentifier: "a1",
            sourceOfTruth: true
        )
        appt1.patient = patient1
        context.insert(appt1)
        patient1.appointments?.append(appt1)

        try context.save()

        let response = try await service.executePanelQuery(query: "who is on today's schedule or agenda?", modelContext: context)
        XCTAssertTrue(response.contains("Jane Doe"))
        XCTAssertTrue(response.contains("Asthma check"))
    }

    /// Text the app lists from chart rows must never be passed off as written by a model.
    @MainActor
    func testAnAnswerListedByTheAppSaysSoAndWhy() async throws {
        let patient = PatientProfile(firstName: "Jane", lastName: "Doe", dateOfBirth: Date(), gender: "Female")
        context.insert(patient)
        let medication = LocalMedication(
            rxID: "rx1", medicationName: "Lisinopril", writtenBy: "Dr. Smith", writtenDate: Date(),
            quantityInfo: "30 tablets", refills: 3, dose: "10mg", route: "Oral", frequency: "daily",
            status: "Active", sourceKind: "Manual", sourceSystemName: "Manual", sourceRecordIdentifier: "rx1", sourceOfTruth: true
        )
        medication.patient = patient
        context.insert(medication)
        try context.save()

        let answer = try await service.answerPatientQuestion(query: "What medication is prescribed?", modelContext: context, patient: patient)

        XCTAssertTrue(answer.text.contains("Lisinopril"))
        XCTAssertEqual(answer.origin, .chartListing(reason: AnswerOrigin.modelUnavailable))
    }

    @MainActor
    func testAPanelQuestionTheParserDoesNotCoverIsListedNotGeneratedWhenTheModelIsOff() async throws {
        let patient = PatientProfile(firstName: "Jane", lastName: "Doe", dateOfBirth: Date(), gender: "Female")
        context.insert(patient)
        try context.save()

        let answer = try await service.answerPanelQuestion("Tell me something surprising about this clinic's week.", modelContext: context)

        guard case .listed(_, let reason) = answer else {
            return XCTFail("Expected text listed by the app, got \(answer)")
        }
        XCTAssertEqual(reason, AnswerOrigin.modelUnavailable)
    }

    // MARK: - Time limit on a model call

    @MainActor
    func testAModelCallThatReturnsInTimeGivesItsAnswer() async throws {
        service.modelTimeLimit = .seconds(5)
        let answer = try await service.withModelTimeLimit { "an answer" }
        XCTAssertEqual(answer, "an answer")
    }

    /// A call that keeps running and ignores cancellation must not keep the clinician waiting.
    @MainActor
    func testAModelCallThatRunsLongIsGivenUpOnAtTheLimit() async throws {
        service.modelTimeLimit = .milliseconds(150)
        let start = Date()
        do {
            _ = try await service.withModelTimeLimit {
                // Two seconds of work that cancellation does not stop.
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 2) { continuation.resume() }
                }
                return "too late"
            }
            XCTFail("A late answer was returned")
        } catch let error as ModelTimeLimitError {
            XCTAssertEqual(error.limit, .milliseconds(150))
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.5, "the wait ended at the limit, not when the work did")
    }

    @MainActor
    func testAModelErrorBeforeTheLimitIsPassedOn() async throws {
        struct Refused: Error {}
        service.modelTimeLimit = .seconds(5)
        do {
            _ = try await service.withModelTimeLimit { throw Refused() }
            XCTFail("The error was swallowed")
        } catch is Refused {
        }
    }

    /// A note the keyword rules sorted must not be presented as written by a model, and holds only
    /// what was dictated: no finding, order or plan of the app's own, and nothing from the chart.
    @MainActor
    func testANoteDraftedWithoutTheModelSaysTheRulesWroteItAndAddsNothing() async throws {
        let patient = PatientProfile(firstName: "Jane", lastName: "Doe", dateOfBirth: Date(), gender: "Female")
        context.insert(patient)
        let old = LocalClinicalRecord(recordID: "old", dateRecorded: Date(), conditionName: "Melanoma In Situ", status: "Final")
        old.patient = patient
        context.insert(old)
        try context.save()
        let dictation = "Follow up for acne, improving on tretinoin, continue."

        let draft = try await service.draftNote(from: dictation, patient: patient)

        XCTAssertEqual(draft.origin, .keywordRules(reason: AnswerOrigin.modelUnavailable))
        XCTAssertEqual(draft.note.primaryDiagnosis, "Acne", "the dictation's own word, not a diagnosis from the chart")
        XCTAssertEqual(draft.note.impressionsAndPlan, dictation)
        XCTAssertEqual(draft.note.ccHPI, dictation, "the history is the dictation as it was said")
        XCTAssertEqual(draft.note.examFindings, DictationSorter.notDictated)
        XCTAssertEqual(draft.note.reviewOfSystems, DictationSorter.notDictated)
        XCTAssertTrue(draft.note.recommendedOrders.isEmpty, "nobody dictated an order")
        XCTAssertTrue(draft.note.medicationChanges.isEmpty)
        XCTAssertFalse(String(describing: draft.note).localizedCaseInsensitiveContains("melanoma"))
    }

    /// Body sites are read from whole words: "itching" names no chin and "diagnosed" no nose.
    @MainActor
    func testABodySiteIsNotReadOutOfAnotherWord() async throws {
        let draft = try await service.draftNote(from: "Diagnosed with eczema, itching and blanching on both arms.")

        XCTAssertEqual(draft.origin, .keywordRules(reason: AnswerOrigin.modelUnavailable))
        XCTAssertFalse(draft.note.affectedAnatomicalZones.contains { $0.contains("chin") || $0.contains("nose") },
                       "\(draft.note.affectedAnatomicalZones)")
        XCTAssertEqual(draft.note.primaryDiagnosis, "Eczema")
    }

    /// With a patient in view, a listing is that patient's rows. It used to fall back to every
    /// patient's rows when the patient had none.
    @MainActor
    func testAListingForAPatientWithNoRowsNeverShowsAnotherPatients() async throws {
        let other = PatientProfile(firstName: "Other", lastName: "Person", dateOfBirth: Date(), gender: "Male")
        context.insert(other)
        let medication = LocalMedication(
            rxID: "rx-other", medicationName: "Warfarin", writtenBy: "Dr. Smith", writtenDate: Date(),
            quantityInfo: "30 tablets", refills: 0, dose: "5mg", route: "Oral", frequency: "daily",
            status: "Active", sourceKind: "Manual", sourceSystemName: "Manual", sourceRecordIdentifier: "rx-other", sourceOfTruth: true
        )
        medication.patient = other
        context.insert(medication)
        let record = LocalClinicalRecord(recordID: "r-other", dateRecorded: Date(), conditionName: "Atrial Fibrillation", status: "Final")
        record.patient = other
        context.insert(record)
        let empty = PatientProfile(firstName: "New", lastName: "Chart", dateOfBirth: Date(), gender: "Female")
        context.insert(empty)
        try context.save()

        let medications = try await service.answerPatientQuestion(query: "What medication is prescribed?", modelContext: context, patient: empty)
        XCTAssertFalse(medications.text.contains("Warfarin"), medications.text)
        XCTAssertEqual(medications.text, "No medications are currently on file for this patient.")

        let history = try await service.answerPatientQuestion(query: "Summarize the history.", modelContext: context, patient: empty)
        XCTAssertFalse(history.text.contains("Atrial Fibrillation"), history.text)
        XCTAssertEqual(history.text, "No clinical history is currently available for this patient.")
    }

    // MARK: - Who wrote it, where there is no badge

    func testAShortcutDialogEndsWithWhoWroteTheAnswer() {
        let listed = PatientAnswer(text: "Allergies: Penicillin", origin: .chartListing(reason: AnswerOrigin.modelUnavailable))
        XCTAssertEqual(
            AnswerDialog.text(listed),
            "Allergies: Penicillin\n\nListed from the chart by the app. No language model wrote this. The on-device model is not available."
        )

        let written = AnswerDialog.text(PatientAnswer(text: "She takes methotrexate.", origin: .model))
        XCTAssertTrue(written.hasSuffix("Written by the on-device model. This text has not been checked against the chart."))

        XCTAssertTrue(AnswerDialog.text(PanelAnswer.generated("Two patients.")).contains("Written by the on-device model"))
        let panelListing = AnswerDialog.text(PanelAnswer.listed("Rows", reason: "The model declined."))
        XCTAssertTrue(panelListing.contains("No language model wrote this. The model declined."))
        XCTAssertFalse(panelListing.contains("Written by"))
    }

    @MainActor
    func testAShortcutDialogForAComputedAnswerSaysTheAppComputedIt() async throws {
        let container = try OpenClinicSchema.makeInMemoryContainer()
        let context = ModelContext(container)
        try DemoDataSeeder.prepare(context: context)
        let service = ClinicalIntelligenceService()
        service.languageModelEnabled = false

        let dialog = AnswerDialog.text(try await service.answerPanelQuestion("Which patients have melanoma history?", modelContext: context))

        XCTAssertTrue(dialog.hasSuffix("Computed from chart data by the app. No language model wrote this."), dialog)
    }

    func testOnlyANoteTheModelDraftedIsSavedAsAnAINote() {
        XCTAssertEqual(SavedNoteOrigin.sourceKind(for: .model), .localAI)
        XCTAssertEqual(SavedNoteOrigin.visitType(for: .model), "AI-assisted encounter")

        let rules = AnswerOrigin.keywordRules(reason: AnswerOrigin.modelUnavailable)
        XCTAssertEqual(SavedNoteOrigin.sourceKind(for: rules), .clinicianCaptured)
        XCTAssertEqual(SavedNoteOrigin.visitType(for: rules), "Dictated encounter")
        XCTAssertFalse(SavedNoteOrigin.visitType(for: rules).contains("AI"))

        XCTAssertEqual(SavedNoteOrigin.sourceKind(for: nil), .clinicianCaptured, "a draft of unknown origin is never called AI")
    }
}
