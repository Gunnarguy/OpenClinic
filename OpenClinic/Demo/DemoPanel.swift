//
//  DemoPanel.swift
//  OpenClinic
//
//  Value types that mirror Resources/Demo/DemoPanel.json, the single source of
//  truth for the synthetic demo panel. Dates in the fixture are relative
//  (days ago, days from now, minutes from the demo anchor), so the panel reads
//  the same on any day it is seeded.
//

import Foundation

// MARK: - Panel

nonisolated struct DemoPanel: Codable, Sendable {
    /// Bumped whenever the fixture changes in a way that needs a reseed.
    let version: Int
    let patients: [DemoPatient]
    /// Seed content for the IntraMail inbox.
    let messages: [DemoMessage]
}

// MARK: - Patient

nonisolated struct DemoPatient: Codable, Sendable {
    let mrn: String
    let firstName: String
    let lastName: String
    /// Date only, "yyyy-MM-dd".
    let dateOfBirth: String
    let gender: String
    let isSmoker: Bool
    let primaryClinician: String
    let preferredPharmacy: String?
    let carePlanSummary: String?
    let allergies: [String]
    let riskFlags: [String]
    let emergencyContactName: String?
    let emergencyContactPhone: String?
    let bloodType: String?
    let medications: [DemoMedication]
    let records: [DemoRecord]
    let appointments: [DemoAppointment]
    let photoSeries: [DemoPhotoSeries]
    /// The coded problem list.
    let problems: [DemoProblem]
    /// Vital signs taken at past visits and at visits already roomed today.
    let vitals: [DemoVitalSet]
    let labs: [DemoLabResult]

    var fullName: String { "\(firstName) \(lastName)" }

    /// Year, month and day of `dateOfBirth`, or nil when the string is not a valid "yyyy-MM-dd" date.
    var birthDateComponents: DateComponents? {
        let parts = dateOfBirth.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }
        return DateComponents(year: year, month: month, day: day)
    }
}

// MARK: - Medication

nonisolated struct DemoMedication: Codable, Sendable {
    let rxID: String
    let medicationName: String
    let genericName: String
    let dose: String?
    let route: String
    let frequency: String
    let indication: String
    let status: String
    let writtenBy: String
    let writtenDaysAgo: Int
    /// When the patient started taking it, if that differs from the day it was written.
    let startDaysAgo: Int?
    let quantityInfo: String
    let refills: Int
    let lastFilledDaysAgo: Int?
    let nextRefillInDays: Int?
    let pharmacyName: String
    let safetyNotes: [String]
}

// MARK: - Clinical notes

/// The content of one chart note. Narrative fields may contain the token
/// `{age}`, which the seeder replaces with the patient's age on the note date.
nonisolated struct DemoNote: Codable, Sendable {
    static let ageToken = "{age}"

    let conditionName: String
    let icd10Code: String
    /// A `DocumentationLifecycleStatus` raw value: draft, reviewed or signed.
    let documentationStatus: String
    /// The authoring clinician. It becomes the provider signature once the note is signed.
    let clinician: String
    let visitType: String
    let severity: String
    let ccHPI: String
    let reviewOfSystems: String?
    let examFindings: String
    let impressionsAndPlan: String
    /// Keys of `AnatomicalRegion.regionNames`.
    let zones: [String]
    let patientInstructions: String
    let followUpPlan: String
    let recommendedOrders: [String]
    let carePlanSummary: String

    var isSigned: Bool { documentationStatus == "signed" }

    /// Every free-text field, for checks that run over the whole narrative.
    var narrativeFields: [String] {
        [ccHPI, reviewOfSystems ?? "", examFindings, impressionsAndPlan, patientInstructions, followUpPlan, carePlanSummary]
    }
}

/// A past visit, dated `daysAgo` days before the day the panel is seeded.
nonisolated struct DemoRecord: Codable, Sendable {
    let recordID: String
    let daysAgo: Int
    let note: DemoNote
}

// MARK: - Appointments

/// An appointment is either on today's schedule (`offsetMinutes` from the demo
/// anchor) or in the future (`daysFromNow` at `hour`:`minute`), never both.
nonisolated struct DemoAppointment: Codable, Sendable {
    let appointmentID: String
    let reasonForVisit: String
    let status: String
    let encounterType: String
    let clinicianName: String
    let location: String
    let durationMinutes: Int
    let checkInStatus: String
    let prepInstructions: String
    let linkedDiagnoses: [String]
    let offsetMinutes: Int?
    let daysFromNow: Int?
    let hour: Int?
    let minute: Int?
    /// The note already in the chart for a visit on today's schedule, if any.
    let todayNote: DemoNote?

    var isToday: Bool { offsetMinutes != nil }
}

// MARK: - Problems, vital signs and laboratory results

/// One problem-list entry, coded in ICD-10-CM.
nonisolated struct DemoProblem: Codable, Sendable {
    let problemID: String
    let display: String
    let icd10Code: String
    /// active or resolved.
    let clinicalStatus: String
    /// confirmed or provisional.
    let verificationStatus: String
    let onsetDaysAgo: Int
    let abatementDaysAgo: Int?
}

