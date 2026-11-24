import AppKit
import SwiftUI

/// Le module Tâches, en style Console : les listes à gauche, la liste choisie à droite,
/// le champ de création en haut et les raccourcis rappelés en bas.
///
/// Dans la liste, tout se fait d'une touche (voir `TaskNavigation.handle`) : la fenêtre
/// les lui passe tant que Max n'écrit pas dans un champ.
struct TasksView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var navigation: TaskNavigation
    @State private var renaming: ProjectID?
    @State private var projectName = ""
    @FocusState private var fieldFocused: Bool

    static var mainLists: [TaskList] { TaskNavigation.mainLists }

    private var selection: TaskList {
        get { navigation.selection }
        nonmutating set { navigation.selection = newValue }
    }
    private var selectedTask: TaskID? {
        get { navigation.selectedTask }
        nonmutating set { navigation.selectedTask = newValue }
    }
    private var expanded: TaskID? {
        get { navigation.expanded }
        nonmutating set { navigation.expanded = newValue }
    }
    private var justClosed: Set<TaskID> { navigation.justClosed }

    var body: some View {
        HStack(spacing: 0) {
            listColumn
                .frame(width: 214)
                .background(Console.bar.opacity(0.6))
            Rectangle().fill(Console.line).frame(width: 1)
            detail
        }
        .onChange(of: navigation.focusNewTask) { _, focus in
            guard focus else { return }
            fieldFocused = true
            navigation.focusNewTask = false
        }
        .onAppear {
            navigation.selectFirstIfNeeded(in: store)
            // La demande a pu arriver avant que le champ existe.
            if navigation.focusNewTask {
                fieldFocused = true
                navigation.focusNewTask = false
            }
        }
        .onChange(of: navigation.selection) { navigation.selectFirstIfNeeded(in: store) }
        .onChange(of: fieldFocused) { _, focused in navigation.newTaskFocused = focused }
        .onDisappear { navigation.justClosed = [] }
    }

    // MARK: - Listes

    private var listColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(Self.mainLists.enumerated()), id: \.offset) { index, list in
                    ListButton(title: list.title, symbol: list.consoleSymbol, key: nil,
                               count: badge(for: list), selected: selection == list,
                               focused: navigation.pane == .lists) { choose(list) }
                        .help("Touche \(index + 1)")
                }

                HStack {
                    Text("PROJETS").font(Console.mono(10, weight: .medium)).tracking(1)
                    Spacer()
                    Button { newProject() } label: { Image(systemName: "plus").font(.system(size: 10)) }
                        .buttonStyle(.plain)
                        .help("Nouveau projet")
                }
                .foregroundStyle(Console.muted)
                .padding(.horizontal, 10)
                .padding(.top, 18)
                .padding(.bottom, 4)

                ForEach(store.projects) { project in
                    projectRow(project)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
    }

    /// Un clic sur une liste la montre et rend les flèches à ses Tâches.
    private func choose(_ list: TaskList) {
        navigation.pane = .tasks
        selection = list
        navigation.selectFirstIfNeeded(in: store)
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func badge(for list: TaskList) -> Int {
        switch list {
        case .inbox, .today: store.count(of: list)
        default: 0
        }
    }

    @ViewBuilder private func projectRow(_ project: Project) -> some View {
        let list = TaskList.project(project.id)
        if renaming == project.id {
            TextField("Nom du projet", text: $projectName)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 5).fill(Console.field))
                .onSubmit {
                    store.renameProject(project.id, to: projectName)
                    renaming = nil
                }
                .onExitCommand { renaming = nil }
        } else {
            ListButton(title: project.name, symbol: nil, key: nil, count: store.count(of: list),
                       selected: selection == list, focused: navigation.pane == .lists,
                       progress: progress(of: project.id)) { choose(list) }
                .contextMenu {
                    Button("Renommer") {
                        projectName = project.name
                        renaming = project.id
                    }
                    Button(project.folder == nil ? "Choisir le dossier…" : "Changer de dossier…") {
                        chooseFolder(for: project)
                    }
                    if project.folder != nil {
                        Button("Retirer le dossier") { store.setProjectFolder(project.id, to: nil) }
                    }
                    Divider()
                    Button("Archiver le projet") {
                        if selection == list { selection = .today }
                        store.archiveProject(project.id)
                    }
                }
        }
    }

    /// Le dossier du Projet, souvent un dépôt : c'est là que Claude travaille sur ses Tâches.
    private func chooseFolder(for project: Project) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choisir"
        panel.message = "Le dossier où Claude travaille sur les tâches de « \(project.name) »"
        if let folder = project.folder { panel.directoryURL = URL(fileURLWithPath: folder) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.setProjectFolder(project.id, to: url.path)
    }

    private func newProject() {
        let names = Set(store.projects.map { TaskStore.folded($0.name) })
        var name = "Nouveau projet"
        var n = 2
        while names.contains(TaskStore.folded(name)) {
            name = "Nouveau projet \(n)"
            n += 1
        }
        let project = store.projectNamed(name)
        selection = .project(project.id)
        projectName = project.name
        renaming = project.id
    }

    /// La part des Tâches du Projet déjà Faites.
    private func progress(of project: ProjectID) -> Double {
        let tasks = store.tasks.filter { $0.projectID == project && $0.state != .cancelled }
        guard !tasks.isEmpty else { return 0 }
        return Double(tasks.filter { $0.state == .done }.count) / Double(tasks.count)
    }

    // MARK: - Liste choisie

    private var detail: some View {
        let tasks = store.tasks(in: selection, keeping: justClosed)
        return VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 18)

            if selection != .history {
                NewTaskField(list: selection, placeholder: placeholder, console: true, focus: $fieldFocused) { task, _ in
                    // La Tâche créée est choisie : après Échap, les touches agissent sur elle.
                    navigation.pane = .tasks
                    navigation.selectedTask = task.id
                }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
            }

            if tasks.isEmpty {
                Spacer()
                Text(emptyText)
                    .font(Console.mono(12))
                    .foregroundStyle(Console.muted)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                taskList(tasks)
            }

            hintBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Un clic dans le vide quitte le champ de création : les touches reviennent à la liste.
        .background {
            Color.clear.contentShape(Rectangle()).onTapGesture { NSApp.keyWindow?.makeFirstResponder(nil) }
        }
        .overlay(alignment: .top) {
            if navigation.picker != nil {
                ProjectPickerView().padding(.top, 70)
            } else if navigation.launcher != nil {
                ClaudeLauncherView().padding(.top, 70)
            }
        }
        .overlay(alignment: .bottom) {
            DeletedBanner()
                .padding(.bottom, 44)
                .animation(.easeOut(duration: 0.2), value: store.lastDeleted?.id)
                .animation(.easeOut(duration: 0.2), value: store.notice)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title.uppercased())
                .font(Console.mono(12, weight: .semibold))
                .tracking(1.5)
            if let subtitle {
                Text(subtitle)
                    .font(Console.mono(11))
                    .foregroundStyle(Console.muted)
            }
            Spacer()
            let count = store.tasks(in: selection).count
            if count > 0 {
                Text("\(count)").font(Console.mono(12)).foregroundStyle(Console.secondary)
            }
        }
    }

    private var title: String {
        if case .project(let id) = selection { return store.project(id)?.name ?? "Projet" }
        return selection.title
    }

    private var subtitle: String? {
        switch selection {
        case .today:
            return store.today.date(calendar: store.calendar)
                .formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_FR")))
        case .project(let id):
            let tasks = store.tasks.filter { $0.projectID == id && $0.state != .cancelled }
            let done = tasks.filter { $0.state == .done }.count
            let folder = store.project(id)?.folder.map { ($0 as NSString).abbreviatingWithTildeInPath }
            let progress = tasks.isEmpty ? nil : "\(done)/\(tasks.count) faites"
            return [progress, folder ?? "sans dossier"].compactMap { $0 }.joined(separator: " · ")
        default:
            return nil
        }
    }

    private var placeholder: String {
        switch selection {
        case .today: "Nouvelle tâche pour aujourd'hui"
        case .someday: "Nouvelle tâche pour un jour"
        default: "Nouvelle tâche · demain, avant ven, #projet, !"
        }
    }

    private var emptyText: String {
        switch selection {
        case .inbox: "Rien à ranger."
        case .today: "Rien de prévu aujourd'hui."
        case .upcoming: "Rien de prévu pour la suite."
        case .someday: "Aucune idée en attente."
        case .history: "Rien de fait pour l'instant."
        case .project: "Aucune tâche dans ce projet."
        }
    }

    /// Les lignes dans l'ordre où la liste les montre, avec les en-têtes de jour pour À venir.
    private enum Line: Identifiable {
        case day(Day)
        case task(TaskItem)

        var id: String {
            switch self {
            case .day(let day): "d\(day)"
            case .task(let task): "t\(task.id)"
            }
        }
    }

    private func lines(_ tasks: [TaskItem]) -> [Line] {
        guard selection == .upcoming else { return tasks.map(Line.task) }
        let today = store.today
        var result: [Line] = []
        var current: Day?
        for task in tasks {
            var open = task
            open.state = .open
            let day = open.upcomingDay(today: today) ?? today
            if day != current {
                result.append(.day(day))
                current = day
            }
            result.append(.task(task))
        }
        return result
    }

    private func taskList(_ tasks: [TaskItem]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(lines(tasks)) { line in
                        switch line {
                        case .day(let day):
                            DayHeader(day: day, today: store.today, calendar: store.calendar)
                        case .task(let task):
                            row(task).id(task.id)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onChange(of: navigation.selectedTask) { _, id in
                if let id { withAnimation(.easeOut(duration: 0.1)) { proxy.scrollTo(id) } }
            }
        }
    }

    @ViewBuilder private func row(_ task: TaskItem) -> some View {
        if expanded == task.id {
            TaskEditor(task: task) {
                expanded = nil
                // Rend le clavier à la liste, pour enchaîner avec ses touches.
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
            .padding(.vertical, 6)
        } else {
            TaskRow(task: task, showsProject: !isProjectList, showsWhen: selection != .upcoming) {
                navigation.toggle($0.id, store: store)
            }
                .padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: 6)
                    // La sélection pâlit quand les flèches sont dans la colonne des listes.
                    // Pas de surbrillance tant que le curseur est dans le champ de création : c'est lui qui a la main.
                    .fill(selectedTask != task.id || fieldFocused ? Color.clear
                          : navigation.pane == .tasks ? Console.selection : Console.field))
                .contentShape(Rectangle())
                // Des gestes simultanés : un clic sur un lien de la ligne l'ouvre, au lieu d'être pris par la sélection.
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    navigation.pane = .tasks
                    selectedTask = task.id
                    expanded = task.id
                })
                .simultaneousGesture(TapGesture().onEnded {
                    navigation.pane = .tasks
                    selectedTask = task.id
                    // Un clic dans la liste quitte le champ de création : les touches reviennent à la liste.
                    NSApp.keyWindow?.makeFirstResponder(nil)
                })
                .contextMenu { TaskContextMenu(task: task) }
        }
    }

    private var hintBar: some View {
        HStack(spacing: 14) {
            ForEach(hints, id: \.0) { key, label in
                HStack(spacing: 5) {
                    Text(key).foregroundStyle(Console.secondary)
                    Text(label)
                }
                .lineLimit(1)
                .fixedSize()
            }
            Spacer(minLength: 0)
        }
        // Une fenêtre étroite coupe les derniers rappels plutôt que de les replier sur deux lignes.
        .clipped()
        .font(Console.mono(10.5))
        .foregroundStyle(Console.muted)
        .padding(.horizontal, 22)
        .frame(height: 30)
        .background(Console.bar.opacity(0.6))
        .overlay(alignment: .top) { Rectangle().fill(Console.line).frame(height: 1) }
    }

    private var hints: [(String, String)] {
        if navigation.picker != nil { return [("↑↓", "choisir"), ("↩", "ranger"), ("esc", "fermer")] }
        if navigation.launcher != nil { return [("↩", "lancer Claude"), ("⇥", "changer de modèle"), ("esc", "renoncer")] }
        if expanded != nil { return [("esc", "replier"), ("↩", "valider le titre")] }
        if fieldFocused { return [("↩", "créer"), ("⇧↩", "créer et continuer"), ("↓", "vers les tâches")] }
        if navigation.pane == .lists {
            let empty = navigation.visible(in: store).isEmpty
            return [("↑↓", "changer de liste")] + (empty ? [] : [("→", "vers les tâches")])
                + [("/", "nouvelle tâche"), ("1-5", "listes")]
        }
        return [("↩", "ouvrir"), ("x", "faite"), ("t", "auj."), ("d", "demain"), ("s", "un jour"),
                ("f", "drapeau"), ("p", "projet"), ("c", "claude"), ("o", "lien"), ("⌫", "suppr."), ("u", "annuler")]
    }

    // MARK: - Clavier

    private var isProjectList: Bool {
        if case .project = selection { true } else { false }
    }
}

