import Foundation

struct FHIRIdentifier: Decodable {
    let system: String?
    let value: String?
}

struct FHIRHumanName: Decodable {
    let family: String?
    let given: [String]?
}

struct FHIRReference: Decodable {
    let reference: String?
    let display: String?
}

struct FHIRCoding: Decodable {
    let system: String?
    let code: String?
    let display: String?
}

struct FHIRCodeableConcept: Decodable {
    let coding: [FHIRCoding]?
    let text: String?

    var preferredText: String? {
        text ?? coding?.first(where: { $0.display?.isEmpty == false })?.display ?? coding?.first?.code
    }
}

struct FHIRDosage: Decodable {
    let text: String?
    let route: FHIRCodeableConcept?
}

struct FHIRTelecom: Decodable {
    let system: String?
    let value: String?
}

struct FHIRContact: Decodable {
    let name: FHIRHumanName?
    let telecom: [FHIRTelecom]?
}

struct FHIRPatientResource: Decodable {
    let id: String
    let identifier: [FHIRIdentifier]?
    let name: [FHIRHumanName]?
    let gender: String?
    let birthDate: String?
    let contact: [FHIRContact]?
}

struct FHIRAllergyIntoleranceResource: Decodable {
    let id: String
    let code: FHIRCodeableConcept?
}

struct FHIRConditionResource: Decodable {
    let id: String
    let code: FHIRCodeableConcept?
    let clinicalStatus: FHIRCodeableConcept?
    let recordedDate: String?
    let onsetDateTime: String?
}

struct FHIRMedicationRequestResource: Decodable {
    struct DispenseRequest: Decodable {
        let numberOfRepeatsAllowed: Int?
    }

    let id: String
    let medicationCodeableConcept: FHIRCodeableConcept?
    let authoredOn: String?
    let requester: FHIRReference?
    let dosageInstruction: [FHIRDosage]?
    let status: String?
    let encounter: FHIRReference?
    let dispenseRequest: DispenseRequest?
}

struct FHIRAppointmentResource: Decodable {
    struct Participant: Decodable {
        let actor: FHIRReference?
    }

    let id: String
    let description: String?
    let start: String?
    let status: String?
    let participant: [Participant]?
}

enum FHIRResourceAdapters {
    private static let iso8601Formatter = ISO8601DateFormatter()

    static func patient(from resource: FHIRPatientResource) -> PatientProfile {
        let firstName = resource.name?.first?.given?.first ?? "Unknown"
        let lastName = resource.name?.first?.family ?? "Patient"
        let medicalRecordNumber = resource.identifier?.first(where: { $0.value?.isEmpty == false })?.value ?? resource.id
        let birthDate = dateOnly(resource.birthDate) ?? Date(timeIntervalSince1970: 0)

        var emergencyContactName: String? = nil
        var emergencyContactPhone: String? = nil

        if let firstContact = resource.contact?.first {
            let given = firstContact.name?.given?.first ?? ""
            let family = firstContact.name?.family ?? ""
            if !given.isEmpty || !family.isEmpty {
                emergencyContactName = "\(given) \(family)".trimmingCharacters(in: .whitespaces)
            }
            emergencyContactPhone = firstContact.telecom?.first(where: { $0.system?.lowercased() == "phone" })?.value
        }

        return PatientProfile(
            medicalRecordNumber: medicalRecordNumber,
            firstName: firstName,
            lastName: lastName,
            dateOfBirth: birthDate,
            gender: resource.gender?.capitalized ?? "Unknown",
            emergencyContactName: emergencyContactName,
            emergencyContactPhone: emergencyContactPhone,
            sourceKind: ClinicalSourceKind.smartFHIR.rawValue,
            sourceSystemName: "SMART on FHIR",
            sourceRecordIdentifier: resource.id,
            sourceLastSyncedAt: .now,
            sourceOfTruth: true
        )
    }

