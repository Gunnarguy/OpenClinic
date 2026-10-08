import Foundation
import SwiftData
import SwiftUI
import Combine
import os

#if canImport(FoundationModels)
import FoundationModels

// Fallback dummy for SDKs without PrivateCloudComputeLanguageModel
#if !compiler(>=7.0)
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
final class PrivateCloudComputeLanguageModel {
    var isAvailable: Bool { false }
    var quotaUsage: QuotaUsage { QuotaUsage() }
    
    struct QuotaUsage {
        var isLimitReached: Bool { true }
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
extension LanguageModelSession {
    convenience init(model: PrivateCloudComputeLanguageModel, instructions: String) {
        self.init(instructions: instructions)
    }
    convenience init(model: PrivateCloudComputeLanguageModel, tools: [any Tool], instructions: String) {
        self.init(tools: tools, instructions: instructions)
    }
}
#endif

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
enum PlatformLanguageModel {
    case system(SystemLanguageModel)
    case privateCloudCompute(PrivateCloudComputeLanguageModel)
}
#endif

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable
struct ClinicalVisitNote {
    // Each guide asks for what the dictation says and nothing more. The earlier wording asked for
    // recommendations, and the note it produced could hold orders nobody dictated.
    @Guide(description: "The condition the dictation names as the subject of the visit.")
    let primaryDiagnosis: String

    @Guide(description: "The reason for the visit and its history, as dictated.")
    let ccHPI: String

    @Guide(description: "Symptoms the dictation says are present or absent.")
    let reviewOfSystems: String

    @Guide(description: "What the dictation says was seen on examination, with body sites.")
    let examFindings: String

    @Guide(description: "The assessment and the plan, as dictated.")
    let impressionsAndPlan: String

    @Guide(description: "What the dictation says the patient was told to do.")
    let patientInstructions: String

    @Guide(description: "When the dictation says the patient returns.")
    let followUpPlan: String

    @Guide(description: "Tests, referrals or procedures the dictation says were ordered.")
    let recommendedOrders: [String]

    @Guide(description: "Medicines the dictation says were started, stopped or continued.")
    let medicationChanges: [String]

    @Guide(description: "Body sites the dictation names.")
    let affectedAnatomicalZones: [String]
}

/// The model's answer to a question about a record: the answer and the lines it rests on.
/// It has no field for advice. The model reports what the record says; it is not asked what to do.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable
struct ChartAnswer {
    @Guide(description: "Direct answer to the question using only facts stated in the record.")
    let answer: String

    @Guide(description: "Short lines from the record that support the answer.")
    let supportingFacts: [String]
}

#else
struct ClinicalVisitNote: Codable {
    let primaryDiagnosis: String
    let ccHPI: String
    let reviewOfSystems: String
    let examFindings: String
    let impressionsAndPlan: String
    let patientInstructions: String
    let followUpPlan: String
    let recommendedOrders: [String]
    let medicationChanges: [String]
    let affectedAnatomicalZones: [String]
}

#endif

/// How a panel question was answered.
nonisolated enum PanelAnswer: Sendable {
    /// Computed from structured chart data, with the facts behind each match.
    case computed(CohortResult)
    /// Written by the language model from a chart summary. Not checked against the chart.
    case generated(String)
    /// Listed from chart rows by the app because the model did not write an answer. `reason` says why.
    case listed(String, reason: String)
}

/// Where the words of an answer came from. The screen says which, because text listed by the app
/// from chart rows and text written by a language model deserve different trust.
nonisolated enum AnswerOrigin: Sendable, Equatable {
    /// Written by the on-device language model.
    case model
    /// Listed from chart rows by the app. `reason` says why the model did not write the answer.
    case chartListing(reason: String)
    /// A note filled in by the app's keyword rules. `reason` says why the model did not draft it.
    case keywordRules(reason: String)

    static let modelUnavailable = "The on-device model is not available."

    /// The system's own wording of why the model did not answer. It describes the model, not the chart.
    static func modelDidNotAnswer(_ error: any Error) -> String {
        "The on-device model did not answer: \(error.localizedDescription)"
    }

    /// The line shown, or spoken by Shortcuts, with the text it describes.
    var note: String {
        switch self {
        case .model:
            return "Written by the on-device model. This text has not been checked against the chart."
        case .chartListing(let reason):
            return "Listed from the chart by the app. No language model wrote this. \(reason)"
        case .keywordRules(let reason):
            return "Sorted from the dictation by the app's keyword rules. No language model wrote this. \(reason)"
        }
    }
}

/// What a saved visit note records about its own origin. Only a draft the model wrote is marked as
/// AI; one sorted by the keyword rules holds the clinician's own sentences and nothing else.
nonisolated enum SavedNoteOrigin {
    static func sourceKind(for origin: AnswerOrigin?) -> ClinicalSourceKind {
        if case .model? = origin { return .localAI }
        return .clinicianCaptured
    }

    static func visitType(for origin: AnswerOrigin?) -> String {
        if case .model? = origin { return "AI-assisted encounter" }
        return "Dictated encounter"
    }
}

/// What a Shortcut says back: the answer, then who wrote it. A dialog has no badge to carry that.
nonisolated enum AnswerDialog {
    static func text(_ answer: PatientAnswer) -> String {
        "\(answer.text)\n\n\(answer.origin.note)"
    }

    static func text(_ answer: PanelAnswer) -> String {
        switch answer {
        case .computed(let result):
            return "\(CohortAnswerFormatter.text(for: result))\n\nComputed from chart data by the app. No language model wrote this."
        case .generated(let text):
            return "\(text)\n\n\(AnswerOrigin.model.note)"
        case .listed(let text, let reason):
            return "\(text)\n\n\(AnswerOrigin.chartListing(reason: reason).note)"
        }
    }
}

/// The on-device model was given up on because it took too long.
nonisolated struct ModelTimeLimitError: LocalizedError, Sendable {
    let limit: Duration

    var errorDescription: String? {
        "no answer within \(limit.components.seconds) seconds."
    }
}

/// A visit note drafted from a dictation, and who drafted it.
struct NoteDraft {
    let note: ClinicalVisitNote
    let origin: AnswerOrigin
}

/// An answer to a question about one patient.
nonisolated struct PatientAnswer: Sendable {
    let text: String
    let origin: AnswerOrigin
}

@MainActor
final class ClinicalIntelligenceService: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    // MARK: - RAG pipeline reference
    private let ragService = ClinicalRAGService.shared

    /// Whether to use RAG-augmented context (vs. static tool summaries only).
    var ragEnabled: Bool = true

    /// False makes every answer come from the chart formatters and no language model is called.
    /// Unit tests set it, so they neither wait on a model nor depend on what one writes.
    var languageModelEnabled: Bool = true

    /// Whether to use Deep Think multi-pass retrieval.
    var deepThinkEnabled: Bool = false

    // MARK: - Conversational session state
    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private var patientSession: LanguageModelSession? {
        get { _patientSession as? LanguageModelSession }
        set { _patientSession = newValue }
    }
    #endif
    private var _patientSession: Any?
    /// True once the model has declined a structured answer about this patient and written the
    /// plain-text one. Later questions about the patient ask for plain text at once.
    private var patientAnswersInPlainText = false
    private var currentPatientID: UUID?
    private var lastRAGMetadata: ResponseMetadata?

