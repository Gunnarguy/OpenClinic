import SwiftUI
import SwiftData
import Combine
import os
#if canImport(Speech)
import Speech
import AVFoundation
#endif

// MARK: - Voice Dictation Service

#if os(iOS)
@MainActor
final class SpeechDictationService: ObservableObject {
    @Published var transcript = ""
    @Published var isListening = false
    @Published var permissionGranted = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func requestPermission() {
        AppLogger.speech.info("🎙️ Requesting speech recognition permission")
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                let granted = status == .authorized
                self?.permissionGranted = granted
                AppLogger.speech.info("🎙️ Speech permission result: \(granted ? "granted" : "denied") (raw: \(status.rawValue))")
            }
        }
    }

    func toggleListening() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    func startListening() {
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            AppLogger.speech.warning("⚠️ Speech recognizer unavailable")
            return
        }

        AppLogger.speech.info("🎤 Starting speech recognition")
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            AppLogger.speech.info("🔊 Audio session activated")
        } catch {
            AppLogger.speech.error("❌ Audio session setup failed: \(error.localizedDescription)")
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.addsPunctuation = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor in
                if let result {
                    self?.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    self?.stopListening()
                }
            }
        }

        do {
            try audioEngine.start()
            isListening = true
            AppLogger.speech.info("✅ Audio engine started — listening")
        } catch {
            AppLogger.speech.error("❌ Audio engine failed to start: \(error.localizedDescription)")
            stopListening()
        }
    }

    func stopListening() {
        AppLogger.speech.info("⏹️ Stopping speech recognition (transcript: \(self.transcript.count) chars)")
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
    }
}
#endif

// MARK: - Clinical Exam View (Voice Dictation Encounter)

struct ClinicalExamView: View {
    let patient: PatientProfile
    @StateObject private var workflowState = ClinicalWorkflowState()

    var body: some View {
        ClinicalExamWorkspace(patient: patient, workflowState: workflowState)
            .navigationTitle("Clinical Encounter")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }
}

struct ClinicalExamWorkspace: View {
    let patient: PatientProfile
    @ObservedObject var workflowState: ClinicalWorkflowState

    @Environment(\.modelContext) private var modelContext
    @StateObject private var intelligenceService = ClinicalIntelligenceService()
    @State private var dictationText = ""
    @State private var selectedRegion: String?

