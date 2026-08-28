//
//  GyroMotionManager.swift
//  Core hardware gyroscope velocity pipeline for the Air-Mouse laser
//  control mode. Captures rotation rates from the iPhone's built-in
//  gyroscope at 60 Hz, converts them into per-frame pixel deltas, and
//  hands each sample to the caller (`onGyroSample`) — typically the
//  Xremote socket layer, which forwards them as `.gyroDelta` packets.
//
//  Streaming is fully gated: nothing leaves the device unless the caller
//  explicitly calls `start()`. The UI wires this to a "press & hold to
//  point" button so the cursor doesn't drift when the user lowers the
//  phone.
//

#if os(iOS)

import CoreMotion
import Observation

@MainActor
@Observable
final class GyroMotionManager {
    /// Rotation-rate (rad/s) → pixels-per-frame scale. Larger is faster.
    /// Spec default: 15.0.
    var sensitivity: Double = 15.0

    /// Fired on every gyro sample while streaming, with the (dx, dy)
    /// delta expressed in screen pixels.
    var onGyroSample: ((Double, Double) -> Void)?

    private(set) var isStreaming = false
    private let motion = CMMotionManager()

    init() {
        // 60 Hz matches typical desktop refresh — and keeps packet rate
        // low enough that even Bonjour-over-Wi-Fi handles it comfortably.
        motion.gyroUpdateInterval = 1.0 / 60.0
    }

    /// Begin streaming. Safe to call repeatedly — no-op if already running
    /// or if the device has no gyro (e.g. iPhone SE 1st gen in Simulator).
    func start() {
        guard !isStreaming else { return }
        guard motion.isGyroAvailable else { return }

        motion.startGyroUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }

            // The user holds the phone like a TV remote — long axis
            // pointed at the projector screen. In that "wand" pose:
            //   • rotationRate.x → pitch  (tilt top of phone up / down)
            //   • rotationRate.z → yaw    (sweep top of phone left / right)
            //   • rotationRate.y → roll   (twist phone around its long
            //                              axis — NOT what we want for
            //                              left/right cursor movement)
            //
            // So vertical cursor follows X (with a sign flip so tilting
            // forward moves the cursor up) and horizontal cursor follows
            // Z (with a sign flip so sweeping the phone right moves the
            // cursor right).
            let dx = -data.rotationRate.z * self.sensitivity
            let dy = -data.rotationRate.x * self.sensitivity
            self.onGyroSample?(dx, dy)
        }
        isStreaming = true
    }

    /// Stop streaming and release the CMMotionManager's update timer.
    func stop() {
        guard isStreaming else { return }
        motion.stopGyroUpdates()
        isStreaming = false
    }
}

#endif
