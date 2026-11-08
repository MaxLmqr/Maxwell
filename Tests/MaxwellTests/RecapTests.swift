import Foundation
import Testing
@testable import Maxwell

@Suite("Récap")
final class RecapTests {
    private let url: URL
    private let db: Database
    private let chrome = "com.google.Chrome"
    /// Paris, semaine du lundi : les Récaps ne dépendent pas du Mac qui lance les tests.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        calendar.firstWeekday = 2
        return calendar
    }()

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("RecapTests-\(UUID().uuidString).sqlite")
        db = try Database(url: url)
    }

    deinit {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    // MARK: - Outils

    private func category(_ name: String) -> CategoryID {
        db.categories().first { $0.name == name }!.id
    }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    /// Une Session dans `bundleID` (et sur `site`), rangée dans `categoryName`.
    private func session(_ bundleID: String, in categoryName: String? = nil, site: String? = nil,
                         from start: Date, minutes: Double) {
        if let categoryName {
            if let site {
                db.setCategory(category(categoryName), for: .site(site), manual: true)
            } else {
                db.setCategory(category(categoryName), for: .app(bundleID), manual: false)
            }
        }
        db.insertSession(bundleID: bundleID, appName: bundleID, site: site,
                         start: start, end: start.addingTimeInterval(minutes * 60))
    }

    private func recap(_ period: Period, containing date: Date, now: Date) -> Recap {
        Recap(db: db, period: period, containing: date, now: now, calendar: calendar)
    }

    // MARK: - Catégories

    @Test func categoriesAreRankedAndSplitIntoPrincipalAndOthers() {
        session("xcode", in: "Développement", from: date(11, 2, 9), minutes: 120)
        session("slack", in: "Communication", from: date(11, 2, 11), minutes: 30)
        session(chrome, in: "Navigation", from: date(11, 2, 14), minutes: 60)
        session("figma", in: "Design", from: date(11, 2, 15), minutes: 20)
        session("notes", in: "Écriture et documents", from: date(11, 2, 16), minutes: 10)
        session("zoom", in: "Réunions", from: date(11, 2, 17), minutes: 5)

        let recap = recap(.day, containing: date(11, 2, 12), now: date(11, 3, 9))

        #expect(recap.total == 245 * 60)
        #expect(recap.categories.map(\.name) == ["Développement", "Navigation", "Communication", "Design",
                                                 "Écriture et documents", "Réunions"])
        #expect(recap.principal.map(\.name) == ["Développement", "Navigation", "Communication", "Design"])
        #expect(recap.others.count == 2)
        #expect(recap.othersDuration == 15 * 60)
        #expect(recap.appCount == 6)
    }

    @Test func hiddenCategoriesDoNotCount() {
        session("xcode", in: "Développement", from: date(11, 2, 9), minutes: 60)
        session("loginwindow", in: "Système", from: date(11, 2, 10), minutes: 30)

        let recap = recap(.day, containing: date(11, 2), now: date(11, 3, 9))

        #expect(recap.total == 3_600)
        #expect(recap.categories.map(\.name) == ["Développement"])
        #expect(recap.buckets.map(\.total).reduce(0, +) == 3_600)
    }

    @Test func anActivityWithoutCategoryIsToBeClassified() {
        session("mystery", from: date(11, 2, 9), minutes: 10)

        let recap = recap(.day, containing: date(11, 2), now: date(11, 3, 9))

        #expect(recap.categories.map(\.id) == [uncategorizedID])
        #expect(recap.categories.first?.name == "À classer")
    }

    // MARK: - Comparaison

    @Test func aCurrentPeriodIsComparedToTheSameElapsedTime() {
        // Semaine passée : lundi 9 h – 10 h, puis mardi ; on est lundi 11 h.
        session("xcode", in: "Développement", from: date(10, 26, 9), minutes: 60)
        session("xcode", from: date(10, 27, 9), minutes: 120)
        session("xcode", from: date(11, 2, 9), minutes: 90)

        let recap = recap(.week, containing: date(11, 2, 11), now: date(11, 2, 11))

        #expect(recap.previousTotal == 3_600)
        #expect(recap.change == .percent(50))
    }

    @Test func aPastPeriodIsComparedToTheWholePreviousOne() {
        session("xcode", in: "Développement", from: date(10, 19, 9), minutes: 60)
        session("xcode", from: date(10, 25, 20), minutes: 60)
        session("xcode", from: date(10, 26, 9), minutes: 60)

        let recap = recap(.week, containing: date(10, 28), now: date(11, 8, 12))

        #expect(recap.previousTotal == 7_200)
        #expect(recap.change == .percent(-50))
    }

    @Test func anAlmostEmptyPreviousPeriodCannotBeCompared() {
        session("xcode", in: "Développement", from: date(11, 1, 9), minutes: 0.5)
        session("xcode", from: date(11, 2, 9), minutes: 60)

        let recap = recap(.day, containing: date(11, 2), now: date(11, 2, 12))

        #expect(recap.previousTotal == 30)
        #expect(recap.change == .notEnoughData)
    }

    // MARK: - Répartition

    @Test func theAverageOnlyCountsActiveDays() {
        session("xcode", in: "Développement", from: date(11, 2, 9), minutes: 120)
        session("xcode", from: date(11, 3, 9), minutes: 0.5)
        session("xcode", from: date(11, 4, 9), minutes: 60)

        let recap = recap(.week, containing: date(11, 4), now: date(11, 8, 20))

        #expect(recap.buckets.count == 7)
        #expect(recap.buckets.map(\.isActive) == [true, false, true, false, false, false, false])
        #expect(recap.activeDayAverage == (180 * 60 + 30) / 2)
    }

    @Test func aSessionAcrossMidnightIsSplitBetweenItsDays() {
        session("xcode", in: "Développement", from: date(11, 2, 23, 30), minutes: 60)

        let recap = recap(.week, containing: date(11, 2), now: date(11, 8, 20))

        #expect(recap.buckets[0].total == 1_800)
        #expect(recap.buckets[1].total == 1_800)
    }

    @Test func eachBucketKnowsTheTimeOfTheOtherCategories() {
        session("xcode", in: "Développement", from: date(11, 2, 9), minutes: 120)
        session(chrome, in: "Navigation", from: date(11, 2, 11), minutes: 60)
        session("slack", in: "Communication", from: date(11, 2, 12), minutes: 30)
        session("figma", in: "Design", from: date(11, 2, 13), minutes: 20)
        session("notes", in: "Écriture et documents", from: date(11, 3, 9), minutes: 10)
        session("zoom", in: "Réunions", from: date(11, 3, 10), minutes: 5)
        session("xcode", from: date(11, 3, 11), minutes: 40)

        let recap = recap(.week, containing: date(11, 2), now: date(11, 8, 20))

        #expect(recap.buckets[0].others == 0)
        #expect(recap.buckets[1].others == 15 * 60)
        let development: TimeInterval? = recap.buckets[1].byCategory[category("Développement")]
        #expect(development == 2_400)
    }

    @Test func theDayClocksGoBackHasTwentyFiveHours() {
        let recap = recap(.day, containing: date(10, 25, 12), now: date(11, 2))

        #expect(recap.buckets.count == 25)
    }

    // MARK: - Apps et Sites

    @Test func smallSitesAreFoldedUnlessTheCategoryOnlyHasSmallSites() {
        session(chrome, in: "Navigation", site: nil, from: date(11, 2, 9), minutes: 15)
        session(chrome, site: "youtube.com", from: date(11, 2, 10), minutes: 30)
        session(chrome, site: "github.com", from: date(11, 2, 11), minutes: 5)
        session(chrome, in: "Développement", site: "stackoverflow.com", from: date(11, 2, 12), minutes: 3)

        let recap = recap(.day, containing: date(11, 2), now: date(11, 3, 9))
        let navigation = recap.category(category("Navigation"))
        let development = recap.category(category("Développement"))

        #expect(navigation?.subjects.map(\.subject) == [.site("youtube.com"), .app(chrome)])
        #expect(navigation?.foldedSites.map(\.subject) == [.site("github.com")])
        #expect(development?.subjects.map(\.subject) == [.site("stackoverflow.com")])
        #expect(development?.foldedSites.isEmpty == true)
    }

    @Test func aBrowserCountsOnceAmongTheAppsUsed() {
        session(chrome, in: "Navigation", site: nil, from: date(11, 2, 9), minutes: 5)
        session(chrome, site: "youtube.com", from: date(11, 2, 10), minutes: 30)
        session(chrome, site: "github.com", from: date(11, 2, 11), minutes: 20)
        session("xcode", in: "Développement", from: date(11, 2, 12), minutes: 60)

        let recap = recap(.day, containing: date(11, 2), now: date(11, 3, 9))

        #expect(recap.appCount == 2)
    }
}
