import AppKit
import CoreGraphics

/// Suit l'app au premier plan et enregistre une session à chaque changement.
/// Dans Chrome, une session démarre aussi quand le site de l'onglet actif change.
/// Le suivi s'interrompt en cas d'inactivité, de veille ou d'écran verrouillé.
@MainActor
final class Tracker: ObservableObject {
    @Published private(set) var currentAppName: String?
    @Published private(set) var isIdle = false
    @Published private(set) var isSuspended = false
    /// Change à chaque tick : les vues l'observent pour se rafraîchir.
    @Published private(set) var lastUpdate = Date()

    let db: Database
    /// Appelé quand une app passe au premier plan, avec son identifiant.
    var onAppSeen: ((String) -> Void)?

    /// Au-delà de ce délai sans clavier/souris, on considère que tu n'es plus là.
    private let idleThreshold: TimeInterval = 180
    private let tickInterval: TimeInterval = 5
    /// Rythme de lecture de l'onglet actif, pendant que Chrome est devant.
    private let siteInterval: TimeInterval = 2
    private let ignoredBundleIDs: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.ScreenSaver.Engine",
        Bundle.main.bundleIdentifier ?? "",
    ]

    /// La session en cours. `siteRead` passe à true quand Chrome a donné l'onglet actif.
    private struct Current {
        let id: Int64
        let start: Date
        let bundleID: String
        let appName: String
        var site: String?
        var siteRead: Bool
    }

    private var current: Current?
    private let chromeTab = ChromeTab()
    private var readingSite = false
    private var timers: [Timer] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(db: Database) {
        self.db = db
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.switchTo(app)
        }
        for name in [NSWorkspace.willSleepNotification,
                     NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observe(workspace, name) { [weak self] _ in self?.suspend() }
        }
        for name in [NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(workspace, name) { [weak self] _ in self?.resume() }
        }

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { [weak self] _ in self?.suspend() }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { [weak self] _ in self?.resume() }

        observe(NotificationCenter.default, NSApplication.willTerminateNotification) { [weak self] _ in
            self?.closeCurrent(at: Date())
        }

        timers = [
            Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            },
            Timer.scheduledTimer(withTimeInterval: siteInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.readSite() }
            },
        ]
        begin(NSWorkspace.shared.frontmostApplication, at: Date())
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handler: @escaping @MainActor (Notification) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { note in
            MainActor.assumeIsolated { handler(note) }
        }
        observers.append((center, token))
    }

    // MARK: - Machine à états

    private func tick() {
        guard !isSuspended else { return }
        let now = Date()
        let idleSeconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState, eventType: CGEventType(rawValue: ~0)!)

        if idleSeconds >= idleThreshold {
            if !isIdle {
                // On arrête la session au dernier geste, pas au moment où on s'en rend compte.
                closeCurrent(at: now.addingTimeInterval(-idleSeconds))
                isIdle = true
            }
        } else if isIdle {
            isIdle = false
            begin(NSWorkspace.shared.frontmostApplication, at: now)
        } else if let current {
            db.updateEnd(sessionID: current.id, end: now)
        } else {
            begin(NSWorkspace.shared.frontmostApplication, at: now)
        }
        lastUpdate = now
    }

    private func switchTo(_ app: NSRunningApplication?) {
        guard !isSuspended, !isIdle else { return }
        let now = Date()
        closeCurrent(at: now)
        begin(app, at: now)
        lastUpdate = now
    }

    private func suspend() {
        guard !isSuspended else { return }
        closeCurrent(at: Date())
        isSuspended = true
    }

    private func resume() {
        guard isSuspended else { return }
        isSuspended = false
        isIdle = false
        begin(NSWorkspace.shared.frontmostApplication, at: Date())
        lastUpdate = Date()
    }

    private func begin(_ app: NSRunningApplication?, at date: Date) {
        guard let app, let bundleID = app.bundleIdentifier, !ignoredBundleIDs.contains(bundleID) else {
            current = nil
            currentAppName = nil
            return
        }
        start(bundleID: bundleID, appName: app.localizedName ?? bundleID, site: nil, siteRead: false, at: date)
        onAppSeen?(bundleID)
        readSite()
    }

    private func start(bundleID: String, appName: String, site: String?, siteRead: Bool, at date: Date) {
        let id = db.insertSession(bundleID: bundleID, appName: appName, site: site, start: date, end: date)
        current = Current(id: id, start: date, bundleID: bundleID, appName: appName, site: site, siteRead: siteRead)
        currentAppName = site ?? appName
    }

    // MARK: - Site de l'onglet actif

    /// Demande à Chrome son onglet actif, s'il est devant. La réponse arrive un peu plus tard :
    /// elle est ignorée si la session a changé entre-temps.
    private func readSite() {
        guard let current, current.bundleID == ChromeTab.bundleID, !readingSite else { return }
        readingSite = true
        Task {
            let reading = await chromeTab.activeSite()
            readingSite = false
            if case .site(let site) = reading { siteRead(site, sessionID: current.id) }
        }
    }

    private func siteRead(_ site: String?, sessionID: Int64) {
        guard var current, current.id == sessionID else { return }
        if !current.siteRead {
            // Première réponse depuis l'arrivée dans Chrome : la session en cours prend ce site.
            db.updateSite(sessionID: current.id, site: site)
            current.site = site
            current.siteRead = true
            self.current = current
            currentAppName = site ?? current.appName
        } else if site != current.site {
            let now = Date()
            closeCurrent(at: now)
            start(bundleID: current.bundleID, appName: current.appName, site: site, siteRead: true, at: now)
        }
    }

    private func closeCurrent(at date: Date) {
        guard let current else { return }
        db.updateEnd(sessionID: current.id, end: max(date, current.start))
        self.current = nil
        currentAppName = nil
    }
}

extension Tracker {
    /// Pour les captures de l'interface : affiche une app en cours sans suivre le Mac.
    func simulateCurrentApp(_ name: String) {
        currentAppName = name
    }
}
