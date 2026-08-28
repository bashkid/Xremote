//
//  LaserOverlayController.swift
//  Hosts a transparent, click-through, always-on-top NSPanel that covers
//  the main screen with a SwiftUI laser-pointer overlay. The iPhone
//  controls show / hide / move / click / style remotely.
//

#if os(macOS)

import AppKit
import SwiftUI
import Observation

@MainActor
@Observable
final class LaserViewModel {
    /// Cursor target in SwiftUI coordinates of the overlay panel
    /// (origin top-left). Bound to `LaserPointerOverlay`.
    var targetPoint: CGPoint = .zero
    var state: PointerState = .idle
    var style: PointerStyle = .pointingHand
    var isVisible: Bool = false

    /// Last smoothed gyro deltas — kept on the view model so the
    /// exponential-smoothing filter in `applyGyroDelta` retains state
    /// across packets without polluting any other call site.
    var smoothedDx: Double = 0
    var smoothedDy: Double = 0
}

@MainActor
final class LaserOverlayController {
    let viewModel = LaserViewModel()
    private var panel: NSPanel?
    private var clickResetTask: Task<Void, Never>?

    /// How aggressively iPhone touch deltas translate to Mac-screen deltas.
    private let sensitivity: CGFloat = 2.0

    // MARK: - Public API (called from XremoteServer dispatch)

    func show(style: PointerStyle?) {
        if let style { viewModel.style = style }
        ensurePanel()
        // Center the cursor on the main screen.
        if let screen = NSScreen.main {
            let f = screen.frame
            viewModel.targetPoint = CGPoint(x: f.width / 2, y: f.height / 2)
        }
        viewModel.state = .moving
        viewModel.isVisible = true
        panel?.orderFrontRegardless()
    }

    func hide() {
        viewModel.isVisible = false
        viewModel.state = .idle
        panel?.orderOut(nil)
    }

    func move(dx: CGFloat, dy: CGFloat) {
        guard viewModel.isVisible else { return }
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        var p = viewModel.targetPoint
        p.x = min(max(0, p.x + dx * sensitivity), frame.width)
        p.y = min(max(0, p.y + dy * sensitivity), frame.height)
        viewModel.targetPoint = p
        if viewModel.state != .moving { viewModel.state = .moving }
    }

    func click() {
        viewModel.state = .clicked
        clickResetTask?.cancel()
        clickResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            await MainActor.run {
                guard let self else { return }
                if self.viewModel.state == .clicked { self.viewModel.state = .idle }
            }
        }
    }

    func setStyle(_ style: PointerStyle) {
        viewModel.style = style
    }

    // MARK: - Panel setup

    private func ensurePanel() {
        guard panel == nil, let screen = NSScreen.main else { return }
        let p = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .screenSaver  // above normal windows + menu bar items
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.isMovable = false
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = true
        // Click-through: the entire screen still receives touches/clicks
        // as if the panel wasn't there.
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        p.contentView = NSHostingView(
            rootView: LaserHostView(viewModel: viewModel)
        )
        p.setFrame(screen.frame, display: false)
        self.panel = p
    }
}

/// Tiny adapter so we can pass the @Observable view model into the SwiftUI
/// overlay using @Bindable.
private struct LaserHostView: View {
    @Bindable var viewModel: LaserViewModel

    var body: some View {
        ZStack {
            // Fully-transparent backdrop so the panel is invisible except
            // for the cursor and trail.
            Color.clear
            if viewModel.isVisible {
                LaserPointerOverlay(
                    targetPoint: $viewModel.targetPoint,
                    state: $viewModel.state,
                    selectedStyle: $viewModel.style
                )
            }
        }
        .ignoresSafeArea()
    }
}

#endif
