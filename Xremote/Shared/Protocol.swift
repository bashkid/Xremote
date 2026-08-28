//
//  Protocol.swift
//  Xremote shared wire protocol
//

import Foundation

// MARK: - Constants

enum XRProtocol {
    static let serviceType = "_xremote._tcp"
    static let defaultPort: UInt16 = 0  // 0 = pick any port; advertised via Bonjour
    static let version = 1
}

// MARK: - Message envelope

enum XRMessageType: String, Codable, Sendable {
    case hello          // client → server: device name + pairing token (if known)
    case helloAck       // server → client: accepted, needs PIN, or rejected
    case pinResponse    // client → server: 6-digit PIN entered by user
    case paired         // server → client: pairing confirmed + new token
    case keyTap         // client → server: virtual key + modifiers (down+up)
    case keyDown        // client → server: virtual key + modifiers
    case keyUp          // client → server: virtual key + modifiers
    case text           // client → server: a string of unicode characters
    case mouseMove      // client → server: relative dx / dy
    case mouseClick     // client → server: button + click count
    case mouseDown      // client → server: button down (held; used for drag)
    case mouseUp        // client → server: button up
    case scroll         // client → server: scroll dx / dy
    case mediaKey       // client → server: media key code (play/pause/etc.)

    // Laser-pointer overlay (Mac-side floating cursor)
    case laserShow      // client → server: open the laser overlay (optional style)
    case laserHide      // client → server: close the laser overlay
    case laserMove      // client → server: move laser by dx, dy
    case laserClick     // client → server: spawn a click ripple at current laser pos
    case laserStyle     // client → server: change cursor style
    case gyroDelta      // client → server: dx, dy from device gyroscope (air mouse)

    // Voice-driven Claude Code automation
    case voiceStart     // client → server: begin a voice session
    case voiceChunk     // client → server: 16kHz mono Int16 PCM chunk
    case voiceStop      // client → server: end voice session; transcribe + run
    case textTask       // client → server: typed task prompt, skips voice
    case taskResponse   // server → client: full agent reply after CLI finishes

    // Bi-directional file manager (envelope for FileTransferPacket)
    case fileTransfer   // both directions: list / download / upload / chunk / complete / failed

    case ping
    case pong
}

enum XRHelloAck: String, Codable, Sendable {
    case accepted
    case needsPin
    case rejected
}

enum XRMouseButton: String, Codable, Sendable {
    case left
    case right
    case middle
}

enum XRMediaKey: String, Codable, Sendable {
    case playPause
    case next
    case previous
    case volumeUp
    case volumeDown
    case mute
}

struct XRModifiers: OptionSet, Codable, Sendable {
    let rawValue: UInt32
    static let shift   = XRModifiers(rawValue: 1 << 0)
    static let control = XRModifiers(rawValue: 1 << 1)
    static let option  = XRModifiers(rawValue: 1 << 2)
    static let command = XRModifiers(rawValue: 1 << 3)
    static let fn      = XRModifiers(rawValue: 1 << 4)
}

/// One wire message. Most fields are optional; the receiver inspects `type`
/// to know which fields to read.
struct XRMessage: Codable, Sendable {
    var type: XRMessageType
    var version: Int = XRProtocol.version

    // hello
    var deviceName: String?
    var deviceToken: String?  // persistent client identity (UUID string)

    // helloAck
    var ack: XRHelloAck?

    // pinResponse
    var pin: String?

    // paired
    var newToken: String?

    // key events
    var key: XRKey?
    var modifiers: XRModifiers?

    // text input
    var text: String?

    // mouse
    var dx: Double?
    var dy: Double?
    var button: XRMouseButton?
    var clickCount: Int?

    // media
    var mediaKey: XRMediaKey?

    // laser pointer
    var pointerStyle: PointerStyle?

    // voice
    /// Raw 16kHz mono Int16 PCM samples. Codable auto-encodes Data as
    /// base64 in JSON, which is fine over the local network.
    var audioData: Data?

    /// The original transcript / typed prompt that produced this response.
    /// Sent back on `.taskResponse` so the iPhone can pair it with the
    /// reply in the history list.
    var transcript: String?

