//
//  XremoteServer.swift
//  NWListener that advertises via Bonjour, accepts framed JSON connections,
//  enforces PIN pairing, and dispatches messages to the simulators.
//

#if os(macOS)

import AppKit
import Foundation
import Network
import Observation

@MainActor
@Observable
final class XremoteServer {
    private(set) var isRunning = false
    private(set) var port: UInt16 = 0
    private(set) var serverName: String = Host.current().localizedName ?? "Mac"
    private(set) var connectedDevices: [String] = []

    let pairing: PairingManager
    let laserOverlay = LaserOverlayController()
    let transcriber = NativeTranscriberDaemon()
    let openClawBridge = OpenClawTerminalBridge()
    let taskTracker = TaskTracker()
    let fileServer = FileServerBridge()
    private var listener: NWListener?
    private var activeConnections: [ObjectIdentifier: NWConnection] = [:]
    /// Last connection that opened a voice session. The token gets recorded
    /// at voiceStart / textTask time so the response routes back even if
    /// the iPhone reconnects under a different NWConnection.
    private weak var activeVoiceConnection: NWConnection?
    /// Device token of the connection currently negotiating a voice or text
    /// task. Read off during task registration.
    private var activeVoiceToken: String?
    /// Per-task → which device token asked. Used to look up the live
    /// connection at completion, falling back to the offline-queue.
    private var taskTokens: [UUID: String] = [:]
    /// Live NWConnection currently bound to each authenticated device token.
    /// Updated by the handshake when a device connects / reconnects.
    private var connectionForToken: [String: NWConnection] = [:]
    /// Reverse lookup so the connection-cleanup hook can purge the right
    /// entry when a socket dies.
    private var tokenForConnection: [ObjectIdentifier: String] = [:]
    /// Responses produced while the asking device was offline. Drained on
    /// the next successful handshake for that token, newest-last so the
    /// iPhone receives them in order.
    private var pendingByToken: [String: [PendingResponse]] = [:]

    private struct PendingResponse {
        let transcript: String?
        let response: String
        let queuedAt: Date
    }

    init(pairing: PairingManager) {
        self.pairing = pairing

        // Final transcript → register a task + launch OpenClaw.
        transcriber.onFinalPhrase = { [weak self] phrase in
            guard let self else { return }
            guard let taskId = self.openClawBridge.run(transcript: phrase) else { return }
            self.taskTracker.register(taskId: taskId, transcript: phrase)
            if let token = self.activeVoiceToken {
                self.taskTokens[taskId] = token
            }
        }

        // Agent finished → tracker + send (or queue) the reply.
        openClawBridge.onCompletion = { [weak self] taskId, transcript, output, status in
            guard let self else { return }
            self.taskTracker.complete(taskId: taskId, output: output, exitStatus: status)
            let summary = Self.summarize(agentOutput: output, exitStatus: status)
            self.deliverOrQueue(taskId: taskId, transcript: transcript, response: summary)
        }

        // Couldn't even spawn `openclaw` → register the task post-hoc so
        // the failure still appears in the dashboard, then return the
        // reason to the iPhone.
        openClawBridge.onLaunchFailure = { [weak self] taskId, transcript, error in
            guard let self else { return }
            let path = self.openClawBridge.executablePath
            let reason = "Couldn't launch \(path): \(error.localizedDescription)"
            // If we never managed to register (because run() returned nil
            // before that line), do it now so the dashboard shows the row.
            if !self.taskTracker.tasks.contains(where: { $0.id == taskId }) {
                self.taskTracker.register(taskId: taskId, transcript: transcript)
            }
            self.taskTracker.fail(taskId: taskId, reason: reason)
            // Bind the response to whichever device was currently asking,
            // since textTask / voice never got to record the token.
            if self.taskTokens[taskId] == nil, let token = self.activeVoiceToken {
                self.taskTokens[taskId] = token
            }
            self.deliverOrQueue(taskId: taskId, transcript: transcript, response: reason)
        }
    }

