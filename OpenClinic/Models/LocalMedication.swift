import SwiftData
import Foundation

@Model
final class LocalMedication {
    @Attribute(.unique) var rxID: String
    var medicationName: String
    var writtenBy: String
    var writtenDate: Date
    var quantityInfo: String
    var refills: Int
    var genericName: String?
    var dose: String?
    var route: String?
    var frequency: String?
    var indication: String?
    var status: String?
    var startDate: Date?
    var lastFilledDate: Date?
    var nextRefillEligibleDate: Date?
    var pharmacyName: String?
    var safetyNotes: [String]?
    var sourceKind: String
    var sourceSystemName: String?
    var sourceRecordIdentifier: String?
    var sourceLastSyncedAt: Date?
    var sourceOfTruth: Bool
    /// True when a later sync no longer returned this row. Kept, and shown as such, instead of deleted.
    var isRemovedAtSource: Bool = false
    var patient: PatientProfile?

    init(
        rxID: String,
        medicationName: String,
        writtenBy: String,
        writtenDate: Date,
        quantityInfo: String,
        refills: Int,
        genericName: String? = nil,
        dose: String? = nil,
        route: String? = nil,
        frequency: String? = nil,
        indication: String? = nil,
        status: String? = nil,
        startDate: Date? = nil,
        lastFilledDate: Date? = nil,
        nextRefillEligibleDate: Date? = nil,
        pharmacyName: String? = nil,
        safetyNotes: [String]? = nil,
        sourceKind: String = ClinicalSourceKind.manualEntry.rawValue,
        sourceSystemName: String? = nil,
        sourceRecordIdentifier: String? = nil,
        sourceLastSyncedAt: Date? = nil,
        sourceOfTruth: Bool = false
    ) {
        self.rxID = rxID
        self.medicationName = medicationName
        self.writtenBy = writtenBy
        self.writtenDate = writtenDate
        self.quantityInfo = quantityInfo
        self.refills = refills
        self.genericName = genericName
        self.dose = dose
        self.route = route
        self.frequency = frequency
        self.indication = indication
        self.status = status
        self.startDate = startDate
        self.lastFilledDate = lastFilledDate
        self.nextRefillEligibleDate = nextRefillEligibleDate
        self.pharmacyName = pharmacyName
        self.safetyNotes = safetyNotes
        self.sourceKind = sourceKind
        self.sourceSystemName = sourceSystemName
        self.sourceRecordIdentifier = sourceRecordIdentifier
        self.sourceLastSyncedAt = sourceLastSyncedAt
        self.sourceOfTruth = sourceOfTruth
    }

    var hasRefillsRemaining: Bool {
        refills > 0
    }
}
