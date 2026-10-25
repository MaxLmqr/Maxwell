import AppKit
import Testing
@testable import Maxwell

@MainActor
@Suite("Contenu de l'Étagère")
final class ShelfTests {
    /// Dossier temporaire propre à chaque test, supprimé à la fin.
    private let folder: URL

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ShelfTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    private func file(_ name: String, bytes: Int = 10) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(count: bytes).write(to: url)
        return url
    }

    private func directory(_ name: String) throws -> URL {
        let url = folder.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func theSameFileIsNeverShelvedTwice() throws {
        let shelf = Shelf()
        let report = try file("rapport.pdf")
        shelf.add([report, report])
        shelf.add([report])
        #expect(shelf.items.count == 1)
    }

    @Test func theLastDroppedFileIsOnTopOfThePile() throws {
        let shelf = Shelf()
        let first = try file("premier.txt")
        let second = try file("second.txt")
        shelf.add([first])
        shelf.add([second])
        #expect(shelf.items.map(\.url) == [first.standardizedFileURL, second.standardizedFileURL])
    }

    @Test func filesDeletedMeanwhileLeaveTheShelf() throws {
        let shelf = Shelf()
        let kept = try file("garde.txt")
        let deleted = try file("supprime.txt")
        shelf.add([kept, deleted])
        try FileManager.default.removeItem(at: deleted)
        shelf.removeMissing()
        #expect(shelf.items.map(\.url) == [kept.standardizedFileURL])
    }

    @Test func aSingleFileIsShownByName() throws {
        let shelf = Shelf()
        shelf.add([try file("rapport.pdf")])
        #expect(shelf.title.hasPrefix("rapport"))
    }

    @Test func severalItemsAreCounted() throws {
        let shelf = Shelf()
        shelf.add([try file("a.txt"), try file("b.txt"), try directory("Photos")])
        #expect(shelf.title == "3 éléments")
    }

    @Test func filesOnlyShowTheirTotalSize() throws {
        let shelf = Shelf()
        shelf.add([try file("a.bin", bytes: 1500), try file("b.bin", bytes: 1500)])
        #expect(shelf.subtitle == ByteCountFormatter.string(fromByteCount: 3000, countStyle: .file))
    }

    @Test func foldersAreCountedInsteadOfMeasured() throws {
        let shelf = Shelf()
        shelf.add([try directory("Photos"), try file("a.txt"), try file("b.txt")])
        #expect(shelf.subtitle == "1 dossier · 2 fichiers")
    }

    @Test func closingEmptiesTheShelf() throws {
        let shelf = Shelf()
        shelf.add([try file("a.txt")])
        shelf.clear()
        #expect(shelf.isEmpty)
    }

    @Test func anEmptiedShelfFoldsBackIntoAPile() throws {
        let shelf = Shelf()
        let file = try file("a.txt")
        shelf.add([file])
        shelf.isExpanded = true
        try FileManager.default.removeItem(at: file)
        shelf.removeMissing()
        #expect(shelf.isExpanded == false)
    }

    @Test func theListGrowsWithItsFilesThenScrolls() {
        let collapsed = ShelfLayout.cardSize(itemCount: 3, expanded: false)
        let two = ShelfLayout.cardSize(itemCount: 2, expanded: true)
        let six = ShelfLayout.cardSize(itemCount: 6, expanded: true)
        let twenty = ShelfLayout.cardSize(itemCount: 20, expanded: true)
        #expect(collapsed == ShelfLayout.collapsed)
        #expect(two.height < six.height)
        #expect(six == twenty)
        #expect(six.width > collapsed.width)
    }

    @Test func anEmptyShelfIsNeverShownAsAList() {
        #expect(ShelfLayout.cardSize(itemCount: 0, expanded: true) == ShelfLayout.collapsed)
    }

    @Test func copyingPutsTheFilesOnThePasteboard() throws {
        // Un presse-papiers à part, pour ne pas écraser celui de Max pendant les tests.
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let files = [try file("a.txt"), try file("b.txt")]
        ShelfActions.copy(files, to: pasteboard)
        let copied = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL]
        #expect(copied?.map(\.standardizedFileURL) == files.map(\.standardizedFileURL))
    }
}
