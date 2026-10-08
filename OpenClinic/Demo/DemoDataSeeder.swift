//
//  DemoDataSeeder.swift
//  OpenClinic
//
//  Seeds the synthetic demo panel from Resources/Demo/DemoPanel.json and keeps
//  its timeline on today's date. The fixture is the single source of truth:
//  nothing clinical is written in code here.
//
//  Rules the seeder keeps:
//  - Only demo-sourced data is ever deleted. Imported or manually entered
//    patients are left alone.
//  - Within one calendar day a status or a note is never changed after it has
//    been seeded, so a clinician's edits and signatures survive a relaunch.
//  - On a new day the schedule starts over: today's statuses and notes come
//    from the fixture again and the history moves with the date, so the
//    intervals written in the notes stay true.
//

import Foundation
import SwiftData
import os

@MainActor
enum DemoDataSeeder {
    nonisolated static let sourceSystemName = "OpenClinic Demo Dataset"

    /// UserDefaults key for the fixture version that was last seeded.
    nonisolated static let versionDefaultsKey = "demoPanelVersion"
    /// UserDefaults key for the day (yyyy-MM-dd) the timeline was last built for.
    nonisolated static let timelineDayDefaultsKey = "demoTimelineDay"
    /// Record ID prefix of the notes that belong to today's schedule.
    nonisolated static let todayNotePrefix = "DEMO-TODAY-"

    private nonisolated static let fixtureName = "DemoPanel"
    private nonisolated static let photoSourceSystemName = "OpenClinic Capture Workspace"
    /// Clinic time given to past visits, prescriptions and photos.
    private nonisolated static let historicalHour = 10

    private static var demoKind: String { ClinicalSourceKind.demoLocalCache.rawValue }

    // MARK: - Public API

    /// Decodes the bundled fixture. Throws if it is missing or malformed.
    nonisolated static func loadPanel(bundle: Bundle = .main) throws -> DemoPanel {
        let url = bundle.url(forResource: fixtureName, withExtension: "json")
            ?? bundle.url(forResource: fixtureName, withExtension: "json", subdirectory: "Demo")
            ?? bundle.url(forResource: fixtureName, withExtension: "json", subdirectory: "Resources/Demo")
        guard let url else { throw DemoPanelError.fixtureMissing }

        let data = try Data(contentsOf: url)
        let panel = try JSONDecoder().decode(DemoPanel.self, from: data)
        try panel.validate()
        return panel
    }

    /// One call for app launch: seeds when the store has no demo data, reseeds when the fixture
    /// version changed, then brings today's timeline up to date. Safe to call repeatedly.
    static func prepare(context: ModelContext, now: Date = .now, calendar: Calendar = .current, defaults: UserDefaults = .standard) throws {
        try prepare(context: context, now: now, calendar: calendar, defaults: defaults, photoDirectory: defaultPhotoDirectory())
    }

    /// Deletes every demo-sourced entity (sourceKind == ClinicalSourceKind.demoLocalCache.rawValue,
    /// plus photos of demo patients) and seeds again.
    static func reset(context: ModelContext, now: Date = .now, calendar: Calendar = .current, defaults: UserDefaults = .standard) throws {
        try reset(context: context, now: now, calendar: calendar, defaults: defaults, photoDirectory: defaultPhotoDirectory())
    }

    /// The demo "clinic now": today's date at the current hour, minute rounded down to
    /// :00/:15/:30/:45. If the hour is before 10 or at/after 15, it is 14:00, so the schedule
    /// built around it always falls inside clinic hours.
    nonisolated static func demoAnchor(for now: Date, calendar: Calendar) -> Date {
        let hour = calendar.component(.hour, from: now)
        let isClinicHour = hour >= 10 && hour < 15
        let anchorHour = isClinicHour ? hour : 14
        let anchorMinute = isClinicHour ? (calendar.component(.minute, from: now) / 15) * 15 : 0
        let startOfDay = calendar.startOfDay(for: now)
        return calendar.date(bySettingHour: anchorHour, minute: anchorMinute, second: 0, of: startOfDay) ?? now
    }

    // MARK: - Entry points with an explicit photo folder

