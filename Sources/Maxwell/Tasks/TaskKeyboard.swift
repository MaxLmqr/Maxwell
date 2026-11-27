import AppKit
import Foundation

/// Une touche tapée dans la liste des Tâches, une fois traduite du clavier.
enum TaskKey: Equatable {
    case up, down, left, right
    /// ⌥↑ et ⌥↓ : la Tâche choisie change de place.
    case moveUp, moveDown
    case open, escape, delete
    case character(String)

    /// La touche d'un évènement clavier, ou nil si la liste n'en fait rien (⌘, ⌃…).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.intersection([.command, .control]).isEmpty else { return nil }
        let option = flags.contains(.option)
        switch Int(event.keyCode) {
        case 126: self = option ? .moveUp : .up
        case 125: self = option ? .moveDown : .down
        case 123: self = .left
        case 124: self = .right
        case 36, 76: self = .open
        case 53: self = .escape
        case 51, 117: self = .delete
        default:
            guard !option, let characters = event.charactersIgnoringModifiers?.lowercased(), !characters.isEmpty
            else { return nil }
            self = .character(characters)
        }
    }
}

/// Ce que montre le module Tâches : la liste, la Tâche choisie, la Tâche dépliée.
/// Partagé pour que le menu ouvre la bonne liste, et pour que le clavier se règle hors des vues :
/// la fenêtre lui passe chaque touche tant que Max n'écrit pas dans un champ.
@MainActor
final class TaskNavigation: ObservableObject {
    @Published var selection: TaskList = .today {
        didSet {
            guard selection != oldValue else { return }
            selectedTask = nil
            expanded = nil
            justClosed = []
        }
    }
    @Published var selectedTask: TaskID?
    @Published var expanded: TaskID?
    /// Les Tâches cochées depuis l'ouverture de la liste : elles restent visibles, barrées.
    @Published var justClosed: Set<TaskID> = []
    /// Passe à true quand Max demande le champ de création (« / » ou « n »).
    @Published var focusNewTask = false
    /// Vrai tant que le curseur est dans le champ de création.
    @Published var newTaskFocused = false

    /// Le sélecteur de Projet ouvert sur une Tâche (touche « p »).
    struct ProjectPicker: Equatable {
        let taskID: TaskID
        var query = ""
        var index = 0
    }

    enum PickerOption: Hashable {
        case project(Project)
        /// Retirer la Tâche de son Projet.
        case none
        /// Créer le Projet tapé, qui n'existe pas encore.
        case create(String)
    }

    @Published var picker: ProjectPicker?

    /// La confirmation avant de confier une Tâche à Claude (touche « c »), avec une précision facultative.
    struct Launcher: Equatable {
        let taskID: TaskID
        var extra = ""
        /// Le modèle qui fera le travail ; Tab passe au suivant.
        var model = ClaudeModel.current
    }

    @Published var launcher: Launcher?

    /// Les choix du sélecteur : les Projets dont le nom contient ce qui est tapé, « Aucun projet »
    /// si la Tâche en a un, et la création du Projet tapé s'il n'existe pas.
    func pickerOptions(in store: TaskStore) -> [PickerOption] {
        guard let picker else { return [] }
        let query = TaskStore.folded(picker.query)
        var options = store.projects
            .filter { query.isEmpty || TaskStore.folded($0.name).contains(query) }
            .map(PickerOption.project)
        if query.isEmpty, store.task(picker.taskID)?.projectID != nil { options.append(.none) }
        let name = picker.query.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty, !store.projects.contains(where: { TaskStore.folded($0.name) == query }) {
            options.append(.create(name))
        }
        return options
    }

    func movePicker(by step: Int, store: TaskStore) {
        let count = pickerOptions(in: store).count
        guard count > 0, let index = picker?.index else { return }
        picker?.index = min(max(index + step, 0), count - 1)
    }

    /// Range la Tâche dans le Projet choisi et ferme le sélecteur.
    func applyPicker(store: TaskStore) {
        guard let picker else { return }
        let options = pickerOptions(in: store)
        defer { self.picker = nil }
        guard options.indices.contains(picker.index) else { return }
        let project: ProjectID?
        switch options[picker.index] {
        case .project(let chosen): project = chosen.id
        case .none: project = nil
        case .create(let name): project = store.projectNamed(name).id
        }
        store.edit(picker.taskID) { $0.projectID = project }
    }

    /// La colonne qui reçoit les flèches : les listes à gauche, ou les Tâches de la liste choisie.
    enum Pane { case lists, tasks }
    @Published var pane: Pane = .tasks

    /// Toutes les listes de la colonne de gauche, dans l'ordre de l'écran : les cinq listes, puis les Projets.
    func allLists(in store: TaskStore) -> [TaskList] {
        Self.mainLists + store.projects.map { .project($0.id) }
    }

    static let mainLists: [TaskList] = [.today, .upcoming, .inbox, .someday, .history]

    /// Choisit la première Tâche si aucune Tâche visible ne l'est : les touches d'une lettre agissent d'emblée.
    func selectFirstIfNeeded(in store: TaskStore) {
        let ids = visible(in: store).map(\.id)
        // Une liste vide n'a rien à choisir : les flèches vont à la colonne des listes.
        if ids.isEmpty { pane = .lists }
        if let selectedTask, ids.contains(selectedTask) { return }
        selectedTask = ids.first
    }

    /// Les Tâches de la liste montrée, dans l'ordre de l'écran.
    func visible(in store: TaskStore) -> [TaskItem] {
        store.tasks(in: selection, keeping: justClosed, withDoneToday: true)
    }

