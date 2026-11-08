import Foundation

/// Une Catégorie créée d'office à l'installation, avec tout ce qui la distingue.
/// L'ordre de `all` est l'ordre de création : la première reçoit l'identifiant 1, et ainsi de suite.
/// C'est par cet identifiant, et non par leur nom que Max peut changer, qu'on les reconnaît ensuite.
struct DefaultCategory {
    let name: String
    /// Nom d'un pictogramme SF Symbols.
    let symbol: String
    let swatch: Theme.Swatch
    /// Précision donnée au modèle d'Apple Intelligence pour choisir cette Catégorie.
    let hint: String
    /// Système : masquée d'office, impossible à supprimer, elle reçoit les dialogues de macOS.
    var isSystem = false

    static let all: [DefaultCategory] = [
        DefaultCategory(name: "Développement", symbol: "chevron.left.forwardslash.chevron.right",
                        swatch: Theme.swatch(light: 0x2F7DD3, dark: 0x4C93E6),                     // bleu
                        hint: "éditeurs de code, IDE, terminaux, outils de développeur"),
        DefaultCategory(name: "IA", symbol: "sparkles",
                        swatch: Theme.swatch(light: 0x8257D6, dark: 0x9C7BEA),                     // violet
                        hint: "assistants d'intelligence artificielle comme Claude ou ChatGPT"),
        DefaultCategory(name: "Communication", symbol: "bubble.left.and.bubble.right",
                        swatch: Theme.swatch(light: 0x1D9E75, dark: 0x2FB386),                     // vert
                        hint: "messagerie et e-mail : Slack, Mail, Messages, WhatsApp"),
        DefaultCategory(name: "Réunions", symbol: "video",
                        swatch: Theme.swatch(light: 0xE8822A, dark: 0xEE9445),                     // orange
                        hint: "visioconférence : Zoom, Google Meet, Teams, FaceTime"),
        DefaultCategory(name: "Design", symbol: "paintpalette",
                        swatch: Theme.swatch(light: 0xD9487E, dark: 0xE66694),                     // rose
                        hint: "création graphique : Figma, Sketch, retouche photo, icônes"),
        DefaultCategory(name: "Écriture et documents", symbol: "doc.text",
                        swatch: Theme.swatch(light: 0xE2AE1F, dark: 0xE7B93A, glyph: 0x4A3500),   // ambre
                        hint: "traitement de texte, notes, lecteurs de PDF comme Aperçu, tableurs, présentations"),
        DefaultCategory(name: "Navigation", symbol: "globe",
                        swatch: Theme.swatch(light: 0x1695B0, dark: 0x2DAEC6),                     // turquoise
                        hint: "navigateurs web uniquement : Safari, Chrome, Arc, Firefox"),
        // Rouge plus sombre que le vert de Communication : les deux restent distincts pour un œil qui les confond.
        DefaultCategory(name: "Divertissement", symbol: "play.circle",
                        swatch: Theme.swatch(light: 0xB8352B, dark: 0xC9483E),                     // rouge
                        hint: "musique, vidéo, jeux, App Store"),
        DefaultCategory(name: "Outils", symbol: "wrench.and.screwdriver",
                        swatch: Theme.swatch(light: 0x86A62E, dark: 0x9AB944, glyph: 0x263300),   // olive
                        hint: "utilitaires : Finder, lanceurs comme Raycast ou Alfred, captures d'écran comme Shottr, nettoyage, gestion de fichiers"),
        DefaultCategory(name: "Système", symbol: "gearshape",
                        swatch: Theme.swatch(light: 0x6B7A8F, dark: 0x8593A6),                     // ardoise
                        hint: "composants de macOS : dialogues, agents, notifications, Réglages Système",
                        isSystem: true),
    ]

    /// La Catégorie par défaut qui a reçu cet identifiant, même si Max l'a renommée ;
    /// nil pour une Catégorie qu'il a ajoutée.
    static func withID(_ id: CategoryID) -> DefaultCategory? {
        id >= 1 && id <= all.count ? all[Int(id - 1)] : nil
    }
}
