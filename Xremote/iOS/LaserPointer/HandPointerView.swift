//
//  HandPointerView.swift
//  Renders the laser-pointer cursor by wrapping an SF Symbol in the
//  Xremote "red neon laser" treatment: emission halo + gradient fill +
//  glass highlight + outer glow shadow.
//

import SwiftUI

struct HandPointerView: View {
    let style: PointerStyle

    // Color tokens carried forward from the original spec.
    private let emission = Color(red: 1.000, green: 0.231, blue: 0.188)  // #FF3B30
    private let glowTop  = Color(red: 1.000, green: 0.353, blue: 0.322)  // #FF5A52
    private let glowMid  = Color(red: 1.000, green: 0.090, blue: 0.278)  // #FF1744
    private let glowBot  = Color(red: 0.690, green: 0.000, blue: 0.125)  // #B00020

    /// Glyph size — fits comfortably inside the 40×50 frame.
    private let glyphSize: CGFloat = 28

    var body: some View {
        ZStack {
            // 1. Ambient emission — blurred halo behind the glyph.
            symbol
                .foregroundStyle(emission)
                .blur(radius: 10)
                .opacity(0.85)

            // 2. Neon gradient fill — the main red body of the cursor.
            symbol
                .foregroundStyle(
                    LinearGradient(
                        colors: [glowTop, glowMid, glowBot],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // 3. Glass highlight — soft white wash on the top of the glyph.
            symbol
                .foregroundStyle(.white)
                .opacity(0.35)
                .blendMode(.overlay)
        }
        .frame(width: 40, height: 50)
        .compositingGroup()
        .shadow(color: glowMid.opacity(0.55), radius: 14, x: 0, y: 0)
    }

    private var symbol: some View {
        Image(systemName: style.symbolName)
            .font(.system(size: glyphSize, weight: .bold))
            .symbolRenderingMode(.monochrome)
    }
}

extension PointerStyle {
    /// SF Symbol used to render the cursor for each style. We deliberately
    /// pick symbols that exist across SF Symbols 1+ so they always render
    /// (some newer specialised names render as blank glyphs on shipping
    /// iOS / macOS releases).
    var symbolName: String {
        switch self {
        case .pointingHand: "hand.point.up.fill"
        case .openHand:     "hand.raised.fill"
        case .arrow:        "cursorarrow"
        case .pen:          "pencil.tip"
        case .stickHand:    "wand.and.rays"
        }
    }
}

// MARK: - Previews

#Preview("All styles") {
    HStack(spacing: 12) {
        ForEach(PointerStyle.allCases) { style in
            VStack(spacing: 6) {
                HandPointerView(style: style)
                Text(style.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    .padding()
    .background(Color.black)
}
