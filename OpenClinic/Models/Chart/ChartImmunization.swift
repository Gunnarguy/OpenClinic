import Foundation
import SwiftData

/// A vaccine that was given. Mirrors a FHIR Immunization.
@Model
final class ChartImmunization {
    /// Server-qualified resource URL for imported rows, `local/<uuid>` otherwise.
    @Attribute(.unique) var qualifiedID: String
    var vaccine: String
    var codeSystem: String?
    var code: String?
    var status: String
    var occurrenceDate: Date?
    /// True when the record came from the person who gave the vaccine.
    var primarySource: Bool?
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
        vaccine: String,
        codeSystem: String? = nil,
        code: String? = nil,
        status: String = "completed",
        occurrenceDate: Date? = nil,
        primarySource: Bool? = nil,
        isRemovedAtSource: Bool = false,
        sourceKind: String = ClinicalSourceKind.manualEntry.rawValue,
        sourceSystemName: String? = nil,
        sourceRecordIdentifier: String? = nil,
        sourceLastSyncedAt: Date? = nil,
        sourceOfTruth: Bool = false
    ) {
        self.qualifiedID = qualifiedID
        self.vaccine = vaccine
        self.codeSystem = codeSystem
        self.code = code
        self.status = status
        self.occurrenceDate = occurrenceDate
        self.primarySource = primarySource
        self.isRemovedAtSource = isRemovedAtSource
        self.sourceKind = sourceKind
        self.sourceSystemName = sourceSystemName
        self.sourceRecordIdentifier = sourceRecordIdentifier
        self.sourceLastSyncedAt = sourceLastSyncedAt
        self.sourceOfTruth = sourceOfTruth
    }
}
