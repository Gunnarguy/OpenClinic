//
//  FHIRR4Resources.swift
//  OpenClinic
//
//  The FHIR R4 resources a chart is built from, cut down to the fields the
//  chart mapper reads. Every field is optional, so a sparse resource still
//  decodes; a resource fails only when a field has the wrong JSON shape.
//  Dates are lenient for the same reason: see FHIRR4LenientDateTime.
//

import Foundation

nonisolated enum FHIRR4Code {
    /// The status FHIR gives a record that should never have existed.
    static let enteredInError = "entered-in-error"
}

/// What the chart mapper asks of every resource before it maps one.
nonisolated protocol FHIRR4MappedResource: Decodable, Sendable {
    /// The FHIR type name, for example `Condition`.
    static var resourceType: String { get }
    /// True when the record was entered in error and must not reach the chart.
    var isEnteredInError: Bool { get }
    /// Every date the mapper reads, as received, so the unreadable ones can be counted.
    var dateFields: [FHIRR4LenientDateTime?] { get }
}

/// The `value[x]` choices the chart reads, shared by an observation and its components.
nonisolated protocol FHIRR4ValueCarrying {
    var valueQuantity: FHIRR4Quantity? { get }
    var valueCodeableConcept: FHIRR4CodeableConcept? { get }
    var valueString: String? { get }
    var valueBoolean: Bool? { get }
    var valueInteger: Int? { get }
}

// MARK: - Patient

nonisolated struct FHIRR4Patient: FHIRR4MappedResource {
    nonisolated struct Communication: Decodable, Sendable {
        let language: FHIRR4CodeableConcept?
        let preferred: Bool?
    }

    static let resourceType = "Patient"

    let id: String?
    let identifier: [FHIRR4Identifier]?
    let name: [FHIRR4HumanName]?
    let telecom: [FHIRR4ContactPoint]?
    let gender: String?
    let birthDate: FHIRR4LenientDateTime?
    let deceasedBoolean: Bool?
    let deceasedDateTime: FHIRR4LenientDateTime?
    let address: [FHIRR4Address]?
    let maritalStatus: FHIRR4CodeableConcept?
    let communication: [Communication]?

    var isEnteredInError: Bool { false }
    var dateFields: [FHIRR4LenientDateTime?] { [birthDate, deceasedDateTime] }
}

// MARK: - Condition

nonisolated struct FHIRR4Condition: FHIRR4MappedResource {
    static let resourceType = "Condition"

    let id: String?
    let clinicalStatus: FHIRR4CodeableConcept?
    let verificationStatus: FHIRR4CodeableConcept?
    let category: [FHIRR4CodeableConcept]?
    let code: FHIRR4CodeableConcept?
    let encounter: FHIRR4Reference?
    let onsetDateTime: FHIRR4LenientDateTime?
    let abatementDateTime: FHIRR4LenientDateTime?
    let recordedDate: FHIRR4LenientDateTime?

    var isEnteredInError: Bool { verificationStatus?.hasCode(FHIRR4Code.enteredInError) ?? false }
    var dateFields: [FHIRR4LenientDateTime?] { [onsetDateTime, abatementDateTime, recordedDate] }
}

// MARK: - MedicationRequest

nonisolated struct FHIRR4MedicationRequest: FHIRR4MappedResource {
    nonisolated struct Dosage: Decodable, Sendable {
        let text: String?
        let route: FHIRR4CodeableConcept?
    }

    nonisolated struct DispenseRequest: Decodable, Sendable {
        let numberOfRepeatsAllowed: Int?
    }

    static let resourceType = "MedicationRequest"

    let id: String?
    let status: String?
    let intent: String?
    let medicationCodeableConcept: FHIRR4CodeableConcept?
    let medicationReference: FHIRR4Reference?
    let encounter: FHIRR4Reference?
    let authoredOn: FHIRR4LenientDateTime?
    let requester: FHIRR4Reference?
    let reasonCode: [FHIRR4CodeableConcept]?
    let reasonReference: [FHIRR4Reference]?
    let dosageInstruction: [Dosage]?
    let dispenseRequest: DispenseRequest?

    var isEnteredInError: Bool { status == FHIRR4Code.enteredInError }
    var dateFields: [FHIRR4LenientDateTime?] { [authoredOn] }
}

