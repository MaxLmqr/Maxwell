import AppKit
import SwiftUI

/// Le vert de Maxwell marque l'app elle-même : l'app en cours, les liens, les interrupteurs.
/// Chaque catégorie a sa propre teinte, la même d'une période à l'autre ; le reste est en gris système.
enum Theme {
    static let accent = adaptive(light: 0x1D9E75, dark: 0x34B88B)
    static let neutralBar = Color.primary.opacity(0.10)
    static let emptyBar = Color.primary.opacity(0.06)

    struct Swatch {
        let fill: Color
        /// Couleur du pictogramme posé sur la teinte, choisie pour rester lisible.
        let glyph: Color
    }

    /// Les teintes des catégories, dans l'ordre où les catégories par défaut sont créées
    /// (`Database.defaultCategories`, puis Système) : les identifiants 1 à 10 leur reviennent.
    static let palette: [Swatch] = [
        swatch(light: 0x2F7DD3, dark: 0x4C93E6),                      // bleu : Développement
        swatch(light: 0x8257D6, dark: 0x9C7BEA),                      // violet : IA
        swatch(light: 0x1D9E75, dark: 0x2FB386),                      // vert : Communication
        swatch(light: 0xE8822A, dark: 0xEE9445),                      // orange : Réunions
        swatch(light: 0xD9487E, dark: 0xE66694),                      // rose : Design
        swatch(light: 0xE2AE1F, dark: 0xE7B93A, glyph: 0x4A3500),    // ambre : Écriture et documents
        swatch(light: 0x1695B0, dark: 0x2DAEC6),                      // turquoise : Navigation
        // Rouge plus sombre que le vert : les deux restent distincts pour un œil qui les confond.
        swatch(light: 0xB8352B, dark: 0xC9483E),                      // rouge : Divertissement
        swatch(light: 0x86A62E, dark: 0x9AB944, glyph: 0x263300),    // olive : Outils
        swatch(light: 0x6B7A8F, dark: 0x8593A6),                      // ardoise : Système
    ]
    /// « À classer » n'a pas de teinte à elle.
    /// Gris assez soutenu pour que le pictogramme blanc reste lisible en mode clair.
    static let uncategorized = swatch(light: 0x80868F, dark: 0x6E747C)

    /// La teinte attitrée de chaque catégorie, qui ne dépend que de la liste des catégories :
    /// celles créées d'office gardent la leur, chaque catégorie ajoutée ensuite prend la teinte
    /// la moins portée. « À classer » prend `uncategorized`.
    static func swatches(for categories: [Category]) -> [CategoryID: Swatch] {
        var uses = [Int](repeating: 0, count: palette.count)
        var result: [CategoryID: Swatch] = [uncategorizedID: uncategorized]
        let byID = categories.sorted { $0.id < $1.id }
        for category in byID where category.id <= palette.count {
            uses[Int(category.id - 1)] += 1
        }
        for category in byID {
            let slot: Int
            if category.id <= palette.count {
                slot = Int(category.id - 1)
            } else {
                slot = uses.indices.min { uses[$0] < uses[$1] }!
                uses[slot] += 1
            }
            result[category.id] = palette[slot]
        }
        return result
    }

    /// Les catégories au-delà de la quatrième.
    static let othersFill = Color.primary.opacity(0.09)

