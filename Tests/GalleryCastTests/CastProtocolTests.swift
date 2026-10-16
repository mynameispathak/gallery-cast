import Foundation
import Testing
@testable import GalleryCast

@Suite
struct CastProtocolTests {

    // MARK: Protobuf wire format

    /// Locks the byte-level encoding against `google_cast.proto`.
    @Test func protobufEncodingMatchesGoogleCastWireFormat() {
        let message = CastMessage(
            sourceID: "s",
            destinationID: "r",
            namespace: "n",
            payloadJSON: "x"
        )
        let frame = [UInt8](message.encoded())
        let expected: [UInt8] = [
            0x00, 0x00, 0x00, 0x10,        // length = 16
            0x08, 0x00,                     // protocol_version = CASTV2_1_0
            0x12, 0x01, 0x73,               // source_id = "s"
            0x1A, 0x01, 0x72,               // destination_id = "r"
            0x22, 0x01, 0x6E,               // namespace = "n"
            0x28, 0x00,                     // payload_type = STRING
            0x32, 0x01, 0x78,               // payload_utf8 = "x"
        ]
        #expect(frame == expected)
    }

    @Test func roundTripStringPayload() {
        let message = CastMessage(
            sourceID: "sender-0",
            destinationID: "receiver-0",
            namespace: CastNamespace.receiver,
            payloadJSON: #"{"type":"GET_STATUS","requestId":1}"#
        )
        var buffer = message.encoded()
        let decoded = CastMessage.decodeFrames(from: &buffer)
        #expect(decoded == [message])
        #expect(buffer.isEmpty)
    }

    @Test func roundTripBinaryPayload() {
        let message = CastMessage(
            sourceID: "sender-1",
            destinationID: "app-0",
            namespace: "urn:x-cast:test",
            payload: .binary(Data([0x00, 0xFF, 0x7F, 0x80]))
        )
        var buffer = message.encoded()
        let decoded = CastMessage.decodeFrames(from: &buffer)
        #expect(decoded == [message])
    }

    @Test func roundTripUnicodeContent() {
        let title = "Vacation 🏔 — Caféstraße"
        let message = CastMessage(
            sourceID: "sender-0",
            destinationID: "receiver-0",
            namespace: CastNamespace.media,
            payloadJSON: title
        )
        var buffer = message.encoded()
        let decoded = CastMessage.decodeFrames(from: &buffer)
        #expect(decoded.first?.payloadString == title)
    }

    // MARK: Frame handling

    @Test func encodedFrameCarriesBigEndianLengthPrefix() {
        let message = CastMessage(
            sourceID: "s", destinationID: "r",
            namespace: "urn:x-cast:test", payloadJSON: "{}"
        )
        let frame = [UInt8](message.encoded())
        let bodyLength = Int(frame[0]) << 24 | Int(frame[1]) << 16
            | Int(frame[2]) << 8 | Int(frame[3])
        #expect(bodyLength == frame.count - 4)
        #expect(bodyLength > 0)
    }

    @Test func decodeFramesSplitsTwoFramesInOneChunk() {
        let first = CastMessage(
            sourceID: "s", destinationID: "r",
            namespace: "urn:a", payloadJSON: "1"
        )
        let second = CastMessage(
            sourceID: "s", destinationID: "r",
            namespace: "urn:b", payloadJSON: "2"
        )
        var buffer = first.encoded() + second.encoded()
        let decoded = CastMessage.decodeFrames(from: &buffer)
        #expect(decoded == [first, second])
        #expect(buffer.isEmpty)
    }

    @Test func decodeFramesKeepsPartialFrameForNextChunk() {
        let message = CastMessage(
            sourceID: "s", destinationID: "r",
            namespace: "urn:a", payloadJSON: "hello"
        )
        let frame = message.encoded()
        var buffer = frame.prefix(6)
        #expect(CastMessage.decodeFrames(from: &buffer).isEmpty)
        buffer.append(frame.suffix(frame.count - 6))
        let decoded = CastMessage.decodeFrames(from: &buffer)
        #expect(decoded == [message])
        #expect(buffer.isEmpty)
    }

    @Test func decodeFramesRejectsOversizedLengthAsDesync() {
        var buffer = Data([0xFF, 0xFF, 0xFF, 0xFF]) // 4 GiB — corruption
        #expect(CastMessage.decodeFrames(from: &buffer).isEmpty)
    }

