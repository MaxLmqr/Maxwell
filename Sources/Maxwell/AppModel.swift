import AppKit
import SwiftUI

/// Période affichée dans la fenêtre de récap. Partagée pour qu'une notification puisse l'ouvrir au bon endroit.
@MainActor
final class RecapNavigation: ObservableObject {
    @Published var period: Period = .week
    @Published var referenceDate = Date()

    /// Les touches du Récap : j s m pour la période, ← → pour remonter le temps, t pour revenir à aujourd'hui.
    /// Renvoie false pour une touche qui ne veut rien dire ici.
    func handle(_ event: NSEvent, now: Date = Date()) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.intersection([.command, .control, .option]).isEmpty else { return false }
        switch Int(event.keyCode) {
        case 123:
            referenceDate = period.shift(referenceDate, by: -1)
            return true
        case 124:
            guard !period.interval(containing: referenceDate).contains(now) else { return true }
            referenceDate = period.shift(referenceDate, by: 1)
            return true
        default: break
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "t": referenceDate = now
        case let key?:
            guard let chosen = Period.allCases.first(where: { $0.key == key }) else { return false }
            period = chosen
        default: return false
        }
        return true
    }
}

/// Les objets vivants de l'app, créés une fois au lancement.
@MainActor
final class AppModel {
    static let shared = AppModel(db: openDatabase(), live: true)

    let db: Database
    let tracker: Tracker
    let categorizer: Categorizer
    let notifier: RecapNotifier
    let recaps: RecapSource
    let navigation = RecapNavigation()
    let taskNavigation = TaskNavigation()
    let mainNavigation = MainNavigation()
    let shelf = ShelfController()
    let tasks: TaskStore
    let claude: ClaudeRunner
    let quickEntry: QuickEntryController
    private var outsideChanges: Timer?

    /// `live: false` sert aux captures de l'interface : rien n'est suivi, classé, notifié ni mis à jour.
    init(db: Database, live: Bool) {
        self.db = db
        categorizer = Categorizer(db: db)
        tracker = Tracker(db: db)
        notifier = RecapNotifier(db: db)
        recaps = RecapSource(db: db, tracker: tracker, categorizer: categorizer)
        tasks = TaskStore(db: db)
        claude = ClaudeRunner(store: tasks)
        quickEntry = QuickEntryController(store: tasks)
        guard live else { return }
        quickEntry.start()
        claude.follow()
        // Claude peut changer les Tâches par le serveur MCP : la fenêtre suit, à deux secondes près.
        outsideChanges = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [tasks] _ in
            MainActor.assumeIsolated { _ = tasks.reloadIfChangedElsewhere() }
        }
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
            .environmentObject(recaps)
            .environmentObject(notifier)
            .environmentObject(navigation)
            .environmentObject(shelf)
            .environmentObject(tasks)
            .environmentObject(claude)
            .environmentObject(taskNavigation)
            .environmentObject(mainNavigation)
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
    /// La fenêtre Maxwell, qui réunit le Temps (le Récap) et les Tâches.
    private static var main: NSWindow?
    private static var categories: NSWindow?

    static let mainSize = NSSize(width: 860, height: 640)
    static let categoriesSize = NSSize(width: 700, height: 520)

    /// Le Récap, dans la fenêtre Maxwell.
    /// Sans date, il s'ouvre sur aujourd'hui, même s'il montrait une autre période avant d'être fermé.
    static func showRecap(period: Period? = nil, date: Date? = nil) {
        let model = AppModel.shared
        if let period { model.navigation.period = period }
        model.navigation.referenceDate = date ?? Date()
        show(.time)
    }

    static func showCategories() {
        if categories == nil {
            categories = makeWindow(name: "Catégories", size: categoriesSize,
                                    content: AppModel.shared.inject(CategoriesView()))
        }
        present(categories!)
    }