    /// Last RAG response metadata (timing, chunk counts, verification).
    var ragMetadata: ResponseMetadata? { lastRAGMetadata }

    /// Reset conversational sessions (call when switching patient context).
    func resetSessions() {
        AppLogger.ai.info("🔄 Resetting AI sessions")
        _patientSession = nil
        patientAnswersInPlainText = false
        currentPatientID = nil
        lastRAGMetadata = nil
    }

    // On 2026-10-07 the on-device model refused every structured answer asked for as a "clinical
    // chart assistant" (6 of 6, "May contain sensitive content") and answered every one asked for
    // as below (6 of 6), on the same record and question.
    private let assistantInstructions = """
    You answer questions about a record that is given to you. Use only what the record and the tools state.
    If they do not state the answer, say so. Give dates, names and amounts as the record gives them.
    """

    private let dictationInstructions = """
    You sort a dictated summary of a visit into the sections of a visit note. Write only what the dictation states, in the dictation's own terms. Leave a section empty rather than add anything that was not said.
    """

    private let panelAssistantInstructions = """
    You answer questions about records that are given to you, one line per person. Use only what the records state.
    If they do not state the answer, say so. Name each person the answer is about, with dates and amounts as the records give them.
    """

    private let panelMergeInstructions = """
    You merge partial answers to one question into a single answer. Keep every name, date and amount. Add nothing that the partial answers do not state.
    """

    var engineStatusLabel: String {
        let ragStatus = ragService.indexedChunkCount > 0 ? " + RAG (\(ragService.indexedChunkCount) chunks)" : ""
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            let model = SystemLanguageModel(useCase: .general)
            switch model.availability {
            case .available:
                return "Apple Intelligence on-device model ready\(ragStatus)"
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Apple Intelligence disabled - using local fallback\(ragStatus)"
            case .unavailable(.deviceNotEligible):
                return "Device not eligible - using local fallback\(ragStatus)"
            case .unavailable(.modelNotReady):
                return "On-device model downloading - using local fallback\(ragStatus)"
            @unknown default:
                return "Foundation model availability unknown - using local fallback\(ragStatus)"
            }
        }
        #endif
        return "Local fallback workflow active\(ragStatus)"
    }

    /// Drafts a visit note from a dictation. The on-device model is asked twice, in the two forms it
    /// accepts; when it writes neither, the app sorts the dictation's sentences into the sections by
    /// keyword, and `origin` says so. `patient` is not read: a note says what was dictated at this visit.
    func draftNote(from dictation: String, patient: PatientProfile? = nil, selectedAnatomy: String? = nil) async throws -> NoteDraft {
        AppLogger.ai.info("🧠 draftNote called — dictation: \(dictation.count) chars, anatomy: \(selectedAnatomy ?? "nil")")
        var reason = AnswerOrigin.modelUnavailable
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            let estimatedTokens = Self.estimateTokens(dictation) + 1500 // Base summary estimate
            if let model = resolveModel(for: estimatedTokens) {
                do {
                    let note = try await generateStructuredNoteWithFoundationModel(from: dictation, selectedAnatomy: selectedAnatomy, model: model)
                    AppLogger.ai.info("✅ Note drafted by the model, structured")
                    return NoteDraft(note: note, origin: .model)
                } catch {
                    AppLogger.ai.error("❌ Structured note refused or failed, asking for plain sections: \(error.localizedDescription)")
                    reason = AnswerOrigin.modelDidNotAnswer(error)
                }
                do {
                    let note = try await generateNoteAsPlainSections(from: dictation, selectedAnatomy: selectedAnatomy, model: model)
                    AppLogger.ai.info("✅ Note drafted by the model, plain sections")
                    return NoteDraft(note: note, origin: .model)
                } catch {
                    AppLogger.ai.error("❌ Plain-section note refused or failed: \(error.localizedDescription)")
                    reason = AnswerOrigin.modelDidNotAnswer(error)
                }
            }
        }
        #endif