    /// File-manager envelope. Decoded / dispatched by `FileServerBridge`
    /// on the Mac and `FileTransferClient` on the iPhone.
    var fileTransfer: FileTransferPacket?

    static func hello(deviceName: String, token: String?) -> XRMessage {
        var m = XRMessage(type: .hello)
        m.deviceName = deviceName
        m.deviceToken = token
        return m
    }

    static func helloAck(_ ack: XRHelloAck) -> XRMessage {
        var m = XRMessage(type: .helloAck)
        m.ack = ack
        return m
    }

    static func pinResponse(_ pin: String) -> XRMessage {
        var m = XRMessage(type: .pinResponse)
        m.pin = pin
        return m
    }

    static func paired(token: String) -> XRMessage {
        var m = XRMessage(type: .paired)
        m.newToken = token
        return m
    }

    static func keyTap(_ key: XRKey, modifiers: XRModifiers = []) -> XRMessage {
        var m = XRMessage(type: .keyTap)
        m.key = key
        m.modifiers = modifiers
        return m
    }

    static func text(_ s: String) -> XRMessage {
        var m = XRMessage(type: .text)
        m.text = s
        return m
    }

    static func mouseMove(dx: Double, dy: Double) -> XRMessage {
        var m = XRMessage(type: .mouseMove)
        m.dx = dx
        m.dy = dy
        return m
    }

    static func mouseClick(_ button: XRMouseButton, count: Int = 1) -> XRMessage {
        var m = XRMessage(type: .mouseClick)
        m.button = button
        m.clickCount = count
        return m
    }

    static func mouseDown(_ button: XRMouseButton) -> XRMessage {
        var m = XRMessage(type: .mouseDown)
        m.button = button
        return m
    }

    static func mouseUp(_ button: XRMouseButton) -> XRMessage {
        var m = XRMessage(type: .mouseUp)
        m.button = button
        return m
    }

    static func scroll(dx: Double, dy: Double) -> XRMessage {
        var m = XRMessage(type: .scroll)
        m.dx = dx
        m.dy = dy
        return m
    }

    static func mediaKey(_ key: XRMediaKey) -> XRMessage {
        var m = XRMessage(type: .mediaKey)
        m.mediaKey = key
        return m
    }

    static func laserShow(style: PointerStyle? = nil) -> XRMessage {
        var m = XRMessage(type: .laserShow)
        m.pointerStyle = style
        return m
    }

    static func laserHide() -> XRMessage {
        XRMessage(type: .laserHide)
    }

    static func laserMove(dx: Double, dy: Double) -> XRMessage {
        var m = XRMessage(type: .laserMove)
        m.dx = dx
        m.dy = dy
        return m
    }

    static func laserClick() -> XRMessage {
        XRMessage(type: .laserClick)
    }

    static func laserStyle(_ style: PointerStyle) -> XRMessage {
        var m = XRMessage(type: .laserStyle)
        m.pointerStyle = style
        return m
    }

    static func gyroDelta(dx: Double, dy: Double) -> XRMessage {
        var m = XRMessage(type: .gyroDelta)
        m.dx = dx
        m.dy = dy
        return m
    }

    static func voiceStart() -> XRMessage {
        XRMessage(type: .voiceStart)
    }

    static func voiceChunk(_ pcm: Data) -> XRMessage {
        var m = XRMessage(type: .voiceChunk)
        m.audioData = pcm
        return m
    }

    static func voiceStop() -> XRMessage {
        XRMessage(type: .voiceStop)
    }

    static func taskResponse(transcript: String?, response: String) -> XRMessage {
        var m = XRMessage(type: .taskResponse)
        m.text = response
        m.transcript = transcript
        return m
    }

    static func textTask(_ prompt: String) -> XRMessage {
        var m = XRMessage(type: .textTask)
        m.text = prompt
        return m
    }

    static func fileTransfer(_ packet: FileTransferPacket) -> XRMessage {
        var m = XRMessage(type: .fileTransfer)
        m.fileTransfer = packet
        return m
    }

    static let ping = XRMessage(type: .ping)
    static let pong = XRMessage(type: .pong)
}
