import Foundation

/// Maxwell en serveur MCP : `Maxwell --mcp`, lancé par Claude Desktop ou Claude Code, expose les Tâches
/// et le Récap. Il parle JSON-RPC sur l'entrée et la sortie standard, une ligne par message,
/// et lit la même base que l'app. Rien d'autre que ces messages ne doit sortir sur la sortie standard.
@MainActor
final class MCPServer {
    private let tools: MCPTools

    init(db: Database) {
        tools = MCPTools(db: db)
    }

    /// Ouvre la base de Maxwell, ou celle que désigne `MAXWELL_DB` (pour les tests), et sert jusqu'à la fin de l'entrée.
    static func run() {
        let url = ProcessInfo.processInfo.environment["MAXWELL_DB"].map { URL(fileURLWithPath: $0) }
            ?? Database.defaultURL
        guard let db = try? Database(url: url) else {
            FileHandle.standardError.write(Data("Maxwell : impossible d'ouvrir la base \(url.path)\n".utf8))
            exit(1)
        }
        let server = MCPServer(db: db)
        while let line = readLine(strippingNewline: true) {
            guard let reply = server.handle(line: line) else { continue }
            FileHandle.standardOutput.write(Data((reply + "\n").utf8))
        }
    }

    /// La réponse à une ligne reçue, ou nil s'il n'y a rien à répondre (une notification).
    func handle(line: String) -> String? {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let message = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
            return Self.encode(["jsonrpc": "2.0", "id": NSNull(),
                                "error": ["code": -32700, "message": "Message JSON illisible"]])
        }
        // Sans identifiant, c'est une notification : on n'y répond pas.
        guard let id = message["id"], !(id is NSNull) else { return nil }
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]

        func result(_ value: Any) -> String { Self.encode(["jsonrpc": "2.0", "id": id, "result": value]) }
        func failure(_ code: Int, _ text: String) -> String {
            Self.encode(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": text]])
        }

        switch method {
        case "initialize":
            return result([
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "maxwell", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"],
                "instructions": """
                    Maxwell est l'assistant personnel de Max sur son Mac : sa liste de tâches et le temps \
                    qu'il passe dans chaque app et sur chaque site. Les dates sont au format AAAA-MM-JJ. \
                    Ne coche une tâche que si Max le demande ou si le travail demandé est vraiment fini ; \
                    pour rendre compte d'un travail, utilise annotate_task.
                    """,
            ])
        case "ping":
            return result([String: Any]())
        case "tools/list":
            return result(["tools": MCPTools.definitions])
        case "tools/call":
            guard let name = params["name"] as? String else { return failure(-32602, "Nom d'outil manquant") }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            do {
                let value = try tools.call(name, arguments)
                return result(["content": [["type": "text", "text": Self.encode(value, pretty: true)]], "isError": false])
            } catch let error as MCPError {
                // Une erreur d'outil se rend à Claude, qui peut corriger sa demande.
                return result(["content": [["type": "text", "text": error.message]], "isError": true])
            } catch {
                return failure(-32603, "\(error)")
            }
        default:
            return failure(-32601, "Méthode inconnue : \(method)")
        }
    }

    static func encode(_ value: Any, pretty: Bool = false) -> String {
        var options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        if pretty { options.insert(.prettyPrinted) }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: options) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}

struct MCPError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
