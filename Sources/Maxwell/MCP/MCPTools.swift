import Foundation

/// Les outils que Maxwell offre à Claude : lire et changer les Tâches, lire le Récap.
@MainActor
final class MCPTools {
    private let db: Database
    private let store: TaskStore
    private let clock: () -> Date

    init(db: Database, calendar: Calendar = .current, clock: @escaping () -> Date = Date.init) {
        self.db = db
        self.clock = clock
        store = TaskStore(db: db, calendar: calendar, clock: clock)
    }

    func call(_ name: String, _ arguments: [String: Any]) throws -> Any {
        // L'app a pu changer la base depuis le dernier appel.
        store.reload()
        switch name {
        case "list_tasks": return try listTasks(arguments)
        case "add_task": return try addTask(arguments)
        case "update_task": return try updateTask(arguments)
        case "complete_task": return try completeTask(arguments)
        case "annotate_task": return try annotateTask(arguments)
        case "list_projects": return listProjects()
        case "get_time_recap": return try timeRecap(arguments)
        default: throw MCPError("Outil inconnu : \(name)")
        }
    }

    // MARK: - Description des outils

    static let definitions: [[String: Any]] = [
        tool("list_tasks", "Liste les tâches \(Owner.ofName). Sans argument : celles d'aujourd'hui.", [
            "list": ["type": "string", "enum": ["today", "upcoming", "inbox", "someday", "history"],
                     "description": "today : à faire aujourd'hui ou en retard. upcoming : prévues plus tard. inbox : pas encore rangées. someday : un jour. history : faites ou annulées."],
            "project": ["type": "string", "description": "Nom d'un projet : ses tâches ouvertes. Remplace `list`."],
        ]),
        tool("add_task", "Crée une tâche.", [
            "title": ["type": "string"],
            "note": ["type": "string"],
            "project": ["type": "string", "description": "Nom du projet ; créé s'il n'existe pas."],
            "when": ["type": "string", "description": "Jour où \(Owner.name) compte s'y mettre : AAAA-MM-JJ, today, tomorrow ou someday."],
            "deadline": ["type": "string", "description": "Date limite, AAAA-MM-JJ."],
            "flagged": ["type": "boolean"],
        ], required: ["title"]),
        tool("update_task", "Change une tâche. Seuls les champs donnés changent ; une chaîne vide efface le projet, le jour ou l'échéance.", [
            "id": ["type": "integer"],
            "title": ["type": "string"],
            "note": ["type": "string"],
            "project": ["type": "string"],
            "when": ["type": "string", "description": "AAAA-MM-JJ, today, tomorrow, someday, ou vide pour aucun jour."],
            "deadline": ["type": "string"],
            "flagged": ["type": "boolean"],
        ], required: ["id"]),
        tool("complete_task", "Marque une tâche comme faite, ou comme annulée.", [
            "id": ["type": "integer"],
            "cancelled": ["type": "boolean", "description": "true pour une tâche abandonnée plutôt que faite."],
        ], required: ["id"]),
        tool("annotate_task", "Ajoute un compte rendu daté à la fin de la note d'une tâche, sans rien effacer.", [
            "id": ["type": "integer"],
            "text": ["type": "string"],
        ], required: ["id", "text"]),
        tool("list_projects", "Liste les projets \(Owner.ofName), avec leur dossier de travail et leur nombre de tâches ouvertes.", [:]),
        tool("get_time_recap", "Le temps actif \(Owner.ofName) sur son Mac pour un jour, une semaine ou un mois : total, comparaison avec la période précédente, et détail par catégorie, par app et par site.", [
            "period": ["type": "string", "enum": ["day", "week", "month"]],
            "date": ["type": "string", "description": "Un jour de la période, AAAA-MM-JJ. Par défaut aujourd'hui."],
        ]),
    ]

    private static func tool(_ name: String, _ description: String, _ properties: [String: Any],
                             required: [String] = []) -> [String: Any] {
        ["name": name, "description": description,
         "inputSchema": ["type": "object", "properties": properties, "required": required]]
    }

    // MARK: - Tâches