/// The vital signs taken at one visit. A set belongs either to a past day (`daysAgo`)
/// or to a visit on today's schedule (`appointmentID`), never both.
nonisolated struct DemoVitalSet: Codable, Sendable {
    let vitalsID: String
    let daysAgo: Int?
    let appointmentID: String?
    let systolic: Int?
    let diastolic: Int?
    let heartRate: Int?
    let temperatureF: Double?
    let oxygenSaturation: Int?
    let weightKg: Double?
    let heightCm: Double?
    let painScore: Int?
}

/// One laboratory result: a number with a unit, or a text result such as "Negative".
nonisolated struct DemoLabResult: Codable, Sendable {
    let labID: String
    let daysAgo: Int
    let panel: String
    let display: String
    let loinc: String?
    let value: Double?
    let unit: String?
    let text: String?
    let referenceRange: String?
    /// H, L or N.
    let interpretation: String?
}

// MARK: - Photos

nonisolated enum DemoPhotoStyle: String, Codable, Sendable {
    /// A round lesion with a ring of erythema.
    case papule
    /// A linear surgical scar.
    case scar
}

nonisolated struct DemoColor: Codable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
}

/// One placeholder image in a series. `size` is in points on a 200-point canvas:
/// the radius of a papule or half the length of a scar.
nonisolated struct DemoPhotoFrame: Codable, Sendable {
    let daysAgo: Int
    let notes: String
    let style: DemoPhotoStyle
    let size: Double
    let color: DemoColor
    /// Opacity of the redness around the lesion, 0 to 1.
    let erythema: Double
    let linkedRecordID: String?
}

nonisolated struct DemoPhotoSeries: Codable, Sendable {
    /// File-name stem, unique within a patient.
    let name: String
    /// Key of `AnatomicalRegion.regionNames`.
    let zone: String
    let title: String
    let images: [DemoPhotoFrame]
}

// MARK: - IntraMail

nonisolated struct DemoMessage: Codable, Sendable {
    let sender: String
    let subject: String
    let preview: String
    let hoursAgo: Double
    let isRead: Bool
    /// An `InboxView.MessageCategory` raw value.
    let category: String
}

// MARK: - Validation

nonisolated enum DemoPanelError: Error, LocalizedError, Sendable {
    case fixtureMissing
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .fixtureMissing:
            return "DemoPanel.json is missing from the app bundle."
        case .invalid(let reason):
            return "DemoPanel.json is invalid: \(reason)"
        }
    }
}

extension DemoPanel {
    /// Structural checks that JSON decoding alone cannot express.
    nonisolated func validate() throws {
        for patient in patients {
            guard patient.birthDateComponents != nil else {
                throw DemoPanelError.invalid("\(patient.mrn) has a date of birth that is not yyyy-MM-dd")
            }
            for record in patient.records {
                guard record.daysAgo > 0 else {
                    throw DemoPanelError.invalid("\(record.recordID) must be dated before today")
                }
            }
            for appointment in patient.appointments {
                let futureFields = [appointment.daysFromNow, appointment.hour, appointment.minute].compactMap { $0 }
                let hasValidSlot = appointment.isToday ? futureFields.isEmpty : futureFields.count == 3
                guard hasValidSlot else {
                    throw DemoPanelError.invalid("\(appointment.appointmentID) needs either offsetMinutes or daysFromNow with hour and minute")
                }
                if let daysFromNow = appointment.daysFromNow, daysFromNow <= 0 {
                    throw DemoPanelError.invalid("\(appointment.appointmentID) must be scheduled after today")
                }
                if appointment.todayNote != nil && !appointment.isToday {
                    throw DemoPanelError.invalid("\(appointment.appointmentID) has a note for today but is not on today's schedule")
                }
            }

            let todaysAppointments = Set(patient.appointments.filter(\.isToday).map(\.appointmentID))
            for set in patient.vitals {
                switch (set.daysAgo, set.appointmentID) {
                case (let daysAgo?, nil) where daysAgo > 0:
                    break
                case (nil, let appointmentID?) where todaysAppointments.contains(appointmentID):
                    break
                default:
                    throw DemoPanelError.invalid("\(set.vitalsID) needs either daysAgo or the ID of one of the patient's appointments today")
                }
                guard (set.systolic == nil) == (set.diastolic == nil) else {
                    throw DemoPanelError.invalid("\(set.vitalsID) has half a blood pressure")
                }
            }
            for lab in patient.labs {
                guard (lab.value != nil) != (lab.text != nil) else {
                    throw DemoPanelError.invalid("\(lab.labID) needs either a value or a text result")
                }
            }
            for problem in patient.problems {
                if let abatement = problem.abatementDaysAgo, abatement > problem.onsetDaysAgo {
                    throw DemoPanelError.invalid("\(problem.problemID) resolves before it starts")
                }
            }
        }
    }
}
