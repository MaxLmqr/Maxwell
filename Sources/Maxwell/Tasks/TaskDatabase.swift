import Foundation
import SQLite3

/// Stockage des Tâches et des Projets, dans la même base que les Sessions.
extension Database {
    func createTaskTables() throws {
        try exec("""
            CREATE TABLE IF NOT EXISTS projects (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                position REAL NOT NULL,
                archived_at REAL
            );
            CREATE TABLE IF NOT EXISTS tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                note TEXT NOT NULL DEFAULT '',
                checklist TEXT NOT NULL DEFAULT '[]',
                project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL,
                when_day TEXT,
                deadline TEXT,
                flagged INTEGER NOT NULL DEFAULT 0,
                repetition TEXT,
                state INTEGER NOT NULL DEFAULT 0,
                created_at REAL NOT NULL,
                closed_at REAL,
                position REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_tasks_state ON tasks(state);
            """)
        // Ajouts aux bases créées avant le pont avec Claude.
        if !columns(of: "projects").contains("folder") {
            try exec("ALTER TABLE projects ADD COLUMN folder TEXT")
        }
        let taskColumns = columns(of: "tasks")
        for (column, type) in [("claude_at", "REAL"), ("claude_session", "TEXT"), ("claude_state", "TEXT"),
                               ("claude_result", "TEXT")] where !taskColumns.contains(column) {
            try exec("ALTER TABLE tasks ADD COLUMN \(column) \(type)")
        }
    }

    // MARK: - Tâches

    private static let taskColumns = """
        id, title, note, checklist, project_id, when_day, deadline, flagged, repetition,
        state, created_at, closed_at, position, claude_at, claude_session, claude_state, claude_result
        """

    /// Toutes les Tâches, Historique compris.
    func tasks() -> [TaskItem] {
        var result: [TaskItem] = []
        run("SELECT \(Self.taskColumns) FROM tasks", []) { stmt in
            let checklist = Self.optionalText(stmt, 3).flatMap {
                try? JSONDecoder().decode([ChecklistItem].self, from: Data($0.utf8))
            } ?? []
            result.append(TaskItem(
                id: sqlite3_column_int64(stmt, 0),
                title: String(cString: sqlite3_column_text(stmt, 1)),
                note: Self.optionalText(stmt, 2) ?? "",
                checklist: checklist,
                projectID: sqlite3_column_type(stmt, 4) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 4),
                when: Self.optionalText(stmt, 5).flatMap(When.init(stored:)),
                deadline: Self.optionalText(stmt, 6).flatMap(Day.init(string:)),
                flagged: sqlite3_column_int64(stmt, 7) != 0,
                repetition: Self.optionalText(stmt, 8).flatMap(Repetition.init(stored:)),
                state: TaskItem.State(rawValue: Int(sqlite3_column_int64(stmt, 9))) ?? .open,
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 10)),
                closedAt: sqlite3_column_type(stmt, 11) == SQLITE_NULL
                    ? nil : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 11)),
                position: sqlite3_column_double(stmt, 12),
                claude: Self.optionalText(stmt, 14).map { session in
                    ClaudeTrace(startedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 13)),
                                session: session,
                                state: Self.optionalText(stmt, 15).flatMap(ClaudeTrace.State.init(rawValue:)) ?? .failed,
                                result: Self.optionalText(stmt, 16))
                }))
        }
        return result
    }

    /// Crée une Tâche Ouverte, en tête de ses listes : ce qu'on vient de noter se voit tout de suite.
    func insertTask(_ draft: TaskItem.Draft, createdAt: Date) -> TaskID {
        run("""
            INSERT INTO tasks (title, note, project_id, when_day, deadline, flagged, repetition, created_at, position)
            SELECT ?, ?, ?, ?, ?, ?, ?, ?, COALESCE(MIN(position), 0) - 1 FROM tasks
            """,
            [draft.title, draft.note, draft.projectID as Any, draft.when?.stored as Any,
             draft.deadline?.description as Any, Int64(draft.flagged ? 1 : 0),
             draft.repetition?.stored as Any, createdAt.timeIntervalSince1970])
        return lastInsertID
    }

    /// Enregistre tous les champs de la Tâche.
    func updateTask(_ task: TaskItem) {
        let checklist = (try? JSONEncoder().encode(task.checklist)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        run("""
            UPDATE tasks SET title = ?, note = ?, checklist = ?, project_id = ?, when_day = ?, deadline = ?,
                flagged = ?, repetition = ?, state = ?, closed_at = ?, position = ?
            WHERE id = ?
            """,
            [task.title, task.note, checklist, task.projectID as Any, task.when?.stored as Any,
             task.deadline?.description as Any, Int64(task.flagged ? 1 : 0), task.repetition?.stored as Any,
             Int64(task.state.rawValue), task.closedAt?.timeIntervalSince1970 as Any, task.position, task.id])
    }

    /// Ce que Claude a fait de la Tâche. À part de `updateTask` : une Tâche dépliée, qui s'enregistre
    /// à chaque frappe, n'écrase pas l'avancement que Claude écrit pendant ce temps.
    func setClaude(_ trace: ClaudeTrace?, for id: TaskID) {
        run("UPDATE tasks SET claude_at = ?, claude_session = ?, claude_state = ?, claude_result = ? WHERE id = ?",
            [trace?.startedAt.timeIntervalSince1970 as Any, trace?.session as Any, trace?.state.rawValue as Any,
             trace?.result as Any, id])
    }

    /// Efface la Tâche pour de bon.
    func deleteTask(_ id: TaskID) {
        run("DELETE FROM tasks WHERE id = ?", [id])
    }

    /// Remet une Tâche effacée, avec son identifiant d'origine.
    func restoreTask(_ task: TaskItem) {
        run("INSERT INTO tasks (id, title, created_at, position) VALUES (?, ?, ?, ?)",
            [task.id, task.title, task.createdAt.timeIntervalSince1970, task.position])
        updateTask(task)
        setClaude(task.claude, for: task.id)
    }

    // MARK: - Projets

    /// Les Projets en cours, sans les archivés.
    func projects() -> [Project] {
        var result: [Project] = []
        run("SELECT id, name, position, folder FROM projects WHERE archived_at IS NULL ORDER BY position, id", []) { stmt in
            result.append(Project(id: sqlite3_column_int64(stmt, 0),
                                  name: String(cString: sqlite3_column_text(stmt, 1)),
                                  position: sqlite3_column_double(stmt, 2),
                                  folder: Self.optionalText(stmt, 3)))
        }
        return result
    }

    func insertProject(name: String) -> ProjectID {
        run("INSERT INTO projects (name, position) SELECT ?, COALESCE(MAX(position), 0) + 1 FROM projects", [name])
        return lastInsertID
    }

    func renameProject(_ id: ProjectID, to name: String) {
        run("UPDATE projects SET name = ? WHERE id = ?", [name, id])
    }

    /// Le dossier où Claude travaille pour ce Projet, ou nil pour le retirer.
    func setProjectFolder(_ id: ProjectID, to folder: String?) {
        run("UPDATE projects SET folder = ? WHERE id = ?", [folder as Any, id])
    }

    /// Le Projet quitte la barre latérale ; ses Tâches encore Ouvertes perdent leur Projet.
    func archiveProject(_ id: ProjectID, at date: Date) {
        run("UPDATE projects SET archived_at = ? WHERE id = ?", [date.timeIntervalSince1970, id])
        run("UPDATE tasks SET project_id = NULL WHERE project_id = ? AND state = 0", [id])
    }
}
