import Foundation
import Testing
@testable import Maxwell

@MainActor
@Suite("Pont avec Claude")
final class ClaudeBridgeTests {
    private let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClaudeBridgeTests-\(UUID().uuidString).sqlite")
    private let db: Database
    private let store: TaskStore
    private let navigation = TaskNavigation()

    init() throws {
        db = try Database(url: url)
        store = TaskStore(db: db)
    }

    deinit {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func call(_ server: MCPServer, _ method: String, _ params: [String: Any] = [:]) throws -> [String: Any] {
        let request = MCPServer.encode(["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
        let reply = try #require(server.handle(line: request))
        return try #require(JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
    }

    private func tool(_ server: MCPServer, _ name: String, _ arguments: [String: Any] = [:]) throws -> (text: String, isError: Bool) {
        let reply = try call(server, "tools/call", ["name": name, "arguments": arguments])
        let result = try #require(reply["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        return (content.first?["text"] as? String ?? "", result["isError"] as? Bool ?? false)
    }

    // MARK: - Projets et dossiers

    @Test func aProjectKeepsItsFolder() throws {
        let project = store.projectNamed("Maxwell")
        store.setProjectFolder(project.id, to: "/Users/max/Maxwell")
        #expect(TaskStore(db: try Database(url: url)).projects.first?.folder == "/Users/max/Maxwell")
    }

    @Test func pFilesTheChosenTaskUnderAProject() {
        let ventes = store.projectNamed("Ventes")
        store.projectNamed("Maxwell")
        let task = store.add(text: "Devis", in: .today)!
        navigation.handle(.down, store: store)
        navigation.handle(.character("p"), store: store)
        #expect(navigation.pickerOptions(in: store).count == 2)
        navigation.picker?.query = "ven"
        // Le Projet qui correspond d'abord, puis la création de ce qui est tapé.
        #expect(navigation.pickerOptions(in: store) == [.project(ventes), .create("ven")])
        navigation.applyPicker(store: store)
        #expect(store.task(task.id)?.projectID == ventes.id)
        #expect(navigation.picker == nil)
    }

    @Test func thePickerCanCreateAProjectOrRemoveIt() {
        let task = store.add(text: "Devis #Ventes", in: .today)!
        navigation.picker = .init(taskID: task.id, query: "Nouveau client")
        #expect(navigation.pickerOptions(in: store) == [.create("Nouveau client")])
        navigation.applyPicker(store: store)
        #expect(store.project(store.task(task.id)?.projectID)?.name == "Nouveau client")

        navigation.picker = .init(taskID: task.id)
        #expect(navigation.pickerOptions(in: store).last == TaskNavigation.PickerOption.none)
        navigation.picker?.index = navigation.pickerOptions(in: store).count - 1
        navigation.applyPicker(store: store)
        #expect(store.task(task.id)?.projectID == nil)
    }

    // MARK: - Confier une Tâche

    @Test func thePromptCarriesTheTaskAsMaxWroteIt() {
        let project = store.projectNamed("Maxwell")
        var task = store.add(text: "Corriger le bip #Maxwell", in: .today)!
        task.note = "Voir le fil https://exemple.slack.com/x"
        task.checklist = [ChecklistItem(title: "Reproduire", done: true), ChecklistItem(title: "Corriger")]
        let prompt = ClaudeRunner.prompt(for: task, project: project, extra: "  sans toucher aux tests ")
        #expect(prompt.hasPrefix("Tâche n° \(task.id) de la liste de tâches de Max (Maxwell) : Corriger le bip"))
        #expect(prompt.contains("Projet : Maxwell"))
        #expect(prompt.contains("https://exemple.slack.com/x"))
        #expect(prompt.contains("- [x] Reproduire\n- [ ] Corriger"))
        #expect(prompt.contains("Précision de Max :\nsans toucher aux tests"))
        #expect(prompt.contains("Ne coche pas la tâche"))
    }

    @Test func cAsksBeforeLaunching() {
        let task = store.add(text: "Corriger le bip", in: .today)!
        navigation.handle(.down, store: store)
        #expect(navigation.handle(.character("c"), store: store))
        #expect(navigation.launcher?.taskID == task.id)
        #expect(store.task(task.id)?.claude == nil)
    }

    @Test func claudesProgressSurvivesEditsAndIsNotUndone() {
        let task = store.add(text: "Corriger le bip", in: .today)!
        let trace = ClaudeTrace(startedAt: Date(timeIntervalSince1970: 1_795_000_000), session: "abc",
                                state: .done, result: "Fait.")
        store.setClaude(trace, for: task.id)
        // Une Tâche dépliée enregistre sa copie, prise avant que Claude finisse.
        var stale = task
        stale.title = "Corriger le bip d'erreur"
        store.update(stale)
        #expect(store.task(task.id)?.claude == trace)
        store.undo()
        #expect(store.task(task.id)?.title == "Corriger le bip")
        #expect(store.task(task.id)?.claude == trace)
    }

    @Test func stepsOfClaudesWorkAreDescribedShortly() {
        #expect(ClaudeRunner.describe(["type": "tool_use", "name": "Edit",
                                       "input": ["file_path": "/Users/max/Maxwell/Sources/Maxwell/Recap.swift"]]) == "Edit Recap.swift")
        #expect(ClaudeRunner.describe(["type": "tool_use", "name": "Bash", "input": ["command": "swift test"]]) == "Bash swift test")
        #expect(ClaudeRunner.describe(["type": "text", "text": "Je regarde le code.\nPuis…"]) == "Je regarde le code.")
        #expect(ClaudeRunner.describe(["type": "thinking", "thinking": ""]) == nil)
    }

