//
//  FHIRR4ChartFetcher.swift
//  OpenClinic
//
//  Reads one patient's whole chart from a FHIR R4 server: the Patient resource,
//  then one search per kind of record. A server that refuses one kind (many do
//  not serve appointments, for instance) still gives up the rest, and the chart
//  says which kinds are missing so an empty list is never mistaken for "none".
//

import Foundation

nonisolated struct FHIRR4ChartFetcher: Sendable {
    nonisolated struct Progress: Sendable {
        /// The resource type whose search just ended.
        let resourceType: String
        /// How many resources that search returned; zero when it failed.
        let fetched: Int
        let completedTypes: Int
        let totalTypes: Int
    }

    /// Everything searched by `patient=<id>`, in the order the chart lists it.
    static let patientResourceTypes: [String] = [
        "Condition", "MedicationRequest", "AllergyIntolerance", "Observation", "Encounter",
        "Procedure", "Immunization", "DiagnosticReport", "DocumentReference", "Appointment",
    ]

    /// Enough to keep an import quick without leaning on a shared server.
    private static let simultaneousSearches = 3

    private nonisolated struct Outcome: Sendable {
        let resourceType: String
        let result: Result<FHIRR4SearchResult, any Error>
    }

    private let client: FHIRR4Client

    init(client: FHIRR4Client) {
        self.client = client
    }

    /// Reads the Patient, then searches every type with `patient=<id>`, at most 3 searches at a time.
    /// A type that fails adds a warning and the rest continue; only a failed Patient read throws.
    ///
    /// Runs off the caller's actor: mapping a long chart is too much work for the main actor.
    @concurrent
    func fetchChart(
        patientID: String,
        calendar: Calendar = .current,
        onProgress: (@Sendable (Progress) async -> Void)? = nil
    ) async throws -> (chart: ImportedChart, rawResources: [FHIRR4RawResource]) {
        let patient = try await client.read(FHIRR4Patient.resourceType, id: patientID)
        let types = Self.patientResourceTypes
        let client = self.client

        let outcomes = await withTaskGroup(of: Outcome.self, returning: [String: Outcome].self) { group in
            var waiting = types.makeIterator()
            var finished: [String: Outcome] = [:]

            for _ in 0..<Self.simultaneousSearches {
                guard let type = waiting.next() else { break }
                group.addTask { await Self.search(type, patientID: patientID, client: client) }
            }
            // Each search that ends makes room for the next, so no more than the limit run at once.
            for await outcome in group {
                finished[outcome.resourceType] = outcome
                var fetched = 0
                if case .success(let result) = outcome.result {
                    fetched = result.resources.count
                }
                await onProgress?(Progress(
                    resourceType: outcome.resourceType,
                    fetched: fetched,
                    completedTypes: finished.count,
                    totalTypes: types.count
                ))
                if let type = waiting.next() {
                    group.addTask { await Self.search(type, patientID: patientID, client: client) }
                }
            }
            return finished
        }

        // A cancelled import must not come back looking like a chart whose searches all failed.
        try Task.checkCancellation()

        var fetched: [FHIRR4RawResource] = []
        var warnings: [String] = []
        var truncatedTypes: [String] = []
        var failedTypes: [String] = []
        for type in types {
            switch outcomes[type]?.result {
            case .success(let result):
                fetched.append(contentsOf: result.resources)
                if result.truncated {
                    truncatedTypes.append(type)
                    let pages = result.pagesFetched == 1 ? "1 page" : "\(result.pagesFetched) pages"
                    warnings.append("\(type): the search stopped at the page limit after \(pages), so the list may be incomplete.")
                }
            case .failure(let error):
                failedTypes.append(type)
                warnings.append("\(type) could not be read: \(error.localizedDescription)")
            case .none:
                failedTypes.append(type)
                warnings.append("\(type) could not be read.")
            }
        }

        var chart = try FHIRR4ChartMapper.chart(
            patient: patient,
            resources: fetched,
            serverBase: client.baseURL.absoluteString,
            calendar: calendar
        )
        chart.warnings = warnings + chart.warnings
        chart.truncatedTypes = truncatedTypes
        chart.failedTypes = failedTypes
        return (chart, [patient] + fetched)
    }

    /// One type's search, with its failure caught so the other types carry on.
    private static func search(_ resourceType: String, patientID: String, client: FHIRR4Client) async -> Outcome {
        do {
            let result = try await client.search(resourceType, parameters: [URLQueryItem(name: "patient", value: patientID)])
            return Outcome(resourceType: resourceType, result: .success(result))
        } catch {
            return Outcome(resourceType: resourceType, result: .failure(error))
        }
    }
}
