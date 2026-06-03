import SwiftUI
import SwiftData

struct InteroperabilityWorkspaceView: View {
    @EnvironmentObject private var smartController: SMARTConnectionController
    @Environment(\.modelContext) private var modelContext
    @State private var showsBrowserLaunchOptions = false
    @State private var showsConnectionDetails = false
    @State private var showsDiscoveryDetails = false
    @State private var showsManualFallback = false

    private let discoveryColumns = [GridItem(.adaptive(minimum: 96), spacing: 8)]

    private var canBeginInAppAuthorization: Bool {
        smartController.canBeginInteractiveAuthorization
    }

    private var hasManualToken: Bool {
        !smartController.manualAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasBaseURL: Bool {
        smartController.fhirBaseURL != nil
    }

    private var resolvedPatientID: String? {
        let typedPatientID = smartController.patientIDText.trimmingCharacters(in: .whitespacesAndNewlines)
        return smartController.session.launchContext.patientID
            ?? smartController.session.tokenResponse?.patient
            ?? (typedPatientID.isEmpty ? nil : typedPatientID)
    }

    private var hasResolvedPatientID: Bool {
        resolvedPatientID != nil
    }

    private var hasAppliedToken: Bool {
        smartController.session.tokenResponse != nil
    }

    private var canImportLaunchPatient: Bool {
        hasAppliedToken && hasResolvedPatientID && !smartController.isImporting
    }

    private var canImportEnteredPatient: Bool {
        hasAppliedToken && !smartController.patientIDText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !smartController.isImporting
    }

    private var readinessTitle: String {
        if smartController.isImporting {
            return "Importing Live FHIR Data"
        }
        if smartController.lastImportSummary != nil {
            return "Live SMART Data Imported"
        }
        if smartController.session.isAuthorized && hasResolvedPatientID {
            return "Ready for Live Patient Import"
        }
        if smartController.session.isAuthorized {
            return "Token Ready, Patient Needed"
        }
        if hasManualToken {
            return "Manual Token Ready to Apply"
        }
        return "Connect a SMART Sandbox"
    }

    private var readinessMessage: String {
        if smartController.isImporting {
            return "Fetching live FHIR resources and syncing them into the local chart workspace."
        }
        if let summary = smartController.lastImportSummary {
            return "Imported \(summary.patientName) from a live SMART/FHIR source on \(summary.importedAt.formatted(date: .abbreviated, time: .shortened))."
        }
        if smartController.session.isAuthorized && hasResolvedPatientID {
            return "The server is authorized and patient context is available. Import the live patient directly into OpenClinic now."
        }
        if smartController.session.isAuthorized {
            return "Authorization is ready. Enter or resolve a patient ID before importing live FHIR data."
        }
        if hasManualToken {
            return "Manual fallback is ready. Apply the bearer token if you need to bypass the SMART sign-in flow for a controlled demo."
        }
        return "Use OpenClinic's in-app SMART sign-in to fetch a real sandbox token, then import the launch patient directly into the chart workspace."
    }

    private var readinessColor: Color {
        if smartController.lastErrorMessage != nil {
            return .red
        }
        if smartController.isImporting || smartController.session.isAuthorized || smartController.lastImportSummary != nil {
            return .green
        }
        if hasManualToken {
            return .blue
        }
        return .orange
    }

    private var readinessIcon: String {
        if smartController.lastErrorMessage != nil {
            return "exclamationmark.triangle.fill"
        }
        if smartController.lastImportSummary != nil {
            return "checkmark.seal.fill"
        }
        if smartController.isImporting {
            return "arrow.triangle.2.circlepath"
        }
        if smartController.session.isAuthorized {
            return "waveform.path.ecg.rectangle"
        }
        if hasManualToken {
            return "key.horizontal.fill"
        }
        return "network"
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Live SMART-on-FHIR Import", systemImage: "waveform.path.ecg.rectangle")
                        .font(.headline)

                    Text("Bring real clinical data into OpenClinic from a SMART sandbox or compatible FHIR server. In-app SMART sign-in is now the default path; manual bearer token import remains available as a fallback.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .clinicalFinePrint()

                    readinessCard
                }
                .padding(.vertical, 4)
            }

            Section("Live SMART Import") {
                Button {
                    Task { await smartController.connectSMARTSandboxEndToEnd() }
                } label: {
                    HStack(spacing: 8) {
                        if smartController.isAuthorizing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                        }
                        Text(smartController.isAuthorizing ? "Signing In with SMART…" : "Sign In to SMART Sandbox")
                    }
                }
                .disabled(!canBeginInAppAuthorization)

                Text("This is the end-to-end path: OpenClinic uses the sandbox preset, a built-in public client ID, and an in-app OAuth sheet to get a real SMART token.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .clinicalFinePrint()

                if let resolvedPatientID {
                    identifierRow("Current SMART Patient", value: resolvedPatientID, monospaced: true)
                } else {
                    Text("After SMART sign-in, OpenClinic imports the patient currently in launch context. Only use a manual override when you are troubleshooting a sandbox flow.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .clinicalFinePrint()
                }

                Button(smartController.isImporting ? "Importing Current SMART Patient…" : "Import Current SMART Patient") {
                    Task { await smartController.importLaunchPatient(modelContext: modelContext) }
                }
                .disabled(!canImportLaunchPatient)

                DisclosureGroup("Connection Details", isExpanded: $showsConnectionDetails) {
                    Picker("Preset", selection: $smartController.selectedPreset) {
                        ForEach(SMARTSandboxPreset.all) { preset in
                            Text(preset.name).tag(preset)
                        }
                    }
                    #if os(iOS)
                    .pickerStyle(.navigationLink)
                    #endif

                    settingsField("FHIR Base URL") {
                        TextField("https://example.com/fhir", text: $smartController.baseURLText)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                    }

                    Text(smartController.selectedPreset.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .clinicalFinePrint()

                    Button {
                        Task { await smartController.discoverConfiguration() }
                    } label: {
                        HStack(spacing: 8) {
                            if smartController.isDiscovering {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "network")
                            }
                            Text(smartController.isDiscovering ? "Checking SMART Server…" : "Check SMART Server")
                        }
                    }
                    .disabled(smartController.isDiscovering || !hasBaseURL)

                    if smartController.isDiscovering {
                        HStack(alignment: .top, spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Inspecting SMART and FHIR endpoints")
                                    .font(.subheadline.weight(.semibold))
                                Text("Verifying well-known SMART configuration and base FHIR metadata before you import anything.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .clinicalFinePrint()
                            }
                        }
                    } else if let summary = smartController.lastDiscoverySummary {
                        LazyVGrid(columns: discoveryColumns, alignment: .leading, spacing: 8) {
                            supportChip(
                                title: "SMART",
                                value: summary.hasSMARTConfiguration ? "Found" : "Missing",
                                color: summary.hasSMARTConfiguration ? .green : .orange
                            )
                            supportChip(
                                title: "FHIR",
                                value: summary.hasFHIRMetadata ? "Found" : "Missing",
                                color: summary.hasFHIRMetadata ? .blue : .secondary
                            )
                            supportChip(
                                title: "PKCE S256",
                                value: summary.supportsPKCES256 ? "Ready" : "Unknown",
                                color: summary.supportsPKCES256 ? .green : .secondary
                            )
                        }
                        .padding(.vertical, 2)

                        DisclosureGroup("Show Discovery Details", isExpanded: $showsDiscoveryDetails) {
                            identifierRow("SMART Config URL", value: summary.configurationURL.absoluteString)
                            identifierRow("FHIR Metadata URL", value: summary.metadataURL.absoluteString)

                            if let configuration = summary.configuration {
                                identifierRow("Authorize Endpoint", value: configuration.authorizationEndpoint.absoluteString)
                                identifierRow("Token Endpoint", value: configuration.tokenEndpoint.absoluteString)
                                if let registrationEndpoint = configuration.registrationEndpoint {
                                    identifierRow("Registration Endpoint", value: registrationEndpoint.absoluteString)
                                }

                                LabeledContent("Scopes Advertised") {
                                    Text("\(summary.scopeCount)")
                                }
                                LabeledContent("Response Types") {
                                    Text("\(summary.responseTypeCount)")
                                }

                                if !summary.capabilities.isEmpty {
                                    chipGrid(title: "SMART Capabilities", items: summary.capabilities, color: .purple)
                                }

                                if !summary.pkceMethods.isEmpty {
                                    chipGrid(title: "PKCE Methods", items: summary.pkceMethods, color: .green)
                                }
                            }

                            if let metadata = summary.capabilityStatement {
                                if let fhirVersion = metadata.fhirVersion, !fhirVersion.isEmpty {
                                    LabeledContent("FHIR Version") {
                                        Text(fhirVersion)
                                    }
                                }
                                if let software = metadata.softwareLabel, !software.isEmpty {
                                    LabeledContent("Software") {
                                        Text(software)
                                            .multilineTextAlignment(.trailing)
                                            .clinicalFinePrint()
                                    }
                                }
                                if let implementation = metadata.implementationLabel, !implementation.isEmpty {
                                    identifierRow("Implementation", value: implementation)
                                }
                                if let publisher = metadata.publisher, !publisher.isEmpty {
                                    LabeledContent("Publisher") {
                                        Text(publisher)
                                            .multilineTextAlignment(.trailing)
                                            .clinicalFinePrint()
                                    }
                                }
                                if !metadata.securityServiceLabels.isEmpty {
                                    chipGrid(title: "Security Services", items: metadata.securityServiceLabels, color: .blue)
                                }
                            }

                            LabeledContent("Discovered") {
                                Text(summary.discoveredAt.formatted(date: .abbreviated, time: .shortened))
                                    .clinicalFinePrint()
                            }

                            if !summary.warnings.isEmpty {
                                ForEach(summary.warnings, id: \.self) { warning in
                                    messageRow(warning, color: .orange, icon: "exclamationmark.triangle.fill")
                                }
                            }
                        }
                    }
                }

                DisclosureGroup("Manual Token Fallback", isExpanded: $showsManualFallback) {
                    settingsField("Bearer Access Token") {
                        TextField("Paste live SMART sandbox token", text: $smartController.manualAccessToken, axis: .vertical)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .lineLimit(2...4)
                    }

                    Text("Manual fallback: paste a valid SMART sandbox bearer token only if you want to bypass sign-in for a controlled rehearsal or recovery path.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .clinicalFinePrint()

                    Button("Apply Manual Token") {
                        smartController.applyManualAccessToken()
                    }
                    .disabled(!hasManualToken)

                    Text("OpenClinic now remembers the last successful SMART token locally on this device for repeat demos. You still need a real OAuth-issued token at least once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .clinicalFinePrint()

                    settingsField("FHIR Patient ID Override") {
                        TextField("Optional patient override", text: $smartController.patientIDText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    Button("Import Patient ID Override") {
                        Task { await smartController.importTypedPatient(modelContext: modelContext) }
                    }
                    .disabled(!canImportEnteredPatient)
                }
            }

            Section {
                DisclosureGroup("Show Advanced SMART Setup", isExpanded: $showsBrowserLaunchOptions) {
                    Text("Use this section for custom SMART servers, launch-context testing, or client overrides. The SMART R4 sandbox can sign in without any manual client registration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .clinicalFinePrint()

                    settingsField("SMART Client ID") {
                        TextField("Enter SMART client ID", text: $smartController.clientID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    settingsField("Client Secret") {
                        SecureField("Optional", text: $smartController.clientSecret)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    settingsField("SMART Launch Context Token") {
                        TextField("Only for EHR-style launch flows", text: $smartController.launchToken)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    Text("Only use the SMART launch token when testing a full EHR-style SMART launch. It is not the bearer token used for FHIR API calls.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .clinicalFinePrint()

                    identifierRow("Redirect URI", value: smartController.redirectURI.absoluteString, monospaced: true)

                    if smartController.selectedPreset == .smartR4 {
                        Text("Sandbox note: if you leave Client ID empty, OpenClinic automatically uses its built-in public sandbox client ID.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .clinicalFinePrint()
                    }

                    Button("Sign In with SMART") {
                        Task { await smartController.authorizeInApp() }
                    }
                    .disabled(!canBeginInAppAuthorization)
                }
            }

            Section("Session State") {
                LabeledContent("Authorized") {
                    Text(smartController.session.isAuthorized ? "Yes" : "No")
                        .foregroundStyle(smartController.session.isAuthorized ? .green : .secondary)
                }
                if let resolvedPatientID {
                    identifierRow("Active Patient Context", value: resolvedPatientID, monospaced: true)
                }
                if let configuration = smartController.session.configuration {
                    identifierRow("Auth Endpoint", value: configuration.authorizationEndpoint.host() ?? configuration.authorizationEndpoint.absoluteString)
                }
                if let token = smartController.session.tokenResponse {
                    LabeledContent("Token Type") {
                        Text(token.tokenType)
                    }
                    if let patient = token.patient {
                        identifierRow("Launch Patient", value: patient, monospaced: true)
                    }
                    if token.isExpired {
                        messageRow("The saved SMART token is expired. Paste a fresh token or sign in with SMART again to reauthorize.", color: .orange, icon: "clock.badge.exclamationmark")
                    }
                }
                if let statusMessage = smartController.statusMessage {
                    messageRow(statusMessage, color: .secondary, icon: "info.circle")
                }
                if let errorMessage = smartController.lastErrorMessage {
                    messageRow(errorMessage, color: .red, icon: "exclamationmark.triangle.fill")
                }
                
                if smartController.session.isAuthorized {
                    Button("Disconnect SMART Session", role: .destructive) {
                        smartController.disconnect()
                    }
                    .foregroundColor(.red)
                }
            }

            if let summary = smartController.lastImportSummary {
                Section("Last Import") {
                    LabeledContent("Patient") {
                        Text(summary.patientName)
                    }
                    identifierRow("FHIR ID", value: summary.patientID, monospaced: true)
                    LabeledContent("Patient Record") {
                        Text(summary.createdNewPatient ? "Created" : "Updated")
                    }
                    LabeledContent("Conditions") {
                        Text("\(summary.conditionCount)")
                    }
                    LabeledContent("Medications") {
                        Text("\(summary.medicationCount)")
                    }
                    LabeledContent("Appointments") {
                        Text("\(summary.appointmentCount)")
                    }
                    if !summary.warnings.isEmpty {
                        ForEach(summary.warnings, id: \.self) { warning in
                            Text(warning)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .clinicalFinePrint()
                        }
                    }
                }
            }
        }
        .navigationTitle("EHR Connectivity")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var readinessCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: readinessIcon)
                    .foregroundStyle(readinessColor)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 5) {
                    Text(readinessTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(readinessMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .clinicalFinePrint()
                }
            }

            if let errorMessage = smartController.lastErrorMessage {
                messageRow(errorMessage, color: .red, icon: "exclamationmark.triangle.fill")
            } else if let statusMessage = smartController.statusMessage {
                messageRow(statusMessage, color: .secondary, icon: "info.circle")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(readinessColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func settingsField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
                .clinicalFinePrint(weight: .semibold)
            content()
        }
    }

    private func identifierRow(_ title: String, value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
                .clinicalFinePrint(weight: .semibold)
            if monospaced {
                Text(value)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .clinicalFinePrintMonospaced()
            } else {
                Text(value)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .clinicalFinePrint()
            }
        }
    }

    private func messageRow(_ message: String, color: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .padding(.top, 1)
            Text(message)
                .font(.caption)
                .foregroundStyle(color)
                .clinicalFinePrint()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    private func chipGrid(title: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .clinicalFinePrint(weight: .semibold)
            LazyVGrid(columns: discoveryColumns, alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .clinicalPillText(weight: .medium)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(color.opacity(0.12), in: Capsule())
                        .foregroundStyle(color)
                }
            }
        }
    }

    private func supportChip(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .clinicalFinePrint(weight: .semibold)
                .foregroundStyle(.secondary)
            Text(value)
                .clinicalPillText(weight: .bold)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(color.opacity(0.12), in: Capsule())
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}
