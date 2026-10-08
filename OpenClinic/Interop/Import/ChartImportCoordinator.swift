//
//  ChartImportCoordinator.swift
//  OpenClinic
//
//  Runs one record import from start to finish: read the patient's resources
//  from a FHIR R4 server, apply them to the local store, then index the new
//  chart rows for retrieval. Views watch `phase` to show progress.
//

import Foundation
import Observation
import SwiftData
import os

/// A patient found on a server, before anything is imported.
nonisolated struct RemotePatientSummary: Sendable, Identifiable, Hashable {
    /// The patient's resource id on the server.
    let id: String
    let name: String
    let sex: String
    let birthDate: Date?
    let isDeceased: Bool
}

@MainActor
@Observable
final class ChartImportCoordinator {
    enum Phase: Equatable {
        case idle
        case fetching(resourceType: String, completedTypes: Int, totalTypes: Int)
        case saving
        case indexing
        case finished
        case failed(String)
    }

    /// An ephemeral session keeps no cache, cookies or credentials on disk, so a FHIR response
    /// exists only in memory until the importer stores it.
    private static let session = URLSession(configuration: .ephemeral)

    private(set) var phase: Phase = .idle
    private(set) var lastSummary: ChartImportSummary?

    var isImporting: Bool {
        switch phase {
        case .fetching, .saving, .indexing: return true
        case .idle, .finished, .failed: return false
        }
    }

    /// A short line for a progress label.
    var statusText: String {
        switch phase {
        case .idle: return ""
        case .fetching(let resourceType, let completed, let total):
            return "Reading \(resourceType) (\(completed) of \(total) resource types done)"
        case .saving: return "Saving to the chart"
        case .indexing: return "Indexing for chart questions"
        case .finished: return "Import complete"
        case .failed(let message): return message
        }
    }

    /// Imports one patient's record. Returns nil when the import failed or was cancelled;
    /// `phase` then says why.
    @discardableResult
    func importChart(
        patientID: String,
        baseURL: URL,
        tokenProvider: @escaping FHIRR4Client.TokenProvider = { _ in nil },
        context: ModelContext
    ) async -> ChartImportSummary? {
        guard !isImporting else { return nil }

        let totalTypes = FHIRR4ChartFetcher.patientResourceTypes.count
        phase = .fetching(resourceType: "Patient", completedTypes: 0, totalTypes: totalTypes)

        let client = FHIRR4Client(baseURL: baseURL, session: Self.session, tokenProvider: tokenProvider)
        let fetcher = FHIRR4ChartFetcher(client: client)

        do {
            let fetched = try await fetcher.fetchChart(patientID: patientID) { [weak self] progress in
                await self?.report(progress)
            }

            // Every search failing is a failed import, not a chart with ten empty lists.
            if fetched.chart.failedTypes.count >= FHIRR4ChartFetcher.patientResourceTypes.count {
                throw ChartImportError.nothingCouldBeRead
            }

            phase = .saving
            let summary = try ChartImportApplier(context: context).apply(fetched.chart, sourceResources: fetched.rawResources)

            phase = .indexing
            let importedID = summary.patientLocalID
            let imported = try? context.fetch(FetchDescriptor<PatientProfile>(predicate: #Predicate { $0.id == importedID })).first
            if let imported {
                await ClinicalRAGService.shared.indexPatient(imported)
            } else {
                await ClinicalRAGService.shared.indexAllData(modelContext: context)
            }

            lastSummary = summary
            phase = .finished
            AppLogger.smart.info("Record import finished: \(summary.totalReceived) facts, \(summary.sourceResourceCount) resources, \(summary.warnings.count) warnings")
            return summary
        } catch is CancellationError {
            phase = .idle
            return nil
        } catch {
            // The log entry names the kind of failure. It never holds a response body.
            context.insert(AuditEvent(
                action: .recordImportFailed,
                entityType: "FHIRImport",
                entityID: "\(baseURL.absoluteString)/Patient/\(patientID)",
                detail: String(describing: type(of: error))
            ))
            try? context.save()
            phase = .failed(error.localizedDescription)
            return nil
        }
    }

    /// Finds patients on the server by name. An empty name returns the server's first page.
    func findPatients(
        named name: String,
        baseURL: URL,
        tokenProvider: @escaping FHIRR4Client.TokenProvider = { _ in nil }
    ) async throws -> [RemotePatientSummary] {
        var configuration = FHIRR4Client.Configuration()
        configuration.pageSize = 25
        configuration.maxPages = 1
        let client = FHIRR4Client(baseURL: baseURL, session: Self.session, configuration: configuration, tokenProvider: tokenProvider)

        var parameters: [URLQueryItem] = []
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            parameters.append(URLQueryItem(name: "name", value: trimmed))
        }

        let serverBase = client.baseURL.absoluteString
        let result = try await client.search("Patient", parameters: parameters)
        return result.resources.compactMap { resource in
            guard let patient = try? FHIRR4ChartMapper.patient(resource, serverBase: serverBase, calendar: .current) else { return nil }
            return RemotePatientSummary(
                id: patient.source.resourceID,
                name: "\(patient.givenName) \(patient.familyName)".trimmingCharacters(in: .whitespaces),
                sex: patient.sex,
                birthDate: patient.birthDate,
                isDeceased: patient.deceasedDate != nil
            )
        }
    }

    func reset() {
        guard !isImporting else { return }
        phase = .idle
    }

    private func report(_ progress: FHIRR4ChartFetcher.Progress) {
        guard case .fetching = phase else { return }
        phase = .fetching(
            resourceType: progress.resourceType,
            completedTypes: progress.completedTypes,
            totalTypes: progress.totalTypes
        )
    }
}
