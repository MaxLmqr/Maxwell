import SwiftUI

// MARK: - Dates lisibles

/// « Aujourd'hui », « Demain », « vendredi » dans la semaine, « 3 déc. » au-delà.
func formatDay(_ day: Day, today: Day, calendar: Calendar = .current) -> String {
    let gap = today.days(to: day, calendar: calendar)
    switch gap {
    case 0: return "Aujourd'hui"
    case 1: return "Demain"
    case -1: return "Hier"
    case 2...6: return day.date(calendar: calendar).formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "fr_FR")))
    default:
        let style = Date.FormatStyle.dateTime.day().month(.abbreviated).locale(Locale(identifier: "fr_FR"))
        let text = day.date(calendar: calendar).formatted(day.year == today.year ? style : style.year())
        return text
    }
}

func formatWhen(_ when: When, today: Day) -> String {
    switch when {
    case .day(let day): formatDay(day, today: today)
    case .someday: "Un jour"
    }
}

extension Repetition {
    var label: String {
        let unit: String = switch (unit, every) {
        case (.day, 1): "Tous les jours"
        case (.week, 1): "Toutes les semaines"
        case (.month, 1): "Tous les mois"
        case (.year, 1): "Tous les ans"
        case (.day, _): "Tous les \(every) jours"
        case (.week, _): "Toutes les \(every) semaines"
        case (.month, _): "Tous les \(every) mois"
        case (.year, _): "Tous les \(every) ans"
        }
        return mode == .afterCompletion ? "\(unit), après avoir été faite" : unit
    }
}

// MARK: - Couleurs des listes

extension TaskList {
    /// Chaque liste a sa couleur, la même dans la barre latérale et dans son en-tête.
    var tint: Color {
        switch self {
        case .inbox: Color(nsColor: .systemBlue)
        case .today: Color(nsColor: .systemYellow)
        case .upcoming: Color(nsColor: .systemRed)
        case .someday: Color(nsColor: .systemBrown)
        case .history: Theme.accent
        case .project: Color(nsColor: .systemTeal)
        }
    }

    var filledSymbol: String {
        switch self {
        case .inbox: "tray.fill"
        case .today: "star.fill"
        case .upcoming: "calendar"
        case .someday: "archivebox.fill"
        case .history: "checkmark.circle.fill"
        case .project: "circle"
        }
    }
}

// MARK: - Case à cocher

/// Un petit carré : vide, plein et coché pour une Tâche Faite, gris et barré pour une Tâche Annulée.
struct TaskCheckbox: View {
    let state: TaskItem.State
    var size: CGFloat = 13
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous).fill(fill)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(state == .open ? Color.secondary.opacity(hovering ? 1 : 0.55) : .clear, lineWidth: 1.4)
                if state != .open || hovering {
                    Image(systemName: state == .cancelled ? "xmark" : "checkmark")
                        .font(.system(size: size * 0.6, weight: .heavy))
                        .foregroundStyle(state == .open ? Color.secondary : .white)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle().inset(by: -4))
            .animation(.easeOut(duration: 0.12), value: state)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(state == .open ? "Marquer comme faite (x)" : "Rouvrir")
    }

    private var fill: Color {
        switch state {
        case .open: .clear
        case .done: Console.done
        case .cancelled: Color.secondary.opacity(0.45)
        }
    }
}

// MARK: - Ligne

