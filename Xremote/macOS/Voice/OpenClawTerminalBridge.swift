//
//  OpenClawTerminalBridge.swift
//  Production bridge to the locally-installed OpenClaw agent CLI.
//
//  Each finalized voice utterance is dispatched on a background thread via
//  `Process()` using the exact verified flag structure:
//
//      openclaw agent --session-key main --message "<transcribed text>"
//
//  The Mac main thread (which drives the menu-bar popover and the floating
//  laser overlay) is never blocked — completion is reported asynchronously
//  through `onCompletion` / `onLaunchFailure`. Each invocation returns a
//  UUID so the `TaskTracker` can correlate the request with the eventual
//  status.
//

#if os(macOS)

import Foundation
import Observation

@MainActor
@Observable
final class OpenClawTerminalBridge {
    /// Probed at init in this order — Apple Silicon Homebrew lives at
    /// /opt/homebrew, Intel/manual installs at /usr/local. If the user
    /// installed somewhere exotic they can override with `executablePath`.
    static let candidateExecutablePaths = [
        "/opt/homebrew/bin/openclaw",
        "/usr/local/bin/openclaw"
    ]

    /// Resolved binary location. Settable so dashboards can correct an
    /// auto-detection that points at the wrong arch.
    var executablePath: String
    /// Workspace context the agent operates against.
    var workspaceURL: URL = URL(fileURLWithPath: NSHomeDirectory())
    /// Logical session, passed as `--session-key`.
    var sessionKey: String = "main"

    /// (taskId, transcript, stdout+stderr, exitStatus)
    var onCompletion: ((UUID, String, String, Int32) -> Void)?
    /// (taskId, transcript, error)
    var onLaunchFailure: ((UUID, String, Error) -> Void)?

    private(set) var lastTranscript: String = ""
    private(set) var lastOutput: String = ""
    private(set) var isRunning: Bool = false

    /// Live processes keyed by task id so cancellation can find them.
    private var liveProcesses: [UUID: Process] = [:]

    init() {
        self.executablePath = Self.candidateExecutablePaths.first(where: {
            FileManager.default.isExecutableFile(atPath: $0)
        }) ?? Self.candidateExecutablePaths.last!
    }

