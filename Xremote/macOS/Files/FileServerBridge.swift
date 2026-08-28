//
//  FileServerBridge.swift
//  Handles every `.fileTransfer` packet that lands on the Mac: directory
//  listing, file download (chunked stream out), and file upload (chunked
//  stream in). Runs on @MainActor — the disk I/O is dispatched onto a
//  background queue so the listener stays responsive.
//

#if os(macOS)

import Foundation
import Network
import Observation

@MainActor
final class FileServerBridge {
    /// 64 KB raw → ~85 KB base64; comfortably under the 1 MB max frame.
    static let chunkSize: Int = 64 * 1024

    /// Active uploads keyed by transferId. Receives chunks until a
    /// `transferComplete` packet arrives, then flushes to disk.
    private var incomingUploads: [String: UploadState] = [:]

    /// Active outbound downloads keyed by transferId so a cancel can stop
    /// the producer task mid-stream.
    private var activeDownloads: [String: Task<Void, Never>] = [:]

    private struct UploadState {
        let url: URL
        var fileHandle: FileHandle
        var receivedChunks: Int
        var totalChunks: Int
    }

    // MARK: - Dispatch

    /// Entry point called from `XremoteServer.dispatch(_:connection:)`
    /// when a `.fileTransfer` envelope arrives.
    func handle(packet: FileTransferPacket, on connection: NWConnection) {
        switch packet.type {
        case .directoryListRequest:
            Task { await self.serveDirectoryList(path: packet.path, on: connection) }
        case .downloadRequest:
            startDownload(path: packet.path ?? "",
                          transferId: packet.transferId ?? UUID().uuidString,
                          connection: connection)
        case .uploadInit:
            beginUpload(packet: packet)
        case .binaryChunk:
            ingestUploadChunk(packet: packet)
        case .transferComplete:
            finishUpload(transferId: packet.transferId)
        case .transferFailed:
            cancelUpload(transferId: packet.transferId)
        case .directoryListResponse:
            break // client-bound only
        }
    }

    // MARK: - Directory listing

    private func serveDirectoryList(path: String?, on connection: NWConnection) async {
        let raw = path ?? NSHomeDirectory()
        let expanded = (raw as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)

        // Listing the disk is offloaded so the main actor never blocks even
        // on slow / network mounted volumes.
        let entries: [FileMetadata] = await Task.detached(priority: .userInitiated) {
            Self.listDirectory(at: url)
        }.value

        let response = FileTransferPacket(
            type: .directoryListResponse,
            path: expanded,
            entries: entries,
            transferId: nil,
            fileName: nil,
            totalSize: nil,
            chunkIndex: nil,
            totalChunks: nil,
            chunk: nil,
            message: nil
        )
        Task { try? await xrSend(.fileTransfer(response), on: connection) }
    }

