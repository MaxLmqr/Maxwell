import AppKit

/// Ce qu'on peut faire des fichiers de l'Étagère sans les faire glisser.
enum ShelfActions {
    static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    /// Copie les fichiers dans le presse-papiers : ⌘V dans le Finder en colle une copie.
    static func copy(_ urls: [URL], to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
    }
}
