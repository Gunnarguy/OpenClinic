import Foundation
import XCTest
@testable import OpenClinic

/// The whole read of one patient, against a stub that answers as the sandbox did.
final class FHIRR4ChartFetcherTests: XCTestCase {

    override func tearDown() {
        FHIRR4StubProtocol.reset()
        super.tearDown()
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private func makeFetcher(configuration: FHIRR4Client.Configuration = FHIRR4Client.Configuration(pageSize: 50)) throws -> FHIRR4ChartFetcher {
        // The trailing slash is on purpose: sources must come out without it.
        let client = FHIRR4Client(
            baseURL: try XCTUnwrap(URL(string: FHIRR4Fixture.serverBase + "/")),
            session: FHIRR4StubProtocol.session(),
            configuration: configuration,
            sleeper: { _ in }
        )
        return FHIRR4ChartFetcher(client: client)
    }

    func testFetchesTheWholeSchroederChart() async throws {
        FHIRR4StubProtocol.install(try FHIRR4Fixture.schroederServer())
        let fetcher = try makeFetcher()
        let progress = FHIRR4Recorder<FHIRR4ChartFetcher.Progress>()

        let fetched = try await fetcher.fetchChart(patientID: FHIRR4Fixture.schroederID, calendar: utc) { step in
            progress.append(step)
        }
        let chart = fetched.chart

        XCTAssertEqual(chart.patient.givenName, "Elisha")
        XCTAssertEqual(chart.patient.familyName, "Schroeder")
        XCTAssertEqual(chart.patient.source.serverBase, "https://r4.smarthealthit.org")
        XCTAssertEqual(chart.counts.map(\.count), [5, 3, 0, 79, 11, 6, 11, 6, 2, 0])
        XCTAssertTrue(chart.warnings.isEmpty, "\(chart.warnings)")
        XCTAssertTrue(chart.truncatedTypes.isEmpty)
        XCTAssertTrue(chart.failedTypes.isEmpty)
        XCTAssertEqual(chart.observations.first?.source.qualifiedID, "https://r4.smarthealthit.org/Observation/3c36fc98-caf2-4a00-9bc7-b3fdb0405eb3")

        // The Patient first, then every resource in the order the types are listed.
        XCTAssertEqual(fetched.rawResources.count, 124)
        XCTAssertEqual(fetched.rawResources.first?.resourceType, "Patient")
        XCTAssertEqual(fetched.rawResources.first?.id, FHIRR4Fixture.schroederID)
        var typesInOrder: [String] = []
        for resource in fetched.rawResources.dropFirst() where typesInOrder.last != resource.resourceType {
            typesInOrder.append(resource.resourceType)
        }
        XCTAssertEqual(typesInOrder, FHIRR4ChartFetcher.patientResourceTypes.filter { !["AllergyIntolerance", "Appointment"].contains($0) })

        // One progress step per type, counted up as the searches end.
        let steps = progress.values
        XCTAssertEqual(steps.count, 10)
        XCTAssertEqual(steps.map(\.completedTypes), Array(1...10))
        XCTAssertTrue(steps.allSatisfy { $0.totalTypes == 10 })
        XCTAssertEqual(Set(steps.map(\.resourceType)), Set(FHIRR4ChartFetcher.patientResourceTypes))
        XCTAssertEqual(steps.first { $0.resourceType == "Observation" }?.fetched, 79)
        XCTAssertEqual(steps.first { $0.resourceType == "AllergyIntolerance" }?.fetched, 0)

        // One read of the Patient, ten searches by patient, and the second Observation page.
        let requests = FHIRR4StubProtocol.requests
        XCTAssertEqual(requests.count, 12)
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://r4.smarthealthit.org/Patient/\(FHIRR4Fixture.schroederID)")
        let searches = requests.filter { FHIRR4StubProtocol.query(of: $0)["patient"] != nil }
        XCTAssertEqual(searches.count, 10)
        XCTAssertTrue(searches.allSatisfy {
            let query = FHIRR4StubProtocol.query(of: $0)
            return query["patient"] == FHIRR4Fixture.schroederID && query["_count"] == "50"
        })
        XCTAssertEqual(
            Set(searches.compactMap { $0.url?.lastPathComponent }),
            Set(FHIRR4ChartFetcher.patientResourceTypes)
        )
    }

    func testOneFailedTypeBecomesAWarningAndTheRestImport() async throws {
        FHIRR4StubProtocol.install(try FHIRR4Fixture.schroederServer(failing: "Procedure"))
        let fetcher = try makeFetcher()

        let fetched = try await fetcher.fetchChart(patientID: FHIRR4Fixture.schroederID, calendar: utc)
        let chart = fetched.chart

        // The failed type is named, so its empty list is not read as "the patient has none".
        XCTAssertEqual(chart.failedTypes, ["Procedure"])
        XCTAssertTrue(chart.truncatedTypes.isEmpty)
        XCTAssertTrue(chart.procedures.isEmpty)
        XCTAssertEqual(chart.warnings.count, 1)
        XCTAssertEqual(
            chart.warnings.first,
            "Procedure could not be read: The server answered with status 500: \(HTTPURLResponse.localizedString(forStatusCode: 500))"
        )

        XCTAssertEqual(chart.counts.map(\.count), [5, 3, 0, 79, 11, 0, 11, 6, 2, 0])
        XCTAssertEqual(fetched.rawResources.count, 118)
        XCTAssertFalse(fetched.rawResources.contains { $0.resourceType == "Procedure" })
    }

    func testASearchCutShortIsListedAsTruncatedNotFailed() async throws {
        FHIRR4StubProtocol.install(try FHIRR4Fixture.schroederServer())
        let fetcher = try makeFetcher(configuration: FHIRR4Client.Configuration(pageSize: 50, maxPages: 1))

        let chart = try await fetcher.fetchChart(patientID: FHIRR4Fixture.schroederID, calendar: utc).chart

        XCTAssertEqual(chart.truncatedTypes, ["Observation"])
        XCTAssertTrue(chart.failedTypes.isEmpty)
        XCTAssertEqual(chart.observations.count, 50)
        XCTAssertEqual(chart.warnings, [
            "Observation: the search stopped at the page limit after 1 page, so the list may be incomplete.",
        ])
        XCTAssertEqual(chart.problems.count, 5)
    }

    func testAFailedPatientReadThrows() async throws {
        FHIRR4StubProtocol.install(try FHIRR4Fixture.schroederServer())
        let fetcher = try makeFetcher()

        await fhirR4AssertThrows(.server(status: 404, message: "Resource Patient/does-not-exist-openclinic is not known")) {
            _ = try await fetcher.fetchChart(patientID: "does-not-exist-openclinic")
        }

        XCTAssertEqual(FHIRR4StubProtocol.requests.count, 1, "nothing is searched for a patient that could not be read")
    }
}
