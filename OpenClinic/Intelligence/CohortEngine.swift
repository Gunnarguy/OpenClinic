//
//  CohortEngine.swift
//  OpenClinic
//
//  Computes the answer to a panel question from structured chart facts.
//
//  No language model takes part. A set question ("which patients ...") has one
//  correct answer, so code computes it and every match carries the chart facts
//  that produced it. A patient is listed only when a charted diagnosis,
//  medication, allergy, flag or appointment satisfies the question.
//

import Foundation

// MARK: - Result

nonisolated struct CohortEvidence: Sendable, Hashable, Identifiable {
    enum Kind: String, Sendable, Hashable {
        case diagnosis, medication, allergy, riskFlag, socialHistory, appointment, demographic, documentation
    }

    let kind: Kind
    /// The record, prescription or appointment identifier the fact came from,
    /// or the MRN for a fact stored on the patient.
    let sourceID: String
    /// The fact itself, for example "Melanoma In Situ".
    let label: String
    /// Supporting detail, for example the ICD-10 code or the appointment status.
    let detail: String?
    let date: Date?

    var id: String { "\(kind.rawValue)|\(sourceID)|\(label)" }
}

nonisolated struct CohortMatch: Sendable, Identifiable {
    let patientID: UUID
    let mrn: String
    let name: String
    let age: Int
    let sex: String
    let evidence: [CohortEvidence]
    /// False when the source gave no date of birth; `age` is then not shown.
    var ageIsKnown = true

    var id: UUID { patientID }
}

nonisolated struct CohortResult: Sendable, Identifiable {
    let id: UUID
    let query: CohortQuery
    /// Patients who satisfy the question, in a stable order.
    let matches: [CohortMatch]
    /// Patients who do not satisfy the question but carry a related fact, such
    /// as a family history. Shown separately and never counted.
    let related: [CohortMatch]
    let panelSize: Int
    /// The date range used when the question named a time window.
    let window: DateInterval?
    let capturedAt: Date

    var matchedMRNs: Set<String> { Set(matches.map(\.mrn)) }
    var relatedMRNs: Set<String> { Set(related.map(\.mrn)) }
}

// MARK: - Engine

