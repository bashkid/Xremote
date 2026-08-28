//
//  FileTransferPacket.swift
//  Shared serialization contract for the bidirectional file manager.
//  Both targets exchange these envelopes, wrapped inside an `XRMessage`
//  of type `.fileTransfer`.
//

import Foundation

enum TransferPacketType: String, Codable, Sendable {
    case directoryListRequest   // client → server: list this path
    case directoryListResponse  // server → client: items at path
    case downloadRequest        // client → server: start streaming this file
    case uploadInit             // client → server: about to push these N bytes
    case binaryChunk            // either direction: one segment of bytes
    case transferComplete       // either direction: stream finished
    case transferFailed         // either direction: stream errored (text is the reason)
}

struct FileMetadata: Codable, Identifiable, Hashable, Sendable {
    let name: String
    let path: String
    let isDirectory: Bool
    let fileSize: Int64
    let modificationDate: Date?

    /// Identifiable via the absolute path — guaranteed unique within a
    /// directory listing, stable across requests, no UUID re-roll on decode.
    var id: String { path }
}

struct FileTransferPacket: Codable, Sendable {
    let type: TransferPacketType

    // Directory operations
    var path: String?
    var entries: [FileMetadata]?

    // Transfer lifecycle
    /// Stable per-transfer id so the receiver can group chunks (or cancel).
    var transferId: String?
    /// Display name of the file being transferred.
    var fileName: String?
    /// Total bytes the receiver should expect.
    var totalSize: Int64?

    // Chunk payload
    /// 0-based sequence number so out-of-order arrivals can be reordered.
    var chunkIndex: Int?
    var totalChunks: Int?
    /// Raw bytes. Codable encodes Data as base64 in JSON, which is fine
    /// over our local-network framed transport.
    var chunk: Data?

    // Optional human-readable error text on transferFailed.
    var message: String?
}
