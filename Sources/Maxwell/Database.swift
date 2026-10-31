import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Identifiant de catégorie. 0 désigne les apps et les sites « À classer ».
typealias CategoryID = Int64
let uncategorizedID: CategoryID = 0

/// Ce qui porte une Catégorie : une App, ou un Site visité dans Chrome.
enum Subject: Hashable {
    case app(String)
    case site(String)
}

/// Temps passé dans une App, ou sur un Site, pendant une période.
struct AppUsage: Identifiable {
    /// L'App ; pour un Site, le navigateur où il a été visité.
    let bundleID: String
    let site: String?
    let name: String
    let categoryID: CategoryID
    let duration: TimeInterval
    var subject: Subject { site.map(Subject.site) ?? .app(bundleID) }
    var id: Subject { subject }
}

struct Category: Identifiable, Hashable {
    let id: CategoryID
    var name: String
    /// Nom d'un pictogramme SF Symbols.
    var symbol: String
    var hidden: Bool
    /// La catégorie Système ne peut pas être supprimée : le classement automatique en dépend.
    var isSystem: Bool

    static let defaultSymbol = "tag"
    static let uncategorizedSymbol = "questionmark.circle"
    /// Pictogrammes proposés pour une catégorie.
    static let symbolChoices = [
        "chevron.left.forwardslash.chevron.right", "sparkles", "bubble.left.and.bubble.right", "video",
        "paintpalette", "doc.text", "globe", "play.circle", "wrench.and.screwdriver", "gearshape",
        "book", "music.note", "gamecontroller", "cart", "chart.line.uptrend.xyaxis", "camera",
        "graduationcap", "briefcase", "heart", "tag",
    ]
}

/// Une app ou un site déjà vu, avec sa catégorie actuelle.
struct KnownApp: Identifiable {
    /// L'App ; pour un Site, le navigateur où il a été visité.
    let bundleID: String
    let site: String?
    let name: String
    let categoryID: CategoryID
    /// true si Max a choisi la catégorie lui-même ; le classement automatique n'y touche plus.
    let manual: Bool
    let totalDuration: TimeInterval
    var subject: Subject { site.map(Subject.site) ?? .app(bundleID) }
    var id: Subject { subject }
}

enum DatabaseError: Error {
    case sqlite(String)
}

/// Stockage local : les sessions d'activité, les catégories et la catégorie de chaque app et de chaque site.
final class Database {
    private var db: OpaquePointer?

    static let defaultCategories = [
        "Développement", "IA", "Communication", "Réunions", "Design",
        "Écriture et documents", "Navigation", "Divertissement", "Outils",
    ]

    private static let defaultSymbols = [
        "Développement": "chevron.left.forwardslash.chevron.right",
        "IA": "sparkles",
        "Communication": "bubble.left.and.bubble.right",
        "Réunions": "video",
        "Design": "paintpalette",
        "Écriture et documents": "doc.text",
        "Navigation": "globe",
        "Divertissement": "play.circle",
        "Outils": "wrench.and.screwdriver",
        "Système": "gearshape",
    ]

    static var defaultURL: URL {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = support.appendingPathComponent("Maxwell", isDirectory: true)
        // Reprend les données enregistrées sous les anciens noms de l'app.
        let legacy = ["MaxActivity", "ActivityTracker"]
            .map { support.appendingPathComponent($0, isDirectory: true) }
            .first { fm.fileExists(atPath: $0.path) }
        if !fm.fileExists(atPath: folder.path), let legacy {
            try? fm.moveItem(at: legacy, to: folder)
        }
        return folder.appendingPathComponent("activity.sqlite")
    }

