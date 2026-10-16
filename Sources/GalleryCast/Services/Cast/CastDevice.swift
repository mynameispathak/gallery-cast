import Foundation
import Network

/// A Cast device found on the local network.
struct CastDevice: Identifiable, Hashable, Sendable {

    /// The Bonjour service instance name — Cast devices name it after
    /// their user-chosen device name ("Living Room TV").
    var name: String

    /// What to connect to: the Bonjour endpoint from browsing, or an
    /// explicit host:port (tests and direct entry).
    var endpoint: NWEndpoint

    var id: String { "\(name)|\(endpointDescription)" }

    private var endpointDescription: String {
        switch endpoint {
        case .service(let name, let type, let domain, let interface):
            return "service:\(name).\(type).\(domain)#\(interface?.index ?? 0)"
        case .hostPort(let host, let port):
            return "host:\(host):\(port.rawValue)"
        default:
            return "other"
        }
    }
}
