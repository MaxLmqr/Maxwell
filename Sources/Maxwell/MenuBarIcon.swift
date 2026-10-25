import AppKit

/// Monogramme M en barres, version monochrome pour la barre de menus.
/// Image « template » : macOS la teinte en noir ou en blanc selon le fond.
enum MenuBarIcon {
    static let image: NSImage = {
        let width: CGFloat = 2.4
        let bars: [(x: CGFloat, top: CGFloat)] = [(0.6, 1), (4.2, 5), (7.8, 9), (11.4, 5), (15, 1)]
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: true) { _ in
            NSColor.black.setFill()
            for bar in bars {
                let rect = NSRect(x: bar.x, y: bar.top, width: width, height: 15 - bar.top)
                NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}
