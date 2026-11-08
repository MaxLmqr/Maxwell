import Foundation

/// Les règles qui découpent l'activité de Max en Sessions, sans rien lire du Mac :
/// le Tracker lui transmet ce qui se passe (app activée, tick avec le temps d'inactivité,
/// veille, réveil, Site lu dans Chrome), toujours avec l'heure de l'évènement.
@MainActor
final class SessionRecorder {
    /// Une App au premier plan, telle que macOS la décrit.
    struct App: Equatable {
        let bundleID: String
        let name: String
    }

    /// La Session en cours. `siteRead` passe à true quand le navigateur a donné son onglet actif.
    struct Current {
        let id: Int64
        let start: Date
        let bundleID: String
        let appName: String
        var site: String?
        var siteRead: Bool
    }

    /// Au-delà de ce délai sans clavier ni souris, Max est en Inactivité.
    static let idleThreshold: TimeInterval = 180

    private let db: Database
    private let ignoredBundleIDs: Set<String>
    /// Appelé à chaque nouvelle Session ouverte sur une App, avec son identifiant.
    var onAppBegan: ((String) -> Void)?

    private(set) var current: Current?
    private(set) var isIdle = false
    private(set) var isSuspended = false
    /// Le nom affiché pour la Session en cours : son Site, sinon son App.
    var currentName: String? { current.map { $0.site ?? $0.appName } }

    init(db: Database, ignoredBundleIDs: Set<String>) {
        self.db = db
        self.ignoredBundleIDs = ignoredBundleIDs
    }

    // MARK: - Évènements

    /// Le premier plan au lancement du suivi.
    func start(with app: App?, at now: Date) {
        begin(app, at: now)
    }

    /// Le tick régulier. `frontmost` n'est lu que si une Session doit s'ouvrir.
    /// Renvoie false pendant une Pause : rien n'a changé.
    @discardableResult
    func tick(idleSeconds: TimeInterval, frontmost: () -> App?, at now: Date) -> Bool {
        guard !isSuspended else { return false }
        if idleSeconds >= Self.idleThreshold {
            if !isIdle {
                // La Session s'arrête au dernier geste, pas au moment où on s'en rend compte.
                close(at: now.addingTimeInterval(-idleSeconds))
                isIdle = true
            }
        } else if isIdle {
            isIdle = false
            begin(frontmost(), at: now)
        } else if let current {
            db.updateEnd(sessionID: current.id, end: now)
        } else {
            begin(frontmost(), at: now)
        }
        return true
    }

    /// Une autre App passe au premier plan. Ignoré pendant une Pause ou une Inactivité.
    @discardableResult
    func activate(_ app: App?, at now: Date) -> Bool {
        guard !isSuspended, !isIdle else { return false }
        close(at: now)
        begin(app, at: now)
        return true
    }

    /// Veille, écran éteint ou verrouillé : la Session en cours se ferme.
    func suspend(at now: Date) {
        guard !isSuspended else { return }
        close(at: now)
        isSuspended = true
    }

    /// Fin de la Pause : une Session s'ouvre sur l'App au premier plan.
    @discardableResult
    func resume(with app: App?, at now: Date) -> Bool {
        guard isSuspended else { return false }
        isSuspended = false
        isIdle = false
        begin(app, at: now)
        return true
    }

    /// Le Site de l'onglet actif, lu pour la Session `sessionID`. Une réponse arrivée après
    /// un changement de Session est ignorée. La première réponse donne son Site à la Session
    /// en cours ; un changement de Site ensuite ouvre une nouvelle Session.
    func siteRead(_ site: String?, sessionID: Int64, at now: Date) {
        guard var current, current.id == sessionID else { return }
        if !current.siteRead {
            db.updateSite(sessionID: current.id, site: site)
            current.site = site
            current.siteRead = true
            self.current = current
        } else if site != current.site {
            close(at: now)
            open(bundleID: current.bundleID, appName: current.appName, site: site, siteRead: true, at: now)
        }
    }

    /// L'app se ferme : la Session en cours aussi.
    func close(at date: Date) {
        guard let current else { return }
        db.updateEnd(sessionID: current.id, end: max(date, current.start))
        self.current = nil
    }

    // MARK: - Sessions

    private func begin(_ app: App?, at date: Date) {
        guard let app, !ignoredBundleIDs.contains(app.bundleID) else {
            current = nil
            return
        }
        open(bundleID: app.bundleID, appName: app.name, site: nil, siteRead: false, at: date)
        onAppBegan?(app.bundleID)
    }

    private func open(bundleID: String, appName: String, site: String?, siteRead: Bool, at date: Date) {
        let id = db.insertSession(bundleID: bundleID, appName: appName, site: site, start: date, end: date)
        current = Current(id: id, start: date, bundleID: bundleID, appName: appName, site: site, siteRead: siteRead)
    }
}
