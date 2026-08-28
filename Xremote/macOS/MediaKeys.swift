//
//  MediaKeys.swift
//  Posts hardware media key events using NSEvent's systemDefined subtype 8.
//

#if os(macOS)

import AppKit

enum MediaKeys {

    // From IOKit/hidsystem/ev_keymap.h
    private static let NX_KEYTYPE_PLAY: Int = 16
    private static let NX_KEYTYPE_NEXT: Int = 17
    private static let NX_KEYTYPE_PREVIOUS: Int = 18
    private static let NX_KEYTYPE_FAST: Int = 19
    private static let NX_KEYTYPE_REWIND: Int = 20
    private static let NX_KEYTYPE_SOUND_UP: Int = 0
    private static let NX_KEYTYPE_SOUND_DOWN: Int = 1
    private static let NX_KEYTYPE_MUTE: Int = 7

    static func post(_ key: XRMediaKey) {
        let code: Int
        switch key {
        case .playPause:  code = NX_KEYTYPE_PLAY
        case .next:       code = NX_KEYTYPE_NEXT
        case .previous:   code = NX_KEYTYPE_PREVIOUS
        case .volumeUp:   code = NX_KEYTYPE_SOUND_UP
        case .volumeDown: code = NX_KEYTYPE_SOUND_DOWN
        case .mute:       code = NX_KEYTYPE_MUTE
        }
        sendSystemDefined(code: code, keyDown: true)
        sendSystemDefined(code: code, keyDown: false)
    }

    /// Volume up / down / mute are routed through Apple's HID system rather
    /// than the keyboard tap. NSEvent provides a Cocoa-friendly bridge.
    private static func sendSystemDefined(code: Int, keyDown: Bool) {
        let flags: NSEvent.ModifierFlags = keyDown ? [.init(rawValue: 0xA00)] : [.init(rawValue: 0xB00)]
        let data1 = (code << 16) | ((keyDown ? 0xA : 0xB) << 8)
        guard let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ) else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
}

#endif