nonisolated enum CohortEngine {

    static func run(_ query: CohortQuery, on snapshot: PanelSnapshot, calendar: Calendar = .current) -> CohortResult {
        let now = snapshot.capturedAt
        let window = query.criteria.compactMap { criterion -> DateInterval? in
            if case .appointment(let scheduleWindow) = criterion {
                return scheduleWindow.interval(now: now, calendar: calendar)
            }
            return nil
        }.first

        var matches: [CohortMatch] = []
        var related: [CohortMatch] = []

        for patient in snapshot.patients {
            if query.presentation == .allergyOverview {
                matches.append(match(patient, evidence: allergyStatus(of: patient)))
                continue
            }

            var evidence: [CohortEvidence] = []
            var satisfiesEveryGroup = true
            for group in query.groups {
                let groupEvidence = group.flatMap { self.evidence(for: $0, patient: patient, now: now, calendar: calendar) }
                if groupEvidence.isEmpty {
                    satisfiesEveryGroup = false
                    break
                }
                evidence.append(contentsOf: groupEvidence)
            }

            if satisfiesEveryGroup, !query.groups.isEmpty {
                matches.append(match(patient, evidence: deduplicated(evidence)))
            } else {
                let relatedEvidence = relatedFacts(for: query, patient: patient)
                if !relatedEvidence.isEmpty {
                    related.append(match(patient, evidence: relatedEvidence))
                }
            }
        }

        return CohortResult(
            id: UUID(),
            query: query,
            matches: sorted(matches, for: query),
            related: related.sorted { $0.name < $1.name },
            panelSize: snapshot.patients.count,
            window: window,
            capturedAt: now
        )
    }

    // MARK: Evidence per criterion

    /// The chart facts on `patient` that satisfy `criterion`. Empty means the
    /// criterion does not hold.
    static func evidence(for criterion: CohortCriterion, patient: PatientFacts, now: Date, calendar: Calendar) -> [CohortEvidence] {
        switch criterion {
        case .diagnosis(let concept):
            return patient.diagnoses
                .filter { $0.namesADiagnosis && concept.matches($0) }
                .sorted { $0.date > $1.date }
                .map { diagnosisEvidence($0, detailSuffix: nil) }

        case .diagnosisNamed(let term):
            return patient.diagnoses
                .filter { $0.namesADiagnosis && PanelVocabulary.diagnosisName($0.name).contains(term) }
                .sorted { $0.date > $1.date }
                .map { diagnosisEvidence($0, detailSuffix: nil) }

        case .medicationClass(let drugClass):
            return patient.medications
                .filter { $0.isActive && drugClass.contains($0) }
                .sorted { $0.name < $1.name }
                .map { medicationEvidence($0, detail: drugClass.label) }

        case .medication(let term):
            return patient.medications
                .filter { $0.isActive && $0.searchText.contains(term) }
                .sorted { $0.name < $1.name }
                .map { medicationEvidence($0, detail: nil) }

        case .allergy(let term):
            return patient.documentedAllergies
                .filter { CohortQueryParser.normalize($0).contains(term) }
                .map { CohortEvidence(kind: .allergy, sourceID: patient.mrn, label: $0, detail: "Documented allergy", date: nil) }

        case .anyAllergy:
            return patient.documentedAllergies
                .map { CohortEvidence(kind: .allergy, sourceID: patient.mrn, label: $0, detail: "Documented allergy", date: nil) }

        case .noKnownAllergies:
            guard patient.documentedAllergies.isEmpty, !patient.allergies.isEmpty else { return [] }
            return [CohortEvidence(kind: .allergy, sourceID: patient.mrn, label: "No known allergies", detail: "Charted negative", date: nil)]

        case .smoker:
            guard patient.isSmoker else { return [] }
            return [CohortEvidence(kind: .socialHistory, sourceID: patient.mrn, label: "Current smoker", detail: "Social history", date: nil)]

        case .riskFlag(let concept):
            guard let flag = concept.matchingFlag(in: patient.riskFlags) else { return [] }
            return [CohortEvidence(kind: .riskFlag, sourceID: patient.mrn, label: flag, detail: "Risk flag", date: nil)]

        case .appointment(let scheduleWindow):
            let interval = scheduleWindow.interval(now: now, calendar: calendar)
            return patient.appointments
                .filter { $0.time >= interval.start && $0.time < interval.end }
                .sorted { $0.time < $1.time }
                .map { CohortEvidence(kind: .appointment, sourceID: $0.appointmentID, label: $0.reason, detail: $0.status, date: $0.time) }

        case .age(let comparison, let bound):
            guard patient.ageIsKnown, comparison.holds(patient.age, bound) else { return [] }
            return [CohortEvidence(kind: .demographic, sourceID: patient.mrn, label: "Age \(patient.age)", detail: nil, date: nil)]

        case .sex(let sex):
            guard patient.sex.trimmingCharacters(in: .whitespaces).lowercased() == sex else { return [] }
            return [CohortEvidence(kind: .demographic, sourceID: patient.mrn, label: patient.sex, detail: nil, date: nil)]

        case .unsignedNote:
            return patient.diagnoses
                .filter { $0.isNote && !$0.isSigned }
                .sorted { $0.date > $1.date }
                .map { diagnosisEvidence($0, detailSuffix: documentationLabel($0.documentationStatus), kind: .documentation) }
        }
    }

    // MARK: Helpers

    private static func match(_ patient: PatientFacts, evidence: [CohortEvidence]) -> CohortMatch {
        CohortMatch(patientID: patient.id, mrn: patient.mrn, name: patient.name, age: patient.age, sex: patient.sex, evidence: evidence, ageIsKnown: patient.ageIsKnown)
    }

    private static func diagnosisEvidence(_ diagnosis: DiagnosisFact, detailSuffix: String?, kind: CohortEvidence.Kind = .diagnosis) -> CohortEvidence {
        let code = diagnosis.icd10?.trimmingCharacters(in: .whitespaces)
        let parts = [code?.isEmpty == false ? "ICD-10 \(code!)" : nil, detailSuffix].compactMap { $0 }
        return CohortEvidence(
            kind: kind,
            sourceID: diagnosis.recordID,
            label: diagnosis.name,
            detail: parts.isEmpty ? nil : parts.joined(separator: ", "),
            date: diagnosis.date == .distantPast ? nil : diagnosis.date
        )
    }

    private static func medicationEvidence(_ medication: MedicationFact, detail: String?) -> CohortEvidence {
        CohortEvidence(kind: .medication, sourceID: medication.rxID, label: medication.name, detail: detail, date: nil)
    }

    private static func documentationLabel(_ status: String) -> String {
        // `DocumentationLifecycleStatus` raw values.
        switch status.lowercased() {
        case "draft": return "Draft"
        case "reviewed": return "Reviewed, awaiting signature"
        default: return status.capitalized
        }
    }

    private static func allergyStatus(of patient: PatientFacts) -> [CohortEvidence] {
        let documented = patient.documentedAllergies
        if !documented.isEmpty {
            return documented.map { CohortEvidence(kind: .allergy, sourceID: patient.mrn, label: $0, detail: "Documented allergy", date: nil) }
        }
        let label = patient.allergies.isEmpty ? "Allergy status not recorded" : "No known allergies"
        return [CohortEvidence(kind: .allergy, sourceID: patient.mrn, label: label, detail: nil, date: nil)]
    }

    /// Facts that are near the question but are not a match: a risk flag that
    /// names the diagnosis without a charted diagnosis behind it.
    private static func relatedFacts(for query: CohortQuery, patient: PatientFacts) -> [CohortEvidence] {
        guard query.groups.count == 1 else { return [] }
        var facts: [CohortEvidence] = []
        for criterion in query.criteria {
            guard case .diagnosis(let concept) = criterion,
                  let flag = concept.relatedFlag(in: patient.riskFlags) else { continue }
            facts.append(CohortEvidence(kind: .riskFlag, sourceID: patient.mrn, label: flag, detail: "Risk flag, not a charted diagnosis", date: nil))
        }
        return deduplicated(facts)
    }

    private static func deduplicated(_ evidence: [CohortEvidence]) -> [CohortEvidence] {
        var seen = Set<String>()
        return evidence.filter { seen.insert($0.id).inserted }
    }

    /// Schedule answers read in time order; cohorts read alphabetically by name.
    private static func sorted(_ matches: [CohortMatch], for query: CohortQuery) -> [CohortMatch] {
        guard query.presentation == .schedule else {
            return matches.sorted { $0.name < $1.name }
        }
        func firstTime(_ match: CohortMatch) -> Date {
            match.evidence.compactMap { $0.kind == .appointment ? $0.date : nil }.min() ?? .distantFuture
        }
        return matches.sorted { firstTime($0) < firstTime($1) }
    }
}

