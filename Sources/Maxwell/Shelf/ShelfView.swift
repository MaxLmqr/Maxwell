import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Dimensions de la carte de l'Étagère, repliée en pile ou dépliée en liste.
enum ShelfLayout {
    static let collapsed = CGSize(width: 196, height: 196)
    static let expandedWidth: CGFloat = 280
    static let headerHeight: CGFloat = 44
    static let rowHeight: CGFloat = 40
    /// Au-delà, la liste défile.
    static let visibleRows = 6
    static let footerHeight: CGFloat = 60
    static let cornerRadius: CGFloat = 28
    /// Taille des aperçus de la pile.
    static let pileThumbnail: CGFloat = 76

    static func cardSize(itemCount: Int, expanded: Bool) -> CGSize {
        guard expanded, itemCount > 0 else { return collapsed }
        let rows = CGFloat(min(itemCount, visibleRows))
        return CGSize(width: expandedWidth, height: headerHeight + rows * rowHeight + 12 + footerHeight)
    }
}

/// La carte flottante de l'Étagère : une zone de dépôt tant qu'elle est vide, une pile de fichiers ensuite,
/// qu'on peut déplier en liste pour n'en prendre qu'un.
struct ShelfView: View {
    @ObservedObject var shelf: Shelf
    var onClose: () -> Void
    var onDragOutBegan: () -> Void = {}
    var onDragOutEnded: () -> Void = {}
    /// Pour les captures : un fond plein remplace le verre, que la capture hors écran ne sait pas dessiner.
    var solidBackground = false
    /// Pour les captures : simule des fichiers glissés au-dessus de l'Étagère.
    var previewTargeted = false
    /// Marge transparente autour de la carte, réceptive aux dépôts elle aussi.
    var margin: CGFloat = 0

    @State private var isTargeted = false
    @State private var appeared = false
    @State private var hoveredRow: URL?
    @State private var pileHovered = false
    /// Courte confirmation affichée en bas de la carte, comme « Copié ».
    @State private var toast: String?

