import AppKit
import SwiftUI

/// Le style Console de la fenêtre Maxwell : sombre, dense, des repères en chasse fixe, tout au clavier.
enum Console {
    static let background = Color(hex: 0x17191B)
    static let bar = Color(hex: 0x111314)
    static let field = Color(hex: 0x222528)
    static let selection = Color(hex: 0x1F3A31)
    static let hover = Color.white.opacity(0.04)
    static let text = Color(hex: 0xE8E6E0)
    static let secondary = Color(hex: 0xA6A59F)
    static let muted = Color(hex: 0x7C7B76)
    /// Le reste d'une barre quand une seule Catégorie est mise en avant.
    static let chartRest = Color(hex: 0x3A3D41)
    /// « Les autres » Catégories, hors des quatre principales.
    static let chartOthers = Color(hex: 0x62656A)
    static let accent = Color(hex: 0x5DCAA5)
    static let accentSoft = Color(hex: 0x9FE1CB)
    static let done = Color(hex: 0x1D9E75)
    static let late = Color(hex: 0xEF9F27)
    static let urgent = Color(hex: 0xF09595)
    static let line = Color.white.opacity(0.07)

    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Les deux modules de Maxwell.
enum Module: String, CaseIterable, Identifiable {
    case time = "Temps"
    case tasks = "Tâches"

    var id: String { rawValue }
    var symbol: String { self == .time ? "chart.bar.xaxis" : "checklist" }
    var key: KeyEquivalent { self == .time ? "1" : "2" }

    /// La touche du haut du clavier qui porte 1 ou 2, quelle que soit la disposition :
    /// en AZERTY elle tape « & » ou « é » sans Maj, ce qui empêche un raccourci « ⌘1 » ordinaire.
    var keyCode: UInt16 { self == .time ? 18 : 19 }
}

/// Le module montré dans la fenêtre Maxwell. Partagé pour que le menu et les raccourcis l'ouvrent au bon endroit.
@MainActor
final class MainNavigation: ObservableObject {
    @Published var module: Module = .tasks
}

/// La fenêtre Maxwell : une barre d'onglets en haut, le module choisi en dessous.
struct MaxwellView: View {
    @EnvironmentObject private var main: MainNavigation
    /// Pour les captures : un Récap ou des Tâches déjà dans un état précis (survol, détail ouvert…).
    var recap = RecapView()
    var tasks = TasksView()

    var body: some View {
        VStack(spacing: 0) {
            ModuleBar()
            Group {
                switch main.module {
                case .time: recap
                case .tasks: tasks
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // La barre des modules monte sous les boutons de la fenêtre, à leur hauteur.
        .ignoresSafeArea(.container, edges: .top)
        .background(Console.background)
        .foregroundStyle(Console.text)
        .environment(\.colorScheme, .dark)
        .tint(Console.accent)
        .frame(minWidth: 720, minHeight: 520)
    }
}

/// La barre du haut : la place des boutons de la fenêtre, puis un onglet par module.
private struct ModuleBar: View {
    @EnvironmentObject private var main: MainNavigation

    var body: some View {
        HStack(spacing: 4) {
            // Les trois boutons de la fenêtre sont dessinés ici par macOS.
            Color.clear.frame(width: 76)
            ForEach(Module.allCases) { module in
                tab(module)
            }
            Spacer()
            Text("MAXWELL")
                .font(Console.mono(10, weight: .medium))
                .tracking(2)
                .foregroundStyle(Console.muted)
                .padding(.trailing, 14)
        }
        .frame(height: 40)
        .background(Console.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(Console.line).frame(height: 1) }
    }

    private func tab(_ module: Module) -> some View {
        let selected = main.module == module
        return Button { main.module = module } label: {
            HStack(spacing: 7) {
                Image(systemName: module.symbol).font(.system(size: 11))
                Text(module.rawValue).font(.system(size: 12, weight: .medium))
                Text("⌘\(String(module.key.character))")
                    .font(Console.mono(10))
                    .foregroundStyle(Console.muted)
            }
            .foregroundStyle(selected ? Console.text : Console.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Console.field : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
