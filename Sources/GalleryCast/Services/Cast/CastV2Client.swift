import Foundation
import Network
import Security

/// One socket to a Cast device: TLS (plain TCP in tests), CASTV2 frame
/// handling, and the heartbeat reflex that keeps the connection alive.
/// Protocol *semantics* — what to send, and when — live one layer up in
/// `CastSessionController`.
///
/// Mutable state lives on `queue`; callers may touch the instance from
/// any isolation domain but must set the callbacks before `start()`.
final class CastV2Client: @unchecked Sendable {

    enum State: Sendable {
        case ready(remoteIPv4: String?)
        case failed(String)
        case cancelled
    }

    /// Inbound messages, on the client's queue. Heartbeat PINGs never
    /// arrive here — they are answered by reflex inside the client.
    var onMessage: (@Sendable (CastMessage) -> Void)?
    var onStateChange: (@Sendable (State) -> Void)?

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "gallerycast.castv2")
    private let buffer = MessageBuffer()

    /// - Parameters:
    ///   - endpoint: device to connect to (Bonjour service or host:port).
    ///   - useTLS: production CASTV2 is TLS; tests use plain TCP against
    ///     a loopback receiver.
    init(endpoint: NWEndpoint, useTLS: Bool = true) {
        let parameters: NWParameters
        if useTLS {
            let tls = NWProtocolTLS.Options()
            // Cast devices identify with self-signed certificates; the
            // protocol's security model is the LAN, not a cert chain.
            sec_protocol_options_set_verify_block(
                tls.securityProtocolOptions,
                { _, _, complete in complete(true) },
                queue
            )
            parameters = NWParameters(tls: tls)
        } else {
            parameters = NWParameters.tcp
        }
        connection = NWConnection(to: endpoint, using: parameters)
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.onStateChange?(.ready(remoteIPv4: self.remoteIPv4()))
                self.receiveNext()
            case .failed(let error):
                self.onStateChange?(.failed(error.localizedDescription))
            case .cancelled:
                self.onStateChange?(.cancelled)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func stop() {
        connection.cancel()
    }

    func send(_ message: CastMessage) {
        connection.send(content: message.encoded(), completion: .contentProcessed { _ in })
    }

    // MARK: Receive loop

    private func receiveNext() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.data.append(data)
                for message in CastMessage.decodeFrames(from: &self.buffer.data) {
                    self.handle(message)
                }
            }
            if let error {
                self.onStateChange?(.failed(error.localizedDescription))
            } else {
                self.receiveNext()
            }
        }
    }

    private func handle(_ message: CastMessage) {
        // Heartbeat reflex: the wire stays alive without any higher
        // layer knowing about it.
        if message.namespace == CastNamespace.heartbeat,
           CastPayloads.messageType(of: message.payloadString ?? "") == "PING" {
            send(CastMessage(
                sourceID: message.destinationID,
                destinationID: message.sourceID,
                namespace: CastNamespace.heartbeat,
                payloadJSON: CastPayloads.pong()
            ))
            return
        }
        onMessage?(message)
    }

    private func remoteIPv4() -> String? {
        guard case .hostPort(let host, _) = connection.currentPath?.remoteEndpoint,
              case .ipv4(let address) = host
        else { return nil }
        return "\(address)"
    }
}

/// Receive-buffer cell. Mutated only on the client's serial queue.
private final class MessageBuffer: @unchecked Sendable {
    var data = Data()
}