/// Une Tâche sur une seule ligne : la case et le titre à gauche, des repères en chasse fixe à droite.
struct TaskRow: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var claude: ClaudeRunner
    let task: TaskItem
    var showsProject = true
    /// Faux dans À venir, où le jour est déjà l'en-tête.
    var showsWhen = true
    /// Dans le menu, la ligne a son propre survol ; dans la fenêtre, c'est la sélection qui compte.
    var hoverHighlight = false
    /// Dans le menu, étroit : seulement le retard, l'échéance et le drapeau.
    var compact = false
    var onToggle: (TaskItem) -> Void
    @State private var hovering = false

    var body: some View {
        let today = store.today
        HStack(spacing: 10) {
            TaskCheckbox(state: task.state) { onToggle(task) }
            TaskTitle(title: task.title, isOpen: task.isOpen)
                .layoutPriority(1)
            Spacer(minLength: 8)
            trailing(today: today)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, hoverHighlight ? 6 : 0)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(hoverHighlight && hovering ? 0.06 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    @ViewBuilder private func trailing(today: Day) -> some View {
        HStack(spacing: 10) {
            // Les liens de la Note, à portée de clic sans déplier la Tâche.
            let titleLinks = TaskLinks.links(in: task.title)
            ForEach(TaskLinks.links(in: task.note).filter { !titleLinks.contains($0) }.prefix(compact ? 1 : 2),
                    id: \.self) { url in
                LinkChip(url: url)
            }
            if let trace = task.claude {
                ClaudeMark(state: trace.state, activity: compact ? nil : claude.activity[task.id])
            }
            if !compact, !task.checklist.isEmpty {
                let done = task.checklist.filter(\.done).count
                Text("☐ \(done)/\(task.checklist.count)").foregroundStyle(.tertiary)
            }
            if !compact, !task.note.isEmpty {
                Text("¶").foregroundStyle(.tertiary).help("A une note")
            }
            if !compact, let repetition = task.repetition {
                Text("↻ \(repetition.shortLabel)").foregroundStyle(.tertiary).help(repetition.label)
            }
            if showsProject, !compact, let project = store.project(task.projectID) {
                Text(project.name.lowercased()).foregroundStyle(.secondary).lineLimit(1)
            }
            if !task.isOpen, let closedAt = task.closedAt {
                Text(formatDay(Day(closedAt, calendar: store.calendar), today: today).lowercased())
                    .foregroundStyle(.secondary)
            } else if let late = task.daysLate(today: today) {
                Text("+\(late)j").foregroundStyle(Color(nsColor: .systemOrange))
                    .help("Prévue \(formatWhen(task.when!, today: today).lowercased()), pas encore faite")
            } else if showsWhen, let when = task.when, when.day.map({ $0 > today }) ?? true {
                Text(formatWhen(when, today: today).lowercased()).foregroundStyle(.secondary)
            }
            if task.isOpen, let deadline = task.deadline {
                let left = today.days(to: deadline, calendar: store.calendar)
                Text(left < 0 ? "J+\(-left)" : left == 0 ? "J-0" : "J-\(left)")
                    .foregroundStyle(left <= 1 ? Color(nsColor: .systemRed) : .secondary)
                    .help("Échéance : \(formatDay(deadline, today: today).lowercased())")
            }
            if task.flagged {
                Image(systemName: "flag.fill").font(.system(size: 10)).foregroundStyle(Color(nsColor: .systemOrange))
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .fixedSize()
    }
}

extension Repetition {
    /// « lun », « 1er », « jour » : de quoi reconnaître la Répétition d'un coup d'œil.
    var shortLabel: String {
        switch unit {
        case .day: every == 1 ? "jour" : "\(every) j"
        case .week: every == 1 ? "sem" : "\(every) sem"
        case .month: every == 1 ? "mois" : "\(every) mois"
        case .year: every == 1 ? "an" : "\(every) ans"
        }
    }
}

/// Une petite pastille de texte, teintée.
struct Badge: View {
    let text: String
    var symbol: String? = nil
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 1.5)
        .background(RoundedRectangle(cornerRadius: 4).fill(tint.opacity(0.14)))
    }
}

// MARK: - Menus d'action

/// Les choix de report, partagés par le menu contextuel et l'éditeur.
struct WhenMenuItems: View {
    let today: Day
    let calendar: Calendar
    let set: (When?) -> Void

    var body: some View {
        Button("Aujourd'hui") { set(.day(today)) }
        Button("Demain") { set(.day(today.adding(1, .day, calendar: calendar))) }
        Button("Ce week-end") { set(.day(today.weekend(calendar: calendar))) }
        Button("Semaine prochaine") { set(.day(today.next(weekday: 2, calendar: calendar))) }
        Button("Un jour") { set(.someday) }
        Divider()
        Button("Sans date") { set(nil) }
    }
}

/// Le menu contextuel d'une Tâche.
struct TaskContextMenu: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem

    var body: some View {
        if task.isOpen {
            Menu("Reporter") {
                WhenMenuItems(today: store.today, calendar: store.calendar) { store.setWhen(task.id, $0) }
            }
            Menu("Projet") {
                Button("Aucun") { store.edit(task.id) { $0.projectID = nil } }
                Divider()
                ForEach(store.projects) { project in
                    Button(project.name) { store.edit(task.id) { $0.projectID = project.id } }
                }
            }
            Button(task.flagged ? "Retirer le drapeau" : "Mettre un drapeau") {
                store.edit(task.id) { $0.flagged.toggle() }
            }
            Divider()
            Button("Marquer comme faite") { store.close(task.id) }
            Button("Annuler la tâche") { store.close(task.id, as: .cancelled) }
        } else {
            Button("Rouvrir") { store.reopen(task.id) }
        }
        Divider()
        Button("Supprimer", role: .destructive) { store.delete(task.id) }
    }
}