    /// Same as `prepare(context:now:calendar:defaults:)`, with the folder the placeholder photos
    /// are written to. Tests pass a temporary folder; nil skips the photo series.
    static func prepare(context: ModelContext, now: Date, calendar: Calendar, defaults: UserDefaults, photoDirectory: URL?) throws {
        let panel = try loadPanel()
        let hasDemoData = try !fetchDemoPatients(in: context).isEmpty
        let storedVersion = defaults.object(forKey: versionDefaultsKey) as? Int

        guard hasDemoData, storedVersion == panel.version else {
            try rebuild(panel, context: context, now: now, calendar: calendar, defaults: defaults, photoDirectory: photoDirectory)
            return
        }

        let today = dayStamp(for: now, calendar: calendar)
        let isNewDay = defaults.string(forKey: timelineDayDefaultsKey) != today
        try refreshTimeline(panel, context: context, now: now, calendar: calendar, isNewDay: isNewDay)
        defaults.set(today, forKey: timelineDayDefaultsKey)
    }

    /// Same as `reset(context:now:calendar:defaults:)`, with the folder the placeholder photos
    /// are written to.
    static func reset(context: ModelContext, now: Date, calendar: Calendar, defaults: UserDefaults, photoDirectory: URL?) throws {
        let panel = try loadPanel()
        try rebuild(panel, context: context, now: now, calendar: calendar, defaults: defaults, photoDirectory: photoDirectory)
    }

    // MARK: - Seeding

    private static func rebuild(
        _ panel: DemoPanel,
        context: ModelContext,
        now: Date,
        calendar: Calendar,
        defaults: UserDefaults,
        photoDirectory: URL?
    ) throws {
        try purgeDemoData(in: context)
        try seed(panel, context: context, now: now, calendar: calendar, photoDirectory: photoDirectory)
        defaults.set(panel.version, forKey: versionDefaultsKey)
        defaults.set(dayStamp(for: now, calendar: calendar), forKey: timelineDayDefaultsKey)
        AppLogger.data.info("Demo panel v\(panel.version) seeded: \(panel.patients.count) patients")
    }

    /// Deletes demo patients with everything attached to them, then any demo-sourced row left over.
    private static func purgeDemoData(in context: ModelContext) throws {
        let kind = demoKind

        for patient in try fetchDemoPatients(in: context) {
            for photo in patient.clinicalPhotos ?? [] {
                context.delete(photo)
            }
            // The cascade rules remove the patient's records, medications and appointments.
            context.delete(patient)
        }
        try context.save()

        for record in try context.fetch(FetchDescriptor<LocalClinicalRecord>()) where record.sourceKind == kind {
            context.delete(record)
        }
        for medication in try context.fetch(FetchDescriptor<LocalMedication>()) where medication.sourceKind == kind {
            context.delete(medication)
        }
        for appointment in try context.fetch(FetchDescriptor<Appointment>()) where appointment.sourceKind == kind {
            context.delete(appointment)
        }
        for problem in try context.fetch(FetchDescriptor<ChartProblem>()) where problem.sourceKind == kind {
            context.delete(problem)
        }
        for allergy in try context.fetch(FetchDescriptor<ChartAllergy>()) where allergy.sourceKind == kind {
            context.delete(allergy)
        }
        for observation in try context.fetch(FetchDescriptor<ChartObservation>()) where observation.sourceKind == kind {
            context.delete(observation)
        }
        try context.save()
    }

