import Foundation

// `MaxActivity --snapshot <dossier>` dessine l'interface en PNG avec des données de démo,
// sans rien suivre ni toucher à la vraie base. Sinon, l'app démarre normalement.
if let index = CommandLine.arguments.firstIndex(of: "--snapshot") {
    let folder = CommandLine.arguments.dropFirst(index + 1).first ?? FileManager.default.currentDirectoryPath
    MainActor.assumeIsolated {
        Snapshot.run(into: URL(fileURLWithPath: folder, isDirectory: true))
    }
} else {
    MaxActivityApp.main()
}
