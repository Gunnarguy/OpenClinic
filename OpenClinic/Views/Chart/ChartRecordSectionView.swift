//
//  ChartRecordSectionView.swift
//  OpenClinic
//
//  The structured part of a chart: problems, allergies, results, encounters,
//  procedures, immunizations, reports and documents. These are the rows a
//  SMART on FHIR import fills. Every row shows where it came from, and an
//  imported row opens the resource exactly as the server sent it.
//

import SwiftUI
import SwiftData

struct ChartRecordSectionView: View {
    let patient: PatientProfile

    private var problems: [ChartProblem] {
        (patient.problems ?? []).sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive }
            return (lhs.sortDate ?? .distantPast) > (rhs.sortDate ?? .distantPast)
        }
    }

    private var allergies: [ChartAllergy] {
        (patient.chartAllergies ?? []).sorted { $0.substance < $1.substance }
    }

    private var results: [ChartObservation] {
        (patient.observations ?? [])
            .filter { $0.category != "vital-signs" }
            .sorted { ($0.effectiveDate ?? .distantPast) > ($1.effectiveDate ?? .distantPast) }
    }

    private var encounters: [ChartEncounter] {
        (patient.encounters ?? []).sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
    }

    private var procedures: [ChartProcedure] {
        (patient.procedures ?? []).sorted { ($0.performedStart ?? .distantPast) > ($1.performedStart ?? .distantPast) }
    }

    private var immunizations: [ChartImmunization] {
        (patient.immunizations ?? []).sorted { ($0.occurrenceDate ?? .distantPast) > ($1.occurrenceDate ?? .distantPast) }
    }

    private var reports: [ChartDiagnosticReport] {
        (patient.diagnosticReports ?? []).sorted { ($0.effectiveDate ?? .distantPast) > ($1.effectiveDate ?? .distantPast) }
    }

    private var documents: [ChartDocument] {
        (patient.documents ?? []).sorted { ($0.documentDate ?? .distantPast) > ($1.documentDate ?? .distantPast) }
    }

    private var isEmpty: Bool {
        problems.isEmpty && allergies.isEmpty && results.isEmpty && encounters.isEmpty
            && procedures.isEmpty && immunizations.isEmpty && reports.isEmpty && documents.isEmpty
    }

    var body: some View {
        VStack(spacing: 16) {
            if isEmpty {
                ContentUnavailableView(
                    "No structured record yet",
                    systemImage: "tray",
                    description: Text("Problems, results, encounters and immunizations appear here after a record is imported from a FHIR server or entered on the chart.")
                )
            }

            RecordCard(title: "Problems", systemImage: "cross.case.fill", tint: .criticalRed, rows: problems) { problem in
                RecordRow(
                    title: problem.display,
                    detail: [problem.clinicalStatus.capitalized, problem.code.map { "Code \($0)" }].compactMap { $0 }.joined(separator: " · "),
                    date: problem.sortDate,
                    trailing: problem.abatementDate.map { "Resolved \($0.formatted(date: .abbreviated, time: .omitted))" },
                    row: problem
                )
            }

            RecordCard(title: "Allergies", systemImage: "exclamationmark.triangle.fill", tint: .clinicalAmber, rows: allergies) { allergy in
                RecordRow(
                    title: allergy.substance,
                    detail: [allergy.clinicalStatus?.capitalized, allergy.criticality.map { "Criticality \($0)" },
                             allergy.reactions.isEmpty ? nil : allergy.reactions.joined(separator: ", ")]
                        .compactMap { $0 }.joined(separator: " · "),
                    date: allergy.recordedDate,
                    trailing: nil,
                    row: allergy
                )
            }

            RecordCard(title: "Results", systemImage: "testtube.2", tint: .clinicalIndigo, rows: results) { observation in
                RecordRow(
                    title: observation.display,
                    detail: [ObservationFormatting.interpretationLabel(observation.interpretation), observation.referenceRange.map { "Reference \($0)" }]
                        .compactMap { $0 }.joined(separator: " · "),
                    date: observation.effectiveDate,
                    trailing: observation.displayValue,
                    row: observation
                )
            }

            RecordCard(title: "Reports", systemImage: "doc.text.magnifyingglass", tint: .clinicalIndigo, rows: reports) { report in
                RecordRow(
                    title: report.display,
                    detail: [report.status.capitalized, report.resultReferences.isEmpty ? nil : "\(report.resultReferences.count) results",
                             report.conclusion]
                        .compactMap { $0 }.joined(separator: " · "),
                    date: report.effectiveDate,
                    trailing: nil,
                    row: report
                )
            }

            RecordCard(title: "Encounters", systemImage: "stethoscope", tint: .clinicalTeal, rows: encounters) { encounter in
                RecordRow(
                    title: encounter.typeDisplay,
                    detail: [encounter.classDisplay, encounter.reason, encounter.practitioner, encounter.serviceProvider]
                        .compactMap { $0 }.joined(separator: " · "),
                    date: encounter.startDate,
                    trailing: nil,
                    row: encounter
                )
            }

            RecordCard(title: "Procedures", systemImage: "scissors", tint: .clinicalTeal, rows: procedures) { procedure in
                RecordRow(
                    title: procedure.display,
                    detail: [procedure.status.capitalized, procedure.reason].compactMap { $0 }.joined(separator: " · "),
                    date: procedure.performedStart,
                    trailing: nil,
                    row: procedure
                )
            }

            RecordCard(title: "Immunizations", systemImage: "syringe.fill", tint: .clinicalTeal, rows: immunizations) { immunization in
                RecordRow(
                    title: immunization.vaccine,
                    detail: immunization.status.capitalized,
                    date: immunization.occurrenceDate,
                    trailing: nil,
                    row: immunization
                )
            }

            RecordCard(title: "Documents", systemImage: "doc.richtext", tint: .clinicalSlate, rows: documents) { document in
                NavigationLink {
                    ChartDocumentDetailView(document: document)
                } label: {
                    RecordRow(
                        title: document.summary ?? document.typeDisplay,
                        detail: [document.typeDisplay, document.author].compactMap { $0 }.joined(separator: " · "),
                        date: document.documentDate,
                        trailing: nil,
                        row: document
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Card

/// A titled list that shows its first rows and expands to all of them.
private struct RecordCard<Row: PersistentModel, Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let rows: [Row]
    @ViewBuilder let content: (Row) -> Content

    @State private var showsAll = false
    private let collapsedCount = 6

    private var visibleRows: [Row] {
        showsAll ? rows : Array(rows.prefix(collapsedCount))
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(title, systemImage: systemImage)
                        .font(.subheadline.bold())
                        .foregroundStyle(tint)
                    Spacer()
                    Text("\(rows.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(rows.count) entries")
                }

                VStack(spacing: 0) {
                    ForEach(Array(visibleRows.enumerated()), id: \.element.persistentModelID) { index, row in
                        if index > 0 { Divider() }
                        content(row)
                            .padding(.vertical, 8)
                    }
                }

                if rows.count > collapsedCount {
                    Button(showsAll ? "Show fewer" : "Show all \(rows.count)") {
                        withAnimation { showsAll.toggle() }
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(
                Color.clear.liquidGlassCard(cornerRadius: 16, shadowRadius: 4)
            )
        }
    }
}

// MARK: - Row

private struct RecordRow<Row: ServerSyncedRow>: View {
    let title: String
    let detail: String
    let date: Date?
    let trailing: String?
    let row: Row

    @State private var showsSource = false

    private var isImported: Bool {
        row.sourceKind == ClinicalSourceKind.smartFHIR.rawValue
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                    .strikethrough(row.isRemovedAtSource)

                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 6) {
                    if let date {
                        Text(date, format: .dateTime.month(.abbreviated).day().year())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ClinicalSourceBadge(descriptor: row.sourceDescriptor)
                    if row.isRemovedAtSource {
                        Text("No longer at source")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.clinicalAmber)
                    }
                }
            }

            Spacer(minLength: 8)

            if let trailing {
                Text(trailing)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .multilineTextAlignment(.trailing)
            }

            if isImported {
                // A 44 point target: the symbol alone is too small to hit.
                Button {
                    showsSource = true
                } label: {
                    Image(systemName: "curlybraces")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("View source resource")
                .accessibilityHint("Shows the FHIR resource this row was read from")
            }
        }
        .sheet(isPresented: $showsSource) {
            SourceResourceView(qualifiedID: row.qualifiedID, title: title)
        }
    }
}

// MARK: - Source resource

/// The FHIR resource behind a chart row, exactly as the server sent it.
struct SourceResourceView: View {
    let qualifiedID: String
    let title: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var record: FHIRResourceRecord?
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Group {
                if let record {
                    List {
                        Section("Resource") {
                            LabeledContent("Type", value: record.resourceType)
                            LabeledContent("ID", value: record.resourceID)
                            if let version = record.versionID {
                                LabeledContent("Version", value: version)
                            }
                            if let updated = record.lastUpdated {
                                LabeledContent("Last updated at source", value: updated.formatted(date: .abbreviated, time: .shortened))
                            }
                            LabeledContent("Fetched", value: record.fetchedAt.formatted(date: .abbreviated, time: .shortened))
                            LabeledContent("Server", value: record.serverBase)
                            if record.isRemovedAtSource {
                                Label("The server no longer returns this resource.", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(Color.clinicalAmber)
                            }
                        }
                        Section("JSON as received") {
                            Text(record.prettyPrintedJSON)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                } else if didLoad {
                    ContentUnavailableView(
                        "Source not stored",
                        systemImage: "curlybraces",
                        description: Text("This row was imported before source resources were kept. Import the record again to store them.")
                    )
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            let id = qualifiedID
            let descriptor = FetchDescriptor<FHIRResourceRecord>(predicate: #Predicate { $0.qualifiedID == id })
            record = try? modelContext.fetch(descriptor).first
            didLoad = true
            if let record {
                modelContext.insert(AuditEvent(
                    action: .sourceResourceViewed,
                    entityType: record.resourceType,
                    entityID: record.qualifiedID
                ))
            }
        }
    }
}

// MARK: - Document

struct ChartDocumentDetailView: View {
    let document: ChartDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ClinicalSourceSummaryRow(descriptor: document.sourceDescriptor)

                if let date = document.documentDate {
                    Text(date, format: .dateTime.month(.wide).day().year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let author = document.author {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let text = document.text, !text.isEmpty {
                    Text(text)
                        .font(.body)
                        .textSelection(.enabled)
                } else {
                    Text("This document's content could not be read as text\(document.contentType.map { " (\($0))" } ?? "").")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(document.summary ?? document.typeDisplay)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
