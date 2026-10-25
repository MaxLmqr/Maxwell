import AppKit
import SwiftUI

/// Le vert de MaxActivity marque ce qui compte : l'app en cours et les catégories principales.
/// Tout le reste reste en gris système, qui suit le mode sombre.
enum Theme {
    static let accent = adaptive(light: 0x1D9E75, dark: 0x34B88B)
    static let neutralBar = Color.primary.opacity(0.10)
    static let emptyBar = Color.primary.opacity(0.06)

    /// Rampe d'une seule teinte pour les quatre catégories les plus utilisées d'une période :
    /// plus une catégorie compte, plus elle est proche du vert de l'app.
    static let rampFills: [Color] = [
        adaptive(light: 0x1D9E75, dark: 0x34B88B),
        adaptive(light: 0x4FB792, dark: 0x26906E),
        adaptive(light: 0x8DD1B6, dark: 0x1D6E55),
        adaptive(light: 0xC4E7D8, dark: 0x17513F),
    ]
    /// Couleur du pictogramme posé sur chaque teinte de la rampe, choisie pour rester lisible.
    static let rampGlyphs: [Color] = [
        adaptive(light: 0xFFFFFF, dark: 0x052A1E),
        adaptive(light: 0xFFFFFF, dark: 0xFFFFFF),
        adaptive(light: 0x0B5C46, dark: 0xFFFFFF),
        adaptive(light: 0x0B5C46, dark: 0xBFE5D5),
    ]
    /// Les catégories au-delà de la quatrième.
    static let othersFill = Color.primary.opacity(0.09)

    static func fill(rank: Int) -> Color { rank < rampFills.count ? rampFills[rank] : othersFill }
    static func glyph(rank: Int) -> Color { rank < rampGlyphs.count ? rampGlyphs[rank] : .secondary }

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
/// Leur rang donne leur couleur : les quatre premières prennent la rampe de vert.
struct CategoryRanking {
    struct Entry: Identifiable {
        let id: CategoryID
        let name: String
        let symbol: String
        let duration: TimeInterval
        let rank: Int
        var fill: Color { Theme.fill(rank: rank) }
        var glyph: Color { Theme.glyph(rank: rank) }
    }

    static let colorCount = Theme.rampFills.count

    let entries: [Entry]
    var total: TimeInterval { entries.reduce(0) { $0 + $1.duration } }
    var colored: ArraySlice<Entry> { entries.prefix(Self.colorCount) }

    init(durations: [CategoryID: TimeInterval], categories: [Category]) {
        let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        entries = durations
            .filter { $0.value >= 1 }
            .sorted { $0.value > $1.value }
            .enumerated()
            .map { rank, item in
                let category = byID[item.key]
                return Entry(id: item.key,
                             name: category?.name ?? "À classer",
                             symbol: category?.symbol ?? Category.uncategorizedSymbol,
                             duration: item.value, rank: rank)
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

/// Icônes des principales apps d'une catégorie, légèrement superposées.
struct AppIconStack: View {
    let bundleIDs: [String]
    var size: CGFloat = 16

    var body: some View {
        HStack(spacing: 2) {
            ForEach(bundleIDs.prefix(3), id: \.self) { id in
                Image(nsImage: AppIcon.image(for: id))
                    .resizable()
                    .frame(width: size, height: size)
            }
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
            Image(nsImage: AppIcon.image(for: app.bundleID))
                .resizable()
                .frame(width: iconSize, height: iconSize)
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