    var body: some View {
        ShelfDropZone(shelf: shelf, isTargeted: $isTargeted) {
            card
                .padding(margin)
                // Accrochée en haut à droite : en se dépliant, la carte s'agrandit vers la gauche et vers le bas.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }

    @ViewBuilder private var card: some View {
        let targeted = isTargeted || previewTargeted
        let expanded = shelf.isExpanded && !shelf.isEmpty
        let size = ShelfLayout.cardSize(itemCount: shelf.items.count, expanded: expanded)

        VStack(spacing: 0) {
            header(expanded: expanded)
            if shelf.isEmpty {
                DropHint(targeted: targeted)
                    .padding([.horizontal, .bottom], 14)
            } else if expanded {
                list
                footer
            } else {
                pile
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .bottom) {
            if let toast {
                Label(toast, systemImage: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Theme.accent))
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .modifier(ShelfCardBackground(solid: solidBackground))
        .overlay {
            RoundedRectangle(cornerRadius: ShelfLayout.cornerRadius, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: 2)
                .opacity(targeted && !shelf.isEmpty ? 1 : 0)
        }
        .scaleEffect(targeted ? 1.03 : 1)
        // L'Étagère glisse depuis le bord de l'écran.
        .offset(x: appeared ? 0 : 60)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(duration: 0.35, bounce: 0.2), value: appeared)
        .animation(.easeOut(duration: 0.15), value: targeted)
        .animation(.spring(duration: 0.3, bounce: 0.15), value: expanded)
        .animation(.spring(duration: 0.3, bounce: 0.2), value: shelf.items)
        .onAppear { appeared = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Étagère")
    }

    // MARK: - Parties

    private func header(expanded: Bool) -> some View {
        HStack(spacing: 6) {
            ShelfIconButton(symbol: "xmark", help: "Fermer l'Étagère", action: onClose)
            Spacer(minLength: 0)
            if expanded {
                Text(shelf.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            if !shelf.isEmpty {
                ShelfIconButton(symbol: expanded ? "rectangle.stack" : "list.bullet",
                                help: expanded ? "Revenir à la pile" : "Voir chaque fichier") {
                    shelf.isExpanded.toggle()
                }
                actionsMenu
            }
        }
        .padding(.horizontal, 12)
        .frame(height: ShelfLayout.headerHeight)
    }

    private var actionsMenu: some View {
        let urls = shelf.items.map(\.url)
        return Menu {
            Button { ShelfActions.reveal(urls) } label: { Label("Afficher dans le Finder", systemImage: "folder") }
            Button { copy(urls) } label: { Label("Copier", systemImage: "doc.on.doc") }
            ShareLink(items: urls) { Label("Partager…", systemImage: "square.and.arrow.up") }
            Divider()
            Button(role: .destructive, action: onClose) { Label("Vider l'Étagère", systemImage: "xmark.circle") }
        } label: {
            ShelfIconLabel(symbol: "ellipsis")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Actions")
    }

    private var pile: some View {
        VStack(spacing: 0) {
            FilePile(items: shelf.items)
                .frame(height: 84)
                .scaleEffect(pileHovered ? 1.05 : 1)
                .animation(.spring(duration: 0.25, bounce: 0.3), value: pileHovered)
                .overlay {
                    FileDragSource(urls: shelf.items.map(\.url),
                                   onClick: { shelf.isExpanded = true },
                                   onHover: { pileHovered = $0 },
                                   menu: shelfMenu,
                                   onDragBegan: onDragOutBegan,
                                   onDragEnded: { _ in onDragOutEnded() })
                }
                .help("Glisse pour déposer les fichiers ailleurs, clique pour les voir un par un")
            VStack(spacing: 2) {
                Text(shelf.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(shelf.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .opacity(toast == nil ? 1 : 0)
        }
        .frame(maxHeight: .infinity)
        .padding(.bottom, 14)
    }

    private var list: some View {
        let rows = min(shelf.items.count, ShelfLayout.visibleRows)
        return ScrollView {
            VStack(spacing: 0) {
                ForEach(shelf.items.reversed()) { item in
                    ShelfRow(item: item, isHovered: hoveredRow == item.url)
                        .overlay {
                            FileDragSource(urls: [item.url],
                                           onDoubleClick: { ShelfActions.open(item.url) },
                                           onHover: { inside in
                                               if inside { hoveredRow = item.url } else if hoveredRow == item.url { hoveredRow = nil }
                                           },
                                           menu: menu(for: item),
                                           onDragBegan: onDragOutBegan,
                                           onDragEnded: { _ in onDragOutEnded() })
                        }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
        }
        .scrollIndicators(shelf.items.count > ShelfLayout.visibleRows ? .automatic : .never)
        .frame(height: CGFloat(rows) * ShelfLayout.rowHeight + 12)
    }

    /// Poignée pour tout faire glisser d'un coup depuis la liste.
    private var footer: some View {
        HStack(spacing: 10) {
            MiniPile(items: shelf.items)
            Text(shelf.items.count == 1 ? "Glisser le fichier" : "Glisser les \(shelf.items.count) éléments")
                .font(.system(size: 12, weight: .medium))
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.forward")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay {
            FileDragSource(urls: shelf.items.map(\.url), menu: shelfMenu,
                           onDragBegan: onDragOutBegan, onDragEnded: { _ in onDragOutEnded() })
        }
        .padding(10)
        .frame(height: ShelfLayout.footerHeight)
    }

    // MARK: - Actions

    private func copy(_ urls: [URL]) {
        ShelfActions.copy(urls)
        showToast(urls.count == 1 ? "Copié" : "\(urls.count) éléments copiés")
    }

    private func showToast(_ text: String) {
        withAnimation(.spring(duration: 0.3, bounce: 0.2)) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard toast == text else { return }
            withAnimation(.easeIn(duration: 0.2)) { toast = nil }
        }
    }

    private var shelfMenu: [ContextAction] {
        let urls = shelf.items.map(\.url)
        return [
            .item("Afficher dans le Finder") { ShelfActions.reveal(urls) },
            .item("Copier") { copy(urls) },
            .share(urls),
            .separator,
            .item("Vider l'Étagère", onClose),
        ]
    }

    private func menu(for item: ShelfItem) -> [ContextAction] {
        [
            .item("Ouvrir") { ShelfActions.open(item.url) },
            .item("Afficher dans le Finder") { ShelfActions.reveal([item.url]) },
            .item("Copier") { copy([item.url]) },
            .share([item.url]),
            .separator,
            .item("Retirer de l'Étagère") { [shelf] in shelf.remove([item.url]) },
        ]
    }
}

/// Reçoit les fichiers déposés, sur la carte comme sur la marge qui la sépare du bord de l'écran.
struct ShelfDropZone<Content: View>: View {
    let shelf: Shelf
    @Binding var isTargeted: Bool
    @ViewBuilder var content: Content

    var body: some View {
        content
            // Une teinte presque invisible rend toute la fenêtre réceptive, marge comprise.
            .background(Color.black.opacity(0.001))
            .onDrop(of: [.fileURL], isTargeted: $isTargeted, perform: receive)
    }

    /// Les fichiers arrivent un par un, en arrière-plan.
    private func receive(_ providers: [NSItemProvider]) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        for provider in files {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in shelf.add([url]) }
            }
        }
        return !files.isEmpty
    }
}

private struct ShelfCardBackground: ViewModifier {
    let solid: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: ShelfLayout.cornerRadius, style: .continuous)
        if solid {
            content
                .background(shape.fill(Color(nsColor: .windowBackgroundColor)))
                .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        } else {
            content.glassEffect(.regular, in: shape)
        }
    }
}

/// Pastille ronde des boutons de la carte.
private struct ShelfIconLabel: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color.primary.opacity(0.08)))
            .contentShape(Circle())
    }
}

private struct ShelfIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { ShelfIconLabel(symbol: symbol) }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(help)
    }
}

