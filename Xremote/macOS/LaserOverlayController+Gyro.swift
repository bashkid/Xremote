//
//  LaserOverlayController+Gyro.swift
//  Air-Mouse consumer. Each `.gyroDelta` packet that arrives over the
//  wire is funnelled into `applyGyroDelta`, which:
//
//    1. Smooths the raw gyro reading with a first-order exponential
//       filter (α = 0.3) so the natural micro-tremor in the user's hand
//       doesn't shake the laser dot on a 4 K display.
//    2. Additively offsets the existing laser cursor position — so
//       trackpad input and gyro input stack cleanly. No regression to
//       the multi-touch movement code in `LaserPointerOverlay`.
//    3. Clamps the result inside `NSScreen.main.frame` so the cursor can
//       never leave the physical display.
//

#if os(macOS)

import AppKit

extension LaserOverlayController {

    /// Smoothing constant. Lower = smoother / laggier; higher = snappier
    /// but jitterier. 0.3 is the spec's tested-comfortable midpoint.
    private static var smoothingAlpha: Double { 0.3 }

    /// Process one (dx, dy) sample from the iPhone gyro pipeline.
    func applyGyroDelta(dx: Double, dy: Double) {
        // Only honour gyro input while the laser overlay is actually on
        // screen — keeps the cursor still when the user's not pointing.
        guard viewModel.isVisible else { return }

        let alpha = Self.smoothingAlpha
        viewModel.smoothedDx = alpha * dx + (1.0 - alpha) * viewModel.smoothedDx
        viewModel.smoothedDy = alpha * dy + (1.0 - alpha) * viewModel.smoothedDy

        var p = viewModel.targetPoint
        p.x += viewModel.smoothedDx
        p.y += viewModel.smoothedDy

        // Clamp to the main screen so the dot can't drift off the display.
        if let frame = NSScreen.main?.frame {
            p.x = min(max(0, p.x), frame.width)
            p.y = min(max(0, p.y), frame.height)
        }
        viewModel.targetPoint = p

        if viewModel.state != .moving { viewModel.state = .moving }
    }

    /// Reset the smoothing filter to zero — called when the user releases
    /// the air-mouse trigger so a stale tremor isn't carried into the
    /// next press.
    func resetGyroSmoothing() {
        viewModel.smoothedDx = 0
        viewModel.smoothedDy = 0
    }
}

#endif
