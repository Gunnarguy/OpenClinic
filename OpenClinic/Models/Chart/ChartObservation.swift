import Foundation
import SwiftData

/// A measured or reported fact: a vital sign, a laboratory result, a smoking status.
/// Mirrors a FHIR Observation. A value on screen always comes from one of these rows.
@Model
final class ChartObservation {
    @Attribute(.unique) var qualifiedID: String
    /// vital-signs, laboratory, social-history, survey, exam or other.
    var category: String
    var display: String
    var codeSystem: String?
    var code: String?
    var effectiveDate: Date?
    var issuedDate: Date?
    var status: String
    var valueNumber: Double?
    var valueUnit: String?
    var valueText: String?
    var valueBoolean: Bool?
    /// JSON of `[ImportedComponent]`, for observations with parts such as blood pressure.
    var componentsData: Data?
    /// H, L, N and so on, when the source says.
    var interpretation: String?
    var referenceRange: String?
    var encounterReference: String?
    var isRemovedAtSource: Bool
    var sourceKind: String
    var sourceSystemName: String?
    var sourceRecordIdentifier: String?
    var sourceLastSyncedAt: Date?
    var sourceOfTruth: Bool
    var patient: PatientProfile?

    init(
        qualifiedID: String,
        category: String,
        display: String,
        codeSystem: String? = nil,
        code: String? = nil,
        effectiveDate: Date? = nil,
        issuedDate: Date? = nil,
        status: String = "final",
        valueNumber: Double? = nil,
        valueUnit: String? = nil,
        valueText: String? = nil,
        valueBoolean: Bool? = nil,
        components: [ImportedComponent] = [],
        interpretation: String? = nil,
        referenceRange: String? = nil,
        encounterReference: String? = nil,
        isRemovedAtSource: Bool = false,
        sourceKind: String = ClinicalSourceKind.manualEntry.rawValue,
        sourceSystemName: String? = nil,
        sourceRecordIdentifier: String? = nil,
        sourceLastSyncedAt: Date? = nil,
        sourceOfTruth: Bool = false
    ) {
        self.qualifiedID = qualifiedID
        self.category = category
        self.display = display
        self.codeSystem = codeSystem
        self.code = code
        self.effectiveDate = effectiveDate
        self.issuedDate = issuedDate
        self.status = status
        self.valueNumber = valueNumber
        self.valueUnit = valueUnit
        self.valueText = valueText
        self.valueBoolean = valueBoolean
        self.componentsData = components.isEmpty ? nil : try? JSONEncoder().encode(components)
        self.interpretation = interpretation
        self.referenceRange = referenceRange
        self.encounterReference = encounterReference
        self.isRemovedAtSource = isRemovedAtSource
        self.sourceKind = sourceKind
        self.sourceSystemName = sourceSystemName
        self.sourceRecordIdentifier = sourceRecordIdentifier
        self.sourceLastSyncedAt = sourceLastSyncedAt
        self.sourceOfTruth = sourceOfTruth
    }

    var components: [ImportedComponent] {
        get {
            guard let componentsData else { return [] }
            return (try? JSONDecoder().decode([ImportedComponent].self, from: componentsData)) ?? []
        }
        set {
            componentsData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue)
        }
    }

    func setValue(_ value: ImportedValue?) {
        valueNumber = nil
        valueUnit = nil
        valueText = nil
        valueBoolean = nil
        switch value {
        case .quantity(let number, let unit):
            valueNumber = number
            valueUnit = unit
        case .text(let text):
            valueText = text
        case .boolean(let flag):
            valueBoolean = flag
        case nil:
            break
        }
    }

    /// The value as a clinician reads it: "133/79 mmHg", "86.5 kg", "Never smoker".
    var displayValue: String {
        ObservationFormatting.displayValue(
            code: code,
            number: valueNumber,
            unit: valueUnit,
            text: valueText,
            boolean: valueBoolean,
            components: components
        )
    }
}

