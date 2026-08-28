//
//  VoiceStreamingManager.swift
//  Lightweight device-audio capture engine for Xremote's voice-driven
//  Claude Code pipeline.
//
//  • Records from the phone's hardware microphone via AVAudioEngine.
//  • Downsamples to 16 kHz mono linear PCM (Int16) — the compact format
//    SFSpeechRecognizer accepts cleanly on the Mac side.
//  • Emits each downsampled chunk through `onChunkRecorded` so callers
//    can forward the bytes onto Xremote's outbound data channel.
//

#if os(iOS)

import AVFoundation
import Observation

@MainActor
@Observable
final class VoiceStreamingManager {
    /// Emitted on each downsampled audio chunk (~100 ms of 16 kHz Int16 PCM).
    var onChunkRecorded: ((Data) -> Void)?
    /// Emitted whenever recording fails to start / continue.
    var onError: ((Error) -> Void)?

    private(set) var isRecording = false

    // Target wire format: 16 kHz mono Int16 interleaved linear PCM.
    private let targetSampleRate: Double = 16_000
    private let targetFormat: AVAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )!

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let bufferSize: AVAudioFrameCount = 4096

    enum VoiceError: LocalizedError {
        case permissionDenied
        case converterUnavailable
        case audioSessionFailed(Error)

        var errorDescription: String? {
            switch self {
            case .permissionDenied:        "Microphone permission was denied."
            case .converterUnavailable:    "Couldn't build the 16 kHz audio converter."
            case .audioSessionFailed(let e): "Audio session failed: \(e.localizedDescription)"
            }
        }
    }

    // MARK: - Lifecycle

    func start() async throws {
        guard !isRecording else { return }
        try await requestMicrophonePermission()
        try configureAudioSession()
        try beginCapture()
        isRecording = true
    }

    func stop() {
        guard isRecording else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        converter = nil
        isRecording = false
    }

    // MARK: - Setup

    private func requestMicrophonePermission() async throws {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return
        case .denied:
            throw VoiceError.permissionDenied
        case .undetermined:
            let ok = await AVAudioApplication.requestRecordPermission()
            if !ok { throw VoiceError.permissionDenied }
        @unknown default:
            throw VoiceError.permissionDenied
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setPreferredSampleRate(targetSampleRate)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw VoiceError.audioSessionFailed(error)
        }
    }

    private func beginCapture() throws {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw VoiceError.converterUnavailable
        }
        self.converter = converter

        inputNode.installTap(
            onBus: 0,
            bufferSize: bufferSize,
            format: inputFormat
        ) { [weak self] buffer, _ in
            self?.process(inputBuffer: buffer, with: converter)
        }

        engine.prepare()
        try engine.start()
    }

    // MARK: - Per-buffer processing

    private nonisolated func process(inputBuffer: AVAudioPCMBuffer, with converter: AVAudioConverter) {
        let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio + 1)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                                  frameCapacity: outputCapacity) else { return }

        var providedInput = false
        let status = converter.convert(to: outputBuffer, error: nil) { _, outStatus in
            if providedInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            providedInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        guard status != .error, outputBuffer.frameLength > 0 else { return }

        let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
        guard let int16 = outputBuffer.int16ChannelData?[0] else { return }
        let data = Data(bytes: int16, count: byteCount)

        Task { @MainActor in
            self.onChunkRecorded?(data)
        }
    }
}

#endif
