import Foundation
import SwiftData

struct FHIRImportSummary: Sendable {
    let patientName: String
    let patientID: String
    let createdNewPatient: Bool
    let conditionCount: Int
    let medicationCount: Int
    let appointmentCount: Int
    let importedAt: Date
    let warnings: [String]
}

private struct FHIRBundle<Resource: Decodable>: Decodable {
    struct Entry: Decodable {
        let resource: Resource?
    }

    let entry: [Entry]?
}

@MainActor
final class FHIRImportService {
    private let client: FHIRClient

    init(client: FHIRClient) {
        self.client = client
    }

    func importPatientContext(patientID: String, baseURL: URL, modelContext: ModelContext) async throws -> FHIRImportSummary {
        let decoder = JSONDecoder()
        var warnings: [String] = []

        let patientData = try await client.fetchResource(resourceType: "Patient", id: patientID, baseURL: baseURL)
        let patientResource = try decoder.decode(FHIRPatientResource.self, from: patientData)
        let (patient, createdNewPatient) = try upsertPatient(from: patientResource, baseURL: baseURL, modelContext: modelContext)

        let conditionResources: [FHIRConditionResource] = await resilientBundleFetch(
            resourceType: "Condition",
            queryItems: [URLQueryItem(name: "patient", value: patientID)],
            baseURL: baseURL,
            decoder: decoder,
            warnings: &warnings
        )

        let medicationResources: [FHIRMedicationRequestResource] = await resilientBundleFetch(
            resourceType: "MedicationRequest",
            queryItems: [URLQueryItem(name: "patient", value: patientID)],
            baseURL: baseURL,
            decoder: decoder,
            warnings: &warnings
        )

        let appointmentResources: [FHIRAppointmentResource] = await resilientBundleFetch(
            resourceType: "Appointment",
            queryItems: [URLQueryItem(name: "actor", value: "Patient/\(patientID)")],
            baseURL: baseURL,
            decoder: decoder,
            warnings: &warnings
        )

        let allergyResources: [FHIRAllergyIntoleranceResource] = await resilientBundleFetch(
            resourceType: "AllergyIntolerance",
            queryItems: [URLQueryItem(name: "patient", value: patientID)],
            baseURL: baseURL,
            decoder: decoder,
            warnings: &warnings
        )

        let conditionCount = try syncConditions(conditionResources, to: patient, baseURL: baseURL, modelContext: modelContext, warnings: &warnings)
        let medicationCount = try syncMedications(medicationResources, to: patient, baseURL: baseURL, modelContext: modelContext, warnings: &warnings)
        let appointmentCount = try syncAppointments(appointmentResources, to: patient, baseURL: baseURL, modelContext: modelContext, warnings: &warnings)

        // Sync allergies
        let allergies = allergyResources.compactMap { $0.code?.preferredText }
        if !allergies.isEmpty {
            var current = patient.allergies
            for allergy in allergies {
                if !current.contains(allergy) {
                    current.append(allergy)
                }
            }
            patient.allergies = current
        }

        try modelContext.save()

        return FHIRImportSummary(
            patientName: patient.fullName,
            patientID: patientID,
            createdNewPatient: createdNewPatient,
            conditionCount: conditionCount,
            medicationCount: medicationCount,
            appointmentCount: appointmentCount,
            importedAt: .now,
            warnings: warnings
        )
    }

    private func resilientBundleFetch<Resource: Decodable>(
        resourceType: String,
        queryItems: [URLQueryItem],
        baseURL: URL,
        decoder: JSONDecoder,
        warnings: inout [String]
    ) async -> [Resource] {
        do {
            let data = try await client.search(resourceType: resourceType, queryItems: queryItems, baseURL: baseURL)
            let bundle = try decoder.decode(FHIRBundle<Resource>.self, from: data)
            return bundle.entry?.compactMap(\.resource) ?? []
        } catch {
            warnings.append("\(resourceType) import skipped: \(error.localizedDescription)")
            return []
        }
    }