extension TaskList {
    var consoleSymbol: String {
        switch self {
        case .inbox: "tray"
        case .today: "sun.max"
        case .upcoming: "calendar"
        case .someday: "archivebox"
        case .history: "checkmark.circle"
        case .project: "circle"
        }
    }
}

/// Une liste dans la colonne de gauche : icône, nom, touche, nombre.
private struct ListButton: View {
    let title: String
    let symbol: String?
    let key: String?
    let count: Int
    let selected: Bool
    /// Vrai quand les flèches sont dans la colonne des listes : la liste choisie est cerclée.
    var focused = false
    var progress: Double? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Group {
                    if let symbol {
                        Image(systemName: symbol)
                    } else {
                        ProjectProgress(progress: progress ?? 0, size: 11)
                    }
                }
                .font(.system(size: 12))
                .frame(width: 16)
                .foregroundStyle(selected ? Console.accent : Console.muted)
                Text(title).lineLimit(1)
                Spacer(minLength: 4)
                if count > 0 {
                    Text("\(count)").font(Console.mono(11)).foregroundStyle(Console.secondary)
                }
                if let key {
                    Text(key).font(Console.mono(10)).foregroundStyle(Console.muted.opacity(0.8))
                }
            }
            .font(.system(size: 12.5))
            .foregroundStyle(selected ? Console.text : Console.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6)
                .fill(selected ? (focused ? Console.selection : Console.field) : hovering ? Console.hover : .clear))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(selected && focused ? Console.accent.opacity(0.6) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// L'icône d'un Projet : un cercle qui se remplit à mesure que ses Tâches sont faites.
struct ProjectProgress: View {
    let progress: Double
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            Circle().strokeBorder(Console.accent, lineWidth: max(size * 0.12, 1.2))
            Pie(progress: progress)
                .fill(Console.accent)
                .padding(size * 0.24)
        }
        .frame(width: size, height: size)
    }
}

