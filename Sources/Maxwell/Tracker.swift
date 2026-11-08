import AppKit
import CoreGraphics

/// Branche le suivi sur le Mac : l'app au premier plan, l'inactivité, la veille, l'écran verrouillé
/// et l'onglet actif de Chrome. Les règles qui en font des Sessions sont dans `SessionRecorder`.
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

    private let tickInterval: TimeInterval = 5
    /// Rythme de lecture de l'onglet actif, pendant que Chrome est devant.
    private let siteInterval: TimeInterval = 2

    private let recorder: SessionRecorder
    private let chromeTab = ChromeTab()
    private var readingSite = false
    private var timers: [Timer] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(db: Database) {
        self.db = db
        recorder = SessionRecorder(db: db, ignoredBundleIDs: [
            "com.apple.loginwindow",
            "com.apple.ScreenSaver.Engine",
            Bundle.main.bundleIdentifier ?? "",
        ])
        recorder.onAppBegan = { [weak self] bundleID in
            self?.onAppSeen?(bundleID)
            self?.readSite()
        }
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
            self?.recorder.close(at: Date())
            self?.publish()
        }

        timers = [
            Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            },
            Timer.scheduledTimer(withTimeInterval: siteInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.readSite() }
            },
        ]
        recorder.start(with: Self.frontmost(), at: Date())
        publish()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         _ handler: @escaping @MainActor (Notification) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { note in
            MainActor.assumeIsolated { handler(note) }
        }
        observers.append((center, token))
    }

    // MARK: - Évènements du Mac

    private static func app(_ running: NSRunningApplication?) -> SessionRecorder.App? {
        guard let running, let bundleID = running.bundleIdentifier else { return nil }
        return SessionRecorder.App(bundleID: bundleID, name: running.localizedName ?? bundleID)
    }

    private static func frontmost() -> SessionRecorder.App? {
        app(NSWorkspace.shared.frontmostApplication)
    }

    private func tick() {
        let now = Date()
        let idleSeconds = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if recorder.tick(idleSeconds: idleSeconds, frontmost: Self.frontmost, at: now) {
            lastUpdate = now
        }
        publish()
    }

    private func switchTo(_ app: NSRunningApplication?) {
        let now = Date()
        if recorder.activate(Self.app(app), at: now) {
            lastUpdate = now
        }
        publish()
    }

    private func suspend() {
        recorder.suspend(at: Date())
        publish()
    }

    private func resume() {
        if recorder.resume(with: Self.frontmost(), at: Date()) {
            lastUpdate = Date()
        }
        publish()
    }

    /// Recopie l'état du suivi pour les vues.
    private func publish() {
        if currentAppName != recorder.currentName { currentAppName = recorder.currentName }
        if isIdle != recorder.isIdle { isIdle = recorder.isIdle }
        if isSuspended != recorder.isSuspended { isSuspended = recorder.isSuspended }
    }

    // MARK: - Site de l'onglet actif

    /// Demande à Chrome son onglet actif, s'il est devant. La réponse arrive un peu plus tard :
    /// le recorder l'ignore si la Session a changé entre-temps.
    private func readSite() {
        guard let current = recorder.current, current.bundleID == ChromeTab.bundleID, !readingSite else { return }
        readingSite = true
        Task {
            let reading = await chromeTab.activeSite()
            readingSite = false
            if case .site(let site) = reading {
                recorder.siteRead(site, sessionID: current.id, at: Date())
                publish()
            }
        }
    }
}

extension Tracker {
    /// Pour les captures de l'interface : affiche une app en cours sans suivre le Mac.
    func simulateCurrentApp(_ name: String) {
        currentAppName = name
    }

    /// Pour les captures de l'interface : fige l'heure que voient les vues.
    func simulateNow(_ date: Date) {
        lastUpdate = date
    }
}
