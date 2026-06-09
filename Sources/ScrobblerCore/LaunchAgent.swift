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

        _ = try? runLaunchctl(["bootout", serviceTarget])
        try runLaunchctl(["bootstrap", domain, plistURL.path])
        try runLaunchctl(["kickstart", "-k", serviceTarget])
    }

    public func uninstall() throws {
        _ = try? runLaunchctl(["bootout", serviceTarget])

        if fileManager.fileExists(atPath: plistURL.path) {
            try fileManager.removeItem(at: plistURL)
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

    private func ensureExecutable() throws {
        let path = executableURL.standardizedFileURL.path
        guard fileManager.isExecutableFile(atPath: path) else {
            throw ScrobblerError.commandFailed("Not an executable file: \(path)")
        }
    }

    @discardableResult
    private func runLaunchctl(_ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        let errorOutput = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errorOutput

        try process.run()
        process.waitUntilExit()

        let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorOutput.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let details = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ScrobblerError.commandFailed(details.isEmpty ? "launchctl failed" : details)
        }

        return stdout
    }
}
