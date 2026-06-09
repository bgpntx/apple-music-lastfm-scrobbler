import CryptoKit
import Foundation

public struct LastFMClient {
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
        try await authenticatedRequest(params)
    }

    public func scrobble(_ scrobble: PendingScrobble) async throws {
        var params = commonTrackParameters(method: "track.scrobble", track: scrobble.track)
        params["timestamp"] = String(scrobble.timestamp)
        try await authenticatedRequest(params)
    }

    private func commonTrackParameters(method: String, track: TrackSnapshot) -> [String: String] {
        var params: [String: String] = [
            "method": method,
            "api_key": config.apiKey,
            "artist": track.artist,
            "track": track.name,
            "duration": String(Int(track.duration.rounded()))
        ]

        if let album = track.album, !album.isEmpty {
            params["album"] = album
        }
        if let albumArtist = track.albumArtist, !albumArtist.isEmpty, albumArtist != track.artist {
            params["albumArtist"] = albumArtist
        }
        if let trackNumber = track.trackNumber, trackNumber > 0 {
            params["trackNumber"] = String(trackNumber)
        }

        return params
    }

    private func authenticatedRequest(_ params: [String: String]) async throws {
        guard let sessionKey = config.sessionKey, !sessionKey.isEmpty else {
            throw ScrobblerError.sessionMissing
        }

        var signedParams = params
        signedParams["sk"] = sessionKey
        _ = try await request(signedParams)
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
