//
//  NativeTranscriberDaemon.swift
//  On-device speech transcriber for Xremote's voice → Claude pipeline.
//
//  Feeds 16 kHz mono Int16 PCM chunks (sent from the iPhone) into
//  `SFSpeechAudioBufferRecognitionRequest` with `requiresOnDeviceRecognition`
//  forced on, so transcription runs 100 % locally on Apple's Neural
//  Engine — no network round-trips, no API costs, no leaked transcript.
//
//  Final utterances are forwarded to `onFinalPhrase`, which the calling
//  layer hands off to `ClaudeTerminalBridge`.
//

#if os(macOS)

import AVFoundation
import Speech
import Observation

@MainActor
@Observable
final class NativeTranscriberDaemon {
    /// Fired once per finalized utterance (`result.isFinal == true`).
    var onFinalPhrase: ((String) -> Void)?
    /// Fired on partial results so the UI can show live captions.
    var onPartialPhrase: ((String) -> Void)?
    /// Fired on any setup / runtime error.
    var onError: ((Error) -> Void)?

    private(set) var isRunning = false
    private(set) var lastError: String?

    enum TranscriberError: LocalizedError {
        case authorizationDenied(SFSpeechRecognizerAuthorizationStatus)
        case recognizerUnavailable
        case onDeviceUnsupported
        case bufferFormatInvalid

        var errorDescription: String? {
            switch self {
            case .authorizationDenied(let status):
                "Speech recognition not authorized (status: \(status.rawValue))."
            case .recognizerUnavailable:
                "SFSpeechRecognizer is unavailable for the current locale."
            case .onDeviceUnsupported:
                "On-device speech recognition is not supported on this Mac."
            case .bufferFormatInvalid:
                "Couldn't build an AVAudioPCMBuffer from incoming bytes."
            }
        }
    }

    // Match the iOS-side wire format exactly: 16 kHz mono Int16 interleaved.
    private let pcmFormat: AVAudioFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16_000,
        channels: 1,
        interleaved: true
    )!

    private let recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    // MARK: - Session lifecycle

    func startSession() async {
        guard !isRunning else { return }

        do {
            try await authorize()
            guard let recognizer, recognizer.isAvailable else {
                throw TranscriberError.recognizerUnavailable
            }
            guard recognizer.supportsOnDeviceRecognition else {
                throw TranscriberError.onDeviceUnsupported
            }

            let req = SFSpeechAudioBufferRecognitionRequest()
            // Pin transcription to local hardware — never hit Apple's servers.
            req.requiresOnDeviceRecognition = true
            req.shouldReportPartialResults = true
            req.taskHint = .dictation
            self.request = req

            self.task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor in
                    self?.handle(result: result, error: error)
                }
            }

            isRunning = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            onError?(error)
        }
    }

    func ingest(pcmData: Data) {
        guard isRunning, let request else { return }
        guard let buffer = makeBuffer(from: pcmData) else {
            onError?(TranscriberError.bufferFormatInvalid)
            return
        }
        request.append(buffer)
    }

    func endSession() {
        request?.endAudio()
        // Leave the task open just long enough to emit any final phrase.
        // The result-handler clears state once isFinal arrives or on error.
        isRunning = false
    }

    func cancel() {
        task?.cancel()
        task = nil
        request = nil
        isRunning = false
    }

    // MARK: - Plumbing

    private func authorize() async throws {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current == .authorized { return }

        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        if status != .authorized {
            throw TranscriberError.authorizationDenied(status)
        }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        if let error {
            lastError = error.localizedDescription
            onError?(error)
            task = nil
            request = nil
            return
        }
        guard let result else { return }
        let text = result.bestTranscription.formattedString
        if result.isFinal {
            onFinalPhrase?(text)
            task = nil
            request = nil
        } else {
            onPartialPhrase?(text)
        }
    }

    /// Wraps incoming raw Int16 PCM bytes in an AVAudioPCMBuffer for the
    /// recognition request.
    private func makeBuffer(from data: Data) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(data.count / MemoryLayout<Int16>.size)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, frameCapacity: frameCount),
              let channelData = buffer.int16ChannelData?[0]
        else { return nil }
        buffer.frameLength = frameCount
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            memcpy(channelData, base, data.count)
        }
        return buffer
    }
}

#endif
