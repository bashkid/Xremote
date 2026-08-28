//
//  Accessibility.swift
//  Polls AXIsProcessTrusted so the server UI can show grant/revoke state live.
//

#if os(macOS)

import AppKit
import ApplicationServices
import Observation

@MainActor
@Observable
final class AccessibilityChecker {
    private(set) var isTrusted: Bool = AXIsProcessTrusted()
    private var timer: Timer?

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let trusted = AXIsProcessTrusted()
                if trusted != self.isTrusted { self.isTrusted = trusted }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Show the macOS prompt asking the user to grant Accessibility permission.
    func requestPermission() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options: CFDictionary = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Open System Settings → Privacy & Security → Accessibility.
    func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

#endif
