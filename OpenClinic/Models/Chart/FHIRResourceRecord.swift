import Foundation
import SwiftData

/// The resource exactly as the server sent it, kept beside the chart rows mapped from it.
///
/// The chart shows mapped values, and mapping loses detail. Keeping the source resource
/// means any value can be traced to what the server said, and the chart can be mapped
/// again after the mapper improves without another download.
@Model
final class FHIRResourceRecord {
    /// `<server base>/<type>/<id>`, the same form chart rows use for `qualifiedID`.
    @Attribute(.unique) var qualifiedID: String
    var serverBase: String
    var resourceType: String
    var resourceID: String
    var versionID: String?
    var lastUpdated: Date?
    /// The FHIR id of the patient this resource belongs to.
    var patientResourceID: String
    @Attribute(.externalStorage) var json: Data
    var fetchedAt: Date
    /// True when a later sync no longer returned this resource.
    var isRemovedAtSource: Bool

    init(
        qualifiedID: String,
        serverBase: String,
        resourceType: String,
        resourceID: String,
        versionID: String? = nil,
        lastUpdated: Date? = nil,
        patientResourceID: String,
        json: Data,
        fetchedAt: Date = .now,
        isRemovedAtSource: Bool = false
    ) {
        self.qualifiedID = qualifiedID
        self.serverBase = serverBase
        self.resourceType = resourceType
        self.resourceID = resourceID
        self.versionID = versionID
        self.lastUpdated = lastUpdated
        self.patientResourceID = patientResourceID
        self.json = json
        self.fetchedAt = fetchedAt
        self.isRemovedAtSource = isRemovedAtSource
    }

    /// The stored JSON, indented for reading.
    var prettyPrintedJSON: String {
        guard let object = try? JSONSerialization.jsonObject(with: json),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return String(data: json, encoding: .utf8) ?? ""
        }
        return text
    }
}
