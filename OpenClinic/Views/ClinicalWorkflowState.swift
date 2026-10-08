import Foundation
import Combine
import os

@MainActor
final class ClinicalWorkflowState: ObservableObject {
    @Published var selectedAnatomy: String?
    @Published var generatedNote: ClinicalVisitNote?
    /// Who drafted `generatedNote`: the on-device model, or the app's keyword rules.
    @Published var generatedNoteOrigin: AnswerOrigin?
    @Published var generatedPDFURL: URL?
    @Published var savedRecordID: String?
    @Published var lastSavedDocumentationStatus: DocumentationLifecycleStatus?
    @Published var isProcessing = false

    func reset() {
        AppLogger.workflow.info("🔄 Workflow state reset")
        selectedAnatomy = nil
        generatedNote = nil
        generatedNoteOrigin = nil
        generatedPDFURL = nil
        savedRecordID = nil
        lastSavedDocumentationStatus = nil
        isProcessing = false
    }
}
