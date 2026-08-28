//
//  TaskTracker.swift
//  Tracks every voice-driven Claude Code job spawned by Xremote on this
//  Mac. The menu-bar popover reads from it to show a live dashboard:
//  how many tasks are running right now, what they were asked, how long
//  they've been running, and what Claude said when they finished.
//

#if os(macOS)

import Foundation
import Observation

@MainActor
@Observable
final class TaskTracker {

    /// One Claude run, from "voice command received" through "process exited".
    struct ManagedTask: Identifiable {
        let id: UUID
        var transcript: String
        let startedAt: Date
        var finishedAt: Date?
        var status: Status
        var output: String?           // What Claude printed (trimmed)
        var exitStatus: Int32?

        enum Status: String, CaseIterable {
            case running
            case completed
            case failed
            case cancelled
        }

        /// Live duration (or final duration after `finishedAt` is set).
        func duration(at now: Date) -> TimeInterval {
            (finishedAt ?? now).timeIntervalSince(startedAt)
        }
    }

    /// Newest-first so the dashboard shows the most relevant tasks at the top.
    private(set) var tasks: [ManagedTask] = []

    /// Re-computed cheaply from `tasks`. Bound to the menu-bar badge.
    var runningCount: Int {
        tasks.lazy.filter { $0.status == .running }.count
    }

    var hasHistory: Bool { !tasks.isEmpty }

    // MARK: - Lifecycle

    /// Add a brand-new task. The bridge calls this immediately before it
    /// launches `claude -p …`.
    func register(taskId: UUID, transcript: String) {
        let task = ManagedTask(
            id: taskId,
            transcript: transcript,
            startedAt: Date(),
            status: .running
        )
        tasks.insert(task, at: 0)
        capHistory()
    }

    /// Mark a task done. Driven by `ClaudeTerminalBridge.onCompletion`.
    func complete(taskId: UUID, output: String, exitStatus: Int32) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[idx].finishedAt = Date()
        tasks[idx].status = exitStatus == 0 ? .completed : .failed
        tasks[idx].output = output
        tasks[idx].exitStatus = exitStatus
    }

    /// Driven by `ClaudeTerminalBridge.onLaunchFailure` (couldn't even spawn).
    func fail(taskId: UUID, reason: String) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[idx].finishedAt = Date()
        tasks[idx].status = .failed
        tasks[idx].output = reason
    }

    /// Move a running task into the cancelled state. The bridge is
    /// responsible for terminating the actual process.
    func cancel(taskId: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        if tasks[idx].status == .running {
            tasks[idx].finishedAt = Date()
            tasks[idx].status = .cancelled
        }
    }

    /// Drop everything that is no longer running so the user can clear the
    /// view from the popover.
    func clearHistory() {
        tasks.removeAll { $0.status != .running }
    }

    // MARK: - Internal

    /// Keep at most this many tasks in memory — the popover only needs
    /// recent history, no point retaining unbounded entries.
    private let historyCap: Int = 40

    private func capHistory() {
        guard tasks.count > historyCap else { return }
        // Always preserve running tasks; drop the oldest finished ones first.
        let excess = tasks.count - historyCap
        var droppable = tasks.enumerated()
            .filter { $0.element.status != .running }
            .sorted { $0.element.startedAt < $1.element.startedAt }
            .prefix(excess)
            .map { $0.offset }
        droppable.sort(by: >)  // remove from the back so indices stay valid
        for i in droppable { tasks.remove(at: i) }
    }
}

#endif
