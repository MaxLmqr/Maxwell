import AppKit
import QuickLookThumbnailing
import SwiftUI

/// Aperçus des fichiers tels que le Finder les montre (première page d'un PDF, image réduite…),
/// générés en arrière-plan par Quick Look et gardés en mémoire.
@MainActor
final class Thumbnails {
    static let shared = Thumbnails()

    private let cache = NSCache<NSString, NSImage>()

    func cached(_ url: URL, size: CGFloat) -> NSImage? {
        cache.object(forKey: key(url, size))
    }

    /// L'aperçu du fichier, ou nil si Quick Look n'en produit pas : l'icône du Finder prend alors le relais.
    func load(_ url: URL, size: CGFloat, scale: CGFloat) async -> NSImage? {
        if let image = cached(url, size: size) { return image }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                                   scale: scale, representationTypes: .all)
        // Décoré comme dans le Finder : coin de page, bordure des photos.
        request.iconMode = true
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        else { return nil }
        let image = representation.nsImage
        cache.setObject(image, forKey: key(url, size))
        return image
    }

    /// L'aperçu s'il est déjà prêt, sinon l'icône du Finder.
    func best(_ url: URL, size: CGFloat) -> NSImage {
        cached(url, size: size) ?? NSWorkspace.shared.icon(forFile: url.path)
    }

    private func key(_ url: URL, _ size: CGFloat) -> NSString {
        "\(url.path)@\(Int(size))" as NSString
    }
}

/// Aperçu d'un fichier : l'icône du Finder d'abord, remplacée par l'aperçu Quick Look dès qu'il est prêt.
struct FileThumbnail: View {
    let url: URL
    let size: CGFloat
    @Environment(\.displayScale) private var scale
    @State private var image: NSImage?

    var body: some View {
        Image(nsImage: image ?? Thumbnails.shared.best(url, size: size))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .task(id: url) {
                image = await Thumbnails.shared.load(url, size: size, scale: scale)
            }
    }
}