    /// Spawn `openclaw agent --session-key <key> --message <transcript>`.
    /// Returns the task id immediately. Reports completion / failure via
    /// the callbacks, on the main actor.
    @discardableResult
    func run(transcript: String) -> UUID? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            NSLog("[Xremote] run() skipped — empty transcript")
            return nil
        }
        let taskId = UUID()

        lastTranscript = trimmed
        isRunning = true

        NSLog("[Xremote] launching openclaw at %@ for transcript: %@",
              executablePath, trimmed)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: executablePath)
        task.currentDirectoryURL = workspaceURL

        // Exact CLI flags as verified by OpenClaw's argument parser. The
        // `--log-level error` flag is critical — without it OpenClaw prints
        // info-level plugin-discovery warnings that pollute the captured
        // response and end up in the iPhone status card.
        task.arguments = [
            "agent",
            "--session-key", sessionKey,
            "--log-level", "error",
            "--message", trimmed
        ]

        // Crucial: `openclaw` is a Node-shebang script (`#!/usr/bin/env node`)
        // so its own startup needs `node` on PATH. GUI-launched apps inherit
        // a near-empty PATH (just `/usr/bin:/bin`), which is why running
        // openclaw fails with `env: node: No such file or directory`. We
        // explicitly extend PATH with the standard Homebrew + Unix bin
        // locations, plus any Node version managers we can detect, so the
        // shebang line can resolve.
        task.environment = enrichedEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        task.standardOutput = stdoutPipe
        task.standardError = stderrPipe

        // Drain pipes asynchronously so a verbose agent response never
        // blocks the child process on a full kernel buffer.
        var buffer = ""
        let drain: (FileHandle) -> Void = { handle in
            handle.readabilityHandler = { [weak self] fh in
                let data = fh.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else {
                    fh.readabilityHandler = nil
                    return
                }
                Task { @MainActor in
                    buffer += chunk
                    self?.lastOutput = buffer
                }
            }
        }
        drain(stdoutPipe.fileHandleForReading)
        drain(stderrPipe.fileHandleForReading)

        task.terminationHandler = { [weak self] proc in
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            let status = proc.terminationStatus
            Task { @MainActor in
                guard let self else { return }
                self.liveProcesses.removeValue(forKey: taskId)
                self.isRunning = !self.liveProcesses.isEmpty
                self.onCompletion?(taskId, trimmed, self.lastOutput, status)
            }
        }

        do {
            try task.run()
            liveProcesses[taskId] = task
            NSLog("[Xremote] openclaw spawned pid=%d for task=%@",
                  task.processIdentifier, taskId.uuidString)
        } catch {
            NSLog("[Xremote] openclaw FAILED to launch: %@",
                  error.localizedDescription)
            isRunning = !liveProcesses.isEmpty
            onLaunchFailure?(taskId, trimmed, error)
            return nil
        }

        return taskId
    }

    @discardableResult
    func cancel(taskId: UUID) -> Bool {
        guard let process = liveProcesses[taskId] else { return false }
        process.terminate()
        return true
    }

    var liveTaskIds: [UUID] { Array(liveProcesses.keys) }

    /// Used by the dashboard to render the exact command shape so the user
    /// can sanity-check against `openclaw --help`.
    func previewCommand(forSample sample: String = "hello") -> String {
        "\(executablePath) agent --session-key \(sessionKey) --log-level error --message \"\(sample)\""
    }

    // MARK: - Environment

    /// The base PATH directories every spawned process should see.
    private static let extraPathRoots = [
        "/opt/homebrew/bin",       // Apple Silicon Homebrew
        "/opt/homebrew/sbin",
        "/usr/local/bin",          // Intel Homebrew / manual installs
        "/usr/local/sbin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin"
    ]

    /// Build the environment dictionary passed to the child Process.
    /// Starts from this app's environment so HOME / USER / locale stay
    /// correct, then prepends every standard binary directory plus any
    /// detectable Node version-manager binaries so `node` resolves.
    private func enrichedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        var pathDirs: [String] = []
        pathDirs.append(contentsOf: Self.extraPathRoots)
        pathDirs.append(contentsOf: detectedNodeManagerBinDirs())
        // Append whatever was already on PATH, skipping duplicates so the
        // priority is "well-known dirs first".
        let existing = (env["PATH"] ?? "").split(separator: ":").map(String.init)
        for dir in existing where !pathDirs.contains(dir) {
            pathDirs.append(dir)
        }
        env["PATH"] = pathDirs.joined(separator: ":")
        return env
    }

    /// Look in the conventional spots used by nvm, fnm, n, asdf for a
    /// `node` binary so users who manage Node through one of those tools
    /// don't have to also install Node via brew.
    private func detectedNodeManagerBinDirs() -> [String] {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var dirs: [String] = []

        // fnm
        let fnmDefault = "\(home)/.fnm/aliases/default/bin"
        if fm.isReadableFile(atPath: fnmDefault + "/node") { dirs.append(fnmDefault) }

        // asdf
        let asdfShims = "\(home)/.asdf/shims"
        if fm.isReadableFile(atPath: asdfShims + "/node") { dirs.append(asdfShims) }

        // n (uses /usr/local/n by default; the binary is just /usr/local/bin/node)

        // nvm — pick the highest-numbered installed version we can find.
        let nvmVersions = "\(home)/.nvm/versions/node"
        if let entries = try? fm.contentsOfDirectory(atPath: nvmVersions) {
            // Naïve numeric sort: "v20.10.0" → sort by string desc works
            // well enough since semver versions sort lexically with v-prefix.
            if let latest = entries.sorted(by: >).first {
                let bin = "\(nvmVersions)/\(latest)/bin"
                if fm.isReadableFile(atPath: bin + "/node") { dirs.append(bin) }
            }
        }

        // Volta
        let volta = "\(home)/.volta/bin"
        if fm.isReadableFile(atPath: volta + "/node") { dirs.append(volta) }

        return dirs
    }
}

#endif
