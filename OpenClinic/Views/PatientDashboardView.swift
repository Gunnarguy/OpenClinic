import SwiftUI
import SwiftData

struct PatientDashboardView: View {
    @Query(sort: \PatientProfile.lastName) private var patients: [PatientProfile]
    @State private var searchText = ""
    private var initialPatient: PatientProfile?

    init(patient: PatientProfile? = nil) {
        self.initialPatient = patient
    }

    private var filteredPatients: [PatientProfile] {
        guard !searchText.isEmpty else { return patients }
        let needle = searchText.lowercased()
        return patients.filter { patient in
            patient.fullName.lowercased().contains(needle)
                || patient.medicalRecordNumber.lowercased().contains(needle)
                || (patient.primaryClinician?.lowercased().contains(needle) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            if let patient = initialPatient {
                PatientChartPageView(patient: patient)
            } else {
                VStack(spacing: 0) {
                    // Context bar (mirrors Intelligence/Agenda)
                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(patients.isEmpty ? .orange : .green)
                                .frame(width: 6, height: 6)
                            Text("\(patients.count) patients on panel")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: "person.crop.circle.fill")
                            Text("Panel")
                                .fontWeight(.medium)
                                .clinicalPillText(weight: .medium)
                        }
                        .font(.caption)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.purple.opacity(0.12), in: Capsule())
                        .foregroundStyle(.purple)
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                    if filteredPatients.isEmpty {
                        ContentUnavailableView(
                            "No Patients Found",
                            systemImage: "person.crop.circle.badge.questionmark",
                            description: Text(patients.isEmpty ? "Add a patient to get started." : "Try a different name, MRN, or clinician.")
                        )
                        .frame(maxHeight: .infinity)
                    } else {
                        List(filteredPatients) { patient in
                            NavigationLink(destination: PatientChartPageView(patient: patient)) {
                                PatientListRow(patient: patient)
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                        .background(ClinicGlowBackground())
                    }
                }
                .navigationTitle("Patients")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .searchable(text: $searchText, prompt: "Search name, MRN, or clinician")
            }
        }
    }
}

private struct PatientListRow: View {
    let patient: PatientProfile

    private var activeMedCount: Int {
        (patient.medications ?? []).filter { ($0.status ?? "Active") == "Active" }.count
    }

    private var problemCount: Int {
        (patient.clinicalRecords ?? []).groupedProblemSummaries().count
    }

    private var nextAppointment: Appointment? {
        (patient.appointments ?? []).sorted { $0.scheduledTime < $1.scheduledTime }.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                // Patient Initials Avatar with mesh gradient
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.clinicalIndigo.opacity(0.35), Color.clinicalTeal.opacity(0.15)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 42, height: 42)
                    .overlay(
                        Text("\(String(patient.firstName.prefix(1)))\(String(patient.lastName.prefix(1)))")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.clinicalIndigo)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(patient.fullName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("MRN \(patient.medicalRecordNumber) • \(patient.age)y • \(patient.gender)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if patient.isSmoker {
                    Image(systemName: "smoke.fill")
                        .font(.caption)
                        .foregroundStyle(Color.clinicalAmber)
                }
            }

            HStack(spacing: 12) {
                patientMetric("Problems", value: "\(problemCount)", color: .clinicalIndigo)
                patientMetric("Rx", value: "\(activeMedCount)", color: .clinicalTeal)
                patientMetric("Appts", value: "\(patient.appointments?.count ?? 0)", color: .clinicalSlate)
            }
            .padding(.top, 2)

