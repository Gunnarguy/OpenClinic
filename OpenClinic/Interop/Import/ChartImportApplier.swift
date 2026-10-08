//
//  ChartImportApplier.swift
//  OpenClinic
//
//  Writes one patient's imported record into the local store.
//
//  The applier is the only place imported values become chart rows. It never
//  deletes: a row the server stopped returning is marked as removed at the
//  source and kept, and a resource type whose search failed or was cut short is
//  left exactly as it was. Every imported row keeps the server and resource it
//  came from, and the source resource itself is stored beside it.
//

import Foundation
import SwiftData

/// What an import changed, by kind of record.
nonisolated struct ChartImportSummary: Sendable {
    struct Line: Sendable, Identifiable {
        let label: String
        let received: Int
        let created: Int
        let updated: Int
        let removedAtSource: Int

        var id: String { label }
    }

    let patientLocalID: UUID
    let patientName: String
    let createdNewPatient: Bool
    let serverBase: String
    let lines: [Line]
    let sourceResourceCount: Int
    let warnings: [String]
    let importedAt: Date

    var totalReceived: Int { lines.reduce(0) { $0 + $1.received } }
}

enum ChartImportError: LocalizedError {
    case ambiguousPatient(String)
    /// Every search for the patient's record failed, which is what an expired sign-in looks like.
    case nothingCouldBeRead

    var errorDescription: String? {
        switch self {
        case .nothingCouldBeRead:
            return "None of the patient's record could be read from the server. Nothing was imported."
        case .ambiguousPatient(let detail):
            return "More than one local chart matches this patient (\(detail)). Nothing was imported."
        }
    }
}

@MainActor
struct ChartImportApplier {
    let context: ModelContext
    var now: Date = .now

    init(context: ModelContext, now: Date = .now) {
        self.context = context
        self.now = now
    }