    private static func seed(_ panel: DemoPanel, context: ModelContext, now: Date, calendar: Calendar, photoDirectory: URL?) throws {
        let timeline = Timeline(now: now, calendar: calendar)
        if let photoDirectory {
            try? FileManager.default.createDirectory(at: photoDirectory, withIntermediateDirectories: true)
        }

        for fixture in panel.patients {
            let dateOfBirth = try birthDate(of: fixture, calendar: calendar)
            let patient = PatientProfile(
                medicalRecordNumber: fixture.mrn,
                firstName: fixture.firstName,
                lastName: fixture.lastName,
                dateOfBirth: dateOfBirth,
                gender: fixture.gender,
                isSmoker: fixture.isSmoker,
                primaryClinician: fixture.primaryClinician,
                preferredPharmacy: fixture.preferredPharmacy,
                carePlanSummary: fixture.carePlanSummary,
                allergies: fixture.allergies,
                riskFlags: fixture.riskFlags,
                emergencyContactName: fixture.emergencyContactName,
                emergencyContactPhone: fixture.emergencyContactPhone,
                bloodType: fixture.bloodType,
                sourceKind: demoKind,
                sourceSystemName: sourceSystemName,
                sourceRecordIdentifier: fixture.mrn,
                sourceLastSyncedAt: now,
                sourceOfTruth: false
            )
            context.insert(patient)

            var medications: [LocalMedication] = []
            for medicationFixture in fixture.medications {
                medications.append(makeMedication(medicationFixture, timeline: timeline))
            }

            var records: [LocalClinicalRecord] = []
            for recordFixture in fixture.records {
                let date = timeline.date(dayOffset: -recordFixture.daysAgo)
                records.append(makeRecord(
                    id: recordFixture.recordID,
                    note: recordFixture.note,
                    date: date,
                    age: timeline.age(bornOn: dateOfBirth, at: date),
                    now: now
                ))
            }

            var appointments: [Appointment] = []
            for appointmentFixture in fixture.appointments {
                let appointment = makeAppointment(appointmentFixture, timeline: timeline)
                appointments.append(appointment)
                if let note = appointmentFixture.todayNote {
                    records.append(makeTodayRecord(for: appointmentFixture, note: note, dateOfBirth: dateOfBirth, timeline: timeline))
                }
            }

            let photos = makePhotos(for: fixture, timeline: timeline, directory: photoDirectory)

            let chartRows = makeChartRows(for: fixture, timeline: timeline)
            for problem in chartRows.problems { context.insert(problem) }
            for allergy in chartRows.allergies { context.insert(allergy) }
            for observation in chartRows.observations { context.insert(observation) }
            patient.problems = chartRows.problems
            patient.chartAllergies = chartRows.allergies
            patient.observations = chartRows.observations

            for medication in medications { context.insert(medication) }
            for record in records { context.insert(record) }
            for appointment in appointments { context.insert(appointment) }
            for photo in photos { context.insert(photo) }

            patient.medications = medications
            patient.clinicalRecords = records
            patient.appointments = appointments
            patient.clinicalPhotos = photos
        }

        try context.save()
    }

    // MARK: - Daily timeline

    /// Moves the schedule to `now`. Times are cosmetic and are refreshed on every call. Statuses,
    /// today's notes and the dates of the history are rebuilt from the fixture only when
    /// `isNewDay` is true.
    private static func refreshTimeline(_ panel: DemoPanel, context: ModelContext, now: Date, calendar: Calendar, isNewDay: Bool) throws {
        let timeline = Timeline(now: now, calendar: calendar)
        let kind = demoKind

        let demoAppointments = try context.fetch(FetchDescriptor<Appointment>()).filter { $0.sourceKind == kind }
        let appointmentsByID = Dictionary(demoAppointments.map { ($0.appointmentID, $0) }, uniquingKeysWith: { first, _ in first })

        for fixture in panel.patients {
            for appointmentFixture in fixture.appointments {
                guard let appointment = appointmentsByID[appointmentFixture.appointmentID] else { continue }
                let time = timeline.time(for: appointmentFixture)
                if appointment.scheduledTime != time {
                    appointment.scheduledTime = time
                }
                if isNewDay, appointment.status != appointmentFixture.status {
                    appointment.status = appointmentFixture.status
                }
            }
        }

        // Problems, vital signs and results are read-only in the demo, so their dates follow the
        // timeline on every call: today's vitals stay at their appointment's time.
        let chartPatients = try fetchDemoPatients(in: context)
        let chartPatientsByMRN = Dictionary(chartPatients.map { ($0.medicalRecordNumber, $0) }, uniquingKeysWith: { first, _ in first })
        for fixture in panel.patients {
            guard let patient = chartPatientsByMRN[fixture.mrn] else { continue }
            redateChartRows(of: patient, fixture: fixture, timeline: timeline)
        }

        if isNewDay {
            // Yesterday's schedule notes go first, and the delete is saved before their IDs are used again.
            let staleNotes = try context.fetch(FetchDescriptor<LocalClinicalRecord>()).filter { $0.recordID.hasPrefix(todayNotePrefix) }
            for note in staleNotes {
                context.delete(note)
            }
            try context.save()

            let demoPatients = try fetchDemoPatients(in: context)
            let patientsByMRN = Dictionary(demoPatients.map { ($0.medicalRecordNumber, $0) }, uniquingKeysWith: { first, _ in first })

            for fixture in panel.patients {
                guard let patient = patientsByMRN[fixture.mrn] else { continue }
                reanchorHistory(of: patient, fixture: fixture, timeline: timeline)

                for appointmentFixture in fixture.appointments {
                    guard let note = appointmentFixture.todayNote,
                          appointmentsByID[appointmentFixture.appointmentID] != nil else { continue }
                    let record = makeTodayRecord(for: appointmentFixture, note: note, dateOfBirth: patient.dateOfBirth, timeline: timeline)
                    context.insert(record)
                    record.patient = patient
                }
            }
            AppLogger.data.info("Demo timeline moved to a new day: statuses and today's notes rebuilt from the fixture")
        }

        try context.save()
    }

