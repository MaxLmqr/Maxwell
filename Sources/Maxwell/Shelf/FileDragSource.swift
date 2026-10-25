import AppKit
import SwiftUI

/// Une entrée du menu contextuel d'une surface de glisser.
enum ContextAction {
    case item(String, () -> Void)
    /// Le sous-menu Partager standard de macOS : AirDrop, Mail, Messages…
    case share([URL])
    case separator
}

/// Surface transparente, posée sur une vue SwiftUI, qui fait glisser des fichiers vers une autre app.
/// La destination décide comme pour un glisser depuis le Finder : les fichiers sont déplacés sur le même disque,
/// copiés vers un autre disque ou avec ⌥.
///
/// SwiftUI ne dit pas ce que la destination a fait des fichiers ; AppKit, si.
struct FileDragSource: NSViewRepresentable {
    let urls: [URL]
    var onClick: (() -> Void)? = nil
    var onDoubleClick: (() -> Void)? = nil
    var onHover: ((Bool) -> Void)? = nil
    var menu: [ContextAction] = []
    var onDragBegan: (() -> Void)? = nil
    var onDragEnded: ((NSDragOperation) -> Void)? = nil

    func makeNSView(context: Context) -> FileDragSourceView { FileDragSourceView() }

    func updateNSView(_ view: FileDragSourceView, context: Context) {
        view.urls = urls
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
        view.onHover = onHover
        view.actions = menu
        view.onDragBegan = onDragBegan
        view.onDragEnded = onDragEnded
    }
}

final class FileDragSourceView: NSView, NSDraggingSource {
    var urls: [URL] = []
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var actions: [ContextAction] = []
    var onDragBegan: (() -> Void)?
    var onDragEnded: ((NSDragOperation) -> Void)?

    private var pressEvent: NSEvent?
    private var trackingArea: NSTrackingArea?

    /// L'Étagère flotte devant une autre app : le premier clic doit déjà compter.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Glisser ici déplace les fichiers, pas la fenêtre.
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseDown(with event: NSEvent) {
        pressEvent = event
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressEvent = nil }
        guard pressEvent != nil else { return }
        if event.clickCount == 2 { onDoubleClick?() } else { onClick?() }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let press = pressEvent, !urls.isEmpty else { return }
        let start = press.locationInWindow
        let now = event.locationInWindow
        guard hypot(now.x - start.x, now.y - start.y) >= 4 else { return }
        pressEvent = nil

        let origin = convert(start, from: nil)
        let items = urls.enumerated().map { index, url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let side: CGFloat = 56
            let shift = CGFloat(min(index, 3)) * 5
            item.setDraggingFrame(NSRect(x: origin.x - side / 2 + shift, y: origin.y - side / 2 - shift,
                                         width: side, height: side),
                                  contents: Thumbnails.shared.best(url, size: 76))
            return item
        }
        let session = beginDraggingSession(with: items, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
        onDragBegan?()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard !actions.isEmpty else { return nil }
        let menu = NSMenu()
        for action in actions {
            switch action {
            case let .item(title, handler):
                menu.addItem(ClosureMenuItem(title: title, handler: handler))
            case let .share(urls):
                menu.addItem(NSSharingServicePicker(items: urls).standardShareMenuItem)
            case .separator:
                menu.addItem(.separator())
            }
        }
        return menu
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Hors de Maxwell, la destination choisit comme pour un glisser depuis le Finder,
        // corbeille comprise. Reposer les fichiers sur l'Étagère elle-même n'a pas de sens.
        context == .outsideApplication ? [.copy, .move, .generic, .delete] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onDragEnded?(operation)
    }
}

/// Élément de menu qui exécute une closure.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) n'est pas utilisé") }

    @objc private func fire() { handler() }
}
