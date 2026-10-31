import AppKit
import CoreServices

/// Lit le Site de l'onglet actif de Chrome, par Apple Events.
/// Les lectures se font hors du fil principal : Chrome peut tarder à répondre, et la première fois
/// macOS attend que Max autorise Maxwell à « contrôler Google Chrome ».
final class ChromeTab: @unchecked Sendable {
    static let bundleID = "com.google.Chrome"

    enum Reading: Equatable {
        /// L'onglet actif est sur ce Site ; nil hors d'un site web ou en navigation privée.
        case site(String?)
        /// Chrome n'a pas répondu, ou Maxwell n'a pas le droit de le lire.
        case unavailable
    }

    /// Les lectures passent une par une par cette file, seule à toucher `permission` et `checkedAt`.
    private let queue = DispatchQueue(label: "Maxwell.ChromeTab")
    private var permission: OSStatus?
    private var checkedAt = Date.distantPast

    func activeSite() async -> Reading {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.readActiveSite()) }
        }
    }

    /// Le Site d'une adresse : son nom d'hôte, sans « www. ».
    /// nil hors du web : nouvel onglet, pages de Chrome, fichiers.
    static func site(fromURL text: String) -> String? {
        guard let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased()),
              var host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    // MARK: - Apple Events

    private func readActiveSite() -> Reading {
        let chrome = NSAppleEventDescriptor(bundleIdentifier: Self.bundleID)
        guard isAllowed(chrome) else { return .unavailable }
        let frontWindow = Self.element(code("cwin"), index: 1)
        switch get(Self.property(code("mode"), of: frontWindow), from: chrome) {
        case .site("normal"?): break
        case .unavailable: return .unavailable
        default: return .site(nil)
        }
        let url = get(Self.property(code("URL "), of: Self.property(code("acTa"), of: frontWindow)), from: chrome)
        guard case .site(let text?) = url else { return url }
        return .site(Self.site(fromURL: text))
    }

    /// La première fois, macOS demande à Max et attend sa réponse. Un refus est relu toutes les minutes,
    /// pour reprendre si Max change d'avis dans les Réglages Système.
    private func isAllowed(_ chrome: NSAppleEventDescriptor) -> Bool {
        if permission != noErr, Date().timeIntervalSince(checkedAt) > 60 {
            permission = AEDeterminePermissionToAutomateTarget(chrome.aeDesc, code("core"), code("getd"), true)
            checkedAt = Date()
        }
        return permission == noErr
    }

    /// Envoie « get <objet> » à Chrome. Le texte obtenu arrive dans `.site`, nil si l'objet n'existe pas
    /// (aucune fenêtre ouverte).
    private func get(_ object: NSAppleEventDescriptor, from chrome: NSAppleEventDescriptor) -> Reading {
        let event = NSAppleEventDescriptor(eventClass: code("core"), eventID: code("getd"), targetDescriptor: chrome,
                                           returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(object, forKeyword: code("----"))
        do {
            let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 1)
            return .site(reply.paramDescriptor(forKeyword: code("----"))?.stringValue)
        } catch {
            switch (error as NSError).code {
            case errAENoSuchObject, errAEIllegalIndex:
                return .site(nil)
            case errAEEventNotPermitted:
                permission = OSStatus(errAEEventNotPermitted)
                checkedAt = Date()
                return .unavailable
            default:
                return .unavailable
            }
        }
    }

    /// « window 1 » : un élément de Chrome, par sa position.
    private static func element(_ classCode: FourCharCode, index: Int32) -> NSAppleEventDescriptor {
        specifier(want: classCode, form: code("indx"), data: NSAppleEventDescriptor(int32: index), container: .null())
    }

    /// « active tab of window 1 » : une propriété d'un objet.
    private static func property(_ propertyCode: FourCharCode, of container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        specifier(want: code("prop"), form: code("prop"), data: NSAppleEventDescriptor(typeCode: propertyCode),
                  container: container)
    }

    private static func specifier(want: FourCharCode, form: FourCharCode, data: NSAppleEventDescriptor,
                                  container: NSAppleEventDescriptor) -> NSAppleEventDescriptor {
        let specifier = NSAppleEventDescriptor.record().coerce(toDescriptorType: code("obj "))!
        specifier.setDescriptor(NSAppleEventDescriptor(typeCode: want), forKeyword: code("want"))
        specifier.setDescriptor(NSAppleEventDescriptor(enumCode: form), forKeyword: code("form"))
        specifier.setDescriptor(data, forKeyword: code("seld"))
        specifier.setDescriptor(container, forKeyword: code("from"))
        return specifier
    }
}

/// Code à quatre lettres des Apple Events, comme « cwin » pour une fenêtre dans le dictionnaire de Chrome.
private func code(_ text: String) -> FourCharCode {
    text.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
}
