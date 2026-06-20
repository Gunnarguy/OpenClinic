import Foundation
import SwiftData
import SwiftUI
import Combine
import os

#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable
struct ClinicalVisitNote {
    @Guide(description: "Primary diagnosis or assessment title for the encounter.")
    let primaryDiagnosis: String

    @Guide(description: "Chief complaint and history of present illness in clinician-ready form.")
    let ccHPI: String

    @Guide(description: "Review of systems using only findings supported by the dictation and chart context.")
    let reviewOfSystems: String

    @Guide(description: "Physical exam findings with anatomical specificity when available.")
    let examFindings: String

    @Guide(description: "Assessment and plan written as concise clinical prose.")
    let impressionsAndPlan: String

    @Guide(description: "Patient-facing after-visit instructions.")
    let patientInstructions: String

    @Guide(description: "Explicit follow-up recommendation including timeframe when possible.")
    let followUpPlan: String

    @Guide(description: "Orders, referrals, labs, or procedures recommended for this encounter.")
    let recommendedOrders: [String]

    @Guide(description: "Medication changes started, stopped, or continued during this encounter.")
    let medicationChanges: [String]

    @Guide(description: "Anatomical zones referenced by the encounter.")
    let affectedAnatomicalZones: [String]
}

@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@Generable
struct ClinicalAssistantAnswer {
    @Guide(description: "Direct answer to the clinician's question using only chart-supported facts.")
    let answer: String

    @Guide(description: "Short factual bullets from the chart that support the answer.")
    let supportingFacts: [String]

    @Guide(description: "Operational next steps or follow-up actions if appropriate.")
    let recommendedActions: [String]
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

struct ClinicalAssistantAnswer: Codable {
    let answer: String
    let supportingFacts: [String]
    let recommendedActions: [String]
}
#endif

@MainActor
final class ClinicalIntelligenceService: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()

    // MARK: - RAG pipeline reference
    private let ragService = ClinicalRAGService.shared

    /// Whether to use RAG-augmented context (vs. static tool summaries only).
    var ragEnabled: Bool = true

    /// Whether to use Deep Think multi-pass retrieval.
    var deepThinkEnabled: Bool = false

    // MARK: - Conversational session state
    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private var patientSession: LanguageModelSession? {
        get { _patientSession as? LanguageModelSession }
        set { _patientSession = newValue }
    }
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private var panelSession: LanguageModelSession? {
        get { _panelSession as? LanguageModelSession }
        set { _panelSession = newValue }
    }
    #endif
    private var _patientSession: Any?
    private var _panelSession: Any?
    private var currentPatientID: UUID?
    private var lastRAGMetadata: ResponseMetadata?

    /// Last RAG response metadata (timing, chunk counts, verification).
    var ragMetadata: ResponseMetadata? { lastRAGMetadata }

    /// Reset conversational sessions (call when switching patient context).
    func resetSessions() {
        AppLogger.ai.info("🔄 Resetting AI sessions")
        _patientSession = nil
        _panelSession = nil
        currentPatientID = nil
        lastRAGMetadata = nil
    }

    private let documentationInstructions = """
    You are an on-device clinical documentation assistant.
    Generate chart-ready medical documentation using only the supplied dictation and patient chart context.
    Do not fabricate symptoms, orders, medications, or diagnoses.
    If information is uncertain, stay conservative and reflect the uncertainty in clinically appropriate language.
    """

    private let assistantInstructions = """
    You are an on-device clinical chart assistant.
    Answer the clinician's question using only tool output and chart context from this device.
    Do not invent missing facts.
    Prefer concise answers with concrete dates, medications, diagnoses, and follow-up details when available.
    """

