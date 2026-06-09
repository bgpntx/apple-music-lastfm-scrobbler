import Foundation
import ScrobblerCore

@main
enum Main {
    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            Foundation.exit(1)
        }
    }

    private static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        let command = args.first ?? "run"
        let store = FileStore()

        switch command {
        case "auth":
            try await authenticate(store: store)
        case "run":
            let config = try store.loadConfig()
            let scrobbler = Scrobbler(
                musicReader: AppleMusicReader(),
                client: LastFMClient(config: config),
                store: store,
                config: config
            )
            try await scrobbler.run()
        case "now":
            let snapshot = try AppleMusicReader().currentTrack()
            printNow(snapshot)
        case "install-agent":
            try installAgent(store: store)
        case "uninstall-agent":
            try uninstallAgent()
        case "agent-status":
            try printAgentStatus()
        case "help", "--help", "-h":
            printHelp()
        default:
            throw ScrobblerError.commandFailed("Unknown command `\(command)`. Run `scrobbler help`.")
        }
    }

    private static func authenticate(store: FileStore) async throws {
        var config = try store.loadConfig()
        let client = LastFMClient(config: config)
        let token = try await client.getToken()
        let authURL = "https://www.last.fm/api/auth/?api_key=\(config.apiKey)&token=\(token)"

        print("Open this URL and approve access:")
        print(authURL)
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/open"), arguments: [authURL])
        print("Press Return after approving in the browser.")
        _ = readLine()

        let session = try await client.getSession(token: token)
        config.sessionKey = session.sessionKey
        config.username = session.username
        try store.saveConfig(config)

        print("Saved Last.fm session for \(session.username) to \(store.configURL.path)")
    }

    private static func installAgent(store: FileStore) throws {
        let config = try store.loadConfig()
        guard config.hasSessionKey else {
            throw ScrobblerError.sessionMissing
        }

        if !FileManager.default.fileExists(atPath: store.configURL.path) {
            try store.saveConfig(config)
        }

        let installer = LaunchAgentInstaller(executableURL: currentExecutableURL())
        try installer.install()

        print("Installed and started \(LaunchAgentInstaller.label)")
        print("Plist: \(installer.plistURL.path)")
        print("Log: \(installer.stdoutURL.path)")
        print("Errors: \(installer.stderrURL.path)")
    }

    private static func uninstallAgent() throws {
        let installer = LaunchAgentInstaller(executableURL: currentExecutableURL())
        try installer.uninstall()
        print("Uninstalled \(LaunchAgentInstaller.label)")
    }

    private static func printAgentStatus() throws {
        let installer = LaunchAgentInstaller(executableURL: currentExecutableURL())
        print(try installer.status())
    }

    private static func currentExecutableURL() -> URL {
        let path = CommandLine.arguments[0]
        let url: URL

        if path.hasPrefix("/") {
            url = URL(fileURLWithPath: path)
        } else {
            url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(path)
        }

        return url.standardizedFileURL
    }

    private static func printNow(_ snapshot: TrackSnapshot) {
        guard snapshot.isPlayableTrack else {
            print(snapshot.state.rawValue)
            return
        }

        let album = snapshot.album.map { " (\($0))" } ?? ""
        print("\(snapshot.artist) - \(snapshot.name)\(album)")
        print("position \(Int(snapshot.playerPosition))s / \(Int(snapshot.duration))s")
    }

    private static func printHelp() {
        print("""
        Usage:
          scrobbler auth   Authorize Last.fm and save a session key
          scrobbler run    Poll Apple Music and scrobble tracks
          scrobbler now    Print the current Apple Music track
          scrobbler install-agent    Install and start a launchd user agent
          scrobbler uninstall-agent  Stop and remove the launchd user agent
          scrobbler agent-status     Print launchd status for the user agent

        Config:
          LASTFM_API_KEY and LASTFM_SHARED_SECRET are required for auth.
          LASTFM_SESSION_KEY can be used instead of running auth.

        Saved config:
          ~/.config/apple-music-lastfm-scrobbler/config.json
        """)
    }
}
