//
//  FHIRR4TestSupport.swift
//  OpenClinicTests
//
//  Shared by the FHIR R4 tests: the fixture loader, a URLProtocol stub that
//  stands in for the server so no test touches the network, and two small
//  thread-safe recorders for what the client asked of its token provider and
//  its sleeper.
//

import Foundation
import os
import XCTest
@testable import OpenClinic

// MARK: - Fixtures

/// The sandbox captures in OpenClinicTests/Fixtures/FHIR, which Xcode copies flat into the test bundle.
enum FHIRR4Fixture {
    static let schroederID = "b8c71d92-a06b-4044-b053-64664e82f851"
    static let serverBase = "https://r4.smarthealthit.org"

    /// Fixture name and resource type for every Schroeder search that returns one page.
    static let schroederSinglePages: [(fixture: String, type: String, count: Int)] = [
        ("Condition.schroeder", "Condition", 5),
        ("MedicationRequest.schroeder", "MedicationRequest", 3),
        ("Encounter.schroeder", "Encounter", 11),
        ("Procedure.schroeder", "Procedure", 6),
        ("Immunization.schroeder", "Immunization", 11),
        ("DiagnosticReport.schroeder", "DiagnosticReport", 6),
    ]

    static func data(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> Data {
        let bundle = Bundle(for: FHIRR4StubProtocol.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "json"),
            "\(name).json is not in the test bundle",
            file: file,
            line: line
        )
        return try Data(contentsOf: url)
    }

    static func bundle(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> FHIRR4Bundle {
        try FHIRR4Bundle(data: data(name, file: file, line: line))
    }

    static func resources(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> [FHIRR4RawResource] {
        try bundle(name, file: file, line: line).resources
    }

    static func patient() throws -> FHIRR4RawResource {
        try FHIRR4RawResource(data: data("Patient.schroeder"))
    }

    /// Both pages of the Observation search, in the order the server sent them.
    static func observations() throws -> [FHIRR4RawResource] {
        try resources("Observation.schroeder.page1") + resources("Observation.schroeder.page2")
    }

    /// Everything captured for the Schroeder patient except the Patient resource: 123 resources.
    static func schroederResources() throws -> [FHIRR4RawResource] {
        var all: [FHIRR4RawResource] = []
        for page in schroederSinglePages {
            all += try resources(page.fixture)
        }
        all += try observations()
        all += try resources("DocumentReference.synthetic")
        return all
    }

    /// A raw resource written inline, for the shapes the sandbox captures do not have.
    static func resource(_ json: String) throws -> FHIRR4RawResource {
        try FHIRR4RawResource(data: Data(json.utf8))
    }

    /// A stub server that answers as the sandbox did for the Schroeder patient. A search for
    /// `failingType` gets a 500. Allergies and appointments are empty, as they were.
    static func schroederServer(failing failingType: String? = nil) throws -> FHIRR4StubProtocol.Handler {
        var pages: [String: Data] = [:]
        for page in schroederSinglePages {
            pages[page.type] = try data(page.fixture)
        }
        pages["Observation"] = try data("Observation.schroeder.page1")
        pages["DocumentReference"] = try data("DocumentReference.synthetic")
        pages["AllergyIntolerance"] = try data("AllergyIntolerance.empty")
        pages["Appointment"] = try data("AllergyIntolerance.empty")
        let secondObservationPage = try data("Observation.schroeder.page2")
        let patient = try data("Patient.schroeder")
        let notFound = try data("OperationOutcome.404")
        let searches = pages

        return { request in
            guard let url = request.url else { throw URLError(.badURL) }
            if FHIRR4StubProtocol.query(of: request)["_getpages"] != nil {
                return FHIRR4StubProtocol.Response(body: secondObservationPage)
            }
            let path = url.path.split(separator: "/").map(String.init)
            if path == ["Patient", schroederID] {
                return FHIRR4StubProtocol.Response(body: patient)
            }
            guard path.count == 1, let body = searches[path[0]] else {
                return FHIRR4StubProtocol.Response(status: 404, body: notFound)
            }
            if path[0] == failingType {
                return FHIRR4StubProtocol.Response(status: 500, body: Data("The database is down.".utf8))
            }
            return FHIRR4StubProtocol.Response(body: body)
        }
    }
}

// MARK: - Server stub

/// Answers every request of a URLSession from a handler the test installs, and keeps
/// the requests so a test can say what was sent and, as important, what was not.
final class FHIRR4StubProtocol: URLProtocol {
    struct Response: Sendable {
        var status = 200
        var headers: [String: String] = ["Content-Type": "application/fhir+json"]
        var body = Data()
    }

    typealias Handler = @Sendable (URLRequest) throws -> Response

    private struct State: Sendable {
        var handler: Handler?
        var requests: [URLRequest] = []
    }

    // URLSession calls the protocol on its own threads, so the handler and the log sit behind a lock.
    private static let state = OSAllocatedUnfairLock(initialState: State())

    static func install(_ handler: @escaping Handler) {
        state.withLock { $0 = State(handler: handler) }
    }

    /// Answers the first request with the first response, the second with the second,
    /// and every request after the last with the last.
    static func install(sequence responses: [Response]) {
        let counter = FHIRR4Counter()
        install { _ in
            guard let last = responses.last else { throw URLError(.badServerResponse) }
            let index = counter.next()
            return index < responses.count ? responses[index] : last
        }
    }

    static func reset() {
        state.withLock { $0 = State() }
    }

    /// Every request received since the handler was installed, in order.
    static var requests: [URLRequest] {
        state.withLock { $0.requests }
    }

    /// A session that sends everything to the stub and keeps nothing on disk.
    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FHIRR4StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func query(of request: URLRequest) -> [String: String] {
        guard let url = request.url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return [:]
        }
        var query: [String: String] = [:]
        for item in items {
            query[item.name] = item.value ?? ""
        }
        return query
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        let handler = Self.state.withLock { state -> Handler? in
            state.requests.append(request)
            return state.handler
        }
        do {
            guard let handler, let url = request.url else { throw URLError(.badURL) }
            let stubbed = try handler(request)
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: stubbed.status,
                httpVersion: "HTTP/1.1",
                headerFields: stubbed.headers
            ) else {
                throw URLError(.badServerResponse)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stubbed.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Recorders

/// Collects values from closures that run on other threads, such as the client's sleeper.
final class FHIRR4Recorder<Value: Sendable>: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: [Value]())

    func append(_ value: Value) {
        storage.withLock { $0.append(value) }
    }

    var values: [Value] {
        storage.withLock { $0 }
    }
}

/// Counts calls from zero.
final class FHIRR4Counter: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: 0)

    /// The number of calls before this one.
    func next() -> Int {
        storage.withLock { count in
            defer { count += 1 }
            return count
        }
    }
}

// MARK: - Assertions

/// XCTAssertThrowsError does not take async code, so this does its job for client errors.
func fhirR4AssertThrows(
    _ expected: FHIRR4Error,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: () async throws -> Void
) async {
    do {
        try await body()
        XCTFail("Expected \(expected), but nothing was thrown", file: file, line: line)
    } catch let error as FHIRR4Error {
        XCTAssertEqual(error, expected, file: file, line: line)
    } catch {
        XCTFail("Expected \(expected), but got \(error)", file: file, line: line)
    }
}
