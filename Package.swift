// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Scrobbler",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "scrobbler", targets: ["Scrobbler"])
    ],
    targets: [
        .target(
            name: "ScrobblerCore"
        ),
        .executableTarget(
            name: "Scrobbler",
            dependencies: ["ScrobblerCore"],
            path: "Sources/ScrobblerCLI"
        ),
        .testTarget(
            name: "ScrobblerTests",
            dependencies: ["ScrobblerCore"]
        )
    ]
)
