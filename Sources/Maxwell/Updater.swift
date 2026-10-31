import AppKit
import Sparkle

/// Mises à jour par Sparkle : l'app lit l'appcast publié avec chaque release GitHub
/// (adresse `SUFeedURL` dans Info.plist) et installe les versions signées avec la clé de Max.
@MainActor
final class Updater: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    /// Absent dans les captures de l'interface, où rien ne doit se mettre à jour.
    private(set) static var shared: Updater?

    private var controller: SPUStandardUpdaterController!

    static func start() {
        shared = Updater()
    }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
    }

    func checkForUpdates() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    // MARK: - SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Maxwell n'a pas d'icône dans le Dock : on passe devant pour que la fenêtre de mise à jour ne reste pas cachée.
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        NSApp.activate()
    }
}
