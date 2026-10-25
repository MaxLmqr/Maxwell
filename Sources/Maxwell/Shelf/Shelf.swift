import Foundation

/// Un élément posé sur l'Étagère : une simple référence vers un fichier ou un dossier, qui reste à sa place.
struct ShelfItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    /// Taille en octets, pour les fichiers seulement : mesurer un dossier serait trop long.
    let byteCount: Int64

    var id: URL { url }

    /// « 1,2 Mo » pour un fichier, « Dossier » pour un dossier.
    var detail: String {
        isDirectory ? "Dossier" : ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    init(url: URL) {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .localizedNameKey])
        self.url = url
        name = values?.localizedName ?? url.lastPathComponent
        isDirectory = values?.isDirectory ?? false
        byteCount = Int64(values?.fileSize ?? 0)
    }
}

/// Le contenu de l'Étagère. Il n'y en a qu'une, et elle ne survit pas au redémarrage de l'app.
@MainActor
final class Shelf: ObservableObject {
    /// Dans l'ordre du dépôt : le dernier posé est sur le dessus de la pile.
    @Published private(set) var items: [ShelfItem] = [] {
        didSet { if items.isEmpty { isExpanded = false } }
    }
    /// Pile repliée, ou liste dépliée pour prendre un seul fichier.
    @Published var isExpanded = false

    var isEmpty: Bool { items.isEmpty }

    /// Ajoute des fichiers ; ceux déjà présents ne sont pas dupliqués.
    func add(_ urls: [URL]) {
        let known = Set(items.map(\.url))
        let new = urls.map(\.standardizedFileURL).filter { !known.contains($0) }
        items.append(contentsOf: uniqued(new).map(ShelfItem.init))
    }

    func remove(_ urls: some Sequence<URL>) {
        let gone = Set(urls.map(\.standardizedFileURL))
        items.removeAll { gone.contains($0.url) }
    }

    func clear() {
        items = []
    }

    /// Retire les fichiers supprimés ou déplacés depuis qu'ils ont été posés.
    func removeMissing() {
        let missing = items.filter { !FileManager.default.fileExists(atPath: $0.url.path) }
        if !missing.isEmpty { remove(missing.map(\.url)) }
    }

    /// « Facture.pdf » pour un seul élément, « 3 éléments » sinon.
    var title: String {
        items.count == 1 ? items[0].name : "\(items.count) éléments"
    }

    /// La taille totale s'il n'y a que des fichiers, sinon le décompte des dossiers et des fichiers.
    var subtitle: String {
        let folders = items.filter(\.isDirectory).count
        let files = items.count - folders
        if folders == 0 {
            return ByteCountFormatter.string(fromByteCount: items.reduce(0) { $0 + $1.byteCount }, countStyle: .file)
        }
        var parts = ["\(folders) dossier\(folders > 1 ? "s" : "")"]
        if files > 0 { parts.append("\(files) fichier\(files > 1 ? "s" : "")") }
        return parts.joined(separator: " · ")
    }

    private func uniqued(_ urls: [URL]) -> [URL] {
        var seen: Set<URL> = []
        return urls.filter { seen.insert($0).inserted }
    }
}