    init(url: URL = Database.defaultURL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &db) == SQLITE_OK else { throw DatabaseError.sqlite(errorMessage) }
        try exec("PRAGMA journal_mode=WAL")
        try exec("PRAGMA foreign_keys=ON")
        try exec("""
            CREATE TABLE IF NOT EXISTS sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                bundle_id TEXT NOT NULL,
                app_name TEXT NOT NULL,
                site TEXT,
                started_at REAL NOT NULL,
                ended_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_sessions_started_at ON sessions(started_at);
            CREATE INDEX IF NOT EXISTS idx_sessions_ended_at ON sessions(ended_at);

            CREATE TABLE IF NOT EXISTS categories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                symbol TEXT,
                position INTEGER NOT NULL,
                hidden INTEGER NOT NULL DEFAULT 0,
                is_system INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS app_categories (
                bundle_id TEXT PRIMARY KEY,
                category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
                manual INTEGER NOT NULL DEFAULT 0
            );
            CREATE TABLE IF NOT EXISTS site_categories (
                site TEXT PRIMARY KEY,
                category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
                manual INTEGER NOT NULL DEFAULT 0
            );
            """)
        seedCategoriesIfNeeded()
        addSymbols()
        addSites()
    }

    private func columns(of table: String) -> Set<String> {
        var columns: Set<String> = []
        run("PRAGMA table_info(\(table))", []) { columns.insert(String(cString: sqlite3_column_text($0, 1))) }
        return columns
    }

    /// Ajoute le pictogramme des catégories aux bases créées avant qu'il existe.
    private func addSymbols() {
        if !columns(of: "categories").contains("symbol") {
            run("ALTER TABLE categories ADD COLUMN symbol TEXT", [])
        }
        for (name, symbol) in Self.defaultSymbols {
            run("UPDATE categories SET symbol = ? WHERE name = ? AND symbol IS NULL", [symbol, name])
        }
    }

    /// Ajoute le Site des sessions aux bases créées avant qu'il existe.
    private func addSites() {
        if !columns(of: "sessions").contains("site") {
            run("ALTER TABLE sessions ADD COLUMN site TEXT", [])
        }
    }

    deinit { sqlite3_close(db) }

    private func seedCategoriesIfNeeded() {
        var count: Int64 = 0
        run("SELECT COUNT(*) FROM categories", []) { count = sqlite3_column_int64($0, 0) }
        guard count == 0 else { return }
        for name in Self.defaultCategories { addCategory(name: name) }
        run("INSERT INTO categories (name, position, hidden, is_system) VALUES ('Système', 1000, 1, 1)", [])
    }

    // MARK: - Sessions

    @discardableResult
    func insertSession(bundleID: String, appName: String, site: String? = nil, start: Date, end: Date) -> Int64 {
        run("INSERT INTO sessions (bundle_id, app_name, site, started_at, ended_at) VALUES (?, ?, ?, ?, ?)",
            [bundleID, appName, site as Any, start.timeIntervalSince1970, end.timeIntervalSince1970])
        return sqlite3_last_insert_rowid(db)
    }

    func updateEnd(sessionID: Int64, end: Date) {
        run("UPDATE sessions SET ended_at = ? WHERE id = ?", [end.timeIntervalSince1970, sessionID])
    }

    func updateSite(sessionID: Int64, site: String?) {
        run("UPDATE sessions SET site = ? WHERE id = ?", [site as Any, sessionID])
    }

    // MARK: - Agrégats (hors catégories masquées)

    /// La catégorie d'une session est celle de son Site s'il y en a un, sinon celle de son App.
    private static let sessionCategory = """
        LEFT JOIN app_categories ac ON s.site IS NULL AND ac.bundle_id = s.bundle_id
        LEFT JOIN site_categories sc ON sc.site = s.site
        """
    /// Une ligne par Site, et une par App pour le temps passé hors des sites.
    private static let bySubject = "GROUP BY s.site, CASE WHEN s.site IS NULL THEN s.bundle_id END"

    /// Sessions de l'intervalle, tronquées aux bornes, sans les catégories masquées.
    private static let visibleSessions = """
        FROM sessions s
        \(sessionCategory)
        LEFT JOIN categories c ON c.id = COALESCE(sc.category_id, ac.category_id)
        WHERE s.ended_at > ?1 AND s.started_at < ?2 AND COALESCE(c.hidden, 0) = 0
        """
    private static let clippedDuration = "SUM(MIN(s.ended_at, ?2) - MAX(s.started_at, ?1))"

    func usageByApp(in interval: DateInterval) -> [AppUsage] {
        var result: [AppUsage] = []
        run("""
            SELECT MAX(s.bundle_id), s.site, COALESCE(s.site, MAX(s.app_name)), COALESCE(c.id, 0),
                   \(Self.clippedDuration) AS secs
            \(Self.visibleSessions)
            \(Self.bySubject)
            ORDER BY secs DESC
            """, bounds(interval)
        ) { stmt in
            result.append(AppUsage(
                bundleID: String(cString: sqlite3_column_text(stmt, 0)),
                site: Self.optionalText(stmt, 1),
                name: String(cString: sqlite3_column_text(stmt, 2)),
                categoryID: sqlite3_column_int64(stmt, 3),
                duration: sqlite3_column_double(stmt, 4)))
        }
        return result.filter { $0.duration >= 1 }
    }

    func durationByCategory(in interval: DateInterval) -> [CategoryID: TimeInterval] {
        var result: [CategoryID: TimeInterval] = [:]
        run("""
            SELECT COALESCE(c.id, 0), \(Self.clippedDuration)
            \(Self.visibleSessions)
            GROUP BY COALESCE(c.id, 0)
            """, bounds(interval)
        ) { stmt in
            result[sqlite3_column_int64(stmt, 0)] = sqlite3_column_double(stmt, 1)
        }
        return result
    }

    func totalDuration(in interval: DateInterval) -> TimeInterval {
        durationByCategory(in: interval).values.reduce(0, +)
    }

    private func bounds(_ interval: DateInterval) -> [Any] {
        [interval.start.timeIntervalSince1970, interval.end.timeIntervalSince1970]
    }

    // MARK: - Catégories

    func categories() -> [Category] {
        var result: [Category] = []
        run("SELECT id, name, COALESCE(symbol, ?), hidden, is_system FROM categories ORDER BY position, id",
            [Category.defaultSymbol]
        ) { stmt in
            result.append(Category(
                id: sqlite3_column_int64(stmt, 0),
                name: String(cString: sqlite3_column_text(stmt, 1)),
                symbol: String(cString: sqlite3_column_text(stmt, 2)),
                hidden: sqlite3_column_int64(stmt, 3) != 0,
                isSystem: sqlite3_column_int64(stmt, 4) != 0))
        }
        return result
    }

    func setSymbol(_ id: CategoryID, _ symbol: String) {
        run("UPDATE categories SET symbol = ? WHERE id = ?", [symbol, id])
    }

    /// Renvoie l'identifiant de la nouvelle catégorie, ou nil si le nom existe déjà.
    @discardableResult
    func addCategory(name: String) -> CategoryID? {
        let before = sqlite3_total_changes(db)
        run("""
            INSERT OR IGNORE INTO categories (name, position)
            SELECT ?, COALESCE(MAX(position), 0) + 1 FROM categories WHERE is_system = 0
            """, [name])
        return sqlite3_total_changes(db) > before ? sqlite3_last_insert_rowid(db) : nil
    }

    func renameCategory(_ id: CategoryID, to name: String) {
        run("UPDATE OR IGNORE categories SET name = ? WHERE id = ?", [name, id])
    }

    /// Les apps et les sites de la catégorie supprimée redeviennent « À classer ».
    func deleteCategory(_ id: CategoryID) {
        run("DELETE FROM categories WHERE id = ? AND is_system = 0", [id])
    }

    func setHidden(_ id: CategoryID, _ hidden: Bool) {
        run("UPDATE categories SET hidden = ? WHERE id = ?", [Int64(hidden ? 1 : 0), id])
    }

    // MARK: - Catégorie des apps et des sites

    func knownApps() -> [KnownApp] {
        var result: [KnownApp] = []
        run("""
            SELECT MAX(s.bundle_id), s.site, COALESCE(s.site, MAX(s.app_name)),
                   COALESCE(sc.category_id, ac.category_id, 0), COALESCE(sc.manual, ac.manual, 0),
                   SUM(s.ended_at - s.started_at) AS secs
            FROM sessions s
            \(Self.sessionCategory)
            \(Self.bySubject)
            ORDER BY secs DESC
            """, []
        ) { stmt in
            result.append(KnownApp(
                bundleID: String(cString: sqlite3_column_text(stmt, 0)),
                site: Self.optionalText(stmt, 1),
                name: String(cString: sqlite3_column_text(stmt, 2)),
                categoryID: sqlite3_column_int64(stmt, 3),
                manual: sqlite3_column_int64(stmt, 4) != 0,
                totalDuration: sqlite3_column_double(stmt, 5)))
        }
        return result
    }

    /// La table où est rangée la catégorie d'une App ou d'un Site, et sa clé.
    private func categoryTable(_ subject: Subject) -> (table: String, column: String, key: String) {
        switch subject {
        case .app(let bundleID): ("app_categories", "bundle_id", bundleID)
        case .site(let site): ("site_categories", "site", site)
        }
    }

    func categoryID(for subject: Subject) -> CategoryID {
        let (table, column, key) = categoryTable(subject)
        var id = uncategorizedID
        run("SELECT category_id FROM \(table) WHERE \(column) = ?", [key]) {
            id = sqlite3_column_int64($0, 0)
        }
        return id
    }

    func setCategory(_ categoryID: CategoryID, for subject: Subject, manual: Bool) {
        let (table, column, key) = categoryTable(subject)
        if categoryID == uncategorizedID {
            run("DELETE FROM \(table) WHERE \(column) = ?", [key])
        } else {
            run("INSERT OR REPLACE INTO \(table) (\(column), category_id, manual) VALUES (?, ?, ?)",
                [key, categoryID, Int64(manual ? 1 : 0)])
        }
    }

    /// Oublie les catégories choisies automatiquement, pour les faire recalculer.
    func clearAutomaticCategories() {
        run("DELETE FROM app_categories WHERE manual = 0", [])
        run("DELETE FROM site_categories WHERE manual = 0", [])
    }

    // MARK: - SQLite

    private var errorMessage: String { String(cString: sqlite3_errmsg(db)) }

    private static func optionalText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        sqlite3_column_type(stmt, index) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(stmt, index))
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw DatabaseError.sqlite(errorMessage) }
    }

    private func run(_ sql: String, _ params: [Any], row: ((OpaquePointer) -> Void)? = nil) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            NSLog("Maxwell SQL error: \(errorMessage)")
            return
        }
        defer { sqlite3_finalize(stmt) }
        for (index, param) in params.enumerated() {
            let i = Int32(index + 1)
            switch param {
            case let v as String: sqlite3_bind_text(stmt, i, v, -1, SQLITE_TRANSIENT)
            case let v as Double: sqlite3_bind_double(stmt, i, v)
            case let v as Int64: sqlite3_bind_int64(stmt, i, v)
            default: sqlite3_bind_null(stmt, i)
            }
        }
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW { row?(stmt); continue }
            if rc != SQLITE_DONE { NSLog("Maxwell SQL error: \(errorMessage)") }
            break
        }
    }
}
