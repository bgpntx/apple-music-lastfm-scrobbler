import Foundation

public protocol AppleMusicReading {
    func currentTrack() throws -> TrackSnapshot
}

public struct AppleMusicReader: AppleMusicReading {
    public init() {}

    private let script = """
    const music = Application("/System/Applications/Music.app");
    const stopped = {
      state: "stopped",
      id: null,
      name: "",
      artist: "",
      album: null,
      albumArtist: null,
      duration: 0,
      playerPosition: 0,
      trackNumber: null
    };

    if (!music.running()) {
      JSON.stringify(stopped);
    } else {
      const state = String(music.playerState()).toLowerCase();
      if (state !== "playing" && state !== "paused") {
        JSON.stringify(stopped);
      } else {
        const track = music.currentTrack();
        JSON.stringify({
          state: state,
          id: String(track.persistentID()),
          name: String(track.name()),
          artist: String(track.artist()),
          album: String(track.album()),
          albumArtist: String(track.albumArtist()),
          duration: Number(track.duration()),
          playerPosition: Number(music.playerPosition()),
          trackNumber: Number(track.trackNumber())
        });
      }
    }
    """

    public func currentTrack() throws -> TrackSnapshot {
        let process = Process()
        let output = Pipe()
        let errorOutput = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]
        process.standardOutput = output
        process.standardError = errorOutput

        do {
            try process.run()
        } catch {
            throw ScrobblerError.appleMusicUnavailable(error.localizedDescription)
        }

        process.waitUntilExit()

        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw ScrobblerError.appleMusicUnavailable(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard let data = stdout.data(using: .utf8) else {
            throw ScrobblerError.appleMusicParseFailed(stdout)
        }

        do {
            return try JSONDecoder().decode(TrackSnapshot.self, from: data)
        } catch {
            throw ScrobblerError.appleMusicParseFailed(stdout)
        }
    }
}
