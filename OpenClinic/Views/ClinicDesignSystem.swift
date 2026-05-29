//
//  ClinicDesignSystem.swift
//  OpenClinic
//
//  Created by Gunnar Hostetler on 2026.
//

import SwiftUI

// MARK: - Clinic Colors
extension Color {
    static let clinicalTeal = Color(red: 0.05, green: 0.58, blue: 0.53) // #0D9488
    static let clinicalIndigo = Color(red: 0.31, green: 0.27, blue: 0.90) // #4F46E5
    static let clinicalAmber = Color(red: 0.85, green: 0.47, blue: 0.02) // #D97706
    static let criticalRed = Color(red: 0.86, green: 0.15, blue: 0.15) // #DC2626
    static let clinicalSlate = Color(red: 0.28, green: 0.33, blue: 0.41) // #475569
    
    static let clinicRowBackground = Color(UIColor.secondarySystemGroupedBackground)
    static let clinicMainBackground = Color(UIColor.systemGroupedBackground)
}

// MARK: - Glassmorphic Card View Modifier
struct GlassmorphicCard: ViewModifier {
    var cornerRadius: CGFloat = 16
    var borderColor: Color = Color.primary.opacity(0.06)
    var shadowRadius: CGFloat = 8
    
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(Color.primary.opacity(0.01))
            .cornerRadius(cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.03), radius: shadowRadius, x: 0, y: 4)
    }
}

extension View {
    func glassmorphicCard(cornerRadius: CGFloat = 16, borderColor: Color = Color.primary.opacity(0.06), shadowRadius: CGFloat = 8) -> some View {
        modifier(GlassmorphicCard(cornerRadius: cornerRadius, borderColor: borderColor, shadowRadius: shadowRadius))
    }
}

// MARK: - Screen Glow Background
struct ClinicGlowBackground: View {
    var body: some View {
        ZStack {
            Color.clinicMainBackground
                .ignoresSafeArea()
            
            // Soft ambient lighting
            GeometryReader { geo in
                ZStack {
                    Circle()
                        .fill(Color.clinicalIndigo.opacity(0.08))
                        .frame(width: geo.size.width * 0.8, height: geo.size.width * 0.8)
                        .blur(radius: 60)
                        .offset(x: -geo.size.width * 0.2, y: -geo.size.height * 0.15)
                    
                    Circle()
                        .fill(Color.clinicalTeal.opacity(0.06))
                        .frame(width: geo.size.width * 0.7, height: geo.size.width * 0.7)
                        .blur(radius: 50)
                        .offset(x: geo.size.width * 0.4, y: geo.size.height * 0.2)
                }
            }
        }
    }
}

// MARK: - Visual Accent Line
struct VisualAccentLine: View {
    let color: Color
    var width: CGFloat = 3
    var height: CGFloat = 36
    
    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(width: width, height: height)
    }
}
