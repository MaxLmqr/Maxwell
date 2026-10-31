// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Maxwell",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Maxwell",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Maxwell",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                // Sparkle.framework est copié dans Maxwell.app/Contents/Frameworks par build.sh ;
                // hors de l'app (captures, tests), il est à côté de l'exécutable compilé.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                              "-Xlinker", "-rpath", "-Xlinker", "@executable_path"]),
            ]
        ),
        .testTarget(
            name: "MaxwellTests",
            dependencies: ["Maxwell"],
            path: "Tests/MaxwellTests"
        ),
    ]
)
