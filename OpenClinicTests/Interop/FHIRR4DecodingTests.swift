import Foundation
import XCTest
@testable import OpenClinic

/// Every sandbox capture must decode, first into raw resources and then into the typed ones.
final class FHIRR4DecodingTests: XCTestCase {

    // MARK: - Bundles

    func testEveryBundleHoldsTheResourcesThatWereCaptured() throws {
        let expected: [(fixture: String, type: String, count: Int)] = FHIRR4Fixture.schroederSinglePages + [
            ("Observation.schroeder.page1", "Observation", 50),
            ("Observation.schroeder.page2", "Observation", 29),
            ("AllergyIntolerance.rice", "AllergyIntolerance", 3),
            ("Appointment.rice", "Appointment", 4),
            ("DocumentReference.synthetic", "DocumentReference", 2),
            ("AllergyIntolerance.empty", "AllergyIntolerance", 0),
        ]
        for page in expected {
            let bundle = try FHIRR4Fixture.bundle(page.fixture)
            XCTAssertEqual(bundle.resources.count, page.count, page.fixture)
            XCTAssertTrue(bundle.resources.allSatisfy { $0.resourceType == page.type }, page.fixture)
            XCTAssertEqual(Set(bundle.resources.map(\.id)).count, page.count, "\(page.fixture) has repeated ids")
        }
    }

    func testBundleTotalsAndPagingLinks() throws {
        let first = try FHIRR4Fixture.bundle("Observation.schroeder.page1")
        XCTAssertEqual(first.total, 79)
        XCTAssertEqual(
            first.nextLink?.absoluteString,
            "https://r4.smarthealthit.org?_getpages=0739cbe6-fc7c-4857-82ee-91099c01e302&_getpagesoffset=50&_count=50&_pretty=true&_bundletype=searchset"
        )

        let second = try FHIRR4Fixture.bundle("Observation.schroeder.page2")
        XCTAssertEqual(second.total, 79)
        XCTAssertNil(second.nextLink, "the last page has a previous link and no next link")

        let empty = try FHIRR4Fixture.bundle("AllergyIntolerance.empty")
        XCTAssertEqual(empty.total, 0)
        XCTAssertNil(empty.nextLink)
        XCTAssertTrue(empty.resources.isEmpty)

        XCTAssertEqual(try FHIRR4Fixture.bundle("Condition.schroeder").total, 5)
    }

    func testBundleSkipsEntriesThatAreNotChartData() throws {
        let json = """
        {
          "resourceType": "Bundle",
          "type": "searchset",
          "entry": [
            { "fullUrl": "https://example.org/nothing", "search": { "mode": "match" } },
            { "resource": { "resourceType": "Condition" } },
            { "resource": { "id": "no-type" } },
            { "resource": { "resourceType": "OperationOutcome", "id": "warning", "issue": [] }, "search": { "mode": "outcome" } },
            "not an object",
            { "resource": { "resourceType": "Condition", "id": "kept" } }
          ]
        }
        """
        let bundle = try FHIRR4Bundle(data: Data(json.utf8))
        XCTAssertEqual(bundle.resources.map(\.id), ["kept"])
        XCTAssertNil(bundle.total)
        XCTAssertNil(bundle.nextLink)
    }

    func testABodyThatIsNotABundleIsAnInvalidResponse() throws {
        let outcome = try FHIRR4Fixture.data("OperationOutcome.404")
        XCTAssertThrowsError(try FHIRR4Bundle(data: outcome)) { error in
            XCTAssertEqual(error as? FHIRR4Error, .invalidResponse)
        }
        XCTAssertThrowsError(try FHIRR4Bundle(data: Data("<html>".utf8))) { error in
            XCTAssertEqual(error as? FHIRR4Error, .invalidResponse)
        }
    }

    // MARK: - Raw resources

