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

/// Lance Claude Code sur une Tâche, dans le dossier de son Projet, en session d'arrière-plan (`claude --bg`) :
/// Max la retrouve dans `claude agents`, où il peut la suivre et lui répondre. Maxwell suit son état
/// avec `claude agents --json` et lit le compte rendu dans la conversation que Claude Code enregistre.
/// La session survit à la fermeture de Maxwell, qui la retrouve au prochain lancement.
@MainActor
final class ClaudeRunner: ObservableObject {
    /// Ce que Claude est en train de faire, par Tâche : « Edit Recap.swift », « Bash swift test »…
    @Published private(set) var activity: [TaskID: String] = [:]

    private let store: TaskStore
    /// Les Tâches dont la session démarre : `claude --bg` n'a pas encore rendu son identifiant.
    private var launching: Set<TaskID> = []
    /// Les Tâches que Max a demandé d'arrêter.
    private var stopping: Set<TaskID> = []
    private var timer: Timer?
    private var polling = false
    private var ticks = 0

    init(store: TaskStore) {
        self.store = store
    }

    /// Au lancement de l'app : marque les lancements interrompus, puis suit les sessions toutes les 3 secondes.
    func follow() {
        for task in store.tasks where task.claude?.state == .running && task.claude?.session.isEmpty == true {
            var trace = task.claude!
            trace.state = .failed
            trace.result = "Interrompue : Maxwell a été fermé pendant que la session démarrait."
            store.setClaude(trace, for: task.id)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
    }

    func isRunning(_ id: TaskID) -> Bool {
        launching.contains(id) || store.task(id)?.claude?.state == .running
    }

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
        var lines = ["Tâche n° \(task.id) de la liste de tâches \(Owner.ofName) (Maxwell) : \(task.title)"]
        if let project { lines.append("Projet : \(project.name)") }
        if let deadline = task.deadline { lines.append("Échéance : \(deadline)") }
        if !task.note.isEmpty { lines.append("\nNote :\n\(task.note)") }
        if !task.checklist.isEmpty {
            lines.append("\nChecklist :")
            lines += task.checklist.map { "- [\($0.done ? "x" : " ")] \($0.title)" }
        }
        let extra = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty { lines.append("\nPrécision \(Owner.ofName) :\n\(extra)") }
        lines.append("""

            Fais ce travail. \(Owner.name) peut suivre cette session dans `claude agents`, sans forcément \
            la regarder : si une décision lui revient, ne tranche pas à sa place, arrête-toi et dis laquelle.
            Termine par un compte rendu court, en français : ce qui est fait, ce qui reste, et ce que \(Owner.name) \
            doit vérifier. Ne coche pas la tâche : \(Owner.name) le fera après avoir relu.
            """)
        return lines.joined(separator: "\n")
    }

    /// Lance Claude sur la Tâche. `extra` est une précision tapée par Max au moment de lancer.
    func start(_ id: TaskID, extra: String = "", autonomy: ClaudeAutonomy = .current, model: ClaudeModel = .current) {
        guard let task = store.task(id), !isRunning(id) else { return }
        guard let claude = Self.claudePath() else {
            store.setClaude(ClaudeTrace(startedAt: Date(), session: "", state: .failed,
                                        result: "Claude Code est introuvable sur ce Mac (commande `claude`)."), for: id)
            return
        }
        var arguments = ["--bg", Self.prompt(for: task, project: store.project(task.projectID), extra: extra),
                         "--permission-mode", autonomy.rawValue]
        // Claude retrouve les Tâches et le Récap de Maxwell pendant qu'il travaille.
        if let maxwell = Bundle.main.executablePath, URL(fileURLWithPath: maxwell).lastPathComponent == "Maxwell" {
            let config = ["mcpServers": ["maxwell": ["command": maxwell, "args": ["--mcp"]]]]
            arguments += ["--mcp-config", MCPServer.encode(config)]
        }
        arguments = Self.arguments(arguments, model: model, name: task.title)
        let folder = folder(for: task)

        launching.insert(id)
        activity[id] = "démarre…"
        store.setClaude(ClaudeTrace(startedAt: Date(), session: "", state: .running, result: nil), for: id)
        Task.detached {
            let launch = ClaudeRunner.run(claude, arguments, in: folder)
            var session: String?
            if let short = ClaudeRunner.backgroundID(in: launch.output) {
                // La liste de `claude agents` donne l'identifiant complet de la session.
                for _ in 0..<10 where session == nil {
                    session = ClaudeRunner.agents()?.keys.first { $0.hasPrefix(short) }
                    if session == nil { try? await Task.sleep(for: .milliseconds(500)) }
                }
            }
            let found = session
            await MainActor.run { [weak self] in self?.launched(id, session: found, output: launch.output) }
        }
    }