/// Zone en pointillés qui invite à déposer ; elle passe au vert quand des fichiers la survolent.
private struct DropHint: View {
    let targeted: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        shape
            .fill(targeted ? Theme.accent.opacity(0.10) : Color.clear)
            .overlay {
                shape.strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .foregroundStyle(targeted ? Theme.accent : Color.primary.opacity(0.22))
            }
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 26, weight: .light))
                    Text("Dépose ici")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(targeted ? Theme.accent : .secondary)
            }
    }
}

/// Les trois derniers fichiers posés, en pile légèrement désordonnée, avec le nombre total en pastille.
private struct FilePile: View {
    let items: [ShelfItem]

    private static let angles: [Double] = [0, -9, 8]
    private static let offsets: [CGSize] = [.zero, CGSize(width: -16, height: 3), CGSize(width: 16, height: 4)]

    var body: some View {
        let top = Array(items.suffix(3))
        ZStack {
            ForEach(Array(top.enumerated()), id: \.element.id) { index, item in
                let depth = top.count - 1 - index
                FileThumbnail(url: item.url, size: ShelfLayout.pileThumbnail)
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                    .rotationEffect(.degrees(Self.angles[depth]))
                    .offset(Self.offsets[depth])
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topTrailing) {
            if items.count > 1 {
                Text("\(items.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Capsule().fill(Theme.accent))
                    .offset(x: 12, y: -2)
            }
        }
    }
}

/// Petite pile d'aperçus pour la poignée « Glisser les éléments ».
private struct MiniPile: View {
    let items: [ShelfItem]

    var body: some View {
        HStack(spacing: -10) {
            ForEach(items.suffix(3)) { item in
                FileThumbnail(url: item.url, size: 22)
            }
        }
    }
}

private struct ShelfRow: View {
    let item: ShelfItem
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 10) {
            FileThumbnail(url: item.url, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: ShelfLayout.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.07 : 0)))
        .contentShape(Rectangle())
    }
}
