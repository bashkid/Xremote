//
//  FilesBrowserView.swift
//  The new "Files" tab: browse the Mac's filesystem, pull down to refresh,
//  tap a folder to dive in, swipe a file for actions (download, share).
//  An upload button at the bottom picks a local iOS file and streams it
//  up to ~/Downloads/Xremote on the Mac.
//

#if os(iOS)

import SwiftUI
import UniformTypeIdentifiers

struct FilesBrowserView: View {
    @Bindable var client: XremoteClient

    @State private var currentPath: String = "~"
    @State private var entries: [FileMetadata] = []
    @State private var isLoading: Bool = false
    @State private var pickerShown: Bool = false
    @State private var shareItem: URL?

    private var fileClient: FileTransferClient? { client.fileClient }

    var body: some View {
        VStack(spacing: 0) {
            pathBar
            transferStrip
            list
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if entries.isEmpty { Task { await refresh() } }
        }
        .onChange(of: fileClient?.lastCompletedDownload) { _, url in
            if let url { shareItem = url }
        }
        .sheet(item: $shareItem) { url in
            ShareSheet(items: [url])
        }
        .sheet(isPresented: $pickerShown) {
            DocumentPicker { urls in
                guard let first = urls.first else { return }
                _ = fileClient?.uploadFile(first)
            }
        }
        .safeAreaInset(edge: .bottom) {
            uploadButton
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Path bar

    private var pathBar: some View {
        HStack(spacing: 10) {
            Button {
                Haptic.soft()
                currentPath = "~"
                Task { await refresh() }
            } label: {
                Image(systemName: "house.fill")
            }

            Button {
                Haptic.soft()
                navigateUp()
            } label: {
                Image(systemName: "arrow.up.circle")
            }
            .disabled(currentPath == "/" || currentPath == "~")

            Text(currentPath)
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .truncationMode(.head)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Haptic.soft()
                    Task { await refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Rectangle().fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Transfer progress strip

    @ViewBuilder
    private var transferStrip: some View {
        let active = (fileClient?.activeDownloads.values.map { $0 } ?? []) +
                     (fileClient?.activeUploads.values.map { $0 } ?? [])
        if !active.isEmpty {
            VStack(spacing: 6) {
                ForEach(active) { status in
                    TransferRow(status: status)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.07))
        }
    }

    // MARK: - List

    private var list: some View {
        Group {
            if entries.isEmpty && !isLoading {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 44))
                        .foregroundStyle(.tertiary)
                    Text("Empty folder")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(entries) { entry in
                        Button {
                            Haptic.soft()
                            tapped(entry)
                        } label: {
                            row(entry)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            if !entry.isDirectory {
                                Button {
                                    Haptic.tap()
                                    _ = fileClient?.downloadFile(entry)
                                } label: {
                                    Label("Download", systemImage: "arrow.down.circle")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable { await refresh() }
            }
        }
    }

    private func row(_ entry: FileMetadata) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.isDirectory ? "folder.fill" : icon(for: entry.name))
                .font(.title3)
                .foregroundStyle(entry.isDirectory ? Color.accentColor : Color.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 6) {
                    if !entry.isDirectory {
                        Text(formatBytes(entry.fileSize))
                    }
                    if let date = entry.modificationDate {
                        if !entry.isDirectory { Text("·") }
                        Text(date, format: .relative(presentation: .named))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            if entry.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private var uploadButton: some View {
        Button {
            Haptic.tap()
            pickerShown = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.circle.fill")
                Text("Upload to Mac")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                Capsule().fill(Color.accentColor)
            )
        }
        .buttonStyle(PressableGlassStyle())
    }

    // MARK: - Actions

    private func tapped(_ entry: FileMetadata) {
        if entry.isDirectory {
            currentPath = entry.path
            Task { await refresh() }
        } else {
            // For files: download to local Documents.
            _ = fileClient?.downloadFile(entry)
        }
    }

    private func navigateUp() {
        let resolved = (currentPath as NSString).expandingTildeInPath
        let parent = (resolved as NSString).deletingLastPathComponent
        currentPath = parent.isEmpty ? "/" : parent
        Task { await refresh() }
    }

    private func refresh() async {
        guard let fileClient else { return }
        isLoading = true
        let next = await fileClient.listDirectory(path: currentPath)
        entries = next
        isLoading = false
    }

    private func icon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "tiff", "bmp":
            return "photo"
        case "mp4", "mov", "avi", "mkv":
            return "film"
        case "mp3", "m4a", "wav", "aac", "flac":
            return "music.note"
        case "pdf":
            return "doc.richtext"
        case "zip", "tar", "gz", "rar", "7z":
            return "doc.zipper"
        case "txt", "md", "rtf":
            return "doc.text"
        case "swift", "py", "js", "ts", "rb", "go", "rs", "java", "c", "cpp", "h":
            return "chevron.left.forwardslash.chevron.right"
        default:
            return "doc"
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Transfer row

private struct TransferRow: View {
    let status: FileTransferClient.TransferStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(status.fileName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer()
                Text(progressLabel)
                    .font(.caption2.weight(.medium).monospaced())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .progressViewStyle(.linear)
        }
    }

    private var progress: Double {
        guard status.totalBytes > 0 else { return 0 }
        return min(1.0, Double(status.sentBytes) / Double(status.totalBytes))
    }

    private var progressLabel: String {
        let fmt = ByteCountFormatter()
        fmt.countStyle = .file
        let sent = fmt.string(fromByteCount: status.sentBytes)
        let total = fmt.string(fromByteCount: status.totalBytes)
        return "\(sent) / \(total)"
    }
}

// MARK: - UIKit pickers / share

private struct DocumentPicker: UIViewControllerRepresentable {
    var onPicked: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPicked: ([URL]) -> Void
        init(onPicked: @escaping ([URL]) -> Void) { self.onPicked = onPicked }
        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) { onPicked(urls) }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// Make URL Identifiable so it can drive .sheet(item:)
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

#endif
