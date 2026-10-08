import Foundation
import XCTest
@testable import OpenClinic

/// The client against a stubbed server. Nothing here sleeps or touches the network.
final class FHIRR4ClientTests: XCTestCase {

    override func tearDown() {
        FHIRR4StubProtocol.reset()
        super.tearDown()
    }

    private func makeClient(
        base: String = FHIRR4Fixture.serverBase,
        configuration: FHIRR4Client.Configuration = FHIRR4Client.Configuration(),
        tokenProvider: @escaping FHIRR4Client.TokenProvider = { _ in nil },
        sleeper: @escaping FHIRR4Client.Sleeper = { _ in }
    ) throws -> FHIRR4Client {
        FHIRR4Client(
            baseURL: try XCTUnwrap(URL(string: base)),
            session: FHIRR4StubProtocol.session(),
            configuration: configuration,
            tokenProvider: tokenProvider,
            sleeper: sleeper
        )
    }

    private var patientQuery: [URLQueryItem] {
        [URLQueryItem(name: "patient", value: FHIRR4Fixture.schroederID)]
    }

    /// A one-resource search page, with a next link when one is given.
    private func page(id: String, next: String? = nil) -> Data {
        let link = next.map { #","link":[{"relation":"next","url":"\#($0)"}]"# } ?? ""
        return Data(#"{"resourceType":"Bundle","type":"searchset","total":2\#(link),"entry":[{"resource":{"resourceType":"Observation","id":"\#(id)"}}]}"#.utf8)
    }

    // MARK: - Headers

    func testSendsTheFHIRAcceptHeaderAndTheBearerToken() async throws {
        let patient = try FHIRR4Fixture.data("Patient.schroeder")
        FHIRR4StubProtocol.install { _ in FHIRR4StubProtocol.Response(body: patient) }
        let asked = FHIRR4Recorder<Bool>()
        let client = try makeClient(tokenProvider: { forceRefresh in
            asked.append(forceRefresh)
            return "token-for-tests"
        })

        let resource = try await client.read("Patient", id: FHIRR4Fixture.schroederID)

        XCTAssertEqual(resource.resourceType, "Patient")
        XCTAssertEqual(resource.id, FHIRR4Fixture.schroederID)
        let request = try XCTUnwrap(FHIRR4StubProtocol.requests.first)
        XCTAssertEqual(FHIRR4StubProtocol.requests.count, 1)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://r4.smarthealthit.org/Patient/\(FHIRR4Fixture.schroederID)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/fhir+json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-for-tests")
        XCTAssertEqual(asked.values, [false], "a first attempt never forces a refresh")
    }

    func testSendsNoAuthorizationHeaderWhenThereIsNoToken() async throws {
        let patient = try FHIRR4Fixture.data("Patient.schroeder")
        FHIRR4StubProtocol.install { _ in FHIRR4StubProtocol.Response(body: patient) }
        let client = try makeClient()

        _ = try await client.read("Patient", id: FHIRR4Fixture.schroederID)

        let request = try XCTUnwrap(FHIRR4StubProtocol.requests.first)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/fhir+json")
    }

    // MARK: - URLs

    func testBaseURLLosesItsTrailingSlashAndKeepsItsPath() async throws {
        let patient = try FHIRR4Fixture.data("Patient.schroeder")
        FHIRR4StubProtocol.install { _ in FHIRR4StubProtocol.Response(body: patient) }
        let client = try makeClient(base: "https://launch.smarthealthit.org/v/r4/fhir/")

        XCTAssertEqual(client.baseURL.absoluteString, "https://launch.smarthealthit.org/v/r4/fhir")
        _ = try await client.read("Patient", id: FHIRR4Fixture.schroederID)
        XCTAssertEqual(
            FHIRR4StubProtocol.requests.first?.url?.absoluteString,
            "https://launch.smarthealthit.org/v/r4/fhir/Patient/\(FHIRR4Fixture.schroederID)"
        )
    }

    /// One server, one spelling: row identifiers are built from the base address.
    func testBaseURLIsLowerCasedAndLosesADefaultPort() throws {
        let client = try makeClient(base: "HTTPS://R4.SmartHealthIT.org:443/Fhir/")
        XCTAssertEqual(client.baseURL.absoluteString, "https://r4.smarthealthit.org/Fhir", "the path keeps its case")

        XCTAssertEqual(FHIRR4Client.normalizedBase("  https://R4.SMARTHEALTHIT.ORG/  "), "https://r4.smarthealthit.org")
        XCTAssertEqual(FHIRR4Client.normalizedBase("http://Example.org:80/fhir//"), "http://example.org/fhir")
        XCTAssertEqual(FHIRR4Client.normalizedBase("https://example.org:8443/fhir"), "https://example.org:8443/fhir", "another port is part of the address")
        XCTAssertEqual(FHIRR4Client.normalizedBase("not an address/"), "not an address")
    }

    // MARK: - Redirects

    func testARedirectToAnotherServerIsRefusedAndNothingIsSentThere() async throws {
        let elsewhere = try XCTUnwrap(URL(string: "https://elsewhere.example/Patient/\(FHIRR4Fixture.schroederID)"))
        let patient = try FHIRR4Fixture.data("Patient.schroeder")
        FHIRR4StubProtocol.install { request in
            request.url?.host == "elsewhere.example"
                ? FHIRR4StubProtocol.Response(body: patient)
                : FHIRR4StubProtocol.Response(status: 302, redirect: elsewhere)
        }
        let client = try makeClient(tokenProvider: { _ in "token-for-tests" })

        await fhirR4AssertThrows(.redirectOutsideServer("https://elsewhere.example")) {
            _ = try await client.read("Patient", id: FHIRR4Fixture.schroederID)
        }

        XCTAssertEqual(FHIRR4StubProtocol.requests.map { $0.url?.host }, ["r4.smarthealthit.org"],
                       "the request with the token and the patient's id never reached the other server")
    }

    func testARedirectOnTheSameServerIsFollowed() async throws {
        let moved = try XCTUnwrap(URL(string: "https://r4.smarthealthit.org/moved/Patient/\(FHIRR4Fixture.schroederID)"))
        let patient = try FHIRR4Fixture.data("Patient.schroeder")
        FHIRR4StubProtocol.install { request in
            request.url?.path.hasPrefix("/moved/") == true
                ? FHIRR4StubProtocol.Response(body: patient)
                : FHIRR4StubProtocol.Response(status: 307, redirect: moved)
        }
        let client = try makeClient()

        let resource = try await client.read("Patient", id: FHIRR4Fixture.schroederID)

        XCTAssertEqual(resource.id, FHIRR4Fixture.schroederID)
        XCTAssertEqual(FHIRR4StubProtocol.requests.count, 2)
    }

    // MARK: - Paging links

    func testARelativeNextLinkIsResolvedAgainstThePageItCameOn() async throws {
        let first = page(id: "o1", next: "?_getpages=abc&_getpagesoffset=1")
        let second = page(id: "o2")
        FHIRR4StubProtocol.install { request in
            FHIRR4StubProtocol.Response(body: FHIRR4StubProtocol.query(of: request)["_getpages"] == "abc" ? second : first)
        }
        let client = try makeClient()

        let result = try await client.search("Observation", parameters: patientQuery)

        XCTAssertEqual(result.resources.map(\.id), ["o1", "o2"])
        XCTAssertEqual(FHIRR4StubProtocol.requests.last?.url?.host, "r4.smarthealthit.org")
        XCTAssertEqual(FHIRR4StubProtocol.requests.last?.url?.path, "/Observation", "a link that is only a query keeps the page's path")
    }

    /// With a base that has a path, a link such as "Observation?page=2" belongs under that path.
    func testARelativeNextLinkStaysUnderABaseThatHasAPath() async throws {
        let first = page(id: "o1", next: "Observation?page=2")
        let second = page(id: "o2")
        FHIRR4StubProtocol.install { request in
            FHIRR4StubProtocol.Response(body: FHIRR4StubProtocol.query(of: request)["page"] == "2" ? second : first)
        }
        let client = try makeClient(base: "https://launch.example/v/r4/fhir")

        let result = try await client.search("Observation", parameters: patientQuery)

        XCTAssertEqual(result.resources.map(\.id), ["o1", "o2"])
        XCTAssertEqual(FHIRR4StubProtocol.requests.last?.url?.path, "/v/r4/fhir/Observation")
    }

    func testANextLinkThatIsNotAnAddressIsAnErrorNotTheEndOfTheSearch() async throws {
        let first = page(id: "o1", next: "mailto:next-page")
        FHIRR4StubProtocol.install { _ in FHIRR4StubProtocol.Response(body: first) }
        let client = try makeClient()

        await fhirR4AssertThrows(.invalidResponse) {
            _ = try await client.search("Observation", parameters: self.patientQuery)
        }
        XCTAssertEqual(FHIRR4StubProtocol.requests.count, 1)
    }

    func testAnIDCannotNameAnotherPath() async throws {
        FHIRR4StubProtocol.install { _ in FHIRR4StubProtocol.Response(status: 404) }
        let client = try makeClient()

        _ = try? await client.read("Patient", id: "../Observation?x=1")

        let url = try XCTUnwrap(FHIRR4StubProtocol.requests.first?.url)
        XCTAssertEqual(url.host, "r4.smarthealthit.org")
        XCTAssertEqual(url.absoluteString, "https://r4.smarthealthit.org/Patient/..%2FObservation%3Fx%3D1")
    }

    func testSearchAddsThePageSizeUnlessTheCallerGaveOne() async throws {
        let empty = try FHIRR4Fixture.data("AllergyIntolerance.empty")
        FHIRR4StubProtocol.install { _ in FHIRR4StubProtocol.Response(body: empty) }
        let client = try makeClient()

        let result = try await client.search("AllergyIntolerance", parameters: patientQuery)
        _ = try await client.search("AllergyIntolerance", parameters: patientQuery + [URLQueryItem(name: "_count", value: "5")])
        _ = try await client.search("Observation", parameters: [URLQueryItem(name: "date", value: "ge2020-01-19T00:52:41+00:00")])

        XCTAssertTrue(result.resources.isEmpty)
        XCTAssertEqual(result.total, 0)
        XCTAssertEqual(result.pagesFetched, 1)
        XCTAssertFalse(result.truncated)

        let requests = FHIRR4StubProtocol.requests
        guard requests.count == 3 else { return XCTFail("Expected 3 requests, got \(requests.count)") }
        XCTAssertEqual(
            requests[0].url?.absoluteString,
            "https://r4.smarthealthit.org/AllergyIntolerance?patient=\(FHIRR4Fixture.schroederID)&_count=100"
        )
        XCTAssertEqual(
            requests[1].url?.absoluteString,
            "https://r4.smarthealthit.org/AllergyIntolerance?patient=\(FHIRR4Fixture.schroederID)&_count=5"
        )
        // A "+" must be escaped, or the server reads the time zone offset as a space.
        XCTAssertEqual(
            requests[2].url?.absoluteString,
            "https://r4.smarthealthit.org/Observation?date=ge2020-01-19T00:52:41%2B00:00&_count=100"
        )
    }

    // MARK: - Paging

    func testSearchFollowsTheSandboxNextLinkAcrossBothPages() async throws {
        let first = try FHIRR4Fixture.data("Observation.schroeder.page1")
        let second = try FHIRR4Fixture.data("Observation.schroeder.page2")
        FHIRR4StubProtocol.install { request in
            let isSecondPage = FHIRR4StubProtocol.query(of: request)["_getpages"] != nil
            return FHIRR4StubProtocol.Response(body: isSecondPage ? second : first)
        }
        let client = try makeClient(configuration: FHIRR4Client.Configuration(pageSize: 50))

        let result = try await client.search("Observation", parameters: patientQuery)

        XCTAssertEqual(result.resources.count, 79)
        XCTAssertEqual(Set(result.resources.map(\.id)).count, 79)
        XCTAssertTrue(result.resources.allSatisfy { $0.resourceType == "Observation" })
        XCTAssertEqual(result.pagesFetched, 2)
        XCTAssertEqual(result.total, 79)
        XCTAssertFalse(result.truncated)
        // Page order is kept: the first resource of each capture is where it should be.
        XCTAssertEqual(result.resources.first?.id, "bcfc01c0-7552-4976-b685-e2449636bb3e")
        XCTAssertEqual(result.resources.dropFirst(50).first?.id, "3c36fc98-caf2-4a00-9bc7-b3fdb0405eb3")

        let requests = FHIRR4StubProtocol.requests
        guard requests.count == 2 else { return XCTFail("Expected 2 requests, got \(requests.count)") }
        XCTAssertEqual(
            requests[0].url?.absoluteString,
            "https://r4.smarthealthit.org/Observation?patient=\(FHIRR4Fixture.schroederID)&_count=50"
        )
        // The sandbox's next link is the server root with a query and no path. It must be followed as given.
        let next = try XCTUnwrap(requests[1].url)
        XCTAssertEqual(next.host, "r4.smarthealthit.org")
        XCTAssertEqual(next.scheme, "https")
        let query = FHIRR4StubProtocol.query(of: requests[1])
        XCTAssertEqual(query["_getpages"], "0739cbe6-fc7c-4857-82ee-91099c01e302")
        XCTAssertEqual(query["_getpagesoffset"], "50")
        XCTAssertEqual(query["_count"], "50")
    }

    func testSearchStopsAtThePageLimitAndSaysSo() async throws {
        let first = try FHIRR4Fixture.data("Observation.schroeder.page1")
        FHIRR4StubProtocol.install { _ in FHIRR4StubProtocol.Response(body: first) }
        let client = try makeClient(configuration: FHIRR4Client.Configuration(pageSize: 50, maxPages: 1))

        let result = try await client.search("Observation", parameters: patientQuery)

        XCTAssertEqual(result.resources.count, 50)
        XCTAssertEqual(result.pagesFetched, 1)
        XCTAssertEqual(result.total, 79)
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(FHIRR4StubProtocol.requests.count, 1)
    }

    func testReachingThePageLimitOnTheLastPageIsNotTruncation() async throws {
        let first = page(id: "a", next: "https://r4.smarthealthit.org?page=2")
        let last = page(id: "b")
        FHIRR4StubProtocol.install(sequence: [
            FHIRR4StubProtocol.Response(body: first),
            FHIRR4StubProtocol.Response(body: last),
        ])
        let client = try makeClient(configuration: FHIRR4Client.Configuration(maxPages: 2))

        let result = try await client.search("Observation", parameters: [])

        XCTAssertEqual(result.resources.map(\.id), ["a", "b"])
        XCTAssertEqual(result.pagesFetched, 2)
        XCTAssertFalse(result.truncated)
    }

    func testAResourceRepeatedOnALaterPageIsKeptOnce() async throws {
        FHIRR4StubProtocol.install(sequence: [
            FHIRR4StubProtocol.Response(body: page(id: "a", next: "https://r4.smarthealthit.org?page=2")),
            FHIRR4StubProtocol.Response(body: page(id: "a")),
        ])
        let client = try makeClient()

        let result = try await client.search("Observation", parameters: [])

        XCTAssertEqual(result.resources.map(\.id), ["a"])
        XCTAssertEqual(result.pagesFetched, 2)
    }

    func testANextLinkOnAnotherHostIsRefusedBeforeAnythingIsSent() async throws {
        let outside = [
            "https://evil.example.org/Observation?page=2": "https://evil.example.org",
            // The same host over plain HTTP would send the token in the clear.
            "http://r4.smarthealthit.org/Observation?page=2": "http://r4.smarthealthit.org",
            "https://r4.smarthealthit.org:8443/Observation?page=2": "https://r4.smarthealthit.org:8443",
            "https://r4.smarthealthit.org.evil.example.org/?page=2": "https://r4.smarthealthit.org.evil.example.org",
        ]
        for (link, origin) in outside {
            let body = page(id: "a", next: link)
            FHIRR4StubProtocol.install { _ in FHIRR4StubProtocol.Response(body: body) }
            let client = try makeClient(tokenProvider: { _ in "token-for-tests" })

            await fhirR4AssertThrows(.nextLinkOutsideServer(origin)) {
                _ = try await client.search("Observation", parameters: self.patientQuery)
            }

            // The stub answers for every host, so a request to the other host would be in this list.
            let requests = FHIRR4StubProtocol.requests
            XCTAssertEqual(requests.count, 1, link)
            XCTAssertEqual(requests.first?.url?.host, "r4.smarthealthit.org", link)
            XCTAssertEqual(requests.first?.url?.scheme, "https", link)
        }
    }

    func testSameServerComparesSchemeHostAndPort() throws {
        let base = try XCTUnwrap(URL(string: "https://r4.smarthealthit.org"))
        let same = [
            "https://r4.smarthealthit.org?_getpages=x&_getpagesoffset=50",
            "https://r4.smarthealthit.org/Observation?page=2",
            "https://R4.SmartHealthIT.org/Observation",
            "HTTPS://r4.smarthealthit.org:443/Observation",
        ]
        let different = [
            "http://r4.smarthealthit.org/Observation",
            "https://r4.smarthealthit.org:8443/Observation",
            "https://evil.example.org/Observation",
            "https://r4.smarthealthit.org.evil.example.org/Observation",
            "https://r4.smarthealthit.org@evil.example.org/Observation",
            "Observation?page=2",
        ]
        for string in same {
            XCTAssertTrue(FHIRR4Client.isSameServer(try XCTUnwrap(URL(string: string)), as: base), string)
        }
        for string in different {
            XCTAssertFalse(FHIRR4Client.isSameServer(try XCTUnwrap(URL(string: string)), as: base), string)
        }
    }

    // MARK: - Unauthorized

    func testUnauthorizedRefreshesTheTokenOnceAndRetries() async throws {
        let patient = try FHIRR4Fixture.data("Patient.schroeder")
        FHIRR4StubProtocol.install { request in
            let isFresh = request.value(forHTTPHeaderField: "Authorization") == "Bearer fresh-token"
            return isFresh ? FHIRR4StubProtocol.Response(body: patient) : FHIRR4StubProtocol.Response(status: 401)
        }
        let asked = FHIRR4Recorder<Bool>()
        let client = try makeClient(tokenProvider: { forceRefresh in
            asked.append(forceRefresh)
            return forceRefresh ? "fresh-token" : "stale-token"
        })

        let resource = try await client.read("Patient", id: FHIRR4Fixture.schroederID)

        XCTAssertEqual(resource.id, FHIRR4Fixture.schroederID)
        XCTAssertEqual(asked.values, [false, true])
        XCTAssertEqual(
            FHIRR4StubProtocol.requests.map { $0.value(forHTTPHeaderField: "Authorization") },
            ["Bearer stale-token", "Bearer fresh-token"]
        )
    }

    func testASecondUnauthorizedThrowsWithoutAThirdTry() async throws {
        FHIRR4StubProtocol.install { _ in FHIRR4StubProtocol.Response(status: 401) }
        let asked = FHIRR4Recorder<Bool>()
        let client = try makeClient(tokenProvider: { forceRefresh in
            asked.append(forceRefresh)
            return "rejected-token"
        })

        await fhirR4AssertThrows(.unauthorized) {
            _ = try await client.read("Patient", id: FHIRR4Fixture.schroederID)
        }

        XCTAssertEqual(asked.values, [false, true])
        XCTAssertEqual(FHIRR4StubProtocol.requests.count, 2)
    }

    // MARK: - Retries

    func testTooManyRequestsWaitsAsLongAsRetryAfterSays() async throws {
        let patient = try FHIRR4Fixture.data("Patient.schroeder")
        FHIRR4StubProtocol.install(sequence: [
            FHIRR4StubProtocol.Response(status: 429, headers: ["Retry-After": "7"]),
            // More than the client will ever wait: capped at 30 seconds.
            FHIRR4StubProtocol.Response(status: 429, headers: ["Retry-After": "120"]),
            // An HTTP date is not seconds, so the doubling wait applies: 500 ms doubled twice.
            FHIRR4StubProtocol.Response(status: 429, headers: ["Retry-After": "Wed, 07 Oct 2026 21:30:00 GMT"]),
            FHIRR4StubProtocol.Response(body: patient),
        ])
        let waits = FHIRR4Recorder<Duration>()
        let client = try makeClient(sleeper: { waits.append($0) })

        let resource = try await client.read("Patient", id: FHIRR4Fixture.schroederID)

        XCTAssertEqual(resource.id, FHIRR4Fixture.schroederID)
        XCTAssertEqual(waits.values, [.seconds(7), .seconds(30), .seconds(2)])
        XCTAssertEqual(FHIRR4StubProtocol.requests.count, 4)
    }

    func testServiceUnavailableGivesUpAfterTheRetriesWithADoublingWait() async throws {
        FHIRR4StubProtocol.install { _ in FHIRR4StubProtocol.Response(status: 503, body: Data("busy".utf8)) }
        let waits = FHIRR4Recorder<Duration>()
        let client = try makeClient(
            configuration: FHIRR4Client.Configuration(maxRetries: 3, baseBackoff: .milliseconds(100)),
            sleeper: { waits.append($0) }
        )

        // "busy" is not an OperationOutcome, so the message is the status's name and not the body.
        await fhirR4AssertThrows(.server(status: 503, message: HTTPURLResponse.localizedString(forStatusCode: 503))) {
            _ = try await client.search("Observation", parameters: self.patientQuery)
        }

        XCTAssertEqual(waits.values, [.milliseconds(100), .milliseconds(200), .milliseconds(400)])
        XCTAssertEqual(FHIRR4StubProtocol.requests.count, 4, "one try and three retries")
    }

    func testBadGatewayAndGatewayTimeoutAreRetried() async throws {
        let patient = try FHIRR4Fixture.data("Patient.schroeder")
        FHIRR4StubProtocol.install(sequence: [
            FHIRR4StubProtocol.Response(status: 502),
            FHIRR4StubProtocol.Response(status: 504),
            FHIRR4StubProtocol.Response(body: patient),
        ])
        let waits = FHIRR4Recorder<Duration>()
        let client = try makeClient(sleeper: { waits.append($0) })

        _ = try await client.read("Patient", id: FHIRR4Fixture.schroederID)

        XCTAssertEqual(waits.values, [.milliseconds(500), .seconds(1)])
    }

    func testATimeoutIsRetriedAndThenReportedAsTransport() async throws {
        let patient = try FHIRR4Fixture.data("Patient.schroeder")
        let calls = FHIRR4Counter()
        FHIRR4StubProtocol.install { _ in
            if calls.next() == 0 { throw URLError(.timedOut) }
            return FHIRR4StubProtocol.Response(body: patient)
        }
        let waits = FHIRR4Recorder<Duration>()
        let client = try makeClient(sleeper: { waits.append($0) })

        _ = try await client.read("Patient", id: FHIRR4Fixture.schroederID)
        XCTAssertEqual(waits.values, [.milliseconds(500)])
        XCTAssertEqual(FHIRR4StubProtocol.requests.count, 2)

        // A connection that never comes back uses up the retries and surfaces as a transport error.
        FHIRR4StubProtocol.install { _ in throw URLError(.networkConnectionLost) }
        do {
            _ = try await client.read("Patient", id: FHIRR4Fixture.schroederID)
            XCTFail("A lost connection must throw")
        } catch let error as FHIRR4Error {
            guard case .transport = error else { return XCTFail("Expected transport, got \(error)") }
        }
        XCTAssertEqual(FHIRR4StubProtocol.requests.count, 4)
    }

    func testOtherTransportErrorsAreNotRetried() async throws {
        FHIRR4StubProtocol.install { _ in throw URLError(.cannotFindHost) }
        let waits = FHIRR4Recorder<Duration>()
        let client = try makeClient(sleeper: { waits.append($0) })

        do {
            _ = try await client.read("Patient", id: FHIRR4Fixture.schroederID)
            XCTFail("An unknown host must throw")
        } catch let error as FHIRR4Error {
            guard case .transport = error else { return XCTFail("Expected transport, got \(error)") }
        }
        XCTAssertTrue(waits.values.isEmpty)
        XCTAssertEqual(FHIRR4StubProtocol.requests.count, 1)
    }

    // MARK: - Error bodies

    func testNotFoundCarriesTheOperationOutcomeMessage() async throws {
        let outcome = try FHIRR4Fixture.data("OperationOutcome.404")
        FHIRR4StubProtocol.install { _ in FHIRR4StubProtocol.Response(status: 404, body: outcome) }
        let waits = FHIRR4Recorder<Duration>()
        let client = try makeClient(sleeper: { waits.append($0) })

        await fhirR4AssertThrows(.server(status: 404, message: "Resource Patient/does-not-exist-openclinic is not known")) {
            _ = try await client.read("Patient", id: "does-not-exist-openclinic")
        }

        XCTAssertTrue(waits.values.isEmpty, "a 404 is an answer, not a reason to retry")
        XCTAssertEqual(FHIRR4StubProtocol.requests.count, 1)
    }

    func testAnErrorWithoutAnOutcomeNeverQuotesTheBody() async throws {
        let html = "<html>\n  <body>Bad   Gateway " + String(repeating: "x", count: 600) + "</body></html>"
        FHIRR4StubProtocol.install { _ in FHIRR4StubProtocol.Response(status: 500, body: Data(html.utf8)) }
        let client = try makeClient()

        do {
            _ = try await client.read("Patient", id: FHIRR4Fixture.schroederID)
            XCTFail("A 500 must throw")
        } catch let error as FHIRR4Error {
            guard case .server(let status, let message) = error else { return XCTFail("Expected server, got \(error)") }
            XCTAssertEqual(status, 500)
            XCTAssertEqual(message, HTTPURLResponse.localizedString(forStatusCode: 500))
            XCTAssertFalse(message.contains("Gateway"), "A body that is not an OperationOutcome must not reach the message")
        }
    }

    func testAnErrorNeverCarriesTheToken() async throws {
        FHIRR4StubProtocol.install { request in
            // A server that echoes the header it rejected, in the one kind of body a message quotes.
            let echoed = request.value(forHTTPHeaderField: "Authorization") ?? ""
            let outcome = #"{"resourceType":"OperationOutcome","issue":[{"severity":"error","code":"security","diagnostics":"Rejected header: \#(echoed)"}]}"#
            return FHIRR4StubProtocol.Response(status: 400, body: Data(outcome.utf8))
        }
        let client = try makeClient(tokenProvider: { _ in "token-for-tests" })

        await fhirR4AssertThrows(.server(status: 400, message: "Rejected header: Bearer [token removed]")) {
            _ = try await client.read("Patient", id: FHIRR4Fixture.schroederID)
        }
    }

    func testATwoHundredThatIsNotFHIRIsAnInvalidResponse() async throws {
        FHIRR4StubProtocol.install { _ in FHIRR4StubProtocol.Response(body: Data("<html>Sign in</html>".utf8)) }
        let client = try makeClient()

        await fhirR4AssertThrows(.invalidResponse) {
            _ = try await client.read("Patient", id: FHIRR4Fixture.schroederID)
        }
        await fhirR4AssertThrows(.invalidResponse) {
            _ = try await client.search("Observation", parameters: self.patientQuery)
        }
    }

    func testReadRefusesAResourceOfAnotherType() async throws {
        let patient = try FHIRR4Fixture.data("Patient.schroeder")
        FHIRR4StubProtocol.install { _ in FHIRR4StubProtocol.Response(body: patient) }
        let client = try makeClient()

        await fhirR4AssertThrows(.invalidResponse) {
            _ = try await client.read("Observation", id: FHIRR4Fixture.schroederID)
        }
    }

    // MARK: - Cancellation

    func testCancellationStopsTheSearchBeforeTheNextPage() async throws {
        // Every page links to another, so only cancellation or the page limit can end this search.
        let first = try FHIRR4Fixture.data("Observation.schroeder.page1")
        FHIRR4StubProtocol.install { _ in FHIRR4StubProtocol.Response(body: first) }
        let calls = FHIRR4Counter()
        let client = try makeClient(tokenProvider: { _ in
            // The token is asked for before each page. Cancelling the running task on the
            // second call cancels the search between its first and second page.
            if calls.next() == 1 {
                withUnsafeCurrentTask { task in
                    if let task { task.cancel() }
                }
            }
            return nil
        })
        let query = patientQuery

        let search = Task { try await client.search("Observation", parameters: query) }
        let result = await search.result

        switch result {
        case .success:
            XCTFail("A cancelled search must throw")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError, "Expected CancellationError, got \(error)")
        }
        XCTAssertEqual(FHIRR4StubProtocol.requests.count, 1, "the second page must never be asked for")
    }
}
