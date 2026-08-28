//
//  ServerBrowser.swift
//  Discovers Xremote Server instances on the local network using NWBrowser.
//

#if os(iOS)

import Foundation
import Network
import Observation

struct DiscoveredServer: Identifiable, Hashable {
    let id: String        // endpoint description, stable for a given service instance
    let name: String
    let endpoint: NWEndpoint
}

@MainActor
@Observable
final class ServerBrowser {
    private(set) var servers: [DiscoveredServer] = []
    private(set) var isBrowsing: Bool = false
    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let descriptor = NWBrowser.Descriptor.bonjour(type: XRProtocol.serviceType, domain: nil)
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: descriptor, using: params)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                if case .ready = state { self.isBrowsing = true }
                if case .failed = state { self.isBrowsing = false }
                if case .cancelled = state { self.isBrowsing = false }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self else { return }
                self.servers = results.compactMap { result in
                    if case let .service(name, _, _, _) = result.endpoint {
                        return DiscoveredServer(id: name, name: name, endpoint: result.endpoint)
                    }
                    return nil
                }.sorted { $0.name < $1.name }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        servers.removeAll()
        isBrowsing = false
    }
}

#endif
