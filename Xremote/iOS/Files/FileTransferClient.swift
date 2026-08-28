//
//  FileTransferClient.swift
//  iPhone-side file-manager state machine. Owns directory-listing
//  request/response correlation and inbound / outbound chunk streams.
//
//  Hooks into `XremoteClient`'s inbound message dispatcher via a callback
//  so this file-manager logic stays decoupled from connection lifecycle.
//

#if os(iOS)

import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class FileTransferClient {
    /// Where downloaded files land. Exposed as the app's Documents
    /// directory so the iOS Files app sees them when
    /// `UIFileSharingEnabled` is on.
    var downloadsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    /// In-flight download accumulators keyed by transferId.
    private struct Download {
        let url: URL
        let fileHandle: FileHandle
        var receivedBytes: Int64
        let totalSize: Int64
    }

    /// In-flight upload progress keyed by transferId.
    struct Upload {
        let fileName: String
        var sentChunks: Int
        let totalChunks: Int
    }

    /// Snapshot of what's currently transferring so the UI can show
    /// progress bars.
    var activeDownloads: [String: TransferStatus] = [:]
    var activeUploads: [String: TransferStatus] = [:]

    struct TransferStatus: Identifiable {
        let id: String          // transferId
        let fileName: String
        let totalBytes: Int64
        var sentBytes: Int64
    }

    /// Continuations awaiting directory listings. We only ever have one
    /// outstanding request per path — repeated taps cancel the old one.
    private var pendingListings: [String: CheckedContinuation<[FileMetadata], Never>] = [:]

    /// Latest finished download — observers (e.g. the browser) can present
    /// a share sheet, mark a row done, etc.
    private(set) var lastCompletedDownload: URL?

    private var downloads: [String: Download] = [:]
    private weak var client: XremoteClient?

    init(client: XremoteClient) {
        self.client = client
    }

    // MARK: - Public API

    /// Async directory listing — uses a continuation so callers can
    /// `await client.listDirectory(...)` cleanly.
    func listDirectory(path: String?) async -> [FileMetadata] {
        guard let client else { return [] }
        let resolved = path ?? "~"
        let pkt = FileTransferPacket(type: .directoryListRequest, path: resolved)
        client.send(.fileTransfer(pkt))

        return await withCheckedContinuation { cont in
            // If a previous request for this path is still outstanding,
            // just resume it with empty and replace it. The new listing
            // will arrive shortly.
            if let prior = pendingListings.removeValue(forKey: resolved) {
                prior.resume(returning: [])
            }
            pendingListings[resolved] = cont
        }
    }

    /// Request that the Mac stream this file down to the iPhone. Returns
    /// the transferId so the caller can correlate the eventual UI update.
    @discardableResult
    func downloadFile(_ remote: FileMetadata) -> String {
        guard let client else { return "" }
        let transferId = UUID().uuidString

        // Pre-create the destination file so progress UI can paint a row.
        let dest = uniqueLocalURL(for: remote.name)
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: dest) else { return "" }

        downloads[transferId] = Download(
            url: dest, fileHandle: handle, receivedBytes: 0, totalSize: remote.fileSize
        )
        activeDownloads[transferId] = TransferStatus(
            id: transferId, fileName: remote.name,
            totalBytes: remote.fileSize, sentBytes: 0
        )

        let req = FileTransferPacket(
            type: .downloadRequest,
            path: remote.path,
            transferId: transferId,
            fileName: remote.name,
            totalSize: remote.fileSize
        )
        client.send(.fileTransfer(req))
        return transferId
    }

    /// Push a local iOS file up to the Mac. Reads in 64 KB chunks on a
    /// detached task so the main actor stays free.
    @discardableResult
    func uploadFile(_ localURL: URL, remoteFileName: String? = nil) -> String? {
        guard let client else { return nil }
        guard let data = try? Data(contentsOf: localURL) else { return nil }

        let transferId = UUID().uuidString
        let chunkSize = 64 * 1024
        let total = data.count
        let totalChunks = max(1, (total + chunkSize - 1) / chunkSize)
        let name = remoteFileName ?? localURL.lastPathComponent

        let init_ = FileTransferPacket(
            type: .uploadInit,
            transferId: transferId,
            fileName: name,
            totalSize: Int64(total),
            totalChunks: totalChunks
        )
        client.send(.fileTransfer(init_))

        activeUploads[transferId] = TransferStatus(
            id: transferId, fileName: name,
            totalBytes: Int64(total), sentBytes: 0
        )

        // Stream the chunks off the main actor.
        Task.detached(priority: .userInitiated) { [weak self] in
            var offset = 0
            var index = 0
            while offset < total {
                let end = min(offset + chunkSize, total)
                let slice = data.subdata(in: offset..<end)
                let pkt = FileTransferPacket(
                    type: .binaryChunk,
                    transferId: transferId,
                    fileName: name,
                    totalSize: Int64(total),
                    chunkIndex: index,
                    totalChunks: totalChunks,
                    chunk: slice
                )
                await MainActor.run { client.send(.fileTransfer(pkt)) }
                await MainActor.run {
                    self?.activeUploads[transferId]?.sentBytes = Int64(end)
                }
                offset = end
                index += 1
            }
            let done = FileTransferPacket(
                type: .transferComplete,
                transferId: transferId,
                fileName: name,
                totalSize: Int64(total),
                totalChunks: totalChunks
            )
            await MainActor.run {
                client.send(.fileTransfer(done))
                self?.activeUploads.removeValue(forKey: transferId)
            }
        }
        return transferId
    }

    // MARK: - Inbound handling (called from XremoteClient.handleInbound)

    func handleInbound(_ packet: FileTransferPacket) {
        switch packet.type {
        case .directoryListResponse:
            let key = packet.path ?? "~"
            // Match exact path first; if no exact match, drain any pending
            // request (covers the "~" → "/Users/foo" expansion case).
            if let cont = pendingListings.removeValue(forKey: key) {
                cont.resume(returning: packet.entries ?? [])
            } else if let any = pendingListings.first {
                pendingListings.removeValue(forKey: any.key)
                any.value.resume(returning: packet.entries ?? [])
            }
        case .binaryChunk:
            guard let id = packet.transferId,
                  var dl = downloads[id],
                  let bytes = packet.chunk else { return }
            try? dl.fileHandle.write(contentsOf: bytes)
            dl.receivedBytes += Int64(bytes.count)
            downloads[id] = dl
            activeDownloads[id]?.sentBytes = dl.receivedBytes
        case .transferComplete:
            guard let id = packet.transferId, let dl = downloads.removeValue(forKey: id) else { return }
            try? dl.fileHandle.close()
            activeDownloads.removeValue(forKey: id)
            lastCompletedDownload = dl.url
        case .transferFailed:
            if let id = packet.transferId, let dl = downloads.removeValue(forKey: id) {
                try? dl.fileHandle.close()
                try? FileManager.default.removeItem(at: dl.url)
                activeDownloads.removeValue(forKey: id)
            }
        case .directoryListRequest, .downloadRequest, .uploadInit:
            break // server-bound only
        }
    }

    // MARK: - Helpers

    private func uniqueLocalURL(for name: String) -> URL {
        let folder = downloadsURL
        var url = folder.appendingPathComponent(name)
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }

        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
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
