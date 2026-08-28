//
//  RemoteTabsView.swift
//  Tab host shown after a successful pairing.
//

#if os(iOS)

import SwiftUI

struct RemoteTabsView: View {
    @Bindable var client: XremoteClient

    var body: some View {
        TabView {
            tab(title: "Touchpad") { TouchpadView(client: client) }
                .tabItem { Label("Touchpad", systemImage: "hand.draw") }

            tab(title: "Keyboard") { KeyboardView(client: client) }
                .tabItem { Label("Keyboard", systemImage: "keyboard") }

            tab(title: "Media") { MediaControlsView(client: client) }
                .tabItem { Label("Media", systemImage: "play.rectangle") }

            tab(title: "Slides") { PresentationView(client: client) }
                .tabItem { Label("Slides", systemImage: "rectangle.on.rectangle") }

            // The Voice tab already has its own mic experience — skip the
            // floating button there to avoid two mic affordances on top of
            // each other.
            tab(title: "Voice", showFloatingVoiceButton: false) {
                VoiceView(client: client)
            }
            .tabItem { Label("Voice", systemImage: "mic.fill") }

            tab(title: "Files") { FilesBrowserView(client: client) }
                .tabItem { Label("Files", systemImage: "folder.fill") }
        }
    }

    /// Wraps a tab in a NavigationStack with the shared toolbar (theme
    /// toggle + disconnect) and the aurora glow behind the nav bar.
    /// Pass `showFloatingVoiceButton: false` for the Voice tab so the
    /// app-wide mic-anywhere capsule doesn't duplicate the in-tab mic.
    @ViewBuilder
    private func tab<Content: View>(
        title: String,
        showFloatingVoiceButton: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        NavigationStack {
            ZStack(alignment: .top) {
                NavBarGlowBackground()
                content()
            }
            .overlay {
                // Full-area overlay so the draggable FloatingVoiceButton's
                // internal GeometryReader gets the entire content area to
                // roam in — not just the bottom-trailing corner.
                if showFloatingVoiceButton {
                    FloatingVoiceButton(client: client)
                        .allowsHitTesting(true)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            // Force the Liquid Glass background of the nav bar to stay
            // visible — iOS 26 hides it by default when there's no
            // scroll content underneath.
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ThemeToggleButton()
                }
                ToolbarItem(placement: .principal) {
                    Text(title.uppercased())
                        .font(.headline.weight(.bold))
                        .tracking(2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Red disconnect icon — explicit disconnect forgets the
                    // server so auto-reconnect on foreground won't undo it.
                    Button {
                        Haptic.tap()
                        client.forgetAndDisconnect()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                            .font(.title3)
                    }
                    .accessibilityLabel("Disconnect")
                }
            }
        }
    }
}

#endif
