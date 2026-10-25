import Foundation
import Testing
@testable import MaxActivity

@MainActor
@Suite("Réglage de l'Étagère")
struct ShelfControllerTests {
    /// Des préférences à part, pour ne pas toucher à celles de Max.
    private func freshDefaults() -> (UserDefaults, String) {
        let suite = "ShelfControllerTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func aShakeOpensTheShelfByDefault() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(ShelfController(defaults: defaults).opensOnShake)
    }

    @Test func turningTheShakeOffIsRemembered() {
        let (defaults, suite) = freshDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        ShelfController(defaults: defaults).opensOnShake = false
        #expect(ShelfController(defaults: defaults).opensOnShake == false)
    }
}
