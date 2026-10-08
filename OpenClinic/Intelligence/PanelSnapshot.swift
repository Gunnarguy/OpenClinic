//
//  PanelSnapshot.swift
//  OpenClinic
//
//  A value copy of the chart facts that panel questions are computed from.
//  The cohort engine reads this snapshot and never touches SwiftData, so the
//  same code runs on the main actor, in tests and in an evaluation run.
//

import Foundation

nonisolated struct PanelSnapshot: Sendable {
    var patients: [PatientFacts]
    var capturedAt: Date

    init(patients: [PatientFacts], capturedAt: Date = .now) {
        self.patients = patients
        self.capturedAt = capturedAt
    }
}

nonisolated struct PatientFacts: Sendable, Identifiable {
    let id: UUID
    let mrn: String
    let name: String
    let age: Int
    let sex: String
    let isSmoker: Bool
    let allergies: [String]
    let riskFlags: [String]
    let diagnoses: [DiagnosisFact]
    let medications: [MedicationFact]
    let appointments: [AppointmentFact]

    /// Allergy entries that name an allergen. "No known drug allergies" is a
    /// charted negative, not an allergy.
    var documentedAllergies: [String] {
        allergies.filter { !ClinicalLexicon.isNoKnownAllergyEntry($0) }
    }
}

nonisolated struct DiagnosisFact: Sendable, Hashable {
    let recordID: String
    let name: String
    let icd10: String?
    let date: Date
    /// `DocumentationLifecycleStatus` raw value: draft, reviewed or signed.
    let documentationStatus: String
    /// True for a clinical note, false for a problem-list entry. Only notes can await a signature.
    var isNote: Bool = true

    var isSigned: Bool {
        documentationStatus.lowercased() == "signed"
    }
}

nonisolated struct MedicationFact: Sendable, Hashable {
    let rxID: String
    let name: String
    let genericName: String?
    let status: String?
    let route: String?

    /// A medication counts as current unless its status says it ended.
    /// A missing status is treated as current, as the chart views do.
    var isActive: Bool {
        guard let status = status?.trimmingCharacters(in: .whitespaces).lowercased(), !status.isEmpty else {
            return true
        }
        return !["completed", "stopped", "discontinued", "cancelled", "canceled", "entered-in-error", "ended"].contains(status)
    }

    /// Lowercased brand and generic names joined, for term matching.
    var searchText: String {
        [name, genericName ?? ""].joined(separator: " ").lowercased()
    }

    /// True when the product is applied to the skin or eye, so it is not systemic therapy.
    var isTopical: Bool {
        let route = (route ?? "").lowercased()
        if ["topical", "ophthalmic", "otic", "cutaneous"].contains(where: route.contains) { return true }
        if !route.isEmpty { return false }
        let text = searchText
        return ["cream", "ointment", "gel", "lotion", "foam", "shampoo", "drops", "ophthalmic", "%"].contains(where: text.contains)
    }
}

nonisolated struct AppointmentFact: Sendable, Hashable {
    let appointmentID: String
    let time: Date
    let reason: String
    let status: String
}

// MARK: - Building a snapshot from the chart

extension PanelSnapshot {
    /// Copies the facts panel questions need out of the SwiftData models.
    @MainActor
    init(patients: [PatientProfile], capturedAt: Date = .now) {
        self.capturedAt = capturedAt
        self.patients = patients.map { PatientFacts(patient: $0) }
    }
}

extension PatientFacts {
    @MainActor
    init(patient: PatientProfile) {
        let records: [LocalClinicalRecord] = patient.clinicalRecords ?? []
        // Rows the source stopped returning are history, not current chart facts.
        let problems: [ChartProblem] = (patient.problems ?? []).filter { !$0.isRemovedAtSource }
        let medications: [LocalMedication] = (patient.medications ?? []).filter { !$0.isRemovedAtSource }
        let appointments: [Appointment] = (patient.appointments ?? []).filter { !$0.isRemovedAtSource }

        self.id = patient.id
        self.mrn = patient.medicalRecordNumber
        self.name = patient.fullName
        self.age = patient.age
        self.sex = patient.gender
        self.isSmoker = patient.isSmoker
        self.allergies = patient.allergies
        self.riskFlags = patient.riskFlags
        let noteDiagnoses = records.map { record in
            DiagnosisFact(
                recordID: record.recordID,
                name: record.conditionName,
                icd10: record.icd10Code,
                date: record.dateRecorded,
                documentationStatus: record.documentationStatus
            )
        }
        let problemDiagnoses = problems.map { problem in
            DiagnosisFact(
                recordID: Self.problemReference(problem),
                name: problem.display,
                icd10: problem.icd10Code,
                date: problem.sortDate ?? .distantPast,
                documentationStatus: "signed",
                isNote: false
            )
        }
        self.diagnoses = noteDiagnoses + problemDiagnoses
        self.medications = medications.map { medication in
            MedicationFact(
                rxID: medication.rxID,
                name: medication.medicationName,
                genericName: medication.genericName,
                status: medication.status,
                route: medication.route
            )
        }
        self.appointments = appointments.map { appointment in
            AppointmentFact(
                appointmentID: appointment.appointmentID,
                time: appointment.scheduledTime,
                reason: appointment.reasonForVisit,
                status: appointment.resolvedStatus
            )
        }
    }
}

extension PatientFacts {
    /// How a problem-list entry is cited: `Condition/<id>` for an imported resource, the
    /// chart's own identifier otherwise.
    @MainActor
    fileprivate static func problemReference(_ problem: ChartProblem) -> String {
        guard let identifier = problem.sourceRecordIdentifier else { return problem.qualifiedID }
        return problem.sourceKind == ClinicalSourceKind.smartFHIR.rawValue ? "Condition/\(identifier)" : identifier
    }
}
