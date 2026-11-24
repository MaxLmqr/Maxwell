import AppKit
import Combine
import Foundation

/// Les Tâches et les Projets, tels que les vues les montrent et les changent.
/// Tout passe par ici : chaque changement est enregistré aussitôt, puis les vues sont prévenues.
@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var projects: [Project] = []
    /// La dernière Tâche supprimée, le temps de se rattraper.
    @Published private(set) var lastDeleted: TaskItem?

    private let db: Database
    private let clock: () -> Date
    let calendar: Calendar
    private var dayChange: AnyCancellable?

    init(db: Database, calendar: Calendar = .current, clock: @escaping () -> Date = Date.init) {
        self.db = db
        self.calendar = calendar
        self.clock = clock
        reload()
        // Aujourd'hui se recalcule à minuit, même si rien d'autre ne bouge.
        dataVersion = db.dataVersion()
        dayChange = NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
    }

    var today: Day { Day(clock(), calendar: calendar) }

    func reload() {
        tasks = db.tasks()
        projects = db.projects()
    }

    private var dataVersion: Int64 = 0

    /// Recharge si un autre programme a écrit dans la base : Claude, par le serveur MCP.
    /// Renvoie true quand quelque chose a changé.
    @discardableResult
    func reloadIfChangedElsewhere() -> Bool {
        let version = db.dataVersion()
        guard version != dataVersion else { return false }
        dataVersion = version
        reload()
        return true
    }

    func tasks(in list: TaskList, keeping kept: Set<TaskID> = []) -> [TaskItem] {
        let today = today
        // Une Tâche cochée à l'instant reste à sa place, barrée, le temps de se rattraper.
        guard list != .history, !kept.isEmpty else { return tasks.inList(list, today: today) }
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        return tasks.map { kept.contains($0.id) && !$0.isOpen ? $0.reopenedForDisplay : $0 }
            .inList(list, today: today)
            .map { byID[$0.id]! }
    }

    func count(of list: TaskList) -> Int {
        let today = today
        return tasks.lazy.filter { $0.belongs(to: list, today: today) }.count
    }

    func task(_ id: TaskID) -> TaskItem? { tasks.first { $0.id == id } }

    func project(_ id: ProjectID?) -> Project? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    // MARK: - Créer

    /// Crée une Tâche à partir d'un texte tapé, en reprenant ce que la liste impose.
    /// Renvoie nil si le texte ne laisse pas de titre.
    @discardableResult
    func add(text: String, in list: TaskList? = nil) -> TaskItem? {
        let entry = QuickEntry.parse(text, today: today, calendar: calendar)
        guard !entry.title.isEmpty else { return nil }
        var draft = TaskItem.Draft(title: entry.title, when: entry.when, deadline: entry.deadline,
                                   flagged: entry.flagged)
        if let name = entry.projectName { draft.projectID = projectNamed(name).id }
        list?.applyDefaults(to: &draft, today: today)
        return add(draft)
    }

    @discardableResult
    func add(_ draft: TaskItem.Draft) -> TaskItem {
        let id = db.insertTask(draft, createdAt: clock())
        remember(UndoStep(label: "création de « \(draft.title) »", restore: [], remove: [id]))
        reload()
        return task(id)!
    }

    // MARK: - Changer

    func update(_ task: TaskItem) {
        if let before = self.task(task.id), before != task {
            remember(UndoStep(label: Self.label(from: before, to: task), restore: [before], remove: []))
        }
        db.updateTask(task)
        reload()
    }

    /// Enregistre ce que Claude a fait de la Tâche. Ce n'est pas une action de Max : `undo` n'y touche pas.
    func setClaude(_ trace: ClaudeTrace?, for id: TaskID) {
        db.setClaude(trace, for: id)
        reload()
    }

    // MARK: - Annuler

    /// De quoi défaire une action : les Tâches telles qu'elles étaient, et celles que l'action a créées.
    struct UndoStep {
        let label: String
        var restore: [TaskItem]
        let remove: [TaskID]
        var date = Date()
    }

    /// Ce qu'une annulation a défait, pour le dire à Max et choisir la Tâche revenue.
    struct Undone: Equatable {
        let label: String
        let taskID: TaskID?
    }

    private var undoSteps: [UndoStep] = []
    /// Le dernier message à montrer en bas de la liste (« Annulé : … »).
    @Published private(set) var notice: String?

    var canUndo: Bool { !undoSteps.isEmpty }

    private func remember(_ step: UndoStep) {
        // La frappe dans une Tâche dépliée enregistre à chaque lettre : une seule annulation pour le tout.
        if step.label == Self.editLabel, let last = undoSteps.last, last.label == Self.editLabel,
           last.restore.map(\.id) == step.restore.map(\.id), step.date.timeIntervalSince(last.date) < 3 {
            undoSteps[undoSteps.count - 1].date = step.date
            return
        }
        undoSteps.append(step)
        if undoSteps.count > 50 { undoSteps.removeFirst() }
    }

    /// Défait la dernière action sur les Tâches : suppression, coche, report, drapeau, déplacement, création…
    /// Renvoie nil s'il n'y a rien à défaire.
    @discardableResult
    func undo() -> Undone? {
        guard let step = undoSteps.popLast() else { return nil }
        for id in step.remove { db.deleteTask(id) }
        let existing = Set(db.tasks().map(\.id))
        for task in step.restore {
            if existing.contains(task.id) { db.updateTask(task) } else { db.restoreTask(task) }
        }
        if let lastDeleted, step.restore.contains(where: { $0.id == lastDeleted.id }) { self.lastDeleted = nil }
        notice = "Annulé : \(step.label)"
        reload()
        return Undone(label: step.label, taskID: step.restore.first?.id)
    }

    func clearNotice() {
        notice = nil
    }

    private static let editLabel = "modification"

    /// Ce qui a changé entre deux états d'une Tâche, en quelques mots.
    private static func label(from before: TaskItem, to after: TaskItem) -> String {
        let name = "« \(after.title) »"
        if before.state != after.state {
            switch after.state {
            case .done: return "\(name) faite"
            case .cancelled: return "\(name) annulée"
            case .open: return "\(name) rouverte"
            }
        }
        if before.when != after.when { return "report de \(name)" }
        if before.flagged != after.flagged { return "drapeau de \(name)" }
        if before.position != after.position { return "déplacement de \(name)" }
        if before.projectID != after.projectID { return "projet de \(name)" }
        return editLabel
    }

    func edit(_ id: TaskID, _ change: (inout TaskItem) -> Void) {
        guard var task = task(id) else { return }
        change(&task)
        update(task)
    }

    /// Rend la Tâche Faite ou Annulée. Une Tâche répétée laisse place à la suivante.
    func close(_ id: TaskID, as state: TaskItem.State = .done) {
        guard var task = task(id), task.isOpen, state != .open else { return }
        let before = task
        var created: [TaskID] = []
        task.state = state
        task.closedAt = clock()
        db.updateTask(task)
        defer {
            remember(UndoStep(label: "« \(task.title) » \(state == .done ? "faite" : "annulée")",
                              restore: [before], remove: created))
        }
        if let repetition = task.repetition {
            let next = repetition.next(when: task.when, deadline: task.deadline, closedOn: today, calendar: calendar)
            let id = db.insertTask(TaskItem.Draft(
                title: task.title, note: task.note, projectID: task.projectID, when: next.when,
                deadline: next.deadline, flagged: task.flagged, repetition: repetition), createdAt: clock())
            created.append(id)
            // La suivante garde la Checklist, décochée, et la place de la précédente.
            var copy = db.tasks().first { $0.id == id }!
            copy.checklist = task.checklist.map { ChecklistItem(title: $0.title) }
            copy.position = task.position
            db.updateTask(copy)
        }
        reload()
    }

    /// Supprime une Tâche créée par erreur. `undo` la fait revenir tant que Maxwell reste ouvert.
    func delete(_ id: TaskID) {
        guard let task = task(id) else { return }
        db.deleteTask(id)
        remember(UndoStep(label: "suppression de « \(task.title) »", restore: [task], remove: []))
        lastDeleted = task
        reload()
    }

    /// Annule la suppression annoncée par le bandeau, si c'est encore la dernière action.
    func undoDelete() {
        guard let task = lastDeleted, undoSteps.last?.restore.first?.id == task.id else { return }
        undo()
    }

    /// Fait disparaître le bandeau « supprimée ». La suppression reste annulable avec `undo`.
    func forgetDeletion() {
        lastDeleted = nil
    }

    /// Remet une Tâche close dans ses listes.
    func reopen(_ id: TaskID) {
        edit(id) {
            $0.state = .open
            $0.closedAt = nil
        }
    }

    func setWhen(_ id: TaskID, _ when: When?) {
        edit(id) { $0.when = when }
    }

    /// Place la Tâche juste avant `target`, ou en fin de liste si `target` est nil.
    func move(_ id: TaskID, before target: TaskID?, in list: TaskList) {
        let ordered = tasks(in: list).filter { $0.id != id }
        let position: Double
        if let target, let index = ordered.firstIndex(where: { $0.id == target }) {
            let after = ordered[index].position
            let before = index > 0 ? ordered[index - 1].position : after - 2
            position = (before + after) / 2
        } else {
            position = (ordered.last?.position ?? 0) + 1
        }
        edit(id) { $0.position = position }
    }

    // MARK: - Projets

    /// Le Projet de ce nom, créé s'il n'existe pas. La casse, les accents et les espaces ne comptent pas.
    @discardableResult
    func projectNamed(_ name: String) -> Project {
        let key = Self.folded(name)
        if let existing = projects.first(where: { Self.folded($0.name) == key }) { return existing }
        let id = db.insertProject(name: name)
        reload()
        return projects.first { $0.id == id }!
    }

    func renameProject(_ id: ProjectID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        db.renameProject(id, to: name)
        reload()
    }

    func setProjectFolder(_ id: ProjectID, to folder: String?) {
        db.setProjectFolder(id, to: folder)
        reload()
    }

    func archiveProject(_ id: ProjectID) {
        db.archiveProject(id, at: clock())
        reload()
    }

    static func folded(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .filter { !$0.isWhitespace }
    }
}

private extension TaskItem {
    /// La même Tâche, comptée comme Ouverte pour garder sa place dans la liste.
    var reopenedForDisplay: TaskItem {
        var copy = self
        copy.state = .open
        return copy
    }
}
