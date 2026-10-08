//
//  ClinicalLexicon.swift
//  OpenClinic
//
//  The vocabulary panel questions are parsed against: diagnosis concepts,
//  drug classes and risk concepts. Each entry lists the phrases that select it
//  in a question and the chart values that satisfy it, so a match is always
//  traceable to a charted diagnosis name, ICD-10 code, medication or flag.
//
//  The lexicon covers the dermatology scope of the demo panel. It is a lookup
//  table for retrieval, not a clinical terminology service.
//

import Foundation

// MARK: - Diagnosis concepts

nonisolated struct DiagnosisConcept: Sendable, Hashable, Identifiable {
    let id: String
    /// How the concept reads in an answer, for example "melanoma".
    let label: String
    /// Phrases in a question that select this concept.
    let queryTerms: [String]
    /// Lowercased substrings of a charted diagnosis name that satisfy it.
    let nameTerms: [String]
    /// ICD-10-CM prefixes that satisfy it.
    let icdPrefixes: [String]
    /// Lowercased risk-flag substrings that are related to the concept but are
    /// not a charted diagnosis, such as a family history. Reported separately
    /// and never counted as a match.
    let relatedFlagTerms: [String]

    func matches(_ diagnosis: DiagnosisFact) -> Bool {
        if let code = diagnosis.icd10?.trimmingCharacters(in: .whitespaces).uppercased(), !code.isEmpty,
           icdPrefixes.contains(where: code.hasPrefix) {
            return true
        }
        let name = diagnosis.name.lowercased()
        return nameTerms.contains(where: name.contains)
    }

    func relatedFlag(in flags: [String]) -> String? {
        flags.first { flag in
            let lowered = flag.lowercased()
            return relatedFlagTerms.contains(where: lowered.contains)
        }
    }
}

// MARK: - Drug classes

nonisolated struct DrugClass: Sendable, Hashable, Identifiable {
    enum RouteRule: Sendable, Hashable {
        case any
        /// Only systemic products count (oral, injected). A topical or eye product does not.
        case systemicOnly
        /// Only products applied to the skin count.
        case topicalOnly
    }

    let id: String
    /// How the class reads in an answer, for example "biologic".
    let label: String
    let queryTerms: [String]
    /// Lowercased generic and brand name substrings that belong to the class.
    let members: [String]
    let routeRule: RouteRule

    func contains(_ medication: MedicationFact) -> Bool {
        let text = medication.searchText
        guard members.contains(where: text.contains) else { return false }
        switch routeRule {
        case .any: return true
        case .systemicOnly: return !medication.isTopical
        case .topicalOnly: return medication.isTopical
        }
    }
}

// MARK: - Risk concepts

nonisolated struct RiskConcept: Sendable, Hashable, Identifiable {
    let id: String
    let label: String
    let queryTerms: [String]
    /// Lowercased substrings of a charted risk flag that satisfy it.
    let flagTerms: [String]

    func matchingFlag(in flags: [String]) -> String? {
        flags.first { flag in
            let lowered = flag.lowercased()
            return flagTerms.contains(where: lowered.contains)
        }
    }
}

// MARK: - Lexicon