    /// Applies the chart and saves. On any error the context is rolled back and nothing changes.
    @discardableResult
    func apply(_ chart: ImportedChart, sourceResources: [FHIRR4RawResource]) throws -> ChartImportSummary {
        do {
            let summary = try applyWithoutSaving(chart, sourceResources: sourceResources)
            try context.save()
            return summary
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: - Apply

    private func applyWithoutSaving(_ chart: ImportedChart, sourceResources: [FHIRR4RawResource]) throws -> ChartImportSummary {
        let serverBase = chart.patient.source.serverBase
        var warnings = chart.warnings

        let (patient, createdNewPatient) = try upsertPatient(chart.patient, warnings: &warnings)

        // A type whose search failed or was cut short, or that held a resource that could not be
        // decoded, proves nothing about what is missing.
        let incomplete = Set(chart.truncatedTypes).union(chart.failedTypes).union(chart.unreadableTypes)
        func complete(_ resourceType: String) -> Bool { !incomplete.contains(resourceType) }

        var lines: [ChartImportSummary.Line] = []

        lines.append(sync(
            label: "Problems", incoming: chart.problems, id: { $0.source.qualifiedID },
            existing: serverRows(patient.problems, serverBase: serverBase), canMarkRemoved: complete("Condition"),
            make: { item in ChartProblem(qualifiedID: item.source.qualifiedID, display: item.code.display) },
            update: { row, item in
                row.display = item.code.display
                row.codeSystem = item.code.system
                row.code = item.code.code
                row.clinicalStatus = item.clinicalStatus
                row.verificationStatus = item.verificationStatus
                row.category = item.category
                row.onsetDate = item.onset
                row.abatementDate = item.abatement
                row.onsetPrecision = item.onsetPrecision?.rawValue
                row.abatementPrecision = item.abatementPrecision?.rawValue
                row.recordedDate = item.recorded
                row.encounterReference = item.encounterReference
                stamp(row, source: item.source, patient: patient)
            }
        ))

        lines.append(sync(
            label: "Medications", incoming: chart.medications, id: { $0.source.qualifiedID },
            existing: serverRows(patient.medications, serverBase: serverBase), canMarkRemoved: complete("MedicationRequest"),
            make: { item in
                LocalMedication(
                    rxID: item.source.qualifiedID,
                    medicationName: item.code.display,
                    writtenBy: item.requester ?? Self.notRecorded,
                    writtenDate: item.authoredOn ?? item.source.lastUpdated ?? now,
                    quantityInfo: item.dosageText ?? Self.notRecorded,
                    refills: item.refills ?? 0
                )
            },
            update: { row, item in
                row.medicationName = item.code.display
                row.writtenBy = item.requester ?? Self.notRecorded
                row.writtenDate = item.authoredOn ?? item.source.lastUpdated ?? row.writtenDate
                row.startDate = item.authoredOn
                row.quantityInfo = item.dosageText ?? Self.notRecorded
                row.refills = item.refills ?? 0
                row.route = item.route
                row.indication = item.reason
                row.status = Self.medicationStatusLabel(item.status)
                stamp(row, source: item.source, patient: patient)
            }
        ))
        let undatedMedications = chart.medications.filter { $0.authoredOn == nil }.count
        if undatedMedications > 0 {
            warnings.append("\(undatedMedications) medication order(s) have no authored date at the source. They show the server's last-updated time instead.")
        }

        lines.append(sync(
            label: "Allergies", incoming: chart.allergies, id: { $0.source.qualifiedID },
            existing: serverRows(patient.chartAllergies, serverBase: serverBase), canMarkRemoved: complete("AllergyIntolerance"),
            make: { item in ChartAllergy(qualifiedID: item.source.qualifiedID, substance: item.substance.display) },
            update: { row, item in
                row.substance = item.substance.display
                row.codeSystem = item.substance.system
                row.code = item.substance.code
                row.clinicalStatus = item.clinicalStatus
                row.verificationStatus = item.verificationStatus
                row.criticality = item.criticality
                row.categories = item.categories
                row.reactions = item.reactions
                row.recordedDate = item.recorded
                stamp(row, source: item.source, patient: patient)
            }
        ))

        lines.append(sync(
            label: "Observations", incoming: chart.observations, id: { $0.source.qualifiedID },
            existing: serverRows(patient.observations, serverBase: serverBase), canMarkRemoved: complete("Observation"),
            make: { item in ChartObservation(qualifiedID: item.source.qualifiedID, category: item.category, display: item.code.display) },
            update: { row, item in
                row.category = item.category
                row.display = item.code.display
                row.codeSystem = item.code.system
                row.code = item.code.code
                row.effectiveDate = item.effective
                row.issuedDate = item.issued
                row.status = item.status
                row.setValue(item.value)
                row.components = item.components
                row.interpretation = item.interpretation
                row.referenceRange = item.referenceRange
                row.encounterReference = item.encounterReference
                stamp(row, source: item.source, patient: patient)
            }
        ))

        lines.append(sync(
            label: "Encounters", incoming: chart.encounters, id: { $0.source.qualifiedID },
            existing: serverRows(patient.encounters, serverBase: serverBase), canMarkRemoved: complete("Encounter"),
            make: { item in ChartEncounter(qualifiedID: item.source.qualifiedID, typeDisplay: item.type) },
            update: { row, item in
                row.typeDisplay = item.type
                row.encounterClass = item.classCode
                row.reason = item.reason
                row.status = item.status
                row.startDate = item.start
                row.endDate = item.end
                row.practitioner = item.practitioner
                row.location = item.location
                row.serviceProvider = item.serviceProvider
                stamp(row, source: item.source, patient: patient)
            }
        ))

        lines.append(sync(
            label: "Procedures", incoming: chart.procedures, id: { $0.source.qualifiedID },
            existing: serverRows(patient.procedures, serverBase: serverBase), canMarkRemoved: complete("Procedure"),
            make: { item in ChartProcedure(qualifiedID: item.source.qualifiedID, display: item.code.display) },
            update: { row, item in
                row.display = item.code.display
                row.codeSystem = item.code.system
                row.code = item.code.code
                row.status = item.status
                row.performedStart = item.performedStart
                row.performedEnd = item.performedEnd
                row.performedPrecision = item.performedPrecision?.rawValue
                row.reason = item.reason
                row.encounterReference = item.encounterReference
                stamp(row, source: item.source, patient: patient)
            }
        ))

        lines.append(sync(
            label: "Immunizations", incoming: chart.immunizations, id: { $0.source.qualifiedID },
            existing: serverRows(patient.immunizations, serverBase: serverBase), canMarkRemoved: complete("Immunization"),
            make: { item in ChartImmunization(qualifiedID: item.source.qualifiedID, vaccine: item.vaccine.display) },
            update: { row, item in
                row.vaccine = item.vaccine.display
                row.codeSystem = item.vaccine.system
                row.code = item.vaccine.code
                row.status = item.status
                row.occurrenceDate = item.occurrence
                row.occurrencePrecision = item.occurrencePrecision?.rawValue
                row.primarySource = item.primarySource
                stamp(row, source: item.source, patient: patient)
            }
        ))

        lines.append(sync(
            label: "Reports", incoming: chart.reports, id: { $0.source.qualifiedID },
            existing: serverRows(patient.diagnosticReports, serverBase: serverBase), canMarkRemoved: complete("DiagnosticReport"),
            make: { item in ChartDiagnosticReport(qualifiedID: item.source.qualifiedID, display: item.code.display) },
            update: { row, item in
                row.display = item.code.display
                row.codeSystem = item.code.system
                row.code = item.code.code
                row.category = item.category
                row.status = item.status
                row.effectiveDate = item.effective
                row.issuedDate = item.issued
                row.conclusion = item.conclusion
                row.resultReferences = item.resultReferences
                row.presentedText = item.presentedText
                stamp(row, source: item.source, patient: patient)
            }
        ))

        lines.append(sync(
            label: "Documents", incoming: chart.documents, id: { $0.source.qualifiedID },
            existing: serverRows(patient.documents, serverBase: serverBase), canMarkRemoved: complete("DocumentReference"),
            make: { item in ChartDocument(qualifiedID: item.source.qualifiedID, typeDisplay: item.type) },
            update: { row, item in
                row.typeDisplay = item.type
                row.summary = item.summary
                row.documentDate = item.date
                row.author = item.author
                row.status = item.status
                row.contentType = item.contentType
                row.text = item.text
                stamp(row, source: item.source, patient: patient)
            }
        ))

        lines.append(sync(
            label: "Appointments", incoming: chart.appointments, id: { $0.source.qualifiedID },
            existing: serverRows(patient.appointments, serverBase: serverBase), canMarkRemoved: complete("Appointment"),
            make: { item in
                Appointment(
                    appointmentID: item.source.qualifiedID,
                    scheduledTime: item.start ?? item.source.lastUpdated ?? now,
                    reasonForVisit: item.summary ?? item.reason ?? "Appointment",
                    status: Self.appointmentStatusLabel(item.status)
                )
            },
            update: { row, item in
                // The time is the server's. It is never moved to today.
                row.scheduledTime = item.start ?? row.scheduledTime
                row.reasonForVisit = item.summary ?? item.reason ?? "Appointment"
                row.status = Self.appointmentStatusLabel(item.status)
                row.durationMinutes = item.minutesDuration ?? Self.minutes(from: item.start, to: item.end)
                row.clinicianName = item.practitioner
                stamp(row, source: item.source, patient: patient)
            }
        ))
        let undatedAppointments = chart.appointments.filter { $0.start == nil }.count
        if undatedAppointments > 0 {
            warnings.append("\(undatedAppointments) appointment(s) have no start time at the source.")
        }

        refreshDerivedFields(of: patient, allergiesWereRead: complete("AllergyIntolerance"))

        let sourceCount = storeSourceResources(
            sourceResources,
            serverBase: serverBase,
            patientResourceID: chart.patient.source.resourceID,
            completeTypes: Set(FHIRR4ChartFetcher.patientResourceTypes).subtracting(incomplete)
        )

        context.insert(AuditEvent(
            timestamp: now,
            action: .recordImported,
            patientID: patient.id,
            entityType: "FHIRImport",
            entityID: chart.patient.source.qualifiedID,
            detail: "\(sourceCount) resources from \(serverBase)"
        ))

        return ChartImportSummary(
            patientLocalID: patient.id,
            patientName: patient.fullName,
            createdNewPatient: createdNewPatient,
            serverBase: serverBase,
            lines: lines,
            sourceResourceCount: sourceCount,
            warnings: warnings,
            importedAt: now
        )
    }

    // MARK: - Patient

    private func upsertPatient(_ imported: ImportedPatient, warnings: inout [String]) throws -> (PatientProfile, Bool) {
        let serverBase = imported.source.serverBase
        let resourceID = imported.source.resourceID
        let smartKind = ClinicalSourceKind.smartFHIR.rawValue
        let allPatients = try context.fetch(FetchDescriptor<PatientProfile>())

        // The same resource on the same server is the same patient. Older imports stored the
        // server URL with or without a trailing slash, so both forms match.
        var matches = allPatients.filter { existing in
            existing.sourceKind == smartKind
                && existing.sourceRecordIdentifier == resourceID
                && Self.sameServer(existing.sourceSystemName, serverBase)
        }
        if matches.isEmpty, let system = imported.mrnSystem, !system.isEmpty, !imported.mrn.isEmpty {
            matches = allPatients.filter { $0.medicalRecordNumber == imported.mrn && $0.medicalRecordNumberSystem == system }
        }
        guard matches.count <= 1 else {
            throw ChartImportError.ambiguousPatient("\(matches.count) charts for resource \(resourceID)")
        }

        let birthDate: Date
        if let date = imported.birthDate {
            birthDate = date
        } else {
            birthDate = matches.first?.dateOfBirth ?? Self.placeholderBirthDate
            warnings.append("The source has no date of birth for this patient.")
        }

        let patient: PatientProfile
        let created: Bool
        if let existing = matches.first {
            patient = existing
            created = false
        } else {
            patient = PatientProfile(
                medicalRecordNumber: uniqueMRN(imported, among: allPatients),
                medicalRecordNumberSystem: imported.mrnSystem,
                firstName: imported.givenName,
                lastName: imported.familyName,
                dateOfBirth: birthDate,
                gender: imported.sex
            )
            context.insert(patient)
            created = true
        }

        patient.firstName = imported.givenName
        patient.lastName = imported.familyName
        patient.dateOfBirth = birthDate
        patient.gender = imported.sex
        patient.medicalRecordNumberSystem = imported.mrnSystem
        patient.deceasedDate = imported.deceasedDate
        patient.isDeceased = imported.isDeceased
        if imported.birthDate != nil {
            patient.dateOfBirthPrecision = imported.birthDatePrecision?.rawValue
        } else if created || patient.dateOfBirth == Self.placeholderBirthDate {
            // No date of birth at the source: the chart says so, and shows no date and no age.
            patient.dateOfBirthPrecision = ChartDateText.unknown
        }
        patient.deceasedDatePrecision = imported.deceasedPrecision?.rawValue
        // The record number follows the source like every other value. A chart made before
        // government numbers were left out could hold one as its record number.
        if !created {
            let wanted = imported.mrn.isEmpty ? resourceID : imported.mrn
            if patient.medicalRecordNumber != wanted, !patient.medicalRecordNumber.hasPrefix("\(wanted) (") {
                patient.medicalRecordNumber = uniqueMRN(imported, among: allPatients.filter { $0 !== patient })
            }
        }
        patient.phone = imported.phone
        patient.addressLine = imported.addressLine
        patient.city = imported.city
        patient.state = imported.state
        patient.postalCode = imported.postalCode
        patient.preferredLanguage = imported.language
        patient.maritalStatus = imported.maritalStatus
        patient.sourceKind = smartKind
        patient.sourceSystemName = serverBase
        patient.sourceRecordIdentifier = resourceID
        patient.sourceLastSyncedAt = now
        patient.sourceOfTruth = true
        return (patient, created)
    }

    /// The MRN is unique in the local store. Two servers can issue the same number, so a
    /// colliding one is qualified with the resource id instead of overwriting a chart.
    private func uniqueMRN(_ imported: ImportedPatient, among patients: [PatientProfile]) -> String {
        Self.uniqueRecordNumber(
            imported.mrn.isEmpty ? imported.source.resourceID : imported.mrn,
            resourceID: imported.source.resourceID,
            taken: Set(patients.map(\.medicalRecordNumber)))
    }

    private static func uniqueRecordNumber(_ candidate: String, resourceID: String, taken: Set<String>) -> String {
        guard taken.contains(candidate) else { return candidate }
        let qualified = "\(candidate) (\(resourceID.prefix(8)))"
        guard taken.contains(qualified) else { return qualified }
        var count = 2
        while taken.contains("\(qualified) \(count)") { count += 1 }
        return "\(qualified) \(count)"
    }

    /// What `dateOfBirth` holds when the source gave none. It is never shown: see `hasKnownBirthDate`.
    private static let placeholderBirthDate = Date(timeIntervalSince1970: 0)

    /// Recomputes the patient-level fields other views read from the rows just synced.
    private func refreshDerivedFields(of patient: PatientProfile, allergiesWereRead: Bool) {
        if allergiesWereRead {
            let rows = (patient.chartAllergies ?? []).filter { !$0.isRemovedAtSource }
            let current = rows.filter(\.isCurrent).map(\.substance)
            if !current.isEmpty {
                patient.allergies = Array(Set(current)).sorted()
            } else if rows.contains(where: \.isNoKnownAllergyAssertion) {
                patient.allergies = ["No known allergies"]
            } else {
                // Nothing recorded is not the same as no known allergies.
                patient.allergies = []
            }
        }

        let smokingStatuses = (patient.observations ?? [])
            .filter { $0.code == ObservationCode.smokingStatus && !$0.isRemovedAtSource }
            .sorted { ($0.effectiveDate ?? .distantPast) > ($1.effectiveDate ?? .distantPast) }
        if let latest = smokingStatuses.first {
            patient.isSmoker = Self.isCurrentSmoker(latest)
        }
    }

    private static func isCurrentSmoker(_ observation: ChartObservation) -> Bool {
        let text = (observation.valueText ?? "").lowercased()
        if text.contains("never") || text.contains("former") || text.contains("ex-smoker") || text.contains("non-smoker") {
            return false
        }
        return text.contains("smoker") || text.contains("smokes")
    }

    // MARK: - Rows

    /// Rows of one relationship that came from this server.
    private func serverRows<Row: ServerSyncedRow>(_ rows: [Row]?, serverBase: String) -> [Row] {
        let smartKind = ClinicalSourceKind.smartFHIR.rawValue
        return (rows ?? []).filter { $0.sourceKind == smartKind && Self.sameServer($0.sourceSystemName, serverBase) }
    }

    private func sync<Item, Row: ServerSyncedRow & PersistentModel>(
        label: String,
        incoming: [Item],
        id: (Item) -> String,
        existing: [Row],
        canMarkRemoved: Bool,
        make: (Item) -> Row,
        update: (Row, Item) -> Void
    ) -> ChartImportSummary.Line {
        // Keyed by the id with its server address in one spelling, so a row stored when the address
        // was typed another way ("HTTPS://Host:443/fhir") is found again and not imported twice.
        var existingByID: [String: Row] = [:]
        for row in existing {
            let key = Self.respelled(row.qualifiedID)
            // An earlier version that imported one server under two spellings left two rows for one
            // resource, the older marked as removed. The current one is the match; the other stays as it is.
            if let held = existingByID[key], !held.isRemovedAtSource || row.isRemovedAtSource { continue }
            existingByID[key] = row
        }

        var created = 0
        var updated = 0
        var seen = Set<String>()

        for item in incoming {
            let key = Self.respelled(id(item))
            guard seen.insert(key).inserted else { continue }
            if let row = existingByID[key] {
                update(row, item)
                row.isRemovedAtSource = false
                updated += 1
            } else {
                let row = make(item)
                context.insert(row)
                update(row, item)
                created += 1
            }
        }

        var removed = 0
        if canMarkRemoved {
            for row in existing where !seen.contains(Self.respelled(row.qualifiedID)) && !row.isRemovedAtSource {
                row.isRemovedAtSource = true
                row.sourceLastSyncedAt = now
                removed += 1
            }
        }

        return ChartImportSummary.Line(label: label, received: incoming.count, created: created, updated: updated, removedAtSource: removed)
    }

    private func stamp(_ row: any ServerSyncedRow, source: ImportedSource, patient: PatientProfile) {
        row.sourceKind = ClinicalSourceKind.smartFHIR.rawValue
        row.sourceSystemName = source.serverBase
        row.sourceRecordIdentifier = source.resourceID
        row.sourceLastSyncedAt = now
        row.sourceOfTruth = true
        if row.patient !== patient {
            row.patient = patient
        }
    }

    // MARK: - Source resources

    /// Stores each resource as received and returns how many were written.
    private func storeSourceResources(
        _ resources: [FHIRR4RawResource],
        serverBase: String,
        patientResourceID: String,
        completeTypes: Set<String>
    ) -> Int {
        // An earlier version that imported one server under two spellings left two stored copies of
        // each resource. Both are refreshed, so a row finds a current record whichever id it holds.
        let existing = (try? context.fetch(FetchDescriptor<FHIRResourceRecord>())) ?? []
        var existingByKey: [String: [FHIRResourceRecord]] = [:]
        for record in existing where Self.sameServer(record.serverBase, serverBase) && record.patientResourceID == patientResourceID {
            existingByKey[Self.respelled(record.qualifiedID), default: []].append(record)
        }

        var seen = Set<String>()
        for received in resources {
            // Stored as the server sent it, except that a Patient's government numbers lose their values.
            let resource = FHIRR4ChartMapper.resourceForStorage(received)
            let qualifiedID = "\(serverBase)/\(resource.resourceType)/\(resource.id)"
            let key = Self.respelled(qualifiedID)
            guard seen.insert(key).inserted else { continue }
            if let records = existingByKey[key] {
                for record in records {
                    if record.json != resource.json {
                        record.json = resource.json
                    }
                    record.versionID = resource.versionID
                    record.lastUpdated = resource.lastUpdated
                    record.fetchedAt = now
                    record.isRemovedAtSource = false
                }
            } else {
                context.insert(FHIRResourceRecord(
                    qualifiedID: qualifiedID,
                    serverBase: serverBase,
                    resourceType: resource.resourceType,
                    resourceID: resource.id,
                    versionID: resource.versionID,
                    lastUpdated: resource.lastUpdated,
                    patientResourceID: patientResourceID,
                    json: resource.json,
                    fetchedAt: now
                ))
            }
        }

        for (key, records) in existingByKey where !seen.contains(key) {
            for record in records where completeTypes.contains(record.resourceType) {
                record.isRemovedAtSource = true
            }
        }
        return seen.count
    }

    // MARK: - Records stored by an earlier version

    /// Brings charts an earlier version imported up to what an import stores now:
    /// a stored Patient resource loses its government numbers, a chart whose record number was one
    /// of them gets the number an import would choose, and a chart whose source gave no date of birth
    /// stops showing the placeholder date as one.
    ///
    /// Returns how many changes were made, or nil when the store could not be read or saved (the
    /// caller then tries again at the next launch). Each stored Patient resource is parsed, so the
    /// app runs this once and not at every launch.
    @discardableResult
    static func repairChartsFromEarlierVersions(in context: ModelContext) -> Int? {
        let patientType = "Patient"
        let descriptor = FetchDescriptor<FHIRResourceRecord>(predicate: #Predicate { $0.resourceType == patientType })
        guard let records = try? context.fetch(descriptor) else { return nil }
        guard !records.isEmpty else { return 0 }
        guard let all = try? context.fetch(FetchDescriptor<PatientProfile>()) else { return nil }
        let smartKind = ClinicalSourceKind.smartFHIR.rawValue

        var changed = 0
        for record in records {
            guard let raw = try? FHIRR4RawResource(data: record.json) else { continue }
            let patient = all.first {
                $0.sourceKind == smartKind && $0.sourceRecordIdentifier == record.resourceID
                    && sameServer($0.sourceSystemName, record.serverBase)
            }

            if let patient, patient.dateOfBirthPrecision == nil, patient.dateOfBirth == placeholderBirthDate,
               !statesABirthDate(raw) {
                patient.dateOfBirthPrecision = ChartDateText.unknown
                changed += 1
            }

            let numbers = FHIRR4ChartMapper.governmentNumberValues(in: raw)
            guard !numbers.isEmpty else { continue }
            if let patient,
               numbers.contains(where: { patient.medicalRecordNumber == $0 || patient.medicalRecordNumber.hasPrefix("\($0) (") }),
               let imported = try? FHIRR4ChartMapper.patient(raw, serverBase: record.serverBase) {
                patient.medicalRecordNumber = uniqueRecordNumber(
                    imported.mrn.isEmpty ? record.resourceID : imported.mrn,
                    resourceID: record.resourceID,
                    taken: Set(all.filter { $0 !== patient }.map(\.medicalRecordNumber)))
                patient.medicalRecordNumberSystem = imported.mrnSystem
            }
            record.json = FHIRR4ChartMapper.resourceForStorage(raw).json
            changed += 1
        }
        if changed > 0 {
            do {
                try context.save()
            } catch {
                return nil
            }
        }
        return changed
    }

    private static func statesABirthDate(_ raw: FHIRR4RawResource) -> Bool {
        guard let object = (try? JSONSerialization.jsonObject(with: raw.json)) as? [String: Any],
              let text = object["birthDate"] as? String else {
            return false
        }
        return !text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Small conversions

    private static let notRecorded = "Not recorded at source"

    private static func sameServer(_ stored: String?, _ serverBase: String) -> Bool {
        guard let stored else { return false }
        // One spelling of the address (scheme and host in lower case, no default port, no trailing
        // slash), and the path compared without regard to case as earlier imports did.
        return FHIRR4Client.normalizedBase(stored).lowercased() == FHIRR4Client.normalizedBase(serverBase).lowercased()
    }

    /// `<server base>/<type>/<id>` as a key for matching: the server base in the client's one
    /// spelling and in lower case, as `sameServer` compares it. A FHIR id holds no slash, so the last
    /// two parts are always the type and the id. Only used to find a row; stored ids are not rewritten.
    static func respelled(_ qualifiedID: String) -> String {
        let parts = qualifiedID.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return qualifiedID }
        let base = parts.dropLast(2).joined(separator: "/")
        return "\(FHIRR4Client.normalizedBase(base).lowercased())/\(parts[parts.count - 2])/\(parts[parts.count - 1])"
    }

    private static func minutes(from start: Date?, to end: Date?) -> Int? {
        guard let start, let end, end > start else { return nil }
        return Int(end.timeIntervalSince(start) / 60)
    }

    /// FHIR medicationrequest-status as the chart words it.
    static func medicationStatusLabel(_ status: String) -> String {
        switch status.lowercased() {
        case "active": return "Active"
        case "on-hold": return "On hold"
        case "cancelled": return "Cancelled"
        case "completed": return "Completed"
        case "stopped": return "Stopped"
        case "draft": return "Draft"
        case "entered-in-error": return "Entered in error"
        default: return "Unknown"
        }
    }

    /// FHIR appointmentstatus as the schedule words it.
    static func appointmentStatusLabel(_ status: String) -> String {
        switch status.lowercased() {
        case "proposed", "pending", "waitlist": return "Pending"
        case "booked": return "Scheduled"
        case "arrived": return "Arrived"
        case "checked-in": return "Checked In"
        case "fulfilled": return "Completed"
        case "noshow": return "No Show"
        case "cancelled": return "Cancelled"
        default: return status.capitalized
        }
    }
}
