//
//  MouseSimulator.swift
//  Posts mouse movement, clicks, and scrolling via CGEvent.
//

#if os(macOS)

import AppKit
import CoreGraphics

enum MouseSimulator {

    /// Tracks which buttons are currently held by `down(_:)`. Used so that a
    /// subsequent `move` emits the proper `*Dragged` event instead of a bare
    /// `mouseMoved`, which is what most macOS apps watch for during a drag.
    private nonisolated(unsafe) static var heldButtons: Set<XRMouseButton> = []

    /// Move the cursor by a delta (in screen points). If a mouse button is
    /// currently held (started via `down(_:)`), emits a *Dragged* event for
    /// that button instead of a plain `mouseMoved`.
    static func move(dx: Double, dy: Double) {
        let current = currentMouseLocation()
        let target = clampToScreens(CGPoint(x: current.x + dx, y: current.y + dy))
        if let held = heldButtons.first {
            let (cgButton, type) = dragComponents(for: held)
            post(type, at: target, button: cgButton)
        } else {
            post(.mouseMoved, at: target, button: .left)
        }
    }

    static func click(_ button: XRMouseButton, count: Int) {
        let location = currentMouseLocation()
        let cgButton: CGMouseButton
        let downType: CGEventType
        let upType: CGEventType
        switch button {
        case .left:
            cgButton = .left;   downType = .leftMouseDown;  upType = .leftMouseUp
        case .right:
            cgButton = .right;  downType = .rightMouseDown; upType = .rightMouseUp
        case .middle:
            cgButton = .center; downType = .otherMouseDown; upType = .otherMouseUp
        }
        let clicks = max(1, count)
        for i in 0..<clicks {
            postMouse(downType, at: location, button: cgButton, clickState: i + 1)
            postMouse(upType,   at: location, button: cgButton, clickState: i + 1)
        }
    }

    /// Press a mouse button without releasing it. Used to start a drag.
    static func down(_ button: XRMouseButton) {
        let location = currentMouseLocation()
        let (cgButton, type) = downComponents(for: button)
        heldButtons.insert(button)
        postMouse(type, at: location, button: cgButton, clickState: 1)
    }

    /// Release a previously-pressed mouse button. Used to end a drag.
    static func up(_ button: XRMouseButton) {
        let location = currentMouseLocation()
        let (cgButton, type) = upComponents(for: button)
        heldButtons.remove(button)
        postMouse(type, at: location, button: cgButton, clickState: 1)
    }

    private static func downComponents(for button: XRMouseButton) -> (CGMouseButton, CGEventType) {
        switch button {
        case .left:   return (.left, .leftMouseDown)
        case .right:  return (.right, .rightMouseDown)
        case .middle: return (.center, .otherMouseDown)
        }
    }

    private static func upComponents(for button: XRMouseButton) -> (CGMouseButton, CGEventType) {
        switch button {
        case .left:   return (.left, .leftMouseUp)
        case .right:  return (.right, .rightMouseUp)
        case .middle: return (.center, .otherMouseUp)
        }
    }

    private static func dragComponents(for button: XRMouseButton) -> (CGMouseButton, CGEventType) {
        switch button {
        case .left:   return (.left, .leftMouseDragged)
        case .right:  return (.right, .rightMouseDragged)
        case .middle: return (.center, .otherMouseDragged)
        }
    }

    static func scroll(dx: Double, dy: Double) {
        let source = CGEventSource(stateID: .hidSystemState)
        let yLines = Int32(dy.rounded())
        let xLines = Int32(dx.rounded())
        if let event = CGEvent(scrollWheelEvent2Source: source,
                               units: .pixel,
                               wheelCount: 2,
                               wheel1: yLines,
                               wheel2: xLines,
                               wheel3: 0) {
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Helpers

    private static func currentMouseLocation() -> CGPoint {
        // NSEvent.mouseLocation is in Cocoa coords (origin bottom-left).
        // CGEvent uses Quartz coords (origin top-left of the primary display).
        let cocoa = NSEvent.mouseLocation
        guard let primary = NSScreen.screens.first else { return .zero }
        let primaryHeight = primary.frame.height
        return CGPoint(x: cocoa.x, y: primaryHeight - cocoa.y)
    }

    private static func clampToScreens(_ point: CGPoint) -> CGPoint {
        guard let primary = NSScreen.screens.first else { return point }
        let primaryHeight = primary.frame.height
        // Convert each Cocoa screen frame into Quartz coords and union them.
        var union: CGRect = .null
        for screen in NSScreen.screens {
            let f = screen.frame
            let quartz = CGRect(x: f.origin.x,
                                y: primaryHeight - (f.origin.y + f.height),
                                width: f.width,
                                height: f.height)
            union = union.isNull ? quartz : union.union(quartz)
        }
        guard !union.isNull else { return point }
        let x = min(max(point.x, union.minX), union.maxX - 1)
        let y = min(max(point.y, union.minY), union.maxY - 1)
        return CGPoint(x: x, y: y)
    }

    private static func post(_ type: CGEventType, at point: CGPoint, button: CGMouseButton) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let event = CGEvent(mouseEventSource: source,
                               mouseType: type,
                               mouseCursorPosition: point,
                               mouseButton: button) {
            event.post(tap: .cghidEventTap)
        }
    }

    private static func postMouse(_ type: CGEventType, at point: CGPoint, button: CGMouseButton, clickState: Int) {
        let source = CGEventSource(stateID: .hidSystemState)
        if let event = CGEvent(mouseEventSource: source,
                               mouseType: type,
                               mouseCursorPosition: point,
                               mouseButton: button) {
            event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
            event.post(tap: .cghidEventTap)
        }
    }
}

#endif
