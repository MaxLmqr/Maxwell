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

    @Test func rankingUsesTheSameHueAsTheCategoryList() {
        let categories = [1, 2, 3, 5, 6, 7, 8, 9, 10, 11].map(category)
        let ranking = CategoryRanking(durations: [11: 3_600, 1: 60], categories: categories)
        let swatches = Theme.swatches(for: categories)
        for entry in ranking.entries {
            #expect(entry.swatch.fill == swatches[entry.id]?.fill)
        }
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

    /// `Theme.palette` attribue ses teintes par identifiant : changer l'ordre de création
    /// des catégories par défaut décalerait toutes les couleurs des nouvelles installations.
    @Test func seedingOrderMatchesThePalette() throws {
        let db = try Database(url: url)
        let names = db.categories().sorted { $0.id < $1.id }.map(\.name)
        #expect(names == ["Développement", "IA", "Communication", "Réunions", "Design",
                          "Écriture et documents", "Navigation", "Divertissement", "Outils", "Système"])
        #expect(names.count == Theme.palette.count)
    }
}
