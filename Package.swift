// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MaxActivity",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "MaxActivity",
            path: "Sources/MaxActivity",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "MaxActivityTests",
            dependencies: ["MaxActivity"],
            path: "Tests/MaxActivityTests"
        ),
    ]
)