    /// Re-dates the seeded history of one patient relative to the timeline's day. Documentation
    /// statuses are left as they are.
    private static func reanchorHistory(of patient: PatientProfile, fixture: DemoPatient, timeline: Timeline) {
        let kind = demoKind

        let records = (patient.clinicalRecords ?? []).filter { $0.sourceKind == kind }
        for recordFixture in fixture.records {
            guard let record = records.first(where: { $0.recordID == recordFixture.recordID }) else { continue }
            let date = timeline.date(dayOffset: -recordFixture.daysAgo)
            if record.documentationSignedAt == record.dateRecorded {
                record.documentationSignedAt = date
            }
            record.dateRecorded = date
            refreshAgeDependentText(of: record, from: recordFixture.note, age: timeline.age(bornOn: patient.dateOfBirth, at: date))
        }

        let medications = (patient.medications ?? []).filter { $0.sourceKind == kind }
        for medicationFixture in fixture.medications {
            guard let medication = medications.first(where: { $0.rxID == medicationFixture.rxID }) else { continue }
            applyDates(of: medicationFixture, to: medication, timeline: timeline)
        }

        let photos = patient.clinicalPhotos ?? []
        for series in fixture.photoSeries {
            for frame in series.images {
                let fileName = photoFileName(mrn: fixture.mrn, series: series, frame: frame)
                guard let photo = photos.first(where: { $0.sourceRecordIdentifier == fileName }) else { continue }
                photo.captureDate = timeline.date(dayOffset: -frame.daysAgo)
            }
        }
    }

    // MARK: - Entity builders

    private static func makeMedication(_ fixture: DemoMedication, timeline: Timeline) -> LocalMedication {
        let medication = LocalMedication(
            rxID: fixture.rxID,
            medicationName: fixture.medicationName,
            writtenBy: fixture.writtenBy,
            writtenDate: timeline.date(dayOffset: -fixture.writtenDaysAgo),
            quantityInfo: fixture.quantityInfo,
            refills: fixture.refills,
            genericName: fixture.genericName,
            dose: fixture.dose,
            route: fixture.route,
            frequency: fixture.frequency,
            indication: fixture.indication,
            status: fixture.status,
            pharmacyName: fixture.pharmacyName,
            safetyNotes: fixture.safetyNotes,
            sourceKind: demoKind,
            sourceSystemName: sourceSystemName,
            sourceRecordIdentifier: fixture.rxID,
            sourceLastSyncedAt: timeline.now,
            sourceOfTruth: false
        )
        applyDates(of: fixture, to: medication, timeline: timeline)
        return medication
    }

    private static func applyDates(of fixture: DemoMedication, to medication: LocalMedication, timeline: Timeline) {
        medication.writtenDate = timeline.date(dayOffset: -fixture.writtenDaysAgo)
        medication.startDate = timeline.date(dayOffset: -(fixture.startDaysAgo ?? fixture.writtenDaysAgo))
        medication.lastFilledDate = fixture.lastFilledDaysAgo.map { timeline.date(dayOffset: -$0) }
        medication.nextRefillEligibleDate = fixture.nextRefillInDays.map { timeline.date(dayOffset: $0) }
    }

