import Foundation
import SwiftData

/// A visit or admission. Mirrors a FHIR Encounter.
@Model
final class ChartEncounter {
    /// Server-qualified resource URL for imported rows, `local/<uuid>` otherwise.
    @Attribute(.unique) var qualifiedID: String
    var typeDisplay: String
    /// v3-ActCode class: AMB, IMP, EMER and so on.
    ///
    /// Not named `classCode`: every NSObject on macOS already answers to that selector
    /// (Cocoa scripting) with a number, and SwiftData then reads a number where this
    /// attribute holds text and stops the process on save.
    var encounterClass: String?
    var reason: String?
    var status: String
    var startDate: Date?
    var endDate: Date?
    var practitioner: String?
    var location: String?
    var serviceProvider: String?
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
        typeDisplay: String,
        encounterClass: String? = nil,
        reason: String? = nil,
        status: String = "finished",
        startDate: Date? = nil,
        endDate: Date? = nil,
        practitioner: String? = nil,
        location: String? = nil,
        serviceProvider: String? = nil,
        isRemovedAtSource: Bool = false,
        sourceKind: String = ClinicalSourceKind.manualEntry.rawValue,
        sourceSystemName: String? = nil,
        sourceRecordIdentifier: String? = nil,
        sourceLastSyncedAt: Date? = nil,
        sourceOfTruth: Bool = false
    ) {
        self.qualifiedID = qualifiedID
        self.typeDisplay = typeDisplay
        self.encounterClass = encounterClass
        self.reason = reason
        self.status = status
        self.startDate = startDate
        self.endDate = endDate
        self.practitioner = practitioner
        self.location = location
        self.serviceProvider = serviceProvider
        self.isRemovedAtSource = isRemovedAtSource
        self.sourceKind = sourceKind
        self.sourceSystemName = sourceSystemName
        self.sourceRecordIdentifier = sourceRecordIdentifier
        self.sourceLastSyncedAt = sourceLastSyncedAt
        self.sourceOfTruth = sourceOfTruth
    }

    /// "Ambulatory", "Inpatient", "Emergency" and so on, for the class code.
    var classDisplay: String? {
        guard let encounterClass else { return nil }
        switch encounterClass.uppercased() {
        case "AMB": return "Ambulatory"
        case "IMP", "ACUTE", "NONAC": return "Inpatient"
        case "EMER": return "Emergency"
        case "HH": return "Home health"
        case "VR": return "Virtual"
        case "OBSENC": return "Observation"
        case "SS": return "Short stay"
        default: return encounterClass
        }
    }
}
