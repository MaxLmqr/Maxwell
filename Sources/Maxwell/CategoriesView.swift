import SwiftUI

/// Gestion des catégories : la liste à gauche, les apps et les sites de la catégorie choisie à droite.
struct CategoriesView: View {
    @EnvironmentObject private var categorizer: Categorizer
    @State private var selection: CategoryID?

    init(initialSelection: CategoryID? = nil) {
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        let _ = categorizer.revision
        let db = categorizer.db
        let categories = db.categories()
        let apps = db.knownApps()
        let counts = Dictionary(grouping: apps, by: \.categoryID).mapValues(\.count)
        let current = selection ?? categories.first?.id

        HStack(spacing: 0) {
            sidebar(categories: categories, counts: counts, current: current)
                .frame(width: 220)
            Divider()
            Group {
                if current == uncategorizedID {
                    CategoryDetail(category: nil, apps: apps.filter { $0.categoryID == uncategorizedID },
                                   categories: categories)
                } else if let category = categories.first(where: { $0.id == current }) {
                    CategoryDetail(category: category, apps: apps.filter { $0.categoryID == category.id },
                                   categories: categories)
                        .id("\(category.id)-\(category.name)")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 640, minHeight: 460)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { categorizer.reclassifyAutomatic() } label: {
                    Label("Reclasser", systemImage: "sparkles")
                }
                .help("Recalcule la catégorie des apps que tu n'as pas classées toi-même")
                .disabled(categorizer.isRunning)
            }
        }
    }

