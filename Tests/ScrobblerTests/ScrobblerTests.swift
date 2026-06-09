import Foundation
import Testing
@testable import ScrobblerCore

struct ScrobblerTests {
    @Test func lastFMSignatureIgnoresFormatAndApiSig() {
        let signature = LastFMSignature.signature(
            for: [
                "method": "auth.getSession",
                "api_key": "xxxxxxxxxx",
                "token": "yyyyyy",
                "format": "json",
                "api_sig": "ignored"
            ],
            secret: "ilovecher"
        )

        #expect(signature == "b87d61da3cda91a8b6746c4aef55d6f8")
    }

    @Test func scrobbleThresholdUsesHalfDurationBeforeFourMinutes() {
        let snapshot = TrackSnapshot(
            state: .playing,
            id: "abc",
            name: "Short Song",
            artist: "Artist",
            album: nil,
            albumArtist: nil,
            duration: 180,
            playerPosition: 90,
            trackNumber: nil
        )
        let active = ActiveTrack(
            snapshot: snapshot,
            startedAt: Date(timeIntervalSince1970: 1_000),
            listenedDuration: 90,
            nowPlayingSent: true,
            scrobbled: false
        )

        #expect(active.shouldScrobble(at: Date(timeIntervalSince1970: 1_090)))
    }

    @Test func scrobbleThresholdCapsAtFourMinutes() {
        let snapshot = TrackSnapshot(
            state: .playing,
            id: "abc",
            name: "Long Song",
            artist: "Artist",
            album: nil,
            albumArtist: nil,
            duration: 900,
            playerPosition: 239,
            trackNumber: nil
        )
        let active = ActiveTrack(
            snapshot: snapshot,
            startedAt: Date(timeIntervalSince1970: 1_000),
            listenedDuration: 239,
            nowPlayingSent: true,
            scrobbled: false
        )

        #expect(!active.shouldScrobble(at: Date(timeIntervalSince1970: 1_240)))

        var advanced = active
        advanced.snapshot.playerPosition = 240
        advanced.listenedDuration = 240
        #expect(advanced.shouldScrobble(at: Date(timeIntervalSince1970: 1_240)))
    }

    @Test func tracksShorterThanThirtySecondsAreIgnored() {
        let snapshot = TrackSnapshot(
            state: .playing,
            id: "abc",
            name: "Interlude",
            artist: "Artist",
            album: nil,
            albumArtist: nil,
            duration: 30,
            playerPosition: 30,
            trackNumber: nil
        )
        let active = ActiveTrack(
            snapshot: snapshot,
            startedAt: Date(timeIntervalSince1970: 1_000),
            nowPlayingSent: true,
            scrobbled: false
        )

        #expect(!snapshot.isPlayableTrack)
        #expect(!active.shouldScrobble(at: Date(timeIntervalSince1970: 1_030)))
    }

    @Test func wallClockTimeDoesNotCountAsPlayback() {
        let snapshot = TrackSnapshot(
            state: .playing,
            id: "abc",
            name: "Paused Song",
            artist: "Artist",
            album: nil,
            albumArtist: nil,
            duration: 180,
            playerPosition: 10,
            trackNumber: nil
        )
        let active = ActiveTrack(
            snapshot: snapshot,
            startedAt: Date(timeIntervalSince1970: 1_000),
            nowPlayingSent: true,
            scrobbled: false
        )

        #expect(!active.shouldScrobble(at: Date(timeIntervalSince1970: 2_000)))
    }

    @Test func seekingForwardDoesNotCountAsListenedPlayback() {
        let initial = TrackSnapshot(
            state: .playing,
            id: "abc",
            name: "Seeked Song",
            artist: "Artist",
            album: nil,
            albumArtist: nil,
            duration: 180,
            playerPosition: 0,
            trackNumber: nil
        )
        let seeked = TrackSnapshot(
            state: .playing,
            id: "abc",
            name: "Seeked Song",
            artist: "Artist",
            album: nil,
            albumArtist: nil,
            duration: 180,
            playerPosition: 95,
            trackNumber: nil
        )

        let active = ActiveTrack(
            snapshot: initial,
            startedAt: Date(timeIntervalSince1970: 1_000),
            lastObservedAt: Date(timeIntervalSince1970: 1_000),
            listenedDuration: 0,
            nowPlayingSent: true,
            scrobbled: false
        ).observing(seeked, at: Date(timeIntervalSince1970: 1_001))

        #expect(active.listenedDuration <= 2)
        #expect(!active.shouldScrobble(at: Date(timeIntervalSince1970: 1_001)))
    }

