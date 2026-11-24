import Foundation

// `Maxwell --snapshot <dossier>` dessine l'interface en PNG avec des données de démo,
// sans rien suivre ni toucher à la vraie base. Sinon, l'app démarre normalement.
// `Maxwell --mcp` sert les Tâches et le Récap à Claude.
if CommandLine.arguments.contains("--mcp") {
    // `Maxwell --mcp` : serveur MCP pour Claude, sans interface ni suivi. Voir MCPServer.
    MainActor.assumeIsolated { MCPServer.run() }
} else if let index = CommandLine.arguments.firstIndex(of: "--snapshot") {
    let folder = CommandLine.arguments.dropFirst(index + 1).first ?? FileManager.default.currentDirectoryPath
    MainActor.assumeIsolated {
        Snapshot.run(into: URL(fileURLWithPath: folder, isDirectory: true))
    }
} else {
    MaxwellApp.main()
}
