import Testing
@testable import Maxwell

@Suite("Teintes des catégories")
struct ThemeTests {
    private func category(_ id: CategoryID) -> Category {
        Category(id: id, name: "C\(id)", symbol: Category.defaultSymbol, hidden: false, isSystem: false)
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
