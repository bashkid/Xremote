//
//  XremoteClient.swift
//  Manages the NWConnection to a discovered Mac server, performs handshake,
//  and exposes send helpers used by the remote UI.
//

#if os(iOS)

import Foundation
import Network
import Observation
import UIKit

enum XRConnectionState: Equatable {
    case idle
    case connecting
    case awaitingPin
    case connected
    case failed(String)
}

/// One entry in the iPhone-side voice / text task history. Stored locally
/// in UserDefaults so it survives app restarts.
struct TaskHistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let transcript: String
    let response: String
    let timestamp: Date
}

@MainActor
@Observable
final class XremoteClient {
    private(set) var state: XRConnectionState = .idle
    private(set) var serverName: String = ""
    /// File-manager state. Set by RootView at startup so this class can
    /// forward inbound `.fileTransfer` packets without owning the
    /// transfer client itself.
    var fileClient: FileTransferClient?
    /// Latest status string returned by the Mac after running a voice task.
    private(set) var lastTaskResponse: String?
    /// Persistent history of every prompt + reply seen since install.
    /// Newest entries first. Capped at `historyCap`.
    private(set) var taskHistory: [TaskHistoryItem] = []
    /// Fired once per inbound `.taskResponse` — VoiceView uses it to drive
    /// the AVSpeechSynthesizer alongside updating the on-screen text.
    var onTaskResponse: ((String) -> Void)?
    private var connection: NWConnection?
    private let historyKey = "XRTaskHistory"
    private let historyCap = 100

    private let tokenStorageKey = "XremoteDeviceToken"
    private let tokensByServerKey = "XremoteTokensByServer"

    init() {
        loadHistory()
    }
    private let lastConnectedKey = "XRLastConnectedServer"

    /// Name of the most recently successfully-connected server. Used by
    /// RootView to auto-reconnect when the iPhone wakes up.
    var lastConnectedServer: String? {
        let value = UserDefaults.standard.string(forKey: lastConnectedKey) ?? ""
        return value.isEmpty ? nil : value
    }

    private var deviceName: String {
        UIDevice.current.name
    }

    func connect(to server: DiscoveredServer) {
        disconnect()
        serverName = server.name
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let connection = NWConnection(to: server.endpoint, using: params)
        self.connection = connection
        state = .connecting
        connection.stateUpdateHandler = { [weak self] s in
            Task { @MainActor in
                guard let self else { return }
                switch s {
                case .ready:
                    Task { await self.performHandshake(serverName: server.name) }
                case .failed(let error):
                    self.state = .failed(error.localizedDescription)
                    self.connection = nil
                case .cancelled:
                    if case .connected = self.state { self.state = .idle }
                default: break
                }
            }
        }
        connection.start(queue: .main)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        state = .idle
    }

    /// Send a typed task prompt (skips voice transcription on the Mac).
    func sendTextTask(_ prompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        send(.textTask(trimmed))
    }

    /// Called when the user explicitly taps "Disconnect" — clears the saved
    /// last-connected server so the auto-reconnect logic doesn't immediately
    /// pull us back in.
    func forgetAndDisconnect() {
        UserDefaults.standard.removeObject(forKey: lastConnectedKey)
        disconnect()
    }

    // MARK: - Pairing

    func submitPin(_ pin: String) {
        guard let connection else { return }
        Task {
            do {
                try await xrSend(.pinResponse(pin), on: connection)
                let reply = try await xrReceive(on: connection)
                await MainActor.run { self.handleHandshake(reply: reply) }
            } catch {
                await MainActor.run { self.state = .failed(error.localizedDescription) }
            }
        }
    }

    private func performHandshake(serverName: String) async {
        guard let connection else { return }
        do {
            let token = storedToken(for: serverName)
            try await xrSend(.hello(deviceName: deviceName, token: token), on: connection)
            let reply = try await xrReceive(on: connection)
            await MainActor.run { self.handleHandshake(reply: reply) }
        } catch {
            await MainActor.run { self.state = .failed(error.localizedDescription) }
        }
    }