// MARK: - AllergyIntolerance

nonisolated struct FHIRR4AllergyIntolerance: FHIRR4MappedResource {
    nonisolated struct Reaction: Decodable, Sendable {
        let manifestation: [FHIRR4CodeableConcept]?
        let severity: String?
    }

    static let resourceType = "AllergyIntolerance"

    let id: String?
    let clinicalStatus: FHIRR4CodeableConcept?
    let verificationStatus: FHIRR4CodeableConcept?
    let criticality: String?
    /// Plain codes in R4: food, medication, environment or biologic.
    let category: [String]?
    let code: FHIRR4CodeableConcept?
    let reaction: [Reaction]?
    let recordedDate: FHIRR4LenientDateTime?

    var isEnteredInError: Bool { verificationStatus?.hasCode(FHIRR4Code.enteredInError) ?? false }
    var dateFields: [FHIRR4LenientDateTime?] { [recordedDate] }
}

// MARK: - Observation

nonisolated struct FHIRR4Observation: FHIRR4MappedResource, FHIRR4ValueCarrying {
    nonisolated struct Component: Decodable, Sendable, FHIRR4ValueCarrying {
        let code: FHIRR4CodeableConcept?
        let valueQuantity: FHIRR4Quantity?
        let valueCodeableConcept: FHIRR4CodeableConcept?
        let valueString: String?
        let valueBoolean: Bool?
        let valueInteger: Int?
    }

    nonisolated struct ReferenceRange: Decodable, Sendable {
        let low: FHIRR4Quantity?
        let high: FHIRR4Quantity?
        let text: String?
    }

    static let resourceType = "Observation"

    let id: String?
    let status: String?
    let category: [FHIRR4CodeableConcept]?
    let code: FHIRR4CodeableConcept?
    let encounter: FHIRR4Reference?
    let effectiveDateTime: FHIRR4LenientDateTime?
    let effectivePeriod: FHIRR4Period?
    let issued: FHIRR4LenientDateTime?
    let valueQuantity: FHIRR4Quantity?
    let valueCodeableConcept: FHIRR4CodeableConcept?
    let valueString: String?
    let valueBoolean: Bool?
    let valueInteger: Int?
    let interpretation: [FHIRR4CodeableConcept]?
    let referenceRange: [ReferenceRange]?
    let component: [Component]?

    var isEnteredInError: Bool { status == FHIRR4Code.enteredInError }
    var dateFields: [FHIRR4LenientDateTime?] { [effectiveDateTime, effectivePeriod?.start, issued] }
}

// MARK: - Encounter

nonisolated struct FHIRR4Encounter: FHIRR4MappedResource {
    nonisolated struct Participant: Decodable, Sendable {
        let individual: FHIRR4Reference?
    }

    nonisolated struct Location: Decodable, Sendable {
        let location: FHIRR4Reference?
    }

    // `class` is a Swift keyword, so the keys are spelled out.
    nonisolated enum CodingKeys: String, CodingKey {
        case id, status, type, reasonCode, period, participant, location, serviceProvider
        case classCoding = "class"
    }

    static let resourceType = "Encounter"

    let id: String?
    let status: String?
    /// v3-ActCode: AMB, IMP, EMER and so on. A single Coding in R4.
    let classCoding: FHIRR4Coding?
    let type: [FHIRR4CodeableConcept]?
    let reasonCode: [FHIRR4CodeableConcept]?
    let period: FHIRR4Period?
    let participant: [Participant]?
    let location: [Location]?
    let serviceProvider: FHIRR4Reference?

    var isEnteredInError: Bool { status == FHIRR4Code.enteredInError }
    var dateFields: [FHIRR4LenientDateTime?] { [period?.start, period?.end] }
}

// MARK: - Procedure

nonisolated struct FHIRR4Procedure: FHIRR4MappedResource {
    static let resourceType = "Procedure"

    let id: String?
    let status: String?
    let code: FHIRR4CodeableConcept?
    let encounter: FHIRR4Reference?
    let performedDateTime: FHIRR4LenientDateTime?
    let performedPeriod: FHIRR4Period?
    let reasonCode: [FHIRR4CodeableConcept]?
    let reasonReference: [FHIRR4Reference]?

    var isEnteredInError: Bool { status == FHIRR4Code.enteredInError }
    var dateFields: [FHIRR4LenientDateTime?] { [performedDateTime, performedPeriod?.start, performedPeriod?.end] }
}

