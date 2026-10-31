import Foundation
import SQLite3
import Testing
@testable import Maxwell

@Suite("Sites dans la base")
final class SiteDatabaseTests {
    private let url: URL
    private let db: Database
    private let chrome = "com.google.Chrome"
    private let day = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 86_400)

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("SiteDatabaseTests-\(UUID().uuidString).sqlite")
        db = try Database(url: url)
    }

    deinit {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func category(_ name: String) -> CategoryID {
        db.categories().first { $0.name == name }!.id
    }

    /// Une session de `minutes` minutes, à partir de `at` minutes après le début de la journée.
    private func session(_ bundleID: String, site: String? = nil, at: Double, minutes: Double) {
        db.insertSession(bundleID: bundleID, appName: bundleID == chrome ? "Google Chrome" : bundleID, site: site,
                         start: Date(timeIntervalSince1970: at * 60),
                         end: Date(timeIntervalSince1970: (at + minutes) * 60))
    }

    @Test func timeOnASiteCountsInTheSiteCategoryNotTheBrowserOne() {
        db.setCategory(category("Navigation"), for: .app(chrome), manual: false)
        db.setCategory(category("Développement"), for: .site("github.com"), manual: false)
        session(chrome, site: "github.com", at: 0, minutes: 10)
        session(chrome, at: 10, minutes: 2)

        let durations = db.durationByCategory(in: day)
        #expect(durations[category("Développement")] == 600)
        #expect(durations[category("Navigation")] == 120)
    }

    @Test func eachSiteHasItsOwnLineBesideTheBrowser() {
        session(chrome, site: "github.com", at: 0, minutes: 10)
        session(chrome, site: "mail.google.com", at: 10, minutes: 5)
        session(chrome, site: "github.com", at: 15, minutes: 10)
        session(chrome, at: 25, minutes: 1)

        let usage = db.usageByApp(in: day)
        #expect(usage.map(\.subject) == [.site("github.com"), .site("mail.google.com"), .app(chrome)])
        #expect(usage.map(\.name) == ["github.com", "mail.google.com", "Google Chrome"])
        #expect(usage.map(\.bundleID) == [chrome, chrome, chrome])
        #expect(usage[0].duration == 1_200)
    }

    @Test func aSiteWithoutCategoryIsToBeClassifiedEvenIfTheBrowserHasOne() {
        db.setCategory(category("Navigation"), for: .app(chrome), manual: false)
        session(chrome, site: "github.com", at: 0, minutes: 10)

        #expect(db.durationByCategory(in: day)[uncategorizedID] == 600)
        #expect(db.knownApps().first { $0.site == "github.com" }?.categoryID == uncategorizedID)
    }

    @Test func reclassifyingForgetsAutomaticSiteCategoriesButKeepsManualOnes() {
        db.setCategory(category("Développement"), for: .site("github.com"), manual: true)
        db.setCategory(category("Divertissement"), for: .site("youtube.com"), manual: false)

        db.clearAutomaticCategories()

        #expect(db.categoryID(for: .site("github.com")) == category("Développement"))
        #expect(db.categoryID(for: .site("youtube.com")) == uncategorizedID)
    }

    @Test func aSiteKeepsItsCategoryApartFromAnAppWithTheSameKey() {
        db.setCategory(category("Développement"), for: .site("example.com"), manual: true)
        #expect(db.categoryID(for: .app("example.com")) == uncategorizedID)
    }

    @Test func theSiteCanBeSetAfterTheSessionStarted() {
        let id = db.insertSession(bundleID: chrome, appName: "Google Chrome",
                                  start: day.start, end: day.start.addingTimeInterval(300))
        db.updateSite(sessionID: id, site: "github.com")
        #expect(db.usageByApp(in: day).map(\.subject) == [.site("github.com")])
    }

    @Test func aDatabaseFromBeforeSitesGainsTheColumn() throws {
        let oldURL = url.deletingLastPathComponent().appendingPathComponent("old-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: oldURL) }
        var handle: OpaquePointer?
        sqlite3_open(oldURL.path, &handle)
        sqlite3_exec(handle, """
            CREATE TABLE sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, bundle_id TEXT NOT NULL,
                                   app_name TEXT NOT NULL, started_at REAL NOT NULL, ended_at REAL NOT NULL);
            INSERT INTO sessions (bundle_id, app_name, started_at, ended_at) VALUES ('com.apple.Notes', 'Notes', 0, 60);
            """, nil, nil, nil)
        sqlite3_close(handle)

        let migrated = try Database(url: oldURL)
        migrated.insertSession(bundleID: chrome, appName: "Google Chrome", site: "github.com",
                               start: Date(timeIntervalSince1970: 60), end: Date(timeIntervalSince1970: 120))
        #expect(Set(migrated.usageByApp(in: day).map(\.subject)) == [.app("com.apple.Notes"), .site("github.com")])
    }
}
