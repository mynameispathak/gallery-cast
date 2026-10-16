import Foundation

/// Namespaces of the CASTV2 protocol. Every message travels on exactly one.
enum CastNamespace {
    static let connection = "urn:x-cast:com.google.cast.tp.connection"
    static let heartbeat = "urn:x-cast:com.google.cast.tp.heartbeat"
    static let receiver = "urn:x-cast:com.google.cast.receiver"
    static let media = "urn:x-cast:com.google.cast.media"
}

/// One CASTV2 envelope (`google_cast.proto`): a source, a destination, a
/// namespace, and a single payload — string (JSON) or binary.
///
/// On the wire each message is a 4-byte big-endian length prefix followed
/// by the protobuf body below. The codec is hand-rolled for this one
/// message type, which keeps the app's zero-dependency build intact.
struct CastMessage: Equatable, Sendable {

    enum Payload: Equatable, Sendable {
        case string(String)
        case binary(Data)
    }

    var sourceID: String
    var destinationID: String
    var namespace: String
    var payload: Payload

    var payloadString: String? {
        if case .string(let value) = payload { return value }
        return nil
    }

    init(sourceID: String, destinationID: String, namespace: String, payload: Payload) {
        self.sourceID = sourceID
        self.destinationID = destinationID
        self.namespace = namespace
        self.payload = payload
    }

    /// Convenience for the common case: a JSON payload.
    init(sourceID: String, destinationID: String, namespace: String, payloadJSON: String) {
        self.init(
            sourceID: sourceID,
            destinationID: destinationID,
            namespace: namespace,
            payload: .string(payloadJSON)
        )
    }

    // MARK: Wire format

    /// A serialized, length-prefixed frame, ready to send over the socket.
    func encoded() -> Data {
        let body = protobufSerialized()
        var frame = Data(capacity: 4 + body.count)
        withUnsafeBytes(of: UInt32(body.count).bigEndian) { frame.append(contentsOf: $0) }
        frame.append(body)
        return frame
    }

    /// Removes every complete frame from the front of `buffer` and decodes
    /// it. A trailing partial frame stays in the buffer for the next chunk.
    ///
    /// A length that is zero or absurdly large, or a frame that fails to
    /// decode, stops the scan: after a desync the rest of the stream is
    /// not trustworthy, and the caller is expected to drop the connection.
    static func decodeFrames(from buffer: inout Data) -> [CastMessage] {
        let bytes = [UInt8](buffer)
        var messages: [CastMessage] = []
        var offset = 0

        while bytes.count - offset >= 4 {
            let length = UInt32(bytes[offset]) << 24
                | UInt32(bytes[offset + 1]) << 16
                | UInt32(bytes[offset + 2]) << 8
                | UInt32(bytes[offset + 3])
            guard length > 0, length <= Self.maxFrameBytes else { break }
            let frameEnd = offset + 4 + Int(length)
            guard bytes.count >= frameEnd else { break }
            let body = Data(bytes[(offset + 4)..<frameEnd])
            guard let message = Self.protobufDecoded(from: body) else { break }
            messages.append(message)
            offset = frameEnd
        }

        buffer = Data(bytes[offset...])
        return messages
    }

    /// Cast control frames are tiny; anything larger means a desync.
    private static let maxFrameBytes: UInt32 = 2 * 1024 * 1024

    // MARK: Protobuf body

    private func protobufSerialized() -> Data {
        var writer = ProtoWriter()

        writer.appendVarint(field: 1, value: 0) // protocol_version = CASTV2_1_0
        writer.appendString(field: 2, value: sourceID)
        writer.appendString(field: 3, value: destinationID)
        writer.appendString(field: 4, value: namespace)
        writer.appendVarint(field: 5, value: isBinaryPayload ? 1 : 0) // payload_type
        switch payload {
        case .string(let value):
            writer.appendString(field: 6, value: value)
        case .binary(let value):
            writer.appendBytes(field: 7, value: value)
        }
        return writer.data
    }

    private var isBinaryPayload: Bool {
        if case .binary = payload { return true }
        return false
    }

    private static func protobufDecoded(from data: Data) -> CastMessage? {
        let bytes = [UInt8](data)
        var index = 0

        func readVarint() -> UInt64? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
                if shift >= 64 { return nil }
            }
            return nil
        }

        func readLengthDelimited() -> Data? {
            guard let length = readVarint(),
                  length <= UInt64(bytes.count - index)
            else { return nil }
            let end = index + Int(length)
            defer { index = end }
            return Data(bytes[index..<end])
        }

        /// Unknown fields are skipped, per protobuf forward-compatibility.
        func skip(wireType: UInt64) -> Bool {
            switch wireType {
            case 0: return readVarint() != nil
            case 1: guard bytes.count - index >= 8 else { return false }; index += 8; return true
            case 2: return readLengthDelimited() != nil
            case 5: guard bytes.count - index >= 4 else { return false }; index += 4; return true
            default: return false
            }
        }

        var sourceID: String?
        var destinationID: String?
        var namespace: String?
        var payloadType: UInt64 = 0
        var utf8: String?
        var binary: Data?

        while index < bytes.count {
            guard let key = readVarint() else { return nil }
            let field = key >> 3
            let wireType = key & 0x7

            switch (field, wireType) {
            case (1, 0):
                _ = readVarint() // protocol_version; only CASTV2_1_0 exists
            case (2, 2):
                guard let raw = readLengthDelimited(), let value = String(data: raw, encoding: .utf8)
                else { return nil }
                sourceID = value
            case (3, 2):
                guard let raw = readLengthDelimited(), let value = String(data: raw, encoding: .utf8)
                else { return nil }
                destinationID = value
            case (4, 2):
                guard let raw = readLengthDelimited(), let value = String(data: raw, encoding: .utf8)
                else { return nil }
                namespace = value
            case (5, 0):
                guard let value = readVarint() else { return nil }
                payloadType = value
            case (6, 2):
                guard let raw = readLengthDelimited(), let value = String(data: raw, encoding: .utf8)
                else { return nil }
                utf8 = value
            case (7, 2):
                guard let value = readLengthDelimited() else { return nil }
                binary = value
            default:
                guard skip(wireType: wireType) else { return nil }
            }
        }

        guard let sourceID, let destinationID, let namespace else { return nil }
        let payload: Payload = payloadType == 1
            ? .binary(binary ?? Data())
            : .string(utf8 ?? "")
        return CastMessage(
            sourceID: sourceID,
            destinationID: destinationID,
            namespace: namespace,
            payload: payload
        )
    }
}

/// Minimal protobuf writer — just enough for `CastMessage`.
private struct ProtoWriter {
    private(set) var data = Data()

    mutating func appendVarint(field: UInt32, value: UInt64) {
        appendTag(field, wireType: 0)
        appendVarint(value)
    }

    mutating func appendString(field: UInt32, value: String) {
        appendBytes(field: field, value: Data(value.utf8))
    }

    mutating func appendBytes(field: UInt32, value: Data) {
        appendTag(field, wireType: 2)
        appendVarint(UInt64(value.count))
        data.append(value)
    }

    private mutating func appendTag(_ field: UInt32, wireType: UInt32) {
        appendVarint(UInt64(field << 3 | wireType))
    }

    private mutating func appendVarint(_ value: UInt64) {
        var remainder = value
        repeat {
            var byte = UInt8(remainder & 0x7F)
            remainder >>= 7
            if remainder != 0 { byte |= 0x80 }
            data.append(byte)
        } while remainder != 0
    }
}
