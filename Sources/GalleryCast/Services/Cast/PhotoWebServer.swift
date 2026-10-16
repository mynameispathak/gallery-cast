import Foundation
import Network

/// Serves the open folder's photos over plain HTTP so a Cast receiver on
/// the LAN can fetch them. GET only, one request per connection, no
/// listing, no traversal; refuses anything that is not a direct child of
/// the served folder. Runs only while a cast session is live.
///
/// The served folder is fixed for the lifetime of the server (switching
/// folders means a new server), so connection handlers capture an
/// immutable context instead of shared mutable state. All handler state
/// lives on the file-scoped serial queue.
@MainActor
final class PhotoWebServer {

    private(set) var port: UInt16?
    private var listener: NWListener?

    /// Starts serving `folder` on an ephemeral port on all interfaces
    /// and waits for the bind to complete.
    @discardableResult
    func start(folder: URL) async throws -> UInt16 {
        stop()

        let context = ServeContext(folder: folder)
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { connection in
            ConnectionServing(
                connection: connection,
                context: context,
                queue: photoServeQueue
            ).start()
        }
        listener.start(queue: photoServeQueue)
        self.listener = listener

        // Bind is effectively instant; poll briefly for the assigned port.
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            switch listener.state {
            case .ready:
                guard let port = listener.port?.rawValue, port > 0 else {
                    try? await Task.sleep(for: .milliseconds(20))
                    continue
                }
                self.port = port
                return port
            case .failed(let error):
                self.listener = nil
                throw error
            default:
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        self.listener = nil
        listener.cancel()
        throw PhotoWebServerError.bindTimeout
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = nil
    }

    /// The URL a receiver should fetch a photo from.
    func url(for photo: Photo, host: String) -> URL? {
        guard let port else { return nil }
        return Self.url(for: photo.filename, host: host, port: port)
    }

    nonisolated static func url(for filename: String, host: String, port: UInt16) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = Int(port)
        // RFC 3986 unreserved characters stay literal; everything else
        // is escaped so spaces and quotes survive the round trip.
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-._~")
        )
        components.percentEncodedPath =
            "/" + (filename.addingPercentEncoding(withAllowedCharacters: allowed) ?? filename)
        return components.url
    }

    nonisolated static func contentType(forExtension fileExtension: String) -> String {
        switch fileExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "heic", "heif": return "image/heic"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        case "tif", "tiff": return "image/tiff"
        case "bmp": return "image/bmp"
        case "avif": return "image/avif"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Per-connection serving

/// Serves exactly one request on a connection, then closes it. Mutated
/// only on `queue`.
private final class ConnectionServing: @unchecked Sendable {
    private let connection: NWConnection
    private let context: ServeContext
    private let queue: DispatchQueue
    private var buffer = Data()

    init(connection: NWConnection, context: ServeContext, queue: DispatchQueue) {
        self.connection = connection
        self.context = context
        self.queue = queue
    }

    func start() {
        connection.start(queue: queue)
        receiveNext()
    }

    private func receiveNext() {
        // Strong self on purpose: this object owns the connection's
        // response cycle and must live until the connection cancels —
        // cancellation releases the pending completion and with it the
        // last reference. Nobody else holds a ConnectionServing alive.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
            if let data { self.buffer.append(data) }
            if error != nil {
                self.connection.cancel()
                return
            }

            if let requestLine = Self.requestLine(from: self.buffer) {
                let response = self.context.response(forRequestLine: requestLine)
                self.connection.send(content: response, completion: .contentProcessed { _ in
                    self.connection.cancel()
                })
            } else if isComplete || self.buffer.count > photoMaxRequestBytes {
                self.connection.cancel()
            } else {
                self.receiveNext()
            }
        }
    }

    /// The request line ("GET /path HTTP/1.1"), or nil while the header
    /// is still incomplete.
    private static func requestLine(from buffer: Data) -> String? {
        guard let range = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
        return String(data: head, encoding: .utf8)
    }
}

// MARK: - Responses

/// Wraps the served folder. Immutable, so connection handlers can hold
/// it freely.
private struct ServeContext: Sendable {
    let folder: URL

    func response(forRequestLine line: String) -> Data {
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET", let path = parts[1].split(separator: "?").first
        else {
            return PhotoWebServerResponse.badRequest
        }

        let name = String(path.dropFirst()).removingPercentEncoding
            ?? String(path.dropFirst())
        guard !name.isEmpty, !name.hasPrefix("."),
              !name.contains("/"), !name.contains("\\"), !name.contains("..")
        else {
            return PhotoWebServerResponse.forbidden
        }

        let fileURL = folder.appendingPathComponent(name)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let data = try? Data(contentsOf: fileURL)
        else {
            return PhotoWebServerResponse.notFound
        }

        let contentType = PhotoWebServer.contentType(forExtension: fileURL.pathExtension)
        return PhotoWebServerResponse.ok(contentType: contentType, body: data)
    }
}

private enum PhotoWebServerResponse {
    static func ok(contentType: String, body: Data) -> Data {
        httpResponse(status: "200 OK", contentType: contentType, body: body)
    }

    static let notFound = httpResponse(status: "404 Not Found", body: "Not found".data(using: .utf8)!)
    static let forbidden = httpResponse(status: "403 Forbidden", body: "Forbidden".data(using: .utf8)!)
    static let badRequest = httpResponse(status: "400 Bad Request", body: "Bad request".data(using: .utf8)!)

    private static func httpResponse(
        status: String,
        contentType: String = "text/plain; charset=utf-8",
        body: Data
    ) -> Data {
        let head = "HTTP/1.1 \(status)\r\n"
            + "Content-Type: \(contentType)\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: close\r\n"
            + "\r\n"
        var response = Data(head.utf8)
        response.append(body)
        return response
    }
}

// MARK: - Constants

private let photoServeQueue = DispatchQueue(label: "gallerycast.photo-server")

/// Request headers are a few dozen bytes; far more means abuse.
private let photoMaxRequestBytes = 16 * 1024

enum PhotoWebServerError: LocalizedError {
    case bindTimeout

    var errorDescription: String? {
        switch self {
        case .bindTimeout: return "The photo server could not bind a port."
        }
    }
}