    private let panelAssistantInstructions = """
    You are an on-device clinical intelligence assistant for a dermatology practice.
    You have access to the full patient panel — all patients, their medications, diagnoses, visit histories, and today's schedule.
    Answer queries by correlating data across multiple patients when asked.
    Use only chart-supported facts from tool output. Do not fabricate data.
    Be concise, specific, and clinically actionable. Include patient names, dates, and concrete details.
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

    func generateStructuredNote(from dictation: String, patient: PatientProfile? = nil, selectedAnatomy: String? = nil) async throws -> ClinicalVisitNote {
        AppLogger.ai.info("🧠 generateStructuredNote called — dictation: \(dictation.count) chars, patient: \(patient?.fullName ?? "nil"), anatomy: \(selectedAnatomy ?? "nil")")
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), let model = availableFoundationModel() {
            AppLogger.ai.info("✨ Foundation Model available — using on-device AI")
            do {
                let note = try await generateStructuredNoteWithFoundationModel(
                    from: dictation,
                    patient: patient,
                    selectedAnatomy: selectedAnatomy,
                    model: model
                )
                AppLogger.ai.info("✅ Foundation Model note generated: \(note.primaryDiagnosis)")
                return note
            } catch {
                AppLogger.ai.error("❌ Foundation Model failed, falling back: \(error.localizedDescription)")
                return generateFallbackStructuredNote(from: dictation, patient: patient, selectedAnatomy: selectedAnatomy)
            }
        }
        #endif

        AppLogger.ai.info("📦 Using fallback note generation")
        return generateFallbackStructuredNote(from: dictation, patient: patient, selectedAnatomy: selectedAnatomy)
    }

    func executeToolQuery(query: String, modelContext: ModelContext, patient: PatientProfile? = nil) async throws -> String {
        AppLogger.ai.info("🔍 executeToolQuery — query: \(query.prefix(60)), patient: \(patient?.fullName ?? "nil"), RAG: \(self.ragEnabled)")

        // Reset session if patient changed
        if let pid = patient?.id, pid != currentPatientID {
            AppLogger.ai.info("👤 Patient context changed — resetting patient session")
            _patientSession = nil
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

        ragService.addStep(.generation, "Generating with Apple Intelligence", "On-device Foundation Model", icon: "apple.logo")

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), let model = availableFoundationModel() {
            AppLogger.ai.info("✨ Foundation Model tool query")
            do {
                let result = try await executeFoundationModelQuery(query: query, modelContext: modelContext, patient: patient, model: model, ragContext: ragContext)
                AppLogger.ai.info("✅ Tool query response: \(result.count) chars")
                return result
            } catch {
                AppLogger.ai.error("❌ Foundation Model tool query failed: \(error.localizedDescription)")
                return try await executeFallbackQuery(query: query, modelContext: modelContext, patient: patient)
            }
        }
        #endif

        AppLogger.ai.info("📦 Using fallback tool query")
        return try await executeFallbackQuery(query: query, modelContext: modelContext, patient: patient)
    }

    /// Cross-patient panel query — searches across ALL patients in the database.
    func executePanelQuery(query: String, modelContext: ModelContext) async throws -> String {
        let allPatients = try modelContext.fetch(FetchDescriptor<PatientProfile>(sortBy: [SortDescriptor(\.lastName)]))
        AppLogger.ai.info("🏥 executePanelQuery — \(allPatients.count) patients, query: \(query.prefix(60)), RAG: \(self.ragEnabled)")

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

        ragService.addStep(.generation, "Generating with Apple Intelligence", "On-device Foundation Model (panel)", icon: "apple.logo")

        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, visionOS 26.0, *), let model = availableFoundationModel() {
            AppLogger.ai.info("✨ Foundation Model panel query")
            do {
                let result = try await executePanelFoundationModelQuery(query: query, patients: allPatients, modelContext: modelContext, model: model, ragContext: ragContext)
                AppLogger.ai.info("✅ Panel response: \(result.count) chars")
                return result
            } catch {
                AppLogger.ai.error("❌ Foundation Model panel query failed: \(error.localizedDescription)")
                return executePanelFallbackQuery(query: query, patients: allPatients, modelContext: modelContext)
            }
        }
        #endif

        AppLogger.ai.info("📦 Using fallback panel query")
        return executePanelFallbackQuery(query: query, patients: allPatients, modelContext: modelContext)
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func availableFoundationModel() -> SystemLanguageModel? {
        let model = SystemLanguageModel(useCase: .general)
        return model.isAvailable ? model : nil
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func generateStructuredNoteWithFoundationModel(
        from dictation: String,
        patient: PatientProfile?,
        selectedAnatomy: String?,
        model: SystemLanguageModel
    ) async throws -> ClinicalVisitNote {
        AppLogger.ai.info("🚀 Building Foundation Model prompt for structured note")
        let session = LanguageModelSession(model: model, instructions: documentationInstructions)
        let context = ClinicalChartFormatter.patientSummary(patient: patient)
        let history = ClinicalChartFormatter.recordSummary(records: (patient?.clinicalRecords ?? []).sorted { $0.dateRecorded > $1.dateRecorded })
        let medications = ClinicalChartFormatter.medicationSummary(medications: (patient?.medications ?? []).sorted { $0.writtenDate > $1.writtenDate })
        let appointments = ClinicalChartFormatter.appointmentSummary(appointments: (patient?.appointments ?? []).sorted { $0.scheduledTime < $1.scheduledTime })

        let prompt = """
        Patient chart summary:
        \(context)