    private func upsertPatient(from resource: FHIRPatientResource, baseURL: URL, modelContext: ModelContext) throws -> (PatientProfile, Bool) {
        let adapted = FHIRResourceAdapters.patient(from: resource, baseURL: baseURL)
        let existingPatients = try modelContext.fetch(FetchDescriptor<PatientProfile>())

        let matched = existingPatients.filter { existing in
            // Exact FHIR ID + Server URL match
            if existing.sourceRecordIdentifier == adapted.sourceRecordIdentifier &&
               existing.sourceSystemName == adapted.sourceSystemName {
                return true
            }
            
            // MRN + System match
            let existingMRN = existing.medicalRecordNumber
            let adaptedMRN = adapted.medicalRecordNumber
            if !existingMRN.isEmpty,
               !adaptedMRN.isEmpty,
               let existingSystem = existing.medicalRecordNumberSystem, !existingSystem.isEmpty,
               let adaptedSystem = adapted.medicalRecordNumberSystem, !adaptedSystem.isEmpty {
                return existingMRN == adaptedMRN && existingSystem == adaptedSystem
            }
            
            return false
        }

        if matched.count > 1 {
            throw PatientMatchingError.ambiguousMatches(
                message: "Multiple profiles matched for ID \(resource.id) and MRN \(adapted.medicalRecordNumber)."
            )
        }

        if let existing = matched.first {
            existing.firstName = adapted.firstName
            existing.lastName = adapted.lastName
            existing.dateOfBirth = adapted.dateOfBirth
            existing.gender = adapted.gender
            existing.emergencyContactName = adapted.emergencyContactName
            existing.emergencyContactPhone = adapted.emergencyContactPhone
            existing.sourceKind = adapted.sourceKind
            existing.sourceSystemName = adapted.sourceSystemName
            existing.sourceRecordIdentifier = adapted.sourceRecordIdentifier
            existing.sourceLastSyncedAt = adapted.sourceLastSyncedAt
            existing.sourceOfTruth = adapted.sourceOfTruth
            existing.medicalRecordNumberSystem = adapted.medicalRecordNumberSystem
            return (existing, false)
        }

        modelContext.insert(adapted)
        return (adapted, true)
    }

    private func syncConditions(
        _ resources: [FHIRConditionResource],
        to patient: PatientProfile,
        baseURL: URL,
        modelContext: ModelContext,
        warnings: inout [String]
    ) throws -> Int {
        if patient.clinicalRecords == nil {
            patient.clinicalRecords = []
        }

        let existingRecords = patient.clinicalRecords ?? []
        var existingRecordsDict = Dictionary(existingRecords.map { ($0.recordID, $0) }, uniquingKeysWith: { first, _ in first })

        var importedCount = 0
        var incomingSeenIDs = Set<String>()

        for resource in resources {
            let adapted = FHIRResourceAdapters.clinicalRecord(from: resource, baseURL: baseURL)
            
            if incomingSeenIDs.contains(adapted.recordID) {
                warnings.append("Duplicate Condition resource with ID \(resource.id) found in incoming feed.")
                continue
            }
            incomingSeenIDs.insert(adapted.recordID)

            if let existing = existingRecordsDict[adapted.recordID] {
                existing.dateRecorded = adapted.dateRecorded
                existing.conditionName = adapted.conditionName
                existing.status = adapted.status
                existing.documentationStatus = adapted.documentationStatus
                existing.documentationSignedAt = adapted.documentationSignedAt
                existing.sourceKind = adapted.sourceKind
                existing.sourceSystemName = adapted.sourceSystemName
                existing.sourceRecordIdentifier = adapted.sourceRecordIdentifier
                existing.sourceLastSyncedAt = adapted.sourceLastSyncedAt
                existing.sourceOfTruth = adapted.sourceOfTruth
                existing.patient = patient
                attach(existing, to: &patient.clinicalRecords)
            } else {
                adapted.patient = patient
                modelContext.insert(adapted)
                patient.clinicalRecords?.append(adapted)
                existingRecordsDict[adapted.recordID] = adapted
                importedCount += 1
            }
        }

        return importedCount
    }

