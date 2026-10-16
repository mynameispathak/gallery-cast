import Foundation

/// JSON payloads exchanged over the CASTV2 namespaces, plus the receiver
/// status documents that come back. Serialized with JSONSerialization so
/// arbitrary filenames and device names escape correctly.
enum CastPayloads {

    /// The Default Media Receiver — the one Cast app that needs no
    /// registration with Google. It displays one photo at a URL; the
    /// slideshow drives it one `LOAD` at a time.
    static let defaultMediaReceiverAppID = "CC1AD845"

    // MARK: Requests

    static func connect() -> String {
        json(["type": "CONNECT"])
    }

    static func close() -> String {
        json(["type": "CLOSE"])
    }

    static func ping() -> String {
        json(["type": "PING"])
    }

    static func pong() -> String {
        json(["type": "PONG"])
    }

    static func getStatus(requestID: Int) -> String {
        json(["type": "GET_STATUS", "requestId": requestID])
    }

    static func launch(appID: String, requestID: Int) -> String {
        json(["type": "LAUNCH", "appId": appID, "requestId": requestID])
    }

    static func stopApp(sessionID: String, requestID: Int) -> String {
        json(["type": "STOP", "sessionId": sessionID, "requestId": requestID])
    }

    /// Tells the receiver app to show one photo. Photos are addressed by
    /// URL — the receiver fetches them itself from the Mac's local server.
    static func load(mediaURL: URL, contentType: String, title: String, requestID: Int) -> String {
        json([
            "type": "LOAD",
            "requestId": requestID,
            "autoplay": true,
            "media": [
                "contentId": mediaURL.absoluteString,
                "contentType": contentType,
                "streamType": "BUFFERED",
                "metadata": [
                    "metadataType": 4, // photo
                    "type": 4,
                    "title": title,
                ],
            ],
        ])
    }

    // MARK: Responses

    /// The `type` discriminator of an inbound payload, if present.
    static func messageType(of payloadJSON: String) -> String? {
        guard let data = payloadJSON.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = object["type"] as? String
        else { return nil }
        return type
    }

    private static func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        ) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// The subset of `RECEIVER_STATUS` the app cares about: which Cast app
/// (if any) is running, and the identifiers needed to talk to it.
struct ReceiverStatus: Equatable, Sendable {

    struct Application: Equatable, Sendable {
        var appID: String
        var sessionID: String?
        var transportID: String?
        var displayName: String?
    }

    var applications: [Application] = []

    static func parse(_ payloadJSON: String) -> ReceiverStatus? {
        struct Wire: Decodable {
            struct Status: Decodable {
                struct Application: Decodable {
                    let appId: String?
                    let sessionId: String?
                    let transportId: String?
                    let displayName: String?
                }
                let applications: [Application]?
            }
            let status: Status
        }

        guard let data = payloadJSON.data(using: .utf8),
              let wire = try? JSONDecoder().decode(Wire.self, from: data)
        else { return nil }

        return ReceiverStatus(
            applications: (wire.status.applications ?? []).map {
                Application(
                    appID: $0.appId ?? "",
                    sessionID: $0.sessionId,
                    transportID: $0.transportId,
                    displayName: $0.displayName
                )
            }
        )
    }
}
