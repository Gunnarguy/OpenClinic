import XCTest
import SwiftData
@testable import OpenClinic

final class ClinicalIntelligenceServiceTests: XCTestCase {
    var service: ClinicalIntelligenceService!
    var container: ModelContainer!
    var context: ModelContext!

    @MainActor
    override func setUp() async throws {
        let schema = Schema([
            PatientProfile.self,
            LocalClinicalRecord.self,
            LocalMedication.self,
            Appointment.self,
            ClinicalPhoto.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
        service = ClinicalIntelligenceService()
    }

    override func tearDown() {
        service = nil
        context = nil
        container = nil
    }

    @MainActor
    func testExecuteFallbackQueryMedication() async throws {
        let patient = PatientProfile(
            firstName: "Jane",
            lastName: "Doe",
            dateOfBirth: Date(),
            gender: "Female"
        )
        context.insert(patient)

        let med = LocalMedication(
            rxID: "rx1",
            medicationName: "Lisinopril",
            writtenBy: "Dr. Smith",
            writtenDate: Date(),
            quantityInfo: "30 tablets",
            refills: 3,
            dose: "10mg",
            route: "Oral",
            frequency: "daily",
            status: "Active",
            sourceKind: "Manual",
            sourceSystemName: "Manual",
            sourceRecordIdentifier: "rx1",
            sourceOfTruth: true
        )
        med.patient = patient
        context.insert(med)
        patient.medications?.append(med)
        try context.save()

        let response = try await service.executeToolQuery(query: "What is patient's prescription refill history?", modelContext: context, patient: patient)
        print("DEBUG RESPONSE: \(response)")
        XCTAssertTrue(response.contains("Lisinopril"), "Response was: \(response)")
        XCTAssertTrue(response.contains("10mg"))
        XCTAssertTrue(response.contains("daily"))
    }

    @MainActor
    func testExecuteFallbackQueryAppointments() async throws {
        let patient = PatientProfile(
            firstName: "Jane",
            lastName: "Doe",
            dateOfBirth: Date(),
            gender: "Female"
        )
        context.insert(patient)

        let appt = Appointment(
            appointmentID: "appt1",
            scheduledTime: Date().addingTimeInterval(3600),
            reasonForVisit: "Annual physical",
            status: "Booked",
            clinicianName: "Dr. House",
            sourceKind: "Manual",
            sourceSystemName: "Manual",
            sourceRecordIdentifier: "appt1",
            sourceOfTruth: true
        )
        appt.patient = patient
        context.insert(appt)
        patient.appointments?.append(appt)
        try context.save()

        let response = try await service.executeToolQuery(query: "Show me the next visit or scheduled appointment", modelContext: context, patient: patient)
        XCTAssertTrue(response.contains("Annual physical"))
    }

    @MainActor
    func testExecutePanelFallbackQueryToday() async throws {
        let patient1 = PatientProfile(
            firstName: "Jane",
            lastName: "Doe",
            dateOfBirth: Date(),
            gender: "Female"
        )
        let patient2 = PatientProfile(
            firstName: "John",
            lastName: "Smith",
            dateOfBirth: Date(),
            gender: "Male"
        )
        context.insert(patient1)
        context.insert(patient2)

        let appt1 = Appointment(
            appointmentID: "a1",
            scheduledTime: Date(),
            reasonForVisit: "Asthma check",
            status: "Booked",
            clinicianName: "Dr. Smith",
            sourceKind: "Manual",
            sourceSystemName: "Manual",
            sourceRecordIdentifier: "a1",
            sourceOfTruth: true
        )
        appt1.patient = patient1
        context.insert(appt1)
        patient1.appointments?.append(appt1)

        try context.save()

        let response = try await service.executePanelQuery(query: "who is on today's schedule or agenda?", modelContext: context)
        XCTAssertTrue(response.contains("Jane Doe"))
        XCTAssertTrue(response.contains("Asthma check"))
    }
}