/// Un quartier de disque, de midi jusqu'à `progress`.
private struct Pie: Shape {
    let progress: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(center: center, radius: rect.width / 2, startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * progress), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// L'en-tête d'un jour dans À venir : « LUN 23 », et le mois au-delà d'une semaine.
private struct DayHeader: View {
    let day: Day
    let today: Day
    let calendar: Calendar

    var body: some View {
        let french = Locale(identifier: "fr_FR")
        let date = day.date(calendar: calendar)
        let gap = today.days(to: day, calendar: calendar)
        let weekday = date.formatted(.dateTime.weekday(.abbreviated).locale(french))
            .replacingOccurrences(of: ".", with: "")
        let month = gap > 6 ? " " + date.formatted(.dateTime.month(.abbreviated).locale(french)) : ""
        HStack(spacing: 8) {
            Text("\(weekday) \(day.day)\(month)".uppercased())
                .font(Console.mono(11, weight: .semibold))
                .foregroundStyle(gap == 1 ? Console.accent : Console.secondary)
            if gap == 1 {
                Text("demain").font(Console.mono(11)).foregroundStyle(Console.muted)
            }
            Rectangle().fill(Console.line).frame(height: 1)
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }
}

/// Le sélecteur de Projet, ouvert par « p » sur une Tâche : on tape pour filtrer, ↩ range la Tâche.
private struct ProjectPickerView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var navigation: TaskNavigation
    @FocusState private var focused: Bool

