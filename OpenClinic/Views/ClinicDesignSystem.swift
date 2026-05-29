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

// MARK: - Liquid Glass Card View Modifier
struct LiquidGlassCard: ViewModifier {
    var cornerRadius: CGFloat = 16
    var borderColor: Color? = nil
    var shadowRadius: CGFloat = 8
    var glowColor: Color? = nil
    
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .background(Color.primary.opacity(0.005))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        borderColor ?? Color.clear,
                        lineWidth: borderColor != nil ? 1 : 0
                    )
            )
            .overlay(
                // Liquid glass edge reflections
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.24),
                                .white.opacity(0.06),
                                .black.opacity(0.03),
                                .white.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .background(
                Group {
                    if let glow = glowColor {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(glow.opacity(0.18), lineWidth: 3)
                            .blur(radius: 4)
                    }
                }
            )
            .shadow(color: Color.black.opacity(0.04), radius: shadowRadius, x: 0, y: 4)
    }
}

extension View {
    func liquidGlassCard(cornerRadius: CGFloat = 16, borderColor: Color? = nil, shadowRadius: CGFloat = 8, glowColor: Color? = nil) -> some View {
        modifier(LiquidGlassCard(cornerRadius: cornerRadius, borderColor: borderColor, shadowRadius: shadowRadius, glowColor: glowColor))
    }
}

// MARK: - Ambient Liquid Background (Pulsating mesh shadows)
struct AmbientLiquidBackground: View {
    @State private var animate = false
    
    var body: some View {
        ZStack {
            Color.clinicMainBackground
                .ignoresSafeArea()
            
            GeometryReader { geo in
                ZStack {
                    // Pulsating top-left indigo circle
                    Circle()
                        .fill(Color.clinicalIndigo.opacity(0.06))
                        .frame(width: geo.size.width * (animate ? 0.95 : 0.8), height: geo.size.width * (animate ? 0.95 : 0.8))
                        .blur(radius: 65)
                        .offset(x: -geo.size.width * (animate ? 0.1 : 0.2), y: -geo.size.height * (animate ? 0.08 : 0.18))
                    
                    // Pulsating bottom-right teal circle
                    Circle()
                        .fill(Color.clinicalTeal.opacity(0.05))
                        .frame(width: geo.size.width * (animate ? 0.72 : 0.88), height: geo.size.width * (animate ? 0.72 : 0.88))
                        .blur(radius: 55)
                        .offset(x: geo.size.width * (animate ? 0.42 : 0.32), y: geo.size.height * (animate ? 0.22 : 0.12))

                    // Center-left warm/purple pulsating circle
                    Circle()
                        .fill(Color.clinicalIndigo.opacity(0.04))
                        .frame(width: geo.size.width * (animate ? 0.65 : 0.5), height: geo.size.width * (animate ? 0.65 : 0.5))
                        .blur(radius: 60)
                        .offset(x: geo.size.width * (animate ? 0.05 : 0.15), y: geo.size.height * (animate ? 0.45 : 0.35))
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8.0).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// MARK: - Screen Glow Background
struct ClinicGlowBackground: View {
    var body: some View {
        AmbientLiquidBackground()
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
