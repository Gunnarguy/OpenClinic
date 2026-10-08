import Foundation
import SwiftData

/// A procedure that was performed. Mirrors a FHIR Procedure.
@Model
final class ChartProcedure {
    /// Server-qualified resource URL for imported rows, `local/<uuid>` otherwise.
    @Attribute(.unique) var qualifiedID: String
    var display: String
    var codeSystem: String?
    var code: String?
    var status: String
    var performedStart: Date?
    var performedEnd: Date?
    /// "year" or "month" when the source stated the date no more exactly than that.
    var performedPrecision: String? = nil
    var reason: String?
    var encounterReference: String?
    /// True when a later sync no longer returned this row. Kept, and shown as such, instead of deleted.
    var isRemovedAtSource: Bool
    var sourceKind: String
    var sourceSystemName: String?
    var sourceRecordIdentifier: String?
    var sourceLastSyncedAt: Date?
    var sourceOfTruth: Bool
    var patient: PatientProfile?

    init(
        qualifiedID: String,
        display: String,
        codeSystem: String? = nil,
        code: String? = nil,
        status: String = "completed",
        performedStart: Date? = nil,
        performedEnd: Date? = nil,
        reason: String? = nil,
        encounterReference: String? = nil,
        isRemovedAtSource: Bool = false,
        sourceKind: String = ClinicalSourceKind.manualEntry.rawValue,
        sourceSystemName: String? = nil,
        sourceRecordIdentifier: String? = nil,
        sourceLastSyncedAt: Date? = nil,
        sourceOfTruth: Bool = false
    ) {
        self.qualifiedID = qualifiedID
        self.display = display
        self.codeSystem = codeSystem
        self.code = code
        self.status = status
        self.performedStart = performedStart
        self.performedEnd = performedEnd
        self.reason = reason
        self.encounterReference = encounterReference
        self.isRemovedAtSource = isRemovedAtSource
        self.sourceKind = sourceKind
        self.sourceSystemName = sourceSystemName
        self.sourceRecordIdentifier = sourceRecordIdentifier
        self.sourceLastSyncedAt = sourceLastSyncedAt
        self.sourceOfTruth = sourceOfTruth
    }
}
