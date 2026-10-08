import Foundation
import SwiftData

/// A clinical document from another system, such as a progress note. Mirrors a FHIR DocumentReference.
@Model
final class ChartDocument {
    /// Server-qualified resource URL for imported rows, `local/<uuid>` otherwise.
    @Attribute(.unique) var qualifiedID: String
    var typeDisplay: String
    var summary: String?
    var documentDate: Date?
    var author: String?
    var status: String
    var contentType: String?
    /// Plain text of the document, when it could be read.
    var text: String?
    /// True when a later sync no longer returned this row. Kept, and shown as such, instead of deleted.
    var isRemovedAtSource: Bool
    var sourceKind: String
    var sourceSystemName: String?
    var sourceRecordIdentifier: String?
    var sourceLastSyncedAt: Date?
    var sourceOfTruth: Bool
    var patient: PatientProfile?

    init(
        qualifiedID: String,
        typeDisplay: String,
        summary: String? = nil,
        documentDate: Date? = nil,
        author: String? = nil,
        status: String = "current",
        contentType: String? = nil,
        text: String? = nil,
        isRemovedAtSource: Bool = false,
        sourceKind: String = ClinicalSourceKind.manualEntry.rawValue,
        sourceSystemName: String? = nil,
        sourceRecordIdentifier: String? = nil,
        sourceLastSyncedAt: Date? = nil,
        sourceOfTruth: Bool = false
    ) {
        self.qualifiedID = qualifiedID
        self.typeDisplay = typeDisplay
        self.summary = summary
        self.documentDate = documentDate
        self.author = author
        self.status = status
        self.contentType = contentType
        self.text = text
        self.isRemovedAtSource = isRemovedAtSource
        self.sourceKind = sourceKind
        self.sourceSystemName = sourceSystemName
        self.sourceRecordIdentifier = sourceRecordIdentifier
        self.sourceLastSyncedAt = sourceLastSyncedAt
        self.sourceOfTruth = sourceOfTruth
    }
}
