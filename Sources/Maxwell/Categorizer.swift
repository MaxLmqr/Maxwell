import AppKit
import FoundationModels

/// Classe une App que Max n'a pas encore rangée. Deux implémentations :
/// Apple Intelligence dans l'app, une fausse dans les tests.
@MainActor
protocol AppClassifier {
    /// Pourquoi le classement automatique ne marche pas sur ce Mac ; nil s'il marche.
    var unavailableReason: String? { get }
    /// Un dialogue ou un agent de macOS, qui va d'office dans Système.
    func isSystemApp(_ bundleID: String) -> Bool
    /// La Catégorie choisie parmi `categories`, ou nil si le classement n'a pas abouti.
    func classify(name: String, bundleID: String, among categories: [Category]) async -> CategoryID?
}

/// D'où vient la Catégorie d'une App ou d'un Site.
enum CategoryOrigin: Equatable {
    /// Pas encore de Catégorie : l'App attend le classement, le Site attend que Max en choisisse une
    /// (ou que son navigateur en ait une).
    case unclassified
    /// Max l'a choisie.
    case byMax
    /// Un Site sans choix de Max suit la Catégorie de son navigateur.
    case followsBrowser
    /// Choisie automatiquement : par Apple Intelligence, ou Système pour un dialogue de macOS.
    case automatic
}

extension KnownApp {
    var origin: CategoryOrigin {
        if categoryID == uncategorizedID { return .unclassified }
        if manual { return .byMax }
        return site == nil ? .automatic : .followsBrowser
    }
}

/// La Catégorisation : la liste des Catégories, la Catégorie de chaque App et de chaque Site,
/// et les choix de Max. Toute modification passe par ici, qui prévient les vues et relance le classement.
/// Les Apps sans Catégorie sont classées par `AppClassifier` ; les Sites ne le sont jamais :
/// sans Catégorie choisie par Max, ils suivent leur navigateur.
@MainActor
final class Categorizer: ObservableObject {
    /// Change à chaque modification des catégories : les vues l'observent pour se rafraîchir.
    @Published private(set) var revision = 0
    @Published private(set) var isRunning = false

    private let db: Database
    private let classifier: AppClassifier
    private var rerunRequested = false
    private var running: Task<Void, Never>?

    /// Sans `classifier`, les Apps sont classées par Apple Intelligence.
    init(db: Database, classifier: AppClassifier? = nil) {
        self.db = db
        self.classifier = classifier ?? AppleIntelligenceClassifier()
    }

    var availabilityMessage: String? { classifier.unavailableReason }

    // MARK: - Lecture

    func categories() -> [Category] { db.categories() }

    /// Toutes les Apps et tous les Sites déjà vus, avec leur Catégorie et son origine (`KnownApp.origin`).
    func knownApps() -> [KnownApp] { db.knownApps() }

    // MARK: - Choix de Max

    /// Max range une App ou un Site dans une Catégorie : le classement automatique n'y touche plus.
    func assign(_ categoryID: CategoryID, to subject: Subject) {
        db.setCategory(categoryID, for: subject, manual: true)
        changed()
    }

    /// Max retire son choix : une App repart au classement automatique, un Site suit de nouveau son navigateur.
    func withdrawChoice(for subject: Subject) {
        db.setCategory(uncategorizedID, for: subject, manual: false)
        changed()
    }

    /// Renvoie l'identifiant de la nouvelle Catégorie, ou nil si le nom existe déjà.
    @discardableResult
    func addCategory(named name: String) -> CategoryID? {
        let id = db.addCategory(name: name)
        if id != nil { changed() }
        return id
    }

    func rename(_ id: CategoryID, to name: String) {
        db.renameCategory(id, to: name)
        changed()
    }

    /// Les Apps et les Sites de la Catégorie supprimée redeviennent « À classer ».
    func delete(_ id: CategoryID) {
        db.deleteCategory(id)
        changed()
    }

    func setSymbol(_ symbol: String, of id: CategoryID) {
        db.setSymbol(id, symbol)
        changed()
    }

    func setHidden(_ hidden: Bool, _ id: CategoryID) {
        db.setHidden(id, hidden)
        changed()
    }

    /// Oublie les Catégories choisies automatiquement et relance le classement. Les choix de Max restent.
    func reclassifyAutomatic() {
        db.clearAutomaticCategories()
        changed()
    }

    // MARK: - Classement automatique

    /// À appeler quand une app passe au premier plan.
    func appSeen(_ bundleID: String) {
        if db.categoryID(for: .app(bundleID)) == uncategorizedID { classifyPending() }
    }

    func classifyPending() {
        guard !isRunning else {
            rerunRequested = true
            return
        }
        isRunning = true
        running = Task {
            repeat {
                rerunRequested = false
                await classifyUncategorizedApps()
            } while rerunRequested
            isRunning = false
        }
    }

    /// Attend la fin du classement en cours, s'il y en a un. Sert aux tests.
    func waitForClassification() async {
        await running?.value
    }

    private func changed() {
        revision += 1
        classifyPending()
    }

    private func classifyUncategorizedApps() async {
        let pending = db.knownApps().filter { $0.site == nil && $0.categoryID == uncategorizedID }
        guard !pending.isEmpty else { return }
        let categories = db.categories()

        for app in pending {
            if classifier.isSystemApp(app.bundleID), let system = categories.first(where: \.isSystem) {
                db.setCategory(system.id, for: .app(app.bundleID), manual: false)
            } else if let id = await classifier.classify(name: app.name, bundleID: app.bundleID,
                                                         among: categories) {
                db.setCategory(id, for: .app(app.bundleID), manual: false)
            } else {
                continue
            }
            revision += 1
        }
    }
}

/// Le classement par le modèle d'Apple Intelligence, sur le Mac, qui choisit obligatoirement
/// dans la liste des catégories.
@MainActor
struct AppleIntelligenceClassifier: AppClassifier {
    var unavailableReason: String? {
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

    /// Dialogues et agents de macOS : apps Apple sans icône dans le Dock.
    func isSystemApp(_ bundleID: String) -> Bool {
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

    func classify(name: String, bundleID: String, among categories: [Category]) async -> CategoryID? {
        guard SystemLanguageModel.default.availability == .available else { return nil }
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
                to: "Application : \(name) (identifiant : \(bundleID))",
                schema: schema)
            let chosen = try response.content.value(String.self)
            return categories.first { $0.name == chosen }?.id
        } catch {
            NSLog("Maxwell classification error for \(bundleID): \(error)")
            return nil
        }
    }
}
