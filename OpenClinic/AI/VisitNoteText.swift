//
//  VisitNoteText.swift
//  OpenClinic
//
//  A visit note as labeled plain-text sections: the prompt that asks the
//  on-device model for one, and the reader that takes one apart again.
//
//  The model refuses to fill a structured note when the patient's record is in
//  the prompt (measured 2026-10-07: 6 of 6 refused, "May contain sensitive
//  content") and writes the same note as plain text every time. So a structured
//  note is asked for from the dictation alone, and this is the second try.
//

import Foundation

nonisolated enum VisitNoteText {
    /// The sections of a note as plain values.
    struct Sections: Sendable, Equatable {
        var diagnosis = ""
        var history = ""
        var symptoms = ""
        var exam = ""
        var plan = ""
        var instructions = ""
        var followUp = ""
        var orders: [String] = []
        var medicationChanges: [String] = []
        var bodySites: [String] = []
    }

    /// The labels, in the order the prompt lists them. The reader accepts exactly these.
    static let labels = [
        "Diagnosis", "History", "Symptoms", "Exam", "Plan", "Instructions", "Follow-up",
        "Orders", "Medication changes", "Body sites",
    ]

    /// What the model is asked, after the dictation.
    static var request: String {
        "Write the note as these labeled sections, one per line, using only what the dictation states:\n"
            + labels.map { "\($0):" }.joined(separator: "\n")
    }

    /// Reads labeled sections. Returns nil when the text has neither a diagnosis nor a plan,
    /// which means the model wrote something other than the note that was asked for.
    static func parse(_ text: String) -> Sections? {
        var found: [String: [String]] = [:]
        var current: String?
        for rawLine in text.components(separatedBy: .newlines) {
            // Models decorate labels: "**Plan:**", "- Plan:", "## Plan:".
            let line = rawLine
                .replacingOccurrences(of: "**", with: "")
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#-• "))
            if let label = labels.first(where: { line.lowercased().hasPrefix($0.lowercased() + ":") }) {
                current = label
                let rest = String(line.dropFirst(label.count + 1)).trimmingCharacters(in: .whitespaces)
                found[label, default: []].append(contentsOf: rest.isEmpty ? [] : [rest])
            } else if let current, !line.isEmpty {
                found[current, default: []].append(line)
            }
        }

        func prose(_ label: String) -> String {
            let value = (found[label] ?? []).joined(separator: " ")
            return isEmptyAnswer(value) ? "" : value
        }
        func list(_ label: String) -> [String] {
            (found[label] ?? [])
                .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ";,")) }
                .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
                .filter { !isEmptyAnswer($0) }
        }

        let sections = Sections(
            diagnosis: prose("Diagnosis"),
            history: prose("History"),
            symptoms: prose("Symptoms"),
            exam: prose("Exam"),
            plan: prose("Plan"),
            instructions: prose("Instructions"),
            followUp: prose("Follow-up"),
            orders: list("Orders"),
            medicationChanges: list("Medication changes"),
            bodySites: list("Body sites")
        )
        return sections.diagnosis.isEmpty && sections.plan.isEmpty ? nil : sections
    }

    /// "None", "Not stated" and the like: the model's way of leaving a section empty.
    private static func isEmptyAnswer(_ value: String) -> Bool {
        let lowered = value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return lowered.isEmpty || ["none", "n/a", "not stated", "not mentioned", "none stated", "not specified", "none mentioned"].contains(lowered)
    }
}
