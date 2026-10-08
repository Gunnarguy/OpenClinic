import Foundation
import XCTest
@testable import OpenClinic

/// The mapper against the sandbox captures. Expected values were read from the JSON, not from the mapper.
final class FHIRR4ChartMapperTests: XCTestCase {

    private let base = FHIRR4Fixture.serverBase

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    /// The Schroeder chart, from every capture that belongs to that patient.
    private func schroederChart() throws -> ImportedChart {
        try FHIRR4ChartMapper.chart(
            patient: FHIRR4Fixture.patient(),
            resources: FHIRR4Fixture.schroederResources(),
            serverBase: base,
            calendar: utc
        )
    }

    /// A chart of the Schroeder patient holding only the given resources.
    private func mappedChart(of resources: [FHIRR4RawResource]) throws -> ImportedChart {
        try FHIRR4ChartMapper.chart(patient: FHIRR4Fixture.patient(), resources: resources, serverBase: base, calendar: utc)
    }

    private func seconds(_ date: Date?) -> TimeInterval? {
        date?.timeIntervalSince1970
    }

    // MARK: - Patient

    func testSchroederPatient() throws {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))

        // A trailing slash on the server address must not reach the source.
        let patient = try FHIRR4ChartMapper.patient(FHIRR4Fixture.patient(), serverBase: base + "/", calendar: eastern)

        XCTAssertEqual(patient.givenName, "Elisha")
        XCTAssertEqual(patient.familyName, "Schroeder")
        XCTAssertEqual(patient.mrn, "f82884e3-7586-4e78-89de-5e682822ed41")
        XCTAssertEqual(patient.mrnSystem, "http://hospital.smarthealthit.org")
        XCTAssertEqual(patient.sex, "Male")
        XCTAssertEqual(patient.deceasedDate, Date(timeIntervalSince1970: 1_579_395_161), "2020-01-19T00:52:41+00:00")
        XCTAssertEqual(patient.phone, "555-193-6568")
        XCTAssertEqual(patient.addressLine, "651 Walsh Camp")
        XCTAssertEqual(patient.city, "Easton")
        XCTAssertEqual(patient.state, "Massachusetts")
        XCTAssertEqual(patient.postalCode, "02334")
        XCTAssertEqual(patient.language, "English")
        XCTAssertEqual(patient.maritalStatus, "M")

        // The date of birth is noon on 1967-01-21 where the clinic is, so it never shows a day off.
        let born = eastern.dateComponents([.year, .month, .day, .hour], from: try XCTUnwrap(patient.birthDate))
        XCTAssertEqual([born.year, born.month, born.day, born.hour], [1967, 1, 21, 12])

        XCTAssertEqual(patient.source.serverBase, "https://r4.smarthealthit.org")
        XCTAssertEqual(patient.source.resourceType, "Patient")
        XCTAssertEqual(patient.source.resourceID, FHIRR4Fixture.schroederID)
        XCTAssertEqual(patient.source.versionID, "4")
        XCTAssertEqual(try XCTUnwrap(seconds(patient.source.lastUpdated)), 1_617_692_492.632, accuracy: 0.0005)
        XCTAssertEqual(patient.source.qualifiedID, "https://r4.smarthealthit.org/Patient/\(FHIRR4Fixture.schroederID)")
    }

    func testNoGovernmentNumberReachesTheMappedPatient() throws {
        let patient = try FHIRR4ChartMapper.patient(FHIRR4Fixture.patient(), serverBase: base, calendar: utc)
        let everything = String(describing: patient)

        // Social Security, driver's license and passport numbers from the capture.
        for number in ["999-29-3401", "S99934593", "X45898258X"] {
            XCTAssertFalse(everything.contains(number), "\(number) was copied into the patient")
        }
        XCTAssertTrue(everything.contains("f82884e3-7586-4e78-89de-5e682822ed41"), "the scan must see the fields it checks")
    }

    func testRecordNumberFallsBackPastGovernmentNumbersAndThenToTheID() throws {
        let withHospitalNumber = try FHIRR4Fixture.resource("""
        {"resourceType":"Patient","id":"p1","identifier":[
          {"system":"http://hl7.org/fhir/sid/us-ssn","value":"999-11-2222"},
          {"type":{"coding":[{"system":"http://terminology.hl7.org/CodeSystem/v2-0203","code":"DL"}]},"system":"urn:oid:2.16.840.1.113883.4.3.25","value":"D1234567"},
          {"type":{"text":"Medical Record Number"},"system":"http://hl7.org/fhir/sid/us-ssn","value":"999-33-4444"},
          {"system":"urn:example:clinic","value":"CLINIC-77"}
        ],"name":[{"text":"Ada Example"}],"gender":"other"}
        """)
        let first = try FHIRR4ChartMapper.patient(withHospitalNumber, serverBase: base, calendar: utc)
        XCTAssertEqual(first.mrn, "CLINIC-77")
        XCTAssertEqual(first.mrnSystem, "urn:example:clinic")
        XCTAssertEqual(first.givenName, "Ada Example", "a name sent only as text is kept")
        XCTAssertEqual(first.familyName, "")
        XCTAssertEqual(first.sex, "Other")
        XCTAssertFalse(String(describing: first).contains("999-"), "an SSN labelled as a record number is still an SSN")

        let onlyGovernmentNumbers = try FHIRR4Fixture.resource("""
        {"resourceType":"Patient","id":"p2","identifier":[
          {"type":{"text":"Social Security Number"},"value":"999-55-6666"},
          {"type":{"coding":[{"code":"PPN"}]},"value":"X0000000X"}
        ],"name":[{"use":"usual","family":"Old","given":["A"]},{"use":"official","family":"New","given":["Bea","Cy"]}]}
        """)
        let second = try FHIRR4ChartMapper.patient(onlyGovernmentNumbers, serverBase: base, calendar: utc)
        XCTAssertEqual(second.mrn, "p2")
        XCTAssertNil(second.mrnSystem)
        XCTAssertEqual(second.givenName, "Bea Cy", "the official name wins over the first one")
        XCTAssertEqual(second.familyName, "New")
        XCTAssertEqual(second.sex, "Unknown")
        XCTAssertNil(second.birthDate)
        let everything = String(describing: second)
        XCTAssertFalse(everything.contains("999-55-6666"))
        XCTAssertFalse(everything.contains("X0000000X"))
    }

    func testAResourceOfTheWrongTypeIsRefused() throws {
        let patient = try FHIRR4Fixture.patient()
        let condition = try XCTUnwrap(FHIRR4Fixture.resources("Condition.schroeder").first)

        // Every field is optional, so without the check a Patient would map to an empty problem.
        XCTAssertThrowsError(try FHIRR4ChartMapper.problem(patient, serverBase: base))
        XCTAssertThrowsError(try FHIRR4ChartMapper.patient(condition, serverBase: base, calendar: utc))
        XCTAssertThrowsError(try FHIRR4ChartMapper.chart(patient: condition, resources: [], serverBase: base))
    }

    // MARK: - Schroeder chart

    func testProblems() throws {
        let problems = try schroederChart().problems

        XCTAssertEqual(problems.count, 5)
        XCTAssertEqual(problems.map(\.code.display), [
            "Stroke",
            "Viral sinusitis (disorder)",
            "Acute viral pharyngitis (disorder)",
            "Body mass index 30+ - obesity (finding)",
            "Streptococcal sore throat (disorder)",
        ])
        XCTAssertEqual(problems.map(\.clinicalStatus), ["active", "resolved", "resolved", "active", "resolved"])
        XCTAssertTrue(problems.allSatisfy { $0.verificationStatus == "confirmed" })
        XCTAssertTrue(problems.allSatisfy { $0.code.system == "http://snomed.info/sct" })
        XCTAssertEqual(problems.filter { $0.abatement != nil }.count, 3)
        // Resolved problems are exactly the ones with an abatement date.
        XCTAssertEqual(problems.map { $0.abatement != nil }, problems.map { $0.clinicalStatus == "resolved" })
        XCTAssertTrue(problems.allSatisfy { $0.category == nil }, "the capture has no Condition.category")

        let stroke = try XCTUnwrap(problems.first)
        XCTAssertEqual(stroke.code.code, "230690007")
        XCTAssertEqual(stroke.onset, Date(timeIntervalSince1970: 1_579_395_161))
        XCTAssertEqual(stroke.recorded, Date(timeIntervalSince1970: 1_579_395_161))
        XCTAssertNil(stroke.abatement)
        XCTAssertEqual(stroke.encounterReference, "Encounter/81a1e9a0-c0fc-40b5-948e-dbe0de859297")
        XCTAssertEqual(stroke.source.reference, "Condition/98a60f67-7888-432f-be02-875f00e418f6")
        XCTAssertEqual(stroke.source.versionID, "4")
    }

    func testMedications() throws {
        let medications = try schroederChart().medications

        XCTAssertEqual(medications.count, 3)
        XCTAssertEqual(medications.map(\.code.code), ["309362", "1804799", "834102"])
        XCTAssertEqual(medications.map(\.code.display), [
            "Clopidogrel 75 MG Oral Tablet",
            "Alteplase 100 MG Injection",
            "Penicillin V Potassium 500 MG Oral Tablet",
        ])
        XCTAssertTrue(medications.allSatisfy { $0.code.system == "http://www.nlm.nih.gov/research/umls/rxnorm" })
        // The requester is a bare Practitioner reference. No name was sent, so none is shown.
        XCTAssertTrue(medications.allSatisfy { $0.requester == nil })
        XCTAssertTrue(medications.allSatisfy { $0.status == "stopped" && $0.intent == "order" })
        XCTAssertTrue(medications.allSatisfy { $0.dosageText == nil && $0.route == nil && $0.refills == nil && $0.reason == nil })
        XCTAssertEqual(medications.first?.authoredOn, Date(timeIntervalSince1970: 1_579_395_161))
        XCTAssertEqual(medications.last?.encounterReference, "Encounter/953db820-6c9f-4685-a914-042c9fa42024")
    }

    func testMedicationByReferenceWithDosage() throws {
        let request = try FHIRR4Fixture.resource("""
        {"resourceType":"MedicationRequest","id":"m1","status":"active","intent":"order",
         "medicationReference":{"reference":"Medication/77","display":"Amoxicillin 500 MG Oral Capsule"},
         "requester":{"reference":"Practitioner/1","display":"Dr. Ada Example"},
         "authoredOn":"2026-09-30",
         "dosageInstruction":[{"text":"One capsule three times daily","route":{"coding":[{"code":"26643006","display":"Oral route"}]}}],
         "dispenseRequest":{"numberOfRepeatsAllowed":2},
         "reasonReference":[{"reference":"Condition/9","display":"Streptococcal sore throat"}],
         "encounter":{"reference":"https://r4.smarthealthit.org/Encounter/e1"}}
        """)
        let medication = try FHIRR4ChartMapper.medication(request, serverBase: base, calendar: utc)

        XCTAssertEqual(medication.code, ImportedCode(system: nil, code: nil, display: "Amoxicillin 500 MG Oral Capsule"))
        XCTAssertEqual(medication.requester, "Dr. Ada Example")
        XCTAssertEqual(medication.dosageText, "One capsule three times daily")
        XCTAssertEqual(medication.route, "Oral route")
        XCTAssertEqual(medication.refills, 2)
        XCTAssertEqual(medication.reason, "Streptococcal sore throat")
        XCTAssertEqual(medication.encounterReference, "Encounter/e1")
        XCTAssertEqual(medication.authoredOn, Date(timeIntervalSince1970: 1_790_769_600), "noon UTC on 2026-09-30")
    }

    func testObservations() throws {
        let observations = try schroederChart().observations

        XCTAssertEqual(observations.count, 79)
        XCTAssertTrue(observations.allSatisfy { $0.status == "final" })
        let byCategory = Dictionary(grouping: observations, by: \.category).mapValues(\.count)
        XCTAssertEqual(byCategory, ["vital-signs": 37, "laboratory": 34, "survey": 7, "exam": 1])
        XCTAssertTrue(observations.allSatisfy { $0.interpretation == nil && $0.referenceRange == nil })

        // Blood pressure: no value of its own, two components.
        let pressures = observations.filter { $0.code.code == "55284-4" }
        XCTAssertEqual(pressures.count, 7)
        let pressure = try XCTUnwrap(pressures.first)
        XCTAssertEqual(pressure.source.resourceID, "f82aebb0-df0a-495a-9915-0cf9a46a2041")
        XCTAssertEqual(pressure.category, "vital-signs")
        XCTAssertNil(pressure.value)
        XCTAssertEqual(pressure.components.count, 2)
        let systolic = try XCTUnwrap(pressure.components.first { $0.code.code == "8480-6" })
        let diastolic = try XCTUnwrap(pressure.components.first { $0.code.code == "8462-4" })
        XCTAssertEqual(systolic.code.display, "Systolic Blood Pressure")
        XCTAssertEqual(diastolic.code.display, "Diastolic Blood Pressure")
        guard case .quantity(let systolicValue, unit: let systolicUnit)? = systolic.value,
              case .quantity(let diastolicValue, unit: let diastolicUnit)? = diastolic.value else {
            return XCTFail("Blood pressure components must be quantities")
        }
        // The numbers are kept as sent, not rounded.
        XCTAssertEqual(systolicValue, 118.13626925019884, accuracy: 1e-9)
        XCTAssertEqual(diastolicValue, 81.46317058696907, accuracy: 1e-9)
        XCTAssertEqual(systolicUnit, "mm[Hg]")
        XCTAssertEqual(diastolicUnit, "mm[Hg]")

        // Smoking status: a coded answer, shown as its text.
        let smoking = observations.filter { $0.code.code == "72166-2" }
        XCTAssertEqual(smoking.count, 7)
        XCTAssertTrue(smoking.allSatisfy { $0.value == .text("Never smoker") && $0.category == "survey" && $0.components.isEmpty })

        // Body weight: a quantity with its unit.
        let weights = observations.filter { $0.code.code == "29463-7" }
        XCTAssertEqual(weights.count, 7)
        let weight = try XCTUnwrap(weights.first)
        guard case .quantity(let kilograms, unit: let unit)? = weight.value else {
            return XCTFail("Body weight must be a quantity")
        }
        XCTAssertEqual(kilograms, 93.6341700531178, accuracy: 1e-9)
        XCTAssertEqual(unit, "kg")
        XCTAssertEqual(weight.code, ImportedCode(system: "http://loinc.org", code: "29463-7", display: "Body Weight"))
        XCTAssertEqual(weight.effective, Date(timeIntervalSince1970: 1_575_161_561), "2019-12-01T00:52:41+00:00")
        XCTAssertEqual(try XCTUnwrap(seconds(weight.issued)), 1_575_161_561.832, accuracy: 0.0005)
        XCTAssertEqual(weight.encounterReference, "Encounter/81a1e9a0-c0fc-40b5-948e-dbe0de859297")

        // Newest first: the cause of death, recorded a week after the stroke.
        let newest = try XCTUnwrap(observations.first)
        XCTAssertEqual(newest.source.resourceID, "3c36fc98-caf2-4a00-9bc7-b3fdb0405eb3")
        XCTAssertEqual(newest.category, "exam")
        XCTAssertEqual(newest.value, .text("Stroke"))
        XCTAssertEqual(observations.last?.source.resourceID, "35cec4fb-1508-4576-8d9f-69a70c580191")
    }

    func testObservationValueChoicesRangeAndInterpretation() throws {
        func observation(_ fields: String) throws -> ImportedObservation {
            let raw = try FHIRR4Fixture.resource(#"{"resourceType":"Observation","id":"o1","status":"final","code":{"text":"Test"},\#(fields)}"#)
            return try FHIRR4ChartMapper.observation(raw, serverBase: base, calendar: utc)
        }

        let coded = try observation(#""valueQuantity":{"value":4.2,"code":"mmol/L"},"interpretation":[{"coding":[{"code":"H","display":"High"}]}],"referenceRange":[{"low":{"value":3.5,"unit":"mmol/L"},"high":{"value":5,"unit":"mmol/L"},"text":"ignored when both ends are numbers"}]"#)
        XCTAssertEqual(coded.value, .quantity(4.2, unit: "mmol/L"), "the coded unit stands in when no unit is written")
        XCTAssertEqual(coded.interpretation, "H")
        XCTAssertEqual(coded.referenceRange, "3.5 to 5 mmol/L")
        XCTAssertEqual(coded.category, "other", "no category means other")

        XCTAssertEqual(try observation(#""valueQuantity":{"value":5,"comparator":"<","unit":"mg/dL"}"#).value, .text("< 5 mg/dL"))
        XCTAssertEqual(try observation(#""valueString":"Trace""#).value, .text("Trace"))
        XCTAssertEqual(try observation(#""valueBoolean":false"#).value, .boolean(false))
        XCTAssertEqual(try observation(#""valueInteger":3"#).value, .quantity(3, unit: nil))
        XCTAssertNil(try observation(#""valueString":"  ""#).value)

        XCTAssertEqual(try observation(#""referenceRange":[{"text":"Negative"}]"#).referenceRange, "Negative")
        XCTAssertEqual(try observation(#""referenceRange":[{"high":{"value":200,"unit":"mg/dL"}}]"#).referenceRange, "at most 200 mg/dL")
        XCTAssertEqual(try observation(#""referenceRange":[{"low":{"value":0.5}}]"#).referenceRange, "at least 0.5")

        let period = try observation(#""effectivePeriod":{"start":"2020-01-19T00:52:41Z","end":"2020-01-19T01:52:41Z"}"#)
        XCTAssertEqual(period.effective, Date(timeIntervalSince1970: 1_579_395_161))
    }

    func testEncounters() throws {
        let encounters = try schroederChart().encounters

        XCTAssertEqual(encounters.count, 11)
        XCTAssertTrue(encounters.allSatisfy { $0.classCode == "AMB" && $0.status == "finished" })
        XCTAssertTrue(encounters.allSatisfy { $0.start != nil && $0.end != nil })
        // Practitioner and organization are bare references in the capture: no names, so none shown.
        XCTAssertTrue(encounters.allSatisfy { $0.practitioner == nil && $0.location == nil && $0.serviceProvider == nil })
        XCTAssertEqual(encounters.compactMap(\.reason).sorted(), [
            "Acute viral pharyngitis (disorder)",
            "Streptococcal sore throat (disorder)",
            "Viral sinusitis (disorder)",
        ])
        XCTAssertEqual(Dictionary(grouping: encounters, by: \.type).mapValues(\.count), [
            "Encounter for check up (procedure)": 7,
            "Encounter for symptom": 3,
            "Death Certification": 1,
        ])

        let newest = try XCTUnwrap(encounters.first)
        XCTAssertEqual(newest.source.resourceID, "50dab420-c17f-4202-a736-089964d0b443")
        XCTAssertEqual(newest.type, "Death Certification")
        XCTAssertEqual(newest.start, Date(timeIntervalSince1970: 1_579_999_961), "2020-01-26T00:52:41+00:00")
        XCTAssertEqual(newest.end, Date(timeIntervalSince1970: 1_580_000_861), "fifteen minutes later")
        XCTAssertEqual(encounters.last?.source.resourceID, "953db820-6c9f-4685-a914-042c9fa42024")
    }

    func testProcedures() throws {
        let procedures = try schroederChart().procedures

        XCTAssertEqual(procedures.count, 6)
        XCTAssertTrue(procedures.allSatisfy { $0.status == "completed" && $0.code.system == "http://snomed.info/sct" })
        XCTAssertTrue(procedures.allSatisfy { $0.performedStart != nil && $0.performedEnd != nil })
        XCTAssertEqual(procedures.compactMap(\.reason), ["Stroke", "Streptococcal sore throat (disorder)"])

        let newest = try XCTUnwrap(procedures.first)
        XCTAssertEqual(newest.source.resourceID, "597519dd-a7bf-4628-97ff-d4e0018072c6")
        XCTAssertEqual(newest.code.code, "433112001")
        XCTAssertEqual(newest.performedStart, Date(timeIntervalSince1970: 1_579_395_161))
        XCTAssertEqual(newest.performedEnd, Date(timeIntervalSince1970: 1_579_396_061))
        XCTAssertEqual(newest.encounterReference, "Encounter/81a1e9a0-c0fc-40b5-948e-dbe0de859297")
    }

    func testImmunizations() throws {
        let immunizations = try schroederChart().immunizations

        XCTAssertEqual(immunizations.count, 11)
        XCTAssertTrue(immunizations.allSatisfy { $0.vaccine.system == "http://hl7.org/fhir/sid/cvx" })
        XCTAssertTrue(immunizations.allSatisfy { $0.status == "completed" && $0.primarySource == true && $0.occurrence != nil })
        XCTAssertEqual(Dictionary(grouping: immunizations, by: { $0.vaccine.code ?? "" }).mapValues(\.count), ["140": 7, "121": 2, "52": 1, "113": 1])

        let newest = try XCTUnwrap(immunizations.first)
        XCTAssertEqual(newest.source.resourceID, "72fea3d5-2a55-4616-9ca3-5785e8a0f56a")
        XCTAssertEqual(newest.vaccine.display, "Influenza, seasonal, injectable, preservative free")
        XCTAssertEqual(newest.occurrence, Date(timeIntervalSince1970: 1_575_161_561))
    }

    func testReports() throws {
        let chart = try schroederChart()
        let reports = chart.reports

        XCTAssertEqual(reports.count, 6)
        XCTAssertTrue(reports.allSatisfy { $0.category == "LAB" && $0.status == "final" && $0.code.system == "http://loinc.org" })
        XCTAssertTrue(reports.allSatisfy { $0.conclusion == nil && $0.presentedText == nil })
        XCTAssertEqual(reports.map(\.resultReferences.count), [1, 4, 11, 4, 4, 11])
        XCTAssertEqual(reports.map(\.code.display), [
            "U.S. standard certificate of death - 2003 revision",
            "Lipid Panel",
            "Complete blood count (hemogram) panel - Blood by Automated count",
            "Lipid Panel",
            "Lipid Panel",
            "Complete blood count (hemogram) panel - Blood by Automated count",
        ])

        let newest = try XCTUnwrap(reports.first)
        XCTAssertEqual(newest.resultReferences, ["Observation/3c36fc98-caf2-4a00-9bc7-b3fdb0405eb3"])
        XCTAssertEqual(newest.effective, Date(timeIntervalSince1970: 1_579_999_961))
        XCTAssertEqual(try XCTUnwrap(seconds(newest.issued)), 1_579_999_961.832, accuracy: 0.0005)

        // Every result points at an observation that is in the same chart.
        let known = Set(chart.observations.map(\.source.reference))
        XCTAssertTrue(reports.allSatisfy { known.isSuperset(of: $0.resultReferences) })
    }

    func testReportWithAPresentedForm() throws {
        let note = Data("Lipids within range.".utf8).base64EncodedString()
        let raw = try FHIRR4Fixture.resource("""
        {"resourceType":"DiagnosticReport","id":"r1","status":"final","code":{"text":"Lipid Panel"},
         "conclusion":"Normal","presentedForm":[
           {"contentType":"application/pdf","data":"JVBERi0="},
           {"contentType":"text/plain; charset=utf-8","data":"\(note)"}]}
        """)
        let report = try FHIRR4ChartMapper.report(raw, serverBase: base, calendar: utc)

        XCTAssertEqual(report.presentedText, "Lipids within range.", "the first form that is text, not the PDF before it")
        XCTAssertEqual(report.conclusion, "Normal")
        XCTAssertNil(report.category)
        XCTAssertTrue(report.resultReferences.isEmpty)
    }

    func testTheTwoSyntheticDocuments() throws {
        let documents = try schroederChart().documents

        XCTAssertEqual(documents.count, 2)
        XCTAssertEqual(documents.map(\.source.resourceID), ["openclinic-test-note-2", "openclinic-test-note-1"], "newest first")
        XCTAssertTrue(documents.allSatisfy { $0.type == "Progress note" && $0.author == "Dr. Test Author" && $0.status == "current" })

        let html = try XCTUnwrap(documents.first)
        XCTAssertEqual(html.contentType, "text/html")
        XCTAssertEqual(html.summary, "Visit summary")
        XCTAssertEqual(html.text, "Visit summary Synthetic text written for OpenClinic tests. Blood pressure 128/82 & pulse 72.")
        XCTAssertEqual(try XCTUnwrap(seconds(html.date)), 1_790_782_200.25, accuracy: 0.0005)

        let plain = try XCTUnwrap(documents.last)
        XCTAssertEqual(plain.contentType, "text/plain")
        XCTAssertEqual(plain.summary, "Dermatology progress note")
        XCTAssertEqual(plain.date, Date(timeIntervalSince1970: 1_790_776_800))
        // Plain text is kept exactly, line breaks included.
        XCTAssertEqual(plain.text, """
        Dermatology progress note. Synthetic text written for OpenClinic tests.
        Subjective: itching of both forearms for two weeks, worse at night.
        Objective: erythematous lichenified plaques on both antecubital fossae.
        Assessment: atopic dermatitis, moderate flare.
        Plan: triamcinolone 0.1% cream twice daily for 14 days, recheck in 4 weeks.
        """)
    }

    func testDocumentAttachmentsThatAreNotInlineText() throws {
        func document(_ attachment: String) throws -> ImportedDocument {
            let raw = try FHIRR4Fixture.resource(#"{"resourceType":"DocumentReference","id":"d1","status":"current","content":[{"attachment":\#(attachment)}]}"#)
            return try FHIRR4ChartMapper.document(raw, serverBase: base, calendar: utc)
        }

        let pdf = try document(#"{"contentType":"application/pdf","data":"JVBERi0="}"#)
        XCTAssertEqual(pdf.contentType, "application/pdf")
        XCTAssertNil(pdf.text)
        XCTAssertEqual(pdf.type, "Document", "the generic word when the server names no type")
        XCTAssertNil(pdf.summary)
        XCTAssertNil(pdf.author)

        // A link is not followed here: the mapper makes no requests.
        let linked = try document(#"{"contentType":"text/plain","url":"https://r4.smarthealthit.org/Binary/1"}"#)
        XCTAssertEqual(linked.contentType, "text/plain")
        XCTAssertNil(linked.text)

        let long = Data(String(repeating: "a", count: FHIRR4ChartMapper.longestDocumentText + 500).utf8).base64EncodedString()
        let capped = try document(#"{"contentType":"TEXT/PLAIN; charset=UTF-8","data":"\#(long)"}"#)
        XCTAssertEqual(capped.contentType, "text/plain")
        XCTAssertEqual(capped.text?.count, 200_000)
    }

    func testHTMLIsReducedToPlainText() {
        let cases: [(html: String, text: String)] = [
            ("<html><body><h1>Visit summary</h1><p>Synthetic text.</p></body></html>", "Visit summary Synthetic text."),
            ("H<sub>2</sub>O and 1.73 m<sup>2</sup>", "H2O and 1.73 m2"),
            ("first<br>second<br/>third", "first second third"),
            ("<p>1 &lt; 2 &amp;&amp; 3 &gt; 2</p>", "1 < 2 && 3 > 2"),
            ("BP < 120 and AT&T", "BP < 120 and AT&T"),
            ("<style>p { color: red }</style><p>Kept</p><SCRIPT>alert('x')</SCRIPT>", "Kept"),
            ("<!-- hidden --><p>Shown</p>", "Shown"),
            ("It&#39;s&nbsp;fine &#x263A; &quot;ok&quot; &apos;yes&apos;", "It's fine \u{263A} \"ok\" 'yes'"),
            ("&amp;lt;", "&lt;"),
            ("  spread\n\n   over\tlines  ", "spread over lines"),
            ("<ul><li>one</li><li>two</li></ul>", "one two"),
            ("", ""),
        ]
        for expected in cases {
            XCTAssertEqual(FHIRR4ChartMapper.plainText(fromHTML: expected.html), expected.text, expected.html)
        }
    }

    // MARK: - Rice captures

    func testAllergiesEnteredInErrorAreLeftOutWithOneWarning() throws {
        let chart = try mappedChart(of: FHIRR4Fixture.resources("AllergyIntolerance.rice"))

        XCTAssertEqual(chart.allergies.map(\.substance.display), ["Peanut", "Shellfish"])
        XCTAssertEqual(chart.allergies.map(\.source.resourceID), ["4889144", "4889143"])
        XCTAssertFalse(chart.allergies.contains { $0.substance.display == "Life" }, "the allergy entered in error must not show")
        XCTAssertFalse(chart.allergies.contains { $0.verificationStatus == "entered-in-error" })
        XCTAssertEqual(chart.warnings, ["Left out 1 AllergyIntolerance resource marked entered-in-error."])

        let peanut = try XCTUnwrap(chart.allergies.first)
        // Typed by hand in the sandbox: text and no coding.
        XCTAssertEqual(peanut.substance, ImportedCode(system: nil, code: nil, display: "Peanut"))
        XCTAssertEqual(peanut.clinicalStatus, "active")
        XCTAssertEqual(peanut.verificationStatus, "unconfirmed")
        XCTAssertEqual(peanut.criticality, "high")
        XCTAssertTrue(peanut.categories.isEmpty)
        XCTAssertTrue(peanut.reactions.isEmpty)
        XCTAssertEqual(try XCTUnwrap(seconds(peanut.recorded)), 1_791_373_939.205, accuracy: 0.0005)
    }

    func testAllergyReactionsAndCategories() throws {
        let raw = try FHIRR4Fixture.resource("""
        {"resourceType":"AllergyIntolerance","id":"a1","category":["medication"],
         "code":{"coding":[{"system":"http://www.nlm.nih.gov/research/umls/rxnorm","code":"7980","display":"Penicillin G"}]},
         "reaction":[{"manifestation":[{"text":"Hives"},{"coding":[{"display":"Wheezing"}]}]},{"manifestation":[{"text":"Hives"}]}]}
        """)
        let allergy = try FHIRR4ChartMapper.allergy(raw, serverBase: base, calendar: utc)

        XCTAssertEqual(allergy.substance, ImportedCode(system: "http://www.nlm.nih.gov/research/umls/rxnorm", code: "7980", display: "Penicillin G"))
        XCTAssertEqual(allergy.categories, ["medication"])
        XCTAssertEqual(allergy.reactions, ["Hives", "Wheezing"])
        XCTAssertNil(allergy.clinicalStatus)
        XCTAssertNil(allergy.recorded)
    }

    func testAppointments() throws {
        let chart = try mappedChart(of: FHIRR4Fixture.resources("Appointment.rice"))
        let appointments = chart.appointments

        XCTAssertEqual(appointments.count, 4)
        // Newest first, and the one whose start could not be read goes last.
        XCTAssertEqual(appointments.map(\.source.resourceID), ["4723149", "3666927", "3666926", "3076955"])
        XCTAssertTrue(appointments.allSatisfy { $0.status == "booked" })
        // Practitioners are bare references here, so no name is shown.
        XCTAssertTrue(appointments.allSatisfy { $0.practitioner == nil })
        XCTAssertEqual(appointments.map(\.summary), [nil, "Colonoscopy Consultation", "Colonoscopy Consultation", "Primary Care Follow-up"])

        let first = try XCTUnwrap(appointments.first)
        XCTAssertEqual(first.start, Date(timeIntervalSince1970: 1_782_710_100), "2026-06-29T05:15:00.000Z")
        XCTAssertEqual(first.end, Date(timeIntervalSince1970: 1_782_711_000))
        XCTAssertEqual(first.minutesDuration, 15)
        XCTAssertNil(first.reason)

        // "2025-09-27T09:00:00" has no time zone. The zone is not guessed: the start is left empty,
        // everything else is kept, and the chart says so.
        let zoneless = try XCTUnwrap(appointments.last)
        XCTAssertNil(zoneless.start)
        XCTAssertEqual(zoneless.end, Date(timeIntervalSince1970: 1_758_929_400), "2025-09-26T23:30:00.000Z")
        XCTAssertEqual(zoneless.reason, "Primary Care Follow-up")
        XCTAssertEqual(zoneless.summary, "Primary Care Follow-up")
        XCTAssertNil(zoneless.minutesDuration)
        XCTAssertEqual(chart.warnings, ["1 Appointment resource had a date that could not be read; that date was left empty."])
    }

    func testAppointmentPractitionerNeedsANameAndThePractitionerType() throws {
        let raw = try FHIRR4Fixture.resource("""
        {"resourceType":"Appointment","id":"ap1","status":"booked","start":"2026-10-08T15:00:00Z",
         "serviceType":[{"coding":[{"display":"General medical practice"}]}],
         "participant":[
           {"actor":{"reference":"Patient/1","display":"Mrs. Babara Rice"}},
           {"actor":{"reference":"Practitioner/2"}},
           {"actor":{"reference":"Location/3","display":"Room 4"}},
           {"actor":{"reference":"https://r4.smarthealthit.org/Practitioner/5","display":"Dr. Ada Example"}}]}
        """)
        let appointment = try FHIRR4ChartMapper.appointment(raw, serverBase: base, calendar: utc)

        XCTAssertEqual(appointment.practitioner, "Dr. Ada Example")
        XCTAssertEqual(appointment.summary, "General medical practice", "the service type stands in for a missing description")
        XCTAssertNil(appointment.reason)
    }

    // MARK: - Leaving things out

    func testEveryKindOfEnteredInErrorIsLeftOutAndCounted() throws {
        let resources = try [
            #"{"resourceType":"Condition","id":"c1","code":{"text":"Wrong patient"},"verificationStatus":{"coding":[{"code":"entered-in-error"}]}}"#,
            #"{"resourceType":"Condition","id":"c2","code":{"text":"Asthma"},"verificationStatus":{"coding":[{"code":"confirmed"}]}}"#,
            #"{"resourceType":"Observation","id":"o1","status":"entered-in-error","code":{"text":"Weight"}}"#,
            #"{"resourceType":"Observation","id":"o2","status":"entered-in-error","code":{"text":"Height"}}"#,
            #"{"resourceType":"MedicationRequest","id":"m1","status":"entered-in-error","medicationCodeableConcept":{"text":"Warfarin"}}"#,
            #"{"resourceType":"Procedure","id":"p1","status":"entered-in-error"}"#,
            #"{"resourceType":"Immunization","id":"i1","status":"entered-in-error"}"#,
            #"{"resourceType":"DiagnosticReport","id":"r1","status":"entered-in-error"}"#,
            #"{"resourceType":"DocumentReference","id":"d1","status":"entered-in-error"}"#,
            #"{"resourceType":"DocumentReference","id":"d2","status":"current","docStatus":"entered-in-error"}"#,
            #"{"resourceType":"Encounter","id":"e1","status":"entered-in-error"}"#,
            #"{"resourceType":"Appointment","id":"a1","status":"entered-in-error"}"#,
        ].map(FHIRR4Fixture.resource)

        let chart = try mappedChart(of: resources)

        XCTAssertEqual(chart.problems.map(\.code.display), ["Asthma"])
        XCTAssertTrue(chart.observations.isEmpty)
        XCTAssertTrue(chart.medications.isEmpty)
        XCTAssertEqual(chart.counts.map(\.count).reduce(0, +), 1, "only the confirmed condition is in the chart")
        XCTAssertEqual(chart.warnings, [
            "Left out 1 Condition resource marked entered-in-error.",
            "Left out 1 MedicationRequest resource marked entered-in-error.",
            "Left out 2 Observation resources marked entered-in-error.",
            "Left out 1 Encounter resource marked entered-in-error.",
            "Left out 1 Procedure resource marked entered-in-error.",
            "Left out 1 Immunization resource marked entered-in-error.",
            "Left out 1 DiagnosticReport resource marked entered-in-error.",
            "Left out 2 DocumentReference resources marked entered-in-error.",
            "Left out 1 Appointment resource marked entered-in-error.",
        ])
    }

    func testAResourceThatCannotBeReadIsCountedAndTheRestStillMap() throws {
        let resources = try [
            #"{"resourceType":"Condition","id":"bad","code":"a string where an object belongs"}"#,
            #"{"resourceType":"Condition","id":"good","code":{"text":"Asthma"}}"#,
            #"{"resourceType":"Condition","id":"sparse"}"#,
            // Types the chart does not hold are ignored without a word.
            #"{"resourceType":"Basic","id":"b1"}"#,
            #"{"resourceType":"Patient","id":"someone-else"}"#,
        ].map(FHIRR4Fixture.resource)

        let chart = try mappedChart(of: resources)

        XCTAssertEqual(chart.problems.map(\.source.resourceID), ["good", "sparse"])
        XCTAssertEqual(chart.warnings, ["Left out 1 Condition resource that could not be read."])
        // The type is named, so an importer does not take the missing row for one removed at the source.
        XCTAssertEqual(chart.unreadableTypes, ["Condition"])

        // A condition with nothing in it still maps, with the generic word and an unknown status.
        let sparse = try XCTUnwrap(chart.problems.last)
        XCTAssertEqual(sparse.code, ImportedCode(system: nil, code: nil, display: "Condition"))
        XCTAssertEqual(sparse.clinicalStatus, "unknown")
        XCTAssertNil(sparse.verificationStatus)
        XCTAssertEqual(chart.patient.source.resourceID, FHIRR4Fixture.schroederID)
    }

    func testTheSchroederChartHasNothingToWarnAbout() throws {
        let chart = try schroederChart()
        XCTAssertTrue(chart.warnings.isEmpty, "\(chart.warnings)")
        XCTAssertTrue(chart.truncatedTypes.isEmpty)
        XCTAssertTrue(chart.failedTypes.isEmpty)
        XCTAssertEqual(chart.counts.map(\.count), [5, 3, 0, 79, 11, 6, 11, 6, 2, 0])
    }

    // MARK: - Order

    func testOrderDoesNotDependOnTheOrderResourcesArriveIn() throws {
        let resources = try FHIRR4Fixture.schroederResources()
            + FHIRR4Fixture.resources("AllergyIntolerance.rice")
            + FHIRR4Fixture.resources("Appointment.rice")
        let forward = try mappedChart(of: resources)
        let backward = try mappedChart(of: resources.reversed())
        // The same resources twice over: the copies must not show up twice.
        let doubled = try mappedChart(of: resources + resources)

        for other in [backward, doubled] {
            XCTAssertEqual(forward.problems, other.problems)
            XCTAssertEqual(forward.medications, other.medications)
            XCTAssertEqual(forward.allergies, other.allergies)
            XCTAssertEqual(forward.observations, other.observations)
            XCTAssertEqual(forward.encounters, other.encounters)
            XCTAssertEqual(forward.procedures, other.procedures)
            XCTAssertEqual(forward.immunizations, other.immunizations)
            XCTAssertEqual(forward.reports, other.reports)
            XCTAssertEqual(forward.documents, other.documents)
            XCTAssertEqual(forward.appointments, other.appointments)
            XCTAssertEqual(forward.warnings, other.warnings)
        }
        XCTAssertEqual(forward.observations.count, 79)
    }

    func testListsAreNewestFirstWithTiesByID() throws {
        let chart = try schroederChart()

        for (earlier, later) in zip(chart.observations, chart.observations.dropFirst()) {
            let first = try XCTUnwrap(earlier.effective)
            let second = try XCTUnwrap(later.effective)
            XCTAssertGreaterThanOrEqual(first, second)
            if first == second {
                XCTAssertLessThan(earlier.source.resourceID, later.source.resourceID)
            }
        }
        XCTAssertEqual(chart.encounters.map { String($0.source.resourceID.prefix(8)) }, [
            "50dab420", "81a1e9a0", "9a45ef9c", "1938e31a", "97c24cc8", "bd501f8d",
            "abddf0f8", "ec14b308", "9abc2707", "694af9c5", "953db820",
        ])
        XCTAssertEqual(chart.immunizations.map { String($0.source.resourceID.prefix(8)) }, [
            "72fea3d5", "1caf97e3", "263ea5af", "92578dac", "1ec5cffa", "23ec4783",
            "7a97bc37", "9dcfc4d3", "3879e2a9", "47e64cac", "9249d5be",
        ])
        XCTAssertEqual(chart.procedures.map { String($0.source.resourceID.prefix(8)) }, [
            "597519dd", "6fd21c8a", "4de0425f", "146c3eef", "97da6a56", "06bed019",
        ])
    }
}
