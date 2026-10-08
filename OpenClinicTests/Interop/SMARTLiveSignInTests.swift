import Foundation
import XCTest
@testable import OpenClinic

/// A real SMART on FHIR sign-in against a server that requires authorization: the SMART Health IT
/// launcher (launch.smarthealthit.org, synthetic patients). It runs the app's own code for
/// discovery, the PKCE authorization request, the token exchange, an authorized FHIR read and the
/// refresh-token exchange. No password is involved: the launcher is told, in the address, which
/// practitioner and patient to use and to skip its sign-in and approval screens.
///
/// What this server cannot show: it answers a FHIR read that carries no token, and asking it to act
/// out an expired token ("request_expired_token") changed nothing on 2026-10-07. A resource server
/// that refuses a request is therefore covered only by the stubbed tests in FHIRR4ClientTests.
///
/// It needs the network, so it runs only when asked:
///     ./Scripts/verify.sh live
/// (which sets TEST_RUNNER_OPENCLINIC_LIVE_SMART=1 for xcodebuild).
///
/// Launch options are encoded as the launcher's source defines them
/// (github.com/smart-on-fhir/smart-launcher-v2, src/isomorphic/codec.ts, read 2026-10-07).
final class SMARTLiveSignInTests: XCTestCase {
    private let openBase = URL(string: "https://launch.smarthealthit.org/v/r4/fhir")!
    private let redirectURI = URL(string: "medmod://smart-callback")!
    private let clientID = "openclinic-live-test"