    private func syncMedications(
        _ resources: [FHIRMedicationRequestResource],
        to patient: PatientProfile,
        baseURL: URL,
        modelContext: ModelContext,
        warnings: inout [String]
    ) throws -> Int {
        if patient.medications == nil {
            patient.medications = []
        }

        let existingMedications = patient.medications ?? []
        var existingMedicationsDict = Dictionary(existingMedications.map { ($0.rxID, $0) }, uniquingKeysWith: { first, _ in first })

        var importedCount = 0
        var incomingSeenIDs = Set<String>()

        for resource in resources {
            let adapted = FHIRResourceAdapters.medication(from: resource, baseURL: baseURL)
            
            if incomingSeenIDs.contains(adapted.rxID) {
                warnings.append("Duplicate MedicationRequest resource with ID \(resource.id) found in incoming feed.")
                continue
            }
            incomingSeenIDs.insert(adapted.rxID)

            if let existing = existingMedicationsDict[adapted.rxID] {
                existing.medicationName = adapted.medicationName
                existing.writtenBy = adapted.writtenBy
                existing.writtenDate = adapted.writtenDate
                existing.quantityInfo = adapted.quantityInfo
                existing.refills = adapted.refills
                existing.route = adapted.route
                existing.status = adapted.status
                existing.sourceKind = adapted.sourceKind
                existing.sourceSystemName = adapted.sourceSystemName
                existing.sourceRecordIdentifier = adapted.sourceRecordIdentifier
                existing.sourceLastSyncedAt = adapted.sourceLastSyncedAt
                existing.sourceOfTruth = adapted.sourceOfTruth
                existing.patient = patient
                attach(existing, to: &patient.medications)
            } else {
                adapted.patient = patient
                modelContext.insert(adapted)
                patient.medications?.append(adapted)
                existingMedicationsDict[adapted.rxID] = adapted
                importedCount += 1
            }
        }

        return importedCount
    }

    private func syncAppointments(
        _ resources: [FHIRAppointmentResource],
        to patient: PatientProfile,
        baseURL: URL,
        modelContext: ModelContext,
        warnings: inout [String]
    ) throws -> Int {
        if patient.appointments == nil {
            patient.appointments = []
        }

        let existingAppointments = patient.appointments ?? []
        var existingAppointmentsDict = Dictionary(existingAppointments.map { ($0.appointmentID, $0) }, uniquingKeysWith: { first, _ in first })

        var importedCount = 0
        var incomingSeenIDs = Set<String>()

        for resource in resources {
            let adapted = FHIRResourceAdapters.appointment(from: resource, baseURL: baseURL)
            
            if incomingSeenIDs.contains(adapted.appointmentID) {
                warnings.append("Duplicate Appointment resource with ID \(resource.id) found in incoming feed.")
                continue
            }
            incomingSeenIDs.insert(adapted.appointmentID)

            if let existing = existingAppointmentsDict[adapted.appointmentID] {
                existing.scheduledTime = adapted.scheduledTime
                existing.reasonForVisit = adapted.reasonForVisit
                existing.status = adapted.status
                existing.clinicianName = adapted.clinicianName
                existing.sourceKind = adapted.sourceKind
                existing.sourceSystemName = adapted.sourceSystemName
                existing.sourceRecordIdentifier = adapted.sourceRecordIdentifier
                existing.sourceLastSyncedAt = adapted.sourceLastSyncedAt
                existing.sourceOfTruth = adapted.sourceOfTruth
                existing.patient = patient
                attach(existing, to: &patient.appointments)
            } else {
                adapted.patient = patient
                modelContext.insert(adapted)
                patient.appointments?.append(adapted)
                existingAppointmentsDict[adapted.appointmentID] = adapted
                importedCount += 1
            }
        }

        return importedCount
    }

    private func attach<T: AnyObject & Identifiable>(_ object: T, to collection: inout [T]?) where T.ID: Equatable {
        if collection == nil {
            collection = []
        }
        guard collection?.contains(where: { $0.id == object.id }) == false else { return }
        collection?.append(object)
    }
}

enum PatientMatchingError: Error, LocalizedError {
    case ambiguousMatches(message: String)
    
    var errorDescription: String? {
        switch self {
        case .ambiguousMatches(let msg): return msg
        }
    }
}
