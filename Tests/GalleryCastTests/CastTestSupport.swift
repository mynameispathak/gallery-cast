import Foundation
import Network
import Testing
@testable import GalleryCast

// MARK: - Async polling

/// Polls `condition` until it holds or `timeout` elapses.
func waitUntil(
    timeout: TimeInterval = 5,
    _ condition: @escaping @MainActor () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(25))
    }
    return await condition()
}

// MARK: - Fixtures

/// Creates a temporary folder holding tiny fake JPEG payloads.
func makePhotoFolder(_ names: [String]) throws -> (folder: URL, payloads: [String: Data]) {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("gc-cast-fixture-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    var payloads: [String: Data] = [:]
    for name in names {
        let payload = Data("cast-fixture-\(name)".utf8)
        try payload.write(to: folder.appendingPathComponent(name))
        payloads[name] = payload
    }
    return (folder, payloads)
}

// MARK: - Fake CASTV2 receiver

/// A loopback CASTV2 receiver for tests: accepts connections, decodes
/// every CastMessage sent to it, and can push canned replies. All
/// mutable state lives on `queue`.
final class FakeCastReceiver: @unchecked Sendable {

    private let queue = DispatchQueue(label: "gallerycast-tests.fake-receiver")
    private var listener: NWListener?
    private var connection: NWConnection?
    private var buffer = Data()
    private var messages: [CastMessage] = []

    private(set) var port: UInt16 = 0

    func start() throws {
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.queue.async { self.accept(connection) }
        }
        listener.start(queue: queue)
        self.listener = listener

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, listener.state != .ready {
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard case .ready = listener.state,
              let port = listener.port?.rawValue, port > 0
        else {
            throw NSError(
                domain: "FakeCastReceiver", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "fake receiver failed to bind"]
            )
        }
        self.port = port
    }

    /// A snapshot of every message received so far.
    func received() -> [CastMessage] {
        queue.sync { messages }
    }

    /// Pushes a message to the most recently connected client.
    func send(_ message: CastMessage) {
        queue.async { [weak self] in
            self?.connection?.send(
                content: message.encoded(),
                completion: .contentProcessed { _ in }
            )
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.connection?.cancel()
            self?.listener?.cancel()
        }
    }

    private func accept(_ connection: NWConnection) {
        self.connection = connection
        connection.start(queue: queue)
        receiveNext(on: connection)
    }

    private func receiveNext(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.messages.append(contentsOf: CastMessage.decodeFrames(from: &self.buffer))
            }
            if error == nil {
                self.receiveNext(on: connection)
            }
        }
    }
}
