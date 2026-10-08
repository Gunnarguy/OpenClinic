//
//  FHIRR4RawResource.swift
//  OpenClinic
//
//  A resource exactly as the server sent it, and the search Bundle it arrived
//  in. The JSON is kept so the importer can store it beside the mapped chart
//  and map it again later without another request. Both are read with
//  JSONSerialization: a Bundle holds resources of any type, and the typed
//  structs keep only the fields the chart uses.
//

import Foundation

/// One resource as received: who it is, which version, and its JSON.
nonisolated struct FHIRR4RawResource: Sendable, Hashable {
    let resourceType: String
    let id: String
    let versionID: String?
    let lastUpdated: Date?
    /// The resource serialized again with sorted keys, so equal resources have equal bytes.
    let json: Data

    /// Throws `FHIRR4Error.invalidResponse` when the object has no `resourceType` or `id`.
    init(jsonObject: [String: Any]) throws {
        // The validity check comes first because JSONSerialization raises an
        // Objective-C exception, not a Swift error, for an object it cannot write.
        guard let resourceType = jsonObject["resourceType"] as? String, !resourceType.isEmpty,
              let id = jsonObject["id"] as? String, !id.isEmpty,
              JSONSerialization.isValidJSONObject(jsonObject) else {
            throw FHIRR4Error.invalidResponse
        }
        let meta = jsonObject["meta"] as? [String: Any]

        self.resourceType = resourceType
        self.id = id
        self.versionID = FHIRR4Text.nonEmpty(meta?["versionId"] as? String)
        self.lastUpdated = (meta?["lastUpdated"] as? String).flatMap { FHIRR4DateTime($0)?.date }
        self.json = try JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys])
    }

    init(data: Data) throws {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw FHIRR4Error.invalidResponse
        }
        try self.init(jsonObject: object)
    }

    /// Decodes the JSON into a typed resource. The calendar's time zone places
    /// date-only values such as a date of birth; see `FHIRR4DateTime`.
    func decode<T: Decodable>(_ type: T.Type, calendar: Calendar = FHIRR4DateTime.defaultCalendar) throws -> T {
        let decoder = JSONDecoder()
        if let key = FHIRR4DateTime.calendarUserInfoKey {
            decoder.userInfo[key] = calendar
        }
        return try decoder.decode(type, from: json)
    }
}

/// One page of a search.
nonisolated struct FHIRR4Bundle: Sendable {
    let total: Int?
    /// The server's link to the following page, exactly as sent. The client decides whether to follow it.
    let nextLink: URL?
    let resources: [FHIRR4RawResource]

    /// Throws `FHIRR4Error.invalidResponse` when the data is not a FHIR Bundle.
    init(data: Data) throws {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              root["resourceType"] as? String == "Bundle" else {
            throw FHIRR4Error.invalidResponse
        }

        total = root["total"] as? Int

        let links = (root["link"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        nextLink = links
            .first { $0["relation"] as? String == "next" }
            .flatMap { $0["url"] as? String }
            .flatMap { URL(string: $0) }

        // An entry can be a search outcome with no resource, and a server can put an
        // OperationOutcome among the matches to explain itself. Neither is chart data.
        let entries = (root["entry"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        resources = entries.compactMap { entry in
            guard let resource = entry["resource"] as? [String: Any],
                  resource["resourceType"] as? String != "OperationOutcome" else {
                return nil
            }
            return try? FHIRR4RawResource(jsonObject: resource)
        }
    }
}
