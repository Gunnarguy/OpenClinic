//
//  ImportedChart.swift
//  OpenClinic
//
//  What one patient's record looks like after it has been read from a FHIR R4
//  server and before it touches the local store. These are plain values: the
//  FHIR mapper produces them, tests compare them, and the chart importer
//  applies them to SwiftData. Nothing here knows about HTTP or persistence.
//

import Foundation

/// Where an imported fact came from: one resource on one server.
nonisolated struct ImportedSource: Sendable, Hashable, Codable {
    /// The server's FHIR base URL, without a trailing slash.
    let serverBase: String
    let resourceType: String
    let resourceID: String
    let versionID: String?
    let lastUpdated: Date?

    /// Unique across servers, for example `https://r4.smarthealthit.org/Condition/297f04aa`.
    var qualifiedID: String { "\(serverBase)/\(resourceType)/\(resourceID)" }
    /// The relative reference other resources use, for example `Condition/297f04aa`.
    var reference: String { "\(resourceType)/\(resourceID)" }
}

/// A coded concept reduced to the coding the chart keeps and the text it shows.
nonisolated struct ImportedCode: Sendable, Hashable, Codable {
    var system: String?
    var code: String?
    var display: String
}

/// The value of an observation or of one of its components.
nonisolated enum ImportedValue: Sendable, Hashable, Codable {
    case quantity(Double, unit: String?)
    case text(String)
    case boolean(Bool)
}

nonisolated struct ImportedComponent: Sendable, Hashable, Codable {
    var code: ImportedCode
    var value: ImportedValue?
}

nonisolated struct ImportedPatient: Sendable, Hashable {
    var source: ImportedSource
    var mrn: String
    var mrnSystem: String?
    var givenName: String
    var familyName: String
    var birthDate: Date?
    /// Administrative sex as the chart shows it: "Female", "Male", "Other" or "Unknown".
    var sex: String
    var deceasedDate: Date?
    var phone: String?
    var addressLine: String?
    var city: String?
    var state: String?
    var postalCode: String?
    var language: String?
    var maritalStatus: String?
}

nonisolated struct ImportedProblem: Sendable, Hashable {
    var source: ImportedSource
    var code: ImportedCode
    /// FHIR condition-clinical code: active, recurrence, relapse, inactive, remission or resolved.
    var clinicalStatus: String
    var verificationStatus: String?
    /// problem-list-item or encounter-diagnosis, when the server says.
    var category: String?
    var onset: Date?
    var abatement: Date?
    var recorded: Date?
    /// Relative reference of the encounter, for example `Encounter/bd501f8d`.
    var encounterReference: String?
}

nonisolated struct ImportedMedication: Sendable, Hashable {
    var source: ImportedSource
    var code: ImportedCode
    /// FHIR medicationrequest-status: active, on-hold, cancelled, completed, stopped, draft or unknown.
    var status: String
    var intent: String?
    var authoredOn: Date?
    var requester: String?
    var dosageText: String?
    var route: String?
    var refills: Int?
    var reason: String?
    var encounterReference: String?
}

nonisolated struct ImportedAllergy: Sendable, Hashable {
    var source: ImportedSource
    var substance: ImportedCode
    var clinicalStatus: String?
    var verificationStatus: String?
    var criticality: String?
    var categories: [String]
    var reactions: [String]
    var recorded: Date?
}

nonisolated struct ImportedObservation: Sendable, Hashable {
    var source: ImportedSource
    /// First observation-category code: vital-signs, laboratory, social-history, survey, exam or other.
    var category: String
    var code: ImportedCode
    var effective: Date?
    var issued: Date?
    var status: String
    var value: ImportedValue?
    var components: [ImportedComponent]
    var interpretation: String?
    var referenceRange: String?
    var encounterReference: String?
}

nonisolated struct ImportedEncounter: Sendable, Hashable {
    var source: ImportedSource
    /// v3-ActCode class: AMB, IMP, EMER and so on.
    var classCode: String?
    var type: String
    var reason: String?
    var status: String
    var start: Date?
    var end: Date?
    var practitioner: String?
    var location: String?
    var serviceProvider: String?
}

nonisolated struct ImportedProcedure: Sendable, Hashable {
    var source: ImportedSource
    var code: ImportedCode
    var status: String
    var performedStart: Date?
    var performedEnd: Date?
    var reason: String?
    var encounterReference: String?
}

nonisolated struct ImportedImmunization: Sendable, Hashable {
    var source: ImportedSource
    var vaccine: ImportedCode
    var status: String
    var occurrence: Date?
    var primarySource: Bool?
}

nonisolated struct ImportedReport: Sendable, Hashable {
    var source: ImportedSource
    var code: ImportedCode
    var category: String?
    var status: String
    var effective: Date?
    var issued: Date?
    var conclusion: String?
    /// Relative references of the result observations, for example `Observation/81b17262`.
    var resultReferences: [String]
    /// Plain text of the presented form, when the report carries one.
    var presentedText: String?
}

nonisolated struct ImportedDocument: Sendable, Hashable {
    var source: ImportedSource
    var type: String
    var summary: String?
    var date: Date?
    var author: String?
    var status: String
    var contentType: String?
    /// Plain text of the first attachment that could be read. HTML is reduced to text.
    var text: String?
}

nonisolated struct ImportedAppointment: Sendable, Hashable {
    var source: ImportedSource
    var status: String
    var start: Date?
    var end: Date?
    var minutesDuration: Int?
    var summary: String?
    var reason: String?
    var practitioner: String?
}

/// One patient's record as read from a server, with everything that was left out and why.
nonisolated struct ImportedChart: Sendable {
    var patient: ImportedPatient
    var problems: [ImportedProblem] = []
    var medications: [ImportedMedication] = []
    var allergies: [ImportedAllergy] = []
    var observations: [ImportedObservation] = []
    var encounters: [ImportedEncounter] = []
    var procedures: [ImportedProcedure] = []
    var immunizations: [ImportedImmunization] = []
    var reports: [ImportedReport] = []
    var documents: [ImportedDocument] = []
    var appointments: [ImportedAppointment] = []
    /// Human-readable notes about anything skipped: a resource type the server refused,
    /// a resource marked entered-in-error, a page limit that was reached.
    var warnings: [String] = []
    /// Resource types whose search stopped at the page limit, so the list may be incomplete.
    var truncatedTypes: [String] = []
    /// Resource types whose search failed, so their lists are empty for a reason other than
    /// "the patient has none". The importer must not treat these as removed at the source.
    var failedTypes: [String] = []
    /// Resource types with at least one resource that could not be decoded. That resource is
    /// missing from its list although the server still has it, so the importer must not treat
    /// rows of these types as removed at the source.
    var unreadableTypes: [String] = []

    /// How many facts of each kind were read, in display order.
    var counts: [(label: String, count: Int)] {
        [
            ("Problems", problems.count),
            ("Medications", medications.count),
            ("Allergies", allergies.count),
            ("Observations", observations.count),
            ("Encounters", encounters.count),
            ("Procedures", procedures.count),
            ("Immunizations", immunizations.count),
            ("Reports", reports.count),
            ("Documents", documents.count),
            ("Appointments", appointments.count),
        ]
    }
}
