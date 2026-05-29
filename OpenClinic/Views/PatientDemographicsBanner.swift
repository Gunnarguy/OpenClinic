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
                        
                        Text("MRN: \(profile.medicalRecordNumber)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                            .foregroundColor(.secondary)
                    }
                    
                    HStack(spacing: 8) {
                        Text(profile.gender)
                        Text("•")
                        Text("Age \(profile.age) (\(formattedDate(profile.dateOfBirth)))")
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
        .glassmorphicCard()
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