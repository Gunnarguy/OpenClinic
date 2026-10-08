import XCTest
@testable import OpenClinic

/// The parts of the SMART sign-in that need no server: what is asked for, and what a callback must
/// carry before its code is used.
final class SMARTSessionTests: XCTestCase {
    private let callback = "medmod://smart-callback"

    func testACallbackWithTheRightStateGivesItsCode() throws {
        let url = try XCTUnwrap(URL(string: "\(callback)?code=abc123&state=expected"))
        XCTAssertEqual(try SMARTSession.authorizationCode(from: url, expectedState: "expected"), "abc123")
    }

    func testACallbackWithAnotherStateIsRefused() throws {
        let url = try XCTUnwrap(URL(string: "\(callback)?code=abc123&state=someone-elses"))
        XCTAssertThrowsError(try SMARTSession.authorizationCode(from: url, expectedState: "expected")) { error in
            guard case SMARTSessionError.redirectStateMismatch = error else { return XCTFail("got \(error)") }
        }
    }

    /// The state ties the code to this sign-in. A callback that leaves it out proves nothing.
    func testACallbackWithNoStateIsRefused() throws {
        let url = try XCTUnwrap(URL(string: "\(callback)?code=abc123"))
        XCTAssertThrowsError(try SMARTSession.authorizationCode(from: url, expectedState: "expected")) { error in
            guard case SMARTSessionError.redirectStateMismatch = error else { return XCTFail("got \(error)") }
        }
    }

    func testAnAuthorizationErrorIsReportedInTheServersWords() throws {
        let url = try XCTUnwrap(URL(string: "\(callback)?error=access_denied&error_description=The%20user%20said%20no&state=expected"))
        XCTAssertThrowsError(try SMARTSession.authorizationCode(from: url, expectedState: "expected")) { error in
            guard case let SMARTSessionError.authorizationDenied(code, description) = error else { return XCTFail("got \(error)") }
            XCTAssertEqual(code, "access_denied")
            XCTAssertEqual(description, "The user said no")
        }
    }

    func testACallbackWithNoCodeIsRefused() throws {
        let url = try XCTUnwrap(URL(string: "\(callback)?state=expected"))
        XCTAssertThrowsError(try SMARTSession.authorizationCode(from: url, expectedState: "expected")) { error in
            guard case SMARTSessionError.redirectMissingCode = error else { return XCTFail("got \(error)") }
        }
    }

    /// A server that enforces scopes refuses a search the token does not cover, so the scopes asked
    /// for have to cover every resource type the import reads.
    func testTheRequestedScopesCoverEveryTypeTheImportReads() {
        let scopes = Set(SMARTScopeSet.providerRead)
        for type in ["Patient"] + FHIRR4ChartFetcher.patientResourceTypes {
            XCTAssertTrue(scopes.contains("user/\(type).rs"), "no scope for \(type)")
        }
    }

