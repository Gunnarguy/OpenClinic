import SwiftUI
import SwiftData

/// Chart Notes view — shows all clinical records with full structured note data (Image 3 / Image 9)
struct ChartNotesView: View {
    let patient: PatientProfile
    @State private var searchText = ""
    @State private var filterStatus: String? = nil

    private var records: [LocalClinicalRecord] {
        (patient.clinicalRecords ?? []).sorted { $0.dateRecorded > $1.dateRecorded }
    }

    private var filteredRecords: [LocalClinicalRecord] {
        records.filter { record in
            let matchesSearch = searchText.isEmpty || {
                let query = searchText.lowercased()
                return record.conditionName.lowercased().contains(query)
                    || (record.ccHPI?.lowercased().contains(query) ?? false)
                    || (record.examFindings?.lowercased().contains(query) ?? false)
                    || (record.impressionsAndPlan?.lowercased().contains(query) ?? false)
                    || (record.icd10Code?.lowercased().contains(query) ?? false)
                    || (record.visitType?.lowercased().contains(query) ?? false)
            }()
            let matchesStatus = filterStatus == nil || record.status == filterStatus
            return matchesSearch && matchesStatus
        }
    }

    private var filterToolbarPlacement: ToolbarItemPlacement {
        #if os(iOS)
        return .topBarTrailing
        #else
        return .primaryAction
        #endif
    }

    var body: some View {
        List {
            if records.isEmpty {
                ContentUnavailableView(
                    "No Chart Notes",
                    systemImage: "folder",
                    description: Text("Complete an exam workflow to generate structured chart notes via the on-device AI.")
                )
            } else {
                if !searchText.isEmpty || filterStatus != nil {
                    HStack {
                        Text("\(filteredRecords.count) of \(records.count) notes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .clinicalFinePrint()
                        Spacer()
                        if filterStatus != nil {
                            Button("Clear Filter") { filterStatus = nil }
                                .font(.caption)
                                .clinicalFinePrint()
                        }
                    }
                }
                ForEach(filteredRecords) { record in
                    NavigationLink(destination: VisitRecordDetailView(record: record, patient: patient)) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.conditionName)
                                        .font(.headline)
                                    if let visitType = record.visitType {
                                        Text(visitType)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .clinicalFinePrint()
                                    }
                                    Text(record.dateRecorded, format: .dateTime.month().day().year())
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .clinicalFinePrint()
                                    HStack(spacing: 6) {
                                        DocumentationStatusBadge(status: record.documentationLifecycle)
                                        ClinicalSourceBadge(descriptor: record.sourceDescriptor)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(record.status)
                                        .clinicalPillText(weight: .bold)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(record.status == "Final" ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                        .foregroundColor(record.status == "Final" ? .green : .orange)
                                        .cornerRadius(4)
                                    if record.ccHPI != nil {
                                        Image(systemName: "doc.text.fill")
                                            .font(.caption)
                                            .foregroundColor(.purple)
                                    }
                                    if let icd10 = record.icd10Code, !icd10.isEmpty {
                                        Text(icd10)
                                            .font(.caption2.monospaced())
                                            .clinicalMicroMonospaced()
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.blue.opacity(0.1))
                                            .foregroundColor(.blue)
                                            .cornerRadius(3)
                                    }
                                }
                            }

                            if let ccHPI = record.ccHPI, !ccHPI.isEmpty {
                                Text(ccHPI)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .clinicalFinePrint()
                                    .clinicalRowSummaryText(lines: 2)
                            }

                            if let followUpPlan = record.followUpPlan, !followUpPlan.isEmpty {
                                Text(followUpPlan)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .clinicalFinePrint()
                                    .clinicalRowSummaryText()
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Chart Notes")
        .searchable(text: $searchText, prompt: "Search notes, diagnoses, ICD-10…")
        .toolbar {
            ToolbarItem(placement: filterToolbarPlacement) {
                Menu {
                    Button { filterStatus = nil } label: {
                        Label("All", systemImage: filterStatus == nil ? "checkmark" : "")
                    }
                    Button { filterStatus = "Final" } label: {
                        Label("Final", systemImage: filterStatus == "Final" ? "checkmark" : "")
                    }
                    Button { filterStatus = "Preliminary" } label: {
                        Label("Preliminary", systemImage: filterStatus == "Preliminary" ? "checkmark" : "")
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                }
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        #endif
    }
}