        Active medications:
        \(medications)

        Recent and prior clinical history:
        \(history)

        Upcoming schedule:
        \(appointments)

        Selected anatomical focus: \(selectedAnatomy ?? "not specified")

        Physician dictation:
        \(dictation)

        Return a fully structured encounter note suitable for same-day charting.
        """

        let response = try await session.respond(to: prompt, generating: ClinicalVisitNote.self)
        return normalize(note: response.content, selectedAnatomy: selectedAnatomy)
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func executeFoundationModelQuery(
        query: String,
        modelContext: ModelContext,
        patient: PatientProfile?,
        model: SystemLanguageModel,
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

        // Reuse or create patient session for conversational continuity
        let session: LanguageModelSession
        if let existing = self.patientSession {
            session = existing
            AppLogger.ai.info("♻️ Reusing existing patient session")
        } else {
            session = LanguageModelSession(model: model, tools: tools, instructions: assistantInstructions)
            self.patientSession = session
            AppLogger.ai.info("🆕 Created new patient session")
        }

        let prompt = """
        Active chart patient: \(patient?.fullName ?? "No specific patient selected")
        \(ragContext.map { "Retrieved clinical context (from RAG search):\n\($0)\n" } ?? "")
        Clinician question: \(query)
        Answer using tool output, retrieved context, and chart facts only.
        """

        let response = try await session.respond(to: prompt, generating: ClinicalAssistantAnswer.self)
        return ClinicalChartFormatter.format(answer: response.content)
    }

    @available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
    private func executePanelFoundationModelQuery(
        query: String,
        patients: [PatientProfile],
        modelContext: ModelContext,
        model: SystemLanguageModel,
        ragContext: String? = nil
    ) async throws -> String {
        // ── Token Budget (OpenIntelligence-style) ──────────────────────
        // 4096 total context window (Apple FM hard limit per TN3193)
        // 1.4 chars/token (empirically validated for Apple FM WordPiece tokenizer)
        let contextWindow = 4096
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

        // ── Single-Pass (fits in budget) ───────────────────────────────
        // Skip tools entirely — put compact data directly in prompt.
        // Reclaims ~1000 tokens that tool schemas would consume.
        if contextTokens <= availableTokens {
            ragService.addStep(.generation, "Single-pass mode", "\(contextTokens)/\(availableTokens) tokens — fits", icon: "checkmark.seal")

            let session = LanguageModelSession(model: model, instructions: panelAssistantInstructions)
            let trimmedRAG = ragContext.map { String($0.prefix(1200)) }

            let prompt = """
            Patient panel (\(patients.count) patients):
            \(compactContext)
            \(trimmedRAG.map { "\nRetrieved clinical context:\n\($0)" } ?? "")

