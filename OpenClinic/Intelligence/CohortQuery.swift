//
//  CohortQuery.swift
//  OpenClinic
//
//  The structured form of a panel question ("which patients ...") and the
//  parser that produces it from the clinician's words.
//
//  The parser is strict on purpose. If any content word in the question is not
//  understood, or the question negates something, it returns nil instead of
//  answering a narrower or broader question than the one that was asked.
//

import Foundation

// MARK: - Criteria

nonisolated enum ScheduleWindow: String, Sendable, Hashable {
    case today
    case tomorrow
    /// The seven days after today.
    case next7Days
    /// The thirty days after today.
    case next30Days

    /// The interval the window covers, relative to `now`.
    func interval(now: Date, calendar: Calendar) -> DateInterval {
        let startOfToday = calendar.startOfDay(for: now)
        func day(_ offset: Int) -> Date {
            calendar.date(byAdding: .day, value: offset, to: startOfToday) ?? startOfToday
        }
        switch self {
        case .today: return DateInterval(start: day(0), end: day(1))
        case .tomorrow: return DateInterval(start: day(1), end: day(2))
        case .next7Days: return DateInterval(start: day(1), end: day(8))
        case .next30Days: return DateInterval(start: day(1), end: day(31))
        }
    }

    var label: String {
        switch self {
        case .today: return "today"
        case .tomorrow: return "tomorrow"
        case .next7Days: return "in the next 7 days"
        case .next30Days: return "in the next 30 days"
        }
    }
}

nonisolated enum AgeComparison: String, Sendable, Hashable {
    case atLeast, olderThan, youngerThan, atMost

    func holds(_ age: Int, _ bound: Int) -> Bool {
        switch self {
        case .atLeast: return age >= bound
        case .olderThan: return age > bound
        case .youngerThan: return age < bound
        case .atMost: return age <= bound
        }
    }

    func label(_ bound: Int) -> String {
        switch self {
        case .atLeast: return "age \(bound) or older"
        case .olderThan: return "older than \(bound)"
        case .youngerThan: return "younger than \(bound)"
        case .atMost: return "age \(bound) or younger"
        }
    }
}

nonisolated enum CohortCriterion: Sendable, Hashable {
    /// A charted diagnosis that satisfies the concept, at any date.
    case diagnosis(DiagnosisConcept)
    /// A charted diagnosis whose name contains the term. Used for diagnoses the lexicon has no
    /// concept for, which is most of what an imported record contains.
    case diagnosisNamed(String)
    /// A current medication in the class.
    case medicationClass(DrugClass)
    /// A current medication whose name contains the term.
    case medication(String)
    /// A documented allergy whose text contains the term.
    case allergy(String)
    /// At least one documented allergy.
    case anyAllergy
    /// Charted as no known allergies.
    case noKnownAllergies
    case smoker
    case riskFlag(RiskConcept)
    case appointment(ScheduleWindow)
    case age(AgeComparison, Int)
    /// Normalized to "female" or "male".
    case sex(String)
    /// A clinical note that is still a draft or reviewed but not signed.
    case unsignedNote

    /// Criteria of the same kind joined by "or" in the question form one group.
    var kind: String {
        switch self {
        case .diagnosis, .diagnosisNamed: return "diagnosis"
        case .medicationClass, .medication: return "medication"
        case .allergy, .anyAllergy, .noKnownAllergies: return "allergy"
        case .smoker: return "smoker"
        case .riskFlag: return "risk"
        case .appointment: return "appointment"
        case .age: return "age"
        case .sex: return "sex"
        case .unsignedNote: return "documentation"
        }
    }

    /// How the criterion reads in an answer.
    var label: String {
        switch self {
        case .diagnosis(let concept): return "charted diagnosis of \(concept.label)"
        case .diagnosisNamed(let term): return "charted diagnosis matching \"\(term)\""
        case .medicationClass(let drugClass): return "current \(drugClass.label)"
        case .medication(let term): return "current medication: \(term)"
        case .allergy(let term): return "documented allergy: \(term)"
        case .anyAllergy: return "any documented allergy"
        case .noKnownAllergies: return "no known allergies"
        case .smoker: return "current smoker"
        case .riskFlag(let concept): return "risk flag: \(concept.label)"
        case .appointment(let window): return "appointment \(window.label)"
        case .age(let comparison, let bound): return comparison.label(bound)
        case .sex(let sex): return sex
        case .unsignedNote: return "note not yet signed"
        }
    }
}

