import XCTest
import SwiftData
@testable import OpenClinic

/// The demo fixture and the seeder that turns it into chart data.
///
/// Fixture tests read DemoPanel.json as shipped. Seeder tests run against an
/// in-memory store, a private UserDefaults suite and a temporary photo folder,
/// so nothing here touches the app's own data.
final class DemoPanelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var photoDirectory: URL!
    private let calendar = Calendar.current

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
        suiteName = "DemoPanelTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        photoDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
    }

    override func tearDown() {
        if let suiteName {
            defaults?.removePersistentDomain(forName: suiteName)
        }
        if let photoDirectory {
            try? FileManager.default.removeItem(at: photoDirectory)
        }
        defaults = nil
        suiteName = nil
        photoDirectory = nil
        context = nil
        container = nil
    }

    // MARK: - Fixture

    func testFixtureDecodesWithUniqueIdentifiers() throws {
        let panel = try DemoDataSeeder.loadPanel()

        XCTAssertEqual(panel.version, 3)
        XCTAssertEqual(panel.patients.count, 10)
        XCTAssertEqual(panel.messages.count, 9)

        assertUnique(panel.patients.map(\.mrn), "MRN")
        assertUnique(panel.patients.flatMap(\.records).map(\.recordID), "record ID")
        assertUnique(panel.patients.flatMap(\.medications).map(\.rxID), "rx ID")
        assertUnique(panel.patients.flatMap(\.appointments).map(\.appointmentID), "appointment ID")
    }

    @MainActor
    func testEveryZoneAndDiagnosisCodeIsValid() throws {
        let panel = try DemoDataSeeder.loadPanel()
        let lifecycle = Set(DocumentationLifecycleStatus.allCases.map(\.rawValue))

        for (id, note) in allNotes(in: panel) {
            for zone in note.zones {
                XCTAssertNotNil(AnatomicalRegion.regionNames[zone], "\(id) uses unknown zone \(zone)")
            }
            XCTAssertNotNil(
                note.icd10Code.range(of: #"^[A-Z][0-9]{2}(\.[0-9A-Z]{1,4})?$"#, options: .regularExpression),
                "\(id) has a malformed ICD-10 code \(note.icd10Code)"
            )
            XCTAssertTrue(lifecycle.contains(note.documentationStatus), "\(id) has unknown documentation status \(note.documentationStatus)")
        }

        for series in panel.patients.flatMap(\.photoSeries) {
            XCTAssertNotNil(AnatomicalRegion.regionNames[series.zone], "Photo series \(series.name) uses unknown zone \(series.zone)")
        }
    }

    func testNarrativesUseTheAgeTokenNotALiteralAge() throws {
        let panel = try DemoDataSeeder.loadPanel()

        for (id, note) in allNotes(in: panel) {
            for text in note.narrativeFields {
                XCTAssertNil(
                    text.range(of: #"[0-9]+-year-old"#, options: .regularExpression),
                    "\(id) states a literal age. Use the {age} token: \(text)"
                )
            }
        }
    }

    func testTodayHasOneAppointmentPerPatientAndNotesOnlyForStartedVisits() throws {
        let panel = try DemoDataSeeder.loadPanel()

        for patient in panel.patients {
            XCTAssertEqual(patient.appointments.filter(\.isToday).count, 1, "\(patient.fullName) should be on today's schedule once")
        }

        let notedStatuses = Set(panel.patients.flatMap(\.appointments).filter { $0.todayNote != nil }.map(\.status))
        XCTAssertTrue(notedStatuses.isSubset(of: ["Completed", "Ready for Checkout", "In Exam"]))
    }

    /// A note written today is either a follow-up of a diagnosis already in the chart or
    /// belongs to a visit booked for a new problem.
    func testTodaysNotesContinueTheHistoryUnlessTheVisitIsForANewProblem() throws {
        let panel = try DemoDataSeeder.loadPanel()

        for patient in panel.patients {
            let historyCodes = Set(patient.records.map(\.note.icd10Code))
            for appointment in patient.appointments {
                guard let note = appointment.todayNote, !historyCodes.contains(note.icd10Code) else { continue }
                XCTAssertTrue(
                    appointment.reasonForVisit.lowercased().contains("new"),
                    "\(patient.fullName): today's note \(note.conditionName) (\(note.icd10Code)) has no history and \(appointment.appointmentID) is not a visit for a new problem"
                )
            }
        }
    }

    /// Clinic clinicians are always written in full. Anyone else is marked as an outside prescriber.
    func testClinicianNamesUseOneFullForm() throws {
        let panel = try DemoDataSeeder.loadPanel()
        let clinicians: Set<String> = ["Dr. Elizabeth Smith, MD", "Dr. Natalie Jones, MD"]

        for patient in panel.patients {
            XCTAssertTrue(clinicians.contains(patient.primaryClinician), "\(patient.mrn) primary clinician: \(patient.primaryClinician)")
            for appointment in patient.appointments {
                XCTAssertTrue(clinicians.contains(appointment.clinicianName), "\(appointment.appointmentID): \(appointment.clinicianName)")
            }
            for medication in patient.medications {
                XCTAssertTrue(
                    clinicians.contains(medication.writtenBy) || medication.writtenBy.contains("outside prescriber"),
                    "\(medication.rxID): \(medication.writtenBy)"
                )
            }
        }
        for (id, note) in allNotes(in: panel) {
            XCTAssertTrue(clinicians.contains(note.clinician), "\(id): \(note.clinician)")
        }
    }

    @MainActor
    func testInboxStartsFromTheFixture() throws {
        let panel = try DemoDataSeeder.loadPanel()
        let categories = Set(InboxView.MessageCategory.allCases.map(\.rawValue))

        for message in panel.messages {
            XCTAssertTrue(categories.contains(message.category), "Unknown IntraMail category \(message.category)")
        }
        XCTAssertEqual(InboxView.sampleMessages.map(\.subject), panel.messages.map(\.subject))
    }

    // MARK: - Seeding

    @MainActor
    func testSeedingMatchesTheFixtureAndPreparingTwiceAddsNothing() throws {
        let panel = try DemoDataSeeder.loadPanel()
        let now = Date()

        try prepare(now: now)
        try assertStoreMatches(panel)

        try prepare(now: now)
        try assertStoreMatches(panel)

        XCTAssertEqual(defaults.object(forKey: DemoDataSeeder.versionDefaultsKey) as? Int, panel.version)
        XCTAssertNotNil(defaults.string(forKey: DemoDataSeeder.timelineDayDefaultsKey))
    }

    @MainActor
    func testSeededTextHasAgesFilledInForTheDateOfEachRecord() throws {
        let panel = try DemoDataSeeder.loadPanel()
        try prepare(now: Date())

        let records = try fetchAll(LocalClinicalRecord.self)
        for record in records {
            let texts = [record.ccHPI, record.reviewOfSystems, record.examFindings, record.impressionsAndPlan,
                         record.patientInstructions, record.followUpPlan, record.carePlanSummary]
            for text in texts.compactMap({ $0 }) {
                XCTAssertFalse(text.contains("{age}"), "\(record.recordID) still contains the age token")
            }
        }

        // Every fixture history note opens with the age, so check it against the birth date by hand.
        for fixture in panel.patients {
            for recordFixture in fixture.records where recordFixture.note.ccHPI.hasPrefix("{age}-year-old") {
                let record = try XCTUnwrap(records.first { $0.recordID == recordFixture.recordID })
                let age = expectedAge(dateOfBirth: fixture.dateOfBirth, on: record.dateRecorded)
                XCTAssertTrue(
                    (record.ccHPI ?? "").hasPrefix("\(age)-year-old"),
                    "\(record.recordID) should open with age \(age): \(record.ccHPI ?? "")"
                )
            }
        }
    }

    @MainActor
    func testSeededEntitiesCarryDemoProvenanceAndDatesOfBirthKeepTheirDay() throws {
        let panel = try DemoDataSeeder.loadPanel()
        let now = Date()
        try prepare(now: now)

        let demoKind = ClinicalSourceKind.demoLocalCache.rawValue
        let system = DemoDataSeeder.sourceSystemName

        for patient in try fetchAll(PatientProfile.self) {
            XCTAssertEqual(patient.sourceKind, demoKind)
            XCTAssertEqual(patient.sourceSystemName, system)
            XCTAssertEqual(patient.sourceRecordIdentifier, patient.medicalRecordNumber)
            XCTAssertEqual(patient.sourceLastSyncedAt, now)
            XCTAssertFalse(patient.sourceOfTruth)

            let fixture = try XCTUnwrap(panel.patients.first { $0.mrn == patient.medicalRecordNumber })
            let born = calendar.dateComponents([.year, .month, .day, .hour], from: patient.dateOfBirth)
            XCTAssertEqual(String(format: "%04d-%02d-%02d", born.year ?? 0, born.month ?? 0, born.day ?? 0), fixture.dateOfBirth)
            XCTAssertEqual(born.hour, 12)
        }
        for medication in try fetchAll(LocalMedication.self) {
            XCTAssertEqual(medication.sourceKind, demoKind)
            XCTAssertEqual(medication.sourceSystemName, system)
            XCTAssertEqual(medication.sourceRecordIdentifier, medication.rxID)
            XCTAssertFalse(medication.sourceOfTruth)
        }
        for appointment in try fetchAll(Appointment.self) {
            XCTAssertEqual(appointment.sourceKind, demoKind)
            XCTAssertEqual(appointment.sourceSystemName, system)
            XCTAssertEqual(appointment.sourceRecordIdentifier, appointment.appointmentID)
            XCTAssertFalse(appointment.sourceOfTruth)
        }
        for record in try fetchAll(LocalClinicalRecord.self) {
            XCTAssertEqual(record.sourceKind, demoKind)
            XCTAssertEqual(record.sourceSystemName, system)
            XCTAssertEqual(record.sourceRecordIdentifier, record.recordID)
            XCTAssertFalse(record.sourceOfTruth)

            if record.documentationStatus == DocumentationLifecycleStatus.signed.rawValue {
                XCTAssertEqual(record.status, "Final")
                XCTAssertEqual(record.documentationSignedAt, record.dateRecorded)
                XCTAssertNotNil(record.providerSignature)
            } else {
                XCTAssertEqual(record.status, "Preliminary")
                XCTAssertNil(record.documentationSignedAt)
                XCTAssertNil(record.providerSignature)
            }
        }
        for photo in try fetchAll(ClinicalPhoto.self) {
            XCTAssertEqual(photo.sourceKind, ClinicalSourceKind.clinicianCaptured.rawValue)
            XCTAssertTrue(photo.sourceOfTruth)
            let size = (try? FileManager.default.attributesOfItem(atPath: photo.filePath)[.size] as? Int) ?? 0
            XCTAssertGreaterThan(size, 0, "No image was written for \(photo.sourceRecordIdentifier ?? photo.filePath)")
        }
    }

    @MainActor
    func testScheduleIsPlacedFromTheAnchorAndFutureVisitsAreDeterministic() throws {
        let panel = try DemoDataSeeder.loadPanel()
        let now = Date()
        try prepare(now: now)

        try assertSchedule(of: panel, isBuiltFor: now)
    }

    // MARK: - Timeline

    @MainActor
    func testPreparingAgainOnTheSameDayKeepsClinicianEdits() throws {
        let panel = try DemoDataSeeder.loadPanel()
        let now = Date()
        try prepare(now: now)

        let draftVisit = try XCTUnwrap(todayAppointments(in: panel).first { $0.todayNote?.documentationStatus == "draft" })
        let openVisit = try XCTUnwrap(todayAppointments(in: panel).first { $0.todayNote == nil })
        let noteID = DemoDataSeeder.todayNotePrefix + draftVisit.appointmentID

        // The clinician signs a draft and moves a waiting patient forward.
        let note = try XCTUnwrap(try storedRecord(noteID))
        XCTAssertEqual(note.documentationStatus, DocumentationLifecycleStatus.draft.rawValue)
        note.documentationStatus = DocumentationLifecycleStatus.signed.rawValue
        note.status = "Final"
        note.documentationSignedAt = now
        let appointment = try XCTUnwrap(try storedAppointment(openVisit.appointmentID))
        appointment.status = "No Show"
        try context.save()

        try prepare(now: now)

        let noteAfter = try XCTUnwrap(try storedRecord(noteID))
        XCTAssertEqual(noteAfter.documentationStatus, DocumentationLifecycleStatus.signed.rawValue)
        XCTAssertEqual(noteAfter.status, "Final")
        XCTAssertEqual(try XCTUnwrap(try storedAppointment(openVisit.appointmentID)).status, "No Show")
        try assertStoreMatches(panel)
    }

    @MainActor
    func testANewDayRebuildsTodaysScheduleFromTheFixture() throws {
        let panel = try DemoDataSeeder.loadPanel()
        let now = Date()
        try prepare(now: now)

        // Day one: every note for today is signed and every visit is completed.
        for visit in todayAppointments(in: panel) {
            try XCTUnwrap(try storedAppointment(visit.appointmentID)).status = "Completed"
            if visit.todayNote != nil {
                let note = try XCTUnwrap(try storedRecord(DemoDataSeeder.todayNotePrefix + visit.appointmentID))
                note.documentationStatus = DocumentationLifecycleStatus.signed.rawValue
                note.status = "Final"
            }
        }
        try context.save()

        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: now))
        try prepare(now: tomorrow)

        try assertStoreMatches(panel)
        try assertSchedule(of: panel, isBuiltFor: tomorrow)

        for visit in todayAppointments(in: panel) {
            let appointment = try XCTUnwrap(try storedAppointment(visit.appointmentID))
            XCTAssertEqual(appointment.status, visit.status, "\(visit.appointmentID) should be back at its fixture status")

            guard let noteFixture = visit.todayNote else { continue }
            let note = try XCTUnwrap(try storedRecord(DemoDataSeeder.todayNotePrefix + visit.appointmentID))
            XCTAssertEqual(note.documentationStatus, noteFixture.documentationStatus)
            XCTAssertEqual(note.status, noteFixture.isSigned ? "Final" : "Preliminary")
            XCTAssertTrue(calendar.isDate(note.dateRecorded, inSameDayAs: tomorrow), "\(note.recordID) should be dated on the new day")
        }

        // The history moves with the day, so "30 days ago" in a note stays 30 days ago.
        let startOfTomorrow = calendar.startOfDay(for: tomorrow)
        for recordFixture in panel.patients.flatMap(\.records) {
            let record = try XCTUnwrap(try storedRecord(recordFixture.recordID))
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: record.dateRecorded), to: startOfTomorrow).day
            XCTAssertEqual(days, recordFixture.daysAgo, "\(recordFixture.recordID) should be \(recordFixture.daysAgo) days before the new day")
        }
    }

    @MainActor
    func testResetRestoresTheFixtureAndLeavesOtherPatientsUntouched() throws {
        let panel = try DemoDataSeeder.loadPanel()
        let now = Date()
        try prepare(now: now)

        // A patient entered by hand, with one note, and an edit to the demo schedule.
        let manual = PatientProfile(
            medicalRecordNumber: "MANUAL-0001",
            firstName: "Pat",
            lastName: "Manual",
            dateOfBirth: now,
            gender: "Female"
        )
        context.insert(manual)
        let manualNote = LocalClinicalRecord(recordID: "MANUAL-REC-0001", dateRecorded: now, conditionName: "Manual note", status: "Preliminary")
        manualNote.patient = manual
        context.insert(manualNote)
        manual.clinicalRecords?.append(manualNote)

        let firstVisit = try XCTUnwrap(todayAppointments(in: panel).first)
        try XCTUnwrap(try storedAppointment(firstVisit.appointmentID)).status = "Cancelled"
        try context.save()

        try DemoDataSeeder.reset(context: context, now: now, calendar: calendar, defaults: defaults, photoDirectory: photoDirectory)

        let patients = try fetchAll(PatientProfile.self)
        XCTAssertEqual(patients.count, panel.patients.count + 1)
        let survivor = try XCTUnwrap(patients.first { $0.medicalRecordNumber == "MANUAL-0001" })
        XCTAssertEqual(survivor.sourceKind, ClinicalSourceKind.manualEntry.rawValue)
        XCTAssertEqual(survivor.clinicalRecords?.map(\.recordID), ["MANUAL-REC-0001"])

        XCTAssertEqual(try XCTUnwrap(try storedAppointment(firstVisit.appointmentID)).status, firstVisit.status)
        try assertStoreMatches(panel, otherPatients: 1, otherRecords: 1)
    }

    // MARK: - Anchor and status

    func testDemoAnchorStaysInsideClinicHours() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))

        func anchor(_ hour: Int, _ minute: Int) throws -> String {
            let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: hour, minute: minute, second: 42)))
            let result = DemoDataSeeder.demoAnchor(for: now, calendar: calendar)
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: result)
            return String(
                format: "%04d-%02d-%02d %02d:%02d:%02d",
                parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0
            )
        }

        XCTAssertEqual(try anchor(8, 10), "2026-10-07 14:00:00")
        XCTAssertEqual(try anchor(11, 37), "2026-10-07 11:30:00")
        XCTAssertEqual(try anchor(16, 5), "2026-10-07 14:00:00")

        XCTAssertEqual(try anchor(10, 0), "2026-10-07 10:00:00")
        XCTAssertEqual(try anchor(14, 59), "2026-10-07 14:45:00")
        XCTAssertEqual(try anchor(8, 50), "2026-10-07 14:00:00")
        XCTAssertEqual(try anchor(23, 59), "2026-10-07 14:00:00")
    }

    @MainActor
    func testResolvedStatusFollowsDocumentationAndNeverTheClock() throws {
        let now = Date()
        let startOfToday = Calendar.current.startOfDay(for: now)
        let lateToday = try XCTUnwrap(Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: now))
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: lateToday))

        let patient = PatientProfile(firstName: "Status", lastName: "Check", dateOfBirth: now, gender: "Female")
        context.insert(patient)

        func addAppointment(_ id: String, at time: Date, status: String) -> Appointment {
            let appointment = Appointment(appointmentID: id, scheduledTime: time, reasonForVisit: "Follow-up", status: status)
            appointment.patient = patient
            context.insert(appointment)
            patient.appointments?.append(appointment)
            return appointment
        }

        // Long past and still to come, both today.
        let roomedEarly = addAppointment("STATUS-1", at: startOfToday.addingTimeInterval(60), status: "Roomed")
        let roomedLate = addAppointment("STATUS-2", at: lateToday, status: "Roomed")
        let checkedInEarly = addAppointment("STATUS-3", at: startOfToday.addingTimeInterval(60), status: "Checked In")
        let scheduledEarly = addAppointment("STATUS-4", at: startOfToday.addingTimeInterval(60), status: "Scheduled")
        let inExam = addAppointment("STATUS-5", at: startOfToday.addingTimeInterval(60), status: "In Exam")
        let scheduledTomorrow = addAppointment("STATUS-6", at: tomorrow, status: "Scheduled")
        try context.save()

        // No note: the stored status is shown whatever the time of day.
        XCTAssertEqual(roomedEarly.resolvedStatus, "Roomed")
        XCTAssertEqual(roomedLate.resolvedStatus, "Roomed")
        XCTAssertEqual(checkedInEarly.resolvedStatus, "Checked In")
        XCTAssertEqual(scheduledEarly.resolvedStatus, "Scheduled")

        // A draft note dated today moves a roomed patient into the exam.
        let note = LocalClinicalRecord(recordID: "STATUS-NOTE", dateRecorded: now, conditionName: "Rosacea", status: "Preliminary")
        note.patient = patient
        context.insert(note)
        patient.clinicalRecords?.append(note)
        try context.save()

        XCTAssertEqual(note.documentationStatus, DocumentationLifecycleStatus.draft.rawValue)
        XCTAssertEqual(roomedEarly.resolvedStatus, "In Exam")
        XCTAssertEqual(roomedLate.resolvedStatus, "In Exam")
        XCTAssertEqual(scheduledTomorrow.resolvedStatus, "Scheduled", "A note written today says nothing about tomorrow's visit")

        note.documentationStatus = DocumentationLifecycleStatus.reviewed.rawValue
        XCTAssertEqual(roomedEarly.resolvedStatus, "Ready for Checkout")

        note.documentationStatus = DocumentationLifecycleStatus.signed.rawValue
        XCTAssertEqual(roomedEarly.resolvedStatus, "Completed")
        XCTAssertEqual(inExam.resolvedStatus, "In Exam", "An explicit workflow status wins over the note")
    }

    // MARK: - Helpers

    @MainActor
    private func prepare(now: Date) throws {
        try DemoDataSeeder.prepare(context: context, now: now, calendar: calendar, defaults: defaults, photoDirectory: photoDirectory)
    }

    @MainActor
    private func fetchAll<Model: PersistentModel>(_ type: Model.Type) throws -> [Model] {
        try context.fetch(FetchDescriptor<Model>())
    }

    @MainActor
    private func storedRecord(_ id: String) throws -> LocalClinicalRecord? {
        try fetchAll(LocalClinicalRecord.self).first { $0.recordID == id }
    }

    @MainActor
    private func storedAppointment(_ id: String) throws -> Appointment? {
        try fetchAll(Appointment.self).first { $0.appointmentID == id }
    }

    private func todayAppointments(in panel: DemoPanel) -> [DemoAppointment] {
        panel.patients.flatMap(\.appointments).filter(\.isToday)
    }

    private func allNotes(in panel: DemoPanel) -> [(id: String, note: DemoNote)] {
        var notes: [(id: String, note: DemoNote)] = []
        for patient in panel.patients {
            for record in patient.records {
                notes.append((id: record.recordID, note: record.note))
            }
            for appointment in patient.appointments {
                if let note = appointment.todayNote {
                    notes.append((id: DemoDataSeeder.todayNotePrefix + appointment.appointmentID, note: note))
                }
            }
        }
        return notes
    }

    private func assertUnique(_ identifiers: [String], _ label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Set(identifiers).count, identifiers.count, "Duplicate \(label) in the fixture", file: file, line: line)
    }

    /// Age in whole years from a "yyyy-MM-dd" birth date, worked out from the date parts.
    private func expectedAge(dateOfBirth: String, on date: Date) -> Int {
        let born = dateOfBirth.split(separator: "-").compactMap { Int($0) }
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        guard born.count == 3, let year = day.year, let month = day.month, let dayOfMonth = day.day else { return -1 }
        let hadBirthday = (month, dayOfMonth) >= (born[1], born[2])
        return year - born[0] - (hadBirthday ? 0 : 1)
    }

    /// The store holds exactly what the fixture describes, in total and per patient.
    @MainActor
    private func assertStoreMatches(
        _ panel: DemoPanel,
        otherPatients: Int = 0,
        otherRecords: Int = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let todayNoteCount = panel.patients.flatMap(\.appointments).filter { $0.todayNote != nil }.count
        let recordCount = panel.patients.flatMap(\.records).count + todayNoteCount
        let photoCount = panel.patients.flatMap(\.photoSeries).flatMap(\.images).count

        let patients = try fetchAll(PatientProfile.self)
        XCTAssertEqual(patients.count, panel.patients.count + otherPatients, "patients", file: file, line: line)
        XCTAssertEqual(try fetchAll(LocalMedication.self).count, panel.patients.flatMap(\.medications).count, "medications", file: file, line: line)
        XCTAssertEqual(try fetchAll(LocalClinicalRecord.self).count, recordCount + otherRecords, "records", file: file, line: line)
        XCTAssertEqual(try fetchAll(Appointment.self).count, panel.patients.flatMap(\.appointments).count, "appointments", file: file, line: line)
        XCTAssertEqual(try fetchAll(ClinicalPhoto.self).count, photoCount, "photos", file: file, line: line)

        for fixture in panel.patients {
            guard let patient = patients.first(where: { $0.medicalRecordNumber == fixture.mrn }) else {
                XCTFail("\(fixture.mrn) is missing from the store", file: file, line: line)
                continue
            }
            let noteCount = fixture.appointments.filter { $0.todayNote != nil }.count
            XCTAssertEqual(patient.medications?.count, fixture.medications.count, "\(fixture.mrn) medications", file: file, line: line)
            XCTAssertEqual(patient.clinicalRecords?.count, fixture.records.count + noteCount, "\(fixture.mrn) records", file: file, line: line)
            XCTAssertEqual(patient.appointments?.count, fixture.appointments.count, "\(fixture.mrn) appointments", file: file, line: line)
            XCTAssertEqual(patient.clinicalPhotos?.count, fixture.photoSeries.flatMap(\.images).count, "\(fixture.mrn) photos", file: file, line: line)
        }
    }

    /// Today's visits sit at the anchor plus their offset. Future visits sit a fixed number of
    /// days ahead at the fixture's time.
    @MainActor
    private func assertSchedule(of panel: DemoPanel, isBuiltFor now: Date, file: StaticString = #filePath, line: UInt = #line) throws {
        let anchor = DemoDataSeeder.demoAnchor(for: now, calendar: calendar)
        let startOfDay = calendar.startOfDay(for: now)

        for fixture in panel.patients.flatMap(\.appointments) {
            let appointment = try XCTUnwrap(try storedAppointment(fixture.appointmentID), file: file, line: line)

            if let offsetMinutes = fixture.offsetMinutes {
                let expected = anchor.addingTimeInterval(Double(offsetMinutes) * 60)
                XCTAssertEqual(
                    appointment.scheduledTime.timeIntervalSinceReferenceDate,
                    expected.timeIntervalSinceReferenceDate,
                    accuracy: 1,
                    "\(fixture.appointmentID) time",
                    file: file,
                    line: line
                )
                XCTAssertTrue(calendar.isDate(appointment.scheduledTime, inSameDayAs: now), "\(fixture.appointmentID) should be today", file: file, line: line)
            } else {
                let parts = calendar.dateComponents([.hour, .minute], from: appointment.scheduledTime)
                let days = calendar.dateComponents([.day], from: startOfDay, to: calendar.startOfDay(for: appointment.scheduledTime)).day
                XCTAssertEqual(days, fixture.daysFromNow, "\(fixture.appointmentID) day", file: file, line: line)
                XCTAssertEqual(parts.hour, fixture.hour, "\(fixture.appointmentID) hour", file: file, line: line)
                XCTAssertEqual(parts.minute, fixture.minute, "\(fixture.appointmentID) minute", file: file, line: line)
            }
        }
    }
}
