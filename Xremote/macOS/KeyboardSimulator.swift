//
//  KeyboardSimulator.swift
//  Posts synthetic keyboard events using CGEvent + Quartz HID tap.
//

#if os(macOS)

import CoreGraphics
import Foundation

enum KeyboardSimulator {

    /// Type an arbitrary string. For ASCII characters we map to real
    /// US-keyboard virtual keys + shift state — this avoids the
    /// `virtualKey: 0` artifact where some apps would also process the
    /// phantom 'a' keycode. For characters outside the map (emoji, accented
    /// letters, CJK, etc.) we fall back to Unicode-string injection.
    static func type(_ string: String) {
        for char in string {
            if let mapping = Self.asciiMap[char] {
                let mods: XRModifiers = mapping.shift ? [.shift] : []
                tap(mapping.key, modifiers: mods)
            } else {
                typeUnicode(String(char))
            }
        }
    }

    /// Tap a virtual key (down then up) with the given modifier set.
    static func tap(_ key: XRKey, modifiers: XRModifiers) {
        let source = CGEventSource(stateID: .hidSystemState)
        let flags = cgFlags(from: modifiers)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: true) {
            down.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: false) {
            up.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
    }

    static func keyDown(_ key: XRKey, modifiers: XRModifiers) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let event = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: true) {
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            event.flags = cgFlags(from: modifiers)
            event.post(tap: .cghidEventTap)
        }
    }

    static func keyUp(_ key: XRKey, modifiers: XRModifiers) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let event = CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: false) {
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            event.flags = cgFlags(from: modifiers)
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Unicode fallback

    /// Inject a string by overriding the keyboard event's Unicode payload.
    /// Used only for characters not in `asciiMap` (emoji, non-Latin, etc.).
    private static func typeUnicode(_ string: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        let utf16 = Array(string.utf16)
        utf16.withUnsafeBufferPointer { buf in
            guard let baseAddress = buf.baseAddress else { return }
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                down.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
                down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: baseAddress)
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
                up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: baseAddress)
                up.post(tap: .cghidEventTap)
            }
        }
    }

    private static func cgFlags(from mods: XRModifiers) -> CGEventFlags {
        var flags: CGEventFlags = []
        if mods.contains(.shift)   { flags.insert(.maskShift) }
        if mods.contains(.control) { flags.insert(.maskControl) }
        if mods.contains(.option)  { flags.insert(.maskAlternate) }
        if mods.contains(.command) { flags.insert(.maskCommand) }
        if mods.contains(.fn)      { flags.insert(.maskSecondaryFn) }
        return flags
    }

    // MARK: - US-keyboard character → keycode map

    /// Each entry: (virtual key, whether shift is required for that glyph).
    /// US ANSI layout. Characters not in this map (Unicode, emoji, accented
    /// chars on non-US layouts) fall through to `typeUnicode`.
    private static let asciiMap: [Character: (key: XRKey, shift: Bool)] = [
        // Lowercase
        "a": (.a, false), "b": (.b, false), "c": (.c, false), "d": (.d, false),
        "e": (.e, false), "f": (.f, false), "g": (.g, false), "h": (.h, false),
        "i": (.i, false), "j": (.j, false), "k": (.k, false), "l": (.l, false),
        "m": (.m, false), "n": (.n, false), "o": (.o, false), "p": (.p, false),
        "q": (.q, false), "r": (.r, false), "s": (.s, false), "t": (.t, false),
        "u": (.u, false), "v": (.v, false), "w": (.w, false), "x": (.x, false),
        "y": (.y, false), "z": (.z, false),

        // Uppercase
        "A": (.a, true), "B": (.b, true), "C": (.c, true), "D": (.d, true),
        "E": (.e, true), "F": (.f, true), "G": (.g, true), "H": (.h, true),
        "I": (.i, true), "J": (.j, true), "K": (.k, true), "L": (.l, true),
        "M": (.m, true), "N": (.n, true), "O": (.o, true), "P": (.p, true),
        "Q": (.q, true), "R": (.r, true), "S": (.s, true), "T": (.t, true),
        "U": (.u, true), "V": (.v, true), "W": (.w, true), "X": (.x, true),
        "Y": (.y, true), "Z": (.z, true),

        // Digits
        "0": (.num0, false), "1": (.num1, false), "2": (.num2, false),
        "3": (.num3, false), "4": (.num4, false), "5": (.num5, false),
        "6": (.num6, false), "7": (.num7, false), "8": (.num8, false),
        "9": (.num9, false),

        // Shifted digits
        ")": (.num0, true), "!": (.num1, true), "@": (.num2, true),
        "#": (.num3, true), "$": (.num4, true), "%": (.num5, true),
        "^": (.num6, true), "&": (.num7, true), "*": (.num8, true),
        "(": (.num9, true),

        // Punctuation
        " ": (.space, false),
        "-": (.minus, false), "_": (.minus, true),
        "=": (.equal, false), "+": (.equal, true),
        "[": (.leftBracket, false), "{": (.leftBracket, true),
        "]": (.rightBracket, false), "}": (.rightBracket, true),
        "\\": (.backslash, false), "|": (.backslash, true),
        ";": (.semicolon, false), ":": (.semicolon, true),
        "'": (.quote, false), "\"": (.quote, true),
        ",": (.comma, false), "<": (.comma, true),
        ".": (.period, false), ">": (.period, true),
        "/": (.slash, false), "?": (.slash, true),
        "`": (.grave, false), "~": (.grave, true),

        // Whitespace
        "\n": (.returnKey, false),
        "\r": (.returnKey, false),
        "\t": (.tab, false),
    ]
}

#endif