            Clinician question: \(query)
            Answer using ONLY the patient data above. Include patient names. Be specific and concise.
            """

            let response = try await session.respond(to: prompt, generating: ClinicalAssistantAnswer.self)
            return ClinicalChartFormatter.format(answer: response.content)
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

        var passResults: [String] = []
        for (i, batch) in batches.enumerated() {
            let batchPts = batchPatients[i]
            let names = batchPts.prefix(3).map(\.fullName).joined(separator: ", ") + (batchPts.count > 3 ? " + \(batchPts.count - 3) more" : "")
            ragService.addStep(.generation, "Pass \(i + 1)/\(batches.count)", names, icon: "brain")

            do {
                let session = LanguageModelSession(model: model, instructions: panelAssistantInstructions)
                let batchContext = batch.joined(separator: "\n")
                let prompt = """
                Patient batch \(i + 1)/\(batches.count) (\(batchPts.count) patients):
                \(batchContext)

                Clinician question: \(query)
                Answer for these patients only. Include all patient names.
                """
                let response = try await session.respond(to: prompt, generating: ClinicalAssistantAnswer.self)
                passResults.append(response.content.answer)
                AppLogger.ai.info("✅ Pass \(i + 1): \(response.content.answer.count) chars")
            } catch {
                AppLogger.ai.warning("⚠️ Pass \(i + 1) failed: \(error.localizedDescription)")
                let fallback = batchPts.map { "\($0.fullName): data unavailable" }.joined(separator: "\n")
                passResults.append(fallback)
            }
        }

        // ── Synthesis ──────────────────────────────────────────────────
        ragService.addStep(.generation, "Synthesizing \(batches.count) passes", "Merging into unified answer", icon: "arrow.triangle.merge")

        let combined = passResults.enumerated().map { "[\($0.offset + 1)] \($0.element)" }.joined(separator: "\n")
        let combinedTokens = Self.estimateTokens(combined)

        if combinedTokens <= availableTokens {
            // Fits — synthesize with FM
            do {
                let session = LanguageModelSession(model: model, instructions: "Merge partial clinical answers into one cohesive response. Preserve all patient names and data. Be concise.")
                let prompt = """
                Original question: \(query)

                Partial answers:
                \(String(combined.prefix(availableChars)))