    /// Route a finished task's response. If the asking device is still
    /// online, send straight away. Otherwise stash it on `pendingByToken`
    /// so it's delivered the next time that device reconnects.
    private func deliverOrQueue(taskId: UUID, transcript: String?, response: String) {
        guard let token = taskTokens.removeValue(forKey: taskId) else {
            // No token recorded (rare — task wasn't tied to a known device).
            // Try the legacy connection-based fallback if we still have one.
            if let conn = activeVoiceConnection {
                Task { try? await xrSend(.taskResponse(transcript: transcript, response: response), on: conn) }
            }
            return
        }
        if let conn = connectionForToken[token], conn.state == .ready {
            Task {
                try? await xrSend(
                    .taskResponse(transcript: transcript, response: response),
                    on: conn
                )
            }
        } else {
            pendingByToken[token, default: []].append(
                PendingResponse(transcript: transcript, response: response, queuedAt: Date())
            )
        }
    }

    /// Cancel a running task — used by the dashboard.
    func cancelTask(_ taskId: UUID) {
        openClawBridge.cancel(taskId: taskId)
        taskTracker.cancel(taskId: taskId)
        taskTokens.removeValue(forKey: taskId)
    }

    /// Forward the agent's full reply to the iPhone, untruncated. The
    /// iPhone Voice tab wraps the text in a scrollable card so even very
    /// long responses are readable.
    private static func summarize(agentOutput: String, exitStatus: Int32) -> String {
        let raw = agentOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            return exitStatus == 0
            ? "Task completed but the agent returned no output."
            : "Task failed (exit \(exitStatus)) and the agent returned no output."
        }
        return raw
    }

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.includePeerToPeer = true
            let l = try NWListener(using: params)
            l.service = NWListener.Service(name: serverName,
                                           type: XRProtocol.serviceType,
                                           domain: nil)
            l.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        if let p = self.listener?.port { self.port = p.rawValue }
                    case .failed, .cancelled:
                        self.isRunning = false
                    default: break
                    }
                }
            }
            l.newConnectionHandler = { [weak self] conn in
                Task { @MainActor in self?.accept(conn) }
            }
            l.start(queue: .main)
            self.listener = l
        } catch {
            NSLog("XremoteServer failed to start: \(error)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for conn in activeConnections.values { conn.cancel() }
        activeConnections.removeAll()
        connectedDevices.removeAll()
        isRunning = false
    }

    // MARK: - Per-connection handling

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        activeConnections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                if case .cancelled = state {
                    self.activeConnections.removeValue(forKey: id)
                    self.purgeTokenBinding(forConnectionId: id)
                }
                if case .failed = state {
                    self.activeConnections.removeValue(forKey: id)
                    self.purgeTokenBinding(forConnectionId: id)
                }
            }
        }
        connection.start(queue: .main)
        Task { await handle(connection) }
    }

    /// Called when a connection drops so we can stop routing live
    /// responses to a dead socket. The queued backlog stays — it's drained
    /// next time that device's token reconnects.
    private func purgeTokenBinding(forConnectionId id: ObjectIdentifier) {
        guard let token = tokenForConnection.removeValue(forKey: id) else { return }
        if let bound = connectionForToken[token], ObjectIdentifier(bound) == id {
            connectionForToken.removeValue(forKey: token)
        }
    }

    /// Bind a freshly-authenticated connection to its device token + drain
    /// any responses that arrived for that token while it was disconnected.
    private func registerAuthenticatedConnection(_ connection: NWConnection, token: String) {
        let id = ObjectIdentifier(connection)
        tokenForConnection[id] = token
        connectionForToken[token] = connection

        let pending = pendingByToken.removeValue(forKey: token) ?? []
        guard !pending.isEmpty else { return }
        // Send oldest-first so the iPhone's history records the original
        // chronological order even after a reconnect.
        let ordered = pending.sorted { $0.queuedAt < $1.queuedAt }
        Task {
            for p in ordered {
                try? await xrSend(
                    .taskResponse(transcript: p.transcript, response: p.response),
                    on: connection
                )
            }
        }
    }

    private nonisolated func handle(_ connection: NWConnection) async {
        var deviceName: String = "Unknown"
        var authenticated = false

        defer {
            connection.cancel()
            Task { @MainActor in
                if let idx = self.connectedDevices.firstIndex(of: deviceName) {
                    self.connectedDevices.remove(at: idx)
                }
            }
        }

        // Handshake loop
        do {
            // First message must be hello
            let hello = try await xrReceive(on: connection)
            guard hello.type == .hello else { return }
            deviceName = hello.deviceName ?? "Unknown"

            // The token this connection will be bound to once authenticated.
            var sessionToken: String?

            let alreadyPaired = await MainActor.run { self.pairing.isPaired(token: hello.deviceToken) }
            if alreadyPaired {
                try await xrSend(.helloAck(.accepted), on: connection)
                authenticated = true
                let newToken = hello.deviceToken ?? UUID().uuidString
                sessionToken = newToken
                try await xrSend(.paired(token: newToken), on: connection)
            } else {
                try await xrSend(.helloAck(.needsPin), on: connection)
                // Wait for PIN response
                let response = try await xrReceive(on: connection)
                guard response.type == .pinResponse, let pin = response.pin else { return }
                let newToken = UUID().uuidString
                let ok = await MainActor.run { self.pairing.pair(pin: pin, newToken: newToken) }
                if ok {
                    try await xrSend(.paired(token: newToken), on: connection)
                    authenticated = true
                    sessionToken = newToken
                } else {
                    try await xrSend(.helloAck(.rejected), on: connection)
                    return
                }
            }

            if authenticated {
                let token = sessionToken
                await MainActor.run {
                    if !self.connectedDevices.contains(deviceName) {
                        self.connectedDevices.append(deviceName)
                    }
                    if let token {
                        self.registerAuthenticatedConnection(connection, token: token)
                    }
                }
            }

            // Main receive loop
            while true {
                let message = try await xrReceive(on: connection)
                await MainActor.run { self.dispatch(message, connection: connection) }
            }
        } catch {
            // Connection closed or errored — fall through to defer.
        }
    }

    private func dispatch(_ message: XRMessage, connection: NWConnection) {
        switch message.type {
        case .keyTap:
            if let key = message.key {
                KeyboardSimulator.tap(key, modifiers: message.modifiers ?? [])
            }
        case .keyDown:
            if let key = message.key {
                KeyboardSimulator.keyDown(key, modifiers: message.modifiers ?? [])
            }
        case .keyUp:
            if let key = message.key {
                KeyboardSimulator.keyUp(key, modifiers: message.modifiers ?? [])
            }
        case .text:
            if let t = message.text { KeyboardSimulator.type(t) }
        case .mouseMove:
            MouseSimulator.move(dx: message.dx ?? 0, dy: message.dy ?? 0)
        case .mouseClick:
            MouseSimulator.click(message.button ?? .left, count: message.clickCount ?? 1)
        case .mouseDown:
            MouseSimulator.down(message.button ?? .left)
        case .mouseUp:
            MouseSimulator.up(message.button ?? .left)
        case .scroll:
            MouseSimulator.scroll(dx: message.dx ?? 0, dy: message.dy ?? 0)
        case .mediaKey:
            if let m = message.mediaKey { MediaKeys.post(m) }
        case .laserShow:
            laserOverlay.show(style: message.pointerStyle)
        case .laserHide:
            laserOverlay.hide()
        case .laserMove:
            laserOverlay.move(dx: CGFloat(message.dx ?? 0),
                              dy: CGFloat(message.dy ?? 0))
        case .laserClick:
            laserOverlay.click()
        case .laserStyle:
            if let style = message.pointerStyle { laserOverlay.setStyle(style) }
        case .gyroDelta:
            laserOverlay.applyGyroDelta(
                dx: message.dx ?? 0,
                dy: message.dy ?? 0
            )
        case .fileTransfer:
            if let packet = message.fileTransfer {
                fileServer.handle(packet: packet, on: connection)
            }
        case .voiceStart:
            activeVoiceConnection = connection
            activeVoiceToken = tokenForConnection[ObjectIdentifier(connection)]
            Task { await transcriber.startSession() }
        case .voiceChunk:
            if let data = message.audioData { transcriber.ingest(pcmData: data) }
        case .voiceStop:
            transcriber.endSession()
        case .textTask:
            // Same path as a final voice transcript: register + run.
            guard let text = message.text else {
                NSLog("[Xremote] textTask received with empty text — ignoring")
                break
            }
            NSLog("[Xremote] textTask received: %@", text)
            activeVoiceConnection = connection
            activeVoiceToken = tokenForConnection[ObjectIdentifier(connection)]
            guard let taskId = openClawBridge.run(transcript: text) else {
                NSLog("[Xremote] openClawBridge.run returned nil for textTask")
                break
            }
            taskTracker.register(taskId: taskId, transcript: text)
            if let token = activeVoiceToken {
                taskTokens[taskId] = token
            }
        case .ping:
            Task { try? await xrSend(.pong, on: connection) }
        default:
            break
        }
    }
}

#endif
