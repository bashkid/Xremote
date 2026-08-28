//
//  FloatingVoiceButton.swift
//  Persistent mic-anywhere button overlaid on every non-Voice tab.
//
//  Two-mode gesture on the capsule:
//
//    • Stationary press (translation stays within ~25 pt) → records a
//      quick voice command and streams it through the existing
//      voice → openclaw pipeline. Release sends it.
//
//    • Drag (translation > 25 pt) → drops out of record mode and lets
//      the user reposition the button anywhere inside the tab's content
//      area. Position is persisted in @AppStorage so it stays put
//      across tab switches and app launches.
//
//  When the Mac pushes back a response, a translucent toast pops above
//  the button (auto-dismisses after 6 s).
//

#if os(iOS)

import SwiftUI

struct FloatingVoiceButton: View {
    @Bindable var client: XremoteClient

    @State private var voice = VoiceStreamingManager()
    @State private var isRecording = false
    @State private var pulse = false
    @State private var lastError: String?
    @State private var toastText: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var lastSeenResponse: String?

    // Persisted position (in container coords). -1 = use default
    // (bottom-trailing). Clamped to current bounds on every render so the
    // button never lands off-screen after a rotation / size change.
    @AppStorage("XRMicPosX") private var savedPosX: Double = -1
    @AppStorage("XRMicPosY") private var savedPosY: Double = -1

    @State private var dragOffset: CGSize = .zero
    @State private var isMoving = false

    private let accentRed = Color(red: 1.0, green: 0.20, blue: 0.27)
    private let buttonRadius: CGFloat = 32
    /// Movement threshold (pt) before a press is treated as a drag.
    private let dragThreshold: CGFloat = 25

    var body: some View {
        GeometryReader { geo in
            let base = resolvedCenter(in: geo.size)
            let display = CGPoint(
                x: base.x + dragOffset.width,
                y: base.y + dragOffset.height
            )

            ZStack(alignment: .topLeading) {
                Color.clear
                floatingContent
                    .position(x: display.x, y: display.y)
                    .gesture(makeGesture(geo: geo, base: base))
            }
        }
        .allowsHitTesting(true)
        .onAppear { wireCallbacks() }
        // When the Mac pushes back a response, flash a toast above the
        // button so the user knows the task finished without jumping to
        // the Voice tab.
        .onChange(of: client.lastTaskResponse) { _, new in
            guard let new, new != lastSeenResponse else { return }
            lastSeenResponse = new
            presentToast(new)
        }
    }

