import AppKit
import FoundationModels

/// Donne une catégorie à chaque app et à chaque site qui n'en a pas encore.
/// Les dialogues d'Apple vont dans Système ; les autres apps et les sites sont classés par le modèle
/// d'Apple Intelligence, sur le Mac, qui choisit obligatoirement dans la liste des catégories.
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
            return "Active Apple Intelligence dans les Réglages Système pour classer les nouvelles apps et les nouveaux sites automatiquement."
        case .unavailable(.modelNotReady):
            return "Le modèle d'Apple Intelligence est en cours de téléchargement. Les nouvelles apps et les nouveaux sites seront classés ensuite."
        case .unavailable(.deviceNotEligible):
            return "Ce Mac ne prend pas en charge Apple Intelligence : classe les nouvelles apps et les nouveaux sites à la main."
        case .unavailable:
            return "Apple Intelligence est indisponible : classe les nouvelles apps et les nouveaux sites à la main."
        }
    }

    /// À appeler quand une app passe au premier plan, ou qu'un site s'ouvre dans Chrome.
    func seen(_ subject: Subject) {
        if db.categoryID(for: subject) == uncategorizedID { classifyPending() }
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
        let pending = db.knownApps().filter { $0.categoryID == uncategorizedID }
        guard !pending.isEmpty else { return }
        let categories = db.categories()
        let modelAvailable = SystemLanguageModel.default.availability == .available

        for app in pending {
            if app.site == nil, isAppleBackgroundApp(app.bundleID), let system = categories.first(where: \.isSystem) {
                db.setCategory(system.id, for: app.subject, manual: false)
            } else if modelAvailable, let category = await askModel(app: app, categories: categories) {
                db.setCategory(category.id, for: app.subject, manual: false)
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
        "Développement": "éditeurs de code, IDE, terminaux, outils de développeur, sites comme GitHub ou Stack Overflow",
        "IA": "assistants d'intelligence artificielle comme Claude ou ChatGPT",
        "Communication": "messagerie et e-mail : Slack, Mail, Gmail, Messages, WhatsApp",
        "Réunions": "visioconférence : Zoom, Google Meet, Teams, FaceTime",
        "Design": "création graphique : Figma, Sketch, retouche photo, icônes",
        "Écriture et documents": "traitement de texte, notes, lecteurs de PDF comme Aperçu, tableurs, présentations, Google Docs, Notion",
        "Navigation": "uniquement les navigateurs web (Safari, Chrome, Arc, Firefox) et les moteurs de recherche (Google, Bing, DuckDuckGo)",
        "Divertissement": "musique, vidéo, jeux, App Store, YouTube, Netflix",
        "Outils": "utilitaires : Finder, lanceurs comme Raycast ou Alfred, captures d'écran comme Shottr, nettoyage, gestion de fichiers",
        "Système": "composants de macOS : dialogues, agents, notifications, Réglages Système",
    ]

    private func askModel(app: KnownApp, categories: [Category]) async -> Category? {
        // Système ne concerne que les composants de macOS, jamais un site.
        let choices = app.site == nil ? categories : categories.filter { !$0.isSystem }
        let names = choices.map(\.name)
        let list = choices
            .map { category in Self.hints[category.name].map { "- \(category.name) : \($0)" } ?? "- \(category.name)" }
            .joined(separator: "\n")
        let (task, prompt) = if let site = app.site {
            ("Tu ranges des sites web par type d'usage. "
                + "Choisis la catégorie qui décrit le mieux ce qu'on fait principalement sur le site.",
             "Site web : \(site)")
        } else {
            ("Tu ranges des applications macOS par type d'usage. "
                + "Choisis la catégorie qui décrit le mieux l'usage principal de l'application.",
             "Application : \(app.name) (identifiant : \(app.bundleID))")
        }
        do {
            let schema = try GenerationSchema(
                root: DynamicGenerationSchema(name: "Categorie", anyOf: names), dependencies: [])
            let session = LanguageModelSession(instructions: """
                \(task)
                Catégories :
                \(list)
                """)
            let response = try await session.respond(to: prompt, schema: schema)
            let name = try response.content.value(String.self)
            return choices.first { $0.name == name }
        } catch {
            NSLog("Maxwell classification error for \(app.site ?? app.bundleID): \(error)")
            return nil
        }
    }
}
