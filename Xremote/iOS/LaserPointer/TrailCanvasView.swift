//
//  TrailCanvasView.swift
//  Hardware-accelerated tapering trail behind the laser cursor.
//

import SwiftUI

struct TrailPoint: Identifiable, Equatable {
    let id = UUID()
    let position: CGPoint
    let timestamp: Date
}

/// Draws an anti-aliased tapering red neon brush along the cursor path.
/// Force-promoted to a Metal-backed graphics context via `.drawingGroup()`
/// so the trail can keep up with 120 Hz pointer updates over long
/// presentation sessions.
struct TrailCanvasView: View {
    let trail: [TrailPoint]
    var maxAge: TimeInterval = 0.6

    private let coreColor = Color(red: 1.0, green: 0.090, blue: 0.278)  // #FF1744
    private let haloColor = Color(red: 1.0, green: 0.227, blue: 0.227)  // #FF3A3A

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, _ in
                draw(context: &context, now: timeline.date)
            }
            .drawingGroup()  // → MTLCommandBuffer for the whole canvas
        }
        .allowsHitTesting(false)
    }

    private func draw(context: inout GraphicsContext, now: Date) {
        guard trail.count >= 2 else { return }

        // Soft halo pass first (under), then crisp core stroke (over).
        for layer in 0..<2 {
            let isCore = layer == 1
            for i in 1..<trail.count {
                let prev = trail[i - 1]
                let here = trail[i]
                let age = now.timeIntervalSince(here.timestamp)
                guard age < maxAge else { continue }

                // Opacity decays linearly with age — recent points are
                // brighter, old ones fade smoothly toward zero.
                let ageAlpha = 1.0 - (age / maxAge)
                // The head of the stroke (newest point) is also wider.
                let headiness = Double(i) / Double(trail.count - 1)

                let baseWidth: Double = isCore ? 4.0 : 12.0
                let width = baseWidth * (0.35 + 0.65 * headiness) * (0.4 + 0.6 * ageAlpha)
                let color = (isCore ? coreColor : haloColor).opacity(isCore ? ageAlpha : ageAlpha * 0.45)

                var path = Path()
                path.move(to: prev.position)
                path.addLine(to: here.position)

                context.stroke(
                    path,
                    with: .color(color),
                    style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }
}
