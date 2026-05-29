import SwiftUI
import SwiftData
import os

struct iPadClinicalDashboard: View {
    @Query(sort: \PatientProfile.lastName) private var patients: [PatientProfile]
    @State private var selectedPatientID: UUID?
    @State private var recentPatientIDs: [UUID] = []

    private var selectedPatient: PatientProfile? {
        if let selectedPatientID {
            return patients.first(where: { $0.id == selectedPatientID })
        }
        return patients.first
    }

    private var recentPatients: [PatientProfile] {
        recentPatientIDs.compactMap { id in
            patients.first(where: { $0.id == id })
        }
    }

    var body: some View {
        NavigationSplitView {
            PatientAgendaList(patients: patients, selection: $selectedPatientID)
                .navigationTitle("Today’s Patients")
                .onAppear { AppLogger.dashboard.info("📋 Patient sidebar loaded — \(patients.count) patients") }
        } detail: {
            VStack(spacing: 0) {
                if !recentPatients.isEmpty {
                    RecentPatientsStrip(
                        patients: recentPatients,
                        selection: $selectedPatientID,
                        onClose: closeRecentPatient
                    )
                }

                if let patient = selectedPatient {
                    NavigationStack {
                        PatientChartPageView(patient: patient)
                    }
                } else {
                    ContentUnavailableView(
                        "Select a Patient",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("Choose a patient from the sidebar to view their chart.")
                    )
                }
            }
        }
        .onAppear {
            rememberRecentPatient(selectedPatientID ?? patients.first?.id)
        }
        .onChange(of: selectedPatientID) { oldVal, newVal in
            AppLogger.dashboard.info("👤 Patient selection changed: \(String(describing: oldVal)) → \(String(describing: newVal))")
            rememberRecentPatient(newVal)
        }
    }

    private func rememberRecentPatient(_ patientID: UUID?) {
        guard let patientID else { return }
        recentPatientIDs.removeAll { $0 == patientID }
        recentPatientIDs.insert(patientID, at: 0)
        recentPatientIDs = Array(recentPatientIDs.prefix(6))
    }

    private func closeRecentPatient(_ patientID: UUID) {
        recentPatientIDs.removeAll { $0 == patientID }

        if selectedPatientID == patientID {
            selectedPatientID = recentPatientIDs.first
        }
    }
}

// MARK: - Patient List Sidebar

struct PatientAgendaList: View {
    let patients: [PatientProfile]
    @Binding var selection: UUID?
    @State private var searchText = ""

    private var todayPatients: [PatientAgendaDaySummary] {
        let cal = Calendar.current
        var groupedAppointments: [UUID: (patient: PatientProfile, appointments: [Appointment])] = [:]

        for patient in patients {
            for appt in patient.appointments ?? [] {
                if cal.isDateInToday(appt.scheduledTime) {
                    let current = groupedAppointments[patient.id] ?? (patient, [])
                    groupedAppointments[patient.id] = (current.patient, current.appointments + [appt])
                }
            }
        }

        let sorted = groupedAppointments.values
            .map { PatientAgendaDaySummary(patient: $0.patient, appointments: $0.appointments) }
            .sorted { $0.primaryAppointment.scheduledTime < $1.primaryAppointment.scheduledTime }

        guard !searchText.isEmpty else { return sorted }
        let needle = searchText.lowercased()
        return sorted.filter { summary in
            summary.patient.fullName.lowercased().contains(needle)
                || summary.patient.medicalRecordNumber.lowercased().contains(needle)
                || summary.reasonSummary.lowercased().contains(needle)
        }
    }

    private var rosterPatients: [PatientProfile] {
        guard !searchText.isEmpty else { return patients }
        let needle = searchText.lowercased()
        return patients.filter { patient in
            patient.fullName.lowercased().contains(needle)
                || patient.medicalRecordNumber.lowercased().contains(needle)
                || (patient.primaryClinician?.lowercased().contains(needle) ?? false)
        }
    }

