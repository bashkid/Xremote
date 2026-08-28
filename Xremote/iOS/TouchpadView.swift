//
//  TouchpadView.swift
//  Dark trackpad panel with Liquid Glass surface that highlights on touch.
//
//  Gestures (powered by the UIKit `TrackpadUIView`):
//    1-finger tap     → left click
//    1-finger drag    → move cursor
//    1-finger 2× tap  → double-click
//    2-finger tap     → right click
//    2-finger drag    → scroll
//    2-finger pinch   → ⌘= / ⌘− (zoom in / out)
//    3-finger tap     → middle click
//    3-finger drag    → drag (mouse button held down)
//

#if os(iOS)

import SwiftUI
import UIKit

struct TouchpadView: View {
    @Bindable var client: XremoteClient

    /// Updated from the UIKit coordinator so we can drive a glow when the
    /// user has fingers on the trackpad.
    @State private var isTouching: Bool = false

    var body: some View {
        VStack(spacing: 14) {
            trackpadPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            clickRow
        }
        .padding()
    }

    // MARK: - Full-boundary trackpad with Liquid Glass

    private var trackpadPanel: some View {
        ZStack {
            // Background fill behind the glass material.
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemBackground))

            // UIKit multi-touch view fills the entire panel — no inner inset.
            TrackpadSurface(client: client, onTouchingChange: { touching in
                if touching != isTouching {
                    withAnimation(.easeOut(duration: 0.18)) { isTouching = touching }
                }
            })
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            // Hint label floats at the top — non-hit-testable so taps fall
            // through to the trackpad below.
            VStack {
                Text("Swipe to scroll, pinch to zoom")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
                Spacer()
            }
            .allowsHitTesting(false)
        }
        .glassEffect(
            .regular.interactive(),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    isTouching ? Color.accentColor.opacity(0.65) : Color.white.opacity(0.06),
                    lineWidth: isTouching ? 2 : 1
                )
        )
        .shadow(
            color: isTouching ? Color.accentColor.opacity(0.35) : .clear,
            radius: isTouching ? 14 : 0,
            x: 0,
            y: 0
        )
    }

    // MARK: - Click buttons

    private var clickRow: some View {
        HStack(spacing: 12) {
            clickButton(label: "Left Click", icon: "cursorarrow.click") {
                client.send(.mouseClick(.left, count: 1))
            }
            clickButton(label: "Right Click", icon: "cursorarrow.click.2") {
                client.send(.mouseClick(.right, count: 1))
            }
        }
    }

    private func clickButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                Text(label)
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.6)
            )
        }
        .buttonStyle(PressableGlassStyle())
    }
}

// MARK: - UIKit trackpad surface

private struct TrackpadSurface: UIViewRepresentable {
    let client: XremoteClient
    var onTouchingChange: (Bool) -> Void

    func makeUIView(context: Context) -> TrackpadUIView {
        let view = TrackpadUIView()
        view.client = client
        view.onTouchingChange = onTouchingChange
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        return view
    }

    func updateUIView(_ uiView: TrackpadUIView, context: Context) {
        uiView.client = client
        uiView.onTouchingChange = onTouchingChange
    }
}

/// Touch-tracking UIView. Counts active fingers and routes their movement to
/// either cursor move, scroll, or drag, plus tap detection for clicks.
private final class TrackpadUIView: UIView {
    weak var client: XremoteClient?
    var onTouchingChange: ((Bool) -> Void)?

    // Sensitivity
    private let moveSensitivity: CGFloat = 1.6
    private let scrollSensitivity: CGFloat = -0.5

    // Gesture state
    private var startTouchTime: TimeInterval = 0
    private var maxFingers: Int = 0
    private var didMove: Bool = false
    private var dragActive: Bool = false
    private var lastTapEnd: TimeInterval = 0
    private var pinchAccumulator: CGFloat = 1.0
    private var anyTouchActive: Bool = false {
        didSet {
            if oldValue != anyTouchActive { onTouchingChange?(anyTouchActive) }
        }
    }

    private let tapMaxDuration: TimeInterval = 0.3
    private let doubleTapWindow: TimeInterval = 0.35

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        let all = event?.allTouches ?? touches
        maxFingers = max(maxFingers, all.count)
        anyTouchActive = true

