import Foundation

struct SMARTConfiguration: Decodable, Sendable {
    let authorizationEndpoint: URL
    let tokenEndpoint: URL
    let registrationEndpoint: URL?
    let introspectionEndpoint: URL?
    let revocationEndpoint: URL?
    let scopesSupported: [String]?
    let responseTypesSupported: [String]?
    let capabilities: [String]?
    let codeChallengeMethodsSupported: [String]?

    enum CodingKeys: String, CodingKey {
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case registrationEndpoint = "registration_endpoint"
        case introspectionEndpoint = "introspection_endpoint"
        case revocationEndpoint = "revocation_endpoint"
        case scopesSupported = "scopes_supported"
        case responseTypesSupported = "response_types_supported"
        case capabilities
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
    }

    /// True when the server says it issues refresh tokens for `offline_access`: the
    /// `permission-offline` capability, or the scope in `scopes_supported` (SMART App Launch 2.2.0,
    /// conformance and scopes pages, read 2026-10-08).
    var supportsOfflineAccess: Bool {
        (capabilities ?? []).contains("permission-offline") || (scopesSupported ?? []).contains(SMARTScopeSet.offlineAccess)
    }
}

struct FHIRCapabilityStatementSummary: Decodable, Sendable {
    struct Software: Decodable, Sendable {
        let name: String?
        let version: String?
    }

    struct Implementation: Decodable, Sendable {
        let description: String?
        let url: URL?
    }

    struct Coding: Decodable, Sendable {
        let system: String?
        let code: String?
        let display: String?
    }

    struct CodeableConcept: Decodable, Sendable {
        let coding: [Coding]?
        let text: String?
    }

    struct Security: Decodable, Sendable {
        let description: String?
        let service: [CodeableConcept]?
    }

    struct Rest: Decodable, Sendable {
        let mode: String?
        let security: Security?
    }

    let software: Software?
    let implementation: Implementation?
    let publisher: String?
    let fhirVersion: String?
    let format: [String]?
    let rest: [Rest]?

    var softwareLabel: String? {
        guard let software else { return nil }
        let parts = [software.name, software.version]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    var implementationLabel: String? {
        if let description = implementation?.description, !description.isEmpty {
            return description
        }
        return implementation?.url?.absoluteString
    }

    var securityServiceLabels: [String] {
        let labels = (rest ?? [])
            .flatMap { $0.security?.service ?? [] }
            .compactMap { concept in
                concept.text
                    ?? concept.coding?.first(where: { ($0.display?.isEmpty == false) || ($0.code?.isEmpty == false) })?.display
                    ?? concept.coding?.first?.code
            }

        var seen: Set<String> = []
        return labels.filter { seen.insert($0).inserted }
    }
}

struct SMARTDiscoverySummary: Sendable {
    let baseURL: URL
    let configurationURL: URL
    let metadataURL: URL
    let discoveredAt: Date
    let configuration: SMARTConfiguration?
    let capabilityStatement: FHIRCapabilityStatementSummary?
    let warnings: [String]

    var hasSMARTConfiguration: Bool { configuration != nil }
    var hasFHIRMetadata: Bool { capabilityStatement != nil }
    var capabilities: [String] { configuration?.capabilities ?? [] }
    var pkceMethods: [String] { configuration?.codeChallengeMethodsSupported ?? [] }
    var scopeCount: Int { configuration?.scopesSupported?.count ?? 0 }
    var responseTypeCount: Int { configuration?.responseTypesSupported?.count ?? 0 }
    var supportsPKCES256: Bool { pkceMethods.contains("S256") }
    var supportsDynamicRegistration: Bool { configuration?.registrationEndpoint != nil }
}

struct SMARTLaunchContext: Sendable, Equatable {
    let patientID: String?
    let encounterID: String?
    let practitionerID: String?
    let needPatientBanner: Bool

    init(
        patientID: String? = nil,
        encounterID: String? = nil,
        practitionerID: String? = nil,
        needPatientBanner: Bool = true
    ) {
        self.patientID = patientID
        self.encounterID = encounterID
        self.practitionerID = practitionerID
        self.needPatientBanner = needPatientBanner
    }
}

struct SMARTTokenResponse: Codable, Sendable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int?
    let scope: String?
    let refreshToken: String?
    let patient: String?
    let encounter: String?
    let idToken: String?
    let issuedAt: Date

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case scope
        case refreshToken = "refresh_token"
        case patient
        case encounter
        case idToken = "id_token"
        case issuedAt = "issued_at"
    }

    init(
        accessToken: String,
        tokenType: String,
        expiresIn: Int? = nil,
        scope: String? = nil,
        refreshToken: String? = nil,
        patient: String? = nil,
        encounter: String? = nil,
        idToken: String? = nil,
        issuedAt: Date = .now
    ) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.scope = scope
        self.refreshToken = refreshToken
        self.patient = patient
        self.encounter = encounter
        self.idToken = idToken
        self.issuedAt = issuedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        tokenType = try container.decode(String.self, forKey: .tokenType)
        expiresIn = try container.decodeIfPresent(Int.self, forKey: .expiresIn)
        scope = try container.decodeIfPresent(String.self, forKey: .scope)
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        patient = try container.decodeIfPresent(String.self, forKey: .patient)
        encounter = try container.decodeIfPresent(String.self, forKey: .encounter)
        idToken = try container.decodeIfPresent(String.self, forKey: .idToken)
        issuedAt = try container.decodeIfPresent(Date.self, forKey: .issuedAt) ?? .now
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encode(tokenType, forKey: .tokenType)
        try container.encodeIfPresent(expiresIn, forKey: .expiresIn)
        try container.encodeIfPresent(scope, forKey: .scope)
        try container.encodeIfPresent(refreshToken, forKey: .refreshToken)
        try container.encodeIfPresent(patient, forKey: .patient)
        try container.encodeIfPresent(encounter, forKey: .encounter)
        try container.encodeIfPresent(idToken, forKey: .idToken)
        try container.encode(issuedAt, forKey: .issuedAt)
    }

    var expirationDate: Date? {
        expiresIn.map { issuedAt.addingTimeInterval(TimeInterval($0)) }
    }

    var isExpired: Bool {
        guard let expirationDate else { return false }
        return Date() >= expirationDate
    }
}

struct SMARTAuthorizationRequest: Sendable {
    let url: URL
    let state: String
    let codeVerifier: String
    let codeChallenge: String
    let requestedScope: String
}

enum SMARTScopeSet {
    /// Read and search access to the patient and to each resource type the record import reads.
    /// A type that is read without its scope is refused by a server that enforces scopes.
    static let importedResourceTypes = [
        "Patient", "Condition", "MedicationRequest", "AllergyIntolerance", "Observation", "Encounter",
        "Procedure", "Immunization", "DiagnosticReport", "DocumentReference", "Appointment",
    ]

    /// Asks for a refresh token. It is added to a sign-in only when the server says it supports it,
    /// because a server that does not may refuse the whole request as an invalid scope.
    static let offlineAccess = "offline_access"

    static let providerRead = ["openid", "fhirUser", "profile", "launch", "launch/patient"]
        + importedResourceTypes.map { "user/\($0).rs" }

    static let patientRead = [
        "openid",
        "profile",
        "patient/Patient.rs",
        "patient/Condition.rs",
        "patient/MedicationRequest.rs",
        "patient/Observation.rs",
        "patient/DocumentReference.rs",
    ]
}
