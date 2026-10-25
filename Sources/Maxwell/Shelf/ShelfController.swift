import AppKit
import Combine
import SwiftUI

/// Fenêtre sans bordure qui flotte au-dessus des autres, sur tous les bureaux et en plein écran,
/// sans jamais prendre le focus à l'app en cours.
final class ShelfPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        // Le verre dessine sa propre ombre.
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Vue hôte qui réagit dès le premier clic, sans attendre que Maxwell passe au premier plan.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// L'Étagère au complet : la Secousse qui l'ouvre, et la fenêtre qui la montre, accrochée au bord droit de l'écran.
@MainActor
final class ShelfController: ObservableObject {
    let shelf = Shelf()
    /// Réglage du menu : une Secousse ouvre l'Étagère. Désactivé, Maxwell n'écoute plus la souris.
    @Published var opensOnShake: Bool {
        didSet {
            defaults.set(opensOnShake, forKey: Self.opensOnShakeKey)
            updateMonitor()
        }
    }
    /// Vrai pendant qu'on fait glisser des fichiers hors de l'Étagère : une Secousse ne doit pas la déplacer.
    private(set) var isDraggingOut = false

    private static let opensOnShakeKey = "shelfOpensOnShake"
    private let defaults: UserDefaults
    private let monitor = DragShakeMonitor()
    private var isStarted = false
    /// Créée à la première apparition seulement.
    private lazy var panel = ShelfPanel()
    private var pruneTimer: Timer?
    private var changes: AnyCancellable?
    /// Incrémenté à chaque apparition : une disparition en cours ne doit pas cacher l'Étagère rouverte entre-temps.
    private var generation = 0
    /// Marge transparente autour de la carte : l'ombre du verre et l'animation y tiennent,
    /// et un fichier lâché contre le bord de l'écran y est reçu.
    private let margin: CGFloat = 20
    /// Écart entre la carte et les bords de l'écran.
    private let edgeGap: CGFloat = 12

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        opensOnShake = defaults.object(forKey: Self.opensOnShakeKey) as? Bool ?? true
        changes = shelf.objectWillChange.sink { [weak self] _ in
            // La notification précède le changement : on lit les nouvelles valeurs au tour suivant.
            DispatchQueue.main.async { self?.fitToContent() }
        }
        monitor.onShake = { [weak self] point in self?.shaken(at: point) }
        monitor.onFileDragEnded = { [weak self] in self?.fileDragEnded() }
    }

    /// Commence à écouter la Secousse, si le réglage le permet.
    func start() {
        isStarted = true
        updateMonitor()
    }

    var isVisible: Bool { panel.isVisible }

    /// Ouvre l'Étagère sans secouer, depuis le menu : au bord droit de l'écran du curseur, à mi-hauteur.
    func openFromMenu() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        show(at: NSPoint(x: mouse.x, y: screen?.visibleFrame.midY ?? mouse.y))
    }

    private func updateMonitor() {
        if isStarted && opensOnShake { monitor.start() } else { monitor.stop() }
    }

    private func shaken(at point: NSPoint) {
        // Secouer en reprenant des fichiers de l'Étagère ne doit pas la déplacer.
        guard !isDraggingOut else { return }
        // Un léger retour sur les trackpads Force Touch confirme la Secousse.
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        show(at: point)
    }

    /// Fait apparaître l'Étagère au bord droit de l'écran, à la hauteur du curseur, ou l'y ramène.
    func show(at point: NSPoint) {
        generation += 1
        let frame = dockedFrame(at: point)
        if panel.isVisible && panel.alphaValue > 0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().setFrame(frame, display: true)
            }
            return
        }
        let view = ShelfView(shelf: shelf,
                             onClose: { [weak self] in self?.close() },
                             onDragOutBegan: { [weak self] in self?.isDraggingOut = true },
                             onDragOutEnded: { [weak self] in self?.dragOutEnded() },
                             margin: margin)
        panel.contentView = FirstClickHostingView(rootView: view)
        panel.setFrame(frame, display: false)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        startPruning()
    }

    /// Vide l'Étagère et la fait disparaître.
    func close() {
        shelf.clear()
        hide()
    }

    /// À la fin d'un glisser de fichiers : une Étagère restée vide disparaît.
    /// Le léger délai laisse le temps au dépôt sur l'Étagère d'arriver.
    func fileDragEnded() {
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, self.generation == current, self.panel.isVisible, self.shelf.isEmpty else { return }
            self.hide()
        }
    }

    /// Après un dépôt ailleurs : les fichiers déplacés quittent l'Étagère, qui se ferme si elle est vide.
    /// Le Finder termine parfois un déplacement juste après le dépôt, d'où les vérifications espacées.
    private func dragOutEnded() {
        isDraggingOut = false
        for delay in [0.0, 0.5, 1.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.removeMissingFiles()
            }
        }
    }

    private func removeMissingFiles() {
        guard panel.isVisible, !shelf.isEmpty else { return }
        shelf.removeMissing()
        if shelf.isEmpty { hide() }
    }

    private func hide() {
        pruneTimer?.invalidate()
        pruneTimer = nil
        let current = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                self.panel.orderOut(nil)
                self.panel.contentView = nil
            }
        })
    }

    /// Retire régulièrement les fichiers supprimés ou déplacés ailleurs que par l'Étagère.
    private func startPruning() {
        pruneTimer?.invalidate()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.removeMissingFiles() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pruneTimer = timer
    }

    // MARK: - Position et taille

    private func panelSize() -> NSSize {
        let card = ShelfLayout.cardSize(itemCount: shelf.items.count, expanded: shelf.isExpanded)
        return NSSize(width: card.width + 2 * margin, height: card.height + 2 * margin)
    }

    /// Cadre accroché au bord droit de l'écran du curseur, la carte centrée sur sa hauteur.
    private func dockedFrame(at point: NSPoint) -> NSRect {
        let size = panelSize()
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return NSRect(origin: point, size: size) }
        let frame = NSRect(x: visible.maxX - edgeGap - size.width + margin,
                           y: point.y - size.height / 2,
                           width: size.width, height: size.height)
        return keptOnScreen(frame, within: visible)
    }

    /// Adapte la fenêtre à la carte quand elle se déplie ou se replie, en gardant le coin haut droit en place.
    private func fitToContent() {
        guard panel.isVisible else { return }
        let size = panelSize()
        let current = panel.frame
        guard size != current.size else { return }
        var frame = NSRect(x: current.maxX - size.width, y: current.maxY - size.height,
                           width: size.width, height: size.height)
        if let visible = panel.screen?.visibleFrame { frame = keptOnScreen(frame, within: visible) }

        if size.width < current.width || size.height < current.height {
            // La carte rétrécit en s'animant : on attend qu'elle ait fini avant de réduire la fenêtre.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                guard let self, self.panelSize() == size else { return }
                self.panel.setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    /// Garde la carte entière à l'écran, à `edgeGap` des bords haut et bas.
    private func keptOnScreen(_ frame: NSRect, within visible: NSRect) -> NSRect {
        var frame = frame
        let lowest = visible.minY + edgeGap - margin
        let highest = visible.maxY - edgeGap + margin - frame.height
        frame.origin.y = min(max(frame.minY, lowest), highest)
        return frame
    }
}
