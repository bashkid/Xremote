//
//  FramedTransport.swift
//  4-byte big-endian length prefix + JSON-encoded XRMessage payload over NWConnection.
//

import Foundation
import Network

enum XRTransportError: Error {
    case connectionClosed
    case malformedFrame
    case oversizeFrame
}

/// Maximum allowed payload (1 MB) — guards against memory abuse.
private let kMaxFrameSize: UInt32 = 1024 * 1024

/// Send a single XRMessage as a framed JSON payload.
func xrSend(_ message: XRMessage, on connection: NWConnection) async throws {
    let data = try JSONEncoder().encode(message)
    var length = UInt32(data.count).bigEndian
    var frame = Data(bytes: &length, count: 4)
    frame.append(data)

    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
        connection.send(content: frame, completion: .contentProcessed { error in
            if let error { cont.resume(throwing: error) }
            else { cont.resume() }
        })
    }
}

/// Receive one framed XRMessage. Throws on connection close or malformed input.
func xrReceive(on connection: NWConnection) async throws -> XRMessage {
    let header = try await receiveExactly(4, on: connection)
    let length = header.withUnsafeBytes { ptr -> UInt32 in
        UInt32(bigEndian: ptr.load(as: UInt32.self))
    }
    guard length > 0 else { throw XRTransportError.malformedFrame }
    guard length <= kMaxFrameSize else { throw XRTransportError.oversizeFrame }

    let body = try await receiveExactly(Int(length), on: connection)
    return try JSONDecoder().decode(XRMessage.self, from: body)
}

private func receiveExactly(_ count: Int, on connection: NWConnection) async throws -> Data {
    var buffer = Data()
    buffer.reserveCapacity(count)
    while buffer.count < count {
        let needed = count - buffer.count
        let chunk = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: needed) { data, _, isComplete, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                if let data, !data.isEmpty {
                    cont.resume(returning: data)
                } else if isComplete {
                    cont.resume(throwing: XRTransportError.connectionClosed)
                } else {
                    cont.resume(returning: Data())
                }
            }
        }
        if chunk.isEmpty { throw XRTransportError.connectionClosed }
        buffer.append(chunk)
    }
    return buffer
}