    var body: some View {
        let options = navigation.pickerOptions(in: store)
        let index = navigation.picker?.index ?? 0
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("#").font(Console.mono(14, weight: .semibold)).foregroundStyle(Console.accent)
                TextField("Projet", text: Binding(
                    get: { navigation.picker?.query ?? "" },
                    set: {
                        navigation.picker?.query = $0
                        navigation.picker?.index = 0
                    }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if !options.isEmpty {
                Rectangle().fill(Console.line).frame(height: 1)
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(options.enumerated()), id: \.offset) { offset, option in
                        row(option, selected: offset == index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                navigation.picker?.index = offset
                                navigation.applyPicker(store: store)
                                NSApp.keyWindow?.makeFirstResponder(nil)
                            }
                    }
                }
                .padding(6)
            }
        }
        .frame(width: 340)
        .background(RoundedRectangle(cornerRadius: 10).fill(Console.field))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Console.accent.opacity(0.4)))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 6)
        .onAppear { focused = true }
    }

    private func row(_ option: TaskNavigation.PickerOption, selected: Bool) -> some View {
        HStack(spacing: 9) {
            switch option {
            case .project(let project):
                ProjectProgress(progress: 0, size: 10)
                Text(project.name)
                Spacer()
                if let folder = project.folder {
                    Text(URL(fileURLWithPath: folder).lastPathComponent)
                        .font(Console.mono(10.5)).foregroundStyle(Console.muted)
                }
            case .none:
                Image(systemName: "xmark").font(.system(size: 9)).frame(width: 10)
                Text("Aucun projet")
                Spacer()
            case .create(let name):
                Image(systemName: "plus").font(.system(size: 9)).frame(width: 10)
                Text("Créer « \(name) »")
                Spacer()
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(selected ? Console.text : Console.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Console.selection : .clear))
    }
}

