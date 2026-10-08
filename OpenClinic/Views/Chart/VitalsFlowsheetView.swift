//
//  VitalsFlowsheetView.swift
//  OpenClinic
//
//  The latest value of each vital sign on the chart, with its date, and the
//  trend behind it. Every number shown is a stored observation. When the chart
//  has no vital signs the view says so; it never fills the space with a guess.
//

import SwiftUI
import Charts

/// One vital sign and its readings, newest first.
struct VitalSeries: Identifiable {
    let id: String
    let label: String
    let icon: String
    let readings: [ChartObservation]

    var latest: ChartObservation? { readings.first }

    /// The numeric readings in time order, for a trend line. Blood pressure plots its systolic value.
    var numericPoints: [(date: Date, value: Double)] {
        readings.reversed().compactMap { observation in
            guard let date = observation.effectiveDate else { return nil }
            if let number = observation.valueNumber { return (date, number) }
            for component in observation.components where component.code.code == ObservationCode.systolic {
                if case .quantity(let number, _) = component.value { return (date, number) }
            }
            return nil
        }
    }
}

enum VitalSigns {
    /// The vitals the flowsheet gives a tile to, in display order.
    private static let layout: [(id: String, label: String, icon: String, codes: Set<String>)] = [
        ("bp", "Blood Pressure", "heart.text.square", [ObservationCode.bloodPressurePanel, "55284-4"]),
        ("hr", "Heart Rate", "heart.fill", [ObservationCode.heartRate]),
        ("rr", "Respiratory Rate", "lungs.fill", [ObservationCode.respiratoryRate]),
        ("temp", "Temperature", "thermometer.medium", [ObservationCode.bodyTemperature, ObservationCode.oralTemperature]),
        ("spo2", "Oxygen Saturation", "waveform.path.ecg", [ObservationCode.oxygenSaturation, ObservationCode.oxygenSaturationPulseOx]),
        ("weight", "Weight", "scalemass", [ObservationCode.bodyWeight]),
        ("height", "Height", "ruler", [ObservationCode.bodyHeight]),
        ("bmi", "Body Mass Index", "figure", [ObservationCode.bodyMassIndex]),
        ("pain", "Pain (0 to 10)", "bolt.heart", [ObservationCode.painSeverity]),
    ]

    /// Groups the chart's vital-sign observations into series, skipping vitals with no readings.
    static func series(from observations: [ChartObservation]) -> [VitalSeries] {
        let vitals = observations.filter { $0.category == "vital-signs" && !$0.isRemovedAtSource }
        return layout.compactMap { entry in
            let readings = vitals
                .filter { observation in
                    if let code = observation.code, entry.codes.contains(code) { return true }
                    // A blood pressure panel is recognized by its parts when the panel code is unfamiliar.
                    return entry.id == "bp" && ObservationFormatting.bloodPressure(from: observation.components) != nil
                }
                .sorted { ($0.effectiveDate ?? .distantPast) > ($1.effectiveDate ?? .distantPast) }
            guard !readings.isEmpty else { return nil }
            return VitalSeries(id: entry.id, label: entry.label, icon: entry.icon, readings: readings)
        }
    }
}

struct VitalsFlowsheetView: View {
    let patient: PatientProfile
    @State private var selectedSeries: VitalSeries?

    private var series: [VitalSeries] {
        VitalSigns.series(from: patient.observations ?? [])
    }

    private let columns = [GridItem(.adaptive(minimum: 132, maximum: 220), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Vital Signs", systemImage: "waveform.path.ecg")
                .font(.subheadline.bold())
                .foregroundStyle(Color.clinicalIndigo)

            if series.isEmpty {
                Text("No vital signs recorded on this chart.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.clinicTertiarySystemBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(series) { item in
                        Button {
                            selectedSeries = item
                        } label: {
                            VitalTile(series: item)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows every reading and the trend")
                    }
                }
            }
        }
        .sheet(item: $selectedSeries) { item in
            VitalTrendView(series: item)
        }
    }
}

private struct VitalTile: View {
    let series: VitalSeries

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: series.icon)
                    .font(.caption)
                    .foregroundStyle(Color.clinicalTeal)
                Spacer()
                if series.readings.count > 1 {
                    Text("\(series.readings.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(series.readings.count) readings")
                }
            }
            Text(series.latest?.displayValue ?? "")
                .font(.system(.title3, design: .rounded).bold())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(series.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let date = series.latest?.effectiveDate {
                Text(date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.clear
                .liquidGlassCard(cornerRadius: 12, borderColor: Color.clinicalTeal.opacity(0.12), shadowRadius: 3)
        )
        .accessibilityElement(children: .combine)
    }
}

/// Every reading of one vital sign, with a trend line when there are at least two numbers.
private struct VitalTrendView: View {
    let series: VitalSeries
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let points = series.numericPoints
                if points.count >= 2 {
                    Section {
                        Chart {
                            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                                LineMark(x: .value("Date", point.date), y: .value(series.label, point.value))
                                    .interpolationMethod(.monotone)
                                PointMark(x: .value("Date", point.date), y: .value(series.label, point.value))
                            }
                        }
                        .foregroundStyle(Color.clinicalTeal)
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 180)
                        .accessibilityLabel("\(series.label) trend, \(points.count) readings")
                    } footer: {
                        if series.id == "bp" {
                            Text("The line shows systolic pressure.")
                        }
                    }
                }

                Section("Readings") {
                    ForEach(series.readings, id: \.qualifiedID) { reading in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(reading.displayValue)
                                    .font(.body.monospacedDigit())
                                if let date = reading.effectiveDate {
                                    Text(date, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            ClinicalSourceBadge(descriptor: reading.sourceDescriptor)
                        }
                    }
                }
            }
            .navigationTitle(series.label)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
