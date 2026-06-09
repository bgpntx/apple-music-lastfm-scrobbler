import Foundation

public struct TrackSnapshot: Codable, Equatable, Sendable {
    public enum PlayerState: String, Codable, Sendable {
        case playing
        case paused
        case stopped
    }

    public var state: PlayerState
    public var id: String?
    public var name: String
    public var artist: String
    public var album: String?
    public var albumArtist: String?
    public var duration: TimeInterval
    public var playerPosition: TimeInterval
    public var trackNumber: Int?

    public init(
        state: PlayerState,
        id: String?,
        name: String,
        artist: String,
        album: String?,
        albumArtist: String?,
        duration: TimeInterval,
        playerPosition: TimeInterval,
        trackNumber: Int?
    ) {
        self.state = state
        self.id = id
        self.name = name
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.duration = duration
        self.playerPosition = playerPosition
        self.trackNumber = trackNumber
    }

    public var isPlayableTrack: Bool {
        state == .playing && !name.isEmpty && !artist.isEmpty && duration > 30
    }

    public var identity: String {
        if let id, !id.isEmpty {
            return id
        }

        return [
            artist,
            album ?? "",
            name,
            String(Int(duration.rounded()))
        ].joined(separator: "\u{1f}")
    }
}

public struct ActiveTrack: Codable, Equatable, Sendable {
    public var snapshot: TrackSnapshot
    public var startedAt: Date
    public var nowPlayingSent: Bool
    public var scrobbled: Bool

    public init(snapshot: TrackSnapshot, startedAt: Date, nowPlayingSent: Bool, scrobbled: Bool) {
        self.snapshot = snapshot
        self.startedAt = startedAt
        self.nowPlayingSent = nowPlayingSent
        self.scrobbled = scrobbled
    }

    public var scrobbleTimestamp: Int {
        Int(startedAt.timeIntervalSince1970)
    }

    public func shouldScrobble(at now: Date) -> Bool {
        guard snapshot.isPlayableTrack, !scrobbled else {
            return false
        }

        let elapsed = snapshot.playerPosition
        let required = min(snapshot.duration / 2, 240)
        return elapsed >= required
    }
}

public struct PendingScrobble: Codable, Equatable, Sendable {
    public var track: TrackSnapshot
    public var timestamp: Int

    public init(track: TrackSnapshot, timestamp: Int) {
        self.track = track
        self.timestamp = timestamp
    }
}
