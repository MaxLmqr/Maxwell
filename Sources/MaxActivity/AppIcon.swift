import AppKit

@MainActor
enum AppIcon {
    private static var cache: [String: NSImage] = [:]

    static func image(for bundleID: String) -> NSImage {
        if let cached = cache[bundleID] { return cached }
        let image: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSWorkspace.shared.icon(for: .application)
        }
        cache[bundleID] = image
        return image
    }
}
