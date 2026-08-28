//
//  RootView.swift
//  Switches between the discovery list and the remote tabs based on
//  connection state. Owns the persisted theme preference and the
//  auto-reconnect behavior.
//

#if os(iOS)

import SwiftUI

struct RootView: View {
    @State private var browser = ServerBrowser()
    @State private var client = XremoteClient()
    @State private var fileClient: FileTransferClient? = nil
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("XRAppTheme") private var storedTheme: String = AppTheme.system.rawValue

    private var theme: AppTheme {
        AppTheme(rawValue: storedTheme) ?? .system
    }

    var body: some View {
        Group {
            if case .connected = client.state {
                RemoteTabsView(client: client)
            } else {
                ConnectView(browser: browser, client: client)
            }
        }
        .preferredColorScheme(theme.colorScheme)
        .animation(.default, value: isConnected)
        .onAppear {
            // Wire the file-transfer client at startup so inbound packets
            // can be routed straight into it.
            if fileClient == nil {
                let fc = FileTransferClient(client: client)
                fileClient = fc
                client.fileClient = fc
            }
            browser.start()
            tryAutoReconnect()
        }
        // Re-attempt auto-reconnect whenever a new server appears in the
        // discovery list (covers cold launch + lock/unlock).
        .onChange(of: browser.servers) { _, _ in
            tryAutoReconnect()
        }
        // iOS suspends background sockets; whenever we come back to the
        // foreground we restart browsing and try to reconnect transparently.
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                browser.start()
                tryAutoReconnect()
            case .background:
                // Let the OS reclaim resources; we'll reconnect on .active.
                break
            default:
                break
            }
        }
    }

    private var isConnected: Bool {
        if case .connected = client.state { return true }
        return false
    }

    /// If we have a remembered server name and it's visible on the network
    /// right now — and we're not already trying to connect — silently
    /// reconnect. The server side will accept our stored device token
    /// without prompting for a PIN.
    private func tryAutoReconnect() {
        switch client.state {
        case .idle, .failed:
            break
        case .connecting, .awaitingPin, .connected:
            return
        }
        guard let last = client.lastConnectedServer,
              let match = browser.servers.first(where: { $0.name == last })
        else { return }
        client.connect(to: match)
    }
}

#endif