    #if os(iOS)
    @StateObject private var speechService = SpeechDictationService()
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }
    #else
    private var isCompact: Bool { false }
    #endif

    private var savedRecord: LocalClinicalRecord? {
        guard let savedRecordID = workflowState.savedRecordID else { return nil }
        return patient.clinicalRecords?.first(where: { $0.recordID == savedRecordID })
    }

    var body: some View {
        Group {
            if isCompact {
                compactLayout
            } else {
                regularLayout
            }
        }
        #if os(iOS)
        .onAppear { speechService.requestPermission() }
        .onChange(of: speechService.transcript) { _, newValue in
            dictationText = newValue
        }
        #endif
    }

    // MARK: - iPad / Wide Layout
    private var regularLayout: some View {
        HStack(spacing: 0) {
            ScrollView { dictationPanel }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ScrollView { intelligencePanel }
                .frame(width: 380)
                .background(Color.clinicSecondarySystemBackground)
        }
    }

    // MARK: - iPhone / Compact Layout
    private var compactLayout: some View {
        ScrollView {
            VStack(spacing: 16) {
                dictationPanel
                Divider()
                intelligencePanel
            }
        }
    }

    // MARK: - Dictation Panel
    private var dictationPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Patient header
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundColor(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(patient.fullName).font(.headline)
                    HStack(spacing: 8) {
                        Text("Age \(patient.age)")
                        Text(patient.gender)
                        if patient.isSmoker {
                            Label("Smoker", systemImage: "smoke").foregroundColor(.orange)
                        }
                    }
                    .font(.caption).foregroundColor(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .cornerRadius(12)

            // Anatomical focus — interactive body map
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Anatomical Focus").font(.headline)
                    Spacer()
                    if selectedRegion != nil {
                        Button {
                            selectedRegion = nil
                            workflowState.selectedAnatomy = nil
                        } label: {
                            Label("Clear", systemImage: "xmark.circle.fill")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                Text("Tap the body region being examined")
                    .font(.caption).foregroundColor(.secondary)

                if let region = selectedRegion {
                    HStack(spacing: 8) {
                        Image(systemName: "scope").foregroundColor(.purple)
                        Text(AnatomicalRegion.displayName(for: region))
                            .font(.subheadline.bold()).foregroundColor(.purple)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.purple.opacity(0.1))
                    .cornerRadius(8)
                }

                examBodyMap
                    .frame(maxWidth: .infinity)

                // Fallback dropdown for regions not on the map
                Menu {
                    Button("None") {
                        selectedRegion = nil
                        workflowState.selectedAnatomy = nil
                    }
                    ForEach(AnatomicalRegion.sortedRegions, id: \.key) { region in
                        Button(region.label) {
                            selectedRegion = region.key
                            workflowState.selectedAnatomy = region.key
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "list.bullet")
                            .foregroundColor(.purple)
                        Text("Or pick from full list…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.clinicTertiarySystemBackground)
                    .cornerRadius(8)
                }
            }

            // Voice dictation
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Clinical Dictation").font(.headline)
                    Spacer()
                    #if os(iOS)
                    Button {
                        speechService.toggleListening()
                    } label: {
                        Image(systemName: speechService.isListening ? "stop.circle.fill" : "mic.circle.fill")
                            .font(.title2)
                            .foregroundColor(speechService.isListening ? .red : .purple)
                            .symbolEffect(.pulse, isActive: speechService.isListening)
                    }
                    .disabled(!speechService.permissionGranted)
                    #endif
                }
                Text("Describe your clinical findings — tap the mic to dictate")
                    .font(.caption).foregroundColor(.secondary)

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $dictationText)
                        .frame(minHeight: 140, maxHeight: 220)
                        .padding(4)
                        .background(Color.clinicTertiarySystemBackground)
                        .cornerRadius(10)

                    if dictationText.isEmpty {
                        Text("e.g. \"2mm papule on the right cheek, slightly erythematous border, no ulceration…\"")
                            .foregroundColor(.secondary.opacity(0.5))
                            .font(.callout).padding(8)
                            .allowsHitTesting(false)
                    }
                }

                #if os(iOS)
                if speechService.isListening {
                    HStack(spacing: 8) {
                        HStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { _ in
                                Capsule().fill(Color.red)
                                    .frame(width: 3, height: CGFloat.random(in: 6...16))
                            }
                        }.frame(height: 16)
                        Text("Listening…").font(.caption).foregroundColor(.red)
                    }
                    .padding(.top, 4)
                }
                #endif
            }

            // Process button
            Button(action: runAIWorkflow) {
                HStack {
                    if workflowState.isProcessing {
                        ProgressView().padding(.trailing, 4)
                    } else {
                        Image(systemName: "waveform.circle.fill")
                    }
                    Text(workflowState.isProcessing ? "Generating Note…" : "Process Diagnostics")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundColor(.white)
                .background(canProcess ? Color.purple : Color.gray)
                .cornerRadius(12)
            }
            .disabled(!canProcess)
        }
        .padding()
    }

    private var canProcess: Bool {
        !workflowState.isProcessing && (!dictationText.isEmpty || selectedRegion != nil)
    }

    // MARK: - Exam Body Map (inline picker)

    private func examRegionButton(_ region: String, label: String, width: CGFloat, height: CGFloat) -> some View {
        let isSelected = selectedRegion == region
        return Button {
            selectedRegion = region
            workflowState.selectedAnatomy = region
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.purple.opacity(0.35) : Color.gray.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(isSelected ? Color.purple : Color.clear, lineWidth: 2)
                    )
                Text(label)
                    .font(.system(size: 7, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? .purple : .secondary)
            }
            .frame(width: width, height: height)
        }
        .buttonStyle(.plain)
    }

    private var examBodyMap: some View {
        VStack(spacing: 0) {
            // Head
            HStack(spacing: 4) {
                examRegionButton("scalp", label: "Scalp", width: 50, height: 22)
            }
            HStack(spacing: 2) {
                examRegionButton("left_ear", label: "L Ear", width: 18, height: 26)
                VStack(spacing: 1) {
                    examRegionButton("forehead", label: "Forehead", width: 50, height: 18)
                    HStack(spacing: 1) {
                        examRegionButton("left_cheek", label: "L", width: 16, height: 18)
                        examRegionButton("facial_mesh_nose", label: "Nose", width: 16, height: 18)
                        examRegionButton("right_cheek", label: "R", width: 16, height: 18)
                    }
                    HStack(spacing: 1) {
                        examRegionButton("lips", label: "Lips", width: 24, height: 12)
                        examRegionButton("chin", label: "Chin", width: 24, height: 12)
                    }
                }
                examRegionButton("right_ear", label: "R Ear", width: 18, height: 26)
            }

            // Neck
            examRegionButton("neck", label: "Neck", width: 36, height: 16)

            // Torso + Arms
            HStack(alignment: .top, spacing: 2) {
                VStack(spacing: 2) {
                    examRegionButton("left_shoulder", label: "L Shldr", width: 32, height: 20)
                    examRegionButton("left_upper_extremity", label: "L Arm", width: 26, height: 60)
                    examRegionButton("left_hand", label: "L Hand", width: 22, height: 24)
                }
                VStack(spacing: 2) {
                    examRegionButton("torso", label: "Chest", width: 70, height: 42)
                    examRegionButton("upper_abdomen", label: "Abdomen", width: 70, height: 34)
                    examRegionButton("lower_back", label: "Lower Back", width: 70, height: 26)
                }
                VStack(spacing: 2) {
                    examRegionButton("right_shoulder", label: "R Shldr", width: 32, height: 20)
                    examRegionButton("right_upper_extremity", label: "R Arm", width: 26, height: 60)
                    examRegionButton("right_hand", label: "R Hand", width: 22, height: 24)
                }
            }

            // Legs
            HStack(spacing: 6) {
                VStack(spacing: 2) {
                    examRegionButton("left_lower_extremity", label: "L Leg", width: 32, height: 66)
                    examRegionButton("left_foot", label: "L Foot", width: 28, height: 18)
                }
                VStack(spacing: 2) {
                    examRegionButton("right_lower_extremity", label: "R Leg", width: 32, height: 66)
                    examRegionButton("right_foot", label: "R Foot", width: 28, height: 18)
                }
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Intelligence Panel
    private var intelligencePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(intelligenceService.engineStatusLabel, systemImage: "cpu")
                .font(.caption).foregroundColor(.secondary)

            if let part = workflowState.selectedAnatomy {
                HStack(spacing: 6) {
                    Image(systemName: "scope").foregroundColor(.red)
                    Text(AnatomicalRegion.displayName(for: part)).fontWeight(.medium)
                }
                .font(.subheadline).padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.purple.opacity(0.1)).cornerRadius(8)
            }

            if let note = workflowState.generatedNote {
                VStack(alignment: .leading, spacing: 10) {
                    Text("AI Structured Note").font(.headline).foregroundColor(.purple)

                    clinicalDataRow(title: "Primary Diagnosis", value: note.primaryDiagnosis)
                    clinicalDataRow(title: "CC / HPI", value: note.ccHPI)
                    clinicalDataRow(title: "Review of Systems", value: note.reviewOfSystems)
                    clinicalDataRow(title: "Exam Findings", value: note.examFindings)
                    clinicalDataRow(title: "Impression & Plan", value: note.impressionsAndPlan)
                    clinicalDataRow(title: "Patient Instructions", value: note.patientInstructions)
                    clinicalDataRow(title: "Follow-Up", value: note.followUpPlan)

                    if !note.recommendedOrders.isEmpty {
                        clinicalDataRow(title: "Recommended Orders", value: note.recommendedOrders.map { "• \($0)" }.joined(separator: "\n"))
                    }
                    if !note.medicationChanges.isEmpty {
                        clinicalDataRow(title: "Medication Changes", value: note.medicationChanges.map { "• \($0)" }.joined(separator: "\n"))
                    }
                    if !note.affectedAnatomicalZones.isEmpty {
                        clinicalDataRow(title: "Anatomical Zones", value: note.affectedAnatomicalZones.map { AnatomicalRegion.displayName(for: $0) }.joined(separator: ", "))
                    }
                }

                Divider()

                VStack(spacing: 10) {
                    Button(action: { persistGeneratedNote(note: note, lifecycle: .draft, generatePDF: false) }) {
                        Label("Save Draft", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundColor(.white)
                            .background(Color.orange)
                            .cornerRadius(12)
                    }

                    Button(action: { persistGeneratedNote(note: note, lifecycle: .reviewed, generatePDF: false) }) {
                        Label("Mark Reviewed", systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundColor(.white)
                            .background(Color.indigo)
                            .cornerRadius(12)
                    }

                    Button(action: { persistGeneratedNote(note: note, lifecycle: .signed, generatePDF: true) }) {
                        Label("Sign & Generate PDF", systemImage: "signature")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundColor(.white)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }

                if let lastSavedDocumentationStatus = workflowState.lastSavedDocumentationStatus {
                    HStack(spacing: 6) {
                        Image(systemName: lastSavedDocumentationStatus == .signed ? "checkmark.seal.fill" : "doc.badge.clock")
                            .foregroundColor(lastSavedDocumentationStatus == .signed ? .green : .orange)
                        Text("Record saved as \(lastSavedDocumentationStatus.label)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                if let savedRecord {
                    NavigationLink(destination: VisitRecordDetailView(record: savedRecord, patient: patient)) {
                        Label("Open Saved Record", systemImage: "doc.text.magnifyingglass")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                }

                if let url = workflowState.generatedPDFURL {
                    ShareLink(item: url) {
                        Label("Share Visit Note PDF", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .foregroundColor(.white).background(Color.green).cornerRadius(12)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                        Text("Signed — \(url.lastPathComponent)")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            } else if !workflowState.isProcessing {
                ContentUnavailableView {
                    Label("Ready to Document", systemImage: "doc.text")
                } description: {
                    Text("Dictate your clinical findings and tap Process Diagnostics to generate a structured note.")
                }
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func runAIWorkflow() {
        #if os(iOS)
        if speechService.isListening { speechService.stopListening() }
        #endif

        workflowState.isProcessing = true
        var prompt = dictationText
        if let part = workflowState.selectedAnatomy {
            prompt = "[Anatomical Focus: \(part)] " + prompt
        }
        AppLogger.exam.info("🧪 AI workflow started — prompt length: \(prompt.count) chars, anatomy: \(workflowState.selectedAnatomy ?? "none")")

        Task {
            do {
                let note = try await intelligenceService.generateStructuredNote(
                    from: prompt, patient: patient, selectedAnatomy: workflowState.selectedAnatomy)
                workflowState.generatedNote = note
                AppLogger.exam.info("✅ Structured note generated: \(note.primaryDiagnosis)")
            } catch {
                AppLogger.exam.error("❌ AI workflow failed: \(error.localizedDescription)")
            }
            workflowState.isProcessing = false
        }
    }

    private func persistGeneratedNote(note: ClinicalVisitNote, lifecycle: DocumentationLifecycleStatus, generatePDF: Bool) {
        let record: LocalClinicalRecord
        let createdNewRecord: Bool

        if let existing = savedRecord {
            record = existing
            createdNewRecord = false
        } else {
            let recordID = UUID().uuidString
            record = LocalClinicalRecord(
                recordID: recordID,
                dateRecorded: Date(),
                conditionName: note.primaryDiagnosis,
                status: "Preliminary",
                isHiddenFromPortal: false,
                visitType: "AI-assisted encounter",
                ccHPI: note.ccHPI,
                reviewOfSystems: note.reviewOfSystems,
                examFindings: note.examFindings,
                impressionsAndPlan: note.impressionsAndPlan,
                affectedAnatomicalZones: note.affectedAnatomicalZones,
                patientInstructions: note.patientInstructions,
                followUpPlan: note.followUpPlan,
                recommendedOrders: note.recommendedOrders,
                carePlanSummary: note.impressionsAndPlan,
                documentationStatus: lifecycle.rawValue,
                documentationSignedAt: lifecycle == .signed ? .now : nil,
                sourceKind: ClinicalSourceKind.localAI.rawValue,
                sourceSystemName: "OpenClinic Encounter Workspace",
                sourceRecordIdentifier: recordID,
                sourceLastSyncedAt: .now,
                sourceOfTruth: false
            )
            modelContext.insert(record)
            if patient.clinicalRecords == nil {
                patient.clinicalRecords = []
            }
            patient.clinicalRecords?.append(record)
            workflowState.savedRecordID = recordID
            createdNewRecord = true
        }

        record.conditionName = note.primaryDiagnosis
        record.status = lifecycle == .signed ? "Final" : "Preliminary"
        record.visitType = "AI-assisted encounter"
        record.ccHPI = note.ccHPI
        record.reviewOfSystems = note.reviewOfSystems
        record.examFindings = note.examFindings
        record.impressionsAndPlan = note.impressionsAndPlan
        record.affectedAnatomicalZones = note.affectedAnatomicalZones
        record.patientInstructions = note.patientInstructions
        record.followUpPlan = note.followUpPlan
        record.recommendedOrders = note.recommendedOrders
        record.carePlanSummary = note.impressionsAndPlan
        record.documentationStatus = lifecycle.rawValue
        record.documentationSignedAt = lifecycle == .signed ? .now : nil
        record.providerSignature = lifecycle == .signed ? (patient.primaryClinician ?? "\(patient.fullName) Care Team") : nil
        record.sourceKind = ClinicalSourceKind.localAI.rawValue
        record.sourceSystemName = "OpenClinic Encounter Workspace"
        record.sourceRecordIdentifier = record.recordID
        record.sourceLastSyncedAt = .now
        record.sourceOfTruth = false
        record.patient = patient

        try? modelContext.save()
        workflowState.lastSavedDocumentationStatus = lifecycle

        AppLogger.exam.info("📝 Clinical record \(createdNewRecord ? "created" : "updated"): \(record.recordID) — \(note.primaryDiagnosis) [\(lifecycle.rawValue)]")

        if generatePDF {
            if let url = generatePDFLocally(patient: patient, record: record, details: note) {
                workflowState.generatedPDFURL = url
                AppLogger.exam.info("📄 PDF generated: \(url.lastPathComponent)")
            } else {
                workflowState.generatedPDFURL = nil
                AppLogger.exam.warning("⚠️ PDF generation returned nil")
            }
        } else {
            workflowState.generatedPDFURL = nil
        }
    }

    private func clinicalDataRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.bold()).foregroundColor(.purple)
            Text(value).font(.callout)
        }
    }
}
