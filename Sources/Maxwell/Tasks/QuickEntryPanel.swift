import AppKit
import Carbon.HIToolbox
import SwiftUI

/// La Saisie rapide : ⌃⌥Espace ouvre, par-dessus l'app en cours, un champ qui crée une Tâche.
/// Le panneau prend le clavier sans activer Maxwell : à sa fermeture, Max retrouve l'app où il était.
@MainActor
final class QuickEntryController {
    static let shortcut = "⌃⌥Espace"
    /// Ouvre la fenêtre Tâches, depuis n'importe quelle app.
    static let windowShortcut = "⌃⌥T"

    private let store: TaskStore
    private var panel: QuickEntryWindow?
    private var hotKey: HotKey?
    private var windowHotKey: HotKey?

    init(store: TaskStore) {
        self.store = store
    }

    func start() {
        hotKey = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey)) { [weak self] in
            self?.toggle()
        }
        windowHotKey = HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey)) {
            Windows.toggleTasks()
        }
    }

    func toggle() {
        if let panel, panel.isVisible { close() } else { open() }
    }

    func open() {
        let panel = panel ?? makePanel()
        self.panel = panel
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                         y: frame.minY + frame.height * 0.68))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        // Un nouveau contenu à chaque ouverture : le champ repart vide.
        panel = nil
    }

    private func makePanel() -> QuickEntryWindow {
        let view = QuickEntryView(close: { [weak self] in self?.close() })
            .environmentObject(store)
        let hosting = NSHostingView(rootView: view)
        let panel = QuickEntryWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 10),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        hosting.postsFrameChangedNotifications = true
        panel.onResignKey = { [weak self] in self?.close() }
        return panel
    }
}

/// Un panneau sans bordure qui peut tout de même recevoir le clavier.
final class QuickEntryWindow: NSPanel {
    var onResignKey: () -> Void = {}
    override var canBecomeKey: Bool { true }
    override func resignKey() {
        super.resignKey()
        onResignKey()
    }
}

private struct QuickEntryView: View {
    let close: () -> Void
    @FocusState private var focused: Bool
    @State private var created: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NewTaskField(list: nil, placeholder: "Nouvelle tâche", large: true, focus: $focused) { task, keepOpen in
                if keepOpen {
                    created = task.title
                } else {
                    close()
                }
            }
            HStack(spacing: 14) {
                if let created {
                    Label("« \(created) » ajoutée", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                } else {
                    Text("demain · avant vendredi · #projet · !")
                }
                Spacer()
                Text("↩ créer   ⇧↩ créer et continuer   esc fermer")
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .onAppear { focused = true }
        .onExitCommand(perform: close)
    }
}

/// Un raccourci clavier global, reçu même quand une autre app est au premier plan.
/// Carbon reste la seule façon de le faire sans demander l'accès à l'Accessibilité.
final class HotKey {
    private var ref: EventHotKeyRef?
    private let id: UInt32
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var installed = false

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        id = Self.nextID
        Self.nextID += 1
        Self.handlers[id] = handler
        Self.installHandler()
        let hotKeyID = EventHotKeyID(signature: OSType(0x4D58_574C), id: id) // « MXWL »
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { NSLog("Maxwell : raccourci global indisponible (\(status))") }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Self.handlers[id] = nil
    }

    private static func installHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async { HotKey.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

/// Le panneau de Saisie rapide tel qu'il apparaît, pour les captures.
struct QuickEntryPreview: View {
    var body: some View {
        QuickEntryView(close: {}).padding(28)
    }
}
