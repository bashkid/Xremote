//
//  PressableGlassStyle.swift
//  Universal press-feedback with a soft chromatic aurora glow when tapped.
//

#if os(iOS)

import SwiftUI

/// Five "aurora" colors used both by the nav-bar glow band and the button
/// press glow, so the two effects feel like they belong to the same system.
enum AuroraPalette {
    static let amber   = Color(red: 1.00, green: 0.78, blue: 0.45)
    static let coral   = Color(red: 1.00, green: 0.45, blue: 0.55)
    static let magenta = Color(red: 0.82, green: 0.38, blue: 0.95)
    static let blue    = Color(red: 0.40, green: 0.55, blue: 1.00)
    static let teal    = Color(red: 0.30, green: 0.85, blue: 0.85)
    static let yellow  = Color(red: 0.95, green: 0.85, blue: 0.40)
}

struct PressableGlassStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Layered chromatic shadows form an aurora halo around the
            // button while it's held. Each color shadow has a different
            // offset so they bleed in different directions, mimicking the
            // reference nav-bar glow.
            .shadow(
                color: configuration.isPressed ? AuroraPalette.coral.opacity(0.55) : .clear,
                radius: configuration.isPressed ? 10 : 0,
                x: -4, y: 0
            )
            .shadow(
                color: configuration.isPressed ? AuroraPalette.magenta.opacity(0.45) : .clear,
                radius: configuration.isPressed ? 14 : 0,
                x: 4, y: -2
            )
            .shadow(
                color: configuration.isPressed ? AuroraPalette.blue.opacity(0.45) : .clear,
                radius: configuration.isPressed ? 18 : 0,
                x: 0, y: 4
            )
            .shadow(
                color: configuration.isPressed ? AuroraPalette.teal.opacity(0.35) : .clear,
                radius: configuration.isPressed ? 12 : 0,
                x: -2, y: -4
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .opacity(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

/// Aurora gradient band that bleeds out behind the nav bar — subtle.
struct NavBarGlowBackground: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    AuroraPalette.amber,
                    AuroraPalette.coral,
                    AuroraPalette.magenta,
                    AuroraPalette.blue,
                    AuroraPalette.teal,
                    AuroraPalette.yellow
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 140)
            .blur(radius: 50)
            .opacity(0.28)

            Spacer(minLength: 0)
        }
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }
}

#endif