nonisolated enum ClinicalLexicon {

    static let diagnoses: [DiagnosisConcept] = [
        DiagnosisConcept(
            id: "melanoma", label: "melanoma",
            queryTerms: ["melanoma", "melanomas"],
            nameTerms: ["melanoma"],
            icdPrefixes: ["C43", "D03", "Z85.820"],
            relatedFlagTerms: ["family history of melanoma"]
        ),
        DiagnosisConcept(
            id: "basalCellCarcinoma", label: "basal cell carcinoma",
            queryTerms: ["basal cell carcinoma", "basal cell carcinomas", "basal cell", "bcc", "bccs"],
            nameTerms: ["basal cell"],
            icdPrefixes: ["C44.01", "C44.11", "C44.21", "C44.31", "C44.41", "C44.51", "C44.61", "C44.71", "C44.81", "C44.91"],
            relatedFlagTerms: []
        ),
        DiagnosisConcept(
            id: "squamousCellCarcinoma", label: "squamous cell carcinoma",
            queryTerms: ["squamous cell carcinoma", "squamous cell carcinomas", "squamous cell", "scc", "sccs"],
            nameTerms: ["squamous cell"],
            icdPrefixes: ["C44.02", "C44.12", "C44.22", "C44.32", "C44.42", "C44.52", "C44.62", "C44.72", "C44.82", "C44.92", "D04"],
            relatedFlagTerms: []
        ),
        DiagnosisConcept(
            id: "skinCancer", label: "skin cancer",
            queryTerms: ["skin cancer", "skin cancers", "skin malignancy", "skin malignancies", "cutaneous malignancy", "cutaneous malignancies"],
            nameTerms: ["melanoma", "basal cell", "squamous cell"],
            icdPrefixes: ["C43", "C44", "D03", "D04", "Z85.82"],
            relatedFlagTerms: ["family history of melanoma", "family history of skin cancer"]
        ),
        DiagnosisConcept(
            id: "psoriasis", label: "psoriasis",
            queryTerms: ["psoriasis", "psoriatic"],
            nameTerms: ["psoriasis"],
            icdPrefixes: ["L40"],
            relatedFlagTerms: []
        ),
        DiagnosisConcept(
            id: "atopicDermatitis", label: "atopic dermatitis",
            queryTerms: ["atopic dermatitis", "atopic eczema", "eczema", "atopic"],
            nameTerms: ["atopic dermatitis", "eczema"],
            icdPrefixes: ["L20"],
            relatedFlagTerms: []
        ),
        DiagnosisConcept(
            id: "contactDermatitis", label: "contact dermatitis",
            queryTerms: ["allergic contact dermatitis", "contact dermatitis"],
            nameTerms: ["contact dermatitis"],
            icdPrefixes: ["L23", "L24", "L25"],
            relatedFlagTerms: []
        ),
        DiagnosisConcept(
            id: "dermatitis", label: "dermatitis",
            queryTerms: ["dermatitis"],
            nameTerms: ["dermatitis", "eczema"],
            icdPrefixes: ["L20", "L21", "L22", "L23", "L24", "L25", "L26", "L27", "L28", "L29", "L30"],
            relatedFlagTerms: []
        ),
        DiagnosisConcept(
            id: "acne", label: "acne",
            queryTerms: ["acne vulgaris", "acne"],
            nameTerms: ["acne"],
            icdPrefixes: ["L70"],
            relatedFlagTerms: []
        ),
        DiagnosisConcept(
            id: "rosacea", label: "rosacea",
            queryTerms: ["rosacea"],
            nameTerms: ["rosacea"],
            icdPrefixes: ["L71"],
            relatedFlagTerms: []
        ),
        DiagnosisConcept(
            id: "actinicKeratosis", label: "actinic keratosis",
            queryTerms: ["actinic keratosis", "actinic keratoses", "actinic", "ak", "aks"],
            nameTerms: ["actinic kerato"],
            icdPrefixes: ["L57.0"],
            relatedFlagTerms: []
        ),
        DiagnosisConcept(
            id: "wart", label: "warts",
            queryTerms: ["verruca vulgaris", "verruca", "verrucae", "warts", "wart"],
            nameTerms: ["verruca", "wart"],
            icdPrefixes: ["B07"],
            relatedFlagTerms: []
        ),
        DiagnosisConcept(
            id: "nevus", label: "melanocytic nevus",
            queryTerms: ["dysplastic nevus", "dysplastic nevi", "atypical nevus", "atypical nevi", "atypical mole", "atypical moles", "nevus", "nevi"],
            nameTerms: ["nevus", "nevi"],
            icdPrefixes: ["D22"],
            relatedFlagTerms: []
        ),
    ]

    static let drugClasses: [DrugClass] = [
        DrugClass(
            id: "biologic", label: "biologic",
            queryTerms: ["biologic therapy", "biologic", "biologics", "monoclonal antibody", "monoclonal antibodies"],
            members: [
                "dupilumab", "dupixent", "guselkumab", "tremfya", "risankizumab", "skyrizi",
                "secukinumab", "cosentyx", "ixekizumab", "taltz", "adalimumab", "humira",
                "etanercept", "enbrel", "infliximab", "ustekinumab", "stelara", "tildrakizumab",
                "tralokinumab", "lebrikizumab", "nemolizumab", "omalizumab", "brodalumab",
                "bimekizumab", "certolizumab",
            ],
            routeRule: .any
        ),
        DrugClass(
            id: "systemicImmunosuppressant", label: "systemic immunosuppressant",
            queryTerms: [
                "systemic immunosuppressant", "systemic immunosuppressants", "immunosuppressant", "immunosuppressants",
                "immunosuppressive", "immunosuppressives", "immunosuppression", "immunomodulator", "immunomodulators",
            ],
            members: [
                "methotrexate", "cyclosporine", "azathioprine", "mycophenolate", "tacrolimus",
                "tofacitinib", "upadacitinib", "abrocitinib", "baricitinib", "deucravacitinib",
            ],
            routeRule: .systemicOnly
        ),
        DrugClass(
            id: "topicalSteroid", label: "topical corticosteroid",
            queryTerms: [
                "topical corticosteroid", "topical corticosteroids", "topical steroid", "topical steroids",
                "steroid cream", "steroid creams", "steroid ointment",
            ],
            members: [
                "clobetasol", "triamcinolone", "hydrocortisone", "betamethasone", "fluocinonide",
                "mometasone", "desonide", "halobetasol", "fluocinolone",
            ],
            routeRule: .topicalOnly
        ),
        DrugClass(
            id: "calcineurinInhibitor", label: "topical calcineurin inhibitor",
            queryTerms: ["topical calcineurin inhibitor", "topical calcineurin inhibitors", "calcineurin inhibitor", "calcineurin inhibitors"],
            members: ["tacrolimus", "pimecrolimus"],
            routeRule: .topicalOnly
        ),
        DrugClass(
            id: "retinoid", label: "retinoid",
            queryTerms: ["retinoid", "retinoids"],
            members: ["tretinoin", "adapalene", "tazarotene", "isotretinoin", "acitretin", "trifarotene"],
            routeRule: .any
        ),
        DrugClass(
            id: "anticoagulant", label: "anticoagulant",
            queryTerms: ["anticoagulant", "anticoagulants", "anticoagulated", "anticoagulation", "blood thinner", "blood thinners"],
            members: ["apixaban", "eliquis", "rivaroxaban", "xarelto", "warfarin", "coumadin", "dabigatran", "edoxaban", "enoxaparin", "heparin"],
            routeRule: .any
        ),
        DrugClass(
            id: "antibiotic", label: "antibiotic",
            queryTerms: ["antibiotic", "antibiotics"],
            members: [
                "doxycycline", "minocycline", "cephalexin", "clindamycin", "mupirocin",
                "amoxicillin", "metronidazole", "azithromycin", "trimethoprim",
            ],
            routeRule: .any
        ),
    ]

    static let risks: [RiskConcept] = [
        RiskConcept(
            id: "uvExposure", label: "UV exposure",
            queryTerms: [
                "uv exposure", "sun exposure", "ultraviolet exposure", "sun damage", "photodamage",
                "uv", "ultraviolet",
            ],
            flagTerms: ["uv exposure", "sun exposure", "ultraviolet", "photodamage", "sun damage"]
        ),
        RiskConcept(
            id: "familyHistoryMelanoma", label: "family history of melanoma",
            queryTerms: ["family history of melanoma"],
            flagTerms: ["family history of melanoma"]
        ),
    ]

    // MARK: Allergies

    /// Short forms a clinician types, mapped to the word used in a charted allergy.
    static let allergenSynonyms: [String: String] = [
        "sulfa": "sulfonamide",
        "pcn": "penicillin",
        "contrast": "contrast",
        "tape": "adhesive",
        "fragrance": "fragrance",
    ]

    static func isNoKnownAllergyEntry(_ entry: String) -> Bool {
        let text = entry.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.isEmpty { return true }
        return ["nkda", "nka", "no known drug allergies", "no known allergies", "none", "none known"].contains(text)
    }
}