    private func handleHandshake(reply: XRMessage) {
        switch reply.type {
        case .helloAck:
            switch reply.ack {
            case .accepted:
                // Server follows up with a `paired` message containing the
                // (possibly refreshed) token. Read that, then enter the main
                // loop. Sequencing avoids two concurrent receivers on the
                // same NWConnection.
                state = .connected
                rememberConnection()
                Task { await self.runConnected(expectPairedFollowup: true) }
            case .needsPin:
                state = .awaitingPin
            case .rejected:
                state = .failed("Incorrect PIN")
                disconnect()
            case .none:
                state = .failed("Malformed server response")
                disconnect()
            }
        case .paired:
            if let token = reply.newToken {
                saveToken(token, for: serverName)
            }
            state = .connected
            rememberConnection()
            Task { await self.runConnected(expectPairedFollowup: false) }
        default:
            state = .failed("Unexpected message")
            disconnect()
        }
    }

    private func runConnected(expectPairedFollowup: Bool) async {
        guard let connection else { return }
        if expectPairedFollowup {
            do {
                let next = try await xrReceive(on: connection)
                if next.type == .paired, let token = next.newToken {
                    await MainActor.run { self.saveToken(token, for: self.serverName) }
                }
            } catch {
                await MainActor.run { self.disconnect() }
                return
            }
        }
        await readLoop()
    }

    private func rememberConnection() {
        UserDefaults.standard.set(serverName, forKey: lastConnectedKey)
    }

    private func readLoop() async {
        guard let connection else { return }
        while true {
            do {
                let msg = try await xrReceive(on: connection)
                await MainActor.run { self.handleInbound(msg) }
            } catch {
                await MainActor.run {
                    if case .connected = self.state { self.state = .idle }
                    self.disconnect()
                }
                return
            }
        }
    }

    /// Dispatched on the main actor for every message the server pushes to
    /// us after the handshake. Currently surfaces `.taskResponse` into the
    /// last-response state and appends a history entry.
    private func handleInbound(_ msg: XRMessage) {
        switch msg.type {
        case .taskResponse:
            guard let text = msg.text else { return }
            lastTaskResponse = text
            onTaskResponse?(text)
            // Persist a history item if the Mac told us what was asked.
            let transcript = (msg.transcript ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !transcript.isEmpty {
                appendHistory(transcript: transcript, response: text)
            }
        case .fileTransfer:
            if let packet = msg.fileTransfer {
                fileClient?.handleInbound(packet)
            }
        default:
            break
        }
    }

    // MARK: - Task history

    /// Wipe the on-disk + in-memory history.
    func clearTaskHistory() {
        taskHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: historyKey)
    }

    /// Remove a single history entry.
    func deleteTaskHistoryItem(_ id: UUID) {
        taskHistory.removeAll { $0.id == id }
        saveHistory()
    }

    private func appendHistory(transcript: String, response: String) {
        let item = TaskHistoryItem(
            id: UUID(),
            transcript: transcript,
            response: response,
            timestamp: Date()
        )
        taskHistory.insert(item, at: 0)
        if taskHistory.count > historyCap {
            taskHistory.removeLast(taskHistory.count - historyCap)
        }
        saveHistory()
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let items = try? JSONDecoder().decode([TaskHistoryItem].self, from: data)
        else { return }
        taskHistory = items
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(taskHistory) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }

    // MARK: - Token persistence (per server name)

    private func storedToken(for server: String) -> String? {
        let all = UserDefaults.standard.dictionary(forKey: tokensByServerKey) as? [String: String] ?? [:]
        return all[server]
    }

    private func saveToken(_ token: String, for server: String) {
        var all = UserDefaults.standard.dictionary(forKey: tokensByServerKey) as? [String: String] ?? [:]
        all[server] = token
        UserDefaults.standard.set(all, forKey: tokensByServerKey)
    }

    // MARK: - Send helpers

    func send(_ message: XRMessage) {
        guard let connection, case .connected = state else { return }
        Task { try? await xrSend(message, on: connection) }
    }
}

#endif
