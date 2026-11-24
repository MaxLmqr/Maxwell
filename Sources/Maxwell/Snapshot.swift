import AppKit
import SwiftUI

/// Dessine chaque écran en PNG, en clair et en sombre, à partir de données de démo.
/// Sert à relire le design sans avoir à capturer l'écran.
@MainActor
enum Snapshot {
    static func run(into folder: URL) {
        NSApplication.shared.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let dbURL = FileManager.default.temporaryDirectory.appendingPathComponent("maxwell-demo.sqlite")
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbURL.path + suffix))
        }
        let db: Database
        do { db = try Database(url: dbURL) } catch { fatalError("Base de démo : \(error)") }
        // MAXWELL_SNAPSHOT_NOW (secondes depuis 1970) fige l'heure : deux séries de captures
        // faites à des moments différents montrent alors exactement les mêmes données.
        let now = ProcessInfo.processInfo.environment["MAXWELL_SNAPSHOT_NOW"]
            .flatMap(Double.init).map(Date.init(timeIntervalSince1970:)) ?? Date()
        DemoData.fill(db, now: now)

        let model = AppModel(db: db, live: false)
        DemoData.fillTasks(model.tasks)
        model.tracker.simulateCurrentApp("Xcode")
        model.tracker.simulateNow(now)
        let categoryID = { (name: String) in db.categories().first { $0.name == name }?.id }
        let files = DemoData.shelfFiles()
        prefetchThumbnails(files)

        for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let expanded = shelf(with: files)
            expanded.isExpanded = true
            let shelves: [(String, Shelf, Bool)] = [
                ("vide", Shelf(), false),
                ("survol", Shelf(), true),
                ("un-fichier", shelf(with: [files[3]]), false),
                ("plusieurs", shelf(with: files), false),
                ("liste", expanded, false),
            ]
            for (name, shelf, targeted) in shelves {
                let view = ShelfView(shelf: shelf, onClose: {}, solidBackground: true, previewTargeted: targeted)
                    .padding(28)
                    .background(Color(nsColor: .underPageBackgroundColor))
                renderView(view, appearance: appearance,
                           to: folder.appendingPathComponent("etagere-\(name)-\(suffix).png"))
            }

            renderView(model.inject(MenuBarView()), appearance: appearance,
                       to: folder.appendingPathComponent("menu-\(suffix).png"))
            renderView(model.inject(QuickEntryPreview()), appearance: appearance,
                       to: folder.appendingPathComponent("saisie-rapide-\(suffix).png"))
            renderWindow(name: "Catégories", size: Windows.categoriesSize,
                         content: model.inject(CategoriesView(initialSelection: categoryID("Navigation"))),
                         appearance: appearance, to: folder.appendingPathComponent("categories-\(suffix).png"))
        }
        // La fenêtre Maxwell est toujours sombre : une seule série.
        model.mainNavigation.module = .time
        for period in Period.allCases {
            model.navigation.period = period
            model.navigation.referenceDate = now
            renderMain(model.inject(MaxwellView()), to: folder.appendingPathComponent("temps-\(period.fileName).png"))
        }
        model.navigation.period = .week
        renderMain(model.inject(MaxwellView(recap: RecapView(previewExpanded: categoryID("Navigation")))),
                   height: 1000, to: folder.appendingPathComponent("temps-detail.png"))
        renderMain(model.inject(MaxwellView(recap: RecapView(previewHovered: categoryID("IA")))),
                   to: folder.appendingPathComponent("temps-survol.png"))
        model.mainNavigation.module = .tasks
        for (name, list) in [("aujourdhui", TaskList.today), ("a-venir", .upcoming), ("reception", .inbox)] {
            model.taskNavigation.selection = list
            renderMain(model.inject(MaxwellView()), to: folder.appendingPathComponent("taches-\(name).png"))
        }
        model.taskNavigation.selection = .today
        let relire = model.tasks.tasks.first { $0.title.hasPrefix("Relire") }?.id
        model.taskNavigation.selectedTask = relire
        model.taskNavigation.expanded = relire
        renderMain(model.inject(MaxwellView()), to: folder.appendingPathComponent("taches-edition.png"))

        // Le pont avec Claude : le compte rendu dans la Tâche dépliée, la confirmation avant de lancer, le choix du Projet.
        let viaClaude = model.tasks.tasks.first { $0.claude != nil }?.id
        model.taskNavigation.selectedTask = viaClaude
        model.taskNavigation.expanded = viaClaude
        renderMain(model.inject(MaxwellView()), to: folder.appendingPathComponent("taches-claude.png"))
        model.taskNavigation.expanded = nil
        model.taskNavigation.selectedTask = relire
        model.taskNavigation.launcher = relire.map { .init(taskID: $0) }
        renderMain(model.inject(MaxwellView()), to: folder.appendingPathComponent("taches-confier.png"))
        model.taskNavigation.launcher = nil
        model.taskNavigation.picker = relire.map { .init(taskID: $0) }
        renderMain(model.inject(MaxwellView()), to: folder.appendingPathComponent("taches-projet.png"))
        model.taskNavigation.picker = nil

        print("✅ Captures dans \(folder.path)")
        exit(0)
    }

    /// Les aperçus Quick Look arrivent en arrière-plan : on les attend avant de dessiner l'Étagère.
    private static func prefetchThumbnails(_ urls: [URL]) {
        final class Counter { var pending = 0 }
        let counter = Counter()
        for url in urls {
            for size in [ShelfLayout.pileThumbnail, 28, 22] {
                counter.pending += 1
                Task {
                    _ = await Thumbnails.shared.load(url, size: size, scale: 2)
                    counter.pending -= 1
                }
            }
        }
        let deadline = Date().addingTimeInterval(8)
        while counter.pending > 0 && Date() < deadline { pump(0.05) }
    }

    private static func shelf(with urls: [URL]) -> Shelf {
        let shelf = Shelf()
        shelf.add(urls)
        return shelf
    }

    /// Une vue seule, sur le fond des fenêtres (pour le menu de la barre de menus).
    private static func renderView<V: View>(_ view: V, appearance: NSAppearance.Name, to url: URL) {
        let hosting = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 400, height: 400),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        show(window)
        window.setContentSize(hosting.fittingSize)
        pump(0.3)
        capture(hosting, to: url)
        window.orderOut(nil)
    }

    /// Une fenêtre complète, barre d'outils comprise, rendue invisible pendant la capture.
    private static func renderWindow<V: View>(name: String, size: NSSize, content: V, showsTitle: Bool = true,
                                              fullSizeContent: Bool = false,
                                              appearance: NSAppearance.Name, to url: URL) {
        let window = Windows.makeWindow(name: name, size: size, content: content,
                                        showsTitle: showsTitle, autosave: false, fullSizeContent: fullSizeContent)
        window.appearance = NSAppearance(named: appearance)
        show(window)
        if let frame = window.contentView?.superview {
            frame.layoutSubtreeIfNeeded()
            capture(frame, to: url)
        }
        window.orderOut(nil)
    }

    /// La fenêtre Maxwell, avec sa barre des modules.
    private static func renderMain<V: View>(_ content: V, height: CGFloat? = nil, to url: URL) {
        let window = Windows.makeMainWindow(content: content, autosave: false)
        if let height { window.setContentSize(NSSize(width: Windows.mainSize.width, height: height)) }
        show(window)
        if let frame = window.contentView?.superview {
            frame.layoutSubtreeIfNeeded()
            capture(frame, to: url)
        }
        window.orderOut(nil)
    }

    private static func show(_ window: NSWindow) {
        window.alphaValue = 0
        window.orderFrontRegardless()
        pump(0.8)
    }

    private static func pump(_ seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private static func capture(_ view: NSView, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

private extension Period {
    var fileName: String {
        switch self {
        case .day: "jour"
        case .week: "semaine"
        case .month: "mois"
        }
    }
}