    private func requireLive() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["OPENCLINIC_LIVE_SMART"] == "1",
            "Live SMART sign-in runs only with ./Scripts/verify.sh live"
        )
    }

    /// The launcher's address for one simulated sign-in: provider standalone launch, this patient
    /// and practitioner, no sign-in or approval screen, a public client, PKCE always checked.
    private func simulatedBase(patient: String, practitioner: String) throws -> URL {
        let options: [Any] = [
            2,              // launch type: provider-standalone
            patient,
            practitioner,
            "AUTO",         // encounter
            1,              // skip the sign-in screen
            1,              // skip the approval screen
            0,              // no simulated EHR frame
            "", "", "", "", "", "", "",
            0,              // client type: public
            2,              // PKCE validation: always
            "",
        ]
        let json = try JSONSerialization.data(withJSONObject: options)
        let encoded = json.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return try XCTUnwrap(URL(string: "https://launch.smarthealthit.org/v/r4/sim/\(encoded)/fhir"))
    }

    /// A patient and a practitioner that exist on the launcher today, read from its open endpoint.
    private func someoneOnTheLauncher(_ network: URLSession) async throws -> (patient: String, practitioner: String) {
        let open = FHIRR4Client(baseURL: openBase, session: network)
        let one = [URLQueryItem(name: "_count", value: "1")]
        let patients = try await open.search("Patient", parameters: one)
        let practitioners = try await open.search("Practitioner", parameters: one)
        return (try XCTUnwrap(patients.resources.first?.id), try XCTUnwrap(practitioners.resources.first?.id))
    }

    /// Sends the authorization request the way the system browser would, without following the
    /// answer, and returns where the server sent the browser.
    private func authorize(_ url: URL, session: URLSession) async throws -> URL {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (_, response) = try await session.data(for: request, delegate: StayPut())
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertTrue((300..<400).contains(http.statusCode), "The authorization endpoint answered \(http.statusCode), not a redirect")
        let location = try XCTUnwrap(http.value(forHTTPHeaderField: "Location"), "No Location header")
        return try XCTUnwrap(URL(string: location, relativeTo: url)?.absoluteURL)
    }

    @MainActor
    func testStandaloneSignInTokenExchangeAuthorizedReadAndRefresh() async throws {
        try requireLive()
        let network = URLSession(configuration: .ephemeral)

        let (patientID, practitionerID) = try await someoneOnTheLauncher(network)
        let base = try simulatedBase(patient: patientID, practitioner: practitionerID)

        // 1. Discovery, through the app's session.
        let session = SMARTSession(urlSession: network)
        let configuration = try await session.discoverConfiguration(baseURL: base)
        XCTAssertEqual(configuration.codeChallengeMethodsSupported?.contains("S256"), true)

        // 2. The authorization request the app would open, with its default scopes plus a refresh token.
        let authorization = try session.makeAuthorizationRequest(
            clientID: clientID,
            redirectURI: redirectURI,
            fhirBaseURL: base,
            scope: SMARTScopeSet.providerRead + ["offline_access"]
        )
        let callback = try await authorize(authorization.url, session: network)
        XCTAssertEqual(callback.scheme, redirectURI.scheme, "The server sent the browser to \(callback.host() ?? "?") instead of back to the app")

        // 3. The callback is checked (state) and its code exchanged with the PKCE verifier.
        let code = try SMARTSession.authorizationCode(from: callback, expectedState: authorization.state)
        let token = try await session.exchangeCodeForToken(
            code: code,
            codeVerifier: authorization.codeVerifier,
            clientID: clientID,
            redirectURI: redirectURI
        )
        XCTAssertFalse(token.accessToken.isEmpty)
        XCTAssertEqual(token.patient, patientID, "The token names the patient the launch chose")
        XCTAssertNotNil(token.refreshToken, "offline_access was asked for, so a refresh token is expected")
        XCTAssertTrue(session.isAuthorized)

        // 4. An authorized read and search through the FHIR client, with the bearer token.
        let accessToken = token.accessToken
        let authorized = FHIRR4Client(baseURL: base, session: network, tokenProvider: { _ in accessToken })
        let patient = try await authorized.read("Patient", id: patientID)
        XCTAssertEqual(patient.id, patientID)
        let fetched = try await FHIRR4ChartFetcher(client: authorized).fetchChart(patientID: patientID)
        XCTAssertTrue(fetched.chart.failedTypes.isEmpty, "Every resource type was readable with the granted scopes: \(fetched.chart.warnings)")

        // 5. The same read without a token, to record whether this server refuses it.
        let anonymous = FHIRR4Client(baseURL: base, session: network)
        var anonymousOutcome = "allowed"
        do {
            _ = try await anonymous.read("Patient", id: patientID)
        } catch {
            anonymousOutcome = "refused (\(error.localizedDescription))"
        }

        // 6. The refresh-token exchange.
        let refreshed = try await session.refreshAccessToken(clientID: clientID)
        XCTAssertFalse(refreshed.accessToken.isEmpty)
        XCTAssertEqual(refreshed.patient, patientID, "The patient context survives a refresh")

        print("SMART LIVE: sign-in ok | patient in token: \(token.patient != nil) | refresh token issued: \(token.refreshToken != nil) | resources read with the token: \(fetched.rawResources.count) | types failed: \(fetched.chart.failedTypes.count) | read without a token: \(anonymousOutcome) | refresh ok: \(!refreshed.accessToken.isEmpty)")
    }

    /// PKCE has to be checked by the server for it to protect anything: a code exchanged with a
    /// verifier that does not match the challenge must be refused.
    @MainActor
    func testACodeExchangedWithTheWrongVerifierIsRefused() async throws {
        try requireLive()
        let network = URLSession(configuration: .ephemeral)
        let (patientID, practitionerID) = try await someoneOnTheLauncher(network)
        let base = try simulatedBase(patient: patientID, practitioner: practitionerID)

        let session = SMARTSession(urlSession: network)
        _ = try await session.discoverConfiguration(baseURL: base)
        let authorization = try session.makeAuthorizationRequest(clientID: clientID, redirectURI: redirectURI, fhirBaseURL: base)
        let callback = try await authorize(authorization.url, session: network)
        let code = try SMARTSession.authorizationCode(from: callback, expectedState: authorization.state)

        do {
            _ = try await session.exchangeCodeForToken(
                code: code,
                codeVerifier: String(repeating: "x", count: 64),
                clientID: clientID,
                redirectURI: redirectURI
            )
            XCTFail("The server accepted a code with the wrong PKCE verifier")
        } catch let error as SMARTSessionError {
            guard case .tokenExchangeRejected = error else { return XCTFail("Expected a rejected exchange, got \(error)") }
            print("SMART LIVE: wrong PKCE verifier refused: \(error.localizedDescription)")
        }
        XCTAssertFalse(session.isAuthorized)
    }
}

/// Lets a test read a redirect instead of following it.
private final class StayPut: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
