import Foundation

struct ClinicalProblemSummary: Identifiable {
    let id: String
    let title: String
    let latestRecord: LocalClinicalRecord
    let occurrenceCount: Int
    let latestDate: Date
}

extension Sequence where Element == LocalClinicalRecord {
    func groupedProblemSummaries() -> [ClinicalProblemSummary] {
        let grouped = Dictionary(grouping: self) { record in
            record.problemGroupingKey
        }

        return grouped.values
            .compactMap { records in
                guard let latestRecord = records.max(by: { $0.dateRecorded < $1.dateRecorded }) else {
                    return nil
                }

                let title = latestRecord.conditionName.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedTitle = title.isEmpty ? "Condition" : title

                return ClinicalProblemSummary(
                    id: latestRecord.problemGroupingKey,
                    title: resolvedTitle,
                    latestRecord: latestRecord,
                    occurrenceCount: records.count,
                    latestDate: latestRecord.dateRecorded
                )
            }
            .sorted { $0.latestDate > $1.latestDate }
    }
}

private extension LocalClinicalRecord {
    var problemGroupingKey: String {
        if let icd10Code {
            let cleanedICD = icd10Code
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            if !cleanedICD.isEmpty {
                return "icd:\(cleanedICD)"
            }
        }

        let cleanedName = conditionName
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()

        return "name:\(cleanedName)"
    }
}

// MARK: - Problem list

/// One line of a patient's problem list.
///
/// Charted problems (`ChartProblem`: a FHIR Condition, a demo problem or one
/// entered on the chart) are the list. A diagnosis that only an encounter note
/// names is added after the active ones and marked as coming from a note, so the
/// list never hides a documented diagnosis and never passes a note off as a
/// charted problem.
struct ProblemListEntry: Identifiable {
    enum Origin {
        /// A row of the problem list.
        case charted
        /// Named by one or more encounter notes and not on the problem list.
        case note
    }

    let id: String
    let title: String
    /// The ICD-10-CM code when the entry has one, else the code the source used.
    let code: String?
    /// "Active", "Resolved" and so on for a charted problem; nil for a note diagnosis, which has no status.
    let statusLabel: String?
    /// True for an active, recurring or relapsed charted problem and for a note diagnosis.
    let isOpen: Bool
    /// Onset, else the recorded date, for a charted problem; the latest note's date for a note diagnosis.
    let date: Date?
    /// How many of the patient's notes carry this diagnosis.
    let noteCount: Int
    let origin: Origin
    let source: ClinicalSourceDescriptor
    /// The newest note with this diagnosis, when there is one.
    let latestNote: LocalClinicalRecord?
}

enum ProblemList {
    /// Charted problems that are still at the source, open ones first, then note-only
    /// diagnoses, then resolved and inactive problems. Newest first inside each group.
    /// A note written for an examination visit (ICD-10-CM Z00 to Z13) adds no entry.
    static func entries(problems: [ChartProblem], notes: [LocalClinicalRecord]) -> [ProblemListEntry] {
        let charted = problems
            .filter { !$0.isRemovedAtSource }
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive { return lhs.isActive }
                let left = lhs.sortDate ?? .distantPast
                let right = rhs.sortDate ?? .distantPast
                if left != right { return left > right }
                return lhs.qualifiedID < rhs.qualifiedID
            }

        // A note belongs to the first charted problem with its ICD-10 code, else the first with its name.
        var notesByProblem: [String: [LocalClinicalRecord]] = [:]
        var unmatched: [LocalClinicalRecord] = []
        for note in notes {
            let noteCode = cleaned(code: note.icd10Code)
            let noteName = cleaned(name: note.conditionName)
            let match = charted.first { problem in
                if let noteCode, let problemCode = cleaned(code: problem.icd10Code), noteCode == problemCode { return true }
                return !noteName.isEmpty && cleaned(name: problem.display) == noteName
            }
            if let match {
                notesByProblem[match.qualifiedID, default: []].append(note)
            } else if !isExaminationEncounter(noteCode) {
                unmatched.append(note)
            }
        }

        func chartedEntry(_ problem: ChartProblem) -> ProblemListEntry {
            let linked = notesByProblem[problem.qualifiedID] ?? []
            return ProblemListEntry(
                id: problem.qualifiedID,
                title: problem.display,
                code: problem.icd10Code ?? problem.code,
                statusLabel: problem.clinicalStatus.capitalized,
                isOpen: problem.isActive,
                date: problem.sortDate,
                noteCount: linked.count,
                origin: .charted,
                source: problem.sourceDescriptor,
                latestNote: linked.max { $0.dateRecorded < $1.dateRecorded }
            )
        }

        let noteEntries = unmatched.groupedProblemSummaries().map { summary in
            ProblemListEntry(
                id: "note/\(summary.id)",
                title: summary.title,
                code: summary.latestRecord.icd10Code,
                statusLabel: nil,
                isOpen: true,
                date: summary.latestDate,
                noteCount: summary.occurrenceCount,
                origin: .note,
                source: summary.latestRecord.sourceDescriptor,
                latestNote: summary.latestRecord
            )
        }

        return charted.filter(\.isActive).map(chartedEntry)
            + noteEntries
            + charted.filter { !$0.isActive }.map(chartedEntry)
    }

    /// ICD-10-CM Z00 to Z13, "Persons encountering health services for examinations": the reason
    /// for a visit such as a screening skin exam, which is not a problem.
    static func isExaminationEncounter(_ cleanedCode: String?) -> Bool {
        guard let code = cleanedCode, code.hasPrefix("z"), let block = Int(code.dropFirst().prefix(2)) else { return false }
        return (0...13).contains(block)
    }

    private static func cleaned(code: String?) -> String? {
        guard let code else { return nil }
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.isEmpty ? nil : value
    }

    /// Lowercased, without diacritics, extra spaces or a trailing SNOMED tag such as "(disorder)".
    private static func cleaned(name: String) -> String {
        name
            .replacingOccurrences(of: #"\s*\((disorder|finding|situation|procedure)\)\s*$"#, with: "", options: .regularExpression)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

extension PatientProfile {
    /// The problem list as the chart shows it. See `ProblemList.entries`.
    var problemList: [ProblemListEntry] {
        ProblemList.entries(problems: problems ?? [], notes: clinicalRecords ?? [])
    }

    /// Open entries on the problem list: active charted problems plus diagnoses only a note names.
    var openProblemCount: Int {
        problemList.filter(\.isOpen).count
    }
}