/// Avant de confier une Tâche à Claude : où il va travailler, ce qu'il a le droit de faire,
/// et une précision facultative. ↩ lance, Échap renonce.
private struct ClaudeLauncherView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var navigation: TaskNavigation
    @EnvironmentObject private var claude: ClaudeRunner
    @FocusState private var focused: Bool

    var body: some View {
        if let launcher = navigation.launcher, let task = store.task(launcher.taskID) {
            let project = store.project(task.projectID)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text("◆").foregroundStyle(Console.accent)
                    Text("Confier à Claude").font(.system(size: 13, weight: .semibold))
                }
                Text(task.title).font(.system(size: 13)).lineLimit(2)

                VStack(alignment: .leading, spacing: 4) {
                    line("dossier", project?.folder.map { ($0 as NSString).abbreviatingWithTildeInPath }
                        ?? (project == nil ? "aucun : la tâche n'a pas de projet" : "aucun : le projet « \(project!.name) » n'a pas de dossier"),
                         warning: project?.folder == nil)
                    line("claude peut", ClaudeAutonomy.current.label, warning: false)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("modèle").foregroundStyle(Console.muted).frame(width: 84, alignment: .leading)
                        ForEach(ClaudeModel.allCases) { model in
                            Text(model.label)
                                .foregroundStyle(model == launcher.model ? Console.background : Console.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 3)
                                    .fill(model == launcher.model ? Console.accent : .clear))
                                .contentShape(Rectangle())
                                .onTapGesture { navigation.launcher?.model = model }
                        }
                    }
                    .font(Console.mono(11))
                }

                TextField("Précision pour Claude (facultatif)", text: Binding(
                    get: { navigation.launcher?.extra ?? "" },
                    set: { navigation.launcher?.extra = $0 }), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...4)
                    .focused($focused)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Console.background))
            }
            .padding(14)
            .frame(width: 460, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Console.field))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Console.accent.opacity(0.4)))
            .shadow(color: .black.opacity(0.4), radius: 18, y: 6)
            .onAppear { focused = true }
        }
    }

    private func line(_ label: String, _ value: String, warning: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).foregroundStyle(Console.muted).frame(width: 84, alignment: .leading)
            Text(value).foregroundStyle(warning ? Console.late : Console.secondary)
        }
        .font(Console.mono(11))
    }
}
