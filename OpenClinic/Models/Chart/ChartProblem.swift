import Foundation
import SwiftData

/// One entry on the problem list: a diagnosis with its coding and clinical status.
/// Mirrors a FHIR Condition. Encounter notes live in `LocalClinicalRecord`.
@Model
final class ChartProblem {
    /// Server-qualified resource URL for imported problems, `local/<uuid>` otherwise.
    @Attribute(.unique) var qualifiedID: String
    var display: String
    var codeSystem: String?
    var code: String?
    /// FHIR condition-clinical code: active, recurrence, relapse, inactive, remission, resolved or unknown.
    var clinicalStatus: String
    var verificationStatus: String?
    var category: String?
    var onsetDate: Date?
    var abatementDate: Date?
    var recordedDate: Date?
    var encounterReference: String?
    /// True when a later sync no longer returned this problem. Kept, and shown as such, instead of deleted.
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
        clinicalStatus: String = "active",
        verificationStatus: String? = nil,
        category: String? = nil,
        onsetDate: Date? = nil,
        abatementDate: Date? = nil,
        recordedDate: Date? = nil,
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
        self.clinicalStatus = clinicalStatus
        self.verificationStatus = verificationStatus
        self.category = category
        self.onsetDate = onsetDate
        self.abatementDate = abatementDate
        self.recordedDate = recordedDate
        self.encounterReference = encounterReference
        self.isRemovedAtSource = isRemovedAtSource
        self.sourceKind = sourceKind
        self.sourceSystemName = sourceSystemName
        self.sourceRecordIdentifier = sourceRecordIdentifier
        self.sourceLastSyncedAt = sourceLastSyncedAt
        self.sourceOfTruth = sourceOfTruth
    }

    /// Active, recurring or relapsed: the problems a clinician is managing now.
    var isActive: Bool {
        ["active", "recurrence", "relapse"].contains(clinicalStatus.lowercased())
    }

    /// The ICD-10-CM code when the problem is coded in that system.
    var icd10Code: String? {
        guard let codeSystem, codeSystem.lowercased().contains("icd-10") else { return nil }
        return code
    }

    /// The date the problem list sorts by: onset, else when it was recorded.
    var sortDate: Date? { onsetDate ?? recordedDate }
}

/// Code system URIs the chart writes for locally authored entries.
enum ChartCodeSystem {
    static let icd10CM = "http://hl7.org/fhir/sid/icd-10-cm"
    static let snomed = "http://snomed.info/sct"
    static let loinc = "http://loinc.org"
    static let rxNorm = "http://www.nlm.nih.gov/research/umls/rxnorm"
    static let cvx = "http://hl7.org/fhir/sid/cvx"
}