        if all.count == 1, touches.first != nil {
            startTouchTime = event?.timestamp ?? CACurrentMediaTime()
            didMove = false
            dragActive = false
        }
        if all.count == 3 && !dragActive {
            client?.send(.mouseDown(.left))
            dragActive = true
            Haptic.soft()
        }
        if all.count == 2 {
            pinchAccumulator = 1.0
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        guard let client else { return }
        let all = event?.allTouches ?? touches
        let count = all.count

        var dx: CGFloat = 0, dy: CGFloat = 0
        for touch in all {
            let now = touch.location(in: self)
            let prev = touch.previousLocation(in: self)
            dx += (now.x - prev.x)
            dy += (now.y - prev.y)
        }
        if count > 0 { dx /= CGFloat(count); dy /= CGFloat(count) }
        if abs(dx) + abs(dy) > 1 { didMove = true }

        switch count {
        case 1:
            client.send(.mouseMove(dx: Double(dx * moveSensitivity),
                                   dy: Double(dy * moveSensitivity)))
        case 2:
            if let pinch = currentPinchDelta(for: all) {
                handlePinch(delta: pinch)
            } else {
                client.send(.scroll(dx: Double(dx * -scrollSensitivity),
                                    dy: Double(dy * scrollSensitivity)))
            }
        case 3:
            client.send(.mouseMove(dx: Double(dx * moveSensitivity),
                                   dy: Double(dy * moveSensitivity)))
        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        let all = event?.allTouches ?? Set<UITouch>()
        let stillDown = all.filter { $0.phase != .ended && $0.phase != .cancelled }
        if stillDown.isEmpty {
            finalizeGesture(at: event?.timestamp ?? CACurrentMediaTime())
            anyTouchActive = false
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        if dragActive {
            client?.send(.mouseUp(.left))
            dragActive = false
        }
        resetState()
        anyTouchActive = false
    }

    // MARK: - Gesture resolution

    private func finalizeGesture(at endTime: TimeInterval) {
        defer { resetState() }
        guard let client else { return }

        if dragActive {
            client.send(.mouseUp(.left))
            dragActive = false
            return
        }

        let duration = endTime - startTouchTime
        if !didMove, duration < tapMaxDuration {
            switch maxFingers {
            case 1:
                Haptic.tap()
                if (endTime - lastTapEnd) < doubleTapWindow {
                    client.send(.mouseClick(.left, count: 2))
                    lastTapEnd = 0
                } else {
                    client.send(.mouseClick(.left, count: 1))
                    lastTapEnd = endTime
                }
            case 2:
                Haptic.tap()
                client.send(.mouseClick(.right, count: 1))
            case 3:
                Haptic.tap()
                client.send(.mouseClick(.middle, count: 1))
            default:
                break
            }
        }
    }

    private func resetState() {
        maxFingers = 0
        didMove = false
        pinchAccumulator = 1.0
    }

    // MARK: - Pinch handling

    private func currentPinchDelta(for touches: Set<UITouch>) -> CGFloat? {
        guard let array = Array(touches) as? [UITouch], array.count == 2 else { return nil }
        let nowDistance = distance(array[0].location(in: self),
                                   array[1].location(in: self))
        let prevDistance = distance(array[0].previousLocation(in: self),
                                    array[1].previousLocation(in: self))
        guard prevDistance > 0 else { return nil }
        let translationMagnitude = hypot(
            array[0].location(in: self).x - array[0].previousLocation(in: self).x +
            array[1].location(in: self).x - array[1].previousLocation(in: self).x,
            array[0].location(in: self).y - array[0].previousLocation(in: self).y +
            array[1].location(in: self).y - array[1].previousLocation(in: self).y
        )
        let pinchDelta = abs(nowDistance - prevDistance)
        guard pinchDelta > translationMagnitude * 0.5, pinchDelta > 1.5 else { return nil }
        return nowDistance - prevDistance
    }

    private func handlePinch(delta: CGFloat) {
        guard let client else { return }
        pinchAccumulator += delta / 30
        while pinchAccumulator >= 1 {
            client.send(.keyTap(.equal, modifiers: [.command]))
            pinchAccumulator -= 1
        }
        while pinchAccumulator <= -1 {
            client.send(.keyTap(.minus, modifiers: [.command]))
            pinchAccumulator += 1
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

#endif
