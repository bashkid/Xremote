//
//  KeyboardView.swift
//  Hidden TextField captures system keyboard input; each character is forwarded
//  as a `text` message. A row of buttons exposes special / modified keys.
//

#if os(iOS)

import SwiftUI

struct KeyboardView: View {
    @Bindable var client: XremoteClient

    @State private var buffer: String = ""
    @State private var suppressNextChange = false
    @FocusState private var focused: Bool

    @State private var shift = false
    @State private var control = false
    @State private var option = false
    @State private var command = false

    // Echo detection: when we send a character to the Mac, the Mac posts a
    // global CGEvent. On the iOS Simulator, that event leaks back into the
    // focused TextField as if the user had typed it. We drop any change
    // that re-introduces the character we just sent within `echoWindow`.
    @State private var lastSentSnippet: String = ""
    @State private var lastSentAt: Date = .distantPast
    private let echoWindow: TimeInterval = 0.5

    var body: some View {
        VStack(spacing: 16) {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Tap below and start typing. Characters appear on \(client.serverName).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    captureField

                    modifierRow

                    specialKeyGrid

                    shortcutsGrid
                }
                .padding(.vertical, 8)
            }
        }
        .padding()
    }

    private var captureField: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                if buffer.isEmpty {
                    Text("Type here…")
                        .foregroundStyle(.tertiary)
                }
                TextField("", text: $buffer)
                    .focused($focused)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.return)
                    .onChange(of: buffer) { oldValue, newValue in
                        if suppressNextChange {
                            suppressNextChange = false
                            return
                        }
                        // Echo detection — drop changes that look like the
                        // Mac re-typing what we just sent (simulator artifact).
                        let added = addedChars(from: oldValue, to: newValue)
                        if !added.isEmpty,
                           added == lastSentSnippet,
                           Date().timeIntervalSince(lastSentAt) < echoWindow {
                            suppressNextChange = true
                            buffer = oldValue
                            return
                        }
                        forwardDifference(from: oldValue, to: newValue)
                        if !added.isEmpty {
                            lastSentSnippet = added
                            lastSentAt = Date()
                        }
                    }
                    .onSubmit {
                        sendKey(.returnKey)
                    }
            }
            if !buffer.isEmpty {
                Button {
                    suppressNextChange = true
                    buffer = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(PressableGlassStyle())
                .accessibilityLabel("Clear")
            }
        }
        .font(.body)
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { focused = true }
    }

    private var modifierRow: some View {
        HStack(spacing: 8) {
            modifierButton(label: "⇧", on: $shift)
            modifierButton(label: "⌃", on: $control)
            modifierButton(label: "⌥", on: $option)
            modifierButton(label: "⌘", on: $command)
        }
    }

    private var specialKeyGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            keyButton("esc",   icon: "escape",                 key: .escape)
            keyButton("tab",   icon: "arrow.right.to.line",    key: .tab)
            keyButton("⌫",     icon: "delete.left",            key: .delete)
            keyButton("return", icon: "return",                key: .returnKey)
            keyButton("←",     icon: "arrow.left",             key: .leftArrow)
            keyButton("↑",     icon: "arrow.up",               key: .upArrow)
            keyButton("↓",     icon: "arrow.down",             key: .downArrow)
            keyButton("→",     icon: "arrow.right",            key: .rightArrow)
            keyButton("home",  icon: "house",                  key: .home)
            keyButton("end",   icon: "arrow.up.right.square",  key: .end)
            keyButton("pg↑",   icon: "arrow.up.to.line",       key: .pageUp)
            keyButton("pg↓",   icon: "arrow.down.to.line",     key: .pageDown)
        }
    }

    private var shortcutsGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Quick shortcuts").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                shortcutButton("⌘C", key: .c, mods: [.command])
                shortcutButton("⌘V", key: .v, mods: [.command])
                shortcutButton("⌘X", key: .x, mods: [.command])
                shortcutButton("⌘Z", key: .z, mods: [.command])
                shortcutButton("⌘⇧Z", key: .z, mods: [.command, .shift])
                shortcutButton("⌘A", key: .a, mods: [.command])
                shortcutButton("⌘S", key: .s, mods: [.command])
                shortcutButton("⌘F", key: .f, mods: [.command])
                shortcutButton("⌘W", key: .w, mods: [.command])
                shortcutButton("⌘Q", key: .q, mods: [.command])
                shortcutButton("⌘Tab", key: .tab, mods: [.command])
                shortcutButton("⌘Space", key: .space, mods: [.command])
            }
        }
    }

    // MARK: - helpers

    private func modifierButton(label: String, on: Binding<Bool>) -> some View {
        Button {
            Haptic.soft()
            on.wrappedValue.toggle()
        } label: {
            Text(label)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(on.wrappedValue ? Color.accentColor.opacity(0.25) : Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(on.wrappedValue ? Color.accentColor : Color.primary.opacity(0.10),
                                lineWidth: on.wrappedValue ? 1.5 : 0.6)
                )
        }
        .buttonStyle(PressableGlassStyle())
    }

    private func keyButton(_ label: String, icon: String, key: XRKey) -> some View {
        Button {
            Haptic.tap()
            sendKey(key)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.body)
                Text(label).font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.6)
            )
        }
        .buttonStyle(PressableGlassStyle())
    }

    private func shortcutButton(_ label: String, key: XRKey, mods: XRModifiers) -> some View {
        Button {
            Haptic.tap()
            client.send(.keyTap(key, modifiers: mods))
        } label: {
            Text(label)
                .font(.callout)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 0.6)
                )
        }
        .buttonStyle(PressableGlassStyle())
    }

    private func sendKey(_ key: XRKey) {
        client.send(.keyTap(key, modifiers: currentModifiers))
    }

    private var currentModifiers: XRModifiers {
        var m: XRModifiers = []
        if shift { m.insert(.shift) }
        if control { m.insert(.control) }
        if option { m.insert(.option) }
        if command { m.insert(.command) }
        return m
    }

    /// Forward only what changed in the TextField between updates. Handles
    /// backspaces, autocorrect replacements, and bulk paste.
    private func forwardDifference(from old: String, to new: String) {
        let oldChars = Array(old)
        let newChars = Array(new)
        var i = 0
        while i < oldChars.count && i < newChars.count && oldChars[i] == newChars[i] {
            i += 1
        }
        let deleted = oldChars.count - i
        let added = String(newChars[i..<newChars.count])

        for _ in 0..<deleted {
            client.send(.keyTap(.delete, modifiers: []))
        }
        if !added.isEmpty {
            client.send(.text(added))
        }
    }

    /// Returns the chars appended at the end of `new` relative to `old`,
    /// or "" if the change wasn't a pure append (deletion / replacement).
    private func addedChars(from old: String, to new: String) -> String {
        let oldChars = Array(old)
        let newChars = Array(new)
        guard newChars.count > oldChars.count else { return "" }
        var i = 0
        while i < oldChars.count && i < newChars.count && oldChars[i] == newChars[i] {
            i += 1
        }
        if oldChars.count != i { return "" }
        return String(newChars[i..<newChars.count])
    }
}

#endif
