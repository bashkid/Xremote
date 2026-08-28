//
//  PointerStyle.swift
//  Shared models for the laser-pointer feature. Transmitted over the wire
//  protocol and used by both the iOS controller and the macOS overlay
//  renderer.
//

import Foundation

enum PointerState: String, Codable, Sendable {
    case idle
    case moving
    case clicked
}

enum PointerStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case pointingHand   // Index finger up
    case openHand       // Open palm hand
    case arrow          // Modern geometric presenter arrow
    case pen            // Stylus nib tip
    case stickHand      // Retro presentation pointer stick

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pointingHand: "Pointing hand"
        case .openHand:     "Open hand"
        case .arrow:        "Arrow"
        case .pen:          "Pen"
        case .stickHand:    "Pointer stick"
        }
    }
}
