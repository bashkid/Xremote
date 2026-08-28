//
//  LaserPointerStage.swift
//  iPhone-side trackpad for controlling the Mac's laser-pointer overlay.
//  Touch deltas are forwarded as `.laserMove`; a quick lift that didn't
//  travel becomes a `.laserClick`. The laser cursor itself renders on the
//  Mac screen, not here — this view just shows a touch surface, a style
//  picker, and a Done button.
//

#if os(iOS)

import SwiftUI

struct LaserPointerStage: View {
    @Binding var isActive: Bool
    @Bindable var client: XremoteClient

    @State private var selectedStyle: PointerStyle = .pointingHand
    @State private var lastTouch: CGPoint = .zero
    @State private var didMove: Bool = false
    @State private var trackpadGlow: Bool = false

    // Air-Mouse (gyro) state. Created on demand so the device sensor stays
    // idle while the user only uses the trackpad.
    @State private var gyro = GyroMotionManager()
    @State private var airMouseActive: Bool = false

    var body: some View {
        ZStack {
            // Dark stage background.
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.04, blue: 0.08),
                    Color(red: 0.01, green: 0.01, blue: 0.03)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                topBar
                instructionsLabel
                trackpadSurface
                airMouseButton
                stylePickerRow
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            client.send(.laserShow(style: selectedStyle))
            gyro.onGyroSample = { [client] dx, dy in
                client.send(.gyroDelta(dx: dx, dy: dy))
            }
        }
        .onDisappear {
            gyro.stop()
            client.send(.laserHide())
        }
    }

    // MARK: - Air-Mouse trigger

    private var airMouseButton: some View {
        Button { } label: {
            HStack(spacing: 10) {
                Image(systemName: airMouseActive
                      ? "dot.circle.and.cursorarrow"
                      : "cursorarrow.motionlines")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, isActive: airMouseActive)
                VStack(alignment: .leading, spacing: 2) {
                    Text(airMouseActive ? "Air-Mouse active" : "Hold to point")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Tilt the phone to move the laser")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        airMouseActive
                        ? Color(red: 0.27, green: 0.55, blue: 1.0).opacity(0.85)
                        : Color.white.opacity(0.08)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        airMouseActive
                        ? Color(red: 0.27, green: 0.55, blue: 1.0)
                        : Color.white.opacity(0.15),
                        lineWidth: airMouseActive ? 1.5 : 0.8
                    )
            )
            .shadow(color: airMouseActive
                    ? Color(red: 0.27, green: 0.55, blue: 1.0).opacity(0.45)
                    : .clear,
                    radius: 16)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            // DragGesture(minimumDistance: 0) fires immediately on touch
            // down and again on touch up — perfect press-and-hold gating.
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !airMouseActive else { return }
                    Haptic.soft()
                    airMouseActive = true
                    gyro.start()
                }
                .onEnded { _ in
                    Haptic.soft()
                    airMouseActive = false
                    gyro.stop()
                }
        )
        .accessibilityLabel(airMouseActive ? "Air-Mouse active — release to stop" : "Hold to use Air-Mouse")
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .foregroundStyle(Color(red: 1.0, green: 0.09, blue: 0.27))
                Text("Laser Pointer")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Button {
                Haptic.tap()
                isActive = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
                    .font(.title3)
            }
            .accessibilityLabel("Close laser pointer")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var instructionsLabel: some View {
        Text("Drag inside the pad to steer the laser on your Mac. Quick tap to click.")
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.55))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 6)
    }

    // MARK: - Trackpad

    private var trackpadSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.06))
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    trackpadGlow
                    ? Color(red: 1.0, green: 0.09, blue: 0.27).opacity(0.85)
                    : Color.white.opacity(0.10),
                    lineWidth: trackpadGlow ? 2 : 1
                )

            // Subtle dot in the centre as a hit-target hint.
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 8, height: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .gesture(panGesture)
        .shadow(
            color: trackpadGlow ? Color(red: 1.0, green: 0.09, blue: 0.27).opacity(0.45) : .clear,
            radius: 14
        )
        .animation(.easeOut(duration: 0.15), value: trackpadGlow)
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !trackpadGlow { trackpadGlow = true }
                if lastTouch == .zero {
                    lastTouch = value.location
                    didMove = false
                    return
                }
                let dx = value.location.x - lastTouch.x
                let dy = value.location.y - lastTouch.y
                lastTouch = value.location

                if abs(dx) + abs(dy) > 1.0 { didMove = true }
                if abs(dx) + abs(dy) > 0.1 {
                    client.send(.laserMove(dx: Double(dx), dy: Double(dy)))
                }
            }
            .onEnded { _ in
                if !didMove {
                    Haptic.tap()
                    client.send(.laserClick())
                }
                lastTouch = .zero
                didMove = false
                trackpadGlow = false
            }
    }

    // MARK: - Style picker

    private var stylePickerRow: some View {
        HStack(spacing: 8) {
            ForEach(PointerStyle.allCases) { style in
                Button {
                    Haptic.soft()
                    selectedStyle = style
                    client.send(.laserStyle(style))
                } label: {
                    VStack(spacing: 4) {
                        HandPointerView(style: style)
                            .scaleEffect(0.6)
                            .frame(width: 30, height: 38)
                        Text(style.shortLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selectedStyle == style
                                  ? Color.white.opacity(0.18)
                                  : Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                selectedStyle == style
                                ? Color(red: 1.0, green: 0.09, blue: 0.27)
                                : Color.white.opacity(0.12),
                                lineWidth: selectedStyle == style ? 1.5 : 0.6
                            )
                    )
                }
                .buttonStyle(PressableGlassStyle())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private extension PointerStyle {
    var shortLabel: String {
        switch self {
        case .pointingHand: "Point"
        case .openHand:     "Palm"
        case .arrow:        "Arrow"
        case .pen:          "Pen"
        case .stickHand:    "Stick"
        }
    }
}

#endif
