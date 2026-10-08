//
//  FHIRR4Client.swift
//  OpenClinic
//
//  Reads from one FHIR R4 server: a single resource, or a search followed
//  across its pages. The client owns the rules that keep a read safe and
//  polite: a bearer token goes to the configured server and nowhere else,
//  an expired token is refreshed once, and a busy server is retried with a
//  growing wait. It knows nothing about charts or persistence.
//

import Foundation
import os

// Request URLs are logged at debug level only and bodies never: both are patient data.
nonisolated private let fhirR4Log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.openclinic", category: "FHIR")

nonisolated enum FHIRR4Error: Error, LocalizedError, Sendable, Equatable {
    case invalidResponse
    /// 401 after the one retry with a fresh token.
    case unauthorized
    /// Any other error status. The message is the OperationOutcome's when there is one.
    case server(status: Int, message: String)
    /// A paging link that points at another host. Carries that host, never the full link.
    case nextLinkOutsideServer(String)
    /// An HTTP redirect to another host, which was not followed. Carries that host only.
    case redirectOutsideServer(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server sent something that is not a FHIR resource."
        case .unauthorized:
            return "The server did not accept the sign-in. Connect to the server again."
        case .server(let status, let message):
            return "The server answered with status \(status): \(message)"
        case .nextLinkOutsideServer(let host):
            return "The server pointed to a different address (\(host)) for the next page, so the read stopped."
        case .redirectOutsideServer(let host):
            return "The server redirected the request to a different address (\(host)), so the read stopped."
        case .transport(let message):
            return message
        }
    }
}

