import AppKit
import SwiftUI

/// Période affichée dans la fenêtre de récap. Partagée pour qu'une notification puisse l'ouvrir au bon endroit.
@MainActor
final class RecapNavigation: ObservableObject {
    @Published var period: Period = .week
    @Published var referenceDate = Date()
}

/// Les objets vivants de l'app, créés une fois au lancement.
@MainActor
final class AppModel {
    static let shared = AppModel(db: openDatabase(), live: true)

    let db: Database
    let tracker: Tracker
    let categorizer: Categorizer
    let notifier: RecapNotifier
    let navigation = RecapNavigation()
    let shelf = ShelfController()

    /// `live: false` sert aux captures de l'interface : rien n'est suivi, classé, notifié ni mis à jour.
    init(db: Database, live: Bool) {
        self.db = db
        categorizer = Categorizer(db: db)
        tracker = Tracker(db: db)
        notifier = RecapNotifier(db: db)
        guard live else { return }
        tracker.onAppSeen = { [categorizer] in categorizer.appSeen($0) }
        tracker.start()
        categorizer.classifyPending()
        notifier.start()
        shelf.start()
        Updater.start()
    }

    func inject<V: View>(_ view: V) -> some View {
        view
            .environmentObject(tracker)
            .environmentObject(categorizer)
            .environmentObject(notifier)
            .environmentObject(navigation)
            .environmentObject(shelf)
    }
}

private func openDatabase() -> Database {
    do {
        return try Database()
    } catch {
        fatalError("Impossible d'ouvrir la base : \(error)")
    }
}

/// Fenêtres gérées par AppKit : elles s'ouvrent aussi bien depuis le menu que depuis une notification.
@MainActor
enum Windows {
    private static var recap: NSWindow?
    private static var categories: NSWindow?

    static let recapSize = NSSize(width: 680, height: 820)
    static let categoriesSize = NSSize(width: 700, height: 520)

    static func showRecap(period: Period? = nil, date: Date? = nil) {
        let model = AppModel.shared
        if let period { model.navigation.period = period }
        if let date { model.navigation.referenceDate = date }
        if recap == nil {
            recap = makeWindow(name: "Récap", size: recapSize, content: model.inject(RecapView()), showsTitle: false)
        }
        present(recap!)
    }

    static func showCategories() {
        if categories == nil {
            categories = makeWindow(name: "Catégories", size: categoriesSize,
                                    content: AppModel.shared.inject(CategoriesView()))
        }
        present(categories!)
    }

    /// La vue SwiftUI fournit elle-même la barre d'outils de la fenêtre.
    /// `showsTitle: false` garde le titre pour le menu Fenêtre sans l'afficher dans la barre.
    /// `autosave` mémorise la position de la fenêtre d'une fois sur l'autre.
    static func makeWindow<V: View>(name: String, size: NSSize, content: V,
                                    showsTitle: Bool = true, autosave: Bool = true) -> NSWindow {
        let controller = NSHostingController(rootView: content)
        controller.sceneBridgingOptions = [.toolbars]
        controller.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.toolbarStyle = .unified
        window.title = name
        window.titleVisibility = showsTitle ? .visible : .hidden
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.center()
        if autosave { window.setFrameAutosaveName(name) }
        return window
    }

    private static func present(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
