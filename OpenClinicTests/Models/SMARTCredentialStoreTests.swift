import XCTest
@testable import OpenClinic

final class SMARTCredentialStoreTests: XCTestCase {
    var store: SMARTCredentialStore!

    override func setUp() {
        store = InMemorySMARTCredentialStore()
    }

    func testSaveAndRead() throws {
        let response = SMARTTokenResponse(
            accessToken: "test_access",
            tokenType: "Bearer",
            expiresIn: 3600,
            scope: "patient/*.read",
            patient: "p1",
            idToken: nil,
            state: "abc",
            receivedAt: Date()
        )
        let baseURL = URL(string: "https://fhir.example.com")!
        let clientID = "my_client"

        let initial = try store.readTokenResponse(baseURL: baseURL, clientID: clientID)
        XCTAssertNil(initial)

        try store.saveTokenResponse(response, baseURL: baseURL, clientID: clientID)

        let retrieved = try store.readTokenResponse(baseURL: baseURL, clientID: clientID)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.accessToken, "test_access")
        XCTAssertEqual(retrieved?.patient, "p1")
    }

    func testMultiServerIsolation() throws {
        let response1 = SMARTTokenResponse(
            accessToken: "token_1",
            tokenType: "Bearer",
            expiresIn: 3600,
            scope: "patient/*.read",
            patient: "p1",
            idToken: nil,
            state: "abc",
            receivedAt: Date()
        )
        let response2 = SMARTTokenResponse(
            accessToken: "token_2",
            tokenType: "Bearer",
            expiresIn: 3600,
            scope: "patient/*.read",
            patient: "p2",
            idToken: nil,
            state: "xyz",
            receivedAt: Date()
        )

        let url1 = URL(string: "https://server1.com")!
        let url2 = URL(string: "https://server2.com")!
        let clientID = "client_abc"

        try store.saveTokenResponse(response1, baseURL: url1, clientID: clientID)
        try store.saveTokenResponse(response2, baseURL: url2, clientID: clientID)

        let read1 = try store.readTokenResponse(baseURL: url1, clientID: clientID)
        let read2 = try store.readTokenResponse(baseURL: url2, clientID: clientID)

        XCTAssertEqual(read1?.accessToken, "token_1")
        XCTAssertEqual(read2?.accessToken, "token_2")
    }

    func testDeletion() throws {
        let response = SMARTTokenResponse(
            accessToken: "test_access",
            tokenType: "Bearer",
            expiresIn: 3600,
            scope: "patient/*.read",
            patient: "p1",
            idToken: nil,
            state: "abc",
            receivedAt: Date()
        )
        let baseURL = URL(string: "https://fhir.example.com")!
        let clientID = "my_client"

        try store.saveTokenResponse(response, baseURL: baseURL, clientID: clientID)
        try store.deleteTokenResponse(baseURL: baseURL, clientID: clientID)

        let read = try store.readTokenResponse(baseURL: baseURL, clientID: clientID)
        XCTAssertNil(read)
    }
}
