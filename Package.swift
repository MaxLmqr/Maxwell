// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Maxwell",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Maxwell",
            path: "Sources/Maxwell",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "MaxwellTests",
            dependencies: ["Maxwell"],
            path: "Tests/MaxwellTests"
        ),
    ]
)
