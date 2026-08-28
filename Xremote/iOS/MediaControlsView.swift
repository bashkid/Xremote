//
//  MediaControlsView.swift
//

#if os(iOS)

import SwiftUI

struct MediaControlsView: View {
    @Bindable var client: XremoteClient

    private let fKeys: [XRKey] = [
        .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10, .f11, .f12
    ]

    // Sticky modifier toggles. They apply to any F-key press below.
    @State private var shift = false
    @State private var control = false
    @State private var option = false
    @State private var command = false

    // Volume slider state. macOS volume is discrete (16 steps), so we
    // translate slider position changes into the appropriate number of
    // vol-up / vol-down media-key presses.
    @State private var volume: Double = 0.5
    @State private var lastSentStep: Int = 8

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                playbackSection
                volumeSection
                functionKeysSection
            }
            .padding()
        }
    }

    // MARK: - Sections

    private var playbackSection: some View {
        VStack(spacing: 14) {
            sectionTitle("Playback")
            HStack(spacing: 22) {
                circleButton(icon: "backward.fill") { client.send(.mediaKey(.previous)) }
                circleButton(icon: "playpause.fill", size: 86) { client.send(.mediaKey(.playPause)) }
                circleButton(icon: "forward.fill") { client.send(.mediaKey(.next)) }
            }
        }
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Volume")
            HStack(spacing: 12) {
                Button {
                    Haptic.soft()
                    client.send(.mediaKey(.mute))
                } label: {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableGlassStyle())

                Slider(value: $volume, in: 0...1)
                    .tint(.accentColor)
                    .onChange(of: volume) { _, newValue in
                        applyVolumeDelta(to: newValue)
                    }

                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
        }
    }

    private func applyVolumeDelta(to newValue: Double) {
        let newStep = Int(round(newValue * 16))
        let delta = newStep - lastSentStep
        guard delta != 0 else { return }
        let key: XRMediaKey = delta > 0 ? .volumeUp : .volumeDown
        for _ in 0..<abs(delta) {
            client.send(.mediaKey(key))
        }
        lastSentStep = newStep
    }

    private var functionKeysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Function keys")

            HStack(spacing: 8) {
                modifierToggle(label: "⇧", on: $shift)
                modifierToggle(label: "⌃", on: $control)
                modifierToggle(label: "⌥", on: $option)
                modifierToggle(label: "⌘", on: $command)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(0..<fKeys.count, id: \.self) { i in
                    fKeyButton(label: "F\(i + 1)", key: fKeys[i])
                }
            }
        }
    }

    // MARK: - Building blocks

    private func sectionTitle(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func circleButton(icon: String, size: CGFloat = 70, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: size * 0.38, weight: .semibold))
                .frame(width: size, height: size)
                .background(
                    Circle().fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    Circle().stroke(Color.primary.opacity(0.10), lineWidth: 0.6)
                )
        }
        .buttonStyle(PressableGlassStyle())
    }

    private func modifierToggle(label: String, on: Binding<Bool>) -> some View {
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

    private func fKeyButton(label: String, key: XRKey) -> some View {
        Button {
            Haptic.soft()
            client.send(.keyTap(key, modifiers: currentModifiers))
        } label: {
            Text(label)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
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

    private var currentModifiers: XRModifiers {
        var m: XRModifiers = []
        if shift   { m.insert(.shift) }
        if control { m.insert(.control) }
        if option  { m.insert(.option) }
        if command { m.insert(.command) }
        return m
    }
}

#endif