// MARK: - Plain-text answer

/// The same answer as text, for Shortcuts, VoiceOver and anywhere a view is
/// not available. The wording is fixed; no model writes it.
nonisolated enum CohortAnswerFormatter {

    static let provenanceLine = "Computed from structured chart data. No generative model was used."

    static func headline(for result: CohortResult) -> String {
        switch result.query.presentation {
        case .allergyOverview:
            let withAllergies = result.matches.filter { match in
                match.evidence.contains { $0.detail == "Documented allergy" }
            }.count
            return "\(withAllergies) of \(result.panelSize) patients have a documented allergy."
        case .schedule:
            let count = result.matches.reduce(0) { $0 + $1.evidence.filter { $0.kind == .appointment }.count }
            let noun = count == 1 ? "appointment" : "appointments"
            let windowLabel = result.query.criteria.compactMap { criterion -> String? in
                if case .appointment(let window) = criterion { return window.label }
                return nil
            }.first ?? ""
            return count == 0 ? "No appointments \(windowLabel)." : "\(count) \(noun) \(windowLabel)."
        case .cohort:
            if result.matches.isEmpty {
                return "No patients match: \(result.query.summary)."
            }
            let noun = result.panelSize == 1 ? "patient" : "patients"
            return "\(result.matches.count) of \(result.panelSize) \(noun) match: \(result.query.summary)."
        }
    }

    static func text(for result: CohortResult) -> String {
        var lines: [String] = [headline(for: result), ""]

        for match in result.matches {
            switch result.query.presentation {
            case .schedule:
                for item in match.evidence where item.kind == .appointment {
                    let time = item.date.map(scheduleStamp) ?? ""
                    let status = item.detail.map { " [\($0)]" } ?? ""
                    lines.append("- \(time)  \(match.name): \(item.label)\(status)")
                }
            case .cohort, .allergyOverview:
                let facts = match.evidence.map(describe).joined(separator: "; ")
                lines.append("- \(match.name) (\(match.mrn)): \(facts)")
            }
        }

        if !result.related.isEmpty {
            lines.append("")
            lines.append("Related, not counted:")
            for match in result.related {
                let facts = match.evidence.map(describe).joined(separator: "; ")
                lines.append("- \(match.name) (\(match.mrn)): \(facts)")
            }
        }

        lines.append("")
        lines.append(provenanceLine)
        return lines.joined(separator: "\n")
    }

    static func describe(_ evidence: CohortEvidence) -> String {
        var text = evidence.label
        if let date = evidence.date, evidence.kind != .appointment {
            text += ", \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        switch evidence.kind {
        case .diagnosis, .medication, .documentation, .appointment:
            text += " [\(evidence.sourceID)]"
        case .allergy, .riskFlag, .socialHistory, .demographic:
            break
        }
        return text
    }

    private static func scheduleStamp(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }
}
