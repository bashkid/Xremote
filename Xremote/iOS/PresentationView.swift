//
//  PresentationView.swift
//  Keynote / PowerPoint / Google Slides remote, styled after a dark/purple
//  presentation-remote aesthetic.
//

#if os(iOS)

import SwiftUI

struct PresentationView: View {
    @Bindable var client: XremoteClient

    @State private var slideNumber: Int = 1
    @State private var isPresenting: Bool = false
    @State private var blackScreenActive: Bool = false
    @State private var elapsed: TimeInterval = 0
    @State private var timer: Timer?
    @State private var showingLaser: Bool = false

    private let accent = Color(red: 0.49, green: 0.27, blue: 0.99)  // ~#7C45FD
    private let cardFill = Color(red: 0.10, green: 0.10, blue: 0.13)
    private let cardStroke = Color.white.opacity(0.06)

    var body: some View {
        // No forced solid-black background — we let the page inherit the
        // same backdrop as the other tabs (system dark + the nav-bar
        // chromatic glow). `preferredColorScheme(.dark)` keeps the
        // cinematic feel: text stays white-on-dark, the system background
        // is near-black so the glow at top transitions smoothly into the
        // content area below (no hard horizontal edge).
        VStack(spacing: 22) {
            header
            slideCounter
            slidePreviewCard
            controlRow
            secondaryRow
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showingLaser) {
            LaserPointerStage(isActive: $showingLaser, client: client)
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Active Presentation")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(client.serverName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Circle()
                .fill(isPresenting ? .red : .white.opacity(0.2))
                .frame(width: 10, height: 10)
        }
    }

    private var slideCounter: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Text("\(slideNumber)")
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("/ slide")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.bottom, 12)
            Spacer()
            timerPill
        }
    }

    private var timerPill: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.fill")
                .font(.caption2)
            Text(timeString(elapsed))
                .font(.system(.callout, design: .monospaced).weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(accent.opacity(isPresenting ? 0.9 : 0.25))
        .clipShape(Capsule())
    }

    private var slidePreviewCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(cardStroke, lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Slide \(slideNumber)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.08))
                        .clipShape(Capsule())
                    Spacer()
                    if blackScreenActive {
                        Label("Blacked out", systemImage: "moon.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                if blackScreenActive {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Screen blacked out")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Tap Black again to resume the slide on \(client.serverName).")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Presentation")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Tap the arrows to step through slides. Play starts the slideshow on your Mac.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(2)
                    }
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }

    private var controlRow: some View {
        HStack(spacing: 22) {
            sideButton(systemName: "chevron.left") { previous() }
            playButton
            sideButton(systemName: "chevron.right") { next() }
        }
        .frame(maxWidth: .infinity)
    }

    private var playButton: some View {
        Button {
            Haptic.tap()
            togglePlay()
        } label: {
            ZStack {
                Circle()
                    .fill(accent)
                    .shadow(color: accent.opacity(0.5), radius: 18, x: 0, y: 8)
                Image(systemName: isPresenting ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: isPresenting ? 0 : 2)
            }
            .frame(width: 86, height: 86)
        }
        .buttonStyle(PressableGlassStyle())
    }

    private func sideButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 64, height: 64)
                .background(.white)
                .clipShape(Circle())
        }
        .buttonStyle(PressableGlassStyle())
    }

    private var secondaryRow: some View {
        HStack(spacing: 12) {
            chip(label: blackScreenActive ? "Resume" : "Black",
                 icon: "moon.fill",
                 isActive: blackScreenActive) {
                toggleBlack()
            }
            chip(label: "Laser", icon: "scope") {
                showingLaser = true
            }
            chip(label: "End", icon: "xmark") {
                end()
            }
        }
    }

    private func chip(label: String, icon: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(label)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isActive ? .white : .white.opacity(0.8))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isActive ? accent : Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(PressableGlassStyle())
    }

    // MARK: - Actions

    private func previous() {
        client.send(.keyTap(.leftArrow))
        if slideNumber > 1 { slideNumber -= 1 }
    }

    private func next() {
        client.send(.keyTap(.rightArrow))
        slideNumber += 1
    }

    private func togglePlay() {
        if isPresenting {
            // Space toggles play/pause in an already-running slideshow.
            client.send(.keyTap(.space))
            stopTimer()
            isPresenting = false
        } else {
            // Shift+F5 = "Play from current slide" in PowerPoint, Google
            // Slides, LibreOffice Impress, etc. Lets the user jump to a
            // slide on the Mac and resume from there instead of restarting
            // from slide 1. For Keynote, start the slideshow manually on
            // the Mac, then use this remote for next / previous / black / end.
            client.send(.keyTap(.f5, modifiers: [.shift]))
            startTimer()
            isPresenting = true
        }
    }

    private func toggleBlack() {
        client.send(.keyTap(.b))
        blackScreenActive.toggle()
    }

    private func end() {
        client.send(.keyTap(.escape))
        stopTimer()
        isPresenting = false
        blackScreenActive = false
    }

    // MARK: - Timer

    private func startTimer() {
        elapsed = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsed += 1
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func timeString(_ t: TimeInterval) -> String {
        let total = Int(t)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

#endif