    private func listTasks(_ arguments: [String: Any]) throws -> Any {
        let list: TaskList
        if let name = arguments["project"] as? String, !name.isEmpty {
            guard let project = project(named: name) else { throw MCPError("Aucun projet nommé « \(name) ».") }
            list = .project(project.id)
        } else {
            switch arguments["list"] as? String ?? "today" {
            case "today": list = .today
            case "upcoming": list = .upcoming
            case "inbox": list = .inbox
            case "someday": list = .someday
            case "history": list = .history
            case let other: throw MCPError("Liste inconnue : \(other).")
            }
        }
        // L'Historique peut être long : les 50 dernières suffisent.
        let tasks = store.tasks(in: list).prefix(list == .history ? 50 : .max)
        return ["tasks": tasks.map(describe), "today": store.today.description]
    }

    private func addTask(_ arguments: [String: Any]) throws -> Any {
        guard let title = (arguments["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else { throw MCPError("Il faut un titre.") }
        var draft = TaskItem.Draft(title: title, note: arguments["note"] as? String ?? "")
        if let name = arguments["project"] as? String, !name.isEmpty { draft.projectID = store.projectNamed(name).id }
        if let when = arguments["when"] as? String, !when.isEmpty { draft.when = try parseWhen(when) }
        if let deadline = arguments["deadline"] as? String, !deadline.isEmpty { draft.deadline = try parseDay(deadline) }
        draft.flagged = arguments["flagged"] as? Bool ?? false
        return describe(store.add(draft))
    }

    private func updateTask(_ arguments: [String: Any]) throws -> Any {
        var task = try task(arguments)
        if let title = (arguments["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            guard !title.isEmpty else { throw MCPError("Le titre ne peut pas être vide.") }
            task.title = title
        }
        if let note = arguments["note"] as? String { task.note = note }
        if let name = arguments["project"] as? String {
            task.projectID = name.isEmpty ? nil : store.projectNamed(name).id
        }
        if let when = arguments["when"] as? String { task.when = when.isEmpty ? nil : try parseWhen(when) }
        if let deadline = arguments["deadline"] as? String {
            task.deadline = deadline.isEmpty ? nil : try parseDay(deadline)
        }
        if let flagged = arguments["flagged"] as? Bool { task.flagged = flagged }
        store.update(task)
        return describe(store.task(task.id)!)
    }

    private func completeTask(_ arguments: [String: Any]) throws -> Any {
        let task = try task(arguments)
        guard task.isOpen else { throw MCPError("La tâche \(task.id) est déjà close.") }
        store.close(task.id, as: arguments["cancelled"] as? Bool == true ? .cancelled : .done)
        return describe(store.task(task.id)!)
    }

    private func annotateTask(_ arguments: [String: Any]) throws -> Any {
        var task = try task(arguments)
        guard let text = (arguments["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { throw MCPError("Il faut un texte.") }
        task.note = Self.annotated(task.note, with: text, on: store.today)
        store.update(task)
        return describe(store.task(task.id)!)
    }

    /// La note suivie d'un compte rendu daté.
    static func annotated(_ note: String, with text: String, on day: Day) -> String {
        let entry = "Claude, \(day) : \(text)"
        return note.isEmpty ? entry : note + "\n\n" + entry
    }

    private func listProjects() -> Any {
        ["projects": store.projects.map { project -> [String: Any] in
            var entry: [String: Any] = ["name": project.name, "open_tasks": store.count(of: .project(project.id))]
            if let folder = project.folder { entry["folder"] = folder }
            return entry
        }]
    }

    private func task(_ arguments: [String: Any]) throws -> TaskItem {
        guard let id = (arguments["id"] as? NSNumber)?.int64Value else { throw MCPError("Il faut l'identifiant `id` de la tâche.") }
        guard let task = store.task(id) else { throw MCPError("Aucune tâche n° \(id).") }
        return task
    }

    private func project(named name: String) -> Project? {
        store.projects.first { TaskStore.folded($0.name) == TaskStore.folded(name) }
    }

    private func parseDay(_ text: String) throws -> Day {
        switch text.lowercased() {
        case "today", "aujourd'hui": return store.today
        case "tomorrow", "demain": return store.today.adding(1, .day, calendar: store.calendar)
        default:
            if let day = Day(string: text), (1...12).contains(day.month), (1...31).contains(day.day) { return day }
            // « vendredi », « le 3 déc » : les mêmes mots que dans la Saisie rapide.
            if case .day(let day) = QuickEntry.parse("x \(text)", today: store.today, calendar: store.calendar).when { return day }
            throw MCPError("Date illisible : « \(text) ». Format attendu : AAAA-MM-JJ.")
        }
    }

    private func parseWhen(_ text: String) throws -> When {
        ["someday", "un jour"].contains(text.lowercased()) ? .someday : .day(try parseDay(text))
    }

    private func describe(_ task: TaskItem) -> [String: Any] {
        let today = store.today
        var entry: [String: Any] = ["id": task.id, "title": task.title, "flagged": task.flagged]
        entry["state"] = switch task.state {
        case .open: "open"
        case .done: "done"
        case .cancelled: "cancelled"
        }
        if !task.note.isEmpty { entry["note"] = task.note }
        if let project = store.project(task.projectID) {
            entry["project"] = project.name
            if let folder = project.folder { entry["folder"] = folder }
        }
        if let when = task.when { entry["when"] = when.stored }
        if let deadline = task.deadline { entry["deadline"] = deadline.description }
        if let late = task.daysLate(today: today) { entry["days_late"] = late }
        if !task.checklist.isEmpty {
            entry["checklist"] = task.checklist.map { ["title": $0.title, "done": $0.done] as [String: Any] }
        }
        if let repetition = task.repetition { entry["repeats"] = repetition.label }
        if let closedAt = task.closedAt { entry["closed_on"] = Day(closedAt, calendar: store.calendar).description }
        let links = task.links
        if !links.isEmpty { entry["links"] = links.map(\.absoluteString) }
        return entry
    }

    // MARK: - Temps

    private func timeRecap(_ arguments: [String: Any]) throws -> Any {
        let period: Period
        switch arguments["period"] as? String ?? "day" {
        case "day": period = .day
        case "week": period = .week
        case "month": period = .month
        case let other: throw MCPError("Période inconnue : \(other).")
        }
        let now = clock()
        var date = now
        if let text = arguments["date"] as? String, !text.isEmpty {
            // Midi : au milieu du jour demandé, quelle que soit l'heure d'été.
            date = try parseDay(text).date(calendar: store.calendar).addingTimeInterval(12 * 3600)
        }
        let recap = Recap(db: db, period: period, containing: date, now: now, calendar: store.calendar)
        let minutes = { (seconds: TimeInterval) in Int((seconds / 60).rounded()) }

        var result: [String: Any] = [
            "period": arguments["period"] as? String ?? "day",
            "from": Day(recap.interval.start, calendar: store.calendar).description,
            "to": Day(recap.interval.end.addingTimeInterval(-1), calendar: store.calendar).description,
            "active_minutes": minutes(recap.total),
            "active_time": formatDuration(recap.total),
            "apps_used": recap.appCount,
            "note": "Temps actif : app au premier plan avec clavier ou souris utilisés. Les vidéos et visios sans geste ne comptent pas.",
        ]
        if case .percent(let change) = recap.change { result["change_vs_previous_percent"] = change }
        result["categories"] = recap.categories.map { category -> [String: Any] in
            ["name": category.name,
             "minutes": minutes(category.duration),
             "share_percent": recap.total > 0 ? Int((category.duration / recap.total * 100).rounded()) : 0,
             "apps_and_sites": category.subjects.prefix(8).map {
                 ["name": $0.name, "minutes": minutes($0.duration), "kind": $0.site == nil ? "app" : "site"] as [String: Any]
             }]
        }
        if period != .day {
            result["by_day"] = recap.buckets.map {
                ["day": Day($0.interval.start, calendar: store.calendar).description, "minutes": minutes($0.total)] as [String: Any]
            }
        }
        return result
    }
}
