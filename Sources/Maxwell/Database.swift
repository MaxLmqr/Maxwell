import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Identifiant de catégorie. 0 désigne les apps « À classer ».
typealias CategoryID = Int64
let uncategorizedID: CategoryID = 0

struct AppUsage: Identifiable {
    let bundleID: String
    let name: String
    let categoryID: CategoryID
    let duration: TimeInterval
    var id: String { bundleID }
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

/// Une app déjà vue, avec sa catégorie actuelle.
struct KnownApp: Identifiable {
    let bundleID: String
    let name: String
    let categoryID: CategoryID
    /// true si Max a choisi la catégorie lui-même ; le classement automatique n'y touche plus.
    let manual: Bool
    let totalDuration: TimeInterval
    var id: String { bundleID }
}

enum DatabaseError: Error {
    case sqlite(String)
}

/// Stockage local : les sessions d'activité, les catégories et la catégorie de chaque app.
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
            """)
        seedCategoriesIfNeeded()
        addSymbols()
    }

    /// Ajoute le pictogramme des catégories aux bases créées avant qu'il existe.
    private func addSymbols() {
        var columns: Set<String> = []
        run("PRAGMA table_info(categories)", []) { columns.insert(String(cString: sqlite3_column_text($0, 1))) }
        if !columns.contains("symbol") {
            run("ALTER TABLE categories ADD COLUMN symbol TEXT", [])
        }
        for (name, symbol) in Self.defaultSymbols {
            run("UPDATE categories SET symbol = ? WHERE name = ? AND symbol IS NULL", [symbol, name])
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
    func insertSession(bundleID: String, appName: String, start: Date, end: Date) -> Int64 {
        run("INSERT INTO sessions (bundle_id, app_name, started_at, ended_at) VALUES (?, ?, ?, ?)",
            [bundleID, appName, start.timeIntervalSince1970, end.timeIntervalSince1970])
        return sqlite3_last_insert_rowid(db)
    }

    func updateEnd(sessionID: Int64, end: Date) {
        run("UPDATE sessions SET ended_at = ? WHERE id = ?", [end.timeIntervalSince1970, sessionID])
    }

    // MARK: - Agrégats (hors catégories masquées)

    /// Sessions de l'intervalle, tronquées aux bornes, sans les catégories masquées.
    private static let visibleSessions = """
        FROM sessions s
        LEFT JOIN app_categories ac ON ac.bundle_id = s.bundle_id
        LEFT JOIN categories c ON c.id = ac.category_id
        WHERE s.ended_at > ?1 AND s.started_at < ?2 AND COALESCE(c.hidden, 0) = 0
        """
    private static let clippedDuration = "SUM(MIN(s.ended_at, ?2) - MAX(s.started_at, ?1))"

    func usageByApp(in interval: DateInterval) -> [AppUsage] {
        var result: [AppUsage] = []
        run("""
            SELECT s.bundle_id, MAX(s.app_name), COALESCE(c.id, 0), \(Self.clippedDuration) AS secs
            \(Self.visibleSessions)
            GROUP BY s.bundle_id
            ORDER BY secs DESC
            """, bounds(interval)
        ) { stmt in
            result.append(AppUsage(
                bundleID: String(cString: sqlite3_column_text(stmt, 0)),
                name: String(cString: sqlite3_column_text(stmt, 1)),
                categoryID: sqlite3_column_int64(stmt, 2),
                duration: sqlite3_column_double(stmt, 3)))
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

    /// Les apps de la catégorie supprimée redeviennent « À classer ».
    func deleteCategory(_ id: CategoryID) {
        run("DELETE FROM categories WHERE id = ? AND is_system = 0", [id])
    }

    func setHidden(_ id: CategoryID, _ hidden: Bool) {
        run("UPDATE categories SET hidden = ? WHERE id = ?", [Int64(hidden ? 1 : 0), id])
    }

    // MARK: - Catégorie des apps

    func knownApps() -> [KnownApp] {
        var result: [KnownApp] = []
        run("""
            SELECT s.bundle_id, MAX(s.app_name), COALESCE(ac.category_id, 0), COALESCE(ac.manual, 0),
                   SUM(s.ended_at - s.started_at) AS secs
            FROM sessions s
            LEFT JOIN app_categories ac ON ac.bundle_id = s.bundle_id
            GROUP BY s.bundle_id
            ORDER BY secs DESC
            """, []
        ) { stmt in
            result.append(KnownApp(
                bundleID: String(cString: sqlite3_column_text(stmt, 0)),
                name: String(cString: sqlite3_column_text(stmt, 1)),
                categoryID: sqlite3_column_int64(stmt, 2),
                manual: sqlite3_column_int64(stmt, 3) != 0,
                totalDuration: sqlite3_column_double(stmt, 4)))
        }
        return result
    }

    func categoryID(for bundleID: String) -> CategoryID {
        var id = uncategorizedID
        run("SELECT category_id FROM app_categories WHERE bundle_id = ?", [bundleID]) {
            id = sqlite3_column_int64($0, 0)
        }
        return id
    }

    func setCategory(_ categoryID: CategoryID, for bundleID: String, manual: Bool) {
        if categoryID == uncategorizedID {
            run("DELETE FROM app_categories WHERE bundle_id = ?", [bundleID])
        } else {
            run("INSERT OR REPLACE INTO app_categories (bundle_id, category_id, manual) VALUES (?, ?, ?)",
                [bundleID, categoryID, Int64(manual ? 1 : 0)])
        }
    }

    /// Oublie les catégories choisies automatiquement, pour les faire recalculer.
    func clearAutomaticCategories() {
        run("DELETE FROM app_categories WHERE manual = 0", [])
    }

    // MARK: - SQLite

    private var errorMessage: String { String(cString: sqlite3_errmsg(db)) }

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