    private func launched(_ id: TaskID, session: String?, output: String) {
        launching.remove(id)
        guard var trace = store.task(id)?.claude else { return }
        if let session {
            trace.session = session
            store.setClaude(trace, for: id)
        } else {
            activity[id] = nil
            trace.state = .failed
            trace.result = Self.launchFailure(output)
            store.setClaude(trace, for: id)
        }
    }

    /// Pourquoi `claude --bg` n'a pas lancé de session, dit à Max.
    static func launchFailure(_ output: String) -> String {
        let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.contains("Workspace not trusted") {
            return "Claude Code ne connaît pas encore ce dossier. Lance `claude` une fois dans ce dossier, " +
                "accepte de lui faire confiance, puis relance la tâche.\n\n\(detail)"
        }
        return detail.isEmpty ? "Claude n'a pas démarré." : String(detail.suffix(600))
    }

    /// L'identifiant court que `claude --bg` affiche : « backgrounded · c6d4072b · Le titre ».
    nonisolated static func backgroundID(in output: String) -> String? {
        for line in output.split(separator: "\n") where line.contains("backgrounded") {
            let parts = line.components(separatedBy: " · ")
            if parts.count >= 2 {
                let id = parts[1].trimmingCharacters(in: .whitespaces)
                if !id.isEmpty, id.allSatisfy({ $0.isHexDigit }) { return id }
            }
        }
        return nil
    }

    /// Les arguments complétés du modèle choisi, et du nom sous lequel la session apparaît dans `claude agents`.
    static func arguments(_ base: [String], model: ClaudeModel, name: String) -> [String] {
        base + (model.alias.map { ["--model", $0] } ?? []) + ["--name", String(name.prefix(60))]
    }

    /// Arrête la session ; sa conversation reste, et « relancer » ou le terminal peuvent repartir de là.
    func stop(_ id: TaskID) {
        guard let session = store.task(id)?.claude?.session, !session.isEmpty,
              let claude = Self.claudePath() else { return }
        stopping.insert(id)
        activity[id] = "s'arrête…"
        Task.detached {
            _ = ClaudeRunner.run(claude, ["stop", ClaudeRunner.shortID(session)], in: nil)
            await MainActor.run { [weak self] in self?.poll(force: true) }
        }
    }

    // MARK: - Relier

    /// Une session de `claude agents` que Max peut relier à une Tâche, y compris une session ouverte à la main.
    struct Session: Identifiable, Equatable {
        let id: String
        var name: String
        var folder: String
        var startedAt: Date
        /// La session tourne encore (elle a un statut dans `claude agents`).
        var live: Bool
    }

