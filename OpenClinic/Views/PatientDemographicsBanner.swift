//
//  PatientDemographicsBanner.swift
//  OpenClinic
//
//  Created by Gunnar Hostetler on 2026.
//

import SwiftUI

struct PatientDemographicsBanner: View {
    let profile: PatientProfile
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                // Initials Avatar with medical-theme gradient
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.clinicalIndigo, Color.clinicalTeal.opacity(0.8)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 46, height: 46)
                    .overlay(
                        Text("\(String(profile.firstName.prefix(1)))\(String(profile.lastName.prefix(1)))")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .center, spacing: 6) {
                        Text(profile.fullName)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .layoutPriority(1)

                        if profile.hasDied {
                            Text("Deceased")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundColor(.primary)
                        }
                        
                        Text("MRN: \(profile.medicalRecordNumber)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 8) {
                        Text(profile.gender)
                        Text("•")
                        Text(ageLine)
                        if let blood = profile.bloodType {
                            Text("•")
                            Text("Type \(blood)")
                                .fontWeight(.semibold)
                                .foregroundColor(.criticalRed)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Toggle Button for details drawer
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.clinicalIndigo)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .padding(8)
                        .background(Color.clinicalIndigo.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }
            
            // Expandable details drawer
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                        .padding(.vertical, 2)
                    
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                        if let clinician = profile.primaryClinician {
                            GridRow {
                                Text("Primary Clinician")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(clinician)
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                        if let pharmacy = profile.preferredPharmacy {
                            GridRow {
                                Text("Preferred Rx")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(pharmacy)
                                    .font(.subheadline)
                            }
                        }
                        if let contactName = profile.emergencyContactName {
                            GridRow {
                                Text("Emergency Contact")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contactName)
                                        .font(.subheadline.weight(.medium))
                                    if let contactPhone = profile.emergencyContactPhone {
                                        Text(contactPhone)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    
                    // Care plan summary block
                    if let summary = profile.carePlanSummary, !summary.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Care Plan Summary")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                            
                            Text(summary)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .lineSpacing(2)
                                .padding(8)
                                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
                                )
                        }
                        .padding(.top, 4)
                    }
                    
                    // Risk flags and allergies tags
                    VStack(alignment: .leading, spacing: 8) {
                        if !profile.allergies.isEmpty {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.clinicalAmber)
                                    .padding(.top, 3)
                                
                                FlowLayout(spacing: 4) {
                                    ForEach(profile.allergies, id: \.self) { allergy in
                                        Text(allergy)
                                            .font(.system(size: 10, weight: .medium, design: .rounded))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(Color.clinicalAmber.opacity(0.12), in: Capsule())
                                            .foregroundColor(.clinicalAmber)
                                    }
                                }
                            }
                        }
                        
                        if !profile.riskFlags.isEmpty {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "flag.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.criticalRed)
                                    .padding(.top, 3)
                                
                                FlowLayout(spacing: 4) {
                                    ForEach(profile.riskFlags, id: \.self) { flag in
                                        Text(flag)
                                            .font(.system(size: 10, weight: .medium, design: .rounded))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(Color.criticalRed.opacity(0.1), in: Capsule())
                                            .foregroundColor(.criticalRed)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: 16)
    }
    
    /// "Age 33 (Mar 12, 1993)", or the date and age of death for a patient who has died.
    private var ageLine: String {
        // With no date of birth at the source there is no age to show, and no date is made up.
        guard profile.hasKnownBirthDate else {
            guard profile.hasDied else { return "Date of birth not recorded at source" }
            guard let died = profile.deceasedDate else { return "Deceased. Dates of birth and death not recorded at source" }
            return "Died \(formattedDate(died, precision: profile.deceasedDatePrecision)). Date of birth not recorded at source"
        }
        let born = formattedDate(profile.dateOfBirth, precision: profile.dateOfBirthPrecision)
        guard profile.hasDied else { return "Age \(profile.ageText) (\(born))" }
        guard let died = profile.deceasedDate else { return "Deceased, date not recorded (born \(born))" }
        return "Died \(formattedDate(died, precision: profile.deceasedDatePrecision)) at age \(profile.ageText) (born \(born))"
    }

    /// A date the source stated only to the year or month is written that way, never as its first day.
    private func formattedDate(_ date: Date, precision: String?) -> String {
        precision == nil ? formattedDate(date) : ChartDateText.text(date, precision: precision)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// Simple custom FlowLayout for tag views
struct FlowLayout: Layout {
    var spacing: CGFloat
    
    init(spacing: CGFloat = 6) {
        self.spacing = spacing
    }
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxWidth: CGFloat = 0
        
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > width {
                maxWidth = max(maxWidth, currentX)
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        
        return CGSize(width: max(maxWidth, currentX), height: currentY + lineHeight)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX: CGFloat = bounds.minX
        var currentY: CGFloat = bounds.minY
        var lineHeight: CGFloat = 0
        
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}