    private static func makeRecord(id: String, note: DemoNote, date: Date, age: Int, now: Date) -> LocalClinicalRecord {
        LocalClinicalRecord(
            recordID: id,
            dateRecorded: date,
            conditionName: note.conditionName,
            status: note.isSigned ? "Final" : "Preliminary",
            isHiddenFromPortal: false,
            visitType: note.visitType,
            severity: note.severity,
            ccHPI: render(note.ccHPI, age: age),
            reviewOfSystems: note.reviewOfSystems.map { render($0, age: age) },
            examFindings: render(note.examFindings, age: age),
            impressionsAndPlan: render(note.impressionsAndPlan, age: age),
            affectedAnatomicalZones: note.zones,
            providerSignature: note.isSigned ? note.clinician : nil,
            patientInstructions: render(note.patientInstructions, age: age),
            followUpPlan: render(note.followUpPlan, age: age),
            recommendedOrders: note.recommendedOrders,
            carePlanSummary: render(note.carePlanSummary, age: age),
            icd10Code: note.icd10Code,
            documentationStatus: note.documentationStatus,
            documentationSignedAt: note.isSigned ? date : nil,
            sourceKind: demoKind,
            sourceSystemName: sourceSystemName,
            sourceRecordIdentifier: id,
            sourceLastSyncedAt: now,
            sourceOfTruth: false
        )
    }

    /// The note for a visit on today's schedule, dated at the appointment time.
    private static func makeTodayRecord(for appointment: DemoAppointment, note: DemoNote, dateOfBirth: Date, timeline: Timeline) -> LocalClinicalRecord {
        let date = timeline.time(for: appointment)
        return makeRecord(
            id: todayNotePrefix + appointment.appointmentID,
            note: note,
            date: date,
            age: timeline.age(bornOn: dateOfBirth, at: date),
            now: timeline.now
        )
    }

    private static func makeAppointment(_ fixture: DemoAppointment, timeline: Timeline) -> Appointment {
        Appointment(
            appointmentID: fixture.appointmentID,
            scheduledTime: timeline.time(for: fixture),
            reasonForVisit: fixture.reasonForVisit,
            status: fixture.status,
            encounterType: fixture.encounterType,
            clinicianName: fixture.clinicianName,
            location: fixture.location,
            durationMinutes: fixture.durationMinutes,
            checkInStatus: fixture.checkInStatus,
            prepInstructions: fixture.prepInstructions,
            linkedDiagnoses: fixture.linkedDiagnoses,
            sourceKind: demoKind,
            sourceSystemName: sourceSystemName,
            sourceRecordIdentifier: fixture.appointmentID,
            sourceLastSyncedAt: timeline.now,
            sourceOfTruth: false
        )
    }

    /// Draws the placeholder images and returns their photo rows. Photos keep the provenance of
    /// a clinician capture, as photos taken in the app do.
    private static func makePhotos(for fixture: DemoPatient, timeline: Timeline, directory: URL?) -> [ClinicalPhoto] {
        guard let directory else { return [] }

        var photos: [ClinicalPhoto] = []
        for series in fixture.photoSeries {
            for frame in series.images {
                let fileName = photoFileName(mrn: fixture.mrn, series: series, frame: frame)
                let fileURL = directory.appendingPathComponent(fileName)
                if !DemoPhotoRenderer.writeJPEG(for: frame, to: fileURL) {
                    // The file name carries the MRN, so only the series is logged.
                    AppLogger.data.error("Could not write a demo photo for series \(series.name, privacy: .public), \(frame.daysAgo) days ago")
                }
                photos.append(ClinicalPhoto(
                    captureDate: timeline.date(dayOffset: -frame.daysAgo),
                    anatomicalRegion: series.zone,
                    notes: "\(frame.notes) (\(series.title))",
                    filePath: fileURL.path,
                    linkedRecordID: frame.linkedRecordID,
                    sourceKind: ClinicalSourceKind.clinicianCaptured.rawValue,
                    sourceSystemName: photoSourceSystemName,
                    sourceRecordIdentifier: fileName,
                    sourceLastSyncedAt: timeline.now,
                    sourceOfTruth: true
                ))
            }
        }
        return photos
    }

