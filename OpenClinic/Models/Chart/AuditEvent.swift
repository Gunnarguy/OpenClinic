import Foundation
import SwiftData

/// One entry in the access log: who did what to which chart, and when.
///
/// The log records that something happened and to which record. It never stores
/// clinical content, so reading the log does not expose the chart.
@Model
final class AuditEvent {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    /// `AuditAction` raw value.
    var action: String
    /// The signed-in clinician, or "system" for automatic work such as a sync.
    var actor: String
    /// The chart the event concerns, when there is one.
    var patientID: UUID?
    /// The kind of record touched, for example "ClinicalNote" or "FHIRImport".
    var entityType: String?
    /// The record's identifier. Never its content.
    var entityID: String?
    /// A short description without clinical content, for example "79 observations, 2 pages".
    var detail: String?

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        action: AuditAction,
        actor: String = "system",
        patientID: UUID? = nil,
        entityType: String? = nil,
        entityID: String? = nil,
        detail: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.action = action.rawValue
        self.actor = actor
        self.patientID = patientID
        self.entityType = entityType
        self.entityID = entityID
        self.detail = detail
    }
}

enum AuditAction: String, CaseIterable, Sendable {
    case chartOpened = "chart.opened"
    case chartQuestionAsked = "chart.question"
    case panelQuestionAsked = "panel.question"
    case noteCreated = "note.created"
    case noteSigned = "note.signed"
    case noteExported = "note.exported"
    case recordImported = "fhir.import"
    case recordImportFailed = "fhir.import.failed"
    case sourceResourceViewed = "fhir.source.viewed"
    case demoDataReset = "demo.reset"
    case appUnlocked = "app.unlocked"
    case appUnlockFailed = "app.unlock.failed"

    var label: String {
        switch self {
        case .chartOpened: return "Chart opened"
        case .chartQuestionAsked: return "Chart question asked"
        case .panelQuestionAsked: return "Panel question asked"
        case .noteCreated: return "Note created"
        case .noteSigned: return "Note signed"
        case .noteExported: return "Note exported"
        case .recordImported: return "Record imported"
        case .recordImportFailed: return "Record import failed"
        case .sourceResourceViewed: return "Source resource viewed"
        case .demoDataReset: return "Demo data reset"
        case .appUnlocked: return "App unlocked"
        case .appUnlockFailed: return "Unlock failed"
        }
    }
}