    /// ⌃⌥T : ouvre les Tâches au premier plan, ou referme la fenêtre si Max y est déjà.
    static func toggleTasks() {
        if let main, main.isKeyWindow, NSApp.isActive, AppModel.shared.mainNavigation.module == .tasks {
            main.orderOut(nil)
            updateDockPresence()
            // Rend la main à l'app d'avant s'il ne reste aucune fenêtre de Maxwell.
            if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { NSApp.hide(nil) }
        } else {
            showTasks()
        }
    }

    /// Sans liste précise, les Tâches s'ouvrent sur Aujourd'hui, le curseur dans « Nouvelle tâche » :
    /// ouvrir la fenêtre et taper suffit à noter une Tâche. Échap rend ensuite le clavier à la liste.
    static func showTasks(_ list: TaskList? = nil) {
        let navigation = AppModel.shared.taskNavigation
        navigation.selection = list ?? .today
        // Rouvrir la fenêtre, c'est repartir d'une liste propre : les Tâches cochées avant n'y restent pas.
        navigation.justClosed = []
        let firstOpening = main == nil
        show(.tasks)
        if list == nil {
            // Après l'affichage. À la toute première ouverture, le champ vient d'être créé
            // et n'accepte le curseur qu'un instant plus tard.
            DispatchQueue.main.asyncAfter(deadline: .now() + (firstOpening ? 0.3 : 0)) {
                navigation.focusNewTask = true
            }
        }
    }

    private static func show(_ module: Module) {
        AppModel.shared.mainNavigation.module = module
        if module == .tasks { AppModel.shared.taskNavigation.selectFirstIfNeeded(in: AppModel.shared.tasks) }
        if main == nil {
            main = makeMainWindow(content: AppModel.shared.inject(MaxwellView()))
            installShortcuts()
        }
        present(main!)
        // Par défaut le clavier va au module, pas à un champ : ses touches d'une lettre marchent d'emblée.
        main?.makeFirstResponder(nil)
    }

    private static var shortcutMonitor: Any?

