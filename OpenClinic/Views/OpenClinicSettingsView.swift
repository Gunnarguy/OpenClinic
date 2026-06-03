import SwiftUI
import SwiftData

struct OpenClinicSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var smartController: SMARTConnectionController
    @ObservedObject private var ragService = ClinicalRAGService.shared
    @StateObject private var intelligenceService = ClinicalIntelligenceService()
    @Query private var patients: [PatientProfile]

    private var recordCount: Int {
        patients.reduce(0) { $0 + ($1.clinicalRecords?.count ?? 0) }
    }

    private var medicationCount: Int {
        patients.reduce(0) { $0 + ($1.medications?.count ?? 0) }
    }

    private var smartPatientCount: Int {
        patients.filter { $0.sourceKind == ClinicalSourceKind.smartFHIR.rawValue }.count
    }

    private var demoPatientCount: Int {
        patients.filter { $0.sourceKind == ClinicalSourceKind.demoLocalCache.rawValue }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workspace") {
                    LabeledContent("Patients") {
                        Text("\(patients.count)")
                    }
                    LabeledContent("Records") {
                        Text("\(recordCount)")
                    }
                    LabeledContent("Medications") {
                        Text("\(medicationCount)")
                    }
                    LabeledContent("Text Layout") {
                        Text("Compact rows, wrapped narratives")
                            .multilineTextAlignment(.trailing)
                            .clinicalFinePrint()
                    }
                }

                Section("Intelligence") {
                    Text(intelligenceService.engineStatusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .clinicalFinePrint()
                    LabeledContent("Indexed Chunks") {
                        Text("\(ragService.indexedChunkCount)")
                    }
                    Button(ragService.isIndexing ? "Reindexing…" : "Reindex Clinical Data") {
                        Task { await ragService.indexAllData(modelContext: modelContext) }
                    }
                    .disabled(ragService.isIndexing)
                }

                Section("Connectivity") {
                    NavigationLink(destination: InteroperabilityWorkspaceView()) {
                        Label("Live SMART / EHR Import", systemImage: "network")
                    }

                    LabeledContent("Imported SMART Patients") {
                        Text("\(smartPatientCount)")
                    }

                    LabeledContent("Local Demo Patients") {
                        Text("\(demoPatientCount)")
                    }

                    if let token = smartController.session.tokenResponse {
                        LabeledContent("SMART Token") {
                            Text(token.tokenType)
                        }
                        if let patientID = token.patient, !patientID.isEmpty {
                            LabeledContent("Launch Patient") {
                                Text(patientID)
                                    .font(.caption.monospaced())
                                    .clinicalFinePrintMonospaced()
                            }
                        }
                        if let lastAuthorizedAt = smartController.session.lastAuthorizedAt {
                            LabeledContent("Last Connected") {
                                Text(lastAuthorizedAt.formatted(date: .abbreviated, time: .shortened))
                                    .clinicalFinePrint()
                            }
                        }
                    } else if smartPatientCount > 0 {
                        Text("No active SMART session. Imported SMART data remains available in the workspace alongside any local demo records.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .clinicalFinePrint()
                    } else {
                        Text("No live SMART session yet. Use Live SMART / EHR Import to pull data from a SMART sandbox or compatible FHIR server. Local demo data can still power the rest of the workflow.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .clinicalFinePrint()
                    }
                    
                    if smartController.session.isAuthorized {
                        Button("Disconnect SMART Session", role: .destructive) {
                            smartController.disconnect()
                        }
                        .foregroundColor(.red)
                    }
                }

                Section("About") {
                    LabeledContent("App") {
                        Text("OpenClinic")
                    }
                    LabeledContent("Mode") {
                        Text("Demo + provider workflow prototype")
                            .multilineTextAlignment(.trailing)
                            .clinicalFinePrint()
                    }
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}