    @Test func decodeFramesStopsAtZeroLengthFrame() {
        // A zero length is corruption, not an empty message: parsing
        // stops and the desync stays in the buffer, where the caller
        // is expected to drop the connection.
        var buffer = Data([0x00, 0x00, 0x00, 0x00, 0x08])
        #expect(CastMessage.decodeFrames(from: &buffer).isEmpty)
        #expect(buffer == Data([0x00, 0x00, 0x00, 0x00, 0x08]))
    }

    // MARK: Payload builders

    @Test func controlPayloadsAreExact() {
        #expect(CastPayloads.connect() == #"{"type":"CONNECT"}"#)
        #expect(CastPayloads.close() == #"{"type":"CLOSE"}"#)
        #expect(CastPayloads.ping() == #"{"type":"PING"}"#)
        #expect(CastPayloads.pong() == #"{"type":"PONG"}"#)
    }

    @Test func launchPayloadCarriesAppIDAndRequestID() {
        let object = jsonObject(
            CastPayloads.launch(appID: "CC1AD845", requestID: 7)
        )
        #expect(object["type"] as? String == "LAUNCH")
        #expect(object["appId"] as? String == "CC1AD845")
        #expect(object["requestId"] as? Int == 7)
    }

    @Test func loadPayloadDescribesThePhoto() {
        let url = URL(string: "http://192.168.1.5:8096/photo-01.jpg")!
        let object = jsonObject(
            CastPayloads.load(mediaURL: url, contentType: "image/jpeg", title: "photo-01", requestID: 3)
        )
        #expect(object["type"] as? String == "LOAD")
        #expect(object["autoplay"] as? Bool == true)
        let media = object["media"] as? [String: Any]
        #expect(media?["contentId"] as? String == "http://192.168.1.5:8096/photo-01.jpg")
        #expect(media?["contentType"] as? String == "image/jpeg")
        #expect(media?["streamType"] as? String == "BUFFERED")
        let metadata = media?["metadata"] as? [String: Any]
        #expect(metadata?["metadataType"] as? Int == 4)
        #expect(metadata?["title"] as? String == "photo-01")
    }

    @Test func loadPayloadEscapesQuotedTitles() {
        let url = URL(string: "http://host:1/photo.jpg")!
        let payload = CastPayloads.load(
            mediaURL: url, contentType: "image/jpeg",
            title: #"a "quoted" name"#, requestID: 1
        )
        #expect(CastPayloads.messageType(of: payload) == "LOAD")
        let object = jsonObject(payload)
        let media = object["media"] as? [String: Any]
        #expect((media?["metadata"] as? [String: Any])?["title"] as? String == #"a "quoted" name"#)
    }

    @Test func messageTypeReadsDiscriminator() {
        #expect(CastPayloads.messageType(of: #"{"type":"RECEIVER_STATUS"}"#) == "RECEIVER_STATUS")
        #expect(CastPayloads.messageType(of: "not json") == nil)
        #expect(CastPayloads.messageType(of: "{}") == nil)
    }

    // MARK: Receiver status

    @Test func receiverStatusParsesRunningApp() {
        let payload = """
        {"requestId":2,"type":"RECEIVER_STATUS",
         "status":{"applications":[{"appId":"CC1AD845","displayName":"Default Media Receiver",
                                    "sessionId":"s-1","transportId":"t-1","statusText":"Ready"}],
                   "volume":{"controlType":"master","level":0.5}}}
        """
        let status = ReceiverStatus.parse(payload)
        #expect(status?.applications.count == 1)
        let app = status?.applications.first
        #expect(app?.appID == "CC1AD845")
        #expect(app?.transportID == "t-1")
        #expect(app?.sessionID == "s-1")
        #expect(app?.displayName == "Default Media Receiver")
    }

    @Test func receiverStatusHandlesIdleReceiver() {
        let payload = #"{"requestId":2,"type":"RECEIVER_STATUS","status":{}}"#
        let status = ReceiverStatus.parse(payload)
        #expect(status?.applications.isEmpty == true)
    }

    @Test func receiverStatusRejectsGarbage() {
        #expect(ReceiverStatus.parse("not json") == nil)
    }

    // MARK: Helpers

    private func jsonObject(_ text: String) -> [String: Any] {
        guard let data = text.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [:] }
        return object
    }
}