// MARK: - Nouvelle tâche

/// Le champ qui crée une Tâche, avec en dessous ce que Maxwell a compris de la ligne.
struct NewTaskField: View {
    @EnvironmentObject private var store: TaskStore
    /// La liste où la Tâche doit apparaître ; nil pour la Boîte de réception par défaut.
    let list: TaskList?
    var placeholder = "Nouvelle tâche"
    var large = false
    /// Le champ de commande de la fenêtre Maxwell : fond sombre, invite « › ».
    var console = false
    var focus: FocusState<Bool>.Binding? = nil
    /// Après la création ; `keepOpen` vaut true quand Max a tapé ⇧Entrée.
    var onCreate: (TaskItem, _ keepOpen: Bool) -> Void = { _, _ in }

    @State private var text = ""

    var body: some View {
        let entry = QuickEntry.parse(text, today: store.today, calendar: store.calendar)
        VStack(alignment: .leading, spacing: large ? 8 : 5) {
            HStack(spacing: large ? 10 : 9) {
                if console {
                    Text("›").font(Console.mono(14, weight: .semibold)).foregroundStyle(Console.accent)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: large ? 20 : 15))
                        .foregroundStyle(Theme.accent)
                }
                field
                    .textFieldStyle(.plain)
                    .font(.system(size: large ? 20 : 13))
                    .onSubmit { submit() }
            }
            .padding(.horizontal, large ? 0 : 10)
            .padding(.vertical, large ? 0 : 8)
            .background {
                if console {
                    RoundedRectangle(cornerRadius: 7).fill(Console.field)
                } else if !large {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.045))
                }
            }
            let chips = chips(for: entry)
            // En grand, la ligne garde sa place pour que le panneau ne change pas de taille.
            if !chips.isEmpty || large {
                HStack(spacing: 6) {
                    ForEach(chips, id: \.self) { chip in
                        Badge(text: chip, tint: console ? Console.accent : Theme.accent)
                    }
                }
                .font(console ? Console.mono(11) : .system(size: large ? 12 : 11))
                .frame(height: large ? 20 : nil)
                .padding(.leading, large ? 30 : 32)
            }
        }
    }

    @ViewBuilder private var field: some View {
        if let focus {
            TextField(placeholder, text: $text).focused(focus)
        } else {
            TextField(placeholder, text: $text)
        }
    }

    private func chips(for entry: QuickEntry) -> [String] {
        guard !text.isEmpty else { return [] }
        var chips: [String] = []
        if let when = entry.when { chips.append(formatWhen(when, today: store.today)) }
        if let deadline = entry.deadline { chips.append("Échéance \(formatDay(deadline, today: store.today))") }
        if let project = entry.projectName {
            let existing = store.projects.first { TaskStore.folded($0.name) == TaskStore.folded(project) }
            chips.append(existing.map { "# \($0.name)" } ?? "# \(project) (nouveau)")
        }
        if entry.flagged { chips.append("Drapeau") }
        return chips
    }

    private func submit() {
        let keepOpen = NSEvent.modifierFlags.contains(.shift)
        guard let task = store.add(text: text, in: list) else { return }
        text = ""
        onCreate(task, keepOpen)
    }
}

