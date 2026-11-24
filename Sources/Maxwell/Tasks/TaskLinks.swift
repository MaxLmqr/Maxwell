import Foundation

/// Les liens d'une Tâche : repérés dans son Titre et sa Note, montrés en court, ouverts d'un clic.
enum TaskLinks {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// Les adresses web trouvées dans le texte, dans l'ordre, sans doublon.
    static func links(in text: String) -> [URL] {
        matches(in: text).map(\.url).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    /// Les liens repérés et leur place dans le texte. Seules les adresses web comptent :
    /// une adresse mail ou un numéro de téléphone restent du texte.
    static func matches(in text: String) -> [(range: Range<String.Index>, url: URL)] {
        guard let detector else { return [] }
        let all = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: all).compactMap { match in
            guard let url = match.url, let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                  let range = Range(match.range, in: text) else { return nil }
            return (range, url)
        }
    }

    /// Un nom court pour un lien : « slack », « gmail », « github »… sinon le nom du site sans « www. ».
    static func label(for url: URL) -> String {
        let host = (url.host ?? url.absoluteString).lowercased()
        let site = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let known: [(suffix: String, name: String)] = [
            ("slack.com", "slack"), ("mail.google.com", "gmail"), ("docs.google.com", "google docs"),
            ("drive.google.com", "google drive"), ("calendar.google.com", "agenda"), ("meet.google.com", "meet"),
            ("github.com", "github"), ("linear.app", "linear"), ("notion.so", "notion"), ("notion.site", "notion"),
            ("figma.com", "figma"), ("claude.ai", "claude"),
        ]
        return known.first { site == $0.suffix || site.hasSuffix("." + $0.suffix) }?.name ?? site
    }

    /// Un morceau de texte : du texte simple, ou un lien.
    enum Segment: Hashable {
        case text(String)
        case link(URL)
    }

    /// Le texte découpé en morceaux, pour dessiner chaque lien comme un vrai lien (curseur en main, clic).
    static func segments(of text: String) -> [Segment] {
        var result: [Segment] = []
        var cursor = text.startIndex
        for (range, url) in matches(in: text) {
            if cursor < range.lowerBound { result.append(.text(String(text[cursor..<range.lowerBound]))) }
            result.append(.link(url))
            cursor = range.upperBound
        }
        if cursor < text.endIndex { result.append(.text(String(text[cursor...]))) }
        return result
    }

    /// Le texte avec chaque lien remplacé par son nom court, suivi de « ↗ » :
    /// « Relire https://github.com/max/maxwell/pull/12 » devient « Relire github ↗ ».
    static func shortened(_ text: String) -> AttributedString {
        var result = AttributedString()
        var cursor = text.startIndex
        for (range, url) in matches(in: text) {
            result += AttributedString(text[cursor..<range.lowerBound])
            var link = AttributedString("\(label(for: url)) ↗")
            link.link = url
            result += link
            cursor = range.upperBound
        }
        result += AttributedString(text[cursor...])
        return result
    }
}

extension TaskItem {
    /// Les liens du Titre puis de la Note.
    var links: [URL] { TaskLinks.links(in: title + "\n" + note) }
}
