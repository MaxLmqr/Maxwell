import Foundation
import Testing
@testable import Maxwell

/// Range chaque App dans la Catégorie qu'on lui a dite, et note qui on lui a demandé de classer.
@MainActor
private final class FakeClassifier: AppClassifier {
    var answers: [String: String] = [:]
    var systemApps: Set<String> = []
    var unavailableReason: String?
    private(set) var asked: [String] = []

    func isSystemApp(_ bundleID: String) -> Bool { systemApps.contains(bundleID) }

    func classify(name: String, bundleID: String, among categories: [Maxwell.Category]) async -> CategoryID? {
        asked.append(bundleID)
        guard unavailableReason == nil, let answer = answers[bundleID] else { return nil }
        return categories.first { $0.name == answer }?.id
    }
}

@MainActor
@Suite("Catégorisation")
final class CategorizerTests {
    private let url: URL
    private let db: Database
    private let classifier = FakeClassifier()
    private let categorizer: Categorizer
    private let chrome = "com.google.Chrome"

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("CategorizerTests-\(UUID().uuidString).sqlite")
        db = try Database(url: url)
        categorizer = Categorizer(db: db, classifier: classifier)
    }

    deinit {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    private func category(_ name: String) -> CategoryID {
        db.categories().first { $0.name == name }!.id
    }

    private func seen(_ bundleID: String, site: String? = nil) {
        db.insertSession(bundleID: bundleID, appName: bundleID, site: site,
                         start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 600))
    }

    private func known(_ subject: Subject) -> KnownApp? {
        categorizer.knownApps().first { $0.subject == subject }
    }

    private func classify() async {
        categorizer.classifyPending()
        await categorizer.waitForClassification()
    }

    @Test func aNewAppIsClassifiedAutomatically() async {
        classifier.answers["xcode"] = "Développement"
        seen("xcode")

        await classify()

        #expect(known(.app("xcode"))?.categoryID == category("Développement"))
        #expect(known(.app("xcode"))?.origin == .automatic)
    }

    @Test func aMacOSDialogGoesToSystemWithoutAskingTheModel() async {
        classifier.systemApps = ["com.apple.dialog"]
        seen("com.apple.dialog")

        await classify()

        #expect(known(.app("com.apple.dialog"))?.categoryID == category("Système"))
        #expect(classifier.asked.isEmpty)
    }

    @Test func anAppStaysUnclassifiedWhenTheModelIsUnavailable() async {
        classifier.unavailableReason = "indisponible"
        classifier.answers["xcode"] = "Développement"
        seen("xcode")

        await classify()

        #expect(known(.app("xcode"))?.origin == .unclassified)
        #expect(categorizer.availabilityMessage == "indisponible")
    }

    @Test func sitesAreNeverClassifiedAutomatically() async {
        seen(chrome)
        seen(chrome, site: "github.com")

        await classify()

        #expect(classifier.asked == [chrome])
        #expect(known(.site("github.com"))?.origin == .unclassified)
    }

    @Test func aBrowserSeenOnlyOnSitesIsStillClassified() async {
        // Le premier classement échoue, et ensuite Chrome n'a plus que des Sessions avec un Site.
        classifier.unavailableReason = "indisponible"
        seen(chrome, site: "github.com")
        await classify()
        #expect(known(.site("github.com"))?.origin == .unclassified)

        classifier.unavailableReason = nil
        classifier.answers[chrome] = "Navigation"
        seen(chrome, site: "mail.google.com")
        await classify()

        #expect(known(.site("github.com"))?.origin == .followsBrowser)
        #expect(known(.site("github.com"))?.categoryID == category("Navigation"))
        // Chrome n'a toujours pas de ligne à lui : seuls ses Sites apparaissent.
        #expect(known(.app(chrome)) == nil)
    }

    @Test func aSiteFollowsItsBrowserUntilMaxChoosesForIt() async {
        classifier.answers[chrome] = "Navigation"
        seen(chrome)
        seen(chrome, site: "github.com")
        await classify()
        #expect(known(.site("github.com"))?.origin == .followsBrowser)
        #expect(known(.site("github.com"))?.categoryID == category("Navigation"))

        categorizer.assign(category("Développement"), to: .site("github.com"))
        await categorizer.waitForClassification()
        #expect(known(.site("github.com"))?.origin == .byMax)
        #expect(known(.site("github.com"))?.categoryID == category("Développement"))

        categorizer.withdrawChoice(for: .site("github.com"))
        await categorizer.waitForClassification()
        #expect(known(.site("github.com"))?.origin == .followsBrowser)
        #expect(known(.site("github.com"))?.categoryID == category("Navigation"))
    }

    @Test func withdrawingMaxsChoiceSendsAnAppBackToAutomaticClassification() async {
        classifier.answers["xcode"] = "Développement"
        seen("xcode")
        categorizer.assign(category("Outils"), to: .app("xcode"))
        await categorizer.waitForClassification()
        #expect(known(.app("xcode"))?.origin == .byMax)

        categorizer.withdrawChoice(for: .app("xcode"))
        await categorizer.waitForClassification()

        #expect(known(.app("xcode"))?.origin == .automatic)
        #expect(known(.app("xcode"))?.categoryID == category("Développement"))
    }

    @Test func reclassifyingKeepsMaxsChoices() async {
        classifier.answers = ["xcode": "Outils", "slack": "Communication"]
        seen("xcode")
        seen("slack")
        seen(chrome, site: "github.com")
        await classify()
        categorizer.assign(category("Développement"), to: .app("xcode"))
        categorizer.assign(category("Développement"), to: .site("github.com"))
        await categorizer.waitForClassification()

        classifier.answers["slack"] = "Réunions"
        categorizer.reclassifyAutomatic()
        await categorizer.waitForClassification()

        #expect(known(.app("xcode"))?.categoryID == category("Développement"))
        #expect(known(.site("github.com"))?.categoryID == category("Développement"))
        #expect(known(.app("slack"))?.categoryID == category("Réunions"))
    }

    @Test func everyChangeByMaxRefreshesTheViews() async {
        let before = categorizer.revision
        let id = categorizer.addCategory(named: "Lecture")!
        categorizer.rename(id, to: "Lectures")
        categorizer.setSymbol("book", of: id)
        categorizer.setHidden(true, id)
        categorizer.delete(id)
        await categorizer.waitForClassification()

        #expect(categorizer.revision == before + 5)
        #expect(!categorizer.categories().contains { $0.id == id })
    }

    @Test func addingAnExistingNameDoesNothing() {
        let before = categorizer.revision
        #expect(categorizer.addCategory(named: "Design") == nil)
        #expect(categorizer.revision == before)
    }
}
