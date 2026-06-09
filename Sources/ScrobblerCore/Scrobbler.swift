import Foundation

public final class Scrobbler {
    private static let pendingFlushInterval: TimeInterval = 60
    private static let stateSaveInterval: TimeInterval = 60
    private static let maxPendingScrobbles = 500
    private static let flushBatchSize = 50
    private static let maxScrobbleAge: TimeInterval = 14 * 24 * 60 * 60

    private let musicReader: AppleMusicReading
    private let client: any LastFMServicing
    private let store: FileStore
    private let config: AppConfig
    private var state: AppState
    private var lastPendingFlush: Date?
    private var lastStateSave: Date?

    public init(musicReader: AppleMusicReading, client: any LastFMServicing, store: FileStore, config: AppConfig) {
        self.musicReader = musicReader
        self.client = client
        self.store = store
        self.config = config
        self.state = store.loadState()
    }

    public func run() async throws {
        guard config.hasSessionKey else {
            throw ScrobblerError.sessionMissing
        }

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
        var shouldSaveState = try await flushPendingScrobbles(at: now)
        if shouldSaveState {
            try saveStateIfNeeded(at: now, force: true)
            shouldSaveState = false
        }

        let reader = musicReader
        let snapshot = try await Task.detached(priority: .utility) {
            try reader.currentTrack()
        }.value

        if snapshot.state == .paused {
            if var activeTrack = state.activeTrack, activeTrack.snapshot.identity == snapshot.identity {
                shouldSaveState = shouldSaveState || activeTrack.snapshot.state != .paused
                activeTrack.snapshot = snapshot
                activeTrack.lastObservedAt = now
                state.activeTrack = activeTrack
                try saveStateIfNeeded(at: now, force: shouldSaveState)
            }
            return
        }

        guard snapshot.isPlayableTrack else {
            if state.activeTrack != nil {
                state.activeTrack = nil
                shouldSaveState = true
            }
            try saveStateIfNeeded(at: now, force: shouldSaveState)
            return
        }

        if state.activeTrack?.snapshot.identity != snapshot.identity {
            state.activeTrack = ActiveTrack(
                snapshot: snapshot,
                startedAt: now.addingTimeInterval(-snapshot.playerPosition),
                lastObservedAt: now,
                listenedDuration: 0,
                nowPlayingSent: false,
                scrobbled: false
            )
            shouldSaveState = true
        } else {
            state.activeTrack = state.activeTrack?.observing(snapshot, at: now)
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
            shouldSaveState = true
        }

        if activeTrack.shouldScrobble(at: now) {
            let pending = PendingScrobble(track: snapshot, timestamp: activeTrack.scrobbleTimestamp)
            do {
                let report = try await client.scrobble(pending)
                if report.accepted > 0 && report.ignoredMessages.isEmpty {
                    print("scrobbled: \(snapshot.artist) - \(snapshot.name)")
                } else if !report.ignoredMessages.isEmpty {
                    print("warn: ignored scrobble: \(report.ignoredMessages.joined(separator: "; "))")
                } else {
                    print("warn: Last.fm accepted 0 scrobbles for \(snapshot.artist) - \(snapshot.name)")
                }
            } catch {
                appendPendingScrobble(pending, at: now)
                print("warn: queued scrobble: \(error.localizedDescription)")
            }
            activeTrack.scrobbled = true
            state.activeTrack = activeTrack
            shouldSaveState = true
        }

        try saveStateIfNeeded(at: now, force: shouldSaveState)
    }

    private func flushPendingScrobbles(at now: Date) async throws -> Bool {
        guard !state.pendingScrobbles.isEmpty else {
            return false
        }

        var changed = trimPendingScrobbles(at: now)

        guard !state.pendingScrobbles.isEmpty else {
            return changed
        }

        if let lastPendingFlush, now.timeIntervalSince(lastPendingFlush) < Self.pendingFlushInterval {
            return changed
        }
        lastPendingFlush = now

        var remaining: [PendingScrobble] = []
        var index = 0
        let queued = state.pendingScrobbles

        while index < queued.count {
            let end = min(index + Self.flushBatchSize, queued.count)
            let batch = Array(queued[index..<end])

            do {
                let report = try await client.scrobble(batch)
                let ignored = report.ignoredMessages.isEmpty ? "" : ", ignored \(report.ignored)"
                print("flushed \(report.accepted) queued scrobble(s)\(ignored)")
            } catch {
                remaining.append(contentsOf: batch)
            }

            index = end
        }

        if remaining.count != state.pendingScrobbles.count {
            state.pendingScrobbles = remaining
            changed = true
        }

        return changed
    }

    private func appendPendingScrobble(_ pending: PendingScrobble, at now: Date) {
        state.pendingScrobbles.append(pending)
        _ = trimPendingScrobbles(at: now)
    }

    @discardableResult
    private func trimPendingScrobbles(at now: Date) -> Bool {
        let originalCount = state.pendingScrobbles.count
        let cutoff = Int(now.addingTimeInterval(-Self.maxScrobbleAge).timeIntervalSince1970)
        var scrobbles = state.pendingScrobbles.filter { $0.timestamp >= cutoff }

        if scrobbles.count > Self.maxPendingScrobbles {
            scrobbles = Array(scrobbles.suffix(Self.maxPendingScrobbles))
        }

        state.pendingScrobbles = scrobbles
        let dropped = originalCount - scrobbles.count
        if dropped > 0 {
            print("warn: dropped \(dropped) stale or excess queued scrobble(s)")
        }

        return dropped > 0
    }

    private func saveStateIfNeeded(at now: Date, force: Bool) throws {
        let shouldSave = force
            || lastStateSave == nil
            || now.timeIntervalSince(lastStateSave ?? now) >= Self.stateSaveInterval

        guard shouldSave else {
            return
        }

        try store.saveState(state)
        lastStateSave = now
    }
}
