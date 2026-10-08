//
//  SandboxImportView.swift
//  OpenClinic
//
//  Finds a synthetic patient on an open FHIR R4 sandbox and imports the whole
//  record: problems, medications, allergies, observations, encounters,
//  procedures, immunizations, reports, documents and appointments.
//
//  No sign-in is involved, so this is the shortest path from a clean install
//  to a chart filled from a real FHIR server. Servers that need authorization
//  use the SMART on FHIR flow on the screen above this one.
//

import SwiftUI
import SwiftData

struct SandboxImportView: View {
    /// The open SMART Health IT R4 sandbox. It serves synthetic Synthea patients and takes no token.
    static let openSandboxURL = URL(string: "https://r4.smarthealthit.org")

    @Environment(\.modelContext) private var modelContext
    @Query private var localPatients: [PatientProfile]

    @State private var coordinator = ChartImportCoordinator()
    @State private var searchText = ""
    @State private var results: [RemotePatientSummary] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var hasSearched = false
    @State private var importingPatientID: String?

    private var serverURL: URL? { Self.openSandboxURL }

    private var importedPatient: PatientProfile? {
        guard let summary = coordinator.lastSummary else { return nil }
        return localPatients.first { $0.id == summary.patientLocalID }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("SMART Health IT open sandbox", systemImage: "server.rack")
                        .font(.subheadline.weight(.semibold))
                    Text("Synthetic patients only. Requests go from this device straight to r4.smarthealthit.org, and what comes back is stored on this device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }

            // Progress and the result sit above the patient list, so they are on screen when a row is tapped.
            if coordinator.isImporting {
                Section("Importing") {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text(coordinator.statusText)
                            .font(.subheadline)
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if case .failed(let message) = coordinator.phase {
                Section("Import failed") {
                    Label(message, systemImage: "xmark.octagon")
                        .foregroundStyle(Color.criticalRed)
                    Text("Nothing was changed. The chart is saved only when every step succeeds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let summary = coordinator.lastSummary, !coordinator.isImporting {
                ChartImportSummarySection(summary: summary)

                if let importedPatient {
                    Section {
                        NavigationLink {
                            PatientChartPageView(patient: importedPatient)
                        } label: {
                            Label("Open \(importedPatient.fullName)'s chart", systemImage: "person.text.rectangle")
                        }
                    }
                }
            }

            Section("Find a patient") {
                HStack {
                    TextField("Family or given name", text: $searchText)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .onSubmit { Task { await search() } }
                    if isSearching {
                        ProgressView()
                    } else {
                        Button("Search") { Task { await search() } }
                            .disabled(coordinator.isImporting)
                    }
                }

                if let searchError {
                    Label(searchError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Color.criticalRed)
                }

                if hasSearched && results.isEmpty && searchError == nil && !isSearching {
                    Text("No patients found.")
                        .foregroundStyle(.secondary)
                }

                ForEach(results) { patient in
                    Button {
                        Task { await importPatient(patient) }
                    } label: {
                        RemotePatientRow(patient: patient, isImporting: importingPatientID == patient.id)
                    }
                    .buttonStyle(.plain)
                    .disabled(coordinator.isImporting)
                }
            }
        }
        .navigationTitle("Import a Sandbox Patient")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            if !hasSearched { await search() }
        }
    }

    // MARK: - Actions

    private func search() async {
        guard let serverURL, !isSearching else { return }
        isSearching = true
        searchError = nil
        defer {
            isSearching = false
            hasSearched = true
        }
        do {
            results = try await coordinator.findPatients(named: searchText, baseURL: serverURL)
        } catch {
            results = []
            searchError = error.localizedDescription
        }
    }

    private func importPatient(_ patient: RemotePatientSummary) async {
        guard let serverURL else { return }
        importingPatientID = patient.id
        defer { importingPatientID = nil }
        await coordinator.importChart(patientID: patient.id, baseURL: serverURL, context: modelContext)
    }
}

// MARK: - Rows

private struct RemotePatientRow: View {
    let patient: RemotePatientSummary
    let isImporting: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(patient.name.isEmpty ? "Unnamed patient" : patient.name)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    Text(patient.sex)
                    if let birthDate = patient.birthDate {
                        Text("Born \(birthDate.formatted(date: .abbreviated, time: .omitted))")
                    }
                    if patient.isDeceased {
                        Text("Deceased")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if isImporting {
                ProgressView()
            } else {
                Image(systemName: "square.and.arrow.down")
                    .foregroundStyle(Color.clinicalIndigo)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Imports this patient's full record")
    }
}

/// What an import changed, by kind of record, with anything that was left out.
struct ChartImportSummarySection: View {
    let summary: ChartImportSummary

    var body: some View {
        Section("Last import") {
            LabeledContent("Patient", value: summary.patientName)
            LabeledContent("Chart", value: summary.createdNewPatient ? "Created" : "Updated")
            LabeledContent("Server", value: summary.serverBase)
            LabeledContent("Source resources stored", value: "\(summary.sourceResourceCount)")
            LabeledContent("Imported", value: summary.importedAt.formatted(date: .abbreviated, time: .shortened))
        }

        Section("By kind of record") {
            ForEach(summary.lines) { line in
                HStack {
                    Text(line.label)
                    Spacer()
                    Text(detail(for: line))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(line.received == 0 ? .secondary : .primary)
                }
                .accessibilityElement(children: .combine)
            }
        }

        if !summary.warnings.isEmpty {
            Section("Left out or incomplete") {
                ForEach(summary.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Color.clinicalAmber)
                }
            }
        }
    }

    private func detail(for line: ChartImportSummary.Line) -> String {
        guard line.received > 0 || line.removedAtSource > 0 else { return "none" }
        var parts = ["\(line.received) read"]
        if line.created > 0 { parts.append("\(line.created) new") }
        if line.updated > 0 { parts.append("\(line.updated) updated") }
        if line.removedAtSource > 0 { parts.append("\(line.removedAtSource) no longer at source") }
        return parts.joined(separator: ", ")
    }
}
