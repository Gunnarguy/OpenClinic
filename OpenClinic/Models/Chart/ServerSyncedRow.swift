import Foundation
import SwiftData

/// A chart row that came from a server and can be refreshed by a later import.
protocol ServerSyncedRow: AnyObject {
    var qualifiedID: String { get }
    var isRemovedAtSource: Bool { get set }
    var sourceKind: String { get set }
    var sourceSystemName: String? { get set }
    var sourceRecordIdentifier: String? { get set }
    var sourceLastSyncedAt: Date? { get set }
    var sourceOfTruth: Bool { get set }
    var patient: PatientProfile? { get set }
}

extension ChartProblem: ServerSyncedRow {}
extension ChartAllergy: ServerSyncedRow {}
extension ChartObservation: ServerSyncedRow {}
extension ChartEncounter: ServerSyncedRow {}
extension ChartProcedure: ServerSyncedRow {}
extension ChartImmunization: ServerSyncedRow {}
extension ChartDiagnosticReport: ServerSyncedRow {}
extension ChartDocument: ServerSyncedRow {}
extension LocalMedication: ServerSyncedRow {
    var qualifiedID: String { rxID }
}
extension Appointment: ServerSyncedRow {
    var qualifiedID: String { appointmentID }
}

extension ServerSyncedRow {
    /// Where this row came from, in the form the provenance badges read.
    var sourceDescriptor: ClinicalSourceDescriptor {
        ClinicalSourceDescriptor(
            kindRawValue: sourceKind,
            systemName: sourceSystemName,
            authoritative: sourceOfTruth,
            lastSyncedAt: sourceLastSyncedAt,
            recordIdentifier: sourceRecordIdentifier
        )
    }
}
