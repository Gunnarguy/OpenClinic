import AppIntents
import SwiftData
import Foundation

// MARK: - Patient Entity

@available(iOS 16.0, macOS 13.0, *)
struct PatientEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Patient")
    
    var id: UUID
    var firstName: String
    var lastName: String
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(firstName) \(lastName)",
            subtitle: "Patient Profile"
        )
    }
    
    static var defaultQuery = PatientEntityQuery()
}

@available(iOS 16.0, macOS 13.0, *)
struct PatientEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    func entities(for identifiers: [PatientEntity.ID]) async throws -> [PatientEntity] {
        return loadAllPatients().filter { identifiers.contains($0.id) }
    }
    
    func suggestedEntities() async throws -> [PatientEntity] {
        return loadAllPatients()
    }
    
    func entities(matching string: String) async throws -> [PatientEntity] {
        let all = loadAllPatients()
        return all.filter { "\($0.firstName) \($0.lastName)".localizedCaseInsensitiveContains(string) }
    }
    
    func allEntities() async throws -> [PatientEntity] {
        return loadAllPatients()
    }
    
    private func loadAllPatients() -> [PatientEntity] {
        do {
            let container = AppStore.shared.container
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<PatientProfile>()
            let patients = try context.fetch(descriptor)
            return patients.map { PatientEntity(id: $0.id, firstName: $0.firstName, lastName: $0.lastName) }
        } catch {
            return []
        }
    }
}

// MARK: - Intents

@available(iOS 16.0, *)
struct AskClinicalAssistantIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Clinical Assistant"
    static var description: IntentDescription = .init(
        "Ask a question about your clinical panel or a specific patient",
        categoryName: "Clinical",
        searchKeywords: ["ask", "clinical", "patient", "medical", "rag"]
    )
    
    static var openAppWhenRun: Bool = false
    
    @Parameter(title: "Patient (Optional)", description: "The patient to ask about")
    var patient: PatientEntity?
    
    @Parameter(title: "Question", description: "What would you like to know?")
    var question: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("Ask clinical assistant about \(\.$patient): \(\.$question)")
    }
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let intelService = await MainActor.run { ClinicalIntelligenceService() }
        let ragService = await MainActor.run { ClinicalRAGService.shared }
        
        do {
            let container = AppStore.shared.container
            let context = ModelContext(container)
            
            // Ensure RAG is indexed
            // Cheap when nothing changed: only new or edited chart text is embedded.
            await ragService.syncIndex(modelContext: context)
            
            var patientProfile: PatientProfile? = nil
            if let patientId = patient?.id {
                let descriptor = FetchDescriptor<PatientProfile>(predicate: #Predicate<PatientProfile> { $0.id == patientId })
                patientProfile = try context.fetch(descriptor).first
            }
            
            // A dialog has no badge, so the text itself ends with who wrote it.
            let response: String
            if let p = patientProfile {
                response = AnswerDialog.text(try await intelService.answerPatientQuestion(query: question, modelContext: context, patient: p))
            } else {
                response = AnswerDialog.text(try await intelService.answerPanelQuestion(question, modelContext: context))
            }
            
            return .result(
                dialog: IntentDialog(stringLiteral: response)
            )
        } catch {
            return .result(
                dialog: IntentDialog(stringLiteral: "Failed to query the assistant: \(error.localizedDescription)")
            )
        }
    }
}

@available(iOS 16.0, *)
struct SummarizePatientIntent: AppIntent {
    static var title: LocalizedStringResource = "Summarize Patient"
    static var description: IntentDescription = .init(
        "Get a clinical summary of a patient",
        categoryName: "Clinical"
    )
    
    static var openAppWhenRun: Bool = false
    
    @Parameter(title: "Patient")
    var patient: PatientEntity
    
    static var parameterSummary: some ParameterSummary {
        Summary("Summarize \(\.$patient)")
    }
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let intelService = await MainActor.run { ClinicalIntelligenceService() }
        let ragService = await MainActor.run { ClinicalRAGService.shared }
        
        do {
            let container = AppStore.shared.container
            let context = ModelContext(container)
            
            // Cheap when nothing changed: only new or edited chart text is embedded.
            await ragService.syncIndex(modelContext: context)
            
            let patientId = patient.id
            let descriptor = FetchDescriptor<PatientProfile>(predicate: #Predicate<PatientProfile> { $0.id == patientId })
            
            guard let patientProfile = try context.fetch(descriptor).first else {
                return .result(dialog: IntentDialog(stringLiteral: "Patient not found."))
            }
            
            let response = AnswerDialog.text(try await intelService.answerPatientQuestion(query: "Summarize this patient's medical history, active medications, and upcoming appointments.", modelContext: context, patient: patientProfile))
            
            return .result(
                dialog: IntentDialog(stringLiteral: response)
            )
        } catch {
            return .result(
                dialog: IntentDialog(stringLiteral: "Failed to summarize patient: \(error.localizedDescription)")
            )
        }
    }
}

// MARK: - App Shortcuts Provider

@available(iOS 16.0, *)
struct ClinicalAppShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskClinicalAssistantIntent(),
            phrases: [
                "Ask my clinical assistant in \(.applicationName)",
                "Query patient panel in \(.applicationName)"
            ],
            shortTitle: "Ask Clinical Assistant",
            systemImageName: "brain"
        )
        
        AppShortcut(
            intent: SummarizePatientIntent(),
            phrases: [
                "Summarize \(\.$patient) in \(.applicationName)",
                "Get patient summary for \(\.$patient) in \(.applicationName)"
            ],
            shortTitle: "Summarize Patient",
            systemImageName: "person.text.rectangle"
        )
    }
}