    static func clinicalRecord(from resource: FHIRConditionResource) -> LocalClinicalRecord {
        let recordedDate = dateTime(resource.recordedDate) ?? dateTime(resource.onsetDateTime) ?? .now
        let status = normalizedStatus(resource.clinicalStatus?.preferredText) ?? "Final"

        return LocalClinicalRecord(
            recordID: resource.id,
            dateRecorded: recordedDate,
            conditionName: resource.code?.preferredText ?? "Condition",
            status: status,
            isHiddenFromPortal: false,
            documentationStatus: status == "Final" ? DocumentationLifecycleStatus.signed.rawValue : DocumentationLifecycleStatus.reviewed.rawValue,
            documentationSignedAt: status == "Final" ? recordedDate : nil,
            sourceKind: ClinicalSourceKind.smartFHIR.rawValue,
            sourceSystemName: "SMART on FHIR",
            sourceRecordIdentifier: resource.id,
            sourceLastSyncedAt: .now,
            sourceOfTruth: true
        )
    }

    static func medication(from resource: FHIRMedicationRequestResource) -> LocalMedication {
        let authoredOn = dateTime(resource.authoredOn) ?? .now
        let dosageText = resource.dosageInstruction?.first?.text ?? "See SIG"

        return LocalMedication(
            rxID: resource.id,
            medicationName: resource.medicationCodeableConcept?.preferredText ?? "Medication",
            writtenBy: resource.requester?.display ?? "Unknown clinician",
            writtenDate: authoredOn,
            quantityInfo: dosageText,
            refills: resource.dispenseRequest?.numberOfRepeatsAllowed ?? 0,
            route: resource.dosageInstruction?.first?.route?.preferredText,
            status: resource.status?.capitalized,
            sourceKind: ClinicalSourceKind.smartFHIR.rawValue,
            sourceSystemName: "SMART on FHIR",
            sourceRecordIdentifier: resource.id,
            sourceLastSyncedAt: .now,
            sourceOfTruth: true
        )
    }

    static func appointment(from resource: FHIRAppointmentResource) -> Appointment {
        let parsedTime = dateTime(resource.start) ?? .now
        
        // Shift the year, month, and day of the appointment to today for the demo workflow
        let calendar = Calendar.current
        let todayComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        let originalComponents = calendar.dateComponents([.hour, .minute, .second], from: parsedTime)
        
        var targetComponents = DateComponents()
        targetComponents.year = todayComponents.year
        targetComponents.month = todayComponents.month
        targetComponents.day = todayComponents.day
        targetComponents.hour = originalComponents.hour
        targetComponents.minute = originalComponents.minute
        targetComponents.second = originalComponents.second
        
        let scheduledTime = calendar.date(from: targetComponents) ?? Date()
        
        let clinicianName = resource.participant?
            .compactMap { $0.actor?.display }
            .first

        return Appointment(
            appointmentID: resource.id,
            scheduledTime: scheduledTime,
            reasonForVisit: resource.description ?? "Appointment",
            status: normalizedAppointmentStatus(resource.status) ?? "Scheduled",
            clinicianName: clinicianName,
            sourceKind: ClinicalSourceKind.smartFHIR.rawValue,
            sourceSystemName: "SMART on FHIR",
            sourceRecordIdentifier: resource.id,
            sourceLastSyncedAt: .now,
            sourceOfTruth: true
        )
    }

    private static func dateOnly(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func dateTime(_ value: String?) -> Date? {
        guard let value else { return nil }
        return iso8601Formatter.date(from: value) ?? dateOnly(value)
    }

    private static func normalizedStatus(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        switch rawValue.lowercased() {
        case "active", "recurrence", "relapse": return "Final"
        case "provisional", "unconfirmed": return "Preliminary"
        default: return rawValue.capitalized
        }
    }

    private static func normalizedAppointmentStatus(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        switch rawValue.lowercased() {
        case "proposed", "pending": return "Pending"
        case "booked": return "Scheduled"
        case "arrived", "checked-in", "checked in": return "Checked In"
        case "fulfilled": return "Completed"
        case "noshow", "no-show": return "No Show"
        case "cancelled", "canceled": return "Cancelled"
        default: return rawValue.capitalized
        }
    }
}
