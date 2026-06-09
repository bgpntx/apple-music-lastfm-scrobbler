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
            nowPlayingSent: true,
            scrobbled: false
        )

        #expect(active.shouldScrobble(at: Date(timeIntervalSince1970: 1_020)))
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
            nowPlayingSent: true,
            scrobbled: false
        )

        #expect(!active.shouldScrobble(at: Date(timeIntervalSince1970: 1_010)))

        var advanced = active
        advanced.snapshot.playerPosition = 240
        #expect(advanced.shouldScrobble(at: Date(timeIntervalSince1970: 1_010)))
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
}