// MARK: - Suppression

/// En bas de la liste, quelques secondes : « … supprimée · Annuler » après une suppression,
/// ou « Annulé : … » après une annulation.
struct DeletedBanner: View {
    @EnvironmentObject private var store: TaskStore

    var body: some View {
        if let task = store.lastDeleted {
            capsule {
                Image(systemName: "trash").foregroundStyle(.secondary)
                Text("« \(task.title) » supprimée")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Annuler (u)") { store.undoDelete() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.accent)
                    .fontWeight(.semibold)
            }
            .task(id: task.id) {
                try? await Task.sleep(for: .seconds(6))
                if store.lastDeleted?.id == task.id { store.forgetDeletion() }
            }
        } else if let notice = store.notice {
            capsule {
                Image(systemName: "arrow.uturn.backward").foregroundStyle(.secondary)
                Text(notice).lineLimit(1).truncationMode(.middle)
            }
            .task(id: notice) {
                try? await Task.sleep(for: .seconds(3))
                if store.notice == notice { store.clearNotice() }
            }
        }
    }

    private func capsule<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 10, content: content)
            .font(.system(size: 12))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Capsule().fill(.regularMaterial).shadow(color: .black.opacity(0.15), radius: 6, y: 2))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Le titre d'une Tâche sur une ligne. Ses liens sont raccourcis (« github ↗ ») et sont de vrais liens :
/// le curseur devient une main au survol, un clic les ouvre.
struct TaskTitle: View {
    let title: String
    let isOpen: Bool

    var body: some View {
        let segments = TaskLinks.segments(of: title)
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    Text(text)
                        .strikethrough(!isOpen, color: .secondary)
                        .foregroundStyle(isOpen ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                case .link(let url):
                    LinkChip(url: url, font: .system(size: 13))
                        .fixedSize()
                }
            }
        }
        .font(.system(size: 13))
    }
}

/// Un lien en court, « slack ↗ », qui s'ouvre d'un clic. Au survol, il se souligne et le curseur devient une main.
struct LinkChip: View {
    let url: URL
    var font: Font = .system(size: 11, design: .monospaced)
    @State private var hovering = false

    var body: some View {
        Link(destination: url) {
            Text("\(TaskLinks.label(for: url)) ↗")
                .font(font)
                .underline(hovering)
        }
        .foregroundStyle(Console.accent)
        .pointerStyle(.link)
        .onHover { hovering = $0 }
        .help(url.absoluteString)
    }
}

/// Le repère d'une Tâche confiée à Claude : ce qu'il fait en ce moment, ou comment ça s'est fini.
struct ClaudeMark: View {
    let state: ClaudeTrace.State
    /// L'étape en cours, montrée seulement pendant que Claude travaille.
    var activity: String?
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 5) {
            Text("◆")
                .opacity(state == .running && pulsing ? 0.3 : 1)
                .animation(state == .running ? .easeInOut(duration: 0.8).repeatForever() : nil, value: pulsing)
            switch state {
            case .running: Text(activity ?? "claude travaille").lineLimit(1).truncationMode(.tail).frame(maxWidth: 220, alignment: .trailing)
            case .done: Text("compte rendu")
            case .failed: Text("échec")
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(state == .failed ? Color(nsColor: .systemRed) : Console.accent)
        .onAppear { pulsing = true }
        .help(state == .running ? "Claude travaille sur cette tâche" : "Ouvre la tâche pour lire ce que Claude a rendu")
    }
}
