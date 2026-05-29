import SwiftData
import Foundation

@Model
final class Appointment {
    @Attribute(.unique) var appointmentID: String
    var scheduledTime: Date
    var reasonForVisit: String
    var status: String
    var encounterType: String?
    var clinicianName: String?
    var location: String?
    var durationMinutes: Int?
    var checkInStatus: String?
    var prepInstructions: String?
    var linkedDiagnoses: [String]?
    var sourceKind: String
    var sourceSystemName: String?
    var sourceRecordIdentifier: String?
    var sourceLastSyncedAt: Date?
    var sourceOfTruth: Bool
    var patient: PatientProfile?

    init(
        appointmentID: String,
        scheduledTime: Date,
        reasonForVisit: String,
        status: String,
        encounterType: String? = nil,
        clinicianName: String? = nil,
        location: String? = nil,
        durationMinutes: Int? = nil,
        checkInStatus: String? = nil,
        prepInstructions: String? = nil,
        linkedDiagnoses: [String]? = nil,
        sourceKind: String = ClinicalSourceKind.manualEntry.rawValue,
        sourceSystemName: String? = nil,
        sourceRecordIdentifier: String? = nil,
        sourceLastSyncedAt: Date? = nil,
        sourceOfTruth: Bool = false
    ) {
        self.appointmentID = appointmentID
        self.scheduledTime = scheduledTime
        self.reasonForVisit = reasonForVisit
        self.status = status
        self.encounterType = encounterType
        self.clinicianName = clinicianName
        self.location = location
        self.durationMinutes = durationMinutes
        self.checkInStatus = checkInStatus
        self.prepInstructions = prepInstructions
        self.linkedDiagnoses = linkedDiagnoses
        self.sourceKind = sourceKind
        self.sourceSystemName = sourceSystemName
        self.sourceRecordIdentifier = sourceRecordIdentifier
        self.sourceLastSyncedAt = sourceLastSyncedAt
        self.sourceOfTruth = sourceOfTruth
    }

    var resolvedStatus: String {
        let cal = Calendar.current
        
        // If the status has been manually set to an explicit terminal state, prioritize it
        if !["scheduled", "confirmed", "pending", "booked", "arrived", "checked-in", "checked in"].contains(status.lowercased()) {
            return status
        }
        
        guard let patient = patient else { return status }
        
        // Check if there is a clinical note recorded today
        let todayRecords = (patient.clinicalRecords ?? []).filter { record in
            cal.isDateInToday(record.dateRecorded)
        }
        
        if let latestTodayRecord = todayRecords.sorted(by: { $0.dateRecorded > $1.dateRecorded }).first {
            switch latestTodayRecord.documentationStatus.lowercased() {
            case "signed":
                return "Completed"
            case "reviewed":
                return "Ready for Checkout"
            case "draft":
                return "In Exam"
            default:
                break
            }
        }
        
        // If no note today, but the time is in the past
        let now = Date()
        if cal.isDateInToday(scheduledTime) && scheduledTime < now {
            let diff = now.timeIntervalSince(scheduledTime)
            if diff < 900 {
                return "Checked In"
            } else {
                return "Waiting triage"
            }
        }
        
        return status
    }

    var workflowStatusLabel: String {
        switch resolvedStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "proposed", "pending":
            return "Pending"
        case "booked", "scheduled":
            return "Scheduled"
        case "arrived", "checked-in", "checked in":
            return "Arrived"
        case "fulfilled", "completed":
            return "Completed"
        case "noshow", "no-show":
            return "No Show"
        case "cancelled", "canceled":
            return "Cancelled"
        case "ready for checkout", "readyforcheckout":
            return "Checkout"
        case "in exam", "inexam":
            return "Exam"
        case "waiting triage", "waiting-triage", "waitingtriage":
            return "Triage"
        case "roomed":
            return "Roomed"
        default:
            return resolvedStatus.isEmpty ? "Unknown" : resolvedStatus.capitalized
        }
    }
}