    /// Les sessions que liste `claude agents`, les plus récentes d'abord.
    nonisolated static func parseSessions(_ data: Data) -> [Session] {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return list.compactMap { entry -> Session? in
            guard let id = entry["sessionId"] as? String else { return nil }
            let folder = entry["cwd"] as? String ?? ""
            let name = (entry["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? URL(fileURLWithPath: folder).lastPathComponent
            let started = (entry["startedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? .distantPast
            return Session(id: id, name: name, folder: folder, startedAt: started, live: entry["status"] != nil)
        }
        .sorted { $0.startedAt > $1.startedAt }
    }

    /// Les sessions qu'on peut relier, lues hors du fil principal.
    func sessions() async -> [Session] {
        await Task.detached {
            guard let claude = ClaudeRunner.claudePath() else { return [] }
            let result = ClaudeRunner.run(claude, ["agents", "--json", "--all"], in: nil, mergeErrors: false)
            return result.status == 0 ? ClaudeRunner.parseSessions(Data(result.output.utf8)) : []
        }.value
    }

    /// Relie une session existante à la Tâche : Maxwell la suit ensuite comme s'il l'avait lancée.
    /// La Tâche n'est pas cochée quand la session finit : c'est à Max de le faire après relecture.
    func link(_ id: TaskID, session: String) {
        guard store.task(id) != nil, !launching.contains(id) else { return }
        stopping.remove(id)
        activity[id] = nil
        store.setClaude(ClaudeTrace(startedAt: Date(), session: session, state: .running, result: nil), for: id)
        poll(force: true)
    }

    /// Détache la session de la Tâche, sans l'arrêter.
    func unlink(_ id: TaskID) {
        guard !launching.contains(id) else { return }
        stopping.remove(id)
        activity[id] = nil
        store.setClaude(nil, for: id)
    }

    /// Le dossier où la session a été ouverte, d'après sa conversation : une session reliée à la main
    /// ne tourne pas forcément dans le dossier du Projet, et `claude --resume` doit partir du bon dossier.
    nonisolated static func folder(in transcript: Data) -> String? {
        for line in transcript.split(separator: 0x0A).reversed() {
            if let entry = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
               let cwd = entry["cwd"] as? String, !cwd.isEmpty {
                return cwd
            }
        }
        return nil
    }

    /// Le dossier de la session, sinon celui de la Tâche.
    func sessionFolder(for task: TaskItem) -> URL {
        if let session = task.claude?.session, !session.isEmpty,
           let cwd = Self.transcriptURL(session: session).flatMap(Self.tail).flatMap(Self.folder(in:)),
           FileManager.default.fileExists(atPath: cwd) {
            return URL(fileURLWithPath: cwd, isDirectory: true)
        }
        return folder(for: task)
    }

    /// L'identifiant court d'une session, celui que prennent `claude attach` et `claude stop`.
    nonisolated static func shortID(_ session: String) -> String { String(session.prefix(8)) }

    // MARK: - Suivre

    /// L'état d'une session dans `claude agents` : `busy` pendant que Claude travaille, `idle` quand il attend.
    struct Agent: Equatable {
        var status: String?
        var state: String?
    }

    /// Ce que dit la fin de la conversation enregistrée.
    struct Transcript: Equatable {
        /// Le dernier texte de Claude depuis la dernière demande.
        var lastText: String?
        /// La dernière étape, en quelques mots.
        var lastStep: String?
        /// Claude a répondu à la dernière demande et n'attend le résultat d'aucun outil.
        var answered = false
    }

    func poll(force: Bool = false) {
        guard !polling else { return }
        ticks += 1
        let traced = store.tasks.filter { $0.claude.map { !$0.session.isEmpty } ?? false }
        let running = traced.filter { $0.claude?.state == .running }
        // Max peut reprendre une session finie dans `claude agents` : on revoit les récentes de temps en temps.
        let recent = traced.filter { $0.claude!.startedAt > Date().addingTimeInterval(-3 * 86400) }
        guard force || !running.isEmpty || (ticks % 7 == 0 && !recent.isEmpty) else { return }
        let watched = Array(Set(running + recent))
        guard !watched.isEmpty, let claude = Self.claudePath() else { return }
        let sessions = watched.map { ($0.id, $0.claude!.session) }

        polling = true
        Task.detached {
            let agents = ClaudeRunner.agents(claude: claude)
            var transcripts: [String: Transcript] = [:]
            for (_, session) in sessions {
                if let data = ClaudeRunner.transcriptURL(session: session).flatMap(ClaudeRunner.tail) {
                    transcripts[session] = ClaudeRunner.summarize(data)
                }
            }
            let summaries = transcripts
            await MainActor.run { [weak self] in
                self?.polling = false
                guard let agents else { return }
                self?.update(sessions.map(\.0), agents: agents, transcripts: summaries)
            }
        }
    }

    private func update(_ ids: [TaskID], agents: [String: Agent], transcripts: [String: Transcript]) {
        for id in ids where !launching.contains(id) {
            guard let trace = store.task(id)?.claude, !trace.session.isEmpty else { continue }
            let (next, step) = Self.reconcile(trace, agent: agents[trace.session],
                                              transcript: transcripts[trace.session], stopping: stopping.contains(id))
            activity[id] = step
            if next != trace { store.setClaude(next, for: id) }
            if next.state != .running { stopping.remove(id) }
        }
    }

    /// La trace mise à jour d'après la session, et l'étape à afficher pendant qu'elle travaille.
    static func reconcile(_ trace: ClaudeTrace, agent: Agent?, transcript: Transcript?,
                          stopping: Bool) -> (ClaudeTrace, String?) {
        var next = trace
        let step = transcript?.lastStep ?? "démarre…"
        func done() {
            next.state = .done
            next.result = transcript?.lastText
        }
        switch agent?.status {
        case "busy":
            next.state = .running
            return (next, stopping ? "s'arrête…" : step)
        case "idle":
            if transcript?.answered == true {
                done()
                return (next, nil)
            }
            // Pas encore de réponse : la session démarre, ou attend Max.
            guard trace.state == .running else { return (next, nil) }
            if let state = agent?.state?.lowercased(), ["input", "wait", "permission", "block"].contains(where: state.contains) {
                return (next, "attend ta réponse dans claude agents")
            }
            return (next, step)
        case let status?:
            next.state = .running
            return (next, "\(status) · attend peut-être ta réponse dans claude agents")
        case nil:
            // La session ne tourne plus.
            guard trace.state == .running else { return (next, nil) }
            if stopping {
                next.state = .failed
                next.result = ["Arrêtée depuis Maxwell.", transcript?.lastText].compactMap { $0 }.joined(separator: "\n\n")
            } else if transcript?.answered == true {
                done()
            } else {
                next.state = .failed
                next.result = transcript?.lastText ?? "La session s'est arrêtée sans compte rendu."
            }
            return (next, nil)
        }
    }

    /// Les sessions que liste `claude agents`, par identifiant complet ; nil si la commande échoue.
    nonisolated static func agents(claude: String? = nil) -> [String: Agent]? {
        guard let claude = claude ?? claudePath() else { return nil }
        let result = run(claude, ["agents", "--json", "--all"], in: nil, mergeErrors: false)
        guard result.status == 0 else { return nil }
        return parseAgents(Data(result.output.utf8))
    }

    nonisolated static func parseAgents(_ data: Data) -> [String: Agent]? {
        guard let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        var agents: [String: Agent] = [:]
        for entry in list {
            guard let session = entry["sessionId"] as? String else { continue }
            agents[session] = Agent(status: entry["status"] as? String, state: entry["state"] as? String)
        }
        return agents
    }

    /// La conversation enregistrée par Claude Code, rangée sous `~/.claude/projects/<dossier>/`.
    nonisolated static func transcriptURL(session: String) -> URL? {
        let projects = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let folders = (try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
        return folders.lazy.map { $0.appendingPathComponent("\(session).jsonl") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// La fin du fichier : la conversation peut peser plusieurs mégaoctets.
    nonisolated static func tail(_ url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > 400_000 ? size - 400_000 : 0
        try? handle.seek(toOffset: start)
        var data = handle.readDataToEndOfFile()
        // La première ligne est sans doute coupée.
        if start > 0, let newline = data.firstIndex(of: 0x0A) { data = Data(data[data.index(after: newline)...]) }
        return data
    }

    /// Lit la conversation : le dernier texte de Claude, sa dernière étape, et s'il a fini de répondre.
    nonisolated static func summarize(_ data: Data) -> Transcript {
        var transcript = Transcript()
        for line in data.split(separator: 0x0A) {
            guard let entry = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  entry["isSidechain"] as? Bool != true,
                  let message = entry["message"] as? [String: Any] else { continue }
            switch entry["type"] as? String {
            case "user":
                // Une nouvelle demande, pas le résultat d'un outil : la réponse est à venir.
                let content = message["content"]
                let isRequest = content is String
                    || (content as? [[String: Any]])?.contains { $0["type"] as? String == "text" } == true
                if isRequest {
                    transcript = Transcript()
                }
            case "assistant":
                let blocks = message["content"] as? [[String: Any]] ?? []
                var usesTool = false
                for block in blocks {
                    if let step = describe(block) { transcript.lastStep = step }
                    switch block["type"] as? String {
                    case "text":
                        let text = (block["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty { transcript.lastText = text }
                    case "tool_use":
                        usesTool = true
                    default:
                        break
                    }
                }
                if usesTool { transcript.answered = false }
                else if blocks.contains(where: { $0["type"] as? String == "text" }) { transcript.answered = transcript.lastText != nil }
            default:
                break
            }
        }
        return transcript
    }

    /// Une étape du travail de Claude en quelques mots, ou nil si le bloc n'en dit rien.
    nonisolated static func describe(_ block: [String: Any]) -> String? {
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

    /// Lance une commande et attend sa fin. La sortie passe par un fichier : une session `--bg` qui
    /// garderait la sortie ouverte bloquerait la lecture d'un tuyau.
    nonisolated static func run(_ executable: String, _ arguments: [String], in folder: URL?,
                                mergeErrors: Bool = true) -> (status: Int32, output: String) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("maxwell-claude-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: file) }
        guard let output = try? FileHandle(forWritingTo: file) else { return (-1, "") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let folder { process.currentDirectoryURL = folder }
        process.environment = environment()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = mergeErrors ? output : FileHandle.nullDevice
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        process.waitUntilExit()
        try? output.close()
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        return (process.terminationStatus, text)
    }

    // MARK: - Reprendre

    /// La commande qui ouvre la session dans un terminal : `claude attach` pour une session d'arrière-plan,
    /// sinon `claude --resume` (les sessions lancées par d'anciennes versions de Maxwell).
    func resumeCommand(for task: TaskItem) -> String? {
        guard let session = task.claude?.session, !session.isEmpty else { return nil }
        let folder = sessionFolder(for: task).path.replacingOccurrences(of: "'", with: "'\\''")
        return "cd '\(folder)' && { claude attach \(Self.shortID(session)) || claude --resume \(session); }"
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

    /// Ouvre la session dans le terminal : Ghostty s'il est là, sinon Terminal.
    /// La commande est aussi copiée, pour la coller ailleurs.
    func resume(_ task: TaskItem) {
        guard let command = resumeCommand(for: task) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)

        if let ghostty = Self.ghostty {
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.environment = Self.environment()
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
    nonisolated static func desktopArguments(claude: String, session: String) -> [String] {
        ["-q", "/dev/null", claude, "--desktop", "--resume", session]
    }

    /// Ouvre la session dans Claude Desktop, une fois que Claude a fini. Une session ne tourne qu'à un endroit :
    /// Maxwell l'arrête d'abord dans `claude agents`, où elle attend sinon la suite.
    func openInDesktop(_ task: TaskItem) {
        guard let session = task.claude?.session, !session.isEmpty, task.claude?.state != .running,
              let claude = Self.claudePath() else { return }
        let folder = sessionFolder(for: task)
        Task.detached {
            _ = ClaudeRunner.run(claude, ["stop", ClaudeRunner.shortID(session)], in: nil)
            let result = ClaudeRunner.run("/usr/bin/script",
                                          ClaudeRunner.desktopArguments(claude: claude, session: session), in: folder)
            guard result.status != 0 else { return }
            let detail = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = "Claude Desktop n'a pas pu ouvrir la session"
                alert.informativeText = detail.isEmpty ? "Code \(result.status)." : String(detail.suffix(400))
                alert.runModal()
            }
        }
    }

    /// L'environnement des processus que Maxwell lance : le PATH du terminal de Max, sans les variables
    /// d'une session Claude Code dont Maxwell aurait hérité (s'il a été lancé depuis l'une d'elles).
    /// Sinon Claude se croirait une session enfant et n'enregistrerait pas la conversation.
    nonisolated static func environment(from inherited: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = inherited.filter { key, _ in
            !key.hasPrefix("CLAUDE") && !key.hasPrefix("AI_AGENT") && key != "BAGGAGE"
        }
        environment["PATH"] = shellPath
        return environment
    }

    // MARK: - Trouver Claude

    nonisolated static func claudePath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Le PATH du terminal de Max : une app lancée depuis le Finder n'a pas git, swift ou npm dans le sien.
    nonisolated static let shellPath: String = {
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
