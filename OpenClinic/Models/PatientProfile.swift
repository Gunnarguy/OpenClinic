import SwiftData
import Foundation

@Model
final class PatientProfile {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var medicalRecordNumber: String
    var firstName: String
    var lastName: String
    var dateOfBirth: Date
    var gender: String
    var isSmoker: Bool
    var primaryClinician: String?
    var preferredPharmacy: String?
    var carePlanSummary: String?
    var allergies: [String]
    var riskFlags: [String]
    var emergencyContactName: String?
    var emergencyContactPhone: String?
    var bloodType: String?
    var sourceKind: String
    var sourceSystemName: String?
    var sourceRecordIdentifier: String?
    var sourceLastSyncedAt: Date?
    var sourceOfTruth: Bool
    var medicalRecordNumberSystem: String?
    var deceasedDate: Date?
    /// True when the source says the patient has died. The date is not always known.
    var isDeceased: Bool = false
    /// "year" or "month" when the source stated the date only that far; nil for a full date. For the
    /// date of birth, "unknown" when the source gave none (`hasKnownBirthDate`).
    var dateOfBirthPrecision: String?
    var deceasedDatePrecision: String?
    var phone: String?
    var addressLine: String?
    var city: String?
    var state: String?
    var postalCode: String?
    var preferredLanguage: String?
    var maritalStatus: String?

    @Relationship(deleteRule: .cascade, inverse: \LocalClinicalRecord.patient) var clinicalRecords: [LocalClinicalRecord]?
    @Relationship(deleteRule: .cascade, inverse: \LocalMedication.patient) var medications: [LocalMedication]?
    @Relationship(deleteRule: .cascade, inverse: \Appointment.patient) var appointments: [Appointment]?
    @Relationship(deleteRule: .cascade, inverse: \ClinicalPhoto.patient) var clinicalPhotos: [ClinicalPhoto]?
    @Relationship(deleteRule: .cascade, inverse: \ChartProblem.patient) var problems: [ChartProblem]?
    @Relationship(deleteRule: .cascade, inverse: \ChartAllergy.patient) var chartAllergies: [ChartAllergy]?
    @Relationship(deleteRule: .cascade, inverse: \ChartObservation.patient) var observations: [ChartObservation]?
    @Relationship(deleteRule: .cascade, inverse: \ChartEncounter.patient) var encounters: [ChartEncounter]?
    @Relationship(deleteRule: .cascade, inverse: \ChartProcedure.patient) var procedures: [ChartProcedure]?
    @Relationship(deleteRule: .cascade, inverse: \ChartImmunization.patient) var immunizations: [ChartImmunization]?
    @Relationship(deleteRule: .cascade, inverse: \ChartDiagnosticReport.patient) var diagnosticReports: [ChartDiagnosticReport]?
    @Relationship(deleteRule: .cascade, inverse: \ChartDocument.patient) var documents: [ChartDocument]?

    init(
        id: UUID = UUID(),
        medicalRecordNumber: String = UUID().uuidString,
        medicalRecordNumberSystem: String? = nil,
        firstName: String,
        lastName: String,
        dateOfBirth: Date,
        gender: String,
        isSmoker: Bool = false,
        primaryClinician: String? = nil,
        preferredPharmacy: String? = nil,
        carePlanSummary: String? = nil,
        allergies: [String] = [],
        riskFlags: [String] = [],
        emergencyContactName: String? = nil,
        emergencyContactPhone: String? = nil,
        bloodType: String? = nil,
        sourceKind: String = ClinicalSourceKind.manualEntry.rawValue,
        sourceSystemName: String? = nil,
        sourceRecordIdentifier: String? = nil,
        sourceLastSyncedAt: Date? = nil,
        sourceOfTruth: Bool = false
    ) {
        self.id = id
        self.medicalRecordNumber = medicalRecordNumber
        self.medicalRecordNumberSystem = medicalRecordNumberSystem
        self.firstName = firstName
        self.lastName = lastName
        self.dateOfBirth = dateOfBirth
        self.gender = gender
        self.isSmoker = isSmoker
        self.primaryClinician = primaryClinician
        self.preferredPharmacy = preferredPharmacy
        self.carePlanSummary = carePlanSummary
        self.allergies = allergies
        self.riskFlags = riskFlags
        self.emergencyContactName = emergencyContactName
        self.emergencyContactPhone = emergencyContactPhone
        self.bloodType = bloodType
        self.sourceKind = sourceKind
        self.sourceSystemName = sourceSystemName
        self.sourceRecordIdentifier = sourceRecordIdentifier
        self.sourceLastSyncedAt = sourceLastSyncedAt
        self.sourceOfTruth = sourceOfTruth
        self.clinicalRecords = []
        self.medications = []
        self.appointments = []
        self.clinicalPhotos = []
        self.problems = []
        self.chartAllergies = []
        self.observations = []
        self.encounters = []
        self.procedures = []
        self.immunizations = []
        self.diagnosticReports = []
        self.documents = []
    }

    var fullName: String {
        "\(firstName) \(lastName)"
    }

    /// Age in whole years. Compared by calendar day, so a birthday counts from
    /// midnight whatever time of day the date of birth was stored with.
    var age: Int {
        age(on: .now)
    }

    /// True when the source says the patient has died, by a flag or by a date of death.
    var hasDied: Bool {
        isDeceased || deceasedDate != nil
    }

    /// False when the source gave no date of birth. `dateOfBirth` then holds a placeholder that no
    /// screen shows and no age is computed from.
    var hasKnownBirthDate: Bool {
        dateOfBirthPrecision != ChartDateText.unknown
    }

    /// The age as text: "33", "about 33" when the source gave only the year of birth, or "not recorded".
    var ageText: String {
        guard hasKnownBirthDate else { return "not recorded" }
        return dateOfBirthPrecision == "year" ? "about \(age)" : "\(age)"
    }

    /// "33y" for a living patient; "died at 96" or "deceased" for one who has died.
    var shortAgeText: String {
        guard hasKnownBirthDate else { return hasDied ? "deceased" : "age not recorded" }
        guard hasDied else { return "\(ageText)y" }
        return deceasedDate == nil ? "deceased" : "died at \(ageText)"
    }

    /// Age in whole years on `date`. A patient with a recorded date of death stops ageing on it.
    func age(on date: Date, calendar: Calendar = .current) -> Int {
        let birthDay = calendar.startOfDay(for: dateOfBirth)
        let day = calendar.startOfDay(for: min(date, deceasedDate ?? date))
        return max(calendar.dateComponents([.year], from: birthDay, to: day).year ?? 0, 0)
    }
}
