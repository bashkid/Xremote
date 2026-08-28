//
//  TaskDashboardWindow.swift
//  A standalone NSWindow that hosts a master/detail SwiftUI view of every
//  voice-driven OpenClaw task — transcript on the left, full agent reply
//  on the right. Lives outside the menu-bar popover so the user can keep
//  it open while continuing to work with the iPhone.
//

#if os(macOS)

import AppKit
import SwiftUI

@MainActor
final class TaskDashboardWindowController {
    private weak var server: XremoteServer?
    private var window: NSWindow?

    init(server: XremoteServer) {
        self.server = server
    }

    /// Show the window (creating it on demand) and focus it. If the user
    /// taps a task row before opening the window we can also preselect it.
    func show(selecting taskId: UUID? = nil) {
        guard let server else { return }
        if window == nil {
            let host = NSHostingController(
                rootView: TaskDashboardView(server: server, initiallySelected: taskId)
            )
            let w = NSWindow(contentViewController: host)
            w.title = "Xremote — Tasks"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = false
            w.setContentSize(NSSize(width: 760, height: 480))
            w.center()
            w.isReleasedWhenClosed = false
            window = w
        } else if let taskId {
            // Window already exists — push the new selection in.
            if let host = window?.contentViewController as? NSHostingController<TaskDashboardView> {
                host.rootView = TaskDashboardView(server: server, initiallySelected: taskId)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - SwiftUI view

private struct TaskDashboardView: View {
    @Bindable var server: XremoteServer
    let initiallySelected: UUID?
    @State private var selectedId: UUID?
    @State private var clock = Date()

    init(server: XremoteServer, initiallySelected: UUID?) {
        self.server = server
        self.initiallySelected = initiallySelected
        self._selectedId = State(initialValue: initiallySelected)
    }

    var body: some View {
        HStack(spacing: 0) {
            taskList
                .frame(width: 280)
            Divider()
            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: "dashboard-clock") {
            while !Task.isCancelled {
                clock = Date()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        .onAppear {
            // If nothing's preselected, jump to the freshest task.
            if selectedId == nil { selectedId = server.taskTracker.tasks.first?.id }
        }
    }

    // MARK: Master

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Voice tasks")
                    .font(.headline)
                Spacer()
                Text("\(server.taskTracker.tasks.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15))
                    .clipShape(Capsule())
            }
            .padding(12)

            Divider()

            if server.taskTracker.tasks.isEmpty {
                Spacer()
                Text("No tasks yet.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(selection: $selectedId) {
                    ForEach(server.taskTracker.tasks) { task in
                        TaskRow(task: task, clock: clock)
                            .tag(task.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    // MARK: Detail

    private var detailPane: some View {
        Group {
            if let id = selectedId,
               let task = server.taskTracker.tasks.first(where: { $0.id == id }) {
                TaskDetail(task: task, clock: clock) {
                    server.cancelTask(task.id)
                }
            } else {
                VStack {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("Select a task to view its full response.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Master row

private struct TaskRow: View {
    let task: TaskTracker.ManagedTask
    let clock: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                statusDot
                Text(task.transcript)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
            }
            HStack(spacing: 6) {
                Text(statusLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor)
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(formatDuration(task.duration(at: clock)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(task.startedAt, format: .dateTime.hour().minute().second())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusDot: some View {
        Circle().fill(statusColor).frame(width: 8, height: 8)
    }
    private var statusColor: Color {
        switch task.status {
        case .running:    .purple
        case .completed:  .green
        case .failed:     .red
        case .cancelled:  .gray
        }
    }
    private var statusLabel: String {
        switch task.status {
        case .running:    "Running"
        case .completed:  "Completed"
        case .failed:     "Failed"
        case .cancelled:  "Cancelled"
        }
    }
}

// MARK: - Detail panel

private struct TaskDetail: View {
    let task: TaskTracker.ManagedTask
    let clock: Date
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    metaCard
                    transcriptCard
                    responseCard
                }
                .padding(16)
            }
        }
    }

    private var header: some View {
        HStack {
            statusBadge
            Text(task.transcript)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
            Spacer()
            if task.status == .running {
                Button("Cancel", role: .destructive) { onCancel() }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(statusLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(statusColor.opacity(0.12))
        .clipShape(Capsule())
    }

    private var metaCard: some View {
        HStack(spacing: 18) {
            meta("Started", task.startedAt.formatted(date: .abbreviated, time: .standard))
            if let finished = task.finishedAt {
                meta("Finished", finished.formatted(date: .abbreviated, time: .standard))
            }
            meta("Duration", formatDuration(task.duration(at: clock)))
            if let exit = task.exitStatus {
                meta("Exit status", "\(exit)")
            }
            Spacer()
        }
        .font(.caption)
    }

    private func meta(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.weight(.medium))
        }
    }

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Transcript")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(task.transcript)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.gray.opacity(0.08))
                )
                .textSelection(.enabled)
        }
    }

    private var responseCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Agent response")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let output = task.output, !output.isEmpty {
                    Button {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(output, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                }
            }

            if let output = task.output, !output.isEmpty {
                Text(output)
                    .font(.system(.body, design: .default))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.purple.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.purple.opacity(0.20), lineWidth: 0.6)
                    )
                    .textSelection(.enabled)
            } else if task.status == .running {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Waiting for the agent…")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } else {
                Text("No response captured.")
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 6)
            }
        }
    }

    private var statusColor: Color {
        switch task.status {
        case .running:    .purple
        case .completed:  .green
        case .failed:     .red
        case .cancelled:  .gray
        }
    }
    private var statusLabel: String {
        switch task.status {
        case .running:    "RUNNING"
        case .completed:  "COMPLETED"
        case .failed:     "FAILED"
        case .cancelled:  "CANCELLED"
        }
    }
}

// MARK: - Shared helpers

private func formatDuration(_ t: TimeInterval) -> String {
    let total = Int(t)
    if total < 60 { return "\(total)s" }
    let m = total / 60
    let s = total % 60
    return String(format: "%dm%02ds", m, s)
}

#endif