// MARK: - Immunization

nonisolated struct FHIRR4Immunization: FHIRR4MappedResource {
    static let resourceType = "Immunization"

    let id: String?
    let status: String?
    let vaccineCode: FHIRR4CodeableConcept?
    let occurrenceDateTime: FHIRR4LenientDateTime?
    let primarySource: Bool?

    var isEnteredInError: Bool { status == FHIRR4Code.enteredInError }
    var dateFields: [FHIRR4LenientDateTime?] { [occurrenceDateTime] }
}

// MARK: - DiagnosticReport

nonisolated struct FHIRR4DiagnosticReport: FHIRR4MappedResource {
    static let resourceType = "DiagnosticReport"

    let id: String?
    let status: String?
    let category: [FHIRR4CodeableConcept]?
    let code: FHIRR4CodeableConcept?
    let effectiveDateTime: FHIRR4LenientDateTime?
    let effectivePeriod: FHIRR4Period?
    let issued: FHIRR4LenientDateTime?
    let conclusion: String?
    let result: [FHIRR4Reference]?
    let presentedForm: [FHIRR4Attachment]?

    var isEnteredInError: Bool { status == FHIRR4Code.enteredInError }
    var dateFields: [FHIRR4LenientDateTime?] { [effectiveDateTime, effectivePeriod?.start, issued] }
}

// MARK: - DocumentReference

nonisolated struct FHIRR4DocumentReference: FHIRR4MappedResource {
    nonisolated struct Content: Decodable, Sendable {
        let attachment: FHIRR4Attachment?
    }

    static let resourceType = "DocumentReference"

    let id: String?
    /// Whether the reference stands: current, superseded or entered-in-error.
    let status: String?
    /// The state of the document itself, which can be entered-in-error on its own.
    let docStatus: String?
    let type: FHIRR4CodeableConcept?
    let description: String?
    let date: FHIRR4LenientDateTime?
    let author: [FHIRR4Reference]?
    let content: [Content]?

    var isEnteredInError: Bool { status == FHIRR4Code.enteredInError || docStatus == FHIRR4Code.enteredInError }
    var dateFields: [FHIRR4LenientDateTime?] { [date] }
}

// MARK: - Appointment

nonisolated struct FHIRR4Appointment: FHIRR4MappedResource {
    nonisolated struct Participant: Decodable, Sendable {
        let actor: FHIRR4Reference?
        let status: String?
    }

    static let resourceType = "Appointment"

    let id: String?
    let status: String?
    let start: FHIRR4LenientDateTime?
    let end: FHIRR4LenientDateTime?
    let minutesDuration: Int?
    let description: String?
    let reasonCode: [FHIRR4CodeableConcept]?
    let serviceType: [FHIRR4CodeableConcept]?
    let participant: [Participant]?

    var isEnteredInError: Bool { status == FHIRR4Code.enteredInError }
    var dateFields: [FHIRR4LenientDateTime?] { [start, end] }
}

// MARK: - OperationOutcome

/// The body a server sends with an error status.
nonisolated struct FHIRR4OperationOutcome: Decodable, Sendable {
    nonisolated struct Issue: Decodable, Sendable {
        let severity: String?
        let code: String?
        let diagnostics: String?
        let details: FHIRR4CodeableConcept?
    }

    let resourceType: String?
    let issue: [Issue]?

    /// True when the JSON really was an OperationOutcome. Every field is optional,
    /// so any JSON object decodes; this is what tells an outcome from another body.
    var isOperationOutcome: Bool { resourceType == "OperationOutcome" }

    /// One line for a person: each issue in the server's most specific wording.
    var summary: String {
        var lines: [String] = []
        for issue in issue ?? [] {
            let line = FHIRR4Text.nonEmpty(issue.diagnostics)
                ?? issue.details?.bestDisplay
                ?? FHIRR4Text.nonEmpty(issue.code)
            if let line, !lines.contains(line) {
                lines.append(line)
            }
        }
        return lines.isEmpty ? "The server reported an error and gave no details." : lines.joined(separator: "; ")
    }
}
