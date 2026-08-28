//
//  Keycodes.swift
//  Xremote shared virtual key codes
//
//  Values match Carbon HIToolbox virtual key codes (kVK_*), which is what
//  CGEvent expects on macOS. Defined here so iOS can reference them without
//  importing Carbon.
//

import Foundation

enum XRKey: UInt16, Codable, Sendable {
    // Letters
    case a = 0x00
    case s = 0x01
    case d = 0x02
    case f = 0x03
    case h = 0x04
    case g = 0x05
    case z = 0x06
    case x = 0x07
    case c = 0x08
    case v = 0x09
    case b = 0x0B
    case q = 0x0C
    case w = 0x0D
    case e = 0x0E
    case r = 0x0F
    case y = 0x10
    case t = 0x11
    case o = 0x1F
    case u = 0x20
    case i = 0x22
    case p = 0x23
    case l = 0x25
    case j = 0x26
    case k = 0x28
    case n = 0x2D
    case m = 0x2E

    // Numbers row
    case num1 = 0x12
    case num2 = 0x13
    case num3 = 0x14
    case num4 = 0x15
    case num5 = 0x17
    case num6 = 0x16
    case num7 = 0x1A
    case num8 = 0x1C
    case num9 = 0x19
    case num0 = 0x1D

    // Modifiers (raw key codes — usually sent via flags, not as keys)
    case shift          = 0x38
    case control        = 0x3B
    case option         = 0x3A
    case command        = 0x37
    case capsLock       = 0x39
    case fn             = 0x3F
    case rightShift     = 0x3C
    case rightControl   = 0x3E
    case rightOption    = 0x3D
    case rightCommand   = 0x36

    // Editing
    case returnKey      = 0x24
    case tab            = 0x30
    case space          = 0x31
    case delete         = 0x33
    case forwardDelete  = 0x75
    case escape         = 0x35

    // Arrows
    case leftArrow      = 0x7B
    case rightArrow     = 0x7C
    case downArrow      = 0x7D
    case upArrow        = 0x7E

    // Navigation
    case home           = 0x73
    case end            = 0x77
    case pageUp         = 0x74
    case pageDown       = 0x79

    // Function keys
    case f1  = 0x7A
    case f2  = 0x78
    case f3  = 0x63
    case f4  = 0x76
    case f5  = 0x60
    case f6  = 0x61
    case f7  = 0x62
    case f8  = 0x64
    case f9  = 0x65
    case f10 = 0x6D
    case f11 = 0x67
    case f12 = 0x6F

    // Punctuation
    case minus      = 0x1B
    case equal      = 0x18
    case leftBracket  = 0x21
    case rightBracket = 0x1E
    case backslash  = 0x2A
    case semicolon  = 0x29
    case quote      = 0x27
    case comma      = 0x2B
    case period     = 0x2F
    case slash      = 0x2C
    case grave      = 0x32
}
