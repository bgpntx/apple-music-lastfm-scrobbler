import Foundation

public final class Scrobbler {
    private let musicReader: AppleMusicReading
    private let client: LastFMClient
    private let store: FileStore
    private let config: AppConfig
    private var state: AppState
    private var lastPendingFlush: Date?

    public init(musicReader: AppleMusicReading, client: LastFMClient, store: FileStore, config: AppConfig) {
        self.musicReader = musicReader
        self.client = client
        self.store = store
        self.config = config
        self.state = store.loadState()
    }

    public func run() async throws {
        print("Polling Apple Music every \(Int(config.pollInterval))s. Press Ctrl-C to stop.")

        while true {
            do {
                try await tick(at: Date())
            } catch {
                print("warn: \(error.localizedDescription)")
            }

            try await Task.sleep(nanoseconds: UInt64(config.pollInterval * 1_000_000_000))
        }
    }

    public func tick(at now: Date) async throws {
        try await flushPendingScrobbles(at: now)

        let snapshot = try musicReader.currentTrack()

        if snapshot.state == .paused {
            if state.activeTrack?.snapshot.identity == snapshot.identity {
                state.activeTrack?.snapshot = snapshot
                try store.saveState(state)
            }
            return
        }

        guard snapshot.isPlayableTrack else {
            if state.activeTrack != nil {
                state.activeTrack = nil
                try store.saveState(state)
            }
            return
        }

        if state.activeTrack?.snapshot.identity != snapshot.identity {
            state.activeTrack = ActiveTrack(
                snapshot: snapshot,
                startedAt: now.addingTimeInterval(-snapshot.playerPosition),
                nowPlayingSent: false,
                scrobbled: false
            )
        } else {
            state.activeTrack?.snapshot = snapshot
        }

        guard var activeTrack = state.activeTrack else {
            return
        }

        if !activeTrack.nowPlayingSent {
            do {
                try await client.updateNowPlaying(snapshot)
                print("now playing: \(snapshot.artist) - \(snapshot.name)")
            } catch {
                print("warn: now playing failed: \(error.localizedDescription)")
            }
            activeTrack.nowPlayingSent = true
            state.activeTrack = activeTrack
        }

        if activeTrack.shouldScrobble(at: now) {
            let pending = PendingScrobble(track: snapshot, timestamp: activeTrack.scrobbleTimestamp)
            do {
                try await client.scrobble(pending)
                print("scrobbled: \(snapshot.artist) - \(snapshot.name)")
            } catch {
                state.pendingScrobbles.append(pending)
                print("warn: queued scrobble: \(error.localizedDescription)")
            }
            activeTrack.scrobbled = true
            state.activeTrack = activeTrack
        }

        try store.saveState(state)
    }

    private func flushPendingScrobbles(at now: Date) async throws {
        guard !state.pendingScrobbles.isEmpty else {
            return
        }

        if let lastPendingFlush, now.timeIntervalSince(lastPendingFlush) < 60 {
            return
        }
        lastPendingFlush = now

        var remaining: [PendingScrobble] = []

        for scrobble in state.pendingScrobbles {
            do {
                try await client.scrobble(scrobble)
                print("flushed: \(scrobble.track.artist) - \(scrobble.track.name)")
            } catch {
                remaining.append(scrobble)
            }
        }

        if remaining.count != state.pendingScrobbles.count {
            state.pendingScrobbles = remaining
            try store.saveState(state)
        }
    }
}