    private nonisolated static func listDirectory(at url: URL) -> [FileMetadata] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .fileSizeKey, .totalFileSizeKey,
            .contentModificationDateKey, .nameKey
        ]
        guard let raw = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let mapped: [FileMetadata] = raw.compactMap { child in
            let values = try? child.resourceValues(forKeys: Set(keys))
            let isDir = values?.isDirectory ?? false
            let size: Int64 = Int64(values?.totalFileSize ?? values?.fileSize ?? 0)
            return FileMetadata(
                name: child.lastPathComponent,
                path: child.path,
                isDirectory: isDir,
                fileSize: size,
                modificationDate: values?.contentModificationDate
            )
        }
        // Folders first, then files; both alphabetical (case-insensitive).
        return mapped.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - Download (Mac → iPhone)

    private func startDownload(path: String, transferId: String, connection: NWConnection) {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)

        // Already in flight? Don't double-start.
        if activeDownloads[transferId] != nil { return }

        let task = Task { [chunkSize = Self.chunkSize] in
            await Self.streamFile(
                url: url,
                chunkSize: chunkSize,
                transferId: transferId,
                connection: connection
            )
            await MainActor.run { self.activeDownloads.removeValue(forKey: transferId) }
        }
        activeDownloads[transferId] = task
    }

    /// Reads the file off the main actor and pushes chunks back to the
    /// iPhone as `.binaryChunk` packets, then a final `.transferComplete`.
    private nonisolated static func streamFile(
        url: URL,
        chunkSize: Int,
        transferId: String,
        connection: NWConnection
    ) async {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            let err = FileTransferPacket(
                type: .transferFailed,
                transferId: transferId,
                message: "File not found: \(url.path)"
            )
            try? await xrSend(.fileTransfer(err), on: connection)
            return
        }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let totalChunks = max(1, (size + chunkSize - 1) / chunkSize)

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            let err = FileTransferPacket(
                type: .transferFailed,
                transferId: transferId,
                message: "Couldn't open \(url.lastPathComponent) for reading."
            )
            try? await xrSend(.fileTransfer(err), on: connection)
            return
        }
        defer { try? handle.close() }

        var index = 0
        while !Task.isCancelled {
            let data = (try? handle.read(upToCount: chunkSize)) ?? Data()
            if data.isEmpty { break }
            let pkt = FileTransferPacket(
                type: .binaryChunk,
                transferId: transferId,
                fileName: url.lastPathComponent,
                totalSize: Int64(size),
                chunkIndex: index,
                totalChunks: totalChunks,
                chunk: data
            )
            do {
                try await xrSend(.fileTransfer(pkt), on: connection)
            } catch {
                return
            }
            index += 1
        }

        let done = FileTransferPacket(
            type: .transferComplete,
            transferId: transferId,
            fileName: url.lastPathComponent,
            totalSize: Int64(size),
            totalChunks: totalChunks
        )
        try? await xrSend(.fileTransfer(done), on: connection)
    }

    // MARK: - Upload (iPhone → Mac)

    private func beginUpload(packet: FileTransferPacket) {
        guard let transferId = packet.transferId,
              let name = packet.fileName else { return }

        // Land everything in ~/Downloads/Xremote so we never overwrite
        // something the user actually wants outside of that folder.
        let downloads = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory() + "/Downloads")
        let folder = downloads.appendingPathComponent("Xremote")
        try? FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true
        )
        let target = uniqueFileURL(in: folder, originalName: name)

        FileManager.default.createFile(atPath: target.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: target) else { return }

        incomingUploads[transferId] = UploadState(
            url: target,
            fileHandle: handle,
            receivedChunks: 0,
            totalChunks: packet.totalChunks ?? 0
        )
    }

    private func ingestUploadChunk(packet: FileTransferPacket) {
        guard let id = packet.transferId,
              var state = incomingUploads[id],
              let bytes = packet.chunk else { return }
        try? state.fileHandle.write(contentsOf: bytes)
        state.receivedChunks += 1
        incomingUploads[id] = state
    }

    private func finishUpload(transferId: String?) {
        guard let id = transferId, let state = incomingUploads.removeValue(forKey: id) else { return }
        try? state.fileHandle.close()
    }

    private func cancelUpload(transferId: String?) {
        guard let id = transferId, let state = incomingUploads.removeValue(forKey: id) else { return }
        try? state.fileHandle.close()
        try? FileManager.default.removeItem(at: state.url)
    }

    /// Avoid clobbering an existing file by suffixing " (n)" until free.
    private func uniqueFileURL(in folder: URL, originalName: String) -> URL {
        let fm = FileManager.default
        var url = folder.appendingPathComponent(originalName)
        guard fm.fileExists(atPath: url.path) else { return url }

        let stem = (originalName as NSString).deletingPathExtension
        let ext = (originalName as NSString).pathExtension
        var counter = 1
        while fm.fileExists(atPath: url.path) {
            let suffix = ext.isEmpty ? "\(stem) (\(counter))" : "\(stem) (\(counter)).\(ext)"
            url = folder.appendingPathComponent(suffix)
            counter += 1
        }
        return url
    }
}

#endif
