import CryptoKit
import Foundation

public struct ScrobbleBatchReport: Equatable, Sendable {
    public var accepted: Int
    public var ignoredMessages: [String]

    public var ignored: Int {
        ignoredMessages.count
    }

    public init(accepted: Int, ignoredMessages: [String]) {
        self.accepted = accepted
        self.ignoredMessages = ignoredMessages
    }
}

public protocol LastFMServicing: Sendable {
    func updateNowPlaying(_ track: TrackSnapshot) async throws
    func scrobble(_ scrobble: PendingScrobble) async throws -> ScrobbleBatchReport
    func scrobble(_ scrobbles: [PendingScrobble]) async throws -> ScrobbleBatchReport
}

public struct LastFMClient: LastFMServicing {
    private let apiRoot = URL(string: "https://ws.audioscrobbler.com/2.0/")!
    private let urlSession: URLSession
    private let config: AppConfig

    public init(config: AppConfig, urlSession: URLSession = .shared) {
        self.config = config
        self.urlSession = urlSession
    }

    public func getToken() async throws -> String {
        let response = try await request([
            "method": "auth.getToken",
            "api_key": config.apiKey
        ])

        guard let token = response["token"] as? String else {
            throw ScrobblerError.lastFMFailed("auth.getToken did not return a token")
        }

        return token
    }

    public func getSession(token: String) async throws -> (username: String, sessionKey: String) {
        let response = try await request([
            "method": "auth.getSession",
            "api_key": config.apiKey,
            "token": token
        ])

        guard let session = response["session"] as? [String: Any],
              let name = session["name"] as? String,
              let key = session["key"] as? String else {
            throw ScrobblerError.lastFMFailed("auth.getSession did not return a session")
        }

        return (name, key)
    }

    public func updateNowPlaying(_ track: TrackSnapshot) async throws {
        let params = commonTrackParameters(method: "track.updateNowPlaying", track: track)
        _ = try await authenticatedRequest(params)
    }

    public func scrobble(_ scrobble: PendingScrobble) async throws -> ScrobbleBatchReport {
        var params = commonTrackParameters(method: "track.scrobble", track: scrobble.track)
        params["timestamp"] = String(scrobble.timestamp)
        let response = try await authenticatedRequest(params)
        return try Self.scrobbleReport(from: response)
    }

    public func scrobble(_ scrobbles: [PendingScrobble]) async throws -> ScrobbleBatchReport {
        guard !scrobbles.isEmpty else {
            return ScrobbleBatchReport(accepted: 0, ignoredMessages: [])
        }

        guard scrobbles.count > 1 else {
            return try await scrobble(scrobbles[0])
        }

        var params: [String: String] = [
            "method": "track.scrobble",
            "api_key": config.apiKey
        ]

        for (index, scrobble) in scrobbles.enumerated() {
            appendTrackParameters(track: scrobble.track, to: &params, suffix: "[\(index)]")
            params["timestamp[\(index)]"] = String(scrobble.timestamp)
        }

        let response = try await authenticatedRequest(params)
        return try Self.scrobbleReport(from: response)
    }

    private func commonTrackParameters(method: String, track: TrackSnapshot) -> [String: String] {
        var params: [String: String] = [
            "method": method,
            "api_key": config.apiKey
        ]

        appendTrackParameters(track: track, to: &params, suffix: "")

        return params
    }

    private func appendTrackParameters(track: TrackSnapshot, to params: inout [String: String], suffix: String) {
        params["artist\(suffix)"] = track.artist
        params["track\(suffix)"] = track.name
        params["duration\(suffix)"] = String(Int(track.duration.rounded()))

        if let album = track.album, !album.isEmpty {
            params["album\(suffix)"] = album
        }
        if let albumArtist = track.albumArtist, !albumArtist.isEmpty, albumArtist != track.artist {
            params["albumArtist\(suffix)"] = albumArtist
        }
        if let trackNumber = track.trackNumber, trackNumber > 0 {
            params["trackNumber\(suffix)"] = String(trackNumber)
        }
    }

    private func authenticatedRequest(_ params: [String: String]) async throws -> [String: Any] {
        guard let sessionKey = config.sessionKey, !sessionKey.isEmpty else {
            throw ScrobblerError.sessionMissing
        }

        var signedParams = params
        signedParams["sk"] = sessionKey
        return try await request(signedParams)
    }

    private func request(_ params: [String: String]) async throws -> [String: Any] {
        var signedParams = params
        signedParams["api_sig"] = LastFMSignature.signature(for: signedParams, secret: config.sharedSecret)
        signedParams["format"] = "json"

        var request = URLRequest(url: apiRoot)
        request.httpMethod = "POST"
        request.setValue("AppleMusicLastFMScrobbler/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody(signedParams)

        let (data, response) = try await urlSession.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        if let error = parsed?["error"], let message = parsed?["message"] {
            throw ScrobblerError.lastFMFailed("HTTP \(statusCode), code \(error): \(message)")
        }

        guard (200..<300).contains(statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 response>"
            throw ScrobblerError.lastFMFailed("HTTP \(statusCode): \(body)")
        }

        guard let parsed else {
            throw ScrobblerError.lastFMFailed("Invalid JSON response")
        }

        return parsed
    }

    static func scrobbleReport(from response: [String: Any]) throws -> ScrobbleBatchReport {
        guard let scrobbles = response["scrobbles"] as? [String: Any] else {
            throw ScrobblerError.lastFMFailed("track.scrobble did not return scrobbles")
        }

        let entries: [[String: Any]]
        if let entry = scrobbles["scrobble"] as? [String: Any] {
            entries = [entry]
        } else if let batch = scrobbles["scrobble"] as? [[String: Any]] {
            entries = batch
        } else {
            entries = []
        }

        var ignoredMessages: [String] = []

        for entry in entries {
            guard let ignored = entry["ignoredMessage"] as? [String: Any] else {
                continue
            }

            let code = ignored["code"].map { "\($0)" } ?? "0"
            let text = (ignored["#text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if code != "0" || !text.isEmpty {
                ignoredMessages.append(text.isEmpty ? "code \(code)" : text)
            }
        }

        let attr = scrobbles["@attr"] as? [String: Any]
        let accepted = intValue(attr?["accepted"]) ?? max(0, entries.count - ignoredMessages.count)
        let ignoredCount = intValue(attr?["ignored"]) ?? ignoredMessages.count

        if ignoredCount > ignoredMessages.count {
            ignoredMessages.append("Last.fm ignored \(ignoredCount - ignoredMessages.count) additional scrobble(s)")
        }

        return ScrobbleBatchReport(accepted: accepted, ignoredMessages: ignoredMessages)
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int:
            return int
        case let string as String:
            return Int(string)
        default:
            return nil
        }
    }

    private func formBody(_ params: [String: String]) -> Data {
        let body = params
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(percentEncode(key))=\(percentEncode(value))"
            }
            .joined(separator: "&")

        return Data(body.utf8)
    }

    private func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

enum LastFMSignature {
    static func signature(for params: [String: String], secret: String) -> String {
        let base = params
            .filter { key, _ in key != "format" && key != "callback" && key != "api_sig" }
            .sorted { $0.key < $1.key }
            .map { key, value in "\(key)\(value)" }
            .joined() + secret

        let digest = Insecure.MD5.hash(data: Data(base.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