    // MARK: - Problems, allergies, vital signs and results

    private struct ChartRows {
        var problems: [ChartProblem] = []
        var allergies: [ChartAllergy] = []
        var observations: [ChartObservation] = []
    }

    private static func chartRowID(_ mrn: String, _ kind: String, _ id: String) -> String {
        "demo/\(mrn)/\(kind)/\(id)"
    }

    private static func makeChartRows(for fixture: DemoPatient, timeline: Timeline) -> ChartRows {
        var rows = ChartRows()

        for problem in fixture.problems {
            rows.problems.append(ChartProblem(
                qualifiedID: chartRowID(fixture.mrn, "problem", problem.problemID),
                display: problem.display,
                codeSystem: ChartCodeSystem.icd10CM,
                code: problem.icd10Code,
                clinicalStatus: problem.clinicalStatus,
                verificationStatus: problem.verificationStatus,
                category: "problem-list-item",
                onsetDate: timeline.date(dayOffset: -problem.onsetDaysAgo),
                abatementDate: problem.abatementDaysAgo.map { timeline.date(dayOffset: -$0) },
                recordedDate: timeline.date(dayOffset: -problem.onsetDaysAgo),
                sourceKind: demoKind,
                sourceSystemName: sourceSystemName,
                sourceRecordIdentifier: problem.problemID,
                sourceLastSyncedAt: timeline.now,
                sourceOfTruth: false
            ))
        }

        // One structured row per entry of the patient's allergy list, so both forms always agree.
        for (index, entry) in fixture.allergies.enumerated() {
            let isNegative = ClinicalLexicon.isNoKnownAllergyEntry(entry)
            rows.allergies.append(ChartAllergy(
                qualifiedID: chartRowID(fixture.mrn, "allergy", String(index + 1)),
                substance: entry,
                codeSystem: isNegative ? ChartCodeSystem.snomed : nil,
                code: isNegative ? "716186003" : nil,
                clinicalStatus: isNegative ? nil : "active",
                verificationStatus: isNegative ? nil : "confirmed",
                sourceKind: demoKind,
                sourceSystemName: sourceSystemName,
                sourceRecordIdentifier: "\(fixture.mrn)-ALG-\(index + 1)",
                sourceLastSyncedAt: timeline.now,
                sourceOfTruth: false
            ))
        }

        for set in fixture.vitals {
            let date = vitalsDate(set, fixture: fixture, timeline: timeline)
            for vital in vitalObservations(set) {
                let observation = ChartObservation(
                    qualifiedID: chartRowID(fixture.mrn, "vitals", "\(set.vitalsID)-\(vital.suffix)"),
                    category: "vital-signs",
                    display: vital.display,
                    codeSystem: ChartCodeSystem.loinc,
                    code: vital.code,
                    effectiveDate: date,
                    issuedDate: date,
                    components: vital.components,
                    sourceKind: demoKind,
                    sourceSystemName: sourceSystemName,
                    sourceRecordIdentifier: "\(set.vitalsID)-\(vital.suffix)",
                    sourceLastSyncedAt: timeline.now,
                    sourceOfTruth: false
                )
                observation.setValue(vital.value)
                rows.observations.append(observation)
            }
        }

        for lab in fixture.labs {
            let date = timeline.date(dayOffset: -lab.daysAgo, hour: 8)
            let observation = ChartObservation(
                qualifiedID: chartRowID(fixture.mrn, "lab", lab.labID),
                category: "laboratory",
                display: lab.display,
                codeSystem: lab.loinc == nil ? nil : ChartCodeSystem.loinc,
                code: lab.loinc,
                effectiveDate: date,
                issuedDate: date,
                interpretation: lab.interpretation,
                referenceRange: lab.referenceRange,
                sourceKind: demoKind,
                sourceSystemName: sourceSystemName,
                sourceRecordIdentifier: lab.labID,
                sourceLastSyncedAt: timeline.now,
                sourceOfTruth: false
            )
            if let value = lab.value {
                observation.setValue(.quantity(value, unit: lab.unit))
            } else if let text = lab.text {
                observation.setValue(.text(text))
            }
            rows.observations.append(observation)
        }

        return rows
    }

