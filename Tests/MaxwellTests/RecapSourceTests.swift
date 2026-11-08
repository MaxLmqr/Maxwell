import Combine
import Foundation
import Testing
@testable import Maxwell

@MainActor
@Suite("Source des Récaps")
final class RecapSourceTests {
    private let url: URL
    private let db: Database

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("RecapSourceTests-\(UUID().uuidString).sqlite")
        db = try Database(url: url)
    }

    deinit {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    @Test func theViewsAreToldWhenTrackingTicksAndWhenMaxMovesAnApp() async {
        let tracker = Tracker(db: db)
        let categorizer = Categorizer(db: db, classifier: NoClassifier())
        let source = RecapSource(db: db, tracker: tracker, categorizer: categorizer)
        var changes = 0
        let subscription = source.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }

        let noon = Date(timeIntervalSince1970: 1_793_966_400)
        db.insertSession(bundleID: "xcode", appName: "Xcode", start: noon.addingTimeInterval(-3_600), end: noon)
        tracker.simulateNow(noon)
        #expect(source.now == noon)
        #expect(changes == 1)

        let tools = db.categories().first { $0.name == "Outils" }!.id
        categorizer.assign(tools, to: .app("xcode"))
        await categorizer.waitForClassification()
        #expect(changes == 2)
        #expect(source.recap(.day, containing: noon).categories.map(\.id) == [tools])
    }
}

@MainActor
private struct NoClassifier: AppClassifier {
    var unavailableReason: String? { nil }
    func isSystemApp(_ bundleID: String) -> Bool { false }
    func classify(name: String, bundleID: String, among categories: [Maxwell.Category]) async -> CategoryID? { nil }
}
