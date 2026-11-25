import Foundation

typealias TaskID = Int64
typealias ProjectID = Int64

/// Un jour du calendrier, sans heure ni fuseau : « le 3 décembre » reste le 3 décembre en voyage.
struct Day: Hashable, Comparable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Lit la forme enregistrée dans la base, « 2026-11-22 ».
    init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// Minuit au début du jour.
    func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func adding(_ value: Int, _ component: Calendar.Component, calendar: Calendar = .current) -> Day {
        // Midi évite les surprises des changements d'heure.
        let noon = calendar.date(byAdding: .hour, value: 12, to: date(calendar: calendar))!
        return Day(calendar.date(byAdding: component, value: value, to: noon)!, calendar: calendar)
    }

    /// Nombre de jours de `self` à `other`, négatif si `other` est avant.
    func days(to other: Day, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: date(calendar: calendar), to: other.date(calendar: calendar)).day!
    }

    /// 1 pour dimanche, 2 pour lundi… comme `Calendar`.
    func weekday(calendar: Calendar = .current) -> Int {
        calendar.component(.weekday, from: date(calendar: calendar))
    }

    static func < (a: Day, b: Day) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }
}

/// Le Quand d'une Tâche : un jour, ou « Un jour » quand Max ne sait pas encore.
enum When: Hashable {
    case day(Day)
    case someday

    var day: Day? {
        if case .day(let day) = self { day } else { nil }
    }

    /// La forme enregistrée dans la base.
    var stored: String {
        switch self {
        case .day(let day): day.description
        case .someday: "someday"
        }
    }

    init?(stored: String) {
        if stored == "someday" { self = .someday }
        else if let day = Day(string: stored) { self = .day(day) }
        else { return nil }
    }
}

/// Comment une Tâche revient une fois Faite ou Annulée.
struct Repetition: Hashable {
    enum Mode: String, CaseIterable {
        /// La suivante tombe à la date prévue, même si la précédente a été faite en retard.
        case fixed
        /// La suivante tombe un intervalle après le jour où la précédente a été close.
        case afterCompletion
    }

    enum Unit: String, CaseIterable {
        case day, week, month, year

        var component: Calendar.Component {
            switch self {
            case .day: .day
            case .week: .weekOfYear
            case .month: .month
            case .year: .year
            }
        }
    }

    var mode: Mode
    var every: Int
    var unit: Unit

    /// La forme enregistrée dans la base, « fixed:1:week ».
    var stored: String { "\(mode.rawValue):\(every):\(unit.rawValue)" }

    init(mode: Mode, every: Int, unit: Unit) {
        self.mode = mode
        self.every = max(every, 1)
        self.unit = unit
    }

    init?(stored: String) {
        let parts = stored.split(separator: ":").map(String.init)
        guard parts.count == 3, let mode = Mode(rawValue: parts[0]), let every = Int(parts[1]),
              let unit = Unit(rawValue: parts[2]) else { return nil }
        self.init(mode: mode, every: every, unit: unit)
    }

    /// Le Quand et l'Échéance de la Tâche suivante, quand la précédente est close le jour `closedOn`.
    /// Jamais dans le passé : à date fixe, c'est la première date après `closedOn`.
    func next(when: When?, deadline: Day?, closedOn: Day, calendar: Calendar = .current) -> (when: When?, deadline: Day?) {
        let anchor = when?.day ?? deadline
        switch mode {
        case .fixed:
            let base = anchor ?? closedOn
            var steps = 1
            // Chaque essai part de la date d'origine : le 31 reste le 31 quand le mois le permet.
            while base.adding(steps * every, unit.component, calendar: calendar) <= closedOn { steps += 1 }
            guard anchor != nil else { return (.day(base.adding(steps * every, unit.component, calendar: calendar)), nil) }
            return Self.shifted(when: when, deadline: deadline) {
                $0.adding(steps * self.every, self.unit.component, calendar: calendar)
            }
        case .afterCompletion:
            let next = closedOn.adding(every, unit.component, calendar: calendar)
            guard let anchor else { return (.day(next), nil) }
            // Le Quand et l'Échéance gardent le même écart entre eux.
            let offset = anchor.days(to: next, calendar: calendar)
            return Self.shifted(when: when, deadline: deadline) { $0.adding(offset, .day, calendar: calendar) }
        }
    }

    private static func shifted(when: When?, deadline: Day?, by shift: (Day) -> Day) -> (when: When?, deadline: Day?) {
        let newWhen: When? = switch when {
        case .day(let day): .day(shift(day))
        case .someday: .someday
        case nil: nil
        }
        return (newWhen, deadline.map(shift))
    }
}

struct ChecklistItem: Hashable, Codable, Identifiable {
    var id = UUID()
    var title: String
    var done = false
}

