import Foundation
import Combine
import SwiftData
import os

struct SMARTSandboxPreset: Identifiable, Hashable {
    let name: String
    let baseURL: String
    let notes: String
    let suggestedPatientID: String?
    let defaultClientID: String?

    var id: String { name }

    static let smartR4 = SMARTSandboxPreset(
        name: "SMART R4 Sandbox",
        baseURL: "https://launch.smarthealthit.org/v/r4/fhir",
        notes: "OpenClinic can use the SMART R4 sandbox as a public client with its built-in redirect URI. No manual client registration is required for the sandbox preset.",
        suggestedPatientID: nil,
        defaultClientID: "medmod-ios-public"
    )

    static let custom = SMARTSandboxPreset(
        name: "Custom Server",
        baseURL: "",
        notes: "Use a SMART-compatible authorization server or paste a sandbox access token for manual import.",
        suggestedPatientID: nil,
        defaultClientID: nil
    )

    static let all: [SMARTSandboxPreset] = [.smartR4, .custom]
}

enum SMARTConnectionControllerError: LocalizedError {
    case missingClientID
    case invalidBaseURL
    case noPendingAuthorization
    case stateMismatch
    case missingPatientContext
    case missingAccessToken
    case authenticationSessionFailed

    var errorDescription: String? {
        switch self {
        case .missingClientID:
            return "A SMART client ID is required before starting authorization."
        case .invalidBaseURL:
            return "Enter a valid FHIR base URL before connecting."
        case .noPendingAuthorization:
            return "There is no pending SMART authorization request to complete."
        case .stateMismatch:
            return "The SMART redirect state did not match the pending authorization request."
        case .missingPatientContext:
            return "No patient context is available yet. Enter a patient ID or launch with a patient context."
        case .missingAccessToken:
            return "Authorize with SMART or paste an access token before importing data."
        case .authenticationSessionFailed:
            return "OpenClinic could not present the SMART sign-in sheet. Try again."
        }
    }
}

@MainActor
final class SMARTConnectionController: ObservableObject {
    private enum StorageKey {
        static let tokenResponse = "smart.savedTokenResponse"
        static let baseURLText = "smart.savedBaseURLText"
        static let patientIDText = "smart.savedPatientIDText"
        static let clientID = "smart.savedClientID"
    }

