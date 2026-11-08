import Foundation
import Testing
@testable import Maxwell

@Suite("Teintes des catégories")
struct ThemeTests {
    private func category(_ id: CategoryID) -> Maxwell.Category {
        Maxwell.Category(id: id, name: "C\(id)", symbol: Maxwell.Category.defaultSymbol, hidden: false, isSystem: false)
    }

    @Test func defaultCategoriesKeepTheirHue() {
        let swatches = Theme.swatches(for: (1...10).map(category))
        for id in 1...10 {
            #expect(swatches[CategoryID(id)]?.fill == Theme.palette[id - 1].fill)
        }
        #expect(swatches[uncategorizedID]?.fill == Theme.uncategorized.fill)
    }

    @Test func addedCategoryTakesTheLeastWornHue() {
        // Réunions (4) supprimée : la première catégorie ajoutée reprend son orange.
        let ids: [CategoryID] = [1, 2, 3, 5, 6, 7, 8, 9, 10, 11]
        let swatches = Theme.swatches(for: ids.map(category))
        #expect(swatches[11]?.fill == Theme.palette[3].fill)
    }
}

@Suite("Ordre des catégories par défaut")
final class DefaultCategoryOrderTests {
    private let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("DefaultCategoryOrderTests-\(UUID().uuidString).sqlite")

    deinit {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    /// Les Catégories par défaut sont reconnues par leur identifiant : changer l'ordre de création
    /// décalerait leurs couleurs et leurs précisions pour Apple Intelligence sur les nouvelles installations.
    @Test func seedingFollowsTheDefaultCatalogue() throws {
        let db = try Database(url: url)
        let seeded = db.categories().sorted { $0.id < $1.id }
        // Les installations existantes ont été créées dans cet ordre : il ne doit pas changer.
        #expect(seeded.map(\.name) == ["Développement", "IA", "Communication", "Réunions", "Design",
                                       "Écriture et documents", "Navigation", "Divertissement", "Outils", "Système"])
        for category in seeded {
            let expected = DefaultCategory.withID(category.id)
            #expect(category.name == expected?.name)
            #expect(category.symbol == expected?.symbol)
            #expect(category.isSystem == expected?.isSystem)
            #expect(category.hidden == category.isSystem)
        }
        #expect(Theme.palette.count == DefaultCategory.all.count)
    }

    @MainActor
    @Test func aRenamedDefaultCategoryKeepsItsHint() throws {
        let db = try Database(url: url)
        let navigation = db.categories().first { $0.name == "Navigation" }!
        db.renameCategory(navigation.id, to: "Web")
        let renamed = db.categories().first { $0.id == navigation.id }!

        #expect(AppleIntelligenceClassifier.promptLine(for: renamed)
                == "- Web : navigateurs web uniquement : Safari, Chrome, Arc, Firefox")

        let addedID = db.addCategory(name: "Lecture")
        let added = db.categories().first { $0.id == addedID }!
        #expect(AppleIntelligenceClassifier.promptLine(for: added) == "- Lecture")
    }
}
