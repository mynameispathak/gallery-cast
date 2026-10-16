import Foundation
import Network
import Observation

/// Browses the local network for Cast devices (`_googlecast._tcp`).
///
/// Network.framework exposes the Bonjour service name but not the TXT
/// records, so the name shown is the instance name — which on Cast
/// devices is the user-chosen name anyway.
@MainActor
@Observable
final class CastDiscoveryService: @unchecked Sendable {

    private(set) var devices: [CastDevice] = []
    private(set) var isBrowsing = false
    private(set) var lastError: String?

    private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }

        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(
            for: .bonjour(type: "_googlecast._tcp", domain: nil),
            using: parameters
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let endpoints = results.map(\.endpoint)
            Task { @MainActor in
                self?.devices = Self.devices(from: endpoints)
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleBrowserState(state)
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        devices = []
        isBrowsing = false
    }

    private func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            isBrowsing = true
            lastError = nil
        case .failed(let error):
            isBrowsing = false
            lastError = error.localizedDescription
            stop()
        default:
            break
        }
    }

    /// Maps browse endpoints to devices, sorted by name for stable menus.
    nonisolated static func devices(from endpoints: [NWEndpoint]) -> [CastDevice] {
        endpoints.compactMap { endpoint in
            guard case let .service(name, _, _, _) = endpoint else { return nil }
            return CastDevice(name: name, endpoint: endpoint)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