    private static func swatch(light: UInt32, dark: UInt32, glyph: UInt32 = 0xFFFFFF) -> Swatch {
        Swatch(fill: adaptive(light: light, dark: dark), glyph: adaptive(light: glyph, dark: glyph))
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// Les catégories d'une période, de la plus utilisée à la moins utilisée.
/// Les quatre premières prennent leur teinte attitrée, les autres restent en gris.
struct CategoryRanking {
    struct Entry: Identifiable {
        let id: CategoryID
        let name: String
        let symbol: String
        let duration: TimeInterval
        let rank: Int
        /// La teinte de la catégorie, même quand elle n'est pas parmi les quatre premières.
        let swatch: Theme.Swatch
        var isColored: Bool { rank < CategoryRanking.colorCount }
        var fill: Color { isColored ? swatch.fill : Theme.othersFill }
        var glyph: Color { isColored ? swatch.glyph : .secondary }
    }

    static let colorCount = 4

    let entries: [Entry]
    var total: TimeInterval { entries.reduce(0) { $0 + $1.duration } }
    var colored: ArraySlice<Entry> { entries.prefix(Self.colorCount) }

    init(durations: [CategoryID: TimeInterval], categories: [Category]) {
        let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let swatches = Theme.swatches(for: categories)
        entries = durations
            .filter { $0.value >= 1 }
            .sorted { $0.value > $1.value }
            .enumerated()
            .map { rank, item in
                let category = byID[item.key]
                return Entry(id: item.key,
                             name: category?.name ?? "À classer",
                             symbol: category?.symbol ?? Category.uncategorizedSymbol,
                             duration: item.value, rank: rank,
                             swatch: swatches[item.key, default: Theme.uncategorized])
            }
    }

    func entry(_ id: CategoryID) -> Entry? { entries.first { $0.id == id } }
}

// MARK: - Composants

/// Petit libellé gris au-dessus d'un chiffre.
struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }
}

/// Grand chiffre en graisse légère.
struct BigNumber: View {
    let text: String
    var size: CGFloat = 30
    init(_ text: String, size: CGFloat = 30) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .light))
            .tracking(-0.5)
            .monospacedDigit()
    }
}

/// Pictogramme d'une catégorie sur un carré arrondi de sa couleur : il sert aussi de légende.
struct CategoryBadge: View {
    let symbol: String
    let fill: Color
    let glyph: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.48, weight: .medium))
            .foregroundStyle(glyph)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(fill))
    }
}

/// Icônes des principales apps et des principaux sites d'une catégorie.
struct AppIconStack: View {
    let subjects: [Subject]
    var size: CGFloat = 16

    var body: some View {
        HStack(spacing: 2) {
            ForEach(subjects.prefix(3), id: \.self) { subject in
                SubjectIcon(subject: subject, size: size)
            }
        }
    }
}

/// L'icône d'une App, ou l'initiale d'un Site sur un carré gris.
struct SubjectIcon: View {
    let subject: Subject
    var size: CGFloat = 16

    var body: some View {
        switch subject {
        case .app(let bundleID):
            Image(nsImage: AppIcon.image(for: bundleID))
                .resizable()
                .frame(width: size, height: size)
        case .site(let site):
            // Le dessin d'une icône d'app occupe environ 80 % de son cadre : le carré du site aussi.
            let side = size * 0.8
            Text(site.prefix(1).uppercased())
                .font(.system(size: side * 0.6, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: side, height: side)
                .background(RoundedRectangle(cornerRadius: side * 0.24, style: .continuous).fill(Theme.othersFill))
                .frame(width: size, height: size)
        }
    }
}

/// Évolution par rapport à la période précédente : une flèche et un pourcentage, sans jugement de couleur.
struct DeltaLabel: View {
    let current: TimeInterval
    let previous: TimeInterval

    var body: some View {
        if previous >= 60 {
            let change = Int(((current - previous) / previous * 100).rounded())
            HStack(spacing: 2) {
                Image(systemName: change > 0 ? "arrow.up.right" : change < 0 ? "arrow.down.right" : "arrow.right")
                    .imageScale(.small)
                Text("\(abs(change)) %")
            }
        } else {
            Text("—")
        }
    }
}

struct AppRow: View {
    let app: AppUsage
    var share: Double? = nil
    var iconSize: CGFloat = 18

    var body: some View {
        HStack(spacing: 10) {
            SubjectIcon(subject: app.subject, size: iconSize)
            Text(app.name).lineLimit(1)
            Spacer(minLength: 8)
            Text(formatDuration(app.duration))
                .foregroundStyle(.secondary)
            if let share {
                Text(formatShare(share))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .font(.system(size: 12))
        .monospacedDigit()
        .padding(.vertical, 4)
    }
}

/// Bouton façon élément de menu : pleine largeur, surbrillance au survol.
struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuRow(configuration: configuration)
    }

    private struct MenuRow: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hovering || configuration.isPressed ? 0.07 : 0)))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}
