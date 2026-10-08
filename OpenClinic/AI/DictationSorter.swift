//
//  DictationSorter.swift
//  OpenClinic
//
//  What drafts a visit note when the on-device model does not.
//

import Foundation

/// Sorts the sentences of a dictation into the sections of a visit note by keyword.
///
/// It writes no sentence of its own. The history holds the whole dictation as it was said, so a
/// sentence the rules place badly is never lost. Every other section holds the sentences whose words
/// point to it (a sentence can sit in two), or says that nothing was dictated for it. A diagnosis is
/// named only by a term the dictation uses as a whole word, in a sentence that does not deny it or
/// give it to a relative. The rules match whole words: "border" is not an order, "plantar" not a plan.
nonisolated enum DictationSorter {
    static let notDictated = "Not dictated."
    static let diagnosisNotDictated = "Diagnosis not dictated"

    nonisolated struct Sections: Sendable, Equatable {
        var diagnosis: String
        var history: String
        var symptoms: String
        var exam: String
        var plan: String
        var instructions: String
        var followUp: String
    }

    /// True for the placeholder a draft carries when the dictation named no diagnosis. A note saved
    /// with it names no problem, so the problem list leaves it out.
    static func isUndictated(diagnosis: String) -> Bool {
        diagnosis.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(diagnosisNotDictated) == .orderedSame
    }

    /// The dictation's sentences, in order, each as it was said.
    static func sentences(of dictation: String) -> [String] {
        var found: [String] = []
        dictation.enumerateSubstrings(in: dictation.startIndex..<dictation.endIndex, options: .bySentences) { sentence, _, _, _ in
            let trimmed = (sentence ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { found.append(trimmed) }
        }
        return found
    }

    static func sort(_ dictation: String) -> Sections {
        var symptoms: [String] = []
        var exam: [String] = []
        var plan: [String] = []
        var instructions: [String] = []
        var followUp: [String] = []

        for sentence in sentences(of: dictation) {
            if says(symptomCues, in: sentence) { symptoms.append(sentence) }
            if says(examCues, in: sentence) { exam.append(sentence) }
            if says(planCues, in: sentence) { plan.append(sentence) }
            if says(instructionCues, in: sentence) { instructions.append(sentence) }
            if says(followUpCues, in: sentence) { followUp.append(sentence) }
        }

        func text(_ lines: [String]) -> String { lines.isEmpty ? notDictated : lines.joined(separator: " ") }
        let whole = dictation.trimmingCharacters(in: .whitespacesAndNewlines)
        return Sections(
            diagnosis: diagnosis(in: dictation),
            history: whole.isEmpty ? notDictated : whole,
            symptoms: text(symptoms),
            exam: text(exam),
            plan: text(plan),
            instructions: text(instructions),
            followUp: text(followUp)
        )
    }

    /// The first condition the dictation names, as a whole word, in a sentence that neither denies
    /// it nor speaks of a relative. "No melanoma", "mother had melanoma" and "Dr. Schwartz" name
    /// nothing, and "cystic acne" names acne, not a cyst.
    static func diagnosis(in dictation: String) -> String {
        for sentence in sentences(of: dictation) {
            let lower = sentence.lowercased()
            guard !says(denialCues, in: lower) else { continue }
            var best: (term: String, position: String.Index)?
            for term in conditionTerms {
                let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: term) + #"s?\b"#
                guard let range = lower.range(of: pattern, options: .regularExpression) else { continue }
                // The earliest term wins; of two that start together, the longer ("atopic dermatitis").
                if let held = best, held.position < range.lowerBound
                    || (held.position == range.lowerBound && held.term.count >= term.count) {
                    continue
                }
                best = (term, range.lowerBound)
            }
            if let best {
                return best.term.prefix(1).uppercased() + best.term.dropFirst()
            }
        }
        return diagnosisNotDictated
    }

    // MARK: - Cues

    /// True when the text holds one of the cues as whole words.
    private static func says(_ cues: String, in text: String) -> Bool {
        text.range(of: cues, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static let symptomCues = #"\b(denies|reports|complains|endorses|itch\w*|pain|painful|burning|bleeding|no nausea|no fever)\b"#
    private static let examCues = #"\b(exam|examination|on inspection|palpation|shows|appears|measures|dermoscopy)\b"#
    private static let planCues = #"\b(continue|start|stop|increase|decrease|prescrib\w*|refill\w*|biopsy|orders?|ordered|check|refer|refers|referred|referral|plan|recommend\w*|excis\w*|cryotherapy|apply)\b"#
    private static let instructionCues = #"\b(instructed|advised|counsell?ed|educated|told to)\b"#
    private static let followUpCues = #"\b(return in|return to clinic|follow[- ]?up in|recheck in|back in (\w+ )?(days?|weeks?|months?|years?))\b"#
    private static let denialCues = #"\b(no|not|denies|denied|without|negative|never|rule out|ruled out|family|mother|father|sister|brother|grandmother|grandfather|aunt|uncle)\b|r/o"#

    /// Longer terms are listed with the shorter ones they contain; `diagnosis` prefers the longer.
    private static let conditionTerms = [
        "melanoma", "basal cell carcinoma", "squamous cell carcinoma", "actinic keratosis", "seborrheic keratosis",
        "plaque psoriasis", "psoriasis", "atopic dermatitis", "contact dermatitis", "seborrheic dermatitis", "dermatitis",
        "eczema", "rosacea", "acne", "wart", "verruca", "urticaria", "vitiligo", "alopecia", "cellulitis", "tinea",
        "dysplastic nevus", "nevus", "cyst", "shingles", "herpes zoster", "hidradenitis",
    ]
}