    @Published var selectedPreset: SMARTSandboxPreset = .smartR4 {
        didSet {
            if oldValue != selectedPreset, !selectedPreset.baseURL.isEmpty {
                baseURLText = selectedPreset.baseURL
            }

            if oldValue != selectedPreset,
               let defaultClientID = selectedPreset.defaultClientID,
               clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                clientID = defaultClientID
            }
        }
    }
    @Published var baseURLText: String = SMARTSandboxPreset.smartR4.baseURL
    @Published var clientID: String = ""
    @Published var clientSecret: String = ""
    @Published var launchToken: String = ""
    @Published var patientIDText: String = ""
    @Published var manualAccessToken: String = ""
    @Published private(set) var pendingAuthorizationRequest: SMARTAuthorizationRequest?
    @Published private(set) var lastImportSummary: FHIRImportSummary?
    @Published private(set) var lastDiscoverySummary: SMARTDiscoverySummary?
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var isDiscovering = false
    @Published private(set) var isAuthorizing = false
    @Published private(set) var isImporting = false

    let session: SMARTSession

    private let fhirClient: FHIRClient
    private let importService: FHIRImportService
    private let webAuthenticationCoordinator = SMARTWebAuthenticationCoordinator()
    private let defaults = UserDefaults.standard
    private var cancellables: Set<AnyCancellable> = []

    init(session: SMARTSession? = nil, fhirClient: FHIRClient? = nil) {
        self.session = session ?? SMARTSession()
        let resolvedFHIRClient = fhirClient ?? FHIRClient()
        self.fhirClient = resolvedFHIRClient
        self.importService = FHIRImportService(client: resolvedFHIRClient)

        self.session.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        restorePersistedSession()
    }

    var redirectURI: URL {
        // Keep the legacy callback URI registered with the SMART sandbox public client.
        URL(string: "medmod://smart-callback")!
    }

    var fhirBaseURL: URL? {
        URL(string: baseURLText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var canBeginInteractiveAuthorization: Bool {
        guard fhirBaseURL != nil else { return false }
        if isDiscovering || isAuthorizing { return false }

        if selectedPreset.defaultClientID != nil {
            return true
        }

        return !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func prepareSMARTSandboxDemo() async {
        selectedPreset = .smartR4
        baseURLText = SMARTSandboxPreset.smartR4.baseURL
        applyPresetDefaultClientIDIfNeeded()
        lastErrorMessage = nil
        persistSessionState()

        if !manualAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            applyManualAccessToken()
        } else {
            statusMessage = "SMART sandbox preset loaded. Use OpenClinic's in-app SMART sign-in, or paste a bearer token if you need a manual fallback."
        }

        await discoverConfiguration()

        guard lastErrorMessage == nil else { return }

        if session.isAuthorized {
            statusMessage = "SMART sandbox is ready. Import the live patient when you're ready."
        } else {
            statusMessage = "SMART sandbox is ready. Sign in with SMART to fetch a real token, or paste a bearer token if you need a manual fallback."
        }
    }

    func connectSMARTSandboxEndToEnd() async {
        selectedPreset = .smartR4
        baseURLText = SMARTSandboxPreset.smartR4.baseURL
        applyPresetDefaultClientIDIfNeeded()
        await authorizeInApp()
    }

    func authorizeInApp() async {
        guard let callbackScheme = redirectURI.scheme else {
            setError("The SMART redirect URI is invalid.")
            return
        }

        applyPresetDefaultClientIDIfNeeded()

        // Reset any existing session to ensure a fresh web authentication sheet is presented
        session.reset()
        persistSessionState()

        do {
            await discoverConfiguration()
            guard lastErrorMessage == nil else { return }

            let authorizationURL = try await beginAuthorization()
            statusMessage = "Presenting SMART sign-in…"
            let callbackURL = try await webAuthenticationCoordinator.authenticate(
                url: authorizationURL,
                callbackScheme: callbackScheme
            )
            await handleOpenURL(callbackURL)
        } catch is CancellationError {
            pendingAuthorizationRequest = nil
            isAuthorizing = false
            lastErrorMessage = nil
            statusMessage = "SMART sign-in canceled."
            AppLogger.smart.info("SMART sign-in canceled by user")
        } catch {
            pendingAuthorizationRequest = nil
            isAuthorizing = false
            AppLogger.smart.error("SMART in-app sign-in failed: \(error.localizedDescription)")
            setError(error.localizedDescription)
        }
    }

    func discoverConfiguration() async {
        guard let baseURL = fhirBaseURL else {
            setError(SMARTConnectionControllerError.invalidBaseURL.localizedDescription)
            return
        }

        isDiscovering = true
        lastErrorMessage = nil
        statusMessage = "Discovering SMART configuration and FHIR metadata…"
        AppLogger.smart.info("Starting SMART discovery for \(baseURL.absoluteString)")
        defer { isDiscovering = false }

        let configurationURL = session.smartConfigurationURL(for: baseURL)
        let metadataURL = session.capabilityStatementURL(for: baseURL)
        var warnings: [String] = []
        var capabilityStatement: FHIRCapabilityStatementSummary?

        do {
            capabilityStatement = try await session.fetchCapabilityStatement(baseURL: baseURL)
        } catch {
            warnings.append("FHIR metadata unavailable: \(error.localizedDescription)")
        }

        do {
            let configuration = try await session.discoverConfiguration(baseURL: baseURL)
            let summary = SMARTDiscoverySummary(
                baseURL: baseURL,
                configurationURL: configurationURL,
                metadataURL: metadataURL,
                discoveredAt: .now,
                configuration: configuration,
                capabilityStatement: capabilityStatement,
                warnings: warnings
            )
            lastDiscoverySummary = summary
            statusMessage = "Discovered SMART endpoints from \(configuration.authorizationEndpoint.host() ?? baseURL.host() ?? "server")."
            AppLogger.smart.info("SMART discovery completed successfully")
        } catch {
            warnings.append("SMART well-known discovery failed: \(error.localizedDescription)")
            lastDiscoverySummary = SMARTDiscoverySummary(
                baseURL: baseURL,
                configurationURL: configurationURL,
                metadataURL: metadataURL,
                discoveredAt: .now,
                configuration: nil,
                capabilityStatement: capabilityStatement,
                warnings: warnings
            )
            AppLogger.smart.error("SMART discovery failed: \(error.localizedDescription)")
            setError(error.localizedDescription)
        }
    }

    func beginAuthorization() async throws -> URL {
        guard let baseURL = fhirBaseURL else {
            throw SMARTConnectionControllerError.invalidBaseURL
        }
        applyPresetDefaultClientIDIfNeeded()

        let resolvedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resolvedClientID.isEmpty else {
            throw SMARTConnectionControllerError.missingClientID
        }

        let resolvedLaunchToken = launchToken.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? defaultLaunchTokenForSelectedPreset()

        lastErrorMessage = nil
        statusMessage = nil
        isAuthorizing = true
        AppLogger.smart.info("Beginning SMART authorization for \(baseURL.absoluteString)")

        do {
            if session.configuration == nil || lastDiscoverySummary?.baseURL != baseURL {
                _ = try await session.discoverConfiguration(baseURL: baseURL)
            }

            let authorizationRequest = try session.makeAuthorizationRequest(
                clientID: resolvedClientID,
                redirectURI: redirectURI,
                fhirBaseURL: baseURL,
                scope: SMARTScopeSet.providerRead,
                launch: resolvedLaunchToken
            )

            pendingAuthorizationRequest = authorizationRequest
            statusMessage = "Opening SMART authorization flow…"
            AppLogger.smart.info("SMART authorization request stored; awaiting callback")
            return authorizationRequest.url
        } catch {
            isAuthorizing = false
            AppLogger.smart.error("SMART authorization setup failed: \(error.localizedDescription)")
            throw error
        }
    }

    func handleOpenURL(_ url: URL) async {
        guard url.scheme == redirectURI.scheme else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryKeys = (components?.queryItems ?? []).map(\.name).joined(separator: ",")
        AppLogger.smart.info("Received SMART callback with query items: \(queryKeys.isEmpty ? "<none>" : queryKeys)")

        defer { isAuthorizing = false }

        do {
            guard let pendingAuthorizationRequest else {
                AppLogger.smart.info("Ignoring SMART callback because there is no pending authorization request")
                return
            }

            if let returnedState = components?.queryItems?.first(where: { $0.name == "state" })?.value,
               returnedState != pendingAuthorizationRequest.state {
                AppLogger.smart.error("SMART callback state mismatch")
                throw SMARTConnectionControllerError.stateMismatch
            }

            if let authorizationError = components?.queryItems?.first(where: { $0.name == "error" })?.value {
                let authorizationErrorDescription = components?.queryItems?.first(where: { $0.name == "error_description" })?.value
                if let authorizationErrorDescription, !authorizationErrorDescription.isEmpty {
                    AppLogger.smart.error("SMART authorization endpoint returned error: \(authorizationError) — \(authorizationErrorDescription)")
                    throw NSError(
                        domain: "SMARTAuthorization",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "\(authorizationError): \(authorizationErrorDescription)"]
                    )
                }

                AppLogger.smart.error("SMART authorization endpoint returned error: \(authorizationError)")
                throw NSError(domain: "SMARTAuthorization", code: 1, userInfo: [NSLocalizedDescriptionKey: authorizationError])
            }

            let code = try session.handleRedirectURL(url)
            AppLogger.smart.info("SMART callback contained authorization code; starting token exchange")
            let token = try await session.exchangeCodeForToken(
                code: code,
                codeVerifier: pendingAuthorizationRequest.codeVerifier,
                clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
                redirectURI: redirectURI,
                clientSecret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )

            fhirClient.setAccessToken(token.accessToken)
            if patientIDText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                patientIDText = token.patient ?? ""
            }
            persistSessionState()
            statusMessage = "SMART authorization completed. Access token ready for FHIR import."
            lastErrorMessage = nil
            self.pendingAuthorizationRequest = nil
            AppLogger.smart.info("SMART authorization completed and pending request cleared")
        } catch {
            AppLogger.smart.error("SMART callback handling failed: \(error.localizedDescription)")
            setError(error.localizedDescription)
        }
    }

    func applyManualAccessToken() {
        let trimmedToken = manualAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            setError(SMARTConnectionControllerError.missingAccessToken.localizedDescription)
            return
        }

        let tokenContext = SMARTManualAccessTokenContext.decode(from: trimmedToken)
        let resolvedPatientID = patientIDText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? tokenContext?.patientID
        let resolvedEncounterID = tokenContext?.encounterID

        fhirClient.setAccessToken(trimmedToken)
        if patientIDText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let resolvedPatientID {
            patientIDText = resolvedPatientID
        }
        if let tokenContext {
            session.updateLaunchContext(
                SMARTLaunchContext(
                    patientID: resolvedPatientID,
                    encounterID: resolvedEncounterID,
                    practitionerID: session.launchContext.practitionerID,
                    needPatientBanner: tokenContext.needPatientBanner ?? session.launchContext.needPatientBanner
                )
            )
            AppLogger.smart.info("Manual SMART access token decoded. Patient context present: \(resolvedPatientID != nil)")
        }
        let token = SMARTTokenResponse(
            accessToken: trimmedToken,
            tokenType: "Bearer",
            expiresIn: tokenContext?.expiresIn,
            patient: resolvedPatientID,
            encounter: resolvedEncounterID,
            issuedAt: tokenContext?.issuedAtDate ?? .now
        )
        session.applyTokenResponse(token)
        persistSessionState()
        lastErrorMessage = nil
        statusMessage = resolvedPatientID == nil ?
            "Manual access token applied for sandbox import." :
            "Manual access token applied and patient context loaded for import."
    }

    func disconnect() {
        session.reset()
        patientIDText = ""
        manualAccessToken = ""
        lastImportSummary = nil
        lastDiscoverySummary = nil
        lastErrorMessage = nil
        statusMessage = "SMART connection cleared."
        persistSessionState()
    }

    func importLaunchPatient(modelContext: ModelContext) async {
        let patientID = session.launchContext.patientID
            ?? session.tokenResponse?.patient
            ?? patientIDText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        await importPatient(patientID: patientID, modelContext: modelContext)
    }

    func importTypedPatient(modelContext: ModelContext) async {
        let patientID = patientIDText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        await importPatient(patientID: patientID, modelContext: modelContext)
    }

    private func importPatient(patientID: String?, modelContext: ModelContext) async {
        guard let baseURL = fhirBaseURL else {
            setError(SMARTConnectionControllerError.invalidBaseURL.localizedDescription)
            return
        }
        guard let patientID else {
            setError(SMARTConnectionControllerError.missingPatientContext.localizedDescription)
            return
        }
        guard session.tokenResponse != nil || !manualAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            setError(SMARTConnectionControllerError.missingAccessToken.localizedDescription)
            return
        }

        isImporting = true
        lastErrorMessage = nil
        defer { isImporting = false }

        do {
            let summary = try await importService.importPatientContext(patientID: patientID, baseURL: baseURL, modelContext: modelContext)
            lastImportSummary = summary
            statusMessage = "Imported sandbox data for \(summary.patientName)."
        } catch {
            setError(error.localizedDescription)
        }
    }

    func setError(_ message: String?) {
        lastErrorMessage = message
        if message != nil {
            statusMessage = nil
        }
    }

    private func applyPresetDefaultClientIDIfNeeded() {
        guard let defaultClientID = selectedPreset.defaultClientID else { return }
        if clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            clientID = defaultClientID
        }
    }

    private func defaultLaunchTokenForSelectedPreset() -> String? {
        guard selectedPreset == .smartR4 else { return nil }

        let launchPayload: [Any] = [
            2,
            "",
            "",
            "AUTO",
            0,
            0,
            0,
            "",
            "",
            "",
            "",
            "",
            "",
            "",
            0,
            1,
            ""
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: launchPayload) else {
            return nil
        }

        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func persistSessionState() {
        defaults.set(baseURLText, forKey: StorageKey.baseURLText)
        defaults.set(patientIDText, forKey: StorageKey.patientIDText)
        defaults.set(clientID, forKey: StorageKey.clientID)

        guard let tokenResponse = session.tokenResponse,
              let encoded = try? JSONEncoder().encode(tokenResponse) else {
            defaults.removeObject(forKey: StorageKey.tokenResponse)
            return
        }

        defaults.set(encoded, forKey: StorageKey.tokenResponse)
    }

    private func restorePersistedSession() {
        if let savedBaseURL = defaults.string(forKey: StorageKey.baseURLText), !savedBaseURL.isEmpty {
            baseURLText = savedBaseURL
            selectedPreset = savedBaseURL == SMARTSandboxPreset.smartR4.baseURL ? .smartR4 : .custom
        }

        if let savedPatientID = defaults.string(forKey: StorageKey.patientIDText), !savedPatientID.isEmpty {
            patientIDText = savedPatientID
        }

        if let savedClientID = defaults.string(forKey: StorageKey.clientID), !savedClientID.isEmpty {
            clientID = savedClientID
        }

        guard let data = defaults.data(forKey: StorageKey.tokenResponse),
              let tokenResponse = try? JSONDecoder().decode(SMARTTokenResponse.self, from: data) else {
            return
        }

        session.applyTokenResponse(tokenResponse)
        fhirClient.setAccessToken(tokenResponse.accessToken)

        if patientIDText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let patient = tokenResponse.patient {
            patientIDText = patient
        }

        statusMessage = tokenResponse.isExpired ?
            "Saved SMART session restored, but the token is expired. Paste a fresh token or sign in with SMART again to continue." :
            "Saved SMART session restored."
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct SMARTManualAccessTokenContext: Decodable {
    struct Context: Decodable {
        let patient: String?
        let encounter: String?
        let needPatientBanner: Bool?

        enum CodingKeys: String, CodingKey {
            case patient
            case encounter
            case needPatientBanner = "need_patient_banner"
        }
    }

    let context: Context?
    let patient: String?
    let encounter: String?
    let exp: Int?
    let iat: Int?

    var patientID: String? {
        context?.patient ?? patient
    }

    var encounterID: String? {
        context?.encounter ?? encounter
    }

    var needPatientBanner: Bool? {
        context?.needPatientBanner
    }

    var issuedAtDate: Date? {
        guard let iat else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(iat))
    }

    var expiresIn: Int? {
        if let exp, let iat {
            return max(exp - iat, 0)
        }

        if let exp {
            return max(exp - Int(Date().timeIntervalSince1970), 0)
        }

        return nil
    }

    static func decode(from accessToken: String) -> SMARTManualAccessTokenContext? {
        let parts = accessToken.split(separator: ".")
        guard parts.count >= 2,
              let payloadData = Data(base64URLEncoded: String(parts[1])) else {
            return nil
        }

        return try? JSONDecoder().decode(SMARTManualAccessTokenContext.self, from: payloadData)
    }
}

private extension Data {
    init?(base64URLEncoded string: String) {
        var normalized = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = normalized.count % 4
        if padding > 0 {
            normalized += String(repeating: "=", count: 4 - padding)
        }

        self.init(base64Encoded: normalized)
    }
}