    /// Applique une touche. Renvoie false si elle ne veut rien dire ici, pour la laisser passer.
    @discardableResult
    func handle(_ key: TaskKey, store: TaskStore) -> Bool {
        if pane == .lists, expanded == nil { return handleInLists(key, store: store) }
        let tasks = visible(in: store)
        switch key {
        case .left:
            guard expanded == nil else { return false }
            pane = .lists
        case .right: return false
        case .up:
            // Au-dessus de la première Tâche, il y a le champ de création.
            if selection != .history, let first = tasks.first, selectedTask == first.id {
                focusNewTask = true
            } else {
                select(-1, in: tasks)
            }
        case .down: select(1, in: tasks)
        case .moveUp: moveSelected(by: -1, in: tasks, store: store)
        case .moveDown: moveSelected(by: 1, in: tasks, store: store)
        case .open:
            guard let id = selectedTask else { return false }
            expanded = id
        case .escape:
            if expanded != nil { expanded = nil } else { selectedTask = nil }
        case .delete:
            guard selectedTask != nil else { return false }
            deleteSelected(in: tasks, store: store)
        case .character(let characters):
            return letter(characters, store: store)
        }
        return true
    }

    /// ↓ depuis le champ de création : le clavier passe à la première Tâche de la liste.
    /// Renvoie false si la liste est vide, pour laisser le curseur où il est.
    func leaveNewTaskField(store: TaskStore) -> Bool {
        guard let first = visible(in: store).first else { return false }
        pane = .tasks
        selectedTask = first.id
        return true
    }

    /// Les flèches dans la colonne des listes : ↑↓ changent de liste, → ou ↩ passent à ses Tâches.
    private func handleInLists(_ key: TaskKey, store: TaskStore) -> Bool {
        switch key {
        case .up, .down:
            let lists = allLists(in: store)
            guard let index = lists.firstIndex(of: selection) else {
                selection = lists[0]
                return true
            }
            selection = lists[min(max(index + (key == .up ? -1 : 1), 0), lists.count - 1)]
        case .right, .open, .escape:
            pane = .tasks
            selectFirstIfNeeded(in: store)
        case .left: break
        case .character(let characters):
            // Les chiffres et « / » gardent leur sens ; les lettres qui agissent sur une Tâche n'en ont pas ici.
            guard Int(characters) != nil || ["&", "é", "\"", "'", "(", "/", "n", "z", "u"].contains(characters) else { return false }
            return letter(characters, store: store)
        case .moveUp, .moveDown, .delete: return false
        }
        return true
    }

    func toggle(_ id: TaskID, store: TaskStore) {
        guard let task = store.task(id) else { return }
        if task.isOpen {
            store.close(id)
            justClosed.insert(id)
        } else {
            store.reopen(id)
            justClosed.remove(id)
        }
    }

    private func select(_ step: Int, in tasks: [TaskItem]) {
        let ids = tasks.map(\.id)
        guard !ids.isEmpty else { return }
        guard let current = selectedTask, let index = ids.firstIndex(of: current) else {
            selectedTask = step > 0 ? ids.first : ids.last
            return
        }
        selectedTask = ids[min(max(index + step, 0), ids.count - 1)]
    }

    private func moveSelected(by step: Int, in tasks: [TaskItem], store: TaskStore) {
        guard selection != .upcoming, selection != .history, let id = selectedTask,
              let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        let target = index + step
        guard target >= 0, target < tasks.count else { return }
        let before = step < 0 ? tasks[target].id : (target + 1 < tasks.count ? tasks[target + 1].id : nil)
        store.move(id, before: before, in: selection)
    }

    private func deleteSelected(in tasks: [TaskItem], store: TaskStore) {
        guard let id = selectedTask else { return }
        let ids = tasks.map(\.id)
        // La sélection passe à la Tâche suivante, comme dans Mail.
        if let index = ids.firstIndex(of: id) {
            selectedTask = index + 1 < ids.count ? ids[index + 1] : (index > 0 ? ids[index - 1] : nil)
        }
        if expanded == id { expanded = nil }
        store.delete(id)
    }

    private func letter(_ characters: String, store: TaskStore) -> Bool {
        // En AZERTY, les touches 1 à 5 tapent & é " ' ( sans Maj.
        let azerty = ["&": 1, "é": 2, "\"": 3, "'": 4, "(": 5]
        if let digit = Int(characters) ?? azerty[characters], (1...Self.mainLists.count).contains(digit) {
            selection = Self.mainLists[digit - 1]
            return true
        }
        switch characters {
        case "/", "n":
            focusNewTask = true
            return true
        case "u", "z":
            // Défait la dernière action, et choisit la Tâche revenue.
            guard let undone = store.undo() else { return false }
            if let id = undone.taskID, visible(in: store).contains(where: { $0.id == id }) {
                pane = .tasks
                selectedTask = id
            }
            return true
        default: break
        }
        guard let id = selectedTask else { return false }
        let today = store.today
        switch characters {
        case "x", " ": toggle(id, store: store)
        case "t": store.setWhen(id, .day(today))
        case "d": store.setWhen(id, .day(today.adding(1, .day, calendar: store.calendar)))
        case "s": store.setWhen(id, .someday)
        case "f": store.edit(id) { $0.flagged.toggle() }
        case "p": picker = ProjectPicker(taskID: id)
        case "c":
            // Une Tâche close, ou déjà entre les mains de Claude, ne se confie pas.
            guard let task = store.task(id), task.isOpen, task.claude?.state != .running else { return false }
            launcher = Launcher(taskID: id)
        case "o":
            guard let url = store.task(id)?.links.first else { return false }
            NSWorkspace.shared.open(url)
        default: return false
        }
        return true
    }
}