/// LOINC codes the chart gives a fixed place to.
nonisolated enum ObservationCode {
    static let bloodPressurePanel = "85354-9"
    static let systolic = "8480-6"
    static let diastolic = "8462-4"
    static let heartRate = "8867-4"
    static let respiratoryRate = "9279-1"
    static let bodyTemperature = "8310-5"
    static let oralTemperature = "8331-1"
    static let oxygenSaturation = "2708-6"
    static let oxygenSaturationPulseOx = "59408-5"
    static let bodyWeight = "29463-7"
    static let bodyHeight = "8302-2"
    static let bodyMassIndex = "39156-5"
    static let painSeverity = "72514-3"
    static let smokingStatus = "72166-2"

    /// SNOMED CT smoking-status codes that mean the patient smokes now.
    static let currentSmokerCodes: Set<String> = [
        "449868002", "428041000124106", "77176002", "428071000124103", "428061000124105", "230059006", "230060001",
    ]
}

/// Turns stored observation values into display text. Pure, so it is shared by the
/// model, the chart documents and the tests.
nonisolated enum ObservationFormatting {
    static func displayValue(
        code: String?,
        number: Double?,
        unit: String?,
        text: String?,
        boolean: Bool?,
        components: [ImportedComponent]
    ) -> String {
        if let pressure = bloodPressure(from: components) {
            return pressure
        }
        if let number {
            // A temperature is read to one decimal place, 98.0 included.
            let isTemperature = code == ObservationCode.bodyTemperature || code == ObservationCode.oralTemperature
            let value = isTemperature ? String(format: "%.1f", number) : format(number)
            return [value, displayUnit(unit)].compactMap { $0 }.joined(separator: " ")
        }
        if let text, !text.isEmpty { return text }
        if let boolean { return boolean ? "Yes" : "No" }
        if !components.isEmpty {
            return components.map { component in
                "\(component.code.display): \(describe(component.value))"
            }.joined(separator: ", ")
        }
        return "No value recorded"
    }

    /// "133/79 mmHg" when the components carry a systolic and a diastolic pressure.
    static func bloodPressure(from components: [ImportedComponent]) -> String? {
        func value(_ loinc: String) -> Double? {
            for component in components where component.code.code == loinc {
                if case .quantity(let number, _) = component.value { return number }
            }
            return nil
        }
        guard let systolic = value(ObservationCode.systolic), let diastolic = value(ObservationCode.diastolic) else { return nil }
        // Blood pressure is read in whole millimeters of mercury, whatever precision the source sent.
        return "\(Int(systolic.rounded()))/\(Int(diastolic.rounded())) mmHg"
    }

    static func describe(_ value: ImportedValue?) -> String {
        switch value {
        case .quantity(let number, let unit):
            return [format(number), displayUnit(unit)].compactMap { $0 }.joined(separator: " ")
        case .text(let text):
            return text
        case .boolean(let flag):
            return flag ? "Yes" : "No"
        case nil:
            return "No value recorded"
        }
    }

    /// Whole numbers print without a decimal; everything else to one place, two under 10.
    static func format(_ number: Double) -> String {
        let magnitude = abs(number)
        if number.rounded() == number, magnitude < 1e9 {
            return String(Int(number))
        }
        let places = magnitude < 10 ? 2 : 1
        var text = String(format: "%.\(places)f", number)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }

    /// The interpretation code as a word: H is "High", L is "Low". Normal results return nil,
    /// so a list shows a flag only where there is something to see.
    static func interpretationLabel(_ code: String?) -> String? {
        guard let code else { return nil }
        switch code.uppercased() {
        case "H": return "High"
        case "HH": return "Critically high"
        case "L": return "Low"
        case "LL": return "Critically low"
        case "A": return "Abnormal"
        case "N": return nil
        default: return code
        }
    }

    /// UCUM writes some units in a form clinicians do not read, such as mm[Hg].
    static func displayUnit(_ unit: String?) -> String? {
        guard let unit, !unit.isEmpty else { return nil }
        switch unit {
        case "mm[Hg]": return "mmHg"
        case "{score}": return nil
        case "[degF]": return "°F"
        case "Cel": return "°C"
        case "/min": return "/min"
        case "10*3/uL": return "×10³/µL"
        case "10*6/uL": return "×10⁶/µL"
        case "kg/m2": return "kg/m²"
        default: return unit
        }
    }
}
