//
//  VoiceView.swift
//  Press-and-hold mic + typed-task field for the voice → on-device
//  transcription → OpenClaw automation pipeline. The full agent response
//  is shown in a scrollable card; tap "Hear it" for the TTS playback.
//

#if os(iOS)

import SwiftUI
import AVFoundation

struct VoiceView: View {
    @Bindable var client: XremoteClient

    @State private var voice = VoiceStreamingManager()
    @State private var speaker = SpeechSpeaker()
    @State private var isRecording = false
    @State private var pulse = false
    @State private var lastError: String?
    @State private var startTime: Date?
    @State private var timerTick = Date()
    @State private var statusResponse: String = ""
    @State private var typedTask: String = ""
    @FocusState private var typedFocused: Bool
    @State private var showingHistory = false

    private let accentRed = Color(red: 1.0, green: 0.20, blue: 0.27)

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(spacing: 18) {
                    statusCard
                    responseCard
                    micButton
                    textTaskField
                    // Extra bottom padding so the floating button doesn't
                    // overlap the hint text when the user scrolls to the end.
                    hint
                        .padding(.bottom, 70)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)

            historyFloatingButton
                .padding(.trailing, 18)
                .padding(.bottom, 18)
        }
        .onAppear {
            wireCallbacks()
            if let prior = client.lastTaskResponse { statusResponse = prior }
        }
        .task(id: "voice-timer") {
            while !Task.isCancelled {
                timerTick = Date()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        .sheet(isPresented: $showingHistory) {
            TaskHistorySheet(client: client)
        }
    }

    // MARK: - Floating history button

    private var historyFloatingButton: some View {
        Button {
            Haptic.tap()
            showingHistory = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                    .shadow(color: Color.accentColor.opacity(0.45), radius: 12, x: 0, y: 6)

                // Unread-style badge with the history count.
                if !client.taskHistory.isEmpty {
                    Text("\(min(client.taskHistory.count, 99))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(Color.red)
                        )
                        .offset(x: 6, y: -6)
                }
            }
        }
        .buttonStyle(PressableGlassStyle())
        .accessibilityLabel("Task history (\(client.taskHistory.count))")
    }

    // MARK: - Status card

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Circle()
                    .fill(isRecording ? accentRed : Color.secondary.opacity(0.4))
                    .frame(width: 10, height: 10)
                    .scaleEffect(isRecording && pulse ? 1.35 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true),
                               value: pulse)
                Text(isRecording ? "Listening…" : "Ready")
                    .font(.headline)
                Spacer()
                if isRecording, let start = startTime {
                    Text(formatElapsed(timerTick.timeIntervalSince(start)))
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if let lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text(isRecording
                     ? "Speak now — release to run on \(client.serverName)."
                     : "Hold the mic and dictate the task, or type it below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.6)
        )
    }

    // MARK: - CLI response (scrollable; full untruncated text)

    @ViewBuilder
    private var responseCard: some View {
        if !statusResponse.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle")
                        .foregroundStyle(.purple)
                    Text("openclaw")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        Haptic.soft()
                        UIPasteboard.general.string = statusResponse
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Copy")
                    Button {
                        Haptic.soft()
                        speaker.stop()
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            statusResponse = ""
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Dismiss")
                }

                // Full response — no line limit. Wrapped in an inner
                // ScrollView so a very long agent reply doesn't push the
                // mic + text input off-screen.
                ScrollView {
                    Text(statusResponse)
                        .font(.callout)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)

                Button {
                    Haptic.tap()
                    if speaker.isSpeaking {
                        speaker.stop()
                    } else {
                        speaker.speak(statusResponse)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: speaker.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                            .symbolEffect(.pulse, isActive: speaker.isSpeaking)
                        Text(speaker.isSpeaking ? "Stop" : "Hear it")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: [Color.purple, Color.purple.opacity(0.75)],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                    )
                }
                .buttonStyle(PressableGlassStyle())
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.purple.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.purple.opacity(0.35), lineWidth: 0.8)
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Mic button

    private var micButton: some View {
        ZStack {
            if isRecording {
                Circle()
                    .fill(accentRed.opacity(0.25))
                    .frame(width: 220, height: 220)
                    .scaleEffect(pulse ? 1.10 : 0.92)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                               value: pulse)
            }
            Circle()
                .fill(
                    LinearGradient(
                        colors: isRecording
                        ? [Color(red: 1.0, green: 0.32, blue: 0.36),
                           Color(red: 0.82, green: 0.07, blue: 0.20)]
                        : [Color.accentColor.opacity(0.95),
                           Color.accentColor.opacity(0.65)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 160, height: 160)
                .overlay(
                    Image(systemName: isRecording ? "waveform" : "mic.fill")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: isRecording)
                )
                .shadow(color: (isRecording ? accentRed : Color.accentColor).opacity(0.45),
                        radius: 18, x: 0, y: 8)
                .scaleEffect(isRecording ? 0.97 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.7),
                           value: isRecording)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isRecording else { return }
                    Task { await startRecording() }
                }
                .onEnded { _ in
                    stopRecording()
                }
        )
        .accessibilityLabel(isRecording ? "Recording — release to send" : "Hold to record voice command")
    }

    // MARK: - Typed task input

    private var textTaskField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Or type the task")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Describe the task…", text: $typedTask, axis: .vertical)
                    .focused($typedFocused)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.10), lineWidth: 0.6)
                    )
                    .submitLabel(.send)
                    .onSubmit { sendTypedTask() }

                Button {
                    sendTypedTask()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(
                            canSendTyped ? Color.accentColor : Color.secondary.opacity(0.45)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSendTyped)
                .accessibilityLabel("Send typed task")
            }
        }
    }

    private var canSendTyped: Bool {
        !typedTask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendTypedTask() {
        let trimmed = typedTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Haptic.tap()
        speaker.stop()
        client.sendTextTask(trimmed)
        typedTask = ""
        typedFocused = false
    }

    // MARK: - Hint

    private var hint: some View {
        VStack(spacing: 6) {
            Label("On-device transcription", systemImage: "lock.shield.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("Speech is transcribed on the Mac's Neural Engine and handed to openclaw. The full reply is shown — and optionally read aloud — here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Glue

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
        client.onTaskResponse = { response in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                statusResponse = response
            }
            Haptic.tap()
        }
    }

    private func startRecording() async {
        Haptic.tap()
        lastError = nil
        speaker.stop()
        client.send(.voiceStart())
        do {
            try await voice.start()
            isRecording = true
            pulse = true
            startTime = Date()
        } catch {
            lastError = error.localizedDescription
            client.send(.voiceStop())
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        Haptic.soft()
        voice.stop()
        client.send(.voiceStop())
        isRecording = false
        pulse = false
        startTime = nil
    }

    private func formatElapsed(_ t: TimeInterval) -> String {
        let total = Int(t)
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - Speech synthesiser

@MainActor
@Observable
private final class SpeechSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private(set) var isSpeaking = false

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        stop()
        configurePlaybackSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
                          ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        synth.speak(utterance)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    private func configurePlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

#endif