    @Test func theChosenModelIsPassedToClaudeAndTabGoesRound() {
        #expect(ClaudeRunner.arguments(["-p", "x"], model: .opus, name: "Corriger le bip")
            == ["-p", "x", "--model", "opus", "--name", "Corriger le bip"])
        // « réglage de Claude » ne passe rien : Claude Code garde le sien.
        #expect(ClaudeRunner.arguments(["-p", "x"], model: .standard, name: "T") == ["-p", "x", "--name", "T"])
        #expect(ClaudeModel.allCases.first == .opus)
        #expect(ClaudeModel.opus.next == .fable)
        #expect(ClaudeModel.standard.next == .opus)
    }

    @Test func resumingGoesToTheProjectFolderThenTheSession() {
        let project = store.projectNamed("Maxwell")
        let folder = FileManager.default.temporaryDirectory.path
        store.setProjectFolder(project.id, to: folder)
        let task = store.add(TaskItem.Draft(title: "Corriger le bip", projectID: project.id))
        store.setClaude(ClaudeTrace(startedAt: Date(), session: "abc-123", state: .done, result: nil), for: task.id)
        let command = ClaudeRunner(store: store).resumeCommand(for: store.task(task.id)!)
        #expect(command == "cd '\(folder)' && claude --resume abc-123")
        // Dans Ghostty : le shell de Max, en mode connexion, exécute cette commande.
        #expect(ClaudeRunner.ghosttyArguments(app: URL(fileURLWithPath: "/Applications/Ghostty.app"),
                                              command: command!, shell: "/bin/zsh")
            == ["-na", "/Applications/Ghostty.app", "--args", "-e", "/bin/zsh", "-lic", command!])
    }

    @Test func claudeDesktopResumesTheSameSession() {
        #expect(ClaudeRunner.desktopArguments(claude: "/bin/claude", session: "abc-123")
            == ["-q", "/dev/null", "/bin/claude", "--desktop", "--resume", "abc-123"])
    }

    // MARK: - Serveur MCP

    @Test func theServerIntroducesItselfAndListsItsTools() throws {
        let server = MCPServer(db: db)
        let hello = try call(server, "initialize", ["protocolVersion": "2025-06-18"])
        #expect(((hello["result"] as? [String: Any])?["serverInfo"] as? [String: Any])?["name"] as? String == "maxwell")
        let list = try call(server, "tools/list")
        let names = ((list["result"] as? [String: Any])?["tools"] as? [[String: Any]])?.compactMap { $0["name"] as? String }
        #expect(names == ["list_tasks", "add_task", "update_task", "complete_task", "annotate_task",
                          "list_projects", "get_time_recap"])
        #expect(server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
    }

    @Test func claudeCanAddAnnotateAndCompleteATask() throws {
        let server = MCPServer(db: db)
        #expect(try !tool(server, "add_task", ["title": "Relancer Paul", "project": "Ventes", "when": "tomorrow"]).isError)
        store.reload()
        let task = try #require(store.tasks.first)
        #expect(store.project(task.projectID)?.name == "Ventes")
        #expect(task.when == .day(store.today.adding(1, .day)))

        #expect(try tool(server, "annotate_task", ["id": task.id, "text": "Mail envoyé."]).text.contains("Mail envoyé."))
        #expect(try !tool(server, "complete_task", ["id": task.id]).isError)
        store.reload()
        #expect(store.task(task.id)?.state == .done)
        #expect(store.task(task.id)?.note.hasSuffix(": Mail envoyé.") == true)
    }

    @Test func toolErrorsGoBackToClaudeAsText() throws {
        let server = MCPServer(db: db)
        let missing = try tool(server, "update_task", ["id": 99, "title": "x"])
        #expect(missing.isError)
        #expect(missing.text == "Aucune tâche n° 99.")
        #expect(try tool(server, "add_task", ["title": "x", "when": "bientôt"]).isError)
    }

    @Test func theTimeRecapIsReadable() throws {
        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3600)
        db.insertSession(bundleID: "com.apple.dt.Xcode", appName: "Xcode", start: start, end: start.addingTimeInterval(1800))
        let recap = try tool(MCPServer(db: db), "get_time_recap", ["period": "day"])
        #expect(!recap.isError)
        let json = try #require(JSONSerialization.jsonObject(with: Data(recap.text.utf8)) as? [String: Any])
        #expect(json["active_minutes"] as? Int == 30)
    }

    @Test func theAppSeesWhatClaudeChanged() throws {
        #expect(!store.reloadIfChangedElsewhere())
        _ = try tool(MCPServer(db: try Database(url: url)), "add_task", ["title": "Venue de Claude"])
        #expect(store.tasks.isEmpty)
        #expect(store.reloadIfChangedElsewhere())
        #expect(store.tasks.map(\.title) == ["Venue de Claude"])
    }
}