// MARK: - Query

nonisolated struct CohortQuery: Sendable, Hashable {
    enum Presentation: String, Sendable, Hashable {
        /// Matching patients with the chart facts that matched.
        case cohort
        /// Appointments in time order.
        case schedule
        /// Every patient's allergy status.
        case allergyOverview
    }

    /// A patient matches when every group has at least one satisfied criterion.
    var groups: [[CohortCriterion]]
    var presentation: Presentation
    /// The question as the clinician asked it.
    var original: String

    var criteria: [CohortCriterion] { groups.flatMap { $0 } }

    /// The computation in words, for example
    /// "current biologic OR current systemic immunosuppressant".
    var summary: String {
        groups
            .map { group in
                let text = group.map(\.label).joined(separator: " OR ")
                return group.count > 1 && groups.count > 1 ? "(\(text))" : text
            }
            .joined(separator: " AND ")
    }
}

// MARK: - Vocabulary from the chart

/// Words that only exist in this panel's charts: the medications and allergens
/// on file. Lets a question name any charted drug without a hardcoded list.
nonisolated struct PanelVocabulary: Sendable {
    /// Lowercased medication words mapped to the term to search for.
    var medicationTerms: [String: String] = [:]
    /// Lowercased allergen words mapped to the term to search for.
    var allergenTerms: [String: String] = [:]
    /// Lowercased diagnosis names and their distinctive words, mapped to the term to search for.
    var diagnosisTerms: [String: String] = [:]

    init() {}

    init(snapshot: PanelSnapshot) {
        for patient in snapshot.patients {
            for diagnosis in patient.diagnoses {
                let name = Self.diagnosisName(diagnosis.name)
                guard !name.isEmpty else { continue }
                if name.count >= 6 { diagnosisTerms[name] = name }
                for word in name.split(separator: " ").map(String.init)
                where word.count >= 6 && !Self.genericDiagnosisWords.contains(word) {
                    diagnosisTerms[word] = word
                }
            }
            for medication in patient.medications {
                for source in [medication.genericName, medication.name] {
                    guard let word = Self.leadingWord(of: source), word.count >= 5 else { continue }
                    medicationTerms[word] = word
                }
            }
            for allergy in patient.documentedAllergies {
                let phrase = CohortQueryParser.normalize(allergy).trimmingCharacters(in: .whitespaces)
                guard !phrase.isEmpty else { continue }
                allergenTerms[phrase] = phrase
                if let word = Self.leadingWord(of: allergy), word.count >= 4 {
                    allergenTerms[word] = word
                }
            }
        }
        for (short, full) in ClinicalLexicon.allergenSynonyms where allergenTerms.values.contains(where: { $0.contains(full) }) {
            allergenTerms[short] = full
        }
    }

    /// A diagnosis name as it would be typed: lowercased, without a terminology qualifier such
    /// as "(disorder)" or "(finding)".
    static func diagnosisName(_ name: String) -> String {
        var text = name
        while let open = text.lastIndex(of: "("), let close = text.lastIndex(of: ")"), open < close,
              text[close...].dropFirst().allSatisfy(\.isWhitespace) {
            text = String(text[..<open])
        }
        return CohortQueryParser.normalize(text).trimmingCharacters(in: .whitespaces)
    }

    /// Words that appear in diagnosis names without naming a diagnosis.
    private static let genericDiagnosisWords: Set<String> = [
        "disorder", "finding", "situation", "disease", "history", "chronic", "unspecified", "primary",
        "secondary", "essential", "suspected", "annual", "screening", "encounter", "follow", "region",
        "general", "examination", "status", "related", "induced", "associated", "without", "condition",
        "patient", "normal", "abnormal", "moderate", "severe", "intermittent", "persistent", "recurrent",
    ]

    private static func leadingWord(of text: String?) -> String? {
        guard let text else { return nil }
        return CohortQueryParser.normalize(text)
            .split(separator: " ")
            .first
            .map(String.init)
    }
}

