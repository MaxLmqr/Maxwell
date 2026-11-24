import SwiftUI

/// Une Tâche dépliée sur place, en carte : titre, note, checklist, et en bas ses réglages.
/// Les réglages choisis s'affichent en pastilles ; les autres restent des icônes discrètes à droite.
/// Chaque changement est enregistré aussitôt.
struct TaskEditor: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var claude: ClaudeRunner
    @State private var task: TaskItem
    @State private var newItem = ""
    @State private var showsChecklist: Bool
    @FocusState private var titleFocused: Bool
    var onClose: () -> Void

    init(task: TaskItem, onClose: @escaping () -> Void) {
        _task = State(initialValue: task)
        _showsChecklist = State(initialValue: !task.checklist.isEmpty)
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TaskCheckbox(state: task.state) {
                    onClose()
                    if task.isOpen { store.close(task.id) } else { store.reopen(task.id) }
                }
                TextField("Nouvelle tâche", text: $task.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold))
                    .focused($titleFocused)
                    .onSubmit(onClose)
            }

            TextField("Notes", text: $task.note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1...10)
                .padding(.leading, 25)

            let links = task.links
            if !links.isEmpty {
                HStack(spacing: 12) {
                    ForEach(links, id: \.self) { LinkChip(url: $0) }
                }
                .padding(.leading, 25)
            }

            // Lu dans le store, pas dans la copie en cours d'édition : Claude l'écrit pendant ce temps.
            if let trace = store.task(task.id)?.claude {
                claudeSection(trace).padding(.leading, 25).padding(.top, 2)
            }

            if showsChecklist {
                checklist.padding(.leading, 25).padding(.top, 2)
            }

            footer.padding(.leading, 25).padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Console.field))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Console.accent.opacity(0.35)))
        .padding(.horizontal, 2)
        .onChange(of: task) { _, task in
            guard !task.title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            store.update(task)
        }
        .onExitCommand(perform: onClose)
        .onAppear { titleFocused = true }
    }

    /// Ce que Claude a fait de la Tâche : l'étape en cours, puis son compte rendu, et de quoi reprendre la session.
    private func claudeSection(_ trace: ClaudeTrace) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ClaudeMark(state: trace.state, activity: claude.activity[task.id])
                Spacer()
                if trace.state == .running {
                    Button("arrêter") { claude.stop(task.id) }
                } else {
                    Button("reprendre dans le terminal") {
                        if let current = store.task(task.id) { claude.resume(current) }
                    }
                    .help("Ouvre la session dans \(ClaudeRunner.ghostty == nil ? "Terminal" : "Ghostty") ; elle est aussi dans claude agents, et la commande est copiée")
                    if ClaudeRunner.desktop != nil {
                        Button("ouvrir dans Claude Desktop") {
                            if let current = store.task(task.id) { claude.openInDesktop(current) }
                        }
                        .help("Ajoute la session à la liste de Claude Desktop, pour la poursuivre là-bas")
                    }
                    Button("relancer") { claude.start(task.id) }
                }
            }
            .buttonStyle(.plain)
            .font(Console.mono(11))
            .foregroundStyle(Console.secondary)

            if let result = trace.result, !result.isEmpty {
                ScrollView {
                    Text(result)
                        .font(.system(size: 12))
                        .foregroundStyle(Console.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Console.background))
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach($task.checklist) { $item in
                HStack(spacing: 8) {
                    TaskCheckbox(state: item.done ? .done : .open, size: 12) { item.done.toggle() }
                    TextField("", text: $item.title)
                        .textFieldStyle(.plain)
                        .strikethrough(item.done, color: .secondary)
                        .foregroundStyle(item.done ? .secondary : .primary)
                    Button {
                        task.checklist.removeAll { $0.id == item.id }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .help("Retirer de la checklist")
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 12)
                TextField("Ajouter un élément", text: $newItem)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        let title = newItem.trimmingCharacters(in: .whitespaces)
                        guard !title.isEmpty else { return }
                        task.checklist.append(ChecklistItem(title: title))
                        newItem = ""
                    }
            }
        }
        .font(.system(size: 12))
    }

    private var footer: some View {
        let today = store.today
        return HStack(spacing: 6) {
            // Ce qui est réglé, en pastilles.
            if let when = task.when {
                WhenButton(when: $task.when, today: today, calendar: store.calendar) {
                    Chip(text: formatWhen(when, today: today), symbol: when == .someday ? "archivebox" : "calendar",
                         tint: .secondary) { task.when = nil }
                }
            }
            if let deadline = task.deadline {
                DayButton(day: $task.deadline, today: today) {
                    Chip(text: "Échéance \(formatDay(deadline, today: today).lowercased())", symbol: "flag.checkered",
                         tint: .red) { task.deadline = nil }
                }
            }
            if let project = store.project(task.projectID) {
                projectMenu {
                    Chip(text: project.name, symbol: "circle.circle", tint: Console.accent) { task.projectID = nil }
                }
            }
            if let repetition = task.repetition {
                repetitionMenu {
                    Chip(text: repetition.label, symbol: "repeat", tint: .secondary) { task.repetition = nil }
                }
            }

            Spacer(minLength: 8)

            // Ce qui ne l'est pas, en icônes.
            HStack(spacing: 2) {
                if task.when == nil {
                    WhenButton(when: $task.when, today: today, calendar: store.calendar) {
                        IconButtonLabel(symbol: "calendar", help: "Quand")
                    }
                }
                if task.deadline == nil {
                    DayButton(day: $task.deadline, today: today) {
                        IconButtonLabel(symbol: "flag.checkered", help: "Échéance")
                    }
                }
                if task.projectID == nil, !store.projects.isEmpty {
                    projectMenu { IconButtonLabel(symbol: "circle.circle", help: "Projet") }
                }
                if task.repetition == nil {
                    repetitionMenu { IconButtonLabel(symbol: "repeat", help: "Répéter") }
                }
                if !showsChecklist {
                    Button { showsChecklist = true } label: { IconButtonLabel(symbol: "checklist", help: "Checklist") }
                        .buttonStyle(.plain)
                }
                Button {
                    onClose()
                    store.delete(task.id)
                } label: {
                    IconButtonLabel(symbol: "trash", help: "Supprimer la tâche")
                }
                .buttonStyle(.plain)
                Button { task.flagged.toggle() } label: {
                    IconButtonLabel(symbol: task.flagged ? "flag.fill" : "flag",
                                    help: task.flagged ? "Retirer le drapeau" : "Drapeau",
                                    tint: task.flagged ? .orange : nil)
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 11))
    }

    private func projectMenu<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        Menu {
            ForEach(store.projects) { project in
                Button(project.name) { task.projectID = project.id }
            }
            if task.projectID != nil {
                Divider()
                Button("Retirer du projet") { task.projectID = nil }
            }
        } label: {
            label()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func repetitionMenu<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        Menu {
            ForEach(Repetition.Unit.allCases, id: \.self) { unit in
                Button(Repetition(mode: .fixed, every: 1, unit: unit).label) {
                    task.repetition = Repetition(mode: task.repetition?.mode ?? .fixed, every: 1, unit: unit)
                }
            }
            if let repetition = task.repetition {
                Divider()
                Toggle("Compter à partir du jour où elle est faite", isOn: Binding(
                    get: { repetition.mode == .afterCompletion },
                    set: { task.repetition?.mode = $0 ? .afterCompletion : .fixed }))
                Button("Ne plus répéter") { task.repetition = nil }
            }
        } label: {
            label()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

/// Un réglage choisi : une pastille teintée, avec une croix pour l'effacer.
struct Chip: View {
    let text: String
    let symbol: String
    let tint: Color
    let clear: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(text).lineLimit(1)
            if hovering {
                // Un geste prioritaire : la pastille est elle-même dans un bouton qui ouvre son réglage.
                Image(systemName: "xmark.circle.fill")
                    .highPriorityGesture(TapGesture().onEnded(clear))
                    .help("Effacer")
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .font(.system(size: 11, design: .monospaced))
        .background(RoundedRectangle(cornerRadius: 4).fill(tint.opacity(0.14)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// Une icône grise de réglage, qui s'éclaire au survol.
struct IconButtonLabel: View {
    let symbol: String
    let help: String
    var tint: Color? = nil
    @State private var hovering = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12))
            .foregroundStyle(tint ?? (hovering ? .primary : .secondary))
            .frame(width: 24, height: 22)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(hovering ? 0.07 : 0)))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .help(help)
    }
}

/// Un bouton qui ouvre un calendrier pour choisir un jour, ou l'effacer.
struct DayButton<Label: View>: View {
    @Binding var day: Day?
    let today: Day
    @ViewBuilder let label: () -> Label
    @State private var picking = false

    var body: some View {
        Button { picking = true } label: { label() }
            .buttonStyle(.plain)
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                VStack(spacing: 8) {
                    DatePicker("", selection: Binding(
                        get: { (day ?? today).date() },
                        set: {
                            day = Day($0)
                            picking = false
                        }), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                    if day != nil {
                        Button("Effacer l'échéance") {
                            day = nil
                            picking = false
                        }
                    }
                }
                .padding(10)
            }
    }
}

/// Le Quand d'une Tâche : les choix courants, et un calendrier pour le reste.
struct WhenButton<Label: View>: View {
    @Binding var when: When?
    let today: Day
    let calendar: Calendar
    @ViewBuilder let label: () -> Label
    @State private var picking = false

    var body: some View {
        Button { picking = true } label: { label() }
            .buttonStyle(.plain)
            .popover(isPresented: $picking, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    WhenMenuItems(today: today, calendar: calendar) {
                        when = $0
                        picking = false
                    }
                    .buttonStyle(MenuRowButtonStyle())
                    DatePicker("", selection: Binding(
                        get: { (when?.day ?? today).date(calendar: calendar) },
                        set: {
                            when = .day(Day($0, calendar: calendar))
                            picking = false
                        }), displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding(.top, 6)
                }
                .padding(8)
                .frame(width: 200)
            }
    }
}
