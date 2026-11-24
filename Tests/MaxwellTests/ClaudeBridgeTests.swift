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
        #expect(command == "cd '\(folder)' && { claude attach abc-123 || claude --resume abc-123; }")
        // Dans Ghostty : le shell de Max, en mode connexion, exécute cette commande.
        #expect(ClaudeRunner.ghosttyArguments(app: URL(fileURLWithPath: "/Applications/Ghostty.app"),
                                              command: command!, shell: "/bin/zsh")
            == ["-na", "/Applications/Ghostty.app", "--args", "-e", "/bin/zsh", "-lic", command!])
    }

    @Test func launchedProcessesDropAnInheritedClaudeSession() {
        let environment = ClaudeRunner.environment(from: [
            "HOME": "/Users/max", "CLAUDECODE": "1", "CLAUDE_CODE_CHILD_SESSION": "1",
            "AI_AGENT": "claude-code", "PATH": "/usr/bin",
        ])
        #expect(environment["HOME"] == "/Users/max")
        #expect(environment["CLAUDECODE"] == nil)
        #expect(environment["CLAUDE_CODE_CHILD_SESSION"] == nil)
        #expect(environment["AI_AGENT"] == nil)
        #expect(environment["PATH"] == ClaudeRunner.shellPath)
    }

    @Test func claudeDesktopResumesTheSameSession() {
        #expect(ClaudeRunner.desktopArguments(claude: "/bin/claude", session: "abc-123")
            == ["-q", "/dev/null", "/bin/claude", "--desktop", "--resume", "abc-123"])
    }

    // MARK: - Sessions d'arrière-plan

    @Test func readsTheIdThatClaudeBgPrints() {
        let output = """
            backgrounded · c6d4072b · Corriger le bip
              claude agents             list sessions
            """
        #expect(ClaudeRunner.backgroundID(in: output) == "c6d4072b")
        #expect(ClaudeRunner.backgroundID(in: "Workspace not trusted.") == nil)
        #expect(ClaudeRunner.launchFailure("Workspace not trusted. Run `claude` in /x once").hasPrefix("Claude Code ne connaît pas"))
        #expect(ClaudeRunner.shortID("c6d4072b-8efc-4191-bdc6-72f506799180") == "c6d4072b")
    }

    @Test func readsTheSessionsOfClaudeAgents() throws {
        let json = """
            [{"pid":1,"cwd":"/x","kind":"interactive","sessionId":"aaa","status":"busy"},
             {"id":"c6d4072b","kind":"background","sessionId":"c6d4072b-8efc","status":"idle","state":"done"},
             {"id":"0fe872f3","kind":"background","sessionId":"0fe872f3-7527","state":"stopped"}]
            """
        let agents = try #require(ClaudeRunner.parseAgents(Data(json.utf8)))
        #expect(agents["c6d4072b-8efc"] == ClaudeRunner.Agent(status: "idle", state: "done"))
        #expect(agents["0fe872f3-7527"] == ClaudeRunner.Agent(status: nil, state: "stopped"))
        #expect(agents.count == 3)
    }

    private func line(_ object: [String: Any]) -> String {
        MCPServer.encode(object)
    }

    @Test func readsTheConversationClaudeCodeSaves() {
        let request = line(["type": "user", "message": ["role": "user", "content": "Corrige le bip"]])
        let tool = line(["type": "assistant", "message": ["content": [
            ["type": "text", "text": "Je regarde."],
            ["type": "tool_use", "name": "Edit", "input": ["file_path": "/x/Recap.swift"]]]]])
        let toolResult = line(["type": "user", "message": ["content": [["type": "tool_result", "content": "ok"]]]])
        let answer = line(["type": "assistant", "message": ["content": [["type": "text", "text": "C'est corrigé."]]]])
        let sidechain = line(["type": "assistant", "isSidechain": true, "message": ["content": [["type": "text", "text": "sous-agent"]]]])

        let working = ClaudeRunner.summarize(Data([request, tool, toolResult].joined(separator: "\n").utf8))
        #expect(working == ClaudeRunner.Transcript(lastText: "Je regarde.", lastStep: "Edit Recap.swift", answered: false))

        let finished = ClaudeRunner.summarize(Data([request, tool, toolResult, answer, sidechain].joined(separator: "\n").utf8))
        #expect(finished.answered)
        #expect(finished.lastText == "C'est corrigé.")

        // Max relance la conversation : la réponse précédente ne compte plus.
        let again = ClaudeRunner.summarize(Data([request, answer, request].joined(separator: "\n").utf8))
        #expect(again == ClaudeRunner.Transcript())
    }

    @Test func followsTheSessionState() {
        let running = ClaudeTrace(startedAt: Date(), session: "s", state: .running, result: nil)
        let working = ClaudeRunner.Transcript(lastText: "Je regarde.", lastStep: "Edit Recap.swift", answered: false)
        let answered = ClaudeRunner.Transcript(lastText: "C'est corrigé.", lastStep: "C'est corrigé.", answered: true)
        let busy = ClaudeRunner.Agent(status: "busy", state: "working")
        let idle = ClaudeRunner.Agent(status: "idle", state: "working")

        // Claude travaille : on montre l'étape.
        var (trace, step) = ClaudeRunner.reconcile(running, agent: busy, transcript: working, stopping: false)
        #expect(trace.state == .running && step == "Edit Recap.swift")
        // Il a répondu et attend : c'est fait, avec son compte rendu.
        (trace, step) = ClaudeRunner.reconcile(running, agent: idle, transcript: answered, stopping: false)
        #expect(trace.state == .done && trace.result == "C'est corrigé." && step == nil)
        // Au démarrage, la session est inactive avant d'avoir lu la demande : toujours en cours.
        (trace, step) = ClaudeRunner.reconcile(running, agent: idle, transcript: nil, stopping: false)
        #expect(trace.state == .running && step == "démarre…")
        // Max reprend une session finie dans claude agents : elle repasse en cours.
        let done = ClaudeTrace(startedAt: Date(), session: "s", state: .done, result: "C'est corrigé.")
        (trace, _) = ClaudeRunner.reconcile(done, agent: busy, transcript: working, stopping: false)
        #expect(trace.state == .running)
        // Arrêtée par Max.
        (trace, _) = ClaudeRunner.reconcile(running, agent: ClaudeRunner.Agent(status: nil, state: "stopped"),
                                            transcript: working, stopping: true)
        #expect(trace.state == .failed && trace.result?.hasPrefix("Arrêtée par Max.") == true)
        // Disparue sans réponse.
        (trace, _) = ClaudeRunner.reconcile(running, agent: nil, transcript: nil, stopping: false)
        #expect(trace.state == .failed)
        // Une session finie qui ne tourne plus ne change pas.
        (trace, step) = ClaudeRunner.reconcile(done, agent: nil, transcript: answered, stopping: false)
        #expect(trace == done && step == nil)
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

/// Lance une vraie session Claude Code en arrière-plan, en mode « plan » et avec haiku, sur une base temporaire.
/// Elle travaille dans ce dépôt, que Claude Code connaît déjà (`claude --bg` refuse un dossier inconnu),
/// puis est retirée de `claude agents`. Coûte une requête : ne tourne que si `MAXWELL_CLAUDE_E2E=1`.
@MainActor
@Suite("Session Claude réelle", .enabled(if: ProcessInfo.processInfo.environment["MAXWELL_CLAUDE_E2E"] == "1"))
struct ClaudeRunnerEndToEndTests {
    @Test(.timeLimit(.minutes(3))) func claudeWorksInTheProjectFolderAndReportsBack() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let database = FileManager.default.temporaryDirectory.appendingPathComponent("maxwell-e2e-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: database) }

        let store = TaskStore(db: try Database(url: database))
        let project = store.projectNamed("Essai")
        store.setProjectFolder(project.id, to: repository.path)
        let task = store.add(TaskItem.Draft(title: "Lis Package.swift et donne seulement le nom du package", projectID: project.id))

        let runner = ClaudeRunner(store: store)
        runner.start(task.id, autonomy: .plan, model: .haiku)
        #expect(store.task(task.id)?.claude?.state == .running)
        while store.task(task.id)?.claude?.state == .running {
            try await Task.sleep(for: .seconds(2))
            runner.poll(force: true)
        }
        let trace = try #require(store.task(task.id)?.claude)
        defer {
            if let claude = ClaudeRunner.claudePath() {
                _ = ClaudeRunner.run(claude, ["stop", ClaudeRunner.shortID(trace.session)], in: nil)
                _ = ClaudeRunner.run(claude, ["rm", ClaudeRunner.shortID(trace.session)], in: nil)
            }
        }
        #expect(trace.state == .done, "\(trace.result ?? "")")
        #expect(trace.result?.contains("Maxwell") == true)
        #expect(runner.activity[task.id] == nil)
    }
}
