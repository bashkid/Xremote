//
//  XremoteApp.swift
//

import SwiftUI

#if os(iOS)

@main
struct XremoteApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

#elseif os(macOS)

import AppKit

@main
struct XremoteApp: App {
    @NSApplicationDelegateAdaptor(ServerAppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings is a scene that doesn't create a visible window for LSUIElement
        // apps, which keeps Xremote Server menu-bar-only.
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class ServerAppDelegate: NSObject, NSApplicationDelegate {
    private let pairing = PairingManager()
    private lazy var server = XremoteServer(pairing: pairing)
    private let accessibility = AccessibilityChecker()
    private var menuBar: MenuBarController?
    private var taskDashboard: TaskDashboardWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        accessibility.start()
        if !accessibility.isTrusted {
            accessibility.requestPermission()
        }
        let dashboard = TaskDashboardWindowController(server: server)
        let menuBar = MenuBarController(
            server: server,
            accessibility: accessibility,
            taskDashboard: dashboard
        )
        menuBar.install()
        self.taskDashboard = dashboard
        self.menuBar = menuBar
        server.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        server.stop()
        accessibility.stop()
    }
}

#endif