    var body: some View {
        List(selection: $selection) {
            if !todayPatients.isEmpty {
                Section("Today") {
                    ForEach(todayPatients) { summary in
                        NavigationLink(value: summary.patient.id) {
                            PatientAgendaRow(summary: summary)
                        }
                    }
                }
            }

            Section(todayPatients.isEmpty ? "Patients" : "All Patients") {
                ForEach(rosterPatients, id: \.id) { patient in
                    NavigationLink(value: patient.id) {
                        PatientRosterRow(patient: patient)
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.sidebar)
        #endif
        .searchable(text: $searchText, prompt: "Search patient, MRN, visit reason")
        .onAppear {
            if selection == nil {
                selection = todayPatients.first?.patient.id ?? rosterPatients.first?.id
            }
        }
    }
}

private struct PatientAgendaDaySummary: Identifiable {
    let patient: PatientProfile
    let appointments: [Appointment]

    var id: UUID { patient.id }

    var primaryAppointment: Appointment {
        appointments.min(by: { $0.scheduledTime < $1.scheduledTime }) ?? appointments[0]
    }

    var appointmentCount: Int {
        appointments.count
    }

    var reasonSummary: String {
        let reasons = appointments
            .map(\.reasonForVisit)
            .filter { !$0.isEmpty }
        let uniqueReasons = Array(NSOrderedSet(array: reasons)) as? [String] ?? reasons

        if uniqueReasons.isEmpty {
            return appointmentCount == 1 ? "Appointment" : "\(appointmentCount) appointments today"
        }

        if appointmentCount == 1 {
            return uniqueReasons[0]
        }

        return "\(appointmentCount) appointments today • " + uniqueReasons.prefix(2).joined(separator: " • ")
    }
}

private struct PatientAgendaRow: View {
    let summary: PatientAgendaDaySummary

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(AgendaView.workflowColor(for: summary.primaryAppointment.resolvedStatus))
                .frame(width: 3, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(summary.patient.fullName)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(summary.primaryAppointment.scheduledTime, format: .dateTime.hour().minute())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .clinicalFinePrintMonospaced()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                HStack {
                    Text(summary.reasonSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .clinicalFinePrint()
                        .clinicalRowSummaryText()
                    Spacer()
                    Text(summary.appointmentCount == 1 ? summary.primaryAppointment.workflowStatusLabel : "\(summary.appointmentCount) today")
                        .clinicalPillText(weight: .medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AgendaView.workflowColor(for: summary.primaryAppointment.resolvedStatus).opacity(0.15))
                        .foregroundStyle(AgendaView.workflowColor(for: summary.primaryAppointment.resolvedStatus))
                        .clipShape(Capsule())
                }
                ClinicalSourceBadge(descriptor: summary.patient.sourceDescriptor)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct PatientRosterRow: View {
    let patient: PatientProfile

    private var nextAppointment: Appointment? {
        (patient.appointments ?? []).sorted { $0.scheduledTime < $1.scheduledTime }.first
    }

    private var activeMedicationCount: Int {
        (patient.medications ?? []).filter { ($0.status ?? "Active") == "Active" }.count
    }

    private var problemCount: Int {
        (patient.clinicalRecords ?? []).groupedProblemSummaries().count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(patient.fullName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("MRN \(patient.medicalRecordNumber)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .clinicalFinePrint()
            }

            HStack(spacing: 10) {
                Text("\(patient.age)y")
                Text(patient.gender)
                Text("\(activeMedicationCount) active Rx")
                Text("\(problemCount) problems")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .clinicalFinePrint()

            ClinicalSourceBadge(descriptor: patient.sourceDescriptor)

            if let nextAppointment {
                Text("Next: \(nextAppointment.scheduledTime.formatted(date: .abbreviated, time: .shortened)) • \(nextAppointment.reasonForVisit)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .clinicalFinePrint()
                    .clinicalRowSummaryText()
            }
        }
        .padding(.vertical, 3)
    }
}

private struct RecentPatientsStrip: View {
    let patients: [PatientProfile]
    @Binding var selection: UUID?
    let onClose: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Open Charts")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(patients) { patient in
                        HStack(spacing: 6) {
                            Button {
                                selection = patient.id
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: selection == patient.id ? "checkmark.circle.fill" : patient.sourceDescriptor.kind.iconName)
                                        .font(.caption)
                                    Text(patient.fullName)
                                        .lineLimit(1)
                                }
                                .contentShape(Rectangle())
                            }

                            Button {
                                onClose(patient.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close \(patient.fullName)")
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background((selection == patient.id ? Color.blue : Color.secondary).opacity(selection == patient.id ? 0.14 : 0.08), in: Capsule())
                        .foregroundStyle(selection == patient.id ? Color.blue : Color.primary)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 8)
        }
        .background(.thinMaterial)
    }
}

// MARK: - Clinical Alert Model

struct ClinicalAlert {
    let icon: String
    let color: Color
    let title: String
    let message: String
}