    @Test func lastFMScrobbleReportSurfacesIgnoredMessages() throws {
        let report = try LastFMClient.scrobbleReport(from: [
            "scrobbles": [
                "@attr": [
                    "accepted": "0",
                    "ignored": "1"
                ],
                "scrobble": [
                    "ignoredMessage": [
                        "code": "1",
                        "#text": "Timestamp is too old"
                    ]
                ]
            ]
        ])

        #expect(report.accepted == 0)
        #expect(report.ignoredMessages == ["Timestamp is too old"])
    }

    @Test func configRequiresSessionKeyForDaemonUse() {
        let missing = AppConfig(
            apiKey: "key",
            sharedSecret: "secret",
            sessionKey: nil,
            username: nil,
            pollInterval: 5
        )
        let present = AppConfig(
            apiKey: "key",
            sharedSecret: "secret",
            sessionKey: "session",
            username: nil,
            pollInterval: 5
        )

        #expect(!missing.hasSessionKey)
        #expect(present.hasSessionKey)
    }

    @Test func failedPendingBatchDoesNotBlockLaterBatches() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("scrobbler-tests-\(UUID().uuidString)", isDirectory: true)
        let store = FileStore(directory: directory)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let now = Date(timeIntervalSince1970: 2_000_000)
        let pending = (0..<51).map { index in
            PendingScrobble(track: track(name: "Queued \(index)"), timestamp: Int(now.timeIntervalSince1970) - 60)
        }
        try store.saveState(AppState(activeTrack: nil, pendingScrobbles: pending))

        let client = FailingFirstBatchClient()
        let scrobbler = Scrobbler(
            musicReader: StaticMusicReader(snapshot: stoppedSnapshot()),
            client: client,
            store: store,
            config: AppConfig(
                apiKey: "key",
                sharedSecret: "secret",
                sessionKey: "session",
                username: nil,
                pollInterval: 5
            )
        )

        try await scrobbler.tick(at: now)

        let state = store.loadState()
        let batchSizes = await client.batchSizes()

        #expect(batchSizes == [50, 1])
        #expect(state.pendingScrobbles.count == 50)
        #expect(state.pendingScrobbles.first?.track.name == "Queued 0")
        #expect(state.pendingScrobbles.last?.track.name == "Queued 49")
    }

    @Test func launchAgentPlistUsesExecutableAndLogPaths() throws {
        let installer = LaunchAgentInstaller(
            executableURL: URL(fileURLWithPath: "/tmp/scrobbler"),
            homeDirectory: URL(fileURLWithPath: "/Users/tester")
        )

        let plist = try PropertyListSerialization.propertyList(
            from: installer.plistData(),
            options: [],
            format: nil
        ) as? [String: Any]

        #expect(plist?["Label"] as? String == LaunchAgentInstaller.label)
        #expect(plist?["ProgramArguments"] as? [String] == ["/tmp/scrobbler", "run"])
        #expect(plist?["RunAtLoad"] as? Bool == true)
        #expect(plist?["KeepAlive"] as? Bool == true)
        #expect(plist?["StandardOutPath"] as? String == "/Users/tester/Library/Logs/\(LaunchAgentInstaller.label).log")
        #expect(plist?["StandardErrorPath"] as? String == "/Users/tester/Library/Logs/\(LaunchAgentInstaller.label).err.log")
    }

    private func track(name: String) -> TrackSnapshot {
        TrackSnapshot(
            state: .playing,
            id: name,
            name: name,
            artist: "Artist",
            album: nil,
            albumArtist: nil,
            duration: 180,
            playerPosition: 90,
            trackNumber: nil
        )
    }

    private func stoppedSnapshot() -> TrackSnapshot {
        TrackSnapshot(
            state: .stopped,
            id: nil,
            name: "",
            artist: "",
            album: nil,
            albumArtist: nil,
            duration: 0,
            playerPosition: 0,
            trackNumber: nil
        )
    }
}

private struct StaticMusicReader: AppleMusicReading {
    var snapshot: TrackSnapshot

    func currentTrack() throws -> TrackSnapshot {
        snapshot
    }
}

private actor FailingFirstBatchClient: LastFMServicing {
    private var batches: [Int] = []

    func updateNowPlaying(_ track: TrackSnapshot) async throws {}

    func scrobble(_ pending: PendingScrobble) async throws -> ScrobbleBatchReport {
        try await scrobble([pending])
    }

    func scrobble(_ scrobbles: [PendingScrobble]) async throws -> ScrobbleBatchReport {
        batches.append(scrobbles.count)
        if scrobbles.count == 50 {
            throw ScrobblerError.lastFMFailed("poison batch")
        }
        return ScrobbleBatchReport(accepted: scrobbles.count, ignoredMessages: [])
    }

    func batchSizes() -> [Int] {
        batches
    }
}