    private var floatingContent: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if let toast = toastText {
                responseToast(toast)
            }
            micCapsule
        }
    }

    // MARK: - Position resolution + clamping

    private func resolvedCenter(in size: CGSize) -> CGPoint {
        // First launch — anchor bottom-right with safe insets.
        if savedPosX < 0 || savedPosY < 0 {
            return CGPoint(
                x: max(buttonRadius + 16, size.width - buttonRadius - 16),
                y: max(buttonRadius + 16, size.height - buttonRadius - 60)
            )
        }
        return clamp(CGPoint(x: savedPosX, y: savedPosY), in: size)
    }

    private func clamp(_ p: CGPoint, in size: CGSize) -> CGPoint {
        let xMin = buttonRadius + 8
        let xMax = max(xMin, size.width - buttonRadius - 8)
        let yMin = buttonRadius + 8
        let yMax = max(yMin, size.height - buttonRadius - 16)
        return CGPoint(
            x: min(max(xMin, p.x), xMax),
            y: min(max(yMin, p.y), yMax)
        )
    }

    // MARK: - Gesture

    private func makeGesture(geo: GeometryProxy, base: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let dist = hypot(value.translation.width, value.translation.height)

                // Step 1: stationary press at the very start kicks off
                // recording. Only fires once per gesture (`!isRecording`).
                if !isMoving && !isRecording && dist < 4 {
                    Task { await startRecording() }
                }

                // Step 2: cross the drag threshold → switch to move mode.
                // Cancels any in-progress recording so we don't leave the
                // mic open while the user repositions the button.
                if !isMoving && dist > dragThreshold {
                    if isRecording {
                        stopRecordingSilently()
                    }
                    isMoving = true
                    Haptic.tap()
                }

                // Step 3: while moving, track the finger (clamped).
                if isMoving {
                    let raw = CGPoint(
                        x: base.x + value.translation.width,
                        y: base.y + value.translation.height
                    )
                    let clamped = clamp(raw, in: geo.size)
                    dragOffset = CGSize(
                        width: clamped.x - base.x,
                        height: clamped.y - base.y
                    )
                }
            }
            .onEnded { value in
                if isMoving {
                    let raw = CGPoint(
                        x: base.x + value.translation.width,
                        y: base.y + value.translation.height
                    )
                    let final = clamp(raw, in: geo.size)
                    savedPosX = final.x
                    savedPosY = final.y
                    dragOffset = .zero
                    isMoving = false
                    Haptic.soft()
                } else if isRecording {
                    stopRecording()
                }
            }
    }

    // MARK: - Mic capsule

    private var micCapsule: some View {
        ZStack {
            if isRecording {
                Circle()
                    .fill(accentRed.opacity(0.25))
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulse ? 1.18 : 0.95)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                               value: pulse)
            }
            Circle()
                .fill(
                    LinearGradient(
                        colors: isRecording
                        ? [accentRed, Color(red: 0.78, green: 0.05, blue: 0.17)]
                        : (isMoving
                           ? [Color.accentColor.opacity(0.65), Color.accentColor.opacity(0.35)]
                           : [Color.accentColor, Color.accentColor.opacity(0.75)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 58, height: 58)
                .overlay(
                    Image(systemName: isRecording
                          ? "waveform"
                          : (isMoving ? "arrow.up.and.down.and.arrow.left.and.right" : "mic.fill"))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: isRecording)
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isMoving ? 0.85 : 0.0), lineWidth: 2)
                )
                .shadow(color: (isRecording ? accentRed : Color.accentColor).opacity(0.45),
                        radius: 14, x: 0, y: 6)
                .scaleEffect(isRecording ? 0.97 : (isMoving ? 1.10 : 1.0))
                .animation(.spring(response: 0.22, dampingFraction: 0.7),
                           value: isRecording)
                .animation(.spring(response: 0.22, dampingFraction: 0.7),
                           value: isMoving)
        }
        .contentShape(Circle())
        .accessibilityLabel(isRecording
                            ? "Recording voice — release to send"
                            : (isMoving
                               ? "Drag to a new spot — release to drop"
                               : "Hold to record a quick voice task, drag to reposition"))
    }

    // MARK: - Response toast

    private func responseToast(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .foregroundStyle(.purple)
                Text("openclaw")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button {
                    dismissToast()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Text(text)
                .font(.caption)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
        }
        .padding(10)
        .frame(maxWidth: 300, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.purple.opacity(0.30), lineWidth: 0.6)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 6)
        .transition(
            .scale(scale: 0.85, anchor: .bottomTrailing)
            .combined(with: .opacity)
        )
    }

    private func presentToast(_ text: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            toastText = text
        }
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            dismissToast()
        }
    }

    private func dismissToast() {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            toastText = nil
        }
    }

    // MARK: - Recording lifecycle

    private func wireCallbacks() {
        voice.onChunkRecorded = { data in
            client.send(.voiceChunk(data))
        }
        voice.onError = { error in
            lastError = error.localizedDescription
            isRecording = false
            pulse = false
            client.send(.voiceStop())
        }
    }

    private func startRecording() async {
        Haptic.tap()
        lastError = nil
        client.send(.voiceStart())
        do {
            try await voice.start()
            // Guard: the user might have dragged before voice.start() returned.
            if isMoving { voice.stop(); return }
            isRecording = true
            pulse = true
        } catch {
            lastError = error.localizedDescription
            client.send(.voiceStop())
        }
    }

    /// Normal release while recording → send the voice task.
    private func stopRecording() {
        guard isRecording else { return }
        Haptic.soft()
        voice.stop()
        client.send(.voiceStop())
        isRecording = false
        pulse = false
    }

    /// Recording aborted because the user started dragging instead.
    /// Closes the mic without surfacing the (empty) transcript.
    private func stopRecordingSilently() {
        voice.stop()
        client.send(.voiceStop())
        isRecording = false
        pulse = false
    }
}

#endif