/// Decides, for one request, whether an HTTP redirect may be followed. URLSession follows every
/// redirect unless a delegate says otherwise, and the request it would repeat carries the token.
nonisolated final class FHIRR4RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let base: URL
    private let refused = OSAllocatedUnfairLock<String?>(initialState: nil)

    init(base: URL) {
        self.base = base
    }

    /// The scheme, host and port of a redirect that was refused, when there was one.
    var refusedOrigin: String? {
        refused.withLock { $0 }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let target = request.url, FHIRR4Client.isSameServer(target, as: base) else {
            let origin = request.url.map(FHIRR4Client.origin(of:)) ?? "an address with no host"
            refused.withLock { $0 = origin }
            // nil ends the request with the redirect response itself as its answer.
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

nonisolated struct FHIRR4SearchResult: Sendable {
    let resources: [FHIRR4RawResource]
    let pagesFetched: Int
    let total: Int?
    /// True when the page limit stopped the search before the server ran out of pages.
    let truncated: Bool
}

actor FHIRR4Client {
    nonisolated struct Configuration: Sendable {
        var pageSize = 100
        var maxPages = 40
        var maxRetries = 3
        var baseBackoff: Duration = .milliseconds(500)
        var requestTimeout: TimeInterval = 30
    }

    /// `forceRefresh` is true on the single retry after a 401. Returning nil sends no Authorization header (open servers).
    typealias TokenProvider = @Sendable (_ forceRefresh: Bool) async throws -> String?
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    /// Normalized: no trailing slash, no query.
    nonisolated let baseURL: URL

    private let session: URLSession
    private let configuration: Configuration
    private let tokenProvider: TokenProvider
    private let sleeper: Sleeper

    /// Statuses that mean "try again shortly", not "this request is wrong".
    private static let retryableStatuses: Set<Int> = [429, 502, 503, 504]
    private static let retryableTransportCodes: Set<URLError.Code> = [.timedOut, .networkConnectionLost]
    /// No wait is longer than this, whatever the server asks for.
    private static let longestWait: Duration = .seconds(30)
    private static let longestMessage = 300
    /// RFC 3986 unreserved characters: everything else in a path segment is escaped.
    private static let pathSegmentAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    init(
        baseURL: URL,
        session: URLSession = .shared,
        configuration: Configuration = Configuration(),
        tokenProvider: @escaping TokenProvider = { _ in nil },
        sleeper: @escaping Sleeper = { try await Task.sleep(for: $0) }
    ) {
        self.baseURL = Self.normalized(baseURL)
        self.session = session
        self.configuration = configuration
        self.tokenProvider = tokenProvider
        self.sleeper = sleeper
    }

    // MARK: - Reading

    func read(_ resourceType: String, id: String) async throws -> FHIRR4RawResource {
        let data = try await send(try url(path: [resourceType, id], query: []))
        let resource = try FHIRR4RawResource(data: data)
        guard resource.resourceType == resourceType else { throw FHIRR4Error.invalidResponse }
        return resource
    }

    func search(_ resourceType: String, parameters: [URLQueryItem]) async throws -> FHIRR4SearchResult {
        var query = parameters
        if !query.contains(where: { $0.name == "_count" }) {
            query.append(URLQueryItem(name: "_count", value: String(configuration.pageSize)))
        }

        var next: URL? = try url(path: [resourceType], query: query)
        var resources: [FHIRR4RawResource] = []
        // A resource can come back on two pages when the data changes mid-search.
        var seen = Set<String>()
        var pages = 0
        var total: Int?
        var truncated = false

        while let page = next {
            try Task.checkCancellation()
            guard pages < configuration.maxPages else {
                truncated = true
                break
            }

            let bundle = try FHIRR4Bundle(data: try await send(page))
            pages += 1
            total = total ?? bundle.total
            for resource in bundle.resources where seen.insert("\(resource.resourceType)/\(resource.id)").inserted {
                resources.append(resource)
            }

            next = nil
            if let linkText = bundle.nextLinkText {
                // A link that cannot be read must not end the search as if the server had run out of pages.
                // A relative link is read against the page it came on, as any link in an answer is.
                guard let link = URL(string: linkText, relativeTo: page)?.absoluteURL, link.host != nil else {
                    fhirR4Log.error("A paging link could not be read.")
                    throw FHIRR4Error.invalidResponse
                }
                // Checked before anything is sent: the next request carries the bearer token.
                guard Self.isSameServer(link, as: baseURL) else {
                    fhirR4Log.error("A paging link pointed outside the FHIR server and was not followed.")
                    throw FHIRR4Error.nextLinkOutsideServer(Self.origin(of: link))
                }
                next = link
            }
        }

        return FHIRR4SearchResult(resources: resources, pagesFetched: pages, total: total, truncated: truncated)
    }

    // MARK: - Requests

    /// Sends one GET and returns the body of a 2xx answer, after the retries the status allows.
    private func send(_ url: URL) async throws -> Data {
        var token = try await tokenProvider(false)
        var refreshedToken = false
        var retries = 0

        while true {
            try Task.checkCancellation()

            // Cached copies are never read: a chart import must show what the server holds now.
            var request = URLRequest(
                url: url,
                cachePolicy: .reloadIgnoringLocalCacheData,
                timeoutInterval: configuration.requestTimeout
            )
            request.httpMethod = "GET"
            request.setValue("application/fhir+json", forHTTPHeaderField: "Accept")
            if let token = FHIRR4Text.nonEmpty(token) {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            fhirR4Log.debug("GET \(url.absoluteString, privacy: .private)")

            let data: Data
            let response: URLResponse
            // The request carries the bearer token and the patient's id, so a redirect is followed
            // only when it stays on this server.
            let redirects = FHIRR4RedirectGuard(base: baseURL)
            let outcome: Result<(Data, URLResponse), any Error>
            do {
                outcome = .success(try await session.data(for: request, delegate: redirects))
            } catch {
                outcome = .failure(error)
            }
            // A refused redirect ends the request with the redirect response or with an error,
            // depending on who serves it. Either way it is reported as what it was.
            if let refused = redirects.refusedOrigin {
                fhirR4Log.error("A redirect pointed outside the FHIR server and was not followed.")
                throw FHIRR4Error.redirectOutsideServer(refused)
            }
            do {
                (data, response) = try outcome.get()
            } catch let error as URLError where error.code == .cancelled {
                // URLSession reports a cancelled task its own way; callers expect Swift's.
                try Task.checkCancellation()
                throw FHIRR4Error.transport(error.localizedDescription)
            } catch let error as URLError where Self.retryableTransportCodes.contains(error.code) {
                guard retries < configuration.maxRetries else {
                    throw FHIRR4Error.transport(error.localizedDescription)
                }
                try await pause(beforeRetry: retries, retryAfter: nil)
                retries += 1
                continue
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw FHIRR4Error.transport(error.localizedDescription)
            }

            guard let http = response as? HTTPURLResponse else { throw FHIRR4Error.invalidResponse }
            let status = http.statusCode
            if (200..<300).contains(status) {
                return data
            }

            if status == 401 {
                guard !refreshedToken else { throw FHIRR4Error.unauthorized }
                refreshedToken = true
                token = try await tokenProvider(true)
                continue
            }

            if Self.retryableStatuses.contains(status), retries < configuration.maxRetries {
                try await pause(beforeRetry: retries, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
                retries += 1
                continue
            }

            fhirR4Log.error("A FHIR request failed with status \(status, privacy: .public).")
            throw FHIRR4Error.server(status: status, message: Self.message(status: status, body: data, token: token))
        }
    }

    /// Waits before retry number `retry` (counted from zero): the server's `Retry-After`
    /// when it gives one in seconds, else the base wait doubled for each retry so far.
    private func pause(beforeRetry retry: Int, retryAfter: String?) async throws {
        var wait = configuration.baseBackoff * (1 << min(retry, 16))
        if let retryAfter, let seconds = Int(retryAfter.trimmingCharacters(in: .whitespaces)), seconds >= 0 {
            wait = .seconds(seconds)
        }
        wait = min(wait, Self.longestWait)
        fhirR4Log.notice("Retrying a FHIR request (retry \(retry + 1, privacy: .public)).")
        try await sleeper(wait)
    }

    // MARK: - URLs

    private func url(path: [String], query: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw FHIRR4Error.transport("The server address is not a usable URL.")
        }
        var encodedPath = components.percentEncodedPath
        for segment in path {
            // Escaping every segment keeps an id with a slash in it from naming another path.
            guard let encoded = segment.addingPercentEncoding(withAllowedCharacters: Self.pathSegmentAllowed),
                  !encoded.isEmpty else {
                throw FHIRR4Error.transport("The request names an empty resource type or id.")
            }
            encodedPath += "/" + encoded
        }
        components.percentEncodedPath = encodedPath

        if !query.isEmpty {
            components.queryItems = query
            // URLComponents leaves "+" as it is and servers read it as a space, which
            // breaks a search on a date with a "+hh:mm" offset.
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components.url else {
            throw FHIRR4Error.transport("The request URL could not be built.")
        }
        return url
    }

    /// The base URL without a trailing slash, query or fragment, with the scheme and host in lower
    /// case and no default port. Row identifiers are built from it, so one server must have one spelling.
    static func normalized(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url }
        components.query = nil
        components.fragment = nil
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if (components.scheme == "https" && components.port == 443) || (components.scheme == "http" && components.port == 80) {
            components.port = nil
        }
        var path = components.percentEncodedPath
        while path.hasSuffix("/") {
            path.removeLast()
        }
        components.percentEncodedPath = path
        return components.url ?? url
    }

    /// `normalized` for an address held as text. Text that is not a URL with a host only loses
    /// its surrounding white space and trailing slashes.
    static func normalizedBase(_ text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.host != nil {
            return normalized(url).absoluteString
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    /// True when `url` has the base URL's scheme, host and port. Only then may a paging
    /// link be followed. The path is not compared: the SMART sandbox pages from its root.
    static func isSameServer(_ url: URL, as base: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), let baseScheme = base.scheme?.lowercased(),
              scheme == baseScheme,
              let host = url.host(percentEncoded: false)?.lowercased(),
              let baseHost = base.host(percentEncoded: false)?.lowercased(),
              host == baseHost else {
            return false
        }
        return (url.port ?? defaultPort(for: scheme)) == (base.port ?? defaultPort(for: baseScheme))
    }

    private static func defaultPort(for scheme: String) -> Int? {
        switch scheme {
        case "https": return 443
        case "http": return 80
        default: return nil
        }
    }

    /// Scheme, host and port only. A paging link's query can hold search terms.
    static func origin(of url: URL) -> String {
        guard let scheme = url.scheme, let host = url.host(percentEncoded: false) else {
            return "an address with no host"
        }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }

    // MARK: - Errors

    /// What to tell a person about an error status: the OperationOutcome's own words when the
    /// server sent one, else the status's standard name. Any other body is never quoted: it can
    /// be an HTML page or part of a record, and these messages reach the screen and the log.
    private static func message(status: Int, body: Data, token: String?) -> String {
        var message = ""
        if let outcome = try? JSONDecoder().decode(FHIRR4OperationOutcome.self, from: body), outcome.isOperationOutcome {
            message = outcome.summary
        }
        if message.isEmpty {
            message = HTTPURLResponse.localizedString(forStatusCode: status)
        }
        // A server that echoes request headers must not get the token into an error.
        // This runs before the cut so that no part of a token survives at the end.
        if let token = FHIRR4Text.nonEmpty(token) {
            message = message.replacingOccurrences(of: token, with: "[token removed]")
        }
        return String(message.prefix(longestMessage))
    }
}
