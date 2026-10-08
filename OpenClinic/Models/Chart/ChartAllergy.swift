import Foundation
import SwiftData

/// A documented allergy or intolerance. Mirrors a FHIR AllergyIntolerance.
@Model
final class ChartAllergy {
    @Attribute(.unique) var qualifiedID: String
    var substance: String
    var codeSystem: String?
    var code: String?
    /// active, inactive or resolved, when recorded.
    var clinicalStatus: String?
    var verificationStatus: String?
    /// low, high or unable-to-assess, when recorded.
    var criticality: String?
    var categories: [String]
    var reactions: [String]
    var recordedDate: Date?
    var isRemovedAtSource: Bool
    var sourceKind: String
    var sourceSystemName: String?
    var sourceRecordIdentifier: String?
    var sourceLastSyncedAt: Date?
    var sourceOfTruth: Bool
    var patient: PatientProfile?

    init(
        qualifiedID: String,
        substance: String,
        codeSystem: String? = nil,
        code: String? = nil,
        clinicalStatus: String? = "active",
        verificationStatus: String? = nil,
        criticality: String? = nil,
        categories: [String] = [],
        reactions: [String] = [],
        recordedDate: Date? = nil,
        isRemovedAtSource: Bool = false,
        sourceKind: String = ClinicalSourceKind.manualEntry.rawValue,
        sourceSystemName: String? = nil,
        sourceRecordIdentifier: String? = nil,
        sourceLastSyncedAt: Date? = nil,
        sourceOfTruth: Bool = false
    ) {
        self.qualifiedID = qualifiedID
        self.substance = substance
        self.codeSystem = codeSystem
        self.code = code
        self.clinicalStatus = clinicalStatus
        self.verificationStatus = verificationStatus
        self.criticality = criticality
        self.categories = categories
        self.reactions = reactions
        self.recordedDate = recordedDate
        self.isRemovedAtSource = isRemovedAtSource
        self.sourceKind = sourceKind
        self.sourceSystemName = sourceSystemName
        self.sourceRecordIdentifier = sourceRecordIdentifier
        self.sourceLastSyncedAt = sourceLastSyncedAt
        self.sourceOfTruth = sourceOfTruth
    }

    /// SNOMED CT codes that record the absence of an allergy, not an allergy.
    static let noKnownAllergyCodes: Set<String> = ["716186003", "409137002", "429625007", "716184000"]

    /// True for a charted negative such as "No known allergy".
    var isNoKnownAllergyAssertion: Bool {
        if let code, Self.noKnownAllergyCodes.contains(code) { return true }
        return ClinicalLexicon.isNoKnownAllergyEntry(substance)
    }

    /// An allergy that is current and was not refuted or removed.
    var isCurrent: Bool {
        guard !isRemovedAtSource, !isNoKnownAllergyAssertion else { return false }
        if let verificationStatus, ["refuted", "entered-in-error"].contains(verificationStatus.lowercased()) { return false }
        if let clinicalStatus, ["inactive", "resolved"].contains(clinicalStatus.lowercased()) { return false }
        return true
    }
}
