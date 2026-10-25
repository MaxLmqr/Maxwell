import AppKit
import os

/// Ce que le moniteur lit du système. Remplaçable dans les tests, où on ne peut pas glisser de vrais fichiers.
protocol PointerState {
    var mouseLocation: NSPoint { get }
    var isLeftButtonDown: Bool { get }
    /// Compteur du presse-papiers de glisser-déposer : il change quand un glisser commence.
    var dragChangeCount: Int { get }
    var dragTypes: [NSPasteboard.PasteboardType] { get }
}

struct SystemPointerState: PointerState {
    var mouseLocation: NSPoint { NSEvent.mouseLocation }
    var isLeftButtonDown: Bool { NSEvent.pressedMouseButtons & 1 != 0 }
    var dragChangeCount: Int { NSPasteboard(name: .drag).changeCount }
    var dragTypes: [NSPasteboard.PasteboardType] { NSPasteboard(name: .drag).types ?? [] }
}

/// Repère une Secousse pendant qu'on fait glisser des fichiers, depuis n'importe quelle app.
///
/// Chaque clic démarre un relevé de la souris à 60 Hz qui s'arrête au relâchement du bouton.
/// Les événements de glisser du système, quand ils arrivent, ajoutent des positions entre deux relevés.
/// Rien ne tourne entre deux clics.
@MainActor
final class DragShakeMonitor {
    var onShake: ((NSPoint) -> Void)?
    /// Appelé quand le bouton est relâché après un glisser de fichiers, avec ou sans Secousse.
    var onFileDragEnded: (() -> Void)?

    private enum Drag {
        case none
        case files
        case other
    }

    static let fileTypes: Set<NSPasteboard.PasteboardType> = [
        .fileURL, NSPasteboard.PasteboardType("NSFilenamesPboardType"),
    ]

    private let pointer: PointerState
    private let pollsAutomatically: Bool
    private var detector = ShakeDetector()
    private var monitors: [Any] = []
    private var timer: Timer?
    private var baseline = 0
    private var drag = Drag.none
    private var hasShaken = false
    /// Pour le prototype : d'où viennent les positions pendant un glisser de fichiers.
    private var eventSamples = 0
    private var polledSamples = 0
    private let log = Logger(subsystem: "com.max.Maxwell", category: "Etagere")

    /// `pollsAutomatically: false` laisse les tests appeler `poll` eux-mêmes.
    init(pointer: PointerState = SystemPointerState(), pollsAutomatically: Bool = true) {
        self.pointer = pointer
        self.pollsAutomatically = pollsAutomatically
    }

    func start() {
        guard monitors.isEmpty else { return }
        watch(.leftMouseDown) { [weak self] _ in self?.pressBegan() }
        watch(.leftMouseDragged) { [weak self] event in self?.dragged(at: event.timestamp) }
    }

    /// Arrête toute écoute de la souris.
    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        timer?.invalidate()
        timer = nil
        drag = .none
    }

    /// Écoute un type d'événement dans les autres apps comme dans Maxwell.
    private func watch(_ mask: NSEvent.EventTypeMask, _ handler: @escaping @MainActor (NSEvent) -> Void) {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated { handler(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated { handler(event) }
            return event
        }) {
            monitors.append(local)
        }
    }

    func pressBegan() {
        baseline = pointer.dragChangeCount
        drag = .none
        hasShaken = false
        detector.reset()
        eventSamples = 0
        polledSamples = 0
        if pollsAutomatically && timer == nil {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll(at: ProcessInfo.processInfo.systemUptime) }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    /// Relevé périodique tant que le bouton reste enfoncé.
    func poll(at time: TimeInterval) {
        guard pointer.isLeftButtonDown else {
            pressEnded()
            return
        }
        if drag == .files { polledSamples += 1 }
        sample(at: time)
    }

    func dragged(at time: TimeInterval) {
        if drag == .files { eventSamples += 1 }
        sample(at: time)
    }

    private func sample(at time: TimeInterval) {
        if drag == .none {
            guard pointer.dragChangeCount != baseline else { return }
            let types = pointer.dragTypes
            let list = types.map(\.rawValue).joined(separator: ", ")
            if types.contains(where: Self.fileTypes.contains) {
                drag = .files
                log.notice("Glisser de fichiers commencé (types : \(list, privacy: .public))")
            } else {
                drag = .other
                log.notice("Glisser sans fichier ignoré (types : \(list, privacy: .public))")
            }
        }
        guard drag == .files, !hasShaken else { return }

        let location = pointer.mouseLocation
        if detector.add(x: location.x, y: location.y, at: time) {
            hasShaken = true
            log.notice("Secousse reconnue (\(self.eventSamples) positions par événements, \(self.polledSamples) par relevé)")
            onShake?(location)
        }
    }

    private func pressEnded() {
        timer?.invalidate()
        timer = nil
        let wasFileDrag = drag == .files
        if wasFileDrag {
            log.notice("Glisser de fichiers terminé : \(self.eventSamples) positions par événements, \(self.polledSamples) par relevé, secousse \(self.hasShaken ? "reconnue" : "non reconnue", privacy: .public)")
        }
        drag = .none
        if wasFileDrag { onFileDragEnded?() }
    }
}