// MARK: - Parser

nonisolated struct CohortQueryParser: Sendable {
    let vocabulary: PanelVocabulary

    init(vocabulary: PanelVocabulary = PanelVocabulary()) {
        self.vocabulary = vocabulary
    }

    /// Returns the structured query, or nil when the question is not one this
    /// parser fully understands.
    func parse(_ question: String) -> CohortQuery? {
        var text = Self.normalize(question)
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let asked = text

        // Criteria are found longest phrase first but reported in the order
        // the clinician said them.
        var found: [(position: Int, criterion: CohortCriterion)] = []
        func add(_ criterion: CohortCriterion, phrase: String) {
            guard !found.contains(where: { $0.criterion == criterion }) else { return }
            let position = asked.range(of: " " + phrase + " ").map { asked.distance(from: asked.startIndex, to: $0.lowerBound) } ?? asked.count
            found.append((position, criterion))
        }
        var mentionsSchedule = false
        var mentionsAllergy = false

        // "No known allergies" is the one negative this parser supports. Every
        // other negation ("not on", "without", "no history of") leaves a word
        // behind that is not filler, so the parse fails below.
        for phrase in ["no known drug allergies", "no known allergies", "no documented allergies", "no allergies", "nkda", "without allergies"] {
            if Self.consume(phrase, in: &text) {
                add(.noKnownAllergies, phrase: phrase)
                break
            }
        }

        // Age bounds carry a number, so they are read before phrase matching.
        if let age = Self.consumeAge(in: &text) {
            found.append((0, age))
        }

        // A question that mixes "and" with "or" has more than one reading.
        let hasAnd = text.contains(" and ")
        let asksAboutAllergy = text.contains(" allerg")

        // Longest phrases first, so "atopic dermatitis" is taken before "dermatitis".
        for entry in phraseTable(includeAllergens: asksAboutAllergy) {
            guard Self.consume(entry.phrase, in: &text) else { continue }
            switch entry.meaning {
            case .criterion(let criterion):
                add(criterion, phrase: entry.phrase)
            case .scheduleWord:
                mentionsSchedule = true
            case .allergyWord:
                mentionsAllergy = true
            }
        }

        let hasOr = Self.consume("or", in: &text)

        // Anything left that is not a filler word means part of the question was
        // not understood. Do not answer a different question.
        let leftover = text.split(separator: " ").map(String.init).filter { !Self.fillerWords.contains($0) }
        guard leftover.isEmpty else { return nil }

        var criteria = found.sorted { $0.position < $1.position }.map(\.criterion)

        // A schedule word with no window means upcoming visits.
        if mentionsSchedule, !criteria.contains(where: { $0.kind == "appointment" }) {
            criteria.append(.appointment(.next30Days))
        }

        // "Allergy" with no allergen named: the whole panel's allergy status
        // when nothing else narrows the question, otherwise "has any allergy".
        if mentionsAllergy, !criteria.contains(where: { $0.kind == "allergy" }) {
            if criteria.isEmpty {
                return CohortQuery(groups: [], presentation: .allergyOverview, original: question)
            }
            criteria.append(.anyAllergy)
        }

        guard !criteria.isEmpty,
              let groups = Self.group(criteria, hasOr: hasOr, hasAnd: hasAnd) else { return nil }

        let presentation: CohortQuery.Presentation =
            criteria.allSatisfy { $0.kind == "appointment" } ? .schedule : .cohort
        return CohortQuery(groups: groups, presentation: presentation, original: question)
    }

    // MARK: Phrase table

    private enum Meaning {
        case criterion(CohortCriterion)
        case scheduleWord
        case allergyWord
    }

    private struct PhraseEntry {
        let phrase: String
        let meaning: Meaning
    }

    /// Allergen words are only read as allergens when the question asks about
    /// an allergy, so a drug name means the medication everywhere else.
    private func phraseTable(includeAllergens: Bool) -> [PhraseEntry] {
        var entries: [PhraseEntry] = []

        for concept in ClinicalLexicon.diagnoses {
            for term in concept.queryTerms {
                entries.append(PhraseEntry(phrase: term, meaning: .criterion(.diagnosis(concept))))
            }
        }
        for drugClass in ClinicalLexicon.drugClasses {
            for term in drugClass.queryTerms {
                entries.append(PhraseEntry(phrase: term, meaning: .criterion(.medicationClass(drugClass))))
            }
        }
        for concept in ClinicalLexicon.risks {
            for term in concept.queryTerms {
                entries.append(PhraseEntry(phrase: term, meaning: .criterion(.riskFlag(concept))))
            }
        }
        if includeAllergens {
            for (word, term) in vocabulary.allergenTerms {
                entries.append(PhraseEntry(phrase: word, meaning: .criterion(.allergy(term))))
            }
        }
        for (word, term) in vocabulary.medicationTerms where !(includeAllergens && vocabulary.allergenTerms[word] != nil) {
            entries.append(PhraseEntry(phrase: word, meaning: .criterion(.medication(term))))
        }

        let fixed: [(String, Meaning)] = [
            ("smokers", .criterion(.smoker)), ("smoker", .criterion(.smoker)), ("smoke", .criterion(.smoker)),
            ("smokes", .criterion(.smoker)), ("smoking", .criterion(.smoker)), ("tobacco", .criterion(.smoker)),
            ("tobacco use", .criterion(.smoker)),

            ("today", .criterion(.appointment(.today))),
            ("tomorrow", .criterion(.appointment(.tomorrow))),
            ("this week", .criterion(.appointment(.next7Days))),
            ("next week", .criterion(.appointment(.next7Days))),
            ("next 7 days", .criterion(.appointment(.next7Days))),
            ("next seven days", .criterion(.appointment(.next7Days))),
            ("coming week", .criterion(.appointment(.next7Days))),
            ("this month", .criterion(.appointment(.next30Days))),
            ("next month", .criterion(.appointment(.next30Days))),
            ("next 30 days", .criterion(.appointment(.next30Days))),

            ("women", .criterion(.sex("female"))), ("female", .criterion(.sex("female"))), ("females", .criterion(.sex("female"))),
            ("men", .criterion(.sex("male"))), ("male", .criterion(.sex("male"))), ("males", .criterion(.sex("male"))),

            ("unsigned notes", .criterion(.unsignedNote)), ("unsigned note", .criterion(.unsignedNote)),
            ("unsigned", .criterion(.unsignedNote)), ("open notes", .criterion(.unsignedNote)),
            ("draft notes", .criterion(.unsignedNote)), ("drafts", .criterion(.unsignedNote)),
            ("needs signing", .criterion(.unsignedNote)), ("need signing", .criterion(.unsignedNote)),
            ("need to sign", .criterion(.unsignedNote)), ("need a signature", .criterion(.unsignedNote)),
            ("awaiting signature", .criterion(.unsignedNote)),

            ("schedule", .scheduleWord), ("scheduled", .scheduleWord), ("agenda", .scheduleWord),
            ("appointments", .scheduleWord), ("appointment", .scheduleWord),
            ("visits", .scheduleWord), ("visit", .scheduleWord),
            ("follow ups", .scheduleWord), ("follow up", .scheduleWord),
            ("followups", .scheduleWord), ("followup", .scheduleWord),
            ("upcoming", .scheduleWord), ("booked", .scheduleWord), ("coming in", .scheduleWord),

            ("allergies", .allergyWord), ("allergy", .allergyWord), ("allergic", .allergyWord),
            ("allergen", .allergyWord), ("allergens", .allergyWord),
        ]
        entries.append(contentsOf: fixed.map { PhraseEntry(phrase: $0.0, meaning: $0.1) })

        // Diagnosis names from the charts fill in what the lexicon has no concept for. A phrase
        // that already means something keeps that meaning.
        var taken = Set(entries.map(\.phrase))
        taken.formUnion(Self.fillerWords)
        for (phrase, term) in vocabulary.diagnosisTerms where !taken.contains(phrase) {
            entries.append(PhraseEntry(phrase: phrase, meaning: .criterion(.diagnosisNamed(term))))
        }

        // Longest first. Ties break alphabetically so the order is stable.
        return entries.sorted {
            $0.phrase.count != $1.phrase.count ? $0.phrase.count > $1.phrase.count : $0.phrase < $1.phrase
        }
    }

    // MARK: Grouping

    /// Builds the AND-of-OR groups, or nil when "or" has more than one reading.
    ///
    /// - No "or": every criterion must hold.
    /// - "or" between criteria of the same kind ("biologics or immunosuppressants"):
    ///   those form one group; other kinds must still hold.
    /// - "or" between exactly two criteria of different kinds: either may hold.
    private static func group(_ criteria: [CohortCriterion], hasOr: Bool, hasAnd: Bool) -> [[CohortCriterion]]? {
        guard hasOr, criteria.count > 1 else { return criteria.map { [$0] } }
        guard !hasAnd else { return nil }

        var groups: [[CohortCriterion]] = []
        var indexByKind: [String: Int] = [:]
        for criterion in criteria {
            if let index = indexByKind[criterion.kind] {
                groups[index].append(criterion)
            } else {
                indexByKind[criterion.kind] = groups.count
                groups.append([criterion])
            }
        }
        if groups.contains(where: { $0.count > 1 }) { return groups }
        return criteria.count == 2 ? [criteria] : nil
    }

    // MARK: Text handling

    /// Lowercases, drops possessives and punctuation, and pads with spaces so
    /// phrases can be matched on word boundaries.
    static func normalize(_ text: String) -> String {
        var result = text.lowercased()
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "'s ", with: " ")
            .replacingOccurrences(of: "'", with: "")
        result = String(result.map { character in
            character.isLetter || character.isNumber ? character : " "
        })
        let words = result.split(separator: " ")
        return " " + words.joined(separator: " ") + " "
    }

    /// Removes every whole-word occurrence of `phrase` and reports whether one was found.
    private static func consume(_ phrase: String, in text: inout String) -> Bool {
        let needle = " " + phrase + " "
        var found = false
        while let range = text.range(of: needle) {
            text.replaceSubrange(range, with: " ")
            found = true
        }
        return found
    }

    private static func consumeAge(in text: inout String) -> CohortCriterion? {
        let patterns: [(String, AgeComparison)] = [
            (#" (?:over|older than|above|past) (\d{1,3}) "#, .olderThan),
            (#" (?:at least|aged at least) (\d{1,3}) "#, .atLeast),
            (#" (\d{1,3}) (?:and|or) (?:older|over|above|up) "#, .atLeast),
            (#" (?:under|younger than|below) (\d{1,3}) "#, .youngerThan),
            (#" (\d{1,3}) (?:and|or) (?:younger|under|below) "#, .atMost),
        ]
        for (pattern, comparison) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let numberRange = Range(match.range(at: 1), in: text),
                  let bound = Int(text[numberRange]),
                  let fullRange = Range(match.range, in: text) else { continue }
            text.replaceSubrange(fullRange, with: " ")
            return .age(comparison, bound)
        }
        return nil
    }

    /// Words that carry no selection meaning in a panel question. A word that
    /// is not here and was not matched as a phrase makes the parse fail.
    private static let fillerWords: Set<String> = [
        "who", "whom", "which", "what", "whats", "whos", "show", "list", "find", "give", "tell", "me", "us",
        "all", "any", "every", "each", "of", "the", "a", "an", "my", "our", "in", "on", "at", "for", "to",
        "is", "are", "was", "were", "be", "been", "has", "have", "had", "having", "do", "does", "did",
        "with", "and", "that", "there", "their", "them", "they", "it", "this", "these", "those",
        "patient", "patients", "people", "person", "panel", "wide", "clinic", "practice", "chart", "charts",
        "history", "histories", "diagnosis", "diagnoses", "diagnosed", "condition", "conditions",
        "currently", "current", "taking", "takes", "take", "prescribed", "medication", "medications",
        "therapy", "treatment", "treated", "risk", "risks", "high", "flag", "flags", "flagged",
        "how", "many", "count", "number", "please", "can", "you", "i", "see", "get", "being",
        "notes", "note", "documented", "known", "drug", "drugs", "old", "years", "year", "age", "aged",
        "exposure", "coming", "due", "now", "right", "from", "about", "among", "across", "status",
        "overview", "summary", "breakdown", "anyone", "anybody", "someone", "use", "uses", "using",
    ]
}
