import AppKit
import SwiftUI

/// Dessine chaque écran en PNG, en clair et en sombre, à partir de données de démo.
/// Sert à relire le design sans avoir à capturer l'écran.
@MainActor
enum Snapshot {
    static func run(into folder: URL) {
        NSApplication.shared.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let dbURL = FileManager.default.temporaryDirectory.appendingPathComponent("maxactivity-demo.sqlite")
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: dbURL.path + suffix))
        }
        let db: Database
        do { db = try Database(url: dbURL) } catch { fatalError("Base de démo : \(error)") }
        let now = Date()
        DemoData.fill(db, now: now)

        let model = AppModel(db: db, live: false)
        model.tracker.simulateCurrentApp("Xcode")
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
            for period in Period.allCases {
                model.navigation.period = period
                model.navigation.referenceDate = now
                renderWindow(name: "Récap", size: Windows.recapSize, content: model.inject(RecapView()),
                             showsTitle: false, appearance: appearance,
                             to: folder.appendingPathComponent("recap-\(period.fileName)-\(suffix).png"))
            }
            model.navigation.period = .week
            renderWindow(name: "Récap", size: Windows.recapSize,
                         content: model.inject(RecapView(previewHovered: categoryID("IA"))),
                         showsTitle: false, appearance: appearance, to: folder.appendingPathComponent("recap-survol-\(suffix).png"))
            renderWindow(name: "Catégories", size: Windows.categoriesSize,
                         content: model.inject(CategoriesView(initialSelection: categoryID("Design"))),
                         appearance: appearance, to: folder.appendingPathComponent("categories-\(suffix).png"))
        }
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
                                              appearance: NSAppearance.Name, to url: URL) {
        let window = Windows.makeWindow(name: name, size: size, content: content,
                                        showsTitle: showsTitle, autosave: false)
        window.appearance = NSAppearance(named: appearance)
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
