import Foundation

public struct AppConfig: Codable, Equatable, Sendable {
    public var apiKey: String
    public var sharedSecret: String
    public var sessionKey: String?
    public var username: String?
    public var pollInterval: TimeInterval

    public static let defaultPollInterval: TimeInterval = 5

    public init(
        apiKey: String,
        sharedSecret: String,
        sessionKey: String?,
        username: String?,
        pollInterval: TimeInterval
    ) {
        self.apiKey = apiKey
        self.sharedSecret = sharedSecret
        self.sessionKey = sessionKey
        self.username = username
        self.pollInterval = pollInterval
    }
}

public struct AppState: Codable, Equatable, Sendable {
    public var activeTrack: ActiveTrack?
    public var pendingScrobbles: [PendingScrobble]

    public static let empty = AppState(activeTrack: nil, pendingScrobbles: [])

    public init(activeTrack: ActiveTrack?, pendingScrobbles: [PendingScrobble]) {
        self.activeTrack = activeTrack
        self.pendingScrobbles = pendingScrobbles
    }
}

public final class FileStore {
    private let fileManager: FileManager
    public let directory: URL

    public init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager

        if let directory {
            self.directory = directory
        } else {
            let base = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".config", isDirectory: true)
                .appendingPathComponent("apple-music-lastfm-scrobbler", isDirectory: true)
            self.directory = base
        }
    }

    public var configURL: URL {
        directory.appendingPathComponent("config.json")
    }

    public var stateURL: URL {
        directory.appendingPathComponent("state.json")
    }

    public func loadConfig() throws -> AppConfig {
        if fileManager.fileExists(atPath: configURL.path) {
            let data = try Data(contentsOf: configURL)
            return try JSONDecoder().decode(AppConfig.self, from: data)
        }

        guard let apiKey = nonEmptyEnvironment("LASTFM_API_KEY"),
              let sharedSecret = nonEmptyEnvironment("LASTFM_SHARED_SECRET") else {
            throw ScrobblerError.configurationMissing(configURL.path)
        }

        return AppConfig(
            apiKey: apiKey,
            sharedSecret: sharedSecret,
            sessionKey: nonEmptyEnvironment("LASTFM_SESSION_KEY"),
            username: nonEmptyEnvironment("LASTFM_USERNAME"),
            pollInterval: AppConfig.defaultPollInterval
        )
    }

    public func saveConfig(_ config: AppConfig) throws {
        try ensureDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: configURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    public func loadState() -> AppState {
        guard fileManager.fileExists(atPath: stateURL.path),
              let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(AppState.self, from: data) else {
            return .empty
        }

        return state
    }

    public func saveState(_ state: AppState) throws {
        try ensureDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: stateURL, options: .atomic)
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func nonEmptyEnvironment(_ key: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[key],
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return value
    }
}

public enum ScrobblerError: LocalizedError {
    case configurationMissing(String)
    case sessionMissing
    case appleMusicUnavailable(String)
    case appleMusicParseFailed(String)
    case lastFMFailed(String)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .configurationMissing(let path):
            return "Missing Last.fm config. Set LASTFM_API_KEY and LASTFM_SHARED_SECRET, or create \(path)."
        case .sessionMissing:
            return "Missing Last.fm session key. Run `scrobbler auth` first, or set LASTFM_SESSION_KEY."
        case .appleMusicUnavailable(let message):
            return "Apple Music is unavailable: \(message)"
        case .appleMusicParseFailed(let output):
            return "Could not parse Apple Music response: \(output)"
        case .lastFMFailed(let message):
            return "Last.fm request failed: \(message)"
        case .commandFailed(let message):
            return message
        }
    }
}
