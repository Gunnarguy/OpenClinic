import Foundation
import SwiftData

/// A report that groups results, such as a lipid panel. Mirrors a FHIR DiagnosticReport.
@Model
final class ChartDiagnosticReport {
    /// Server-qualified resource URL for imported rows, `local/<uuid>` otherwise.
    @Attribute(.unique) var qualifiedID: String
    var display: String
    var codeSystem: String?
    var code: String?
    var category: String?
    var status: String
    var effectiveDate: Date?
    var issuedDate: Date?
    var conclusion: String?
    /// Relative references of the result observations, for example `Observation/81b17262`.
    var resultReferences: [String]
    var presentedText: String?
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
        category: String? = nil,
        status: String = "final",
        effectiveDate: Date? = nil,
        issuedDate: Date? = nil,
        conclusion: String? = nil,
        resultReferences: [String] = [],
        presentedText: String? = nil,
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
        self.category = category
        self.status = status
        self.effectiveDate = effectiveDate
        self.issuedDate = issuedDate
        self.conclusion = conclusion
        self.resultReferences = resultReferences
        self.presentedText = presentedText
        self.isRemovedAtSource = isRemovedAtSource
        self.sourceKind = sourceKind
        self.sourceSystemName = sourceSystemName
        self.sourceRecordIdentifier = sourceRecordIdentifier
        self.sourceLastSyncedAt = sourceLastSyncedAt
        self.sourceOfTruth = sourceOfTruth
    }
}
