//
//  ServerStatusView.swift
//  Popover contents anchored to the menu-bar status item.
//

#if os(macOS)

import SwiftUI

struct ServerStatusView: View {
    @Bindable var server: XremoteServer
    @Bindable var accessibility: AccessibilityChecker
    var onOpenTaskDetail: (UUID?) -> Void = { _ in }

    @State private var clock = Date()
    @State private var agentExpanded: Bool = false
    @State private var agentPath: String = ""
    @State private var agentSession: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider()
                accessibilityRow
                Divider()
                serverInfo
                pinRow
                Divider()
                connectedDevices
                Divider()
                tasksDashboard
                Divider()
                agentConfig
                Divider()
                footer
            }
            .padding(16)
            .frame(width: 320)
        }
        .frame(maxHeight: 560)
        // Tick the duration timer ~2/sec so live "running" tasks update.
        .task(id: "tracker-clock") {
            while !Task.isCancelled {
                clock = Date()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "iphone.gen3")
                .font(.title2)
            Text("Xremote Server")
                .font(.headline)
            Spacer()
            // Running-task badge — shown only when there's something to see.
            if server.taskTracker.runningCount > 0 {
                HStack(spacing: 4) {
                    Circle().fill(Color.purple)
                        .frame(width: 6, height: 6)
                    Text("\(server.taskTracker.runningCount) running")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.purple)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.purple.opacity(0.15))
                .clipShape(Capsule())
            }
            Circle()
                .fill(server.isRunning ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var accessibilityRow: some View {
        if !accessibility.isTrusted {
            VStack(alignment: .leading, spacing: 8) {
                Label("Accessibility permission required", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.subheadline.weight(.semibold))
                Text("Xremote Server needs Accessibility access so it can simulate keyboard and mouse input.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Open Settings") { accessibility.openSystemSettings() }
                    Button("Request") { accessibility.requestPermission() }
                }
                .controlSize(.small)
            }
        } else {
            Label("Accessibility granted", systemImage: "checkmark.shield.fill")
                .foregroundStyle(.green)
                .font(.caption)
        }
    }

    private var serverInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Server").font(.caption).foregroundStyle(.secondary)
            Text(server.serverName).font(.body.weight(.medium))
            if server.port > 0 {
                Text("Port \(server.port)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var pinRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pairing PIN").font(.caption).foregroundStyle(.secondary)
            HStack {
                Text(server.pairing.currentPin)
                    .font(.system(.title2, design: .monospaced).weight(.semibold))
                    .tracking(4)
                Spacer()
                Button {
                    server.pairing.rerollPin()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Generate a new PIN")
            }
        }
    }

    private var connectedDevices: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connected devices").font(.caption).foregroundStyle(.secondary)
            if server.connectedDevices.isEmpty {
                Text("None")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(server.connectedDevices, id: \.self) { name in
                    Label(name, systemImage: "iphone")
                        .font(.caption)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Forget all devices") { server.pairing.unpairAll() }
                .controlSize(.small)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .controlSize(.small)
        }
    }

    // MARK: - OpenClaw agent config

    private var agentConfig: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .foregroundStyle(.blue)
                Text("OpenClaw agent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    if !agentExpanded {
                        agentPath = server.openClawBridge.executablePath
                        agentSession = server.openClawBridge.sessionKey
                    }
                    withAnimation { agentExpanded.toggle() }
                } label: {
                    Image(systemName: agentExpanded ? "chevron.up" : "chevron.down")
                }
                .buttonStyle(.borderless)
            }

            // Preview of the exact command shape that runs per voice task.
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .foregroundStyle(.tertiary)
                    .font(.caption2)
                Text(server.openClawBridge.previewCommand())
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.gray.opacity(0.08))
            )

            if agentExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Executable path")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("/usr/local/bin/openclaw", text: $agentPath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))

                    Text("Session key — passed as -—session-key")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField("main", text: $agentSession)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))

                    HStack {
                        Spacer()
                        Button("Save") {
                            let p = agentPath.trimmingCharacters(in: .whitespacesAndNewlines)
                            let s = agentSession.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !p.isEmpty { server.openClawBridge.executablePath = p }
                            if !s.isEmpty { server.openClawBridge.sessionKey = s }
                            withAnimation { agentExpanded = false }
                        }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Tasks dashboard

    private var tasksDashboard: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The whole header is tappable — clicking "Voice tasks"
            // opens the full dashboard window.
            Button {
                onOpenTaskDetail(nil)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .foregroundStyle(.purple)
                    Text("Voice tasks")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open the full tasks dashboard window")

            HStack(spacing: 8) {
                taskSummaryStrip
                Spacer()
                if server.taskTracker.hasHistory {
                    Button {
                        server.taskTracker.clearHistory()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Clear finished tasks")
                }
            }

            // Show only the 3 most-recent rows here. Everything else lives
            // in the dashboard window — the header link above opens it.
            let recent = Array(server.taskTracker.tasks.prefix(3))
            if !recent.isEmpty {
                VStack(spacing: 6) {
                    ForEach(recent) { task in
                        TaskRow(task: task,
                                clock: clock,
                                onCancel: { server.cancelTask(task.id) },
                                onOpenDetail: { onOpenTaskDetail(task.id) })
                    }
                }
                if server.taskTracker.tasks.count > recent.count {
                    Button {
                        onOpenTaskDetail(nil)
                    } label: {
                        HStack(spacing: 4) {
                            Text("View all \(server.taskTracker.tasks.count) tasks")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.purple)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.purple)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("No tasks yet. Hold the mic on the iPhone to start one.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var taskSummaryStrip: some View {
        HStack(spacing: 10) {
            summaryChip(label: "Running",
                        value: server.taskTracker.runningCount,
                        color: .purple)
            summaryChip(label: "Done",
                        value: server.taskTracker.tasks.filter { $0.status == .completed }.count,
                        color: .green)
            summaryChip(label: "Failed",
                        value: server.taskTracker.tasks.filter { $0.status == .failed }.count,
                        color: .red)
        }
    }

    private func summaryChip(label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
    }
}

// MARK: - Task row

private struct TaskRow: View {
    let task: TaskTracker.ManagedTask
    let clock: Date
    let onCancel: () -> Void
    let onOpenDetail: () -> Void

    var body: some View {
        Button(action: onOpenDetail) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    statusDot
                    Text(task.transcript)
                        .font(.caption.weight(.medium))
                        .lineLimit(2)
                    Spacer()
                    Text(formatDuration(task.duration(at: clock)))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    if task.status == .running {
                        Button {
                            onCancel()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("Cancel this task")
                    }
                }
                if let output = task.output, !output.isEmpty, task.status != .running {
                    Text(output)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.gray.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .help("Open detailed view")
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 7, height: 7)
            .overlay(
                Circle()
                    .stroke(statusColor.opacity(0.3), lineWidth: 3)
                    .scaleEffect(task.status == .running ? 1.6 : 1)
                    .opacity(task.status == .running ? 0.6 : 0)
            )
    }

    private var statusColor: Color {
        switch task.status {
        case .running:    .purple
        case .completed:  .green
        case .failed:     .red
        case .cancelled:  .gray
        }
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let total = Int(t)
        if total < 60 {
            return "\(total)s"
        }
        let m = total / 60
        let s = total % 60
        return String(format: "%dm%02ds", m, s)
    }
}

#endif