    @MainActor
    func testTheLaunchScopeIsSentOnlyWithALaunchToken() async throws {
        // Discovery is answered by the stub, so the request is built by the same code the app runs.
        FHIRR4StubProtocol.install { _ in
            FHIRR4StubProtocol.Response(body: Data("""
            {"authorization_endpoint":"https://ehr.example/auth/authorize","token_endpoint":"https://ehr.example/auth/token"}
            """.utf8))
        }
        defer { FHIRR4StubProtocol.reset() }
        let session = SMARTSession(urlSession: FHIRR4StubProtocol.session())
        let base = try XCTUnwrap(URL(string: "https://ehr.example/fhir"))
        _ = try await session.discoverConfiguration(baseURL: base)
        XCTAssertEqual(FHIRR4StubProtocol.requests.first?.url?.absoluteString, "https://ehr.example/fhir/.well-known/smart-configuration")
        let redirect = try XCTUnwrap(URL(string: callback))

        let standalone = try session.makeAuthorizationRequest(clientID: "app", redirectURI: redirect, fhirBaseURL: base)
        XCTAssertFalse(standalone.requestedScope.split(separator: " ").contains("launch"))
        XCTAssertTrue(standalone.requestedScope.contains("launch/patient"))

        let fromEHR = try session.makeAuthorizationRequest(clientID: "app", redirectURI: redirect, fhirBaseURL: base, launch: "token")
        XCTAssertTrue(fromEHR.requestedScope.split(separator: " ").contains("launch"))

        // PKCE: a 64-character verifier and an S256 challenge in the address.
        XCTAssertEqual(standalone.codeVerifier.count, 64)
        let query = URLComponents(url: standalone.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(query.first { $0.name == "code_challenge_method" }?.value, "S256")
        XCTAssertEqual(query.first { $0.name == "code_challenge" }?.value, standalone.codeChallenge)
        XCTAssertEqual(query.first { $0.name == "state" }?.value, standalone.state)
    }

    // MARK: - Redirects

    /// A 307 on the token request would post the code and the verifier again to wherever it points.
    @MainActor
    func testATokenRequestNeverFollowsARedirect() async throws {
        let elsewhere = try XCTUnwrap(URL(string: "https://elsewhere.example/token"))
        FHIRR4StubProtocol.install { request in
            switch (request.url?.host, request.url?.path) {
            case ("ehr.example", "/fhir/.well-known/smart-configuration"):
                return FHIRR4StubProtocol.Response(body: Data("""
                {"authorization_endpoint":"https://ehr.example/auth/authorize","token_endpoint":"https://ehr.example/auth/token"}
                """.utf8))
            case ("ehr.example", _):
                return FHIRR4StubProtocol.Response(status: 307, redirect: elsewhere)
            default:
                return FHIRR4StubProtocol.Response(body: Data(#"{"access_token":"stolen","token_type":"Bearer","expires_in":3600}"#.utf8))
            }
        }
        defer { FHIRR4StubProtocol.reset() }
        let session = SMARTSession(urlSession: FHIRR4StubProtocol.session())
        _ = try await session.discoverConfiguration(baseURL: try XCTUnwrap(URL(string: "https://ehr.example/fhir")))

        do {
            _ = try await session.exchangeCodeForToken(
                code: "code", codeVerifier: "verifier", clientID: "app", redirectURI: try XCTUnwrap(URL(string: callback)))
            XCTFail("the redirect was followed")
        } catch {
            guard case SMARTSessionError.redirectRefused = error else { return XCTFail("got \(error)") }
        }

        XCTAssertFalse(session.isAuthorized)
        XCTAssertFalse(FHIRR4StubProtocol.requests.contains { $0.url?.host == "elsewhere.example" },
                       "the code and the verifier never reached the other server")
    }

    /// The discovery document names where the sign-in and the code are sent, so it is read only from
    /// the server that was asked.
    @MainActor
    func testDiscoveryDoesNotFollowARedirectToAnotherServer() async throws {
        let elsewhere = try XCTUnwrap(URL(string: "https://elsewhere.example/.well-known/smart-configuration"))
        FHIRR4StubProtocol.install { request in
            request.url?.host == "elsewhere.example"
                ? FHIRR4StubProtocol.Response(body: Data("""
                {"authorization_endpoint":"https://elsewhere.example/authorize","token_endpoint":"https://elsewhere.example/token"}
                """.utf8))
                : FHIRR4StubProtocol.Response(status: 302, redirect: elsewhere)
        }
        defer { FHIRR4StubProtocol.reset() }
        let session = SMARTSession(urlSession: FHIRR4StubProtocol.session())

        do {
            _ = try await session.discoverConfiguration(baseURL: try XCTUnwrap(URL(string: "https://ehr.example/fhir")))
            XCTFail("the redirect was followed")
        } catch {
            guard case SMARTSessionError.redirectRefused = error else { return XCTFail("got \(error)") }
        }
        XCTAssertNil(session.configuration)
        XCTAssertEqual(FHIRR4StubProtocol.requests.map { $0.url?.host }, ["ehr.example"])
    }
}