    /// ⌘1, ⌘2 et ⌘W dans la fenêtre Maxwell. Maxwell n'a pas de barre de menus pour les porter,
    /// et ⌘1 se lit sur la touche physique pour marcher aussi en AZERTY.
    private static func installShortcuts() {
        guard shortcutMonitor == nil else { return }
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let main, event.window === main else { return event }
            let model = AppModel.shared
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
                if let module = Module.allCases.first(where: { $0.keyCode == event.keyCode }) {
                    model.mainNavigation.module = module
                    return nil
                }
                if event.charactersIgnoringModifiers == "w" {
                    main.orderOut(nil)
                    updateDockPresence()
                    return nil
                }
                return event
            }
            // Pendant que Max écrit dans un champ, les touches lui reviennent ;
            // Échap dans le champ de création rend la main à la liste.
            // Avant de confier une Tâche à Claude : ↩ lance, Échap renonce, le reste s'écrit dans la précision.
            if model.mainNavigation.module == .tasks, let launcher = model.taskNavigation.launcher {
                switch Int(event.keyCode) {
                case 36, 76:
                    ClaudeModel.current = launcher.model
                    model.claude.start(launcher.taskID, extra: launcher.extra, model: launcher.model)
                    model.taskNavigation.launcher = nil
                    main.makeFirstResponder(nil)
                case 48:
                    // Tab : le modèle suivant.
                    model.taskNavigation.launcher?.model = launcher.model.next
                case 53:
                    model.taskNavigation.launcher = nil
                    main.makeFirstResponder(nil)
                default: return event
                }
                return nil
            }
            // Le sélecteur de Projet garde le clavier : ↑↓ choisissent, ↩ range, Échap ferme, le reste s'écrit.
            if model.mainNavigation.module == .tasks, model.taskNavigation.picker != nil {
                switch Int(event.keyCode) {
                case 126: model.taskNavigation.movePicker(by: -1, store: model.tasks)
                case 125: model.taskNavigation.movePicker(by: 1, store: model.tasks)
                case 36, 76:
                    model.taskNavigation.applyPicker(store: model.tasks)
                    main.makeFirstResponder(nil)
                case 53:
                    model.taskNavigation.picker = nil
                    main.makeFirstResponder(nil)
                default: return event
                }
                return nil
            }
            if main.firstResponder is NSTextView {
                let tasks = model.taskNavigation
                if event.keyCode == 53, model.mainNavigation.module == .tasks, tasks.expanded == nil {
                    main.makeFirstResponder(nil)
                    return nil
                }
                // ↓ dans le champ de création descend sur la première Tâche.
                if event.keyCode == 125, model.mainNavigation.module == .tasks, tasks.newTaskFocused,
                   tasks.leaveNewTaskField(store: model.tasks) {
                    main.makeFirstResponder(nil)
                    return nil
                }
                return event
            }
            switch model.mainNavigation.module {
            case .tasks:
                if let key = TaskKey(event: event), model.taskNavigation.handle(key, store: model.tasks) { return nil }
            case .time:
                if model.navigation.handle(event) { return nil }
            }
            // Une touche sans effet ici continue son chemin : macOS la signale par son bip habituel.
            return event
        }
    }

    /// La fenêtre Maxwell : sombre, sans barre de titre visible, ses boutons posés sur la barre des modules.
    static func makeMainWindow<V: View>(content: V, autosave: Bool = true) -> NSWindow {
        let window = makeWindow(name: "Maxwell", size: mainSize, content: content, showsTitle: false,
                                autosave: autosave, fullSizeContent: true)
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(red: 0x17 / 255, green: 0x19 / 255, blue: 0x1B / 255, alpha: 1)
        window.isMovableByWindowBackground = true
        return window
    }

    /// La vue SwiftUI fournit elle-même la barre d'outils de la fenêtre.
    /// `showsTitle: false` garde le titre pour le menu Fenêtre sans l'afficher dans la barre.
    /// `autosave` mémorise la position de la fenêtre d'une fois sur l'autre.
    static func makeWindow<V: View>(name: String, size: NSSize, content: V,
                                    showsTitle: Bool = true, autosave: Bool = true,
                                    fullSizeContent: Bool = false) -> NSWindow {
        let controller = NSHostingController(rootView: content)
        controller.sceneBridgingOptions = [.toolbars]
        controller.sizingOptions = [.minSize]
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // La barre latérale monte jusque sous les boutons de la fenêtre, comme dans Finder ou Mail.
        if fullSizeContent { window.styleMask.insert(.fullSizeContentView) }
        // La fenêtre vient sur le bureau où l'on est, au lieu de faire basculer le Mac vers celui où elle a été
        // ouverte la première fois. Pas devant une app en plein écran : c'est une fenêtre de travail, qui
        // resterait posée dessus ; macOS bascule alors vers un bureau normal pour l'afficher.
        window.collectionBehavior = [.moveToActiveSpace]
        window.toolbarStyle = .unified
        window.title = name
        window.titleVisibility = showsTitle ? .visible : .hidden
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.center()
        if autosave { window.setFrameAutosaveName(name) }
        // Au bouton rouge : une fois la fenêtre fermée, Maxwell quitte le Dock si c'était la dernière.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { updateDockPresence() } }
        }
        return window
    }

    /// Maxwell est dans le Dock et dans ⌘Tab tant qu'une de ses fenêtres est ouverte (même réduite),
    /// et redevient une simple icône de barre de menus quand elles sont toutes fermées.
    static func updateDockPresence() {
        let open = [main, categories].compactMap { $0 }.contains { $0.isVisible || $0.isMiniaturized }
        let policy: NSApplication.ActivationPolicy = open ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }

    private static func present(_ window: NSWindow) {
        // Depuis un raccourci global, la simple demande `NSApp.activate()` est refusée par macOS :
        // la fenêtre s'affichait derrière l'app en cours, qui gardait le clavier.
        // Dans le Dock d'abord : une app de barre de menus seule n'y figure pas, ni dans ⌘Tab.
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
