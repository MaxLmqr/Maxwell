import AppKit
import FoundationModels

/// Donne une catégorie à chaque app qui n'en a pas encore.
/// Les dialogues d'Apple vont dans Système ; les autres apps sont classées par le modèle
/// d'Apple Intelligence, sur le Mac, qui choisit obligatoirement dans la liste des catégories.
/// Les sites ne sont pas classés : sans catégorie choisie par Max, ils suivent leur navigateur.
@MainActor
final class Categorizer: ObservableObject {
    /// Change à chaque modification des catégories : les vues l'observent pour se rafraîchir.
    @Published private(set) var revision = 0
    @Published private(set) var isRunning = false

    let db: Database
    private var rerunRequested = false

    init(db: Database) {
        self.db = db
    }

    var availabilityMessage: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Active Apple Intelligence dans les Réglages Système pour classer les nouvelles apps automatiquement."
        case .unavailable(.modelNotReady):
            return "Le modèle d'Apple Intelligence est en cours de téléchargement. Les nouvelles apps seront classées ensuite."
        case .unavailable(.deviceNotEligible):
            return "Ce Mac ne prend pas en charge Apple Intelligence : classe les nouvelles apps à la main."
        case .unavailable:
            return "Apple Intelligence est indisponible : classe les nouvelles apps à la main."
        }
    }

    /// À appeler quand une app passe au premier plan.
    func appSeen(_ bundleID: String) {
        if db.categoryID(for: .app(bundleID)) == uncategorizedID { classifyPending() }
    }

    /// À appeler après toute modification faite par Max (catégorie d'une app ou d'un site, liste des catégories).
    func changed() {
        revision += 1
        classifyPending()
    }

    func reclassifyAutomatic() {
        db.clearAutomaticCategories()
        changed()
    }

    func classifyPending() {
        guard !isRunning else {
            rerunRequested = true
            return
        }
        isRunning = true
        Task {
            repeat {
                rerunRequested = false
                await classifyUncategorizedApps()
            } while rerunRequested
            isRunning = false
        }
    }

    private func classifyUncategorizedApps() async {
        let pending = db.knownApps().filter { $0.site == nil && $0.categoryID == uncategorizedID }
        guard !pending.isEmpty else { return }
        let categories = db.categories()
        let modelAvailable = SystemLanguageModel.default.availability == .available

        for app in pending {
            if isAppleBackgroundApp(app.bundleID), let system = categories.first(where: \.isSystem) {
                db.setCategory(system.id, for: .app(app.bundleID), manual: false)
            } else if modelAvailable, let category = await askModel(app: app, categories: categories) {
                db.setCategory(category.id, for: .app(app.bundleID), manual: false)
            } else {
                continue
            }
            revision += 1
        }
    }

    /// Dialogues et agents de macOS : apps Apple sans icône dans le Dock.
    private func isAppleBackgroundApp(_ bundleID: String) -> Bool {
        guard bundleID.hasPrefix("com.apple.") else { return false }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
              let info = Bundle(url: url)?.infoDictionary else { return true }
        let flag = { (key: String) in (info[key] as? Bool) ?? ((info[key] as? String) == "1") }
        return flag("LSUIElement") || flag("LSBackgroundOnly")
    }

    /// Précisions pour les catégories par défaut ; une catégorie ajoutée par Max n'a que son nom.
    private static let hints: [String: String] = [
        "Développement": "éditeurs de code, IDE, terminaux, outils de développeur",
        "IA": "assistants d'intelligence artificielle comme Claude ou ChatGPT",
        "Communication": "messagerie et e-mail : Slack, Mail, Messages, WhatsApp",
        "Réunions": "visioconférence : Zoom, Google Meet, Teams, FaceTime",
        "Design": "création graphique : Figma, Sketch, retouche photo, icônes",
        "Écriture et documents": "traitement de texte, notes, lecteurs de PDF comme Aperçu, tableurs, présentations",
        "Navigation": "navigateurs web uniquement : Safari, Chrome, Arc, Firefox",
        "Divertissement": "musique, vidéo, jeux, App Store",
        "Outils": "utilitaires : Finder, lanceurs comme Raycast ou Alfred, captures d'écran comme Shottr, nettoyage, gestion de fichiers",
        "Système": "composants de macOS : dialogues, agents, notifications, Réglages Système",
    ]

    private func askModel(app: KnownApp, categories: [Category]) async -> Category? {
        let names = categories.map(\.name)
        let list = categories
            .map { category in Self.hints[category.name].map { "- \(category.name) : \($0)" } ?? "- \(category.name)" }
            .joined(separator: "\n")
        do {
            let schema = try GenerationSchema(
                root: DynamicGenerationSchema(name: "Categorie", anyOf: names), dependencies: [])
            let session = LanguageModelSession(instructions: """
                Tu ranges des applications macOS par type d'usage. \
                Choisis la catégorie qui décrit le mieux l'usage principal de l'application.
                Catégories :
                \(list)
                """)
            let response = try await session.respond(
                to: "Application : \(app.name) (identifiant : \(app.bundleID))",
                schema: schema)
            let name = try response.content.value(String.self)
            return categories.first { $0.name == name }
        } catch {
            NSLog("Maxwell classification error for \(app.bundleID): \(error)")
            return nil
        }
    }
}