            HStack(spacing: 8) {
                ClinicalSourceBadge(descriptor: patient.sourceDescriptor)
                
                if let nextAppointment {
                    Spacer()
                    Text("Next: \(nextAppointment.scheduledTime.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func patientMetric(_ label: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text("\(label): \(value)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct PatientChartPageView: View {
    let patient: PatientProfile
    @State private var selectedSection: ChartSection = .summary
    @State private var reconciledMedIDs: Set<String> = []

    private enum ChartSection: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case visits = "Visits"
        case medications = "Meds"
        case imaging = "Imaging"
        case tools = "Tools"

        var id: String { rawValue }
    }

    private var sortedRecords: [LocalClinicalRecord] {
        (patient.clinicalRecords ?? []).sorted { $0.dateRecorded > $1.dateRecorded }
    }

    private var groupedProblems: [ClinicalProblemSummary] {
        sortedRecords.groupedProblemSummaries()
    }

    private var sortedAppointments: [Appointment] {
        (patient.appointments ?? []).sorted { $0.scheduledTime < $1.scheduledTime }
    }

    private var sortedMedications: [LocalMedication] {
        (patient.medications ?? []).sorted { $0.writtenDate > $1.writtenDate }
    }

    private var activeMedications: [LocalMedication] {
        sortedMedications.filter { ($0.status ?? "Active") == "Active" }
    }

    private var nextAppointment: Appointment? {
        sortedAppointments.first { $0.scheduledTime >= Date() }
    }

    private var latestRecord: LocalClinicalRecord? {
        sortedRecords.first
    }

    // MARK: - Patient Content

    private func clinicalAlerts(for patient: PatientProfile) -> [ClinicalAlert] {
        var alerts: [ClinicalAlert] = []
        let meds = patient.medications ?? []
        let medNames = meds.map { $0.medicationName.lowercased() }

        if medNames.contains(where: { $0.contains("methotrexate") }) {
            alerts.append(ClinicalAlert(
                icon: "pills.circle.fill", color: .red, title: "Methotrexate Monitoring",
                message: "Patient on methotrexate — verify CBC and LFTs within last 30 days."
            ))
        }
        if medNames.contains(where: { $0.contains("dupixent") || $0.contains("dupilumab") }) {
            alerts.append(ClinicalAlert(
                icon: "syringe.fill", color: .orange, title: "Biologic Therapy",
                message: "Dupixent patient — assess for conjunctivitis and injection site reactions."
            ))
        }
        if medNames.contains(where: { $0.contains("humira") || $0.contains("adalimumab") }) {
            alerts.append(ClinicalAlert(
                icon: "syringe.fill", color: .orange, title: "TNF Inhibitor",
                message: "Humira patient — screen for TB and monitor for infection signs."
            ))
        }
        if patient.isSmoker && (patient.clinicalRecords ?? []).contains(where: {
            $0.conditionName.lowercased().contains("melanoma") || $0.conditionName.lowercased().contains("carcinoma")
        }) {
            alerts.append(ClinicalAlert(
                icon: "exclamationmark.triangle.fill", color: .red, title: "High-Risk Patient",
                message: "Current smoker with skin cancer history — prioritize full-body skin exam."
            ))
        } else if patient.isSmoker {
            alerts.append(ClinicalAlert(
                icon: "smoke.fill", color: .orange, title: "Smoking Status",
                message: "Current smoker — consider cessation counseling and wound healing implications."
            ))
        }
        let highRiskAllergies = patient.allergies.filter { a in
            let lower = a.lowercased()
            return lower.contains("penicillin") || lower.contains("sulfa") || lower.contains("latex") || lower.contains("nsaid")
        }
        if !highRiskAllergies.isEmpty {
            alerts.append(ClinicalAlert(
                icon: "allergens.fill", color: .yellow, title: "Allergy Alert",
                message: "Documented allergies: \(highRiskAllergies.joined(separator: ", "))"
            ))
        }
        if !patient.riskFlags.isEmpty {
            alerts.append(ClinicalAlert(
                icon: "flag.fill", color: .purple, title: "Risk Flags",
                message: patient.riskFlags.joined(separator: " • ")
            ))
        }
        return alerts
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PatientDemographicsBanner(profile: patient)
                chartSectionPicker
                sectionContent
            }
            .padding()
        }
        .background(ClinicGlowBackground())
        .navigationTitle(patient.fullName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var chartSectionPicker: some View {
        Picker("Chart Section", selection: $selectedSection) {
            ForEach(ChartSection.allCases) { section in
                Text(section.rawValue).tag(section)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .summary:
            summarySection
        case .visits:
            visitsSection
        case .medications:
            medicationsSection
        case .imaging:
            imagingSection
        case .tools:
            toolsSection
        }
    }

    private var summarySection: some View {
        VStack(spacing: 16) {
            // Safety Priority Stack (CDS Alerts + Allergies + Risk Flags) at the very top
            let cdsAlerts = clinicalAlerts(for: patient)
            if !cdsAlerts.isEmpty || !patient.allergies.isEmpty || !patient.riskFlags.isEmpty {
                VStack(spacing: 8) {
                    if !cdsAlerts.isEmpty {
                        cdsAlertsCard(cdsAlerts)
                    }
                    if !patient.allergies.isEmpty || !patient.riskFlags.isEmpty {
                        alertsCard(patient)
                    }
                }
            }

            // Vitals Flowsheet Grid
            ClinicalVitalsGrid(patient: patient)

            // Dynamic Metric Badges Row
            metricsRow(patient)

            // Encounter Workflow Action Lane
            actionLaneCard

            // Inline Medication Reconciliation Widget
            ActiveMedsWorkspaceWidget(medications: activeMedications, reconciledMedIDs: $reconciledMedIDs)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(chartPanelBackground)

            // Problem List Card
            if !groupedProblems.isEmpty {
                infoCard(title: "Problem List", systemImage: "cross.case.fill", tint: .red) {
                    VStack(spacing: 0) {
                        ForEach(Array(groupedProblems.prefix(6).enumerated()), id: \.element.id) { index, summary in
                            problemPreviewRow(summary)
                            if index < min(groupedProblems.count, 6) - 1 {
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                }
            }

            // Next Appointment Card
            if let appointment = nextAppointment {
                infoCard(title: "Next Appointment", systemImage: "calendar.badge.clock", tint: .purple) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(appointment.reasonForVisit)
                            .font(.subheadline.weight(.semibold))
                            .clinicalRowSummaryText()
                        Text("\(appointment.scheduledTime.formatted(date: .abbreviated, time: .shortened)) • \(appointment.workflowStatusLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .clinicalFinePrint()
                        if let clinician = appointment.clinicianName {
                            Text("Clinician: \(clinician)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .clinicalFinePrint()
                        }
                        HStack(spacing: 6) {
                            ClinicalSourceBadge(descriptor: appointment.sourceDescriptor)
                            SourceOfTruthBadge(authoritative: appointment.sourceDescriptor.authoritative)
                        }
                    }
                }
            }

            // Care Plan Card
            if let plan = patient.carePlanSummary, !plan.isEmpty {
                carePlanCard(plan)
            }

            // Chart Navigation Menu Card
            infoCard(title: "Chart Overview", systemImage: "list.bullet.rectangle", tint: .blue) {
                VStack(spacing: 0) {
                    NavigationLink(destination: VisitHistoryView(patient: patient)) {
                        chartRow(label: "Visit Timeline", icon: "bed.double", color: .blue)
                    }
                    Divider().padding(.leading, 44)
                    NavigationLink(destination: ChartNotesView(patient: patient)) {
                        chartRow(label: "Structured Notes", icon: "folder", color: .indigo)
                    }
                    Divider().padding(.leading, 44)
                    NavigationLink(destination: RxListView(patient: patient)) {
                        chartRow(label: "Medication List", icon: "pills", color: .green)
                    }
                }
            }
        }
    }

    private var visitsSection: some View {
        VStack(spacing: 16) {
            infoCard(title: "Recent Entries", systemImage: "clock.arrow.circlepath", tint: .blue) {
                if sortedRecords.isEmpty {
                    emptyStateRow("No documented visits")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(sortedRecords.prefix(5).enumerated()), id: \.element.id) { index, record in
                            visitPreviewRow(record)
                            if index < min(sortedRecords.count, 5) - 1 {
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                }
            }

            infoCard(title: "Chart Actions", systemImage: "doc.text.magnifyingglass", tint: .indigo) {
                VStack(spacing: 0) {
                    NavigationLink(destination: VisitHistoryView(patient: patient)) {
                        chartRow(label: "Open Full Visit History", icon: "bed.double", color: .blue)
                    }
                    Divider().padding(.leading, 44)
                    NavigationLink(destination: ChartNotesView(patient: patient)) {
                        chartRow(label: "Review Chart Notes", icon: "folder", color: .indigo)
                    }
                }
            }
        }
    }

    private var medicationsSection: some View {
        VStack(spacing: 16) {
            infoCard(title: "Active Medications", systemImage: "pills.fill", tint: .green) {
                if activeMedications.isEmpty {
                    emptyStateRow("No active medications on file")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(activeMedications.prefix(6).enumerated()), id: \.element.id) { index, medication in
                            medicationPreviewRow(medication)
                            if index < min(activeMedications.count, 6) - 1 {
                                Divider().padding(.leading, 44)
                            }
                        }
                    }
                }
            }

            infoCard(title: "Medication Workflow", systemImage: "cross.case", tint: .green) {
                NavigationLink(destination: RxListView(patient: patient)) {
                    chartRow(label: "Open Medication Workspace", icon: "pills", color: .green)
                }
            }
        }
    }

    private var imagingSection: some View {
        VStack(spacing: 16) {
            infoCard(title: "Clinical Imaging", systemImage: "camera.viewfinder", tint: .orange) {
                VStack(spacing: 0) {
                    NavigationLink(destination: ClinicalPhotoView(patient: patient)) {
                        chartRow(label: "Clinical Photos", icon: "camera.fill", color: .orange)
                    }
                    Divider().padding(.leading, 44)
                    NavigationLink(destination: LesionTrackingView(patient: patient)) {
                        chartRow(label: "Lesion Tracking", icon: "chart.line.uptrend.xyaxis", color: .teal)
                    }
                    Divider().padding(.leading, 44)
                    NavigationLink(destination: AnatomicalRealityView(patient: patient)) {
                        chartRow(label: "Body Map", icon: "figure.stand", color: .red)
                    }
                }
            }
        }
    }

    private var toolsSection: some View {
        VStack(spacing: 16) {
            infoCard(title: "Clinical Tools", systemImage: "stethoscope", tint: .purple) {
                VStack(spacing: 0) {
                    NavigationLink(destination: ClinicalExamView(patient: patient)) {
                        chartRow(label: "Clinical Exam Workspace", icon: "waveform.path.ecg.rectangle", color: .purple)
                    }
                    Divider().padding(.leading, 44)
                    NavigationLink(destination: ClinicIntelligenceView(patient: patient)) {
                        chartRow(label: "Clinical Intelligence", icon: "brain.head.profile", color: .blue)
                    }
                    Divider().padding(.leading, 44)
                    NavigationLink(destination: ClinicalAssistantView(patient: patient)) {
                        chartRow(label: "On-Device AI Assistant", icon: "bubble.left.and.bubble.right.fill", color: .clinicalIndigo)
                    }
                    Divider().padding(.leading, 44)
                    NavigationLink(destination: InteroperabilityWorkspaceView()) {
                        chartRow(label: "EHR Connectivity", icon: "network", color: .teal)
                    }
                }
            }

            infoCard(title: "Use Cases", systemImage: "lightbulb", tint: .secondary) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Use intelligence when you need synthesis across chart history, medications, and upcoming care. Default chart review should still begin in Visits and Medications.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .clinicalRowSummaryText(lines: 3)
                }
            }
        }
    }

    // MARK: - CDS Alerts

    private func cdsAlertsCard(_ alerts: [ClinicalAlert]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Clinical Decision Support", systemImage: "brain.head.profile")
                .font(.subheadline.bold())
                .foregroundColor(.primary)
            ForEach(alerts, id: \.title) { alert in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: alert.icon)
                        .foregroundColor(alert.color)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.title)
                            .font(.caption.bold())
                            .clinicalFinePrint(weight: .bold)
                        Text(alert.message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .clinicalFinePrint()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(alertPanelBackground)
    }

    // MARK: - Alerts

    private func alertsCard(_ patient: PatientProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(patient.allergies, id: \.self) { allergy in
                Label(allergy, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundColor(.orange)
            }
            ForEach(patient.riskFlags, id: \.self) { flag in
                Label(flag, systemImage: "flag.fill")
                    .font(.subheadline)
                    .foregroundColor(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(warningPanelBackground)
    }

    // MARK: - Metrics

    private func metricsRow(_ patient: PatientProfile) -> some View {
        HStack(spacing: 12) {
            metricTile(label: "Problems", value: "\(groupedProblems.count)", icon: "cross.case", color: .blue)
            metricTile(label: "Active Rx", value: "\(activeMedications.count)", icon: "pills", color: .green)
            metricTile(label: "Appointments", value: "\(patient.appointments?.count ?? 0)", icon: "calendar", color: .purple)
        }
    }

    private var actionLaneCard: some View {
        infoCard(title: "Encounter Workflow Lane", systemImage: "checklist", tint: .clinicalIndigo) {
            VStack(spacing: 8) {
                // Workflow step 1: Review Note
                workflowStepRow(
                    stepNumber: 1,
                    title: "Review Note",
                    detail: latestRecord.map { "\($0.conditionName) - \($0.documentationLifecycle.label)" } ?? "No note written",
                    isCompleted: latestRecord != nil,
                    destination: latestRecord.map { AnyView(VisitRecordDetailView(record: $0, patient: patient)) }
                )
                
                // Workflow step 2: Reconcile Meds
                let rxCount = activeMedications.count
                let allReconciled = rxCount > 0 && reconciledMedIDs.count >= rxCount
                workflowStepRow(
                    stepNumber: 2,
                    title: "Reconcile Medications",
                    detail: rxCount == 0 ? "No active medications" : "\(reconciledMedIDs.count)/\(rxCount) reconciled",
                    isCompleted: rxCount == 0 || allReconciled,
                    destination: AnyView(RxListView(patient: patient))
                )
                
                // Workflow step 3: Patient Instructions
                let hasInstructions = latestRecord?.patientInstructions?.isEmpty == false
                workflowStepRow(
                    stepNumber: 3,
                    title: "Author Instructions",
                    detail: hasInstructions ? "Ready to review" : "Needs clinical entry",
                    isCompleted: hasInstructions,
                    destination: latestRecord.map { AnyView(VisitRecordDetailView(record: $0, patient: patient)) }
                )
                
                // Workflow step 4: Confirm Follow-Up
                let hasAppt = nextAppointment != nil
                workflowStepRow(
                    stepNumber: 4,
                    title: "Confirm Follow-Up",
                    detail: nextAppointment.map { $0.scheduledTime.formatted(date: .abbreviated, time: .shortened) } ?? "No future appointment",
                    isCompleted: hasAppt,
                    destination: AnyView(VisitHistoryView(patient: patient))
                )
            }
        }
    }

    private func workflowStepRow(stepNumber: Int, title: String, detail: String, isCompleted: Bool, destination: AnyView?) -> some View {
        Group {
            if let dest = destination {
                NavigationLink(destination: dest) {
                    stepRowContent(stepNumber: stepNumber, title: title, detail: detail, isCompleted: isCompleted)
                }
            } else {
                stepRowContent(stepNumber: stepNumber, title: title, detail: detail, isCompleted: isCompleted)
            }
        }
        .buttonStyle(.plain)
    }

    private func stepRowContent(stepNumber: Int, title: String, detail: String, isCompleted: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isCompleted ? Color.clinicalTeal.opacity(0.12) : Color.clinicalIndigo.opacity(0.08))
                    .frame(width: 26, height: 26)
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.clinicalTeal)
                } else {
                    Text("\(stepNumber)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.clinicalIndigo)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(isCompleted ? .secondary : .primary)
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .clinicalFinePrint()
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(10)
        .background(
            Color.clear
                .liquidGlassCard(
                    cornerRadius: 10,
                    borderColor: isCompleted ? Color.clinicalTeal.opacity(0.1) : Color.clinicalIndigo.opacity(0.08),
                    shadowRadius: 2
                )
        )
    }

    private func infoCard<Content: View>(title: String, systemImage: String, tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.bold())
                .foregroundStyle(tint)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(chartPanelBackground)
    }

    private func emptyStateRow(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    private func visitPreviewRow(_ record: LocalClinicalRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text")
                .foregroundStyle(.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.conditionName)
                    .font(.subheadline.weight(.semibold))
                Text(record.dateRecorded.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let visitType = record.visitType {
                    Text(visitType)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let followUp = record.followUpPlan, !followUp.isEmpty {
                    Text("Follow-up: \(followUp)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .clinicalRowSummaryText(lines: 2)
                }
                HStack(spacing: 6) {
                    DocumentationStatusBadge(status: record.documentationLifecycle)
                    ClinicalSourceBadge(descriptor: record.sourceDescriptor)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func problemPreviewRow(_ summary: ClinicalProblemSummary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "cross.case.fill")
                .foregroundStyle(.red)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(summary.title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if summary.occurrenceCount > 1 {
                        Text("\(summary.occurrenceCount) entries")
                            .clinicalPillText(weight: .medium)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Last updated \(summary.latestDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .clinicalFinePrint()
                HStack(spacing: 6) {
                    DocumentationStatusBadge(status: summary.latestRecord.documentationLifecycle)
                    ClinicalSourceBadge(descriptor: summary.latestRecord.sourceDescriptor)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func medicationPreviewRow(_ medication: LocalMedication) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "pills.fill")
                .foregroundStyle(.green)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(medication.medicationName)
                    .font(.subheadline.weight(.semibold))
                Text([medication.dose, medication.route, medication.frequency]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                    .joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let indication = medication.indication, !indication.isEmpty {
                    Text(indication)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .clinicalRowSummaryText(lines: 2)
                }
                HStack(spacing: 6) {
                    ClinicalSourceBadge(descriptor: medication.sourceDescriptor)
                    SourceOfTruthBadge(authoritative: medication.sourceDescriptor.authoritative)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }

    private func metricTile(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            Text(value)
                .font(.title2.bold().monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .clinicalMicroLabel()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(chartMetricBackground)
    }

    // MARK: - Care Plan

    private func carePlanCard(_ plan: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Care Plan", systemImage: "heart.text.clipboard")
                .font(.subheadline.bold())
            Text(plan)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(chartPanelBackground)
    }

    private func chartRow(label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(color)
                .frame(width: 28)
            Text(label)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    private var chartPanelBackground: some View {
        Color.clear
            .liquidGlassCard(cornerRadius: 12)
    }

    private var chartMetricBackground: some View {
        Color.clear
            .liquidGlassCard(cornerRadius: 12, borderColor: Color.primary.opacity(0.04), shadowRadius: 3)
    }

    private var alertPanelBackground: some View {
        Color.clear
            .liquidGlassCard(cornerRadius: 12, borderColor: Color.criticalRed.opacity(0.2), shadowRadius: 4, glowColor: Color.criticalRed)
            .background(Color.criticalRed.opacity(0.03))
            .cornerRadius(12)
    }

    private var warningPanelBackground: some View {
        Color.clear
            .liquidGlassCard(cornerRadius: 12, borderColor: Color.clinicalAmber.opacity(0.2), shadowRadius: 4, glowColor: Color.clinicalAmber)
            .background(Color.clinicalAmber.opacity(0.03))
            .cornerRadius(12)
    }
}

// MARK: - Clinical Vitals Flowsheet View
private struct ClinicalVitalsGrid: View {
    let patient: PatientProfile
    
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    
    // Compute stable simulated vitals based on patient UUID hash
    private var vitals: (bp: String, hr: Int, temp: Double, spo2: Int, bpStatus: Color, hrStatus: Color, tempStatus: Color, spo2Status: Color) {
        let hash = abs(patient.id.uuidString.hashValue)
        
        let hrBase = 65 + (hash % 20) // 65 - 85
        let bpSys = 115 + (hash % 15) // 115 - 130
        let bpDia = 75 + (hash % 10)  // 75 - 85
        let tempBase = 98.2 + Double(hash % 8) / 10.0 // 98.2 - 99.0
        let spo2Base = 97 + (hash % 3) // 97 - 99
        
        // Adjust for smoker status (higher heart rate, slightly lower SpO2)
        let hr = patient.isSmoker ? hrBase + 8 : hrBase
        let spo2 = patient.isSmoker ? max(spo2Base - 1, 95) : spo2Base
        
        // Status evaluation colors
        let bpStatus: Color = (bpSys > 130 || bpDia > 85) ? .clinicalAmber : .clinicalTeal
        let hrStatus: Color = (hr > 90) ? .clinicalAmber : .clinicalTeal
        let tempStatus: Color = (tempBase > 99.1) ? .clinicalAmber : .clinicalTeal
        let spo2Status: Color = (spo2 < 96) ? .criticalRed : .clinicalTeal
        
        return ("\(bpSys)/\(bpDia)", hr, tempBase, spo2, bpStatus, hrStatus, tempStatus, spo2Status)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Clinical Vitals Flowsheet", systemImage: "waveform.path.ecg")
                .font(.subheadline.bold())
                .foregroundColor(.clinicalIndigo)
            
            #if os(iOS)
            if horizontalSizeClass == .compact {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    vitalTile(label: "Blood Pressure", value: vitals.bp, unit: "mmHg", status: vitals.bpStatus, icon: "heart.text.square")
                    vitalTile(label: "Heart Rate", value: "\(vitals.hr)", unit: "bpm", status: vitals.hrStatus, icon: "heart.fill")
                    vitalTile(label: "Temperature", value: String(format: "%.1f", vitals.temp), unit: "°F", status: vitals.tempStatus, icon: "thermometer.medium")
                    vitalTile(label: "Oxygen Sat", value: "\(vitals.spo2)", unit: "%", status: vitals.spo2Status, icon: "waveform.path.ecg")
                }
            } else {
                HStack(spacing: 8) {
                    vitalTile(label: "Blood Pressure", value: vitals.bp, unit: "mmHg", status: vitals.bpStatus, icon: "heart.text.square")
                    vitalTile(label: "Heart Rate", value: "\(vitals.hr)", unit: "bpm", status: vitals.hrStatus, icon: "heart.fill")
                    vitalTile(label: "Temperature", value: String(format: "%.1f", vitals.temp), unit: "°F", status: vitals.tempStatus, icon: "thermometer.medium")
                    vitalTile(label: "Oxygen Sat", value: "\(vitals.spo2)", unit: "%", status: vitals.spo2Status, icon: "waveform.path.ecg")
                }
            }
            #else
            HStack(spacing: 8) {
                vitalTile(label: "Blood Pressure", value: vitals.bp, unit: "mmHg", status: vitals.bpStatus, icon: "heart.text.square")
                vitalTile(label: "Heart Rate", value: "\(vitals.hr)", unit: "bpm", status: vitals.hrStatus, icon: "heart.fill")
                vitalTile(label: "Temperature", value: String(format: "%.1f", vitals.temp), unit: "°F", status: vitals.tempStatus, icon: "thermometer.medium")
                vitalTile(label: "Oxygen Sat", value: "\(vitals.spo2)", unit: "%", status: vitals.spo2Status, icon: "waveform.path.ecg")
            }
            #endif
        }
    }
    
    private func vitalTile(label: String, value: String, unit: String, status: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(status)
                Spacer()
                Circle()
                    .fill(status)
                    .frame(width: 6, height: 6)
            }
            Text(value)
                .font(.system(.title3, design: .rounded).bold())
                .minimumScaleFactor(0.8)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(label)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text(unit)
                    .font(.system(size: 7))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.clear
                .liquidGlassCard(cornerRadius: 12, borderColor: status.opacity(0.12), shadowRadius: 3, glowColor: status)
        )
    }
}

// MARK: - Active Medications Workspace Widget
private struct ActiveMedsWorkspaceWidget: View {
    let medications: [LocalMedication]
    @Binding var reconciledMedIDs: Set<String>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Active Medications Workspace", systemImage: "pills.fill")
                .font(.subheadline.bold())
                .foregroundColor(.clinicalTeal)
            
            if medications.isEmpty {
                Text("No active medications on file")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(medications) { rx in
                        HStack(spacing: 12) {
                            Button {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                    if reconciledMedIDs.contains(rx.rxID) {
                                        reconciledMedIDs.remove(rx.rxID)
                                    } else {
                                        reconciledMedIDs.insert(rx.rxID)
                                    }
                                }
                            } label: {
                                Image(systemName: reconciledMedIDs.contains(rx.rxID) ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundColor(reconciledMedIDs.contains(rx.rxID) ? .clinicalTeal : .secondary)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .buttonStyle(.plain)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rx.medicationName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(reconciledMedIDs.contains(rx.rxID) ? .secondary : .primary)
                                    .strikethrough(reconciledMedIDs.contains(rx.rxID))
                                
                                Text([rx.dose, rx.route, rx.frequency].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " • "))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if reconciledMedIDs.contains(rx.rxID) {
                                Text("Reconciled")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.clinicalTeal)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.clinicalTeal.opacity(0.12), in: Capsule())
                            } else {
                                ClinicalSourceBadge(descriptor: rx.sourceDescriptor)
                            }
                        }
                        .padding(10)
                        .background(
                            Color.clear
                                .liquidGlassCard(
                                    cornerRadius: 10,
                                    borderColor: reconciledMedIDs.contains(rx.rxID) ? Color.clinicalTeal.opacity(0.15) : Color.primary.opacity(0.04),
                                    shadowRadius: 2
                                )
                        )
                    }
                }
            }
        }
    }
}