/// Lance une vraie session Claude Code, sur un dossier et une base temporaires, en mode « plan ».
/// Coûte une requête : ne tourne que si `MAXWELL_CLAUDE_E2E=1`.
@MainActor
@Suite("Session Claude réelle", .enabled(if: ProcessInfo.processInfo.environment["MAXWELL_CLAUDE_E2E"] == "1"))
struct ClaudeRunnerEndToEndTests {
    @Test(.timeLimit(.minutes(3))) func claudeWorksInTheProjectFolderAndReportsBack() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("maxwell-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "Le mot de passe du jour est : tournesol.".write(to: root.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)

        let store = TaskStore(db: try Database(url: root.appendingPathComponent("test.sqlite")))
        let project = store.projectNamed("Essai")
        store.setProjectFolder(project.id, to: root.path)
        let task = store.add(TaskItem.Draft(title: "Lis note.txt et donne le mot de passe du jour", projectID: project.id))

        let runner = ClaudeRunner(store: store)
        runner.start(task.id, autonomy: .plan, model: .haiku)
        #expect(store.task(task.id)?.claude?.state == .running)
        while store.task(task.id)?.claude?.state == .running {
            try await Task.sleep(for: .milliseconds(300))
        }
        let trace = try #require(store.task(task.id)?.claude)
        #expect(trace.state == .done)
        #expect(trace.result?.lowercased().contains("tournesol") == true)
        // Le processus se ferme un instant après avoir rendu son compte rendu.
        for _ in 0..<50 where runner.isRunning(task.id) { try await Task.sleep(for: .milliseconds(200)) }
        #expect(!runner.isRunning(task.id))
        #expect(runner.activity[task.id] == nil)
    }
}
