//
//  MenuBarController.swift
//  Sets up the NSStatusItem and a popover containing ServerStatusView.
//

#if os(macOS)

import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let server: XremoteServer
    private let accessibility: AccessibilityChecker
    private let taskDashboard: TaskDashboardWindowController

    init(server: XremoteServer,
         accessibility: AccessibilityChecker,
         taskDashboard: TaskDashboardWindowController) {
        self.server = server
        self.accessibility = accessibility
        self.taskDashboard = taskDashboard
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "keyboard.fill", accessibilityDescription: "Xremote Server")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        statusItem = item

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 560)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: ServerStatusView(
                server: server,
                accessibility: accessibility,
                onOpenTaskDetail: { [weak self] taskId in
                    self?.taskDashboard.show(selecting: taskId)
                    self?.popover?.performClose(nil)
                }
            )
        )
        self.popover = popover
    }

    @objc private func togglePopover(_ sender: AnyObject) {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

#endif