    /// A vital set taken today carries its appointment's time; a past one, the clinic's usual hour.
    private static func vitalsDate(_ set: DemoVitalSet, fixture: DemoPatient, timeline: Timeline) -> Date {
        if let appointmentID = set.appointmentID,
           let appointment = fixture.appointments.first(where: { $0.appointmentID == appointmentID }) {
            return timeline.time(for: appointment)
        }
        return timeline.date(dayOffset: -(set.daysAgo ?? 0))
    }

    private struct VitalObservation {
        let suffix: String
        let display: String
        let code: String
        let value: ImportedValue?
        var components: [ImportedComponent] = []
    }

    /// The observations one vital set becomes. Blood pressure is a panel with two components.
    private static func vitalObservations(_ set: DemoVitalSet) -> [VitalObservation] {
        var result: [VitalObservation] = []
        if let systolic = set.systolic, let diastolic = set.diastolic {
            result.append(VitalObservation(
                suffix: "bp", display: "Blood pressure", code: ObservationCode.bloodPressurePanel, value: nil,
                components: [
                    ImportedComponent(
                        code: ImportedCode(system: ChartCodeSystem.loinc, code: ObservationCode.systolic, display: "Systolic blood pressure"),
                        value: .quantity(Double(systolic), unit: "mm[Hg]")
                    ),
                    ImportedComponent(
                        code: ImportedCode(system: ChartCodeSystem.loinc, code: ObservationCode.diastolic, display: "Diastolic blood pressure"),
                        value: .quantity(Double(diastolic), unit: "mm[Hg]")
                    ),
                ]
            ))
        }
        if let heartRate = set.heartRate {
            result.append(VitalObservation(suffix: "hr", display: "Heart rate", code: ObservationCode.heartRate, value: .quantity(Double(heartRate), unit: "/min")))
        }
        if let temperature = set.temperatureF {
            result.append(VitalObservation(suffix: "temp", display: "Body temperature", code: ObservationCode.bodyTemperature, value: .quantity(temperature, unit: "[degF]")))
        }
        if let saturation = set.oxygenSaturation {
            result.append(VitalObservation(suffix: "spo2", display: "Oxygen saturation", code: ObservationCode.oxygenSaturation, value: .quantity(Double(saturation), unit: "%")))
        }
        if let weight = set.weightKg {
            result.append(VitalObservation(suffix: "wt", display: "Body weight", code: ObservationCode.bodyWeight, value: .quantity(weight, unit: "kg")))
        }
        if let height = set.heightCm {
            result.append(VitalObservation(suffix: "ht", display: "Body height", code: ObservationCode.bodyHeight, value: .quantity(height, unit: "cm")))
        }
        if let pain = set.painScore {
            result.append(VitalObservation(suffix: "pain", display: "Pain severity, 0 to 10", code: ObservationCode.painSeverity, value: .quantity(Double(pain), unit: "{score}")))
        }
        return result
    }

    /// Moves the demo's problems, vital signs and results to the timeline's day.
    private static func redateChartRows(of patient: PatientProfile, fixture: DemoPatient, timeline: Timeline) {
        let kind = demoKind

        let problems = (patient.problems ?? []).filter { $0.sourceKind == kind }
        for problemFixture in fixture.problems {
            let id = chartRowID(fixture.mrn, "problem", problemFixture.problemID)
            guard let problem = problems.first(where: { $0.qualifiedID == id }) else { continue }
            problem.onsetDate = timeline.date(dayOffset: -problemFixture.onsetDaysAgo)
            problem.recordedDate = problem.onsetDate
            problem.abatementDate = problemFixture.abatementDaysAgo.map { timeline.date(dayOffset: -$0) }
        }

        let observations = (patient.observations ?? []).filter { $0.sourceKind == kind }
        var observationsByID: [String: ChartObservation] = [:]
        for observation in observations { observationsByID[observation.qualifiedID] = observation }

        for set in fixture.vitals {
            let date = vitalsDate(set, fixture: fixture, timeline: timeline)
            for vital in vitalObservations(set) {
                let id = chartRowID(fixture.mrn, "vitals", "\(set.vitalsID)-\(vital.suffix)")
                guard let observation = observationsByID[id], observation.effectiveDate != date else { continue }
                observation.effectiveDate = date
                observation.issuedDate = date
            }
        }
        for lab in fixture.labs {
            let date = timeline.date(dayOffset: -lab.daysAgo, hour: 8)
            guard let observation = observationsByID[chartRowID(fixture.mrn, "lab", lab.labID)], observation.effectiveDate != date else { continue }
            observation.effectiveDate = date
            observation.issuedDate = date
        }
    }

