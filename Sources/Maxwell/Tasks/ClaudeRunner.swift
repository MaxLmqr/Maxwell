import AppKit
import Foundation

/// Ce que Claude a le droit de faire seul quand Maxwell le lance en arrière-plan,
/// où personne ne peut valider une action en cours de route.
enum ClaudeAutonomy: String, CaseIterable, Identifiable {
    /// Claude agit et s'arrête de lui-même devant ce qui lui paraît risqué.
    case auto
    /// Claude modifie des fichiers, mais ne lance aucune commande.
    case acceptEdits
    /// Claude lit et propose un plan, sans rien changer.
    case plan

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: "agir en autonomie"
        case .acceptEdits: "modifier des fichiers, sans commande"
        case .plan: "proposer un plan, sans rien changer"
        }
    }

    static let key = "claudeAutonomy"
    static var current: ClaudeAutonomy {
        get { UserDefaults.standard.string(forKey: key).flatMap(ClaudeAutonomy.init(rawValue:)) ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

/// Le modèle qui travaille sur une Tâche confiée. Maxwell retient le dernier choisi.
enum ClaudeModel: String, CaseIterable, Identifiable {
    case opus, fable, sonnet, haiku
    /// Celui que Claude Code utilise sans consigne : son propre réglage.
    case standard

    var id: String { rawValue }
    var label: String { self == .standard ? "réglage de Claude" : rawValue }
    /// Ce qu'on passe à `claude --model`, nil pour ne rien passer.
    var alias: String? { self == .standard ? nil : rawValue }

    /// Le suivant dans la liste, en boucle (touche Tab).
    var next: ClaudeModel {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }

    static let key = "claudeModel"
    static var current: ClaudeModel {
        // Opus tant que Max n'en a pas choisi un autre.
        get { UserDefaults.standard.string(forKey: key).flatMap(ClaudeModel.init(rawValue:)) ?? .opus }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }
}

/// Lance Claude Code sur une Tâche, en arrière-plan, dans le dossier de son Projet, et suit son avancement.
/// Rien ne passe par Claude Desktop : Maxwell démarre lui-même `claude -p` et lit ce qu'il renvoie.
@MainActor
final class ClaudeRunner: ObservableObject {
    /// Ce que Claude est en train de faire, par Tâche : « Edit Recap.swift », « Bash swift test »…
    @Published private(set) var activity: [TaskID: String] = [:]

    private let store: TaskStore
    private var processes: [TaskID: Process] = [:]
    private var buffers: [TaskID: Data] = [:]
    private var errors: [TaskID: String] = [:]

    init(store: TaskStore) {
        self.store = store
    }

    /// Au lancement de l'app : une Tâche restée « en cours » n'a plus de session derrière elle.
    func markInterruptedRuns() {
        for task in store.tasks where task.claude?.state == .running {
            var trace = task.claude!
            trace.state = .failed
            trace.result = "Interrompue : Maxwell a été fermé pendant que Claude travaillait."
            store.setClaude(trace, for: task.id)
        }
    }

    func isRunning(_ id: TaskID) -> Bool { processes[id] != nil }

    // MARK: - Lancer

    /// Le dossier où Claude travaille sur la Tâche : celui de son Projet, sinon un dossier neutre.
    func folder(for task: TaskItem) -> URL {
        if let folder = store.project(task.projectID)?.folder, FileManager.default.fileExists(atPath: folder) {
            return URL(fileURLWithPath: folder, isDirectory: true)
        }
        let neutral = Database.defaultURL.deletingLastPathComponent().appendingPathComponent("Claude", isDirectory: true)
        try? FileManager.default.createDirectory(at: neutral, withIntermediateDirectories: true)
        return neutral
    }

    /// La demande envoyée à Claude : la Tâche telle que Max l'a écrite, puis ce qu'on attend en retour.
    static func prompt(for task: TaskItem, project: Project?, extra: String) -> String {
        var lines = ["Tâche n° \(task.id) de la liste de tâches de Max (Maxwell) : \(task.title)"]
        if let project { lines.append("Projet : \(project.name)") }
        if let deadline = task.deadline { lines.append("Échéance : \(deadline)") }
        if !task.note.isEmpty { lines.append("\nNote :\n\(task.note)") }
        if !task.checklist.isEmpty {
            lines.append("\nChecklist :")
            lines += task.checklist.map { "- [\($0.done ? "x" : " ")] \($0.title)" }
        }
        let extra = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { lines.append("\nPrécision de Max :\n\(extra)") }
        lines.append("""

            Fais ce travail. Personne ne peut te répondre pendant que tu travailles : si une décision \
            revient à Max, ne tranche pas à sa place, arrête-toi et dis laquelle.
            Termine par un compte rendu court, en français : ce qui est fait, ce qui reste, et ce que Max \
            doit vérifier. Ne coche pas la tâche : Max le fera après avoir relu.
            """)
        return lines.joined(separator: "\n")
    }

    /// Lance Claude sur la Tâche. `extra` est une précision tapée par Max au moment de lancer.
    func start(_ id: TaskID, extra: String = "", autonomy: ClaudeAutonomy = .current, model: ClaudeModel = .current) {
        guard let task = store.task(id), processes[id] == nil else { return }
        let session = UUID().uuidString.lowercased()
        guard let claude = Self.claudePath() else {
            store.setClaude(ClaudeTrace(startedAt: Date(), session: session, state: .failed,
                                        result: "Claude Code est introuvable sur ce Mac (commande `claude`)."), for: id)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claude)
        process.currentDirectoryURL = folder(for: task)
        var arguments = ["-p", Self.prompt(for: task, project: store.project(task.projectID), extra: extra),
                         "--output-format", "stream-json", "--verbose",
                         "--session-id", session,
                         "--permission-mode", autonomy.rawValue]
        // Claude retrouve les Tâches et le Récap de Maxwell pendant qu'il travaille.
        if let maxwell = Bundle.main.executablePath, URL(fileURLWithPath: maxwell).lastPathComponent == "Maxwell" {
            let config = ["mcpServers": ["maxwell": ["command": maxwell, "args": ["--mcp"]]]]
            arguments += ["--mcp-config", MCPServer.encode(config)]
        }
        process.arguments = Self.arguments(arguments, model: model, name: task.title)
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = Self.shellPath
        process.environment = environment

        let output = Pipe(), errorOutput = Pipe()
        process.standardOutput = output
        process.standardError = errorOutput
        process.standardInput = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in self?.receive(data, for: id) }
        }
        errorOutput.fileHandleForReading.readabilityHandler = { handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            guard !text.isEmpty else { return }
            Task { @MainActor [weak self] in self?.errors[id, default: ""] += text }
        }
        process.terminationHandler = { finished in
            let status = finished.terminationStatus
            Task { @MainActor [weak self] in self?.finished(id, status: status) }
        }

        do {
            try process.run()
        } catch {
            store.setClaude(ClaudeTrace(startedAt: Date(), session: session, state: .failed,
                                        result: "Impossible de lancer Claude : \(error.localizedDescription)"), for: id)
            return
        }
        processes[id] = process
        buffers[id] = Data()
        errors[id] = ""
        activity[id] = "démarre…"
        store.setClaude(ClaudeTrace(startedAt: Date(), session: session, state: .running, result: nil), for: id)
    }

    /// Les arguments complétés du modèle choisi, et du nom sous lequel la session apparaît dans `claude --resume`.
    static func arguments(_ base: [String], model: ClaudeModel, name: String) -> [String] {
        base + (model.alias.map { ["--model", $0] } ?? []) + ["--name", String(name.prefix(60))]
    }

    func stop(_ id: TaskID) {
        guard let process = processes[id] else { return }
        errors[id] = "Arrêtée par Max."
        process.terminate()
    }

    // MARK: - Suivre

    private func receive(_ data: Data, for id: TaskID) {
        buffers[id, default: Data()].append(data)
        // Une ligne par message ; la dernière peut être incomplète.
        while let newline = buffers[id]?.firstIndex(of: 0x0A) {
            let line = buffers[id]!.prefix(upTo: newline)
            buffers[id]!.removeSubrange(...newline)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            handle(message, for: id)
        }
    }

    private func handle(_ message: [String: Any], for id: TaskID) {
        switch message["type"] as? String {
        case "assistant":
            let content = (message["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            for block in content {
                if let step = Self.describe(block) { activity[id] = step }
            }
        case "result":
            guard var trace = store.task(id)?.claude else { return }
            let failed = message["is_error"] as? Bool ?? false
            trace.state = failed ? .failed : .done
            trace.result = (message["result"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            store.setClaude(trace, for: id)
        default:
            break
        }
    }

    /// Une étape du travail de Claude en quelques mots, ou nil si le bloc n'en dit rien.
    static func describe(_ block: [String: Any]) -> String? {
        switch block["type"] as? String {
        case "text":
            let text = (block["text"] as? String ?? "").split(separator: "\n").first.map(String.init) ?? ""
            return text.isEmpty ? nil : String(text.prefix(90))
        case "tool_use":
            let name = block["name"] as? String ?? "outil"
            let input = block["input"] as? [String: Any] ?? [:]
            let detail = (input["file_path"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
                ?? input["command"] as? String ?? input["pattern"] as? String ?? input["description"] as? String
            return detail.map { "\(name) \($0.prefix(70))" } ?? name
        default:
            return nil
        }
    }

    private func finished(_ id: TaskID, status: Int32) {
        processes[id] = nil
        buffers[id] = nil
        activity[id] = nil
        let error = errors.removeValue(forKey: id) ?? ""
        // Sans message « result », la session s'est arrêtée avant de conclure.
        guard var trace = store.task(id)?.claude, trace.state == .running else { return }
        trace.state = .failed
        let detail = error.trimmingCharacters(in: .whitespacesAndNewlines)
        trace.result = detail.isEmpty ? "Claude s'est arrêté sans compte rendu (code \(status))." : String(detail.suffix(600))
        store.setClaude(trace, for: id)
    }

    // MARK: - Reprendre

    /// La commande qui rouvre la session dans un terminal, pour continuer avec Claude à la main.
    func resumeCommand(for task: TaskItem) -> String? {
        guard let session = task.claude?.session else { return nil }
        let folder = folder(for: task).path.replacingOccurrences(of: "'", with: "'\\''")
        return "cd '\(folder)' && claude --resume \(session)"
    }

    /// Ghostty, s'il est installé : c'est le terminal de Max.
    static var ghostty: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty")
    }

    /// Ce qu'il faut lancer pour ouvrir Ghostty sur la commande : une nouvelle fenêtre dont le shell de Max,
    /// en mode connexion pour avoir son PATH, exécute la commande. Le `cd` est dans la commande elle-même :
    /// le shell de Max peut changer de dossier à son démarrage.
    static func ghosttyArguments(app: URL, command: String, shell: String) -> [String] {
        ["-na", app.path, "--args", "-e", shell, "-lic", command]
    }

    /// Rouvre la session dans le terminal, pour continuer avec Claude à la main : Ghostty s'il est là,
    /// sinon Terminal. La commande est aussi copiée, pour la coller ailleurs.
    func resume(_ task: TaskItem) {
        guard let command = resumeCommand(for: task) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)

        if let ghostty = Self.ghostty {
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = Self.ghosttyArguments(
                app: ghostty, command: command,
                shell: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
            if (try? open.run()) != nil { return }
        }
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"Terminal\"\nactivate\ndo script \"\(escaped)\"\nend tell"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }

    // MARK: - Ouvrir dans Claude Desktop

    /// Claude Desktop, s'il est installé.
    static var desktop: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop")
    }

    /// Ce qu'il faut lancer pour confier la session à Claude Desktop, où elle rejoint la liste des sessions.
    /// `claude --desktop` refuse de tourner sans terminal : `script` lui en prête un.
    static func desktopArguments(claude: String, session: String) -> [String] {
        ["-q", "/dev/null", claude, "--desktop", "--resume", session]
    }

    /// Ouvre la session dans Claude Desktop, une fois que Claude a fini : une session ne tourne qu'à un endroit.
    /// La commande part du dossier de la Tâche, où Claude Code range la session.
    func openInDesktop(_ task: TaskItem) {
        guard let session = task.claude?.session, task.claude?.state != .running,
              let claude = Self.claudePath() else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        process.arguments = Self.desktopArguments(claude: claude, session: session)
        process.currentDirectoryURL = folder(for: task)
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = Self.shellPath
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        // Dans le terminal prêté, les erreurs arrivent sur la sortie standard.
        let errors = Pipe()
        process.standardOutput = errors
        process.standardError = errors
        process.terminationHandler = { finished in
            guard finished.terminationStatus != 0 else { return }
            let detail = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in
                let alert = NSAlert()
                alert.messageText = "Claude Desktop n'a pas pu ouvrir la session"
                alert.informativeText = detail.isEmpty ? "Code \(finished.terminationStatus)." : String(detail.suffix(400))
                alert.runModal()
            }
        }
        try? process.run()
    }

    // MARK: - Trouver Claude

    static func claudePath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Le PATH du terminal de Max : une app lancée depuis le Finder n'a pas git, swift ou npm dans le sien.
    static let shellPath: String = {
        let fallback = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        process.arguments = ["-lc", "printf %s \"$PATH\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return fallback }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? fallback : path
    }()
}
