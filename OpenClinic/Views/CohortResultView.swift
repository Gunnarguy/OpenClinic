//
//  CohortResultView.swift
//  OpenClinic
//
//  Shows a computed panel answer: how many patients match, which chart facts
//  made each one match, and what the computation was.
//

import SwiftUI

struct CohortResultView: View {
    let result: CohortResult

    /// Evidence rows shown per patient before the rest collapse into a count.
    private let visibleEvidenceLimit = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if result.matches.isEmpty {
                Text("No chart in the panel satisfies this question.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(result.matches) { match in
                        CohortMatchRow(match: match, presentation: result.query.presentation, evidenceLimit: visibleEvidenceLimit)
                    }
                }
            }

            if !result.related.isEmpty {
                relatedSection
            }

            provenanceFooter
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(CohortAnswerFormatter.headline(for: result))
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            if let window = result.window {
                // The interval end is the first instant after the window.
                let lastDay = window.end.addingTimeInterval(-1)
                Label {
                    Text(window.start...lastDay)
                } icon: {
                    Image(systemName: "calendar")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Related

    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Related, not counted", systemImage: "arrow.triangle.branch")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(result.related) { match in
                CohortMatchRow(match: match, presentation: .cohort, evidenceLimit: visibleEvidenceLimit)
                    .opacity(0.85)
            }
        }
        .padding(.top, 2)
    }

    // MARK: Footer

    private var provenanceFooter: some View {
        Label {
            Text(CohortAnswerFormatter.provenanceLine)
        } icon: {
            Image(systemName: "function")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }
}

// MARK: - Match row

private struct CohortMatchRow: View {
    let match: CohortMatch
    let presentation: CohortQuery.Presentation
    let evidenceLimit: Int

    private var visibleEvidence: [CohortEvidence] { Array(match.evidence.prefix(evidenceLimit)) }
    private var hiddenCount: Int { max(0, match.evidence.count - evidenceLimit) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(initials)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.clinicalIndigo)
                .frame(width: 34, height: 34)
                .background(Color.clinicalIndigo.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(match.name)
                        .font(.subheadline.weight(.semibold))
                    Text(match.mrn)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(match.ageIsKnown ? "\(match.age)y \(match.sex)" : "age not recorded, \(match.sex)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }

                ForEach(visibleEvidence) { evidence in
                    CohortEvidenceRow(evidence: evidence, showsTime: presentation == .schedule)
                }

                if hiddenCount > 0 {
                    Text("and \(hiddenCount) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.clinicTertiarySystemBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var initials: String {
        match.name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
            .uppercased()
    }
}

// MARK: - Evidence row

private struct CohortEvidenceRow: View {
    let evidence: CohortEvidence
    let showsTime: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
                .frame(width: 16)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(evidence.label)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                if !detailLine.isEmpty {
                    Text(detailLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if showsSourceID {
                Text(evidence.sourceID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.05), in: Capsule())
                    .accessibilityLabel("Source \(evidence.sourceID)")
            }
        }
    }

    /// Record, prescription and appointment identifiers are shown. Facts stored
    /// on the patient have no identifier of their own.
    private var showsSourceID: Bool {
        switch evidence.kind {
        case .diagnosis, .medication, .appointment, .documentation: return true
        case .allergy, .riskFlag, .socialHistory, .demographic: return false
        }
    }

    private var detailLine: String {
        var parts: [String] = []
        if let date = evidence.date {
            if evidence.kind == .appointment {
                parts.append(showsTime && Calendar.current.isDateInToday(date)
                    ? date.formatted(date: .omitted, time: .shortened)
                    : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
            } else {
                parts.append(date.formatted(date: .abbreviated, time: .omitted))
            }
        }
        if let detail = evidence.detail, !detail.isEmpty {
            parts.append(detail)
        }
        return parts.joined(separator: " · ")
    }

    private var icon: String {
        switch evidence.kind {
        case .diagnosis: return "cross.case"
        case .medication: return "pills"
        case .allergy: return "exclamationmark.triangle"
        case .riskFlag: return "flag"
        case .socialHistory: return "person.text.rectangle"
        case .appointment: return "calendar"
        case .demographic: return "person"
        case .documentation: return "doc.text"
        }
    }

    private var tint: Color {
        switch evidence.kind {
        case .diagnosis: return .criticalRed
        case .medication: return .clinicalTeal
        case .allergy: return .clinicalAmber
        case .riskFlag: return .clinicalAmber
        case .appointment: return .clinicalIndigo
        case .documentation: return .clinicalIndigo
        case .socialHistory, .demographic: return .clinicalSlate
        }
    }
}
