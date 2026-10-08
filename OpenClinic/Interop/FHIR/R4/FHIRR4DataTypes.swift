//
//  FHIRR4DataTypes.swift
//  OpenClinic
//
//  The FHIR R4 data types the chart reads. Every field is optional: servers
//  leave out far more than the specification suggests, and a missing display
//  name is no reason to lose a medication. Only the fields the chart uses are
//  declared, and anything else in the JSON is ignored.
//

import Foundation

/// Small string helpers shared by the data types and the chart mapper.
nonisolated enum FHIRR4Text {
    /// The string without surrounding white space, or nil when nothing is left.
    /// Servers send empty strings where they mean "absent".
    static func nonEmpty(_ string: String?) -> String? {
        guard let trimmed = string?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

nonisolated struct FHIRR4Coding: Decodable, Sendable, Hashable {
    let system: String?
    let code: String?
    let display: String?
}

nonisolated struct FHIRR4CodeableConcept: Decodable, Sendable, Hashable {
    let coding: [FHIRR4Coding]?
    let text: String?

    /// What to show a person: the text the author wrote, else the first coding's
    /// display name, else a bare code, which is still better than nothing.
    var bestDisplay: String? {
        if let text = FHIRR4Text.nonEmpty(text) { return text }
        let codings = coding ?? []
        for coding in codings {
            if let display = FHIRR4Text.nonEmpty(coding.display) { return display }
        }
        for coding in codings {
            if let code = FHIRR4Text.nonEmpty(coding.code) { return code }
        }
        return nil
    }

    /// The first code present, for status concepts where only the code matters.
    var firstCode: String? {
        for coding in coding ?? [] {
            if let code = FHIRR4Text.nonEmpty(coding.code) { return code }
        }
        return nil
    }

    func coding(inSystem system: String) -> FHIRR4Coding? {
        coding?.first { $0.system == system }
    }

    func hasCode(_ code: String) -> Bool {
        coding?.contains { $0.code == code } ?? false
    }
}

nonisolated struct FHIRR4Reference: Decodable, Sendable, Hashable {
    let reference: String?
    let display: String?

    /// The resource type named by the reference, for example `Encounter`.
    /// Nil for `urn:uuid:` references, which name no type, and for contained ones.
    var resourceType: String? { target?.type }

    /// The logical id the reference points at.
    var id: String? { target?.id }

    /// `Type/id`, the form the chart stores, whatever form the server used.
    var relativeReference: String? {
        guard let target, let type = target.type else { return nil }
        return "\(type)/\(target.id)"
    }

    /// Reads the three forms servers use: `Type/id`, an absolute URL ending in
    /// `/Type/id`, and `urn:uuid:`. A version suffix (`/_history/3`) is dropped.
    private var target: (type: String?, id: String)? {
        guard let reference = FHIRR4Text.nonEmpty(reference), !reference.hasPrefix("#") else { return nil }

        let uuidPrefix = "urn:uuid:"
        if reference.lowercased().hasPrefix(uuidPrefix) {
            let id = String(reference.dropFirst(uuidPrefix.count))
            return id.isEmpty ? nil : (nil, id)
        }

        var segments = reference.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if segments.count >= 4, segments[segments.count - 2] == "_history" {
            segments.removeLast(2)
        }
        guard segments.count >= 2 else { return nil }
        let type = segments[segments.count - 2]
        let id = segments[segments.count - 1]
        guard Self.looksLikeResourceType(type), !id.contains(where: \.isWhitespace) else { return nil }
        return (type, id)
    }

    /// Resource type names are ASCII letters starting with a capital, which is
    /// what tells `Patient/1` from the last two segments of an unrelated URL.
    private static func looksLikeResourceType(_ string: String) -> Bool {
        guard let first = string.unicodeScalars.first, ("A"..."Z").contains(first) else { return false }
        return string.unicodeScalars.allSatisfy { ("A"..."Z").contains($0) || ("a"..."z").contains($0) }
    }
}

nonisolated struct FHIRR4Quantity: Decodable, Sendable, Hashable {
    let value: Double?
    let comparator: String?
    let unit: String?
    let system: String?
    let code: String?

    /// The unit as written for people, else the coded unit.
    var bestUnit: String? {
        FHIRR4Text.nonEmpty(unit) ?? FHIRR4Text.nonEmpty(code)
    }
}

nonisolated struct FHIRR4Period: Decodable, Sendable, Hashable {
    let start: FHIRR4LenientDateTime?
    let end: FHIRR4LenientDateTime?
}

nonisolated struct FHIRR4Identifier: Decodable, Sendable, Hashable {
    let use: String?
    let type: FHIRR4CodeableConcept?
    let system: String?
    let value: String?
}

nonisolated struct FHIRR4HumanName: Decodable, Sendable, Hashable {
    let use: String?
    let text: String?
    let family: String?
    let given: [String]?
    let prefix: [String]?
    let suffix: [String]?
}

nonisolated struct FHIRR4ContactPoint: Decodable, Sendable, Hashable {
    let system: String?
    let value: String?
    let use: String?
}

nonisolated struct FHIRR4Address: Decodable, Sendable, Hashable {
    let use: String?
    let text: String?
    let line: [String]?
    let city: String?
    let state: String?
    let postalCode: String?
    let country: String?
}

nonisolated struct FHIRR4Meta: Decodable, Sendable, Hashable {
    let versionId: String?
    let lastUpdated: FHIRR4LenientDateTime?
}

nonisolated struct FHIRR4Attachment: Decodable, Sendable, Hashable {
    let contentType: String?
    /// Base64, as FHIR carries inline bytes.
    let data: String?
    let url: String?
    let title: String?
}

nonisolated struct FHIRR4Annotation: Decodable, Sendable, Hashable {
    let authorString: String?
    let authorReference: FHIRR4Reference?
    let time: FHIRR4LenientDateTime?
    let text: String?
}
