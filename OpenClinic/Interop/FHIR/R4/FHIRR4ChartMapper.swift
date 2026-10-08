//
//  FHIRR4ChartMapper.swift
//  OpenClinic
//
//  Turns raw FHIR R4 resources into the plain values of ImportedChart. Pure
//  functions, no I/O. The clinical rules live here: a record entered in error
//  never reaches the chart, a Social Security, license or passport number is
//  never copied into the mapped patient, and nothing the server left out is
//  made up. The stored source resource is the server's JSON as sent, which
//  still holds every identifier the server included.
//

import Foundation

nonisolated enum FHIRR4ChartMapper {

    /// Document text is cut here. An attachment can be a whole scanned chart.
    static let longestDocumentText = 200_000

    // MARK: - Chart

    /// Maps one patient's resources. Throws only when the Patient resource itself cannot
    /// be read; any other resource that cannot be read is left out and counted in `warnings`.
    /// Resources of types the chart does not hold are ignored.
    static func chart(
        patient: FHIRR4RawResource,
        resources: [FHIRR4RawResource],
        serverBase: String,
        calendar: Calendar = .current
    ) throws -> ImportedChart {
        var warnings: [String] = []
        var unreadableTypes: [String] = []

        let patientResource: FHIRR4Patient = try decoded(patient, calendar: calendar)
        if hasUnreadableDate(patientResource) {
            warnings.append("The patient record had a date that could not be read; that date was left empty.")
        }
        // A date of birth or death stated to the year or month keeps that precision in the chart,
        // so there is nothing to warn about.
        var chart = ImportedChart(
            patient: self.patient(patientResource, source: source(for: patient, serverBase: serverBase))
        )

        // The same resource can arrive twice, from two pages or two searches. The first copy wins.
        var seen = Set<String>()
        var grouped: [String: [FHIRR4RawResource]] = [:]
        for resource in resources where seen.insert("\(resource.resourceType)/\(resource.id)").inserted {
            grouped[resource.resourceType, default: []].append(resource)
        }

        chart.problems = newestFirst(
            collect(FHIRR4Condition.self, from: grouped, serverBase: serverBase, calendar: calendar,
                    warnings: &warnings, unreadableTypes: &unreadableTypes, map: problem(_:source:)),
            date: { $0.onset ?? $0.recorded }, id: \.source.resourceID
        )
        chart.medications = newestFirst(
            collect(FHIRR4MedicationRequest.self, from: grouped, serverBase: serverBase, calendar: calendar,
                    warnings: &warnings, unreadableTypes: &unreadableTypes, map: medication(_:source:)),
            date: \.authoredOn, id: \.source.resourceID
        )
        chart.allergies = newestFirst(
            collect(FHIRR4AllergyIntolerance.self, from: grouped, serverBase: serverBase, calendar: calendar,
                    warnings: &warnings, unreadableTypes: &unreadableTypes, map: allergy(_:source:)),
            date: \.recorded, id: \.source.resourceID
        )
        chart.observations = newestFirst(
            collect(FHIRR4Observation.self, from: grouped, serverBase: serverBase, calendar: calendar,
                    warnings: &warnings, unreadableTypes: &unreadableTypes, map: observation(_:source:)),
            date: { $0.effective ?? $0.issued }, id: \.source.resourceID
        )
        chart.encounters = newestFirst(
            collect(FHIRR4Encounter.self, from: grouped, serverBase: serverBase, calendar: calendar,
                    warnings: &warnings, unreadableTypes: &unreadableTypes, map: encounter(_:source:)),
            date: \.start, id: \.source.resourceID
        )
        chart.procedures = newestFirst(
            collect(FHIRR4Procedure.self, from: grouped, serverBase: serverBase, calendar: calendar,
                    warnings: &warnings, unreadableTypes: &unreadableTypes, map: procedure(_:source:)),
            date: \.performedStart, id: \.source.resourceID
        )
        chart.immunizations = newestFirst(
            collect(FHIRR4Immunization.self, from: grouped, serverBase: serverBase, calendar: calendar,
                    warnings: &warnings, unreadableTypes: &unreadableTypes, map: immunization(_:source:)),
            date: \.occurrence, id: \.source.resourceID
        )
        chart.reports = newestFirst(
            collect(FHIRR4DiagnosticReport.self, from: grouped, serverBase: serverBase, calendar: calendar,
                    warnings: &warnings, unreadableTypes: &unreadableTypes, map: report(_:source:)),
            date: { $0.effective ?? $0.issued }, id: \.source.resourceID
        )
        chart.documents = newestFirst(
            collect(FHIRR4DocumentReference.self, from: grouped, serverBase: serverBase, calendar: calendar,
                    warnings: &warnings, unreadableTypes: &unreadableTypes, map: document(_:source:)),
            date: \.date, id: \.source.resourceID
        )
        chart.appointments = newestFirst(
            collect(FHIRR4Appointment.self, from: grouped, serverBase: serverBase, calendar: calendar,
                    warnings: &warnings, unreadableTypes: &unreadableTypes, map: appointment(_:source:)),
            date: \.start, id: \.source.resourceID
        )

        chart.warnings = warnings
        chart.unreadableTypes = unreadableTypes
        return chart
    }

    // MARK: - One resource at a time
    //
    // These map a single resource whatever its status. Only `chart` leaves out
    // records entered in error, because only it can count them for the warning.

    static func patient(_ raw: FHIRR4RawResource, serverBase: String, calendar: Calendar = .current) throws -> ImportedPatient {
        patient(try decoded(raw, calendar: calendar), source: source(for: raw, serverBase: serverBase))
    }

    static func problem(_ raw: FHIRR4RawResource, serverBase: String, calendar: Calendar = .current) throws -> ImportedProblem {
        problem(try decoded(raw, calendar: calendar), source: source(for: raw, serverBase: serverBase))
    }

    static func medication(_ raw: FHIRR4RawResource, serverBase: String, calendar: Calendar = .current) throws -> ImportedMedication {
        medication(try decoded(raw, calendar: calendar), source: source(for: raw, serverBase: serverBase))
    }

    static func allergy(_ raw: FHIRR4RawResource, serverBase: String, calendar: Calendar = .current) throws -> ImportedAllergy {
        allergy(try decoded(raw, calendar: calendar), source: source(for: raw, serverBase: serverBase))
    }

    static func observation(_ raw: FHIRR4RawResource, serverBase: String, calendar: Calendar = .current) throws -> ImportedObservation {
        observation(try decoded(raw, calendar: calendar), source: source(for: raw, serverBase: serverBase))
    }

    static func encounter(_ raw: FHIRR4RawResource, serverBase: String, calendar: Calendar = .current) throws -> ImportedEncounter {
        encounter(try decoded(raw, calendar: calendar), source: source(for: raw, serverBase: serverBase))
    }

    static func procedure(_ raw: FHIRR4RawResource, serverBase: String, calendar: Calendar = .current) throws -> ImportedProcedure {
        procedure(try decoded(raw, calendar: calendar), source: source(for: raw, serverBase: serverBase))
    }

    static func immunization(_ raw: FHIRR4RawResource, serverBase: String, calendar: Calendar = .current) throws -> ImportedImmunization {
        immunization(try decoded(raw, calendar: calendar), source: source(for: raw, serverBase: serverBase))
    }

    static func report(_ raw: FHIRR4RawResource, serverBase: String, calendar: Calendar = .current) throws -> ImportedReport {
        report(try decoded(raw, calendar: calendar), source: source(for: raw, serverBase: serverBase))
    }

    static func document(_ raw: FHIRR4RawResource, serverBase: String, calendar: Calendar = .current) throws -> ImportedDocument {
        document(try decoded(raw, calendar: calendar), source: source(for: raw, serverBase: serverBase))
    }

    static func appointment(_ raw: FHIRR4RawResource, serverBase: String, calendar: Calendar = .current) throws -> ImportedAppointment {
        appointment(try decoded(raw, calendar: calendar), source: source(for: raw, serverBase: serverBase))
    }

    /// Where a value came from. The server base is put in its one spelling (lower-case scheme and
    /// host, no default port, no trailing slash) so that `qualifiedID` is the same however the
    /// address was typed.
    static func source(for raw: FHIRR4RawResource, serverBase: String) -> ImportedSource {
        ImportedSource(
            serverBase: FHIRR4Client.normalizedBase(serverBase),
            resourceType: raw.resourceType,
            resourceID: raw.id,
            versionID: raw.versionID,
            lastUpdated: raw.lastUpdated
        )
    }

    // MARK: - Patient

    static func patient(_ patient: FHIRR4Patient, source: ImportedSource) -> ImportedPatient {
        let name = patient.name?.first { $0.use == "official" } ?? patient.name?.first
        var given = (name?.given ?? []).compactMap(FHIRR4Text.nonEmpty).joined(separator: " ")
        let family = FHIRR4Text.nonEmpty(name?.family) ?? ""
        if given.isEmpty, family.isEmpty, let text = FHIRR4Text.nonEmpty(name?.text) {
            // Some servers send only the whole name as one string. It is better kept than lost.
            given = text
        }

        let recordNumber = medicalRecordNumber(in: patient.identifier ?? [])
        let address = patient.address?.first
        let addressLine = (address?.line ?? []).compactMap(FHIRR4Text.nonEmpty).joined(separator: ", ")
        let phone = patient.telecom?.lazy
            .filter { $0.system == "phone" }
            .compactMap { FHIRR4Text.nonEmpty($0.value) }
            .first

        return ImportedPatient(
            source: source,
            mrn: recordNumber?.value ?? source.resourceID,
            mrnSystem: recordNumber?.system,
            givenName: given,
            familyName: family,
            birthDate: patient.birthDate?.date,
            sex: sex(patient.gender),
            deceasedDate: patient.deceasedDateTime?.date,
            phone: phone,
            addressLine: FHIRR4Text.nonEmpty(addressLine),
            city: FHIRR4Text.nonEmpty(address?.city),
            state: FHIRR4Text.nonEmpty(address?.state),
            postalCode: FHIRR4Text.nonEmpty(address?.postalCode),
            language: patient.communication?.first?.language?.bestDisplay,
            maritalStatus: patient.maritalStatus?.bestDisplay,
            // A date of death that cannot be read still says the patient died.
            isDeceased: patient.deceasedBoolean == true || patient.deceasedDateTime != nil,
            birthDatePrecision: partialPrecision(patient.birthDate),
            deceasedPrecision: partialPrecision(patient.deceasedDateTime)
        )
    }

    private static func sex(_ gender: String?) -> String {
        switch gender?.lowercased() {
        case "female": return "Female"
        case "male": return "Male"
        case "other": return "Other"
        default: return "Unknown"
        }
    }

    /// The identifier typed as a medical record number, else the first one that is not a
    /// government number. Government numbers are dropped before anything is chosen, so
    /// one can never be picked, even when a server labels it a record number.
    private static func medicalRecordNumber(in identifiers: [FHIRR4Identifier]) -> (value: String, system: String?)? {
        // A number is a government number wherever it appears: an entry that calls the same value a
        // record number is left out too.
        let governmentValues = Set(identifiers.filter(isGovernmentNumber).compactMap { FHIRR4Text.nonEmpty($0.value) })
        let usable = identifiers.filter { identifier in
            guard let value = FHIRR4Text.nonEmpty(identifier.value) else { return false }
            return !isGovernmentNumber(identifier) && !governmentValues.contains(value)
        }
        guard let chosen = usable.first(where: isMedicalRecordNumber) ?? usable.first,
              let value = FHIRR4Text.nonEmpty(chosen.value) else {
            return nil
        }
        return (value, FHIRR4Text.nonEmpty(chosen.system))
    }

    private static func isMedicalRecordNumber(_ identifier: FHIRR4Identifier) -> Bool {
        // v2-0203 is HL7's identifier type table. Older servers use its pre-R4 address or none.
        let typedMR = identifier.type?.coding?.contains { coding in
            coding.code == "MR" && (coding.system == nil || coding.system?.hasSuffix("0203") == true)
        } ?? false
        return typedMR || identifier.type?.text?.lowercased() == "medical record number"
    }

    private static func isGovernmentNumber(_ identifier: FHIRR4Identifier) -> Bool {
        isGovernmentNumber(
            system: identifier.system,
            typeCodes: (identifier.type?.coding ?? []).compactMap(\.code),
            typeWording: [identifier.type?.text] + (identifier.type?.coding ?? []).map(\.display)
        )
    }

    /// v2-0203 identifier types that are never a record number and never stored: Social Security,
    /// driver's license, passport, Medicare, Medicaid, tax, national individual, social beneficiary
    /// and bank card numbers (terminology.hl7.org CodeSystem v2-0203, version 5.0.0, read 2026-10-07).
    static let governmentNumberTypeCodes: Set<String> = ["SS", "DL", "PPN", "MC", "MA", "TAX", "NI", "SB", "BC"]

    /// A government or financial number, recognized by its system, its v2-0203 type code or the
    /// type's wording.
    static func isGovernmentNumber(system: String?, typeCodes: [String], typeWording: [String?]) -> Bool {
        let system = system?.lowercased() ?? ""
        if system == "http://hl7.org/fhir/sid/us-ssn"
            || system == "http://hl7.org/fhir/sid/us-medicare"
            || system == "http://hl7.org/fhir/sid/us-mbi"
            || system == "urn:oid:2.16.840.1.113883.4.1"
            || system.hasPrefix("urn:oid:2.16.840.1.113883.4.3.")
            || system.contains("passport") {
            return true
        }
        if typeCodes.contains(where: governmentNumberTypeCodes.contains) {
            return true
        }
        let phrases = ["social security", "driver", "passport", "medicare", "medicaid", "tax id", "taxpayer"]
        return typeWording.compactMap { $0?.lowercased() }.contains { wording in
            phrases.contains { wording.contains($0) }
        }
    }

    /// What replaces a government number's value in the stored copy of a Patient resource.
    static let removedIdentifierValue = "[removed before storage]"

    /// The resource as it is stored. A Patient keeps every identifier's system and type, and loses
    /// the value of each government number, wherever the identifier sits in the resource and
    /// wherever else the number is repeated; every other resource is returned as it came.
    static func resourceForStorage(_ raw: FHIRR4RawResource) -> FHIRR4RawResource {
        guard raw.resourceType == "Patient",
              let object = (try? JSONSerialization.jsonObject(with: raw.json)) as? [String: Any] else {
            return raw
        }
        let numbers = governmentNumbers(in: object)
        guard !numbers.isEmpty else { return raw }
        let scrubbed = (replacing(numbers, in: object, key: nil) as? [String: Any]) ?? object
        return (try? FHIRR4RawResource(jsonObject: scrubbed)) ?? raw
    }

    /// The values of the government numbers a Patient resource states, as the server wrote them.
    static func governmentNumberValues(in raw: FHIRR4RawResource) -> Set<String> {
        guard raw.resourceType == "Patient",
              let object = (try? JSONSerialization.jsonObject(with: raw.json)) as? [String: Any] else {
            return []
        }
        return governmentNumbers(in: object)
    }

    /// Walks the whole resource: an identifier can sit in a contained resource or under `link`.
    private static func governmentNumbers(in value: Any) -> Set<String> {
        var found = Set<String>()
        if let object = value as? [String: Any] {
            if let number = object["value"] as? String, number != removedIdentifierValue, isGovernmentIdentifier(object) {
                found.insert(number)
            }
            for member in object.values {
                found.formUnion(governmentNumbers(in: member))
            }
        } else if let list = value as? [Any] {
            for member in list {
                found.formUnion(governmentNumbers(in: member))
            }
        }
        return found
    }

    /// True for a JSON object that is an identifier of a government or financial number.
    private static func isGovernmentIdentifier(_ object: [String: Any]) -> Bool {
        let type = object["type"] as? [String: Any]
        let codings = (type?["coding"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        return isGovernmentNumber(
            system: object["system"] as? String,
            typeCodes: codings.compactMap { $0["code"] as? String },
            typeWording: [type?["text"] as? String] + codings.map { $0["display"] as? String }
        )
    }

    /// The resource with the given numbers taken out: a `value` or `valueString` that is exactly one
    /// of them, and any occurrence in the text of a narrative (`div`). No other field is rewritten,
    /// so an id, a date or a reference that happens to contain the digits stays whole.
    private static func replacing(_ numbers: Set<String>, in value: Any, key: String?) -> Any {
        if let text = value as? String {
            if key == "value" || key == "valueString" {
                return numbers.contains(text) ? removedIdentifierValue : text
            }
            return key == "div" ? removing(numbers, fromNarrative: text) : text
        }
        if let list = value as? [Any] {
            return list.map { replacing(numbers, in: $0, key: key) }
        }
        if let object = value as? [String: Any] {
            var copy: [String: Any] = [:]
            for (name, member) in object {
                copy[name] = replacing(numbers, in: member, key: name)
            }
            return copy
        }
        return value
    }

    /// A narrative with the numbers removed from its text. Markup is left alone (an `xmlns` holds
    /// "1999"), a number is matched only where no letter or digit touches it, and a number shorter
    /// than four characters is left in place because removing it would damage unrelated text.
    private static func removing(_ numbers: Set<String>, fromNarrative div: String) -> String {
        // Longest first, so a number that contains another is removed whole.
        let ordered = numbers.filter { $0.count >= 4 }.sorted { ($0.count, $0) > ($1.count, $1) }
        guard !ordered.isEmpty else { return div }
        let replacement = NSRegularExpression.escapedTemplate(for: removedIdentifierValue)
        func cleaned(_ text: String) -> String {
            var result = text
            for number in ordered where result.contains(number) {
                let pattern = "(?<![A-Za-z0-9])" + NSRegularExpression.escapedPattern(for: number) + "(?![A-Za-z0-9])"
                result = result.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
            }
            return result
        }

        var result = ""
        var text = ""
        var insideTag = false
        for character in div {
            if character == "<" {
                result += cleaned(text)
                text = ""
                insideTag = true
                result.append(character)
            } else if insideTag {
                if character == ">" { insideTag = false }
                result.append(character)
            } else {
                text.append(character)
            }
        }
        return result + cleaned(text)
    }

    // MARK: - Condition

    static func problem(_ condition: FHIRR4Condition, source: ImportedSource) -> ImportedProblem {
        ImportedProblem(
            source: source,
            code: code(condition.code, fallback: "Condition"),
            clinicalStatus: condition.clinicalStatus?.firstCode ?? "unknown",
            verificationStatus: condition.verificationStatus?.firstCode,
            category: firstCode(in: condition.category),
            onset: condition.onsetDateTime?.date,
            abatement: condition.abatementDateTime?.date,
            recorded: condition.recordedDate?.date,
            encounterReference: condition.encounter?.relativeReference,
            onsetPrecision: partialPrecision(condition.onsetDateTime),
            abatementPrecision: partialPrecision(condition.abatementDateTime)
        )
    }

    // MARK: - MedicationRequest

    static func medication(_ request: FHIRR4MedicationRequest, source: ImportedSource) -> ImportedMedication {
        let medication: ImportedCode
        if let concept = request.medicationCodeableConcept, concept.bestDisplay != nil {
            medication = code(concept, fallback: "Medication")
        } else {
            // A reference to a Medication resource: its display name is all there is without another request.
            medication = ImportedCode(system: nil, code: nil, display: display(request.medicationReference) ?? "Medication")
        }
        let dosages = request.dosageInstruction ?? []

        return ImportedMedication(
            source: source,
            code: medication,
            status: FHIRR4Text.nonEmpty(request.status) ?? "unknown",
            intent: FHIRR4Text.nonEmpty(request.intent),
            authoredOn: request.authoredOn?.date,
            // Nil when the server names no one. A bare Practitioner reference is not a name.
            requester: display(request.requester),
            dosageText: dosages.lazy.compactMap { FHIRR4Text.nonEmpty($0.text) }.first,
            route: dosages.lazy.compactMap { $0.route?.bestDisplay }.first,
            refills: request.dispenseRequest?.numberOfRepeatsAllowed,
            reason: request.reasonCode?.first?.bestDisplay ?? display(request.reasonReference?.first),
            encounterReference: request.encounter?.relativeReference
        )
    }

    // MARK: - AllergyIntolerance

    static func allergy(_ allergy: FHIRR4AllergyIntolerance, source: ImportedSource) -> ImportedAllergy {
        var reactions: [String] = []
        for reaction in allergy.reaction ?? [] {
            for manifestation in reaction.manifestation ?? [] {
                if let text = manifestation.bestDisplay, !reactions.contains(text) {
                    reactions.append(text)
                }
            }
        }
        return ImportedAllergy(
            source: source,
            substance: code(allergy.code, fallback: "Allergy"),
            clinicalStatus: allergy.clinicalStatus?.firstCode,
            verificationStatus: allergy.verificationStatus?.firstCode,
            criticality: FHIRR4Text.nonEmpty(allergy.criticality),
            categories: (allergy.category ?? []).compactMap(FHIRR4Text.nonEmpty),
            reactions: reactions,
            recorded: allergy.recordedDate?.date
        )
    }

    // MARK: - Observation

    static func observation(_ observation: FHIRR4Observation, source: ImportedSource) -> ImportedObservation {
        ImportedObservation(
            source: source,
            category: firstCode(in: observation.category) ?? "other",
            code: code(observation.code, fallback: "Observation"),
            effective: observation.effectiveDateTime?.date ?? observation.effectivePeriod?.start?.date,
            issued: observation.issued?.date,
            status: FHIRR4Text.nonEmpty(observation.status) ?? "unknown",
            value: value(of: observation),
            components: (observation.component ?? []).map { component in
                ImportedComponent(code: code(component.code, fallback: "Component"), value: value(of: component))
            },
            interpretation: firstCode(in: observation.interpretation) ?? observation.interpretation?.first?.bestDisplay,
            referenceRange: referenceRangeText(observation.referenceRange?.first),
            encounterReference: observation.encounter?.relativeReference
        )
    }

    /// The value as the chart holds it. A number is kept exactly as sent. A quantity with a
    /// comparator ("<", ">=") becomes text, because "< 5" stored as the number 5 would be wrong.
    static func value(of carrier: some FHIRR4ValueCarrying) -> ImportedValue? {
        if let quantity = carrier.valueQuantity, let number = quantity.value {
            guard let comparator = FHIRR4Text.nonEmpty(quantity.comparator) else {
                return .quantity(number, unit: quantity.bestUnit)
            }
            let unit = quantity.bestUnit.map { " \($0)" } ?? ""
            return .text("\(comparator) \(formatted(number))\(unit)")
        }
        if let text = carrier.valueCodeableConcept?.bestDisplay {
            return .text(text)
        }
        if let text = FHIRR4Text.nonEmpty(carrier.valueString) {
            return .text(text)
        }
        if let flag = carrier.valueBoolean {
            return .boolean(flag)
        }
        if let integer = carrier.valueInteger {
            return .quantity(Double(integer), unit: nil)
        }
        return nil
    }

    /// "3.5 to 5.1 mmol/L" when both ends are numbers, else the range's own text,
    /// else the one end the server gave.
    static func referenceRangeText(_ range: FHIRR4Observation.ReferenceRange?) -> String? {
        guard let range else { return nil }
        let unit = (range.high?.bestUnit ?? range.low?.bestUnit).map { " \($0)" } ?? ""
        if let low = range.low?.value, let high = range.high?.value {
            return "\(formatted(low)) to \(formatted(high))\(unit)"
        }
        if let text = FHIRR4Text.nonEmpty(range.text) {
            return text
        }
        if let low = range.low?.value {
            return "at least \(formatted(low))\(unit)"
        }
        if let high = range.high?.value {
            return "at most \(formatted(high))\(unit)"
        }
        return nil
    }

    /// A number for a sentence: whole numbers without ".0", everything else as Swift prints it.
    private static func formatted(_ number: Double) -> String {
        if number == number.rounded(), abs(number) < 1e15 {
            return String(Int64(number))
        }
        return String(number)
    }

    // MARK: - Encounter

    static func encounter(_ encounter: FHIRR4Encounter, source: ImportedSource) -> ImportedEncounter {
        ImportedEncounter(
            source: source,
            classCode: FHIRR4Text.nonEmpty(encounter.classCoding?.code),
            type: encounter.type?.first?.bestDisplay ?? "Encounter",
            reason: encounter.reasonCode?.first?.bestDisplay,
            status: FHIRR4Text.nonEmpty(encounter.status) ?? "unknown",
            start: encounter.period?.start?.date,
            end: encounter.period?.end?.date,
            practitioner: encounter.participant?.lazy.compactMap { display($0.individual) }.first,
            location: encounter.location?.lazy.compactMap { display($0.location) }.first,
            serviceProvider: display(encounter.serviceProvider)
        )
    }

    // MARK: - Procedure

    static func procedure(_ procedure: FHIRR4Procedure, source: ImportedSource) -> ImportedProcedure {
        ImportedProcedure(
            source: source,
            code: code(procedure.code, fallback: "Procedure"),
            status: FHIRR4Text.nonEmpty(procedure.status) ?? "unknown",
            performedStart: procedure.performedDateTime?.date ?? procedure.performedPeriod?.start?.date,
            performedEnd: procedure.performedPeriod?.end?.date,
            reason: procedure.reasonCode?.first?.bestDisplay ?? display(procedure.reasonReference?.first),
            encounterReference: procedure.encounter?.relativeReference,
            performedPrecision: partialPrecision(procedure.performedDateTime ?? procedure.performedPeriod?.start)
        )
    }

    // MARK: - Immunization

    static func immunization(_ immunization: FHIRR4Immunization, source: ImportedSource) -> ImportedImmunization {
        ImportedImmunization(
            source: source,
            vaccine: code(immunization.vaccineCode, fallback: "Immunization"),
            status: FHIRR4Text.nonEmpty(immunization.status) ?? "unknown",
            occurrence: immunization.occurrenceDateTime?.date,
            primarySource: immunization.primarySource,
            occurrencePrecision: partialPrecision(immunization.occurrenceDateTime)
        )
    }

    // MARK: - DiagnosticReport

    static func report(_ report: FHIRR4DiagnosticReport, source: ImportedSource) -> ImportedReport {
        ImportedReport(
            source: source,
            code: code(report.code, fallback: "Report"),
            category: firstCode(in: report.category),
            status: FHIRR4Text.nonEmpty(report.status) ?? "unknown",
            effective: report.effectiveDateTime?.date ?? report.effectivePeriod?.start?.date,
            issued: report.issued?.date,
            conclusion: FHIRR4Text.nonEmpty(report.conclusion),
            resultReferences: (report.result ?? []).compactMap(\.relativeReference),
            presentedText: report.presentedForm?.lazy.compactMap { text(of: $0) }.first
        )
    }

    // MARK: - DocumentReference

    static func document(_ document: FHIRR4DocumentReference, source: ImportedSource) -> ImportedDocument {
        let attachments = (document.content ?? []).compactMap(\.attachment)
        // Only bytes carried inline can become text here. Following an attachment's URL is a request, and this file makes none.
        let attachment = attachments.first { $0.data != nil } ?? attachments.first

        return ImportedDocument(
            source: source,
            type: document.type?.bestDisplay ?? "Document",
            summary: FHIRR4Text.nonEmpty(document.description),
            date: document.date?.date,
            author: document.author?.lazy.compactMap { display($0) }.first,
            status: FHIRR4Text.nonEmpty(document.status) ?? "unknown",
            contentType: mediaType(attachment?.contentType),
            text: attachment.flatMap { text(of: $0) }
        )
    }

    /// The text of an attachment that carries its bytes inline as plain text or HTML.
    /// Anything else (a PDF, an image, a link to fetch) gives nil.
    static func text(of attachment: FHIRR4Attachment) -> String? {
        guard let encoded = attachment.data,
              let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) else {
            return nil
        }
        let text: String
        switch mediaType(attachment.contentType) {
        case "text/plain":
            text = String(decoding: data, as: UTF8.self)
        case "text/html":
            text = plainText(fromHTML: String(decoding: data, as: UTF8.self))
        default:
            return nil
        }
        return text.isEmpty ? nil : String(text.prefix(longestDocumentText))
    }

    /// The media type alone, in lower case: `text/html; charset=utf-8` gives `text/html`.
    static func mediaType(_ contentType: String?) -> String? {
        guard let first = contentType?.split(separator: ";").first else { return nil }
        return FHIRR4Text.nonEmpty(first.lowercased())
    }

    // MARK: - Appointment

    static func appointment(_ appointment: FHIRR4Appointment, source: ImportedSource) -> ImportedAppointment {
        let practitioner = (appointment.participant ?? []).lazy
            .compactMap(\.actor)
            .filter { $0.resourceType == "Practitioner" }
            .compactMap { display($0) }
            .first

        return ImportedAppointment(
            source: source,
            status: FHIRR4Text.nonEmpty(appointment.status) ?? "unknown",
            start: appointment.start?.date,
            end: appointment.end?.date,
            minutesDuration: appointment.minutesDuration,
            summary: FHIRR4Text.nonEmpty(appointment.description) ?? appointment.serviceType?.first?.bestDisplay,
            reason: appointment.reasonCode?.first?.bestDisplay,
            practitioner: practitioner
        )
    }

    // MARK: - HTML

    /// Tags that sit inside a line of text. Removing one must not split a word
    /// ("H<sub>2</sub>O" is "H2O"); every other tag ends a block and becomes a space.
    private static let inlineTags: Set<String> = [
        "a", "abbr", "b", "bdi", "bdo", "cite", "code", "em", "font", "i", "mark",
        "q", "s", "small", "span", "strong", "sub", "sup", "u",
    ]

    private static let namedEntities: [String: Unicode.Scalar] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
    ]

    /// Reduces an HTML note to one line of plain text: tags go, character references
    /// are decoded, runs of white space become single spaces. Script and style bodies
    /// are dropped with their tags, since they are never part of what a note says.
    static func plainText(fromHTML html: String) -> String {
        let scalars = Array(html.unicodeScalars)
        var output = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "<", let tag = tag(in: scalars, at: index) {
                if tag.isBlock {
                    output.append(" ")
                }
                index = tag.end
            } else if scalar == "&", let reference = characterReference(in: scalars, at: index) {
                output.append(reference.scalar)
                index = reference.end
            } else {
                output.append(scalar)
                index += 1
            }
        }
        return String(output).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Reads the tag or comment that starts at `start`, where the scalar is "<".
    /// Returns nil when what follows is not markup, as in "BP < 120".
    private static func tag(in scalars: [Unicode.Scalar], at start: Int) -> (isBlock: Bool, end: Int)? {
        let count = scalars.count
        guard start + 1 < count else { return nil }
        let next = scalars[start + 1]

        if next == "!", start + 3 < count, scalars[start + 2] == "-", scalars[start + 3] == "-" {
            var index = start + 4
            while index + 2 < count {
                if scalars[index] == "-", scalars[index + 1] == "-", scalars[index + 2] == ">" {
                    return (false, index + 3)
                }
                index += 1
            }
            // A comment that never closes runs to the end, as it does in a browser.
            return (false, count)
        }

        guard next == "/" || next == "!" || next == "?" || isASCIILetter(next),
              let close = scalars[(start + 1)...].firstIndex(of: ">") else {
            return nil
        }

        let isClosing = next == "/"
        let nameStart = isClosing ? start + 2 : start + 1
        var nameEnd = nameStart
        while nameEnd < close, isASCIILetter(scalars[nameEnd]) || isASCIIDigit(scalars[nameEnd]) {
            nameEnd += 1
        }
        let name = String(String.UnicodeScalarView(scalars[nameStart..<nameEnd])).lowercased()

        var end = close + 1
        let isSelfClosing = scalars[close - 1] == "/"
        if !isClosing, !isSelfClosing, name == "script" || name == "style" {
            end = endOfElement(named: name, in: scalars, from: end)
        }
        return (!inlineTags.contains(name), end)
    }

    /// The index just past `</name>`, or the end of the text when the element never closes.
    private static func endOfElement(named name: String, in scalars: [Unicode.Scalar], from start: Int) -> Int {
        let closing = Array(("</" + name).unicodeScalars)
        var index = start
        while index + closing.count <= scalars.count {
            let matches = scalars[index] == "<" && closing.indices.allSatisfy { offset in
                lowercasedASCII(scalars[index + offset]) == closing[offset]
            }
            if matches {
                guard let close = scalars[index...].firstIndex(of: ">") else { return scalars.count }
                return close + 1
            }
            index += 1
        }
        return scalars.count
    }

    /// Decodes the character reference that starts at `start`, where the scalar is "&":
    /// the five XML names, `&nbsp;`, and numeric references. Returns nil for anything
    /// else, which leaves the text as it was ("AT&T").
    private static func characterReference(in scalars: [Unicode.Scalar], at start: Int) -> (scalar: Unicode.Scalar, end: Int)? {
        // The longest reference read here is "&#x10FFFF;", so the ";" is searched for nearby only.
        let limit = min(scalars.count, start + 10)
        guard start + 1 < limit, let semicolon = scalars[(start + 1)..<limit].firstIndex(of: ";") else {
            return nil
        }
        let body = String(String.UnicodeScalarView(scalars[(start + 1)..<semicolon]))
        if let named = namedEntities[body] {
            return (named, semicolon + 1)
        }

        guard body.hasPrefix("#") else { return nil }
        let digits = body.dropFirst()
        let isHex = digits.hasPrefix("x") || digits.hasPrefix("X")
        guard let value = isHex ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits, radix: 10),
              let scalar = Unicode.Scalar(value) else {
            return nil
        }
        // A control character has no place in a note; white space is collapsed later anyway.
        let isControl = value < 0x20 || (0x7F...0x9F).contains(value)
        return (isControl ? " " : scalar, semicolon + 1)
    }

    private static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
    }

    private static func isASCIIDigit(_ scalar: Unicode.Scalar) -> Bool {
        ("0"..."9").contains(scalar)
    }

    private static func lowercasedASCII(_ scalar: Unicode.Scalar) -> Unicode.Scalar {
        guard ("A"..."Z").contains(scalar), let lower = Unicode.Scalar(scalar.value + 32) else { return scalar }
        return lower
    }

    // MARK: - Shared pieces

    /// Counts for one resource type, so that each kind of omission is reported once.
    private nonisolated struct Tally {
        var enteredInError = 0
        var unreadable = 0
        var unreadableDates = 0
        var partialDates = 0

        func warnings(for type: String) -> [String] {
            var lines: [String] = []
            if enteredInError > 0 {
                lines.append("Left out \(Self.counted(enteredInError, type)) marked entered-in-error.")
            }
            if unreadable > 0 {
                lines.append("Left out \(Self.counted(unreadable, type)) that could not be read.")
            }
            if unreadableDates > 0 {
                lines.append("\(Self.counted(unreadableDates, type)) had a date that could not be read; that date was left empty.")
            }
            if partialDates > 0 {
                lines.append("\(Self.counted(partialDates, type)) had a date given only to the year or month; the chart shows the first day of that period.")
            }
            return lines
        }

        private static func counted(_ count: Int, _ type: String) -> String {
            "\(count) \(type) \(count == 1 ? "resource" : "resources")"
        }
    }

    /// Decodes and maps every resource of one type, leaving out the ones entered in
    /// error and the ones that cannot be read. One bad resource never stops the rest.
    private static func collect<Resource: FHIRR4MappedResource, Value>(
        _ type: Resource.Type,
        from grouped: [String: [FHIRR4RawResource]],
        serverBase: String,
        calendar: Calendar,
        warnings: inout [String],
        unreadableTypes: inout [String],
        map: (Resource, ImportedSource) -> Value
    ) -> [Value] {
        var tally = Tally()
        var values: [Value] = []
        for raw in grouped[type.resourceType] ?? [] {
            guard let resource = try? raw.decode(type, calendar: calendar) else {
                tally.unreadable += 1
                continue
            }
            // Patient safety: an allergy or diagnosis entered in error must not show as one.
            guard !resource.isEnteredInError else {
                tally.enteredInError += 1
                continue
            }
            if hasUnreadableDate(resource) {
                tally.unreadableDates += 1
            }
            // Some dates carry their precision to the chart (a problem's onset, a procedure's
            // start). The rest are stored as a full date, so the import says so.
            if resource.datesStoredWhole.contains(where: { partialPrecision($0) != nil }) {
                tally.partialDates += 1
            }
            values.append(map(resource, source(for: raw, serverBase: serverBase)))
        }
        warnings.append(contentsOf: tally.warnings(for: type.resourceType))
        if tally.unreadable > 0 {
            unreadableTypes.append(type.resourceType)
        }
        return values
    }

    /// Decodes a raw resource as the type the caller expects. The type name is checked
    /// first because every field is optional: a Patient would decode as an empty Condition.
    private static func decoded<Resource: FHIRR4MappedResource>(_ raw: FHIRR4RawResource, calendar: Calendar) throws -> Resource {
        guard raw.resourceType == Resource.resourceType else {
            throw DecodingError.typeMismatch(Resource.self, DecodingError.Context(
                codingPath: [],
                debugDescription: "Expected \(Resource.resourceType), found \(raw.resourceType)."
            ))
        }
        return try raw.decode(Resource.self, calendar: calendar)
    }

    private static func hasUnreadableDate(_ resource: some FHIRR4MappedResource) -> Bool {
        resource.dateFields.contains { $0?.isUnreadable == true }
    }

    /// Year or month when the server stated no more than that; nil for a full date or none.
    private static func partialPrecision(_ value: FHIRR4LenientDateTime?) -> ImportedDatePrecision? {
        switch value?.value?.precision {
        case .year: return .year
        case .month: return .month
        default: return nil
        }
    }

    /// Newest first, undated last, ties by resource id, so the same input always gives the same order.
    private static func newestFirst<Value>(_ values: [Value], date: (Value) -> Date?, id: (Value) -> String) -> [Value] {
        values.sorted { left, right in
            switch (date(left), date(right)) {
            case let (leftDate?, rightDate?) where leftDate != rightDate:
                return leftDate > rightDate
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                return id(left) < id(right)
            }
        }
    }

    /// The first coding's system and code, with the best text to show. The fallback is
    /// the generic word for the kind of thing, so a display is never empty.
    static func code(_ concept: FHIRR4CodeableConcept?, fallback: String) -> ImportedCode {
        let first = concept?.coding?.first
        return ImportedCode(
            system: FHIRR4Text.nonEmpty(first?.system),
            code: FHIRR4Text.nonEmpty(first?.code),
            display: concept?.bestDisplay ?? fallback
        )
    }

    private static func firstCode(in concepts: [FHIRR4CodeableConcept]?) -> String? {
        concepts?.lazy.compactMap(\.firstCode).first
    }

    private static func display(_ reference: FHIRR4Reference?) -> String? {
        FHIRR4Text.nonEmpty(reference?.display)
    }
}