/// Une Tâche. (`Task` est déjà pris par Swift.)
struct TaskItem: Identifiable, Hashable {
    enum State: Int {
        case open = 0, done = 1, cancelled = 2
    }

    let id: TaskID
    var title: String
    var note = ""
    var checklist: [ChecklistItem] = []
    var projectID: ProjectID?
    var when: When?
    var deadline: Day?
    var flagged = false
    var repetition: Repetition?
    var state: State = .open
    var createdAt: Date
    var closedAt: Date?
    /// L'ordre de la Tâche dans ses listes.
    var position: Double
    /// Ce que Claude a fait de la Tâche, nil si elle ne lui a jamais été confiée.
    var claude: ClaudeTrace?

    var isOpen: Bool { state == .open }

    /// Ce qu'on choisit en créant une Tâche.
    struct Draft: Equatable {
        var title: String
        var note = ""
        var projectID: ProjectID?
        var when: When?
        var deadline: Day?
        var flagged = false
        var repetition: Repetition?
    }
}

/// La trace d'une Tâche confiée à Claude : la session, où elle en est, et son compte rendu.
struct ClaudeTrace: Hashable {
    enum State: String {
        case running, done, failed
    }

    var startedAt: Date
    /// L'identifiant de la session Claude Code, pour la reprendre.
    var session: String
    var state: State
    /// Le compte rendu de Claude, ou la raison de l'échec.
    var result: String?
}

struct Project: Identifiable, Hashable {
    let id: ProjectID
    var name: String
    var position: Double
    /// Le dossier du Projet, souvent un dépôt de code : c'est là que Claude travaille sur ses Tâches.
    var folder: String?
}

/// Les listes où Max retrouve ses Tâches.
enum TaskList: Hashable {
    case inbox, today, upcoming, someday, history
    case project(ProjectID)

    var title: String {
        switch self {
        case .inbox: "Boîte de réception"
        case .today: "Aujourd'hui"
        case .upcoming: "À venir"
        case .someday: "Un jour"
        case .history: "Historique"
        case .project: "Projet"
        }
    }

    var symbol: String {
        switch self {
        case .inbox: "tray"
        case .today: "star"
        case .upcoming: "calendar"
        case .someday: "archivebox"
        case .history: "checkmark.circle"
        case .project: "circle"
        }
    }

    /// Ce que reçoit une Tâche créée depuis cette liste, pour qu'elle y reste.
    func applyDefaults(to draft: inout TaskItem.Draft, today: Day) {
        switch self {
        case .today where draft.when == nil && draft.deadline == nil: draft.when = .day(today)
        case .someday where draft.when == nil: draft.when = .someday
        case .project(let id) where draft.projectID == nil: draft.projectID = id
        default: break
        }
    }
}

extension TaskItem {
    /// Une Tâche est dans Aujourd'hui si son Quand ou son Échéance est aujourd'hui ou passé.
    func isDue(today: Day) -> Bool {
        if let day = when?.day, day <= today { return true }
        if let deadline, deadline <= today { return true }
        return false
    }

    /// Le jour sous lequel la Tâche apparaît dans À venir, nil si elle n'y est pas.
    func upcomingDay(today: Day) -> Day? {
        guard isOpen, !isDue(today: today) else { return nil }
        return [when?.day, deadline].compactMap { $0 }.filter { $0 > today }.min()
    }

    func belongs(to list: TaskList, today: Day) -> Bool {
        switch list {
        case .history: return !isOpen
        case _ where !isOpen: return false
        // Sans Quand, même rangée dans un Projet : la Tâche n'a pas encore de jour.
        case .inbox: return when == nil
        case .today: return isDue(today: today)
        case .upcoming: return upcomingDay(today: today) != nil
        case .someday: return when == .someday && !isDue(today: today)
        case .project(let id): return projectID == id
        }
    }

    /// Nombre de jours depuis le Quand, pour une Tâche Ouverte prévue avant aujourd'hui.
    func daysLate(today: Day) -> Int? {
        guard isOpen, let day = when?.day, day < today else { return nil }
        return day.days(to: today)
    }

    func isOverdue(today: Day) -> Bool {
        guard isOpen, let deadline else { return false }
        return deadline < today
    }
}

extension Array where Element == TaskItem {
    /// Les Tâches de la liste, dans l'ordre où elle les montre.
    func inList(_ list: TaskList, today: Day) -> [TaskItem] {
        let members = filter { $0.belongs(to: list, today: today) }
        switch list {
        case .history:
            return members.sorted { ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast) }
        case .upcoming:
            return members.sorted {
                let a = $0.upcomingDay(today: today)!, b = $1.upcomingDay(today: today)!
                return a != b ? a < b : $0.position < $1.position
            }
        default:
            return members.sorted { $0.position < $1.position }
        }
    }
}