    func testRawResourceKeepsIdentityVersionAndJSON() throws {
        let patient = try FHIRR4Fixture.patient()
        XCTAssertEqual(patient.resourceType, "Patient")
        XCTAssertEqual(patient.id, FHIRR4Fixture.schroederID)
        XCTAssertEqual(patient.versionID, "4")
        // 2021-04-06T03:01:32.632-04:00
        XCTAssertEqual(try XCTUnwrap(patient.lastUpdated).timeIntervalSince1970, 1_617_692_492.632, accuracy: 0.0005)

        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: patient.json) as? [String: Any])
        XCTAssertEqual(object["birthDate"] as? String, "1967-01-21")
        XCTAssertEqual((object["identifier"] as? [Any])?.count, 5)
    }

    func testEqualResourcesHaveEqualBytesWhateverTheKeyOrder() throws {
        let one = try FHIRR4Fixture.resource(#"{"resourceType":"Condition","id":"a","meta":{"versionId":"2","lastUpdated":"2021-04-06T03:10:58.874-04:00"},"code":{"text":"Stroke"}}"#)
        let two = try FHIRR4Fixture.resource(#"{ "code": { "text": "Stroke" }, "meta": { "lastUpdated": "2021-04-06T03:10:58.874-04:00", "versionId": "2" }, "id": "a", "resourceType": "Condition" }"#)
        let other = try FHIRR4Fixture.resource(#"{"resourceType":"Condition","id":"a","meta":{"versionId":"3"},"code":{"text":"Stroke"}}"#)

        XCTAssertEqual(one.json, two.json)
        XCTAssertEqual(one, two)
        XCTAssertNotEqual(one, other)
        XCTAssertEqual(one.versionID, "2")
        XCTAssertEqual(try XCTUnwrap(one.lastUpdated).timeIntervalSince1970, 1_617_693_058.874, accuracy: 0.0005)
        XCTAssertNil(other.lastUpdated)
    }

    func testRawResourceNeedsATypeAndAnID() {
        for json in [#"{"id":"a"}"#, #"{"resourceType":"Condition"}"#, #"{"resourceType":"","id":"a"}"#, #"["Condition"]"#, "not json"] {
            XCTAssertThrowsError(try FHIRR4RawResource(data: Data(json.utf8)), json) { error in
                XCTAssertEqual(error as? FHIRR4Error, .invalidResponse)
            }
        }
        XCTAssertThrowsError(try FHIRR4RawResource(jsonObject: ["resourceType": "Condition", "id": "a", "when": Date()])) { error in
            XCTAssertEqual(error as? FHIRR4Error, .invalidResponse, "a value JSON cannot hold must throw, not crash")
        }
    }

    // MARK: - Typed resources

    func testPatientDecodes() throws {
        let patient = try FHIRR4Fixture.patient().decode(FHIRR4Patient.self)
        XCTAssertEqual(patient.id, FHIRR4Fixture.schroederID)
        XCTAssertEqual(patient.gender, "male")
        XCTAssertEqual(patient.birthDate?.value?.precision, .day)
        XCTAssertEqual(patient.deceasedDateTime?.date, Date(timeIntervalSince1970: 1_579_395_161))
        XCTAssertEqual(patient.name?.first?.use, "official")
        XCTAssertEqual(patient.name?.first?.family, "Schroeder")
        XCTAssertEqual(patient.name?.first?.given ?? [], ["Elisha"])
        XCTAssertEqual(patient.telecom?.first?.value, "555-193-6568")
        XCTAssertEqual(patient.address?.first?.line ?? [], ["651 Walsh Camp"])
        XCTAssertEqual(patient.maritalStatus?.coding?.first?.code, "M")
        XCTAssertEqual(patient.communication?.first?.language?.text, "English")

        // The capture has five identifiers: Synthea's own, the MRN, and three government numbers.
        let identifiers = patient.identifier ?? []
        XCTAssertEqual(identifiers.count, 5)
        let recordNumbers = identifiers.filter { $0.type?.text == "Medical Record Number" }
        XCTAssertEqual(recordNumbers.count, 1)
        XCTAssertEqual(recordNumbers.first?.system, "http://hospital.smarthealthit.org")
        XCTAssertEqual(recordNumbers.first?.type?.coding(inSystem: "http://terminology.hl7.org/CodeSystem/v2-0203")?.code, "MR")
    }

    func testConditionsDecode() throws {
        let conditions = try FHIRR4Fixture.resources("Condition.schroeder").map { try $0.decode(FHIRR4Condition.self) }
        XCTAssertEqual(conditions.count, 5)
        XCTAssertTrue(conditions.allSatisfy { $0.code?.coding?.first?.system == "http://snomed.info/sct" })
        XCTAssertEqual(conditions.filter { $0.abatementDateTime?.date != nil }.count, 3)
        XCTAssertTrue(conditions.allSatisfy { $0.onsetDateTime?.date != nil && $0.recordedDate?.date != nil })
        XCTAssertEqual(conditions.compactMap { $0.clinicalStatus?.firstCode }.sorted(), ["active", "active", "resolved", "resolved", "resolved"])
        XCTAssertTrue(conditions.allSatisfy { $0.verificationStatus?.firstCode == "confirmed" && !$0.isEnteredInError })
        XCTAssertTrue(conditions.allSatisfy { $0.encounter?.resourceType == "Encounter" })
    }

    func testMedicationRequestsDecode() throws {
        let requests = try FHIRR4Fixture.resources("MedicationRequest.schroeder").map { try $0.decode(FHIRR4MedicationRequest.self) }
        XCTAssertEqual(requests.count, 3)
        XCTAssertTrue(requests.allSatisfy {
            $0.medicationCodeableConcept?.coding?.first?.system == "http://www.nlm.nih.gov/research/umls/rxnorm"
        })
        XCTAssertTrue(requests.allSatisfy { $0.medicationReference == nil })
        // The requester is a bare reference: a type and an id, no name.
        XCTAssertTrue(requests.allSatisfy { $0.requester?.resourceType == "Practitioner" && $0.requester?.display == nil })
        XCTAssertTrue(requests.allSatisfy { $0.status == "stopped" && $0.intent == "order" && $0.authoredOn?.date != nil })
        XCTAssertEqual(requests.filter { $0.reasonReference?.isEmpty == false }.count, 1)
    }

    func testEncountersDecode() throws {
        let encounters = try FHIRR4Fixture.resources("Encounter.schroeder").map { try $0.decode(FHIRR4Encounter.self) }
        XCTAssertEqual(encounters.count, 11)
        XCTAssertTrue(encounters.allSatisfy { $0.classCoding?.code == "AMB" })
        XCTAssertTrue(encounters.allSatisfy { $0.type?.first?.text != nil })
        XCTAssertTrue(encounters.allSatisfy { $0.period?.start?.date != nil && $0.period?.end?.date != nil })
        XCTAssertEqual(encounters.filter { $0.reasonCode?.isEmpty == false }.count, 3)
        XCTAssertEqual(encounters.filter { $0.participant?.first?.individual?.resourceType == "Practitioner" }.count, 10)
        XCTAssertTrue(encounters.allSatisfy { $0.serviceProvider?.resourceType == "Organization" })
    }

    func testProceduresDecode() throws {
        let procedures = try FHIRR4Fixture.resources("Procedure.schroeder").map { try $0.decode(FHIRR4Procedure.self) }
        XCTAssertEqual(procedures.count, 6)
        XCTAssertTrue(procedures.allSatisfy { $0.performedPeriod?.start?.date != nil && $0.performedPeriod?.end?.date != nil })
        XCTAssertTrue(procedures.allSatisfy { $0.performedDateTime == nil && $0.status == "completed" })
        XCTAssertEqual(procedures.compactMap { $0.reasonReference?.first?.display }.sorted(), ["Streptococcal sore throat (disorder)", "Stroke"])
    }

    func testImmunizationsDecode() throws {
        let immunizations = try FHIRR4Fixture.resources("Immunization.schroeder").map { try $0.decode(FHIRR4Immunization.self) }
        XCTAssertEqual(immunizations.count, 11)
        XCTAssertTrue(immunizations.allSatisfy { $0.vaccineCode?.coding(inSystem: "http://hl7.org/fhir/sid/cvx") != nil })
        XCTAssertTrue(immunizations.allSatisfy { $0.occurrenceDateTime?.date != nil && $0.primarySource == true })
        XCTAssertEqual(immunizations.filter { $0.vaccineCode?.coding?.first?.code == "140" }.count, 7)
    }

    func testDiagnosticReportsDecode() throws {
        let reports = try FHIRR4Fixture.resources("DiagnosticReport.schroeder").map { try $0.decode(FHIRR4DiagnosticReport.self) }
        XCTAssertEqual(reports.count, 6)
        XCTAssertTrue(reports.allSatisfy { $0.category?.first?.coding?.first?.code == "LAB" })
        XCTAssertTrue(reports.allSatisfy { $0.effectiveDateTime?.date != nil && $0.issued?.date != nil })
        let results = reports.flatMap { $0.result ?? [] }
        XCTAssertEqual(results.count, 35)
        XCTAssertTrue(results.allSatisfy { $0.resourceType == "Observation" && $0.display != nil })
    }

    func testObservationsDecodeAcrossBothPages() throws {
        let observations = try FHIRR4Fixture.observations().map { try $0.decode(FHIRR4Observation.self) }
        XCTAssertEqual(observations.count, 79)

        let categories = Set(observations.compactMap { $0.category?.first?.coding?.first?.code })
        XCTAssertEqual(categories, ["vital-signs", "laboratory", "survey", "exam"])

        // value[x] is a quantity or a coded answer; blood pressure has neither and uses components.
        XCTAssertEqual(observations.filter { $0.valueQuantity != nil }.count, 64)
        XCTAssertEqual(observations.filter { $0.valueCodeableConcept != nil }.count, 8)
        let pressures = observations.filter { $0.code?.coding(inSystem: "http://loinc.org")?.code == "55284-4" }
        XCTAssertEqual(pressures.count, 7)
        for pressure in pressures {
            XCTAssertNil(pressure.valueQuantity)
            let codes = Set((pressure.component ?? []).compactMap { $0.code?.coding?.first?.code })
            XCTAssertEqual(codes, ["8480-6", "8462-4"])
            XCTAssertTrue((pressure.component ?? []).allSatisfy { $0.valueQuantity?.unit == "mm[Hg]" })
        }
        XCTAssertTrue(observations.allSatisfy { $0.effectiveDateTime?.date != nil && $0.issued?.date != nil })
    }

    func testAllergiesDecodeIncludingTheOneEnteredInError() throws {
        let allergies = try FHIRR4Fixture.resources("AllergyIntolerance.rice").map { try $0.decode(FHIRR4AllergyIntolerance.self) }
        XCTAssertEqual(allergies.count, 3)
        XCTAssertEqual(allergies.filter(\.isEnteredInError).count, 1)
        XCTAssertEqual(allergies.first(where: \.isEnteredInError)?.id, "4889149")
        // These allergies were typed by hand in the sandbox: text, no coding.
        XCTAssertTrue(allergies.allSatisfy { $0.code?.coding == nil && $0.code?.text != nil })
        XCTAssertEqual(allergies.compactMap { $0.code?.bestDisplay }, ["Life", "Peanut", "Shellfish"])
    }

    func testAppointmentsDecodeEvenWithADateFHIRDoesNotAllow() throws {
        let appointments = try FHIRR4Fixture.resources("Appointment.rice").map { try $0.decode(FHIRR4Appointment.self) }
        XCTAssertEqual(appointments.count, 4)
        XCTAssertTrue(appointments.allSatisfy { ($0.participant ?? []).contains { $0.actor?.resourceType == "Patient" } })
        XCTAssertEqual(appointments.filter { ($0.participant ?? []).contains { $0.actor?.resourceType == "Practitioner" } }.count, 2)

        // One start has a time and no zone. It decodes as unreadable and the rest of the resource survives.
        let unreadable = appointments.filter { $0.start?.isUnreadable == true }
        XCTAssertEqual(unreadable.map(\.id), ["3076955"])
        XCTAssertEqual(unreadable.first?.start?.original, "2025-09-27T09:00:00")
        XCTAssertNotNil(unreadable.first?.end?.date)
        XCTAssertEqual(unreadable.first?.description, "Primary Care Follow-up")
    }

    func testDocumentReferencesDecode() throws {
        let documents = try FHIRR4Fixture.resources("DocumentReference.synthetic").map { try $0.decode(FHIRR4DocumentReference.self) }
        XCTAssertEqual(documents.count, 2)
        XCTAssertEqual(documents.compactMap { $0.content?.first?.attachment?.contentType }, ["text/plain", "text/html"])
        XCTAssertTrue(documents.allSatisfy { $0.content?.first?.attachment?.data != nil })
        XCTAssertTrue(documents.allSatisfy { $0.author?.first?.display == "Dr. Test Author" && $0.date?.date != nil })
    }

    func testOperationOutcomeSummary() throws {
        let outcome = try JSONDecoder().decode(FHIRR4OperationOutcome.self, from: FHIRR4Fixture.data("OperationOutcome.404"))
        XCTAssertTrue(outcome.isOperationOutcome)
        XCTAssertEqual(outcome.issue?.first?.severity, "error")
        XCTAssertEqual(outcome.summary, "Resource Patient/does-not-exist-openclinic is not known")

        let several = try JSONDecoder().decode(FHIRR4OperationOutcome.self, from: Data("""
        {"resourceType":"OperationOutcome","issue":[
          {"severity":"error","code":"invalid","details":{"text":"Unknown search parameter"}},
          {"severity":"warning","code":"not-supported"},
          {"severity":"error","code":"invalid","details":{"text":"Unknown search parameter"}}
        ]}
        """.utf8))
        XCTAssertEqual(several.summary, "Unknown search parameter; not-supported")

        let other = try JSONDecoder().decode(FHIRR4OperationOutcome.self, from: FHIRR4Fixture.data("Patient.schroeder"))
        XCTAssertFalse(other.isOperationOutcome)
    }

    // MARK: - Data types

    func testReferenceParsingForms() throws {
        func reference(_ string: String?) throws -> FHIRR4Reference {
            let object: [String: Any] = string.map { ["reference": $0] } ?? [:]
            return try JSONDecoder().decode(FHIRR4Reference.self, from: JSONSerialization.data(withJSONObject: object))
        }

        let cases: [(reference: String?, type: String?, id: String?, relative: String?)] = [
            ("Encounter/bd501f8d-1301-461c-acaf-1c00b401e228", "Encounter", "bd501f8d-1301-461c-acaf-1c00b401e228", "Encounter/bd501f8d-1301-461c-acaf-1c00b401e228"),
            ("https://r4.smarthealthit.org/Observation/81b17262", "Observation", "81b17262", "Observation/81b17262"),
            ("https://launch.smarthealthit.org/v/r4/fhir/Patient/123", "Patient", "123", "Patient/123"),
            ("Patient/123/_history/4", "Patient", "123", "Patient/123"),
            ("https://example.org/fhir/Patient/123/_history/4", "Patient", "123", "Patient/123"),
            ("urn:uuid:0d3d4f0e-7d1c-4a0b-9a55-0f6c2f0c7e11", nil, "0d3d4f0e-7d1c-4a0b-9a55-0f6c2f0c7e11", nil),
            ("#contained-medication", nil, nil, nil),
            ("https://example.org/fhir", nil, nil, nil),
            ("Patient", nil, nil, nil),
            ("", nil, nil, nil),
            (nil, nil, nil, nil),
        ]
        for expected in cases {
            let parsed = try reference(expected.reference)
            let label = expected.reference ?? "nil"
            XCTAssertEqual(parsed.resourceType, expected.type, label)
            XCTAssertEqual(parsed.id, expected.id, label)
            XCTAssertEqual(parsed.relativeReference, expected.relative, label)
        }
    }

    func testBestDisplayPrefersTextThenDisplayThenCode() throws {
        func concept(_ json: String) throws -> FHIRR4CodeableConcept {
            try JSONDecoder().decode(FHIRR4CodeableConcept.self, from: Data(json.utf8))
        }

        XCTAssertEqual(try concept(#"{"text":"Stroke","coding":[{"code":"230690007","display":"Cerebrovascular accident"}]}"#).bestDisplay, "Stroke")
        XCTAssertEqual(try concept(#"{"text":"  ","coding":[{"code":"1"},{"code":"2","display":"Second"}]}"#).bestDisplay, "Second")
        XCTAssertEqual(try concept(#"{"coding":[{"system":"http://loinc.org","code":"8480-6"}]}"#).bestDisplay, "8480-6")
        XCTAssertNil(try concept(#"{"coding":[]}"#).bestDisplay)
        XCTAssertNil(try concept("{}").bestDisplay)

        let two = try concept(#"{"coding":[{"system":"a","code":"1"},{"system":"b","code":"2"}]}"#)
        XCTAssertEqual(two.coding(inSystem: "b")?.code, "2")
        XCTAssertNil(two.coding(inSystem: "c"))
        XCTAssertEqual(two.firstCode, "1")
    }
}
