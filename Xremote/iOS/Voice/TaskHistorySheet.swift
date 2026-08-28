//
//  TaskHistorySheet.swift
//  Browses the persisted prompt → response history surfaced from
//  `XremoteClient.taskHistory`. Tap a row to dive into the full response.
//

#if os(iOS)

import SwiftUI

struct TaskHistorySheet: View {
    @Bindable var client: XremoteClient
    @Environment(\.dismiss) private var dismiss
    @State private var selected: TaskHistoryItem?

    var body: some View {
        NavigationStack {
            Group {
                if client.taskHistory.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !client.taskHistory.isEmpty {
                        Menu {
                            Button(role: .destructive) {
                                client.clearTaskHistory()
                            } label: {
                                Label("Clear all", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(item: $selected) { item in
                TaskHistoryDetail(item: item)
            }
        }
    }

    // MARK: - States

    private var list: some View {
        List {
            ForEach(client.taskHistory) { item in
                Button {
                    Haptic.soft()
                    selected = item
                } label: {
                    row(item)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                let ids = offsets.map { client.taskHistory[$0].id }
                for id in ids { client.deleteTaskHistoryItem(id) }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ item: TaskHistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.transcript)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            Text(item.response)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(item.timestamp, format: .relative(presentation: .named))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("No history yet")
                .font(.headline)
            Text("Voice or typed tasks you send to openclaw will appear here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Detail

private struct TaskHistoryDetail: View {
    let item: TaskHistoryItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("You asked", body: item.transcript, tint: .blue)
                    section("openclaw replied", body: item.response, tint: .purple)
                    Text(item.timestamp.formatted(date: .abbreviated, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(16)
            }
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = item.response
                        Haptic.soft()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("Copy reply")
                }
            }
        }
        .presentationDetents([.large])
    }

    private func section(_ title: String, body: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(body)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tint.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(tint.opacity(0.25), lineWidth: 0.6)
                )
        }
    }
}

#endif