    private func sidebar(categories: [Category], counts: [CategoryID: Int], current: CategoryID?) -> some View {
        let uncategorized = counts[uncategorizedID] ?? 0
        let selected = categories.first { $0.id == current }

        return VStack(spacing: 0) {
            List(selection: Binding(get: { current }, set: { selection = $0 })) {
                if uncategorized > 0 {
                    SidebarRow(name: "À classer", symbol: Category.uncategorizedSymbol,
                               count: uncategorized, hidden: false)
                        .tag(uncategorizedID)
                }
                Section {
                    ForEach(categories) { category in
                        SidebarRow(name: category.name, symbol: category.symbol,
                                   count: counts[category.id] ?? 0, hidden: category.hidden)
                            .tag(category.id)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            HStack(spacing: 2) {
                Button { addCategory(existing: categories) } label: {
                    Image(systemName: "plus").frame(width: 24, height: 22)
                }
                .help("Nouvelle catégorie")
                Button { delete(selected, categories: categories) } label: {
                    Image(systemName: "minus").frame(width: 24, height: 22)
                }
                .help("Supprimer la catégorie : ses apps et ses sites seront reclassés")
                .disabled(selected == nil || selected?.isSystem == true)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
        }
    }

    private func addCategory(existing: [Category]) {
        let names = Set(existing.map(\.name))
        var name = "Nouvelle catégorie"
        var suffix = 2
        while names.contains(name) {
            name = "Nouvelle catégorie \(suffix)"
            suffix += 1
        }
        if let id = categorizer.db.addCategory(name: name) {
            selection = id
            categorizer.changed()
        }
    }

    private func delete(_ category: Category?, categories: [Category]) {
        guard let category, !category.isSystem else { return }
        categorizer.db.deleteCategory(category.id)
        selection = categories.first { $0.id != category.id }?.id
        categorizer.changed()
    }
}

private struct SidebarRow: View {
    let name: String
    let symbol: String
    let count: Int
    let hidden: Bool

    var body: some View {
        HStack {
            Label {
                Text(name).lineLimit(1)
            } icon: {
                Image(systemName: symbol)
            }
            .foregroundStyle(hidden ? .secondary : .primary)
            Spacer()
            if hidden {
                Image(systemName: "eye.slash")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Text("\(count)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private struct CategoryDetail: View {
    @EnvironmentObject private var categorizer: Categorizer
    /// nil pour les apps et les sites « À classer ».
    let category: Category?
    let apps: [KnownApp]
    let categories: [Category]
    @State private var name: String
    @FocusState private var nameFocused: Bool

    init(category: Category?, apps: [KnownApp], categories: [Category]) {
        self.category = category
        self.apps = apps
        self.categories = categories
        _name = State(initialValue: category?.name ?? "À classer")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if apps.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(apps) { app in
                        AppAssignmentRow(app: app, current: category, categories: categories)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
            if let message = categorizer.availabilityMessage {
                Divider()
                Label(message, systemImage: "sparkles")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
        .onAppear {
            if category?.name.hasPrefix("Nouvelle catégorie") == true { nameFocused = true }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            if let category {
                Menu {
                    ForEach(Category.symbolChoices, id: \.self) { symbol in
                        Button {
                            categorizer.db.setSymbol(category.id, symbol)
                            categorizer.changed()
                        } label: {
                            Image(systemName: symbol)
                        }
                    }
                } label: {
                    CategoryBadge(symbol: category.symbol, fill: Theme.accent.opacity(0.14),
                                  glyph: Theme.accent, size: 40)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Changer le pictogramme")
            } else {
                CategoryBadge(symbol: Category.uncategorizedSymbol, fill: Theme.othersFill,
                              glyph: .secondary, size: 40)
            }

            VStack(alignment: .leading, spacing: 2) {
                if category != nil {
                    TextField("Nom", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20, weight: .semibold))
                        .focused($nameFocused)
                        .onSubmit(rename)
                } else {
                    Text("À classer").font(.system(size: 20, weight: .semibold))
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let category {
                Toggle("Dans les récaps", isOn: Binding(
                    get: { !category.hidden },
                    set: { visible in
                        categorizer.db.setHidden(category.id, !visible)
                        categorizer.changed()
                    }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(Theme.accent)
                    .font(.system(size: 12))
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    private var subtitle: String {
        let sites = apps.filter { $0.site != nil }.count
        let count = [(apps.count - sites, "app"), (sites, "site")]
            .filter { $0.0 > 0 }
            .map { "\($0.0) \($0.1)\($0.0 > 1 ? "s" : "")" }
            .joined(separator: " et ")
        if category == nil { return "\(count) en attente de catégorie" }
        if category?.hidden == true { return "\(count) · masquée : son temps n'est pas compté" }
        let time = apps.reduce(0) { $0 + $1.totalDuration }
        return time >= 60 ? "\(count) · \(formatDuration(time)) au total" : count
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: category?.symbol ?? Category.uncategorizedSymbol)
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
            Text("Aucune app ni aucun site dans cette catégorie")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Fais un clic droit sur une app ou un site dans le récap pour l'y ranger.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rename() {
        guard let category else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != category.name else {
            name = category.name
            return
        }
        categorizer.db.renameCategory(category.id, to: trimmed)
        categorizer.changed()
    }
}

private struct AppAssignmentRow: View {
    @EnvironmentObject private var categorizer: Categorizer
    let app: KnownApp
    let current: Category?
    let categories: [Category]

    var body: some View {
        HStack(spacing: 10) {
            SubjectIcon(subject: app.subject, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                origin
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(formatDuration(app.totalDuration))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Menu { moveMenu } label: {
                Text(current == nil ? "Classer" : "Déplacer")
            }
            .menuStyle(.button)
            .controlSize(.small)
            .fixedSize()
        }
        .padding(.vertical, 3)
        .contextMenu { moveMenu }
    }

    @ViewBuilder private var origin: some View {
        // « une app classée », « un site classé ».
        let classified = app.site == nil ? "classée" : "classé"
        if current == nil {
            Text("Pas encore \(classified)")
        } else if app.manual {
            Text("\(classified.capitalized) par toi")
        } else if app.site != nil {
            Text("Suit la catégorie de Chrome")
        } else {
            Label("Classée par Apple Intelligence", systemImage: "sparkles")
                .labelStyle(.titleAndIcon)
        }
    }

    @ViewBuilder private var moveMenu: some View {
        ForEach(categories.filter { $0.id != current?.id }) { category in
            Button {
                categorizer.db.setCategory(category.id, for: app.subject, manual: true)
                categorizer.changed()
            } label: {
                Label(category.name, systemImage: category.symbol)
            }
        }
        if app.manual {
            Divider()
            Button(app.site == nil ? "Laisser l'IA choisir" : "Suivre la catégorie de Chrome") {
                categorizer.db.setCategory(uncategorizedID, for: app.subject, manual: false)
                categorizer.changed()
            }
        }
    }
}
