//
//  PairingManager.swift
//  Generates a 6-digit PIN per session and persists already-paired device tokens.
//

#if os(macOS)

import Foundation
import Observation

@MainActor
@Observable
final class PairingManager {
    /// PIN shown to the user. Re-rolled on launch and after each successful pair.
    private(set) var currentPin: String = PairingManager.generatePin()

    private let storageKey = "XremotePairedTokens"
    private var pairedTokens: Set<String>

    init() {
        let stored = UserDefaults.standard.array(forKey: storageKey) as? [String] ?? []
        self.pairedTokens = Set(stored)
    }

    func isPaired(token: String?) -> Bool {
        guard let token else { return false }
        return pairedTokens.contains(token)
    }

    /// Returns true if pin matched; saves the new token; rerolls the visible PIN.
    func pair(pin: String, newToken: String) -> Bool {
        guard pin == currentPin else { return false }
        pairedTokens.insert(newToken)
        UserDefaults.standard.set(Array(pairedTokens), forKey: storageKey)
        rerollPin()
        return true
    }

    func rerollPin() {
        currentPin = PairingManager.generatePin()
    }

    func unpairAll() {
        pairedTokens.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private static func generatePin() -> String {
        var n = UInt32.random(in: 0..<1_000_000)
        var s = ""
        for _ in 0..<6 {
            s = "\(n % 10)" + s
            n /= 10
        }
        return s
    }
}

#endif
