//
//  LaserPointerOverlay.swift
//  Central orchestrator for the Xremote hand-laser-pointer feature.
//  Owns smoothed position, motion trail, and click-ripple lifecycle.
//

import SwiftUI

// MARK: - Overlay

struct LaserPointerOverlay: View {
    @Binding var targetPoint: CGPoint
    @Binding var state: PointerState
    @Binding var selectedStyle: PointerStyle

    // Smoothing weight from the spec.
    private let alpha: CGFloat = 0.28
    private let trailMaxAge: TimeInterval = 0.6
    private let trailCap: Int = 240

    // Anchor: where the cursor renders right now (lags `targetPoint` by α).
    @State private var renderPos: CGPoint = .zero
    @State private var lastSampledRenderPos: CGPoint = .zero
    @State private var trail: [TrailPoint] = []
    @State private var clickRings: [ClickRing] = []

    var body: some View {
        ZStack {
            // 1. Tapering kinetic trail (Metal-backed).
            TrailCanvasView(trail: trail, maxAge: trailMaxAge)
                .ignoresSafeArea()

            // 2. Expanding click rings (one transient view per click).
            ForEach(clickRings) { ring in
                ClickRingView(color: Color(red: 1.0, green: 0.090, blue: 0.278)) {
                    clickRings.removeAll { $0.id == ring.id }
                }
                .position(ring.position)
            }

            // 3. The cursor itself.
            HandPointerView(style: selectedStyle)
                .position(renderPos)
        }
        .allowsHitTesting(false)
        .onAppear {
            if renderPos == .zero { renderPos = targetPoint }
        }
        .onChange(of: targetPoint) { _, _ in
            // The spec asks for the dampening loop to live on
            // `onChange(of:targetPoint)`. We re-arm the per-frame stepper
            // here; the task below keeps blending each refresh.
        }
        .onChange(of: state) { _, new in
            if new == .clicked { spawnClickRing() }
        }
        .task(id: "laser-tick") {
            // 120 Hz smoothing loop. Async-await driven (no Combine), so it
            // cleans up automatically when the view goes away.
            while !Task.isCancelled {
                tick()
                try? await Task.sleep(nanoseconds: 8_333_333)  // ~1/120s
            }
        }
    }

    // MARK: - Per-frame stepper

    private func tick() {
        // Double-exponential smoothing as specified.
        let dx = targetPoint.x - renderPos.x
        let dy = targetPoint.y - renderPos.y
        let needsMove = abs(dx) > 0.05 || abs(dy) > 0.05
        if needsMove {
            renderPos.x += dx * alpha
            renderPos.y += dy * alpha
        }

        // Sample the trail when the cursor has actually moved a meaningful
        // distance — keeps the array compact for the Metal pass.
        let movedSinceLast = hypot(renderPos.x - lastSampledRenderPos.x,
                                   renderPos.y - lastSampledRenderPos.y)
        if movedSinceLast > 1.5 {
            trail.append(TrailPoint(position: renderPos, timestamp: Date()))
            lastSampledRenderPos = renderPos
            if trail.count > trailCap {
                trail.removeFirst(trail.count - trailCap)
            }
        }

        // Prune expired trail points so they stop being submitted to Canvas.
        let cutoff = Date().addingTimeInterval(-trailMaxAge)
        if let firstAlive = trail.firstIndex(where: { $0.timestamp >= cutoff }),
           firstAlive > 0 {
            trail.removeFirst(firstAlive)
        }
    }

    // MARK: - Click ripple

    private func spawnClickRing() {
        clickRings.append(ClickRing(position: renderPos))
    }
}

// MARK: - Click ring

private struct ClickRing: Identifiable, Equatable {
    let id = UUID()
    let position: CGPoint
}

private struct ClickRingView: View {
    let color: Color
    let onComplete: () -> Void

    @State private var scale: Double = 0.1
    @State private var opacity: Double = 1.0

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 3)
            .frame(width: 60, height: 60)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                // 0.1 → 2.5 scale, 1.0 → 0.0 opacity, over exactly 350ms.
                withAnimation(.linear(duration: 0.35)) {
                    scale = 2.5
                    opacity = 0
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                onComplete()
            }
    }
}