    // MARK: - Helpers

    private static func fetchDemoPatients(in context: ModelContext) throws -> [PatientProfile] {
        let kind = demoKind
        return try context.fetch(FetchDescriptor<PatientProfile>()).filter { $0.sourceKind == kind }
    }

    private static func defaultPhotoDirectory() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("ClinicalPhotos", isDirectory: true)
    }

    private static func photoFileName(mrn: String, series: DemoPhotoSeries, frame: DemoPhotoFrame) -> String {
        "\(mrn)_\(series.name)_\(frame.daysAgo).jpg"
    }

    /// A date of birth is a calendar date, so it is stored at local noon and never shows a day off.
    private static func birthDate(of fixture: DemoPatient, calendar: Calendar) throws -> Date {
        guard var components = fixture.birthDateComponents else {
            throw DemoPanelError.invalid("\(fixture.mrn) has a date of birth that is not yyyy-MM-dd")
        }
        components.hour = 12
        guard let date = calendar.date(from: components) else {
            throw DemoPanelError.invalid("\(fixture.mrn) has a date of birth the calendar cannot represent")
        }
        return date
    }

    private static func render(_ text: String, age: Int) -> String {
        text.replacingOccurrences(of: DemoNote.ageToken, with: String(age))
    }

    /// Rewrites the fields whose fixture text depends on the patient's age. Other text stays as stored.
    private static func refreshAgeDependentText(of record: LocalClinicalRecord, from note: DemoNote, age: Int) {
        func rendered(_ template: String?) -> String? {
            guard let template, template.contains(DemoNote.ageToken) else { return nil }
            return render(template, age: age)
        }
        if let text = rendered(note.ccHPI) { record.ccHPI = text }
        if let text = rendered(note.reviewOfSystems) { record.reviewOfSystems = text }
        if let text = rendered(note.examFindings) { record.examFindings = text }
        if let text = rendered(note.impressionsAndPlan) { record.impressionsAndPlan = text }
        if let text = rendered(note.patientInstructions) { record.patientInstructions = text }
        if let text = rendered(note.followUpPlan) { record.followUpPlan = text }
        if let text = rendered(note.carePlanSummary) { record.carePlanSummary = text }
    }

    private static func dayStamp(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: - Relative dates

    /// Turns the fixture's relative dates into real ones for the day of `now`.
    private struct Timeline {
        let now: Date
        let calendar: Calendar
        let startOfToday: Date
        let anchor: Date

        init(now: Date, calendar: Calendar) {
            self.now = now
            self.calendar = calendar
            self.startOfToday = calendar.startOfDay(for: now)
            self.anchor = DemoDataSeeder.demoAnchor(for: now, calendar: calendar)
        }

        /// A time `dayOffset` days from today, negative for the past.
        func date(dayOffset: Int, hour: Int = DemoDataSeeder.historicalHour, minute: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) ?? startOfToday
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        func time(for appointment: DemoAppointment) -> Date {
            if let offsetMinutes = appointment.offsetMinutes {
                return calendar.date(byAdding: .minute, value: offsetMinutes, to: anchor) ?? anchor
            }
            return date(
                dayOffset: appointment.daysFromNow ?? 0,
                hour: appointment.hour ?? DemoDataSeeder.historicalHour,
                minute: appointment.minute ?? 0
            )
        }

        /// Age in whole years on the calendar day of `date`.
        func age(bornOn dateOfBirth: Date, at date: Date) -> Int {
            let birthDay = calendar.startOfDay(for: dateOfBirth)
            let day = calendar.startOfDay(for: date)
            return max(calendar.dateComponents([.year], from: birthDay, to: day).year ?? 0, 0)
        }
    }
}