        AppLogger.ai.info("📦 Using keyword rules for the note")
        let note = generateFallbackStructuredNote(from: dictation, selectedAnatomy: selectedAnatomy)
        return NoteDraft(note: note, origin: .keywordRules(reason: reason))
    }

    /// How long the on-device model may take to write one answer. The framework's call has no limit
    /// of its own, and a call that never returns would leave nothing on screen but a spinner.
    var modelTimeLimit: Duration = .seconds(60)

    /// Runs one model call and gives up on it after `modelTimeLimit`. The caller then lists chart
    /// rows and says the model did not answer in time. The wait ends at the limit even when the
    /// call ignores cancellation and keeps running.
    func withModelTimeLimit<Result: Sendable>(_ operation: @escaping @MainActor () async throws -> Result) async throws -> Result {
        let limit = modelTimeLimit
        let once = ResumeOnce()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let work = Task { @MainActor in
                    do {
                        let result = try await operation()
                        if once.claim() { continuation.resume(returning: result) }
                    } catch {
                        if once.claim() { continuation.resume(throwing: error) }
                    }
                }
                once.cancelWork = { work.cancel() }
                once.timer = Task { @MainActor in
                    try? await Task.sleep(for: limit)
                    guard !Task.isCancelled, once.claim() else { return }
                    work.cancel()
                    continuation.resume(throwing: ModelTimeLimitError(limit: limit))
                }
            }
        } onCancel: {
            // The caller gave up (a view went away): the model call is told, and the timer still
            // ends the wait if the call does not listen.
            Task { @MainActor in once.cancelWork?() }
        }
    }

    /// Lets exactly one of two tasks answer a continuation, and stops the timer when the work wins.
    @MainActor
    private final class ResumeOnce {
        private var claimed = false
        var timer: Task<Void, Never>?
        var cancelWork: (() -> Void)?

        func claim() -> Bool {
            guard !claimed else { return false }
            claimed = true
            timer?.cancel()
            return true
        }
    }

    /// The answer as plain text, for Shortcuts and tests. Screens use `answerPatientQuestion`, which
    /// also says whether the model or the app wrote the text.
    func executeToolQuery(query: String, modelContext: ModelContext, patient: PatientProfile? = nil) async throws -> String {
        try await answerPatientQuestion(query: query, modelContext: modelContext, patient: patient).text
    }

    /// Answers a question about one patient. The on-device model writes the answer when it is
    /// available and willing; otherwise the app lists the matching chart rows, and `origin` says so.
    func answerPatientQuestion(query: String, modelContext: ModelContext, patient: PatientProfile? = nil) async throws -> PatientAnswer {
        AppLogger.ai.info("🔍 executeToolQuery — query: \(query.prefix(60)), patient: \(patient?.fullName ?? "nil"), RAG: \(self.ragEnabled)")

        // Reset session if patient changed
        if let pid = patient?.id, pid != currentPatientID {
            AppLogger.ai.info("👤 Patient context changed — resetting patient session")
            _patientSession = nil
            patientAnswersInPlainText = false
            currentPatientID = pid
        }

        // Step 1: RAG context retrieval (if indexed data exists)
        var ragContext: String?
        if ragEnabled && ragService.indexedChunkCount > 0 {
            do {
                let ragResponse: RAGResponse
                if deepThinkEnabled {
                    ragResponse = try await ragService.deepThink(text: query, patientScope: patient?.id, passes: 3)
                } else {
                    ragResponse = try await ragService.queryWithVerification(text: query, patientScope: patient?.id)
                }
                lastRAGMetadata = ragResponse.metadata
                if !ragResponse.retrievedChunks.isEmpty {
                    ragContext = ragResponse.context
                    AppLogger.ai.info("📊 RAG: \(ragResponse.retrievedChunks.count) chunks, \(String(format: "%.0f", ragResponse.metadata.totalTimeMs))ms, confidence: \(ragResponse.metadata.verification?.confidence.rawValue ?? "n/a")")
                }
            } catch {
                AppLogger.ai.warning("⚠️ RAG retrieval failed (continuing without): \(error.localizedDescription)")
            }
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            let estimatedTokens = Self.estimateTokens(query) + (ragContext.map { Self.estimateTokens($0) } ?? 0) + 1000 // Base context tools estimate
            if let model = resolveModel(for: estimatedTokens) {
                AppLogger.ai.info("✨ Foundation Model tool query")
                ragService.addStep(.generation, "Asking the on-device model", "Apple Intelligence", icon: "apple.logo")
                do {
                    let result = try await executeFoundationModelQuery(query: query, modelContext: modelContext, patient: patient, model: model, ragContext: ragContext)
                    AppLogger.ai.info("✅ Tool query response: \(result.count) chars")
                    return PatientAnswer(text: result, origin: .model)
                } catch {
                    AppLogger.ai.error("❌ Foundation Model tool query failed: \(error.localizedDescription)")
                    ragService.addStep(.generation, "The model did not answer", "The app lists chart rows instead", icon: "list.bullet.rectangle")
                    let listing = try await executeFallbackQuery(query: query, modelContext: modelContext, patient: patient)
                    return PatientAnswer(text: listing, origin: .chartListing(reason: AnswerOrigin.modelDidNotAnswer(error)))
                }
            }
        }
        #endif

        AppLogger.ai.info("📦 Using fallback tool query")
        let listing = try await executeFallbackQuery(query: query, modelContext: modelContext, patient: patient)
        return PatientAnswer(text: listing, origin: .chartListing(reason: AnswerOrigin.modelUnavailable))
    }

    /// Answers a cross-patient question.
    ///
    /// A set question ("which patients ...", "who is on ...") is computed from
    /// structured chart data by `CohortEngine`, with the chart facts behind each
    /// match. Only a question the parser does not fully understand goes to the
    /// language model, and that answer is returned as `.generated` so the
    /// caller can label it as unverified.
    func answerPanelQuestion(_ query: String, modelContext: ModelContext) async throws -> PanelAnswer {
        let allPatients = try modelContext.fetch(FetchDescriptor<PatientProfile>(sortBy: [SortDescriptor(\.lastName)]))
        let snapshot = PanelSnapshot(patients: allPatients)
        let parser = CohortQueryParser(vocabulary: PanelVocabulary(snapshot: snapshot))

        if let cohortQuery = parser.parse(query) {
            let result = CohortEngine.run(cohortQuery, on: snapshot)
            lastRAGMetadata = nil
            AppLogger.ai.info("🧮 Panel question computed from chart data: \(result.matches.count) of \(result.panelSize) patients")
            return .computed(result)
        }

        AppLogger.ai.info("🗣️ Panel question not parsed as a cohort query, using the language model")
        return try await generatePanelAnswer(query: query, allPatients: allPatients, modelContext: modelContext)
    }

    /// Cross-patient panel query as plain text, for Shortcuts and evaluation runs.
    func executePanelQuery(query: String, modelContext: ModelContext) async throws -> String {
        switch try await answerPanelQuestion(query, modelContext: modelContext) {
        case .computed(let result): return CohortAnswerFormatter.text(for: result)
        case .generated(let text): return text
        case .listed(let text, _): return text
        }
    }

    /// Language-model path for panel questions the cohort parser does not cover. Returns
    /// `.generated` for model text and `.listed` when the app listed chart rows instead.
    private func generatePanelAnswer(query: String, allPatients: [PatientProfile], modelContext: ModelContext) async throws -> PanelAnswer {
        AppLogger.ai.info("🏥 generatePanelAnswer — \(allPatients.count) patients, query: \(query.prefix(60)), RAG: \(self.ragEnabled)")

        // RAG context retrieval (panel-wide, no patient scope)
        var ragContext: String?
        if ragEnabled && ragService.indexedChunkCount > 0 {
            do {
                let ragResponse: RAGResponse
                if deepThinkEnabled {
                    ragResponse = try await ragService.deepThink(text: query, passes: 3)
                } else {
                    ragResponse = try await ragService.queryWithVerification(text: query)
                }
                lastRAGMetadata = ragResponse.metadata
                if !ragResponse.retrievedChunks.isEmpty {
                    ragContext = ragResponse.context
                    AppLogger.ai.info("📊 RAG (panel): \(ragResponse.retrievedChunks.count) chunks, \(String(format: "%.0f", ragResponse.metadata.totalTimeMs))ms")
                }
            } catch {
                AppLogger.ai.warning("⚠️ RAG panel retrieval failed: \(error.localizedDescription)")
            }
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) {
            let estimatedTokens = Self.estimateTokens(query) + (ragContext.map { Self.estimateTokens($0) } ?? 0) + (allPatients.count * 20)
            if let model = resolveModel(for: estimatedTokens) {
                AppLogger.ai.info("✨ Foundation Model panel query")
                ragService.addStep(.generation, "Asking the on-device model", "Apple Intelligence (panel)", icon: "apple.logo")
                do {
                    let result = try await executePanelFoundationModelQuery(query: query, patients: allPatients, modelContext: modelContext, model: model, ragContext: ragContext)
                    AppLogger.ai.info("✅ Panel response: \(result.count) chars")
                    return .generated(result)
                } catch {
                    AppLogger.ai.error("❌ Foundation Model panel query failed: \(error.localizedDescription)")
                    ragService.addStep(.generation, "The model did not answer", "The app lists chart rows instead", icon: "list.bullet.rectangle")
                    return .listed(
                        executePanelFallbackQuery(query: query, patients: allPatients, modelContext: modelContext),
                        reason: AnswerOrigin.modelDidNotAnswer(error)
                    )
                }
            }
        }
        #endif

        AppLogger.ai.info("📦 Using fallback panel query")
        return .listed(
            executePanelFallbackQuery(query: query, patients: allPatients, modelContext: modelContext),
            reason: AnswerOrigin.modelUnavailable
        )
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func resolveModel(for estimatedTokens: Int) -> PlatformLanguageModel? {
        guard languageModelEnabled else { return nil }
        let pcc = PrivateCloudComputeLanguageModel()
        if estimatedTokens > 4000, pcc.isAvailable, !pcc.quotaUsage.isLimitReached {
            AppLogger.ai.info("☁️ Routing to Private Cloud Compute (\(estimatedTokens) estimated tokens)")
            return .privateCloudCompute(pcc)
        }
        
        let model = SystemLanguageModel(useCase: .general)
        return model.isAvailable ? .system(model) : nil
    }

    private func dictationSession(_ model: PlatformLanguageModel) -> LanguageModelSession {
        switch model {
        case .system(let m):
            return LanguageModelSession(model: m, instructions: dictationInstructions)
        case .privateCloudCompute(let m):
            return LanguageModelSession(model: m, instructions: dictationInstructions)
        }
    }

    /// The prompt holds the dictation and the body site, and nothing from the chart: the model
    /// refuses a structured note when the record is in the prompt, and a note should say what was
    /// dictated at this visit, not what the chart already holds.
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func generateStructuredNoteWithFoundationModel(
        from dictation: String,
        selectedAnatomy: String?,
        model: PlatformLanguageModel
    ) async throws -> ClinicalVisitNote {
        let session = dictationSession(model)
        let prompt = """
        Body site in focus: \(selectedAnatomy ?? "not specified")

        Dictation:
        \(dictation)

        Sort the dictation into the sections of the note.
        """
        let note = try await withModelTimeLimit {
            try await session.respond(to: prompt, generating: ClinicalVisitNote.self).content
        }
        return normalize(note: note, selectedAnatomy: selectedAnatomy)
    }

    /// The second form: the same note as labeled lines of plain text, which the model writes when it
    /// has declined to fill the structure.
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func generateNoteAsPlainSections(
        from dictation: String,
        selectedAnatomy: String?,
        model: PlatformLanguageModel
    ) async throws -> ClinicalVisitNote {
        let session = dictationSession(model)
        let prompt = """
        Body site in focus: \(selectedAnatomy ?? "not specified")

        Dictation:
        \(dictation)

        \(VisitNoteText.request)
        """
        let text = try await withModelTimeLimit {
            try await session.respond(to: prompt).content
        }
        guard let sections = VisitNoteText.parse(text) else {
            throw VisitNoteTextError.notANote
        }
        return normalize(note: ClinicalVisitNote(
            primaryDiagnosis: sections.diagnosis,
            ccHPI: sections.history,
            reviewOfSystems: sections.symptoms,
            examFindings: sections.exam,
            impressionsAndPlan: sections.plan,
            patientInstructions: sections.instructions,
            followUpPlan: sections.followUp,
            recommendedOrders: sections.orders,
            medicationChanges: sections.medicationChanges,
            affectedAnatomicalZones: sections.bodySites
        ), selectedAnatomy: selectedAnatomy)
    }

    private enum VisitNoteTextError: LocalizedError {
        case notANote
        var errorDescription: String? { "the model's text did not hold the sections of a note." }
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func executeFoundationModelQuery(
        query: String,
        modelContext: ModelContext,
        patient: PatientProfile?,
        model: PlatformLanguageModel,
        ragContext: String? = nil
    ) async throws -> String {
        let patientSummary = ClinicalChartFormatter.patientSummary(patient: patient)
        let medications = try ClinicalChartFormatter.medications(modelContext: modelContext, patient: patient)
        let medicationSummary = ClinicalChartFormatter.medicationSummary(medications: medications)
        let records = try ClinicalChartFormatter.records(modelContext: modelContext, patient: patient)
        let recordSummary = ClinicalChartFormatter.recordSummary(records: records)
        let historyEntries = records.map {
            ClinicalHistoryEntry(
                summary: ClinicalChartFormatter.recordSummary(records: [$0]),
                searchText: [
                    $0.conditionName,
                    $0.ccHPI,
                    $0.impressionsAndPlan,
                    $0.visitType,
                    $0.carePlanSummary,
                    $0.followUpPlan,
                    ($0.recommendedOrders ?? []).joined(separator: " ")
                ]
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            )
        }
        let appointments = (patient?.appointments ?? []).sorted { $0.scheduledTime < $1.scheduledTime }
        let appointmentSummary = ClinicalChartFormatter.appointmentSummary(appointments: appointments)

        let tools: [any Tool] = [
            PatientSummaryTool(summary: patientSummary),
            MedicationLookupTool(summary: medicationSummary),
            ClinicalHistoryLookupTool(allSummary: recordSummary, entries: historyEntries),
            AppointmentLookupTool(summary: appointmentSummary)
        ]

        func makeSession() -> LanguageModelSession {
            switch model {
            case .system(let m):
                return LanguageModelSession(model: m, tools: tools, instructions: assistantInstructions)
            case .privateCloudCompute(let m):
                return LanguageModelSession(model: m, tools: tools, instructions: assistantInstructions)
            }
        }

        // Reuse or create patient session for conversational continuity
        let session: LanguageModelSession
        if let existing = self.patientSession {
            session = existing
            AppLogger.ai.info("♻️ Reusing existing patient session")
        } else {
            session = makeSession()
            self.patientSession = session
            AppLogger.ai.info("🆕 Created new patient session")
        }

        let prompt = """
        Record of \(patient?.fullName ?? "the patient"):
        \(ragContext.map { "\($0)\n" } ?? "The tools return the record.\n")
        Question: \(query)
        """

        if patientAnswersInPlainText {
            do {
                return try await withModelTimeLimit {
                    try await session.respond(to: prompt).content
                }
            } catch let late as ModelTimeLimitError {
                self.patientSession = nil
                throw late
            } catch {
                // A long conversation can fill a session. One more try in a new one; if that fails
                // too, the caller lists chart rows.
                self.patientSession = nil
                let fresh = makeSession()
                let text = try await withModelTimeLimit {
                    try await fresh.respond(to: prompt).content
                }
                self.patientSession = fresh
                return text
            }
        }

        do {
            let answer = try await withModelTimeLimit {
                try await session.respond(to: prompt, generating: ChartAnswer.self).content
            }
            return ClinicalChartFormatter.format(answer: answer.answer, supportingFacts: answer.supportingFacts)
        } catch let late as ModelTimeLimitError {
            // The call may still be running inside this session, so the next question gets a new one.
            self.patientSession = nil
            throw late
        } catch {
            // The model declines some structured answers and writes the same answer as plain text.
            // A session that has declined keeps the refusal in its transcript, so the retry starts a new one.
            AppLogger.ai.error("❌ Structured answer refused or failed, asking for plain text: \(error.localizedDescription)")
            self.patientSession = nil
            let fresh = makeSession()
            let text = try await withModelTimeLimit {
                try await fresh.respond(to: prompt).content
            }
            // The conversation goes on in the form the model answers, without the declined try each time.
            self.patientSession = fresh
            self.patientAnswersInPlainText = true
            return text
        }
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func executePanelFoundationModelQuery(
        query: String,
        patients: [PatientProfile],
        modelContext: ModelContext,
        model: PlatformLanguageModel,
        ragContext: String? = nil
    ) async throws -> String {
        // ── Token Budget (OpenIntelligence-style) ──────────────────────
        // If PCC is used, we have 32768 context window, otherwise 4096.
        let isPCC: Bool
        switch model {
        case .system:
            isPCC = false
        case .privateCloudCompute:
            isPCC = true
        }
        let contextWindow = isPCC ? 32768 : 4096
        // 1.4 chars/token (empirically validated for Apple FM WordPiece tokenizer)
        let charsPerToken: Double = 1.4

        let systemPromptTokens = Self.estimateTokens(panelAssistantInstructions)
        let questionTokens = Self.estimateTokens(query)
        let ragTokens = ragContext.map { Self.estimateTokens(String($0.prefix(1200))) } ?? 0
        let outputReserveTokens = 300
        let safetyFactor = 0.88  // 12% margin
        let rawAvailable = contextWindow - systemPromptTokens - questionTokens - ragTokens - outputReserveTokens
        let availableTokens = max(0, Int(Double(rawAvailable) * safetyFactor))
        let availableChars = Int(Double(availableTokens) * charsPerToken)

        AppLogger.ai.info("📊 Token budget: \(availableTokens) tokens (\(availableChars) chars) for \(patients.count) patients")
        ragService.addStep(.generation, "Token budget: \(availableTokens) available", "\(patients.count) patients, \(contextWindow)-token window", icon: "gauge.with.needle")

        // ── Query-Aware Extraction ─────────────────────────────────────
        // Classify what data fields the query actually needs. Don't waste
        // 3000 chars on medication history when the question is about ages.
        let intent = PanelQueryIntent.classify(query)
        ragService.addStep(.generation, "Query intent: \(intent.label)", "Fields: \(intent.fields.joined(separator: ", "))", icon: "magnifyingglass.circle")
        AppLogger.ai.info("🔍 Panel query intent: \(intent.label) — fields: \(intent.fields)")

        // ── Compact Patient Representations ────────────────────────────
        // Build minimal single-line representations per patient with only
        // the fields this query needs. Dramatically reduces token usage.
        let compactLines = patients.map { intent.compactLine(for: $0) }
        let compactContext = compactLines.joined(separator: "\n")
        let contextTokens = Self.estimateTokens(compactContext)

        AppLogger.ai.info("📏 Compact context: \(compactContext.count) chars ≈ \(contextTokens) tokens")

        func makeSession(_ instructions: String) -> LanguageModelSession {
            switch model {
            case .system(let m):
                return LanguageModelSession(model: m, instructions: instructions)
            case .privateCloudCompute(let m):
                return LanguageModelSession(model: m, instructions: instructions)
            }
        }

        // ── Single-Pass (fits in budget) ───────────────────────────────
        // Skip tools entirely — put compact data directly in prompt.
        // Reclaims ~1000 tokens that tool schemas would consume.
        if contextTokens <= availableTokens {
            ragService.addStep(.generation, "Single-pass mode", "\(contextTokens)/\(availableTokens) tokens — fits", icon: "checkmark.seal")

            let session = makeSession(panelAssistantInstructions)
            let trimmedRAG = ragContext.map { String($0.prefix(1200)) }

            let prompt = """
            Records of \(patients.count) patients:
            \(compactContext)
            \(trimmedRAG.map { "\nRelated record text:\n\($0)" } ?? "")

            Question: \(query)
            """

            let answer = try await withModelTimeLimit {
                try await session.respond(to: prompt, generating: ChartAnswer.self).content
            }
            return ClinicalChartFormatter.format(answer: answer.answer, supportingFacts: answer.supportingFacts)
        }

        // ── Recursive RAG (overflow) ───────────────────────────────────
        // Context too large even with compact extraction. Process in passes,
        // each filling most of the available token budget.
        let charsPerBatch = availableChars
        var currentBatch: [String] = []
        var currentChars = 0
        var batches: [[String]] = []
        var batchPatients: [[PatientProfile]] = []
        var currentBatchPatients: [PatientProfile] = []

        for (i, line) in compactLines.enumerated() {
            let lineChars = line.count + 1  // +1 for newline
            if currentChars + lineChars > charsPerBatch && !currentBatch.isEmpty {
                batches.append(currentBatch)
                batchPatients.append(currentBatchPatients)
                currentBatch = []
                currentBatchPatients = []
                currentChars = 0
            }
            currentBatch.append(line)
            currentBatchPatients.append(patients[i])
            currentChars += lineChars
        }
        if !currentBatch.isEmpty {
            batches.append(currentBatch)
            batchPatients.append(currentBatchPatients)
        }

        ragService.addStep(.generation, "Recursive RAG: \(batches.count) passes", "\(patients.count) patients exceed single-pass budget", icon: "arrow.triangle.2.circlepath")
        AppLogger.ai.info("🔄 Recursive RAG: \(batches.count) passes for \(patients.count) patients")

        // Every pass has to be written by the model. A pass it declines is thrown, and the caller
        // then lists chart rows for the whole question: an answer is never part model, part app.
        var passResults: [String] = []
        for (i, batch) in batches.enumerated() {
            let batchPts = batchPatients[i]
            ragService.addStep(.generation, "Pass \(i + 1)/\(batches.count)", "\(batchPts.count) patients", icon: "brain")

            let session = makeSession(panelAssistantInstructions)
            let batchContext = batch.joined(separator: "\n")
            let prompt = """
            Records of \(batchPts.count) patients (part \(i + 1) of \(batches.count)):
            \(batchContext)

            Question: \(query)
            Answer for these people only.
            """
            let answer = try await withModelTimeLimit {
                try await session.respond(to: prompt, generating: ChartAnswer.self).content
            }
            passResults.append(answer.answer)
            AppLogger.ai.info("✅ Pass \(i + 1): \(answer.answer.count) chars")
        }

        // ── Synthesis ──────────────────────────────────────────────────
        ragService.addStep(.generation, "Synthesizing \(batches.count) passes", "Merging into unified answer", icon: "arrow.triangle.merge")

        let combined = passResults.enumerated().map { "[\($0.offset + 1)] \($0.element)" }.joined(separator: "\n")
        let combinedTokens = Self.estimateTokens(combined)

        if combinedTokens <= availableTokens {
            // Fits — synthesize with FM
            do {
                let session = makeSession(panelMergeInstructions)
                let prompt = """
                Question: \(query)

                Partial answers:
                \(String(combined.prefix(availableChars)))

                Merge them into one answer.
                """
                let answer = try await withModelTimeLimit {
                    try await session.respond(to: prompt, generating: ChartAnswer.self).content
                }
                return ClinicalChartFormatter.format(answer: answer.answer, supportingFacts: answer.supportingFacts)
            } catch {
                AppLogger.ai.warning("⚠️ Synthesis FM failed — concatenating directly")
            }
        }

        // Too large to merge, or the merge was declined: the model's own partial answers, in order.
        return passResults.joined(separator: "\n\n")
    }

    // MARK: - Token Estimation

    /// Estimate token count using 1.4 chars/token (validated for Apple FM WordPiece tokenizer)
    private static func estimateTokens(_ text: String) -> Int {
        max(1, Int(ceil(Double(text.count) / 1.4)))
    }

    // MARK: - Panel Query Intent Classification

    /// Classifies panel queries to extract only the data fields needed, avoiding
    /// wasted tokens on irrelevant patient information.
    private enum PanelQueryIntent {
        case demographics    // age, sex, name, MRN, blood type
        case medications     // drug names, doses, indications
        case conditions      // diagnoses, conditions, clinical records
        case scheduling      // appointments, follow-ups
        case riskFactors     // allergies, risk flags, smoking
        case fullClinical    // needs everything (complex cross-domain queries)

        var label: String {
            switch self {
            case .demographics: return "demographics"
            case .medications: return "medications"
            case .conditions: return "conditions"
            case .scheduling: return "scheduling"
            case .riskFactors: return "risk factors"
            case .fullClinical: return "full clinical"
            }
        }

        var fields: [String] {
            switch self {
            case .demographics: return ["name", "age", "sex", "MRN"]
            case .medications: return ["name", "medications"]
            case .conditions: return ["name", "conditions", "diagnoses"]
            case .scheduling: return ["name", "appointments"]
            case .riskFactors: return ["name", "allergies", "risk flags", "smoking"]
            case .fullClinical: return ["name", "age", "conditions", "medications", "appointments", "allergies"]
            }
        }

        static func classify(_ query: String) -> PanelQueryIntent {
            let q = query.lowercased()

            let demoKeywords = ["age", "old", "young", "birth", "gender", "sex", "male", "female", "mrn", "blood type", "demographic"]
            let medKeywords = ["medication", "medicine", "drug", "prescri", "dose", "biologic", "topical", "steroid", "methotrexate", "refill", "pharmacy"]
            let conditionKeywords = ["diagnosis", "condition", "disease", "psoriasis", "eczema", "dermatitis", "melanoma", "acne", "rash", "lesion", "biopsy"]
            let schedKeywords = ["appointment", "schedule", "visit", "upcoming", "follow-up", "next visit", "today", "tomorrow", "when"]
            let riskKeywords = ["allergy", "allergic", "risk", "smok", "flag", "contraindic"]

            var scores: [(PanelQueryIntent, Int)] = []
            scores.append((.demographics, demoKeywords.filter { q.contains($0) }.count))
            scores.append((.medications, medKeywords.filter { q.contains($0) }.count))
            scores.append((.conditions, conditionKeywords.filter { q.contains($0) }.count))
            scores.append((.scheduling, schedKeywords.filter { q.contains($0) }.count))
            scores.append((.riskFactors, riskKeywords.filter { q.contains($0) }.count))

            let best = scores.max(by: { $0.1 < $1.1 })
            if let best, best.1 > 0 {
                return best.0
            }
            return .fullClinical
        }

        /// Build a compact single-line representation with only query-relevant fields.
        func compactLine(for patient: PatientProfile) -> String {
            switch self {
            case .demographics:
                return "\(patient.fullName) | \(patient.shortAgeText) \(patient.gender) | MRN: \(patient.medicalRecordNumber.prefix(8)) | Blood: \(patient.bloodType ?? "—")"

            case .medications:
                let meds = (patient.medications ?? [])
                    .filter { ($0.status ?? "Active") == "Active" }
                    .map { "\($0.medicationName) \($0.dose ?? "")" }
                    .joined(separator: "; ")
                return "\(patient.fullName) | Meds: \(meds.isEmpty ? "none" : String(meds.prefix(200)))"

            case .conditions:
                let conditions = Array(Set((patient.clinicalRecords ?? []).map(\.conditionName)))
                    .joined(separator: "; ")
                return "\(patient.fullName) | Dx: \(conditions.isEmpty ? "none" : String(conditions.prefix(200)))"

            case .scheduling:
                let appts = (patient.appointments ?? [])
                    .sorted { $0.scheduledTime < $1.scheduledTime }
                    .prefix(2)
                    .map { "\($0.scheduledTime.formatted(date: .abbreviated, time: .shortened)): \($0.reasonForVisit)" }
                    .joined(separator: "; ")
                return "\(patient.fullName) | Appts: \(appts.isEmpty ? "none scheduled" : appts)"

            case .riskFactors:
                let allergies = patient.allergies.isEmpty ? "none" : patient.allergies.joined(separator: ", ")
                let risks = patient.riskFlags.isEmpty ? "none" : patient.riskFlags.joined(separator: ", ")
                return "\(patient.fullName) | Allergies: \(allergies) | Risks: \(risks) | Smoker: \(patient.isSmoker ? "yes" : "no")"

            case .fullClinical:
                let topCondition = (patient.clinicalRecords ?? []).first?.conditionName ?? "—"
                let medCount = (patient.medications ?? []).filter { ($0.status ?? "Active") == "Active" }.count
                let allergies = patient.allergies.isEmpty ? "none" : patient.allergies.prefix(3).joined(separator: ",")
                let nextAppt = (patient.appointments ?? []).sorted { $0.scheduledTime < $1.scheduledTime }.first
                let apptStr = nextAppt.map { $0.scheduledTime.formatted(date: .abbreviated, time: .shortened) } ?? "—"
                return "\(patient.fullName) | \(patient.shortAgeText) \(patient.gender) | Dx: \(topCondition) | \(medCount) meds | Allg: \(allergies) | Next: \(apptStr)"
            }
        }
    }
    #endif

    /// The draft when the model writes none: the dictation's own sentences, sorted into sections by
    /// keyword (`DictationSorter`). The app adds no finding, plan or order of its own, and nothing
    /// from the chart: a section the dictation did not cover says "Not dictated." The body sites are
    /// the one the clinician selected and any the dictation names.
    private func generateFallbackStructuredNote(from dictation: String, selectedAnatomy: String?) -> ClinicalVisitNote {
        let sections = DictationSorter.sort(dictation)
        return ClinicalVisitNote(
            primaryDiagnosis: sections.diagnosis,
            ccHPI: sections.history,
            reviewOfSystems: sections.symptoms,
            examFindings: sections.exam,
            impressionsAndPlan: sections.plan,
            patientInstructions: sections.instructions,
            followUpPlan: sections.followUp,
            recommendedOrders: [],
            medicationChanges: [],
            affectedAnatomicalZones: inferredZones(from: dictation.lowercased(), selectedAnatomy: selectedAnatomy)
        )
    }

    private func executeFallbackQuery(query: String, modelContext: ModelContext, patient: PatientProfile?) async throws -> String {
        let normalizedQuery = query.lowercased()

        if ["medication", "prescription", "rx", "refill"].contains(where: normalizedQuery.contains) {
            let medications = try ClinicalChartFormatter.medications(modelContext: modelContext, patient: patient)
            if medications.isEmpty {
                return "No medications are currently on file for this patient."
            }
            return ClinicalChartFormatter.medicationSummary(medications: medications)
        }

        if ["appointment", "follow-up", "schedule", "next visit"].contains(where: normalizedQuery.contains) {
            let appointments = (patient?.appointments ?? []).sorted { $0.scheduledTime < $1.scheduledTime }
            return appointments.isEmpty ? "No appointments are currently scheduled for this patient." : ClinicalChartFormatter.appointmentSummary(appointments: appointments)
        }

        if ["allerg", "smok", "pharmacy", "mrn", "risk"].contains(where: normalizedQuery.contains) {
            return ClinicalChartFormatter.patientSummary(patient: patient)
        }

        let records = try ClinicalChartFormatter.records(modelContext: modelContext, patient: patient)
        let matching = ClinicalHeuristics.filter(records: records, for: normalizedQuery)
        if matching.isEmpty {
            return records.isEmpty ? "No clinical history is currently available for this patient." : ClinicalChartFormatter.recordSummary(records: Array(records.prefix(5)))
        }
        return ClinicalChartFormatter.recordSummary(records: matching)
    }

    private func executePanelFallbackQuery(query: String, patients: [PatientProfile], modelContext: ModelContext) -> String {
        let q = query.lowercased()
        let cal = Calendar.current

        // Schedule / today queries
        if ["schedule", "today", "agenda", "who"].contains(where: q.contains) {
            let todayAppts = patients.flatMap { p in
                (p.appointments ?? []).filter { cal.isDateInToday($0.scheduledTime) }
                    .map { (p, $0) }
            }.sorted { $0.1.scheduledTime < $1.1.scheduledTime }

            if todayAppts.isEmpty { return "No appointments scheduled for today." }
            let lines = todayAppts.map { "\($0.0.fullName) — \($0.1.scheduledTime.formatted(date: .omitted, time: .shortened)): \($0.1.reasonForVisit) [\($0.1.status)]" }
            return "Today's schedule (\(todayAppts.count) patients):\n" + lines.joined(separator: "\n")
        }

        // Medication queries across panel
        if ["medication", "rx", "prescri", "drug", "taking"].contains(where: q.contains) {
            let medEntries = patients.flatMap { p in
                (p.medications ?? []).map { "[\(p.fullName)] \($0.medicationName) — \($0.quantityInfo) | Status: \($0.status ?? "Active")" }
            }
            return medEntries.isEmpty ? "No medications on file for any patient." : "Panel medications (\(medEntries.count)):\n" + medEntries.joined(separator: "\n")
        }

        // Risk / allergy queries
        if ["risk", "allerg", "flag", "smok"].contains(where: q.contains) {
            let entries = patients.compactMap { p -> String? in
                var flags: [String] = []
                if !p.allergies.isEmpty { flags.append("Allergies: \(p.allergies.joined(separator: ", "))") }
                if !p.riskFlags.isEmpty { flags.append("Risk: \(p.riskFlags.joined(separator: ", "))") }
                if p.isSmoker { flags.append("Current smoker") }
                return flags.isEmpty ? nil : "[\(p.fullName)] \(flags.joined(separator: " | "))"
            }
            return entries.isEmpty ? "No risk flags or allergies documented across the panel." : "Panel risk overview:\n" + entries.joined(separator: "\n")
        }

        // Condition / diagnosis search
        let allRecords = patients.flatMap { p in
            (p.clinicalRecords ?? []).map { (p, $0) }
        }
        let tokens = q.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 }
        let matched = allRecords.filter { pair in
            let haystack = [pair.1.conditionName, pair.1.ccHPI, pair.1.impressionsAndPlan].compactMap { $0?.lowercased() }.joined(separator: " ")
            return tokens.contains { haystack.contains($0) }
        }

        if !matched.isEmpty {
            let lines = matched.sorted { $0.1.dateRecorded > $1.1.dateRecorded }.prefix(10).map {
                "[\($0.0.fullName)] \($0.1.dateRecorded.formatted(date: .abbreviated, time: .omitted)): \($0.1.conditionName) — \($0.1.status)"
            }
            return "Matching records across panel (\(matched.count) total):\n" + lines.joined(separator: "\n")
        }

        // General panel overview fallback
        let summary = patients.prefix(16).map { p -> String in
            let conditionCount = p.clinicalRecords?.count ?? 0
            let medCount = p.medications?.count ?? 0
            let nextAppt = (p.appointments ?? []).filter { $0.scheduledTime > Date() }.sorted { $0.scheduledTime < $1.scheduledTime }.first
            var line = "\(p.fullName) — \(conditionCount) records, \(medCount) meds"
            if let appt = nextAppt { line += ", next: \(appt.reasonForVisit)" }
            return line
        }
        return "Patient panel (\(patients.count)):\n" + summary.joined(separator: "\n") + "\n\nTry asking about specific conditions, medications, risks, or today's schedule."
    }

    private func inferredZones(from dictation: String, selectedAnatomy: String?) -> [String] {
        var zones = Set<String>()
        if let selectedAnatomy {
            zones.insert(selectedAnatomy)
        }

        // Whole words only: "itching" names no chin and "diagnosed" no nose.
        for (zone, label) in AnatomicalRegion.regionNames {
            let names = [zone.replacingOccurrences(of: "_", with: " "), label.lowercased()]
            let named = names.contains { name in
                !name.isEmpty && dictation.range(
                    of: #"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\b"#,
                    options: [.regularExpression, .caseInsensitive]) != nil
            }
            if named { zones.insert(zone) }
        }

        return zones.isEmpty ? (selectedAnatomy.map { [$0] } ?? []) : Array(zones).sorted()
    }

    private func normalize(note: ClinicalVisitNote, selectedAnatomy: String?) -> ClinicalVisitNote {
        let zones = note.affectedAnatomicalZones.isEmpty ? (selectedAnatomy.map { [$0] } ?? []) : note.affectedAnatomicalZones
        return ClinicalVisitNote(
            primaryDiagnosis: note.primaryDiagnosis,
            ccHPI: note.ccHPI,
            reviewOfSystems: note.reviewOfSystems,
            examFindings: note.examFindings,
            impressionsAndPlan: note.impressionsAndPlan,
            patientInstructions: note.patientInstructions,
            followUpPlan: note.followUpPlan,
            recommendedOrders: note.recommendedOrders,
            medicationChanges: note.medicationChanges,
            affectedAnatomicalZones: zones
        )
    }
}

private struct ClinicalHistoryEntry: Sendable {
    let summary: String
    let searchText: String
}

private enum ClinicalHeuristics {
    static func filter(records: [LocalClinicalRecord], for query: String) -> [LocalClinicalRecord] {
        let tokens = query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }

        let filtered = records.filter { record in
            let haystack = [
                record.conditionName,
                record.ccHPI,
                record.impressionsAndPlan,
                record.visitType,
                record.carePlanSummary
            ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

            return tokens.contains { haystack.contains($0) }
        }

        return filtered.sorted { $0.dateRecorded > $1.dateRecorded }
    }
}

private enum ClinicalChartFormatter {
    static func medications(modelContext: ModelContext, patient: PatientProfile?) throws -> [LocalMedication] {
        // With a patient in view the answer is that patient's rows, and none when there are none.
        if let patient {
            return (patient.medications ?? []).sorted { $0.writtenDate > $1.writtenDate }
        }
        return try modelContext.fetch(FetchDescriptor<LocalMedication>()).sorted { $0.writtenDate > $1.writtenDate }
    }

    static func records(modelContext: ModelContext, patient: PatientProfile?) throws -> [LocalClinicalRecord] {
        if let patient {
            return (patient.clinicalRecords ?? []).sorted { $0.dateRecorded > $1.dateRecorded }
        }
        return try modelContext.fetch(FetchDescriptor<LocalClinicalRecord>()).sorted { $0.dateRecorded > $1.dateRecorded }
    }

    static func patientSummary(patient: PatientProfile?) -> String {
        guard let patient else {
            return "No patient is currently selected in chart context."
        }

        let allergies = patient.allergies.isEmpty ? "None documented" : patient.allergies.joined(separator: ", ")
        let riskFlags = patient.riskFlags.isEmpty ? "None documented" : patient.riskFlags.joined(separator: ", ")

        return """
        Patient: \(patient.fullName)
        MRN: \(patient.medicalRecordNumber)
        Age/Sex: \(patient.ageText) / \(patient.gender)
        Smoking: \(patient.isSmoker ? "Current smoker" : "Non-smoker")
        Primary clinician: \(patient.primaryClinician ?? "Not assigned")
        Preferred pharmacy: \(patient.preferredPharmacy ?? "Not documented")
        Allergies: \(allergies)
        Risk flags: \(riskFlags)
        Blood type: \(patient.bloodType ?? "Not documented")
        Care plan summary: \(patient.carePlanSummary ?? "No care plan summary documented")
        """
    }

    static func medicationSummary(medications: [LocalMedication]) -> String {
        guard !medications.isEmpty else {
            return "No medications currently on file."
        }

        return medications.map { medication in
            var line = "\(medication.medicationName)"
            if let dose = medication.dose, !dose.isEmpty {
                line += " \(dose)"
            }
            line += " | \(medication.route ?? "Unspecified") | \(medication.frequency ?? "See instructions") | Status: \(medication.status ?? "Active")"
            if let indication = medication.indication {
                line += " | Indication: \(indication)"
            }
            if let pharmacyName = medication.pharmacyName {
                line += " | Pharmacy: \(pharmacyName)"
            }
            if let lastFilledDate = medication.lastFilledDate {
                line += " | Last filled: \(lastFilledDate.formatted(date: .abbreviated, time: .omitted))"
            }
            if let nextRefillEligibleDate = medication.nextRefillEligibleDate {
                line += " | Refill eligible: \(nextRefillEligibleDate.formatted(date: .abbreviated, time: .omitted))"
            }
            if let safetyNotes = medication.safetyNotes, !safetyNotes.isEmpty {
                line += " | Safety: \(safetyNotes.joined(separator: "; "))"
            }
            return line
        }
        .joined(separator: "\n")
    }

    static func recordSummary(records: [LocalClinicalRecord]) -> String {
        guard !records.isEmpty else {
            return "No clinical history currently on file."
        }

        return records.map { record in
            var line = "\(record.dateRecorded.formatted(date: .abbreviated, time: .omitted)): \(record.conditionName) [\(record.status)]"
            if let visitType = record.visitType {
                line += " | Visit: \(visitType)"
            }
            if let severity = record.severity {
                line += " | Severity: \(severity)"
            }
            if let followUpPlan = record.followUpPlan {
                line += " | Follow-up: \(followUpPlan)"
            }
            return line
        }
        .joined(separator: "\n")
    }

    static func appointmentSummary(appointments: [Appointment]) -> String {
        guard !appointments.isEmpty else {
            return "No appointments scheduled."
        }

        return appointments.map { appointment in
            var line = "\(appointment.scheduledTime.formatted(date: .abbreviated, time: .shortened)): \(appointment.reasonForVisit)"
            if let encounterType = appointment.encounterType { line += " | \(encounterType)" }
            if let clinicianName = appointment.clinicianName { line += " | Clinician: \(clinicianName)" }
            if let location = appointment.location { line += " | Location: \(location)" }
            if let checkInStatus = appointment.checkInStatus { line += " | Check-in: \(checkInStatus)" }
            if let linkedDiagnoses = appointment.linkedDiagnoses, !linkedDiagnoses.isEmpty {
                line += " | Diagnoses: \(linkedDiagnoses.joined(separator: ", "))"
            }
            return line
        }
        .joined(separator: "\n")
    }

    /// A model answer and the record lines it rests on.
    static func format(answer: String, supportingFacts: [String]) -> String {
        guard !supportingFacts.isEmpty else { return answer }
        return answer + "\n\nSupport:\n- " + supportingFacts.joined(separator: "\n- ")
    }

}

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private struct PatientSummaryTool: Tool {
    let summary: String

    let name = "patientSummary"
    let description = "Returns the current patient's demographics, allergies, risk flags, clinician, and care plan summary."

    @Generable
    struct Arguments {
        @Guide(description: "What part of the patient summary the model wants, such as allergies, risk flags, or demographics.")
        let focus: String
    }

    func call(arguments: Arguments) async throws -> String {
        summary
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private struct MedicationLookupTool: Tool {
    let summary: String

    let name = "medicationLookup"
    let description = "Returns active and prior medications with dose, route, frequency, refill timing, and safety notes."

    @Generable
    struct Arguments {
        @Guide(description: "Medication question focus, such as active meds, refill timing, or safety concerns.")
        let focus: String
    }

    func call(arguments: Arguments) async throws -> String {
        summary
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private struct ClinicalHistoryLookupTool: Tool {
    let allSummary: String
    let entries: [ClinicalHistoryEntry]

    let name = "clinicalHistoryLookup"
    let description = "Returns the patient's visit history, diagnoses, care plan summaries, and follow-up recommendations."

    @Generable
    struct Arguments {
        @Guide(description: "Condition or historical focus requested by the clinician.")
        let focus: String
    }

    func call(arguments: Arguments) async throws -> String {
        let tokens = arguments.focus
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }

        guard !tokens.isEmpty else {
            return allSummary
        }

        let filtered = entries.filter { entry in
            tokens.contains { entry.searchText.contains($0) }
        }

        return filtered.isEmpty ? allSummary : filtered.map(\ .summary).joined(separator: "\n")
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private struct AppointmentLookupTool: Tool {
    let summary: String

    let name = "appointmentLookup"
    let description = "Returns upcoming appointments, encounter types, locations, and linked diagnoses for the current patient."

    @Generable
    struct Arguments {
        @Guide(description: "Scheduling focus, such as next visit, follow-up, or urgent evaluation.")
        let focus: String
    }

    func call(arguments: Arguments) async throws -> String {
        summary
    }
}

// MARK: - Panel-Wide Tools (cross-patient queries)

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private struct PanelRosterTool: Tool {
    let summary: String

    let name = "panelRoster"
    let description = "Returns demographics, allergies, risk flags, and care plan for every patient in the panel. Use to find patients by condition, age, risk, or demographic."

    @Generable
    struct Arguments {
        @Guide(description: "What aspect of the patient roster to focus on, such as allergies, smokers, risk flags, or a specific patient name.")
        let focus: String
    }

    func call(arguments: Arguments) async throws -> String {
        String(summary.prefix(2000))
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private struct PanelMedicationTool: Tool {
    let summary: String

    let name = "panelMedications"
    let description = "Returns all medications across every patient in the panel, tagged by patient name. Use to find who is on a specific drug, correlate prescriptions, or check for interactions across patients."

    @Generable
    struct Arguments {
        @Guide(description: "Medication focus — a drug name, drug class, or question like 'who is on methotrexate' or 'biologics prescribed'.")
        let focus: String
    }

    func call(arguments: Arguments) async throws -> String {
        String(summary.prefix(2000))
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private struct PanelHistoryTool: Tool {
    let allSummary: String
    let entries: [ClinicalHistoryEntry]

    let name = "panelClinicalHistory"
    let description = "Returns clinical visit history and diagnoses across all patients. Use to find patients with a specific condition, correlate diagnoses, or review treatment outcomes across the panel."

    @Generable
    struct Arguments {
        @Guide(description: "Clinical focus — a condition, procedure, diagnosis, or treatment pattern to search for across all patients.")
        let focus: String
    }

    func call(arguments: Arguments) async throws -> String {
        let tokens = arguments.focus
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }

        guard !tokens.isEmpty else { return allSummary }

        let filtered = entries.filter { entry in
            tokens.contains { entry.searchText.contains($0) }
        }
        let result = filtered.isEmpty ? allSummary : filtered.map(\.summary).joined(separator: "\n")
        return String(result.prefix(2000))
    }
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
private struct PanelScheduleTool: Tool {
    let summary: String

    let name = "panelSchedule"
    let description = "Returns today's full clinic schedule across all patients with appointment times, visit reasons, and workflow status."

    @Generable
    struct Arguments {
        @Guide(description: "Schedule focus, such as who is next, completed visits, or patients still waiting.")
        let focus: String
    }

    func call(arguments: Arguments) async throws -> String {
        String(summary.prefix(2000))
    }
}
#endif