                Combine into a single complete answer.
                """
                let response = try await session.respond(to: prompt, generating: ClinicalAssistantAnswer.self)
                return ClinicalChartFormatter.format(answer: response.content)
            } catch {
                AppLogger.ai.warning("⚠️ Synthesis FM failed — concatenating directly")
            }
        }

        // Either too large for FM synthesis or FM failed — format directly
        let header = "Panel query across \(patients.count) patients:\n\n"
        return header + passResults.joined(separator: "\n\n")
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
                return "\(patient.fullName) | \(patient.age)y \(patient.gender) | MRN: \(patient.medicalRecordNumber.prefix(8)) | Blood: \(patient.bloodType ?? "—")"

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
                return "\(patient.fullName) | \(patient.age)y \(patient.gender) | Dx: \(topCondition) | \(medCount) meds | Allg: \(allergies) | Next: \(apptStr)"
            }
        }
    }
    #endif

    private func generateFallbackStructuredNote(from dictation: String, patient: PatientProfile?, selectedAnatomy: String?) -> ClinicalVisitNote {
        let lower = dictation.lowercased()
        let profile = ClinicalHeuristics.profile(for: lower, patient: patient)
        let zones = inferredZones(from: lower, selectedAnatomy: selectedAnatomy)
        let zoneLabel = zones.map { AnatomicalRegion.displayName(for: $0) }.joined(separator: ", ")
        let patientPrefix = patient.map { "\($0.fullName), age \($0.age)," } ?? "Patient"

        let historyContext: String
        if let patient, let lastRecord = (patient.clinicalRecords ?? []).sorted(by: { $0.dateRecorded > $1.dateRecorded }).first {
            historyContext = " Recent chart history includes \(lastRecord.conditionName.lowercased())."
        } else {
            historyContext = ""
        }

        let hpi = "\(patientPrefix) presents for evaluation of \(profile.name.lowercased()) involving \(zoneLabel.isEmpty ? "the documented area" : zoneLabel).\(historyContext) Dictation notes: \(dictation.trimmingCharacters(in: .whitespacesAndNewlines))."

        let exam = zoneLabel.isEmpty
            ? profile.examTemplate
            : "\(profile.examTemplate) Focused examination localizes findings to \(zoneLabel)."

        return ClinicalVisitNote(
            primaryDiagnosis: profile.name,
            ccHPI: hpi,
            reviewOfSystems: profile.reviewOfSystems,
            examFindings: exam,
            impressionsAndPlan: profile.plan,
            patientInstructions: profile.patientInstructions,
            followUpPlan: profile.followUp,
            recommendedOrders: profile.orders,
            medicationChanges: profile.medicationChanges,
            affectedAnatomicalZones: zones
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

        for (zone, label) in AnatomicalRegion.regionNames {
            if dictation.contains(zone.replacingOccurrences(of: "_", with: " ")) || dictation.contains(label.lowercased()) {
                zones.insert(zone)
            }
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
    struct Profile {
        let name: String
        let reviewOfSystems: String
        let examTemplate: String
        let plan: String
        let patientInstructions: String
        let followUp: String
        let orders: [String]
        let medicationChanges: [String]
    }

    static func profile(for dictation: String, patient: PatientProfile?) -> Profile {
        let knownConditions = (patient?.clinicalRecords ?? []).map { $0.conditionName.lowercased() }

        if dictation.contains("melanoma") || knownConditions.contains(where: { $0.contains("melanoma") }) {
            return Profile(
                name: "Pigmented Lesion Under Melanoma Evaluation",
                reviewOfSystems: "Denies constitutional symptoms unless otherwise documented. Monitor for evolving pigment change, bleeding, or rapid enlargement.",
                examTemplate: "Pigmented lesion demonstrates asymmetry or other concerning morphology requiring formal lesion assessment.",
                plan: "Pigmented lesion is clinically concerning. Recommend biopsy or definitive excision based on lesion morphology, pathology review, and oncology surveillance history.",
                patientInstructions: "Photograph the lesion only if instructed, avoid manipulating the site, and report bleeding or rapid growth immediately.",
                followUp: "Expedited pathology review with oncology-focused dermatology follow-up within 1 to 2 weeks.",
                orders: ["Dermatopathology review", "Lesion photography"],
                medicationChanges: []
            )
        }

        if dictation.contains("psoriasis") || dictation.contains("plaque") || knownConditions.contains(where: { $0.contains("psoriasis") }) {
            return Profile(
                name: "Plaque Psoriasis",
                reviewOfSystems: "Assess itching, morning stiffness, nail changes, fatigue, and any joint swelling or dactylitis symptoms.",
                examTemplate: "Well-demarcated erythematous plaques with scale are present in the documented distribution.",
                plan: "Psoriasis flare requires topical optimization and reassessment for systemic therapy need, particularly if joint symptoms or functional limitation are present.",
                patientInstructions: "Use topical therapy exactly as prescribed, moisturize daily, and report worsening joint pain, fever, or mouth sores if systemic therapy is started.",
                followUp: "Clinical and safety-lab follow-up in 4 to 6 weeks.",
                orders: ["CBC", "CMP", "Rheumatology review if joint symptoms persist"],
                medicationChanges: ["Continue or optimize psoriasis-directed therapy"]
            )
        }

        if dictation.contains("eczema") || dictation.contains("dermatitis") || knownConditions.contains(where: { $0.contains("dermatitis") }) {
            return Profile(
                name: "Eczematous Dermatitis",
                reviewOfSystems: "Assess itch severity, sleep disruption, trigger exposure, superinfection symptoms, and asthma or allergy flare if relevant.",
                examTemplate: "Exam shows eczematous erythema with scale, excoriation, or lichenification in the affected distribution.",
                plan: "Dermatitis is being managed with barrier repair, trigger avoidance, and anti-inflammatory therapy adjusted to severity and anatomical location.",
                patientInstructions: "Continue emollients aggressively, avoid known triggers, and watch for drainage, crusting, or signs of infection.",
                followUp: "Reassess symptom control in 2 to 8 weeks depending on severity.",
                orders: ["Patch testing if contact dermatitis remains possible"],
                medicationChanges: ["Continue dermatitis regimen with topical adjustment as needed"]
            )
        }

        if dictation.contains("rosacea") || dictation.contains("flushing") || knownConditions.contains(where: { $0.contains("rosacea") }) {
            return Profile(
                name: "Rosacea",
                reviewOfSystems: "Assess flushing triggers, ocular irritation, burning, stinging, and any worsening nasal skin thickening.",
                examTemplate: "Centrofacial erythema and inflammatory change are present in the documented distribution.",
                plan: "Rosacea management should address inflammatory lesions, trigger mitigation, and ocular involvement when present.",
                patientInstructions: "Use daily sunscreen, avoid known triggers such as heat and alcohol, and report worsening eye symptoms promptly.",
                followUp: "Follow-up in 4 to 6 weeks to reassess inflammatory control and ocular symptoms.",
                orders: ["Ophthalmology referral if ocular symptoms are present"],
                medicationChanges: ["Continue rosacea-directed topical therapy"]
            )
        }

        if dictation.contains("wart") || dictation.contains("verruca") {
            return Profile(
                name: "Verruca Vulgaris",
                reviewOfSystems: "Review treatment response, lesion spread, pain with pressure, and new satellite lesions.",
                examTemplate: "Verrucous papule is present with morphology consistent with common wart.",
                plan: "Treat with procedural destruction and adjunct topical therapy if persistent or multifocal.",
                patientInstructions: "Keep treated sites clean, avoid picking, and minimize autoinoculation with hand hygiene.",
                followUp: "Procedure follow-up in 3 to 4 weeks if lesion persists.",
                orders: ["Repeat cryotherapy if needed"],
                medicationChanges: ["Continue or initiate wart-directed topical therapy"]
            )
        }

        if dictation.contains("basal cell") || dictation.contains("bcc") || knownConditions.contains(where: { $0.contains("basal cell") }) {
            return Profile(
                name: "Basal Cell Carcinoma",
                reviewOfSystems: "Assess bleeding, crusting, itch, tenderness, lesion growth, and new suspicious lesions elsewhere.",
                examTemplate: "Lesion morphology is compatible with non-melanoma skin cancer and warrants definitive treatment planning.",
                plan: "Likely basal cell carcinoma. Recommend tissue confirmation when needed and definitive destruction or excision with margin management based on location and subtype.",
                patientInstructions: "Protect the area from additional trauma or sun exposure and report any rapid change before the procedure date.",
                followUp: "Dermatologic procedure follow-up within 2 to 6 weeks depending on treatment selection.",
                orders: ["Biopsy or excision planning", "Pathology review"],
                medicationChanges: []
            )
        }

        return Profile(
            name: "Dermatologic Evaluation",
            reviewOfSystems: "No additional system concerns are documented beyond the presenting complaint unless specified in dictation.",
            examTemplate: "Focused skin examination demonstrates the clinician-documented findings without evidence of acute systemic compromise.",
            plan: "Complete diagnostic workup and treatment planning using the documented morphology, anatomical distribution, and prior chart history.",
            patientInstructions: "Follow wound care or medication instructions as discussed and return sooner for rapid change, pain, bleeding, or signs of infection.",
            followUp: "Clinical follow-up based on pathology, symptom severity, and treatment response.",
            orders: [],
            medicationChanges: []
        )
    }

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
        if let patient, let medications = patient.medications, !medications.isEmpty {
            return medications.sorted { $0.writtenDate > $1.writtenDate }
        }
        return try modelContext.fetch(FetchDescriptor<LocalMedication>()).sorted { $0.writtenDate > $1.writtenDate }
    }

    static func records(modelContext: ModelContext, patient: PatientProfile?) throws -> [LocalClinicalRecord] {
        if let patient, let records = patient.clinicalRecords, !records.isEmpty {
            return records.sorted { $0.dateRecorded > $1.dateRecorded }
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
        Age/Sex: \(patient.age) / \(patient.gender)
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

    static func format(answer: ClinicalAssistantAnswer) -> String {
        var sections: [String] = [answer.answer]

        if !answer.supportingFacts.isEmpty {
            sections.append("Support:\n- " + answer.supportingFacts.joined(separator: "\n- "))
        }

        if !answer.recommendedActions.isEmpty {
            sections.append("Next actions:\n- " + answer.recommendedActions.joined(separator: "\n- "))
        }

        return sections.joined(separator: "\n\n")
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
