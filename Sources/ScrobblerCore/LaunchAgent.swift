import Darwin
import Foundation

public struct LaunchAgentInstaller {
    public static let label = "com.local.apple-music-lastfm-scrobbler"

    private let fileManager: FileManager
    private let homeDirectory: URL
    private let executableURL: URL

    public init(
        executableURL: URL,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) {
        self.executableURL = executableURL
        self.homeDirectory = homeDirectory
        self.fileManager = fileManager
    }

    public var plistURL: URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(Self.label).plist")
    }

    public var stdoutURL: URL {
        logDirectory.appendingPathComponent("\(Self.label).log")
    }

    public var stderrURL: URL {
        logDirectory.appendingPathComponent("\(Self.label).err.log")
    }

    public func install() throws {
        try ensureExecutable()
        try fileManager.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        let data = try plistData()
        try data.write(to: plistURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: plistURL.path)

        try bootoutIfLoaded()
        try runLaunchctl(["bootstrap", domain, plistURL.path])
        try runLaunchctl(["kickstart", "-k", serviceTarget])
    }

    public func uninstall() throws {
        let bootoutError: Error?
        do {
            try bootoutIfLoaded()
            bootoutError = nil
        } catch {
            bootoutError = error
        }

        if fileManager.fileExists(atPath: plistURL.path) {
            try fileManager.removeItem(at: plistURL)
        }

        if let bootoutError {
            throw bootoutError
        }
    }

    public func status() throws -> String {
        try runLaunchctl(["print", serviceTarget])
    }

    public func plistData() throws -> Data {
        let plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [
                executableURL.standardizedFileURL.path,
                "run"
            ],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Background",
            "StandardOutPath": stdoutURL.path,
            "StandardErrorPath": stderrURL.path
        ]

        return try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
    }

    private var logDirectory: URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
    }

    private var domain: String {
        "gui/\(getuid())"
    }

    private var serviceTarget: String {
        "\(domain)/\(Self.label)"
    }

    private enum LoadState {
        case loaded
        case notLoaded
        case unknown
    }

    private struct LaunchctlResult {
        var status: Int32
        var stdout: String
        var stderr: String
    }

    private func ensureExecutable() throws {
        let path = executableURL.standardizedFileURL.path
        guard fileManager.isExecutableFile(atPath: path) else {
            throw ScrobblerError.commandFailed("Not an executable file: \(path)")
        }
    }

    private func bootoutIfLoaded() throws {
        let initialState = loadState()

        guard initialState != .notLoaded else {
            return
        }

        _ = try? runLaunchctl(["bootout", serviceTarget])

        if initialState == .unknown {
            Thread.sleep(forTimeInterval: 0.2)
            return
        }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if loadState() == .notLoaded {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }

        throw ScrobblerError.commandFailed("Timed out waiting for launchd service to unload: \(serviceTarget)")
    }

    private func loadState() -> LoadState {
        let result = runLaunchctlResult(["print", serviceTarget])
        if result.status == 0 {
            return .loaded
        }
        if result.status == 113 || result.stderr.contains("Could not find service") {
            return .notLoaded
        }
        return .unknown
    }

    @discardableResult
    private func runLaunchctl(_ arguments: [String]) throws -> String {
        let result = runLaunchctlResult(arguments)

        guard result.status == 0 else {
            let details = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ScrobblerError.commandFailed(details.isEmpty ? "launchctl failed" : details)
        }

        return result.stdout
    }

    private func runLaunchctlResult(_ arguments: [String]) -> LaunchctlResult {
        let process = Process()
        let output = Pipe()
        let errorOutput = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errorOutput

        do {
            try process.run()
        } catch {
            return LaunchctlResult(status: -1, stdout: "", stderr: error.localizedDescription)
        }
        process.waitUntilExit()

        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return LaunchctlResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
