import Foundation

/// La personne qui utilise Maxwell sur ce Mac, nommée dans ce que Maxwell écrit à Claude.
enum Owner {
    /// Son prénom, d'après le nom complet du compte macOS ; « l'utilisateur » si le compte n'en a pas.
    static let name = firstName(of: NSFullUserName()) ?? "l'utilisateur"

    static func firstName(of fullName: String) -> String? {
        fullName.split(whereSeparator: \.isWhitespace).first.map(String.init)
    }

    /// « de Max », « de l'utilisateur ».
    static var ofName: String { "de \(name)" }
}
