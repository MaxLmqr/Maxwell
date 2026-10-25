import AppKit
import Testing
@testable import MaxActivity

/// Souris et presse-papiers de glisser-déposer simulés.
private final class FakePointer: PointerState {
    var mouseLocation = NSPoint(x: 500, y: 400)
    var isLeftButtonDown = false
    var dragChangeCount = 7
    var dragTypes: [NSPasteboard.PasteboardType] = []

    /// Ce qu'écrit une app quand elle commence à faire glisser quelque chose.
    func beginDrag(_ types: [NSPasteboard.PasteboardType]) {
        dragChangeCount += 1
        dragTypes = types
    }
}

@MainActor
@Suite("Secousse pendant un glisser")
struct DragShakeMonitorTests {
    private let pointer = FakePointer()
    private let monitor: DragShakeMonitor
    private var shakes: [NSPoint] { recorded.points }
    private let recorded = Recorder()

    private final class Recorder {
        var points: [NSPoint] = []
        var fileDragsEnded = 0
    }

    init() {
        monitor = DragShakeMonitor(pointer: pointer, pollsAutomatically: false)
        monitor.onShake = { [recorded] in recorded.points.append($0) }
        monitor.onFileDragEnded = { [recorded] in recorded.fileDragsEnded += 1 }
    }

    /// Bouton enfoncé, puis relevés à 60 Hz pendant `duration` secondes en suivant `x`.
    private func press(for duration: Double, startingDrag types: [NSPasteboard.PasteboardType]?,
                       x: (Double) -> Double) {
        pointer.isLeftButtonDown = true
        monitor.pressBegan()
        if let types { pointer.beginDrag(types) }
        for step in 0...Int(duration * 60) {
            let time = 100 + Double(step) / 60
            pointer.mouseLocation.x = x(Double(step) / 60)
            monitor.poll(at: time)
        }
        pointer.isLeftButtonDown = false
        monitor.poll(at: 100 + duration + 0.1)
    }

    private let shake: (Double) -> Double = { time in 500 + 50 * sin(2 * .pi * 4 * time) }

    @Test func shakingWhileDraggingFilesShowsTheShelf() {
        press(for: 0.6, startingDrag: [.fileURL], x: shake)
        #expect(shakes.count == 1)
    }

    @Test func legacyFinderFileTypeCountsAsFiles() {
        press(for: 0.6, startingDrag: [NSPasteboard.PasteboardType("NSFilenamesPboardType")], x: shake)
        #expect(shakes.count == 1)
    }

    @Test func shakingWhileDraggingTextDoesNothing() {
        press(for: 0.6, startingDrag: [.string], x: shake)
        #expect(shakes.isEmpty)
    }

    @Test func shakingWithoutDraggingDoesNothing() {
        // Bouton enfoncé sans glisser : sélection de texte, déplacement de fenêtre…
        press(for: 0.6, startingDrag: nil, x: shake)
        #expect(shakes.isEmpty)
    }

    @Test func eachDragCanShowTheShelfAgain() {
        press(for: 0.6, startingDrag: [.fileURL], x: shake)
        press(for: 0.6, startingDrag: [.fileURL], x: shake)
        #expect(shakes.count == 2)
    }

    @Test func aSecondShakeDuringTheSameDragIsIgnored() {
        press(for: 1.5, startingDrag: [.fileURL], x: shake)
        #expect(shakes.count == 1)
    }
}

extension DragShakeMonitorTests {
    @Test func theEndOfAFileDragIsReportedOnce() {
        // L'Étagère s'en sert pour disparaître si rien n'y a été déposé.
        press(for: 0.3, startingDrag: [.fileURL]) { _ in 500 }
        #expect(recorded.fileDragsEnded == 1)
    }

    @Test func theEndOfAnotherDragIsNotReported() {
        press(for: 0.3, startingDrag: [.string]) { _ in 500 }
        press(for: 0.3, startingDrag: nil) { _ in 500 }
        #expect(recorded.fileDragsEnded == 0)
    }
}
