import AppKit

/// Dix semaines d'activité plausibles, pour dessiner l'interface sans toucher aux vraies données.
enum DemoData {
    private struct DemoApp {
        let bundleID: String
        let name: String
        let category: String
        let weight: Double
        /// Durée d'une session, en minutes.
        let minutes: ClosedRange<Double>
    }

    private static let work: [DemoApp] = [
        DemoApp(bundleID: "com.apple.dt.Xcode", name: "Xcode", category: "Développement", weight: 26, minutes: 8...35),
        DemoApp(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code", category: "Développement", weight: 7, minutes: 5...25),
        DemoApp(bundleID: "com.mitchellh.ghostty", name: "Ghostty", category: "Développement", weight: 10, minutes: 2...12),
        DemoApp(bundleID: "com.anthropic.claudefordesktop", name: "Claude", category: "IA", weight: 14, minutes: 3...20),
        DemoApp(bundleID: "com.google.Chrome", name: "Google Chrome", category: "Navigation", weight: 12, minutes: 2...15),
        DemoApp(bundleID: "com.tinyspeck.slackmacgap", name: "Slack", category: "Communication", weight: 10, minutes: 1...8),
        DemoApp(bundleID: "com.apple.mail", name: "Mail", category: "Communication", weight: 4, minutes: 2...10),
        DemoApp(bundleID: "com.figma.Desktop", name: "Figma", category: "Design", weight: 6, minutes: 5...30),
        DemoApp(bundleID: "com.apple.FaceTime", name: "FaceTime", category: "Réunions", weight: 2, minutes: 25...55),
        DemoApp(bundleID: "com.apple.Notes", name: "Notes", category: "Écriture et documents", weight: 4, minutes: 2...12),
        DemoApp(bundleID: "com.apple.Preview", name: "Aperçu", category: "Écriture et documents", weight: 2, minutes: 1...6),
        DemoApp(bundleID: "com.apple.finder", name: "Finder", category: "Outils", weight: 3, minutes: 1...4),
        DemoApp(bundleID: "com.raycast.macos", name: "Raycast", category: "Outils", weight: 2, minutes: 0.3...1),
        DemoApp(bundleID: "com.apple.iCal", name: "Calendrier", category: "Outils", weight: 2, minutes: 1...3),
        DemoApp(bundleID: "com.apple.systempreferences", name: "Réglages Système", category: "Système", weight: 1, minutes: 0.5...2),
    ]

    private static let leisure: [DemoApp] = [
        DemoApp(bundleID: "com.spotify.client", name: "Spotify", category: "Divertissement", weight: 6, minutes: 3...20),
        DemoApp(bundleID: "com.apple.TV", name: "TV", category: "Divertissement", weight: 3, minutes: 10...40),
        DemoApp(bundleID: "com.apple.Photos", name: "Photos", category: "Divertissement", weight: 2, minutes: 3...15),
        DemoApp(bundleID: "com.google.Chrome", name: "Google Chrome", category: "Navigation", weight: 10, minutes: 3...25),
        DemoApp(bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp", category: "Communication", weight: 6, minutes: 1...8),
        DemoApp(bundleID: "com.apple.MobileSMS", name: "Messages", category: "Communication", weight: 4, minutes: 1...6),
        DemoApp(bundleID: "com.apple.journal", name: "Journal", category: "Écriture et documents", weight: 2, minutes: 5...15),
        DemoApp(bundleID: "com.anthropic.claudefordesktop", name: "Claude", category: "IA", weight: 3, minutes: 3...15),
        DemoApp(bundleID: "com.apple.dt.Xcode", name: "Xcode", category: "Développement", weight: 3, minutes: 10...40),
    ]

    static func fill(_ db: Database, now: Date) {
        let categories = Dictionary(uniqueKeysWithValues: db.categories().map { ($0.name, $0.id) })
        for app in work + leisure {
            if let id = categories[app.category] { db.setCategory(id, for: app.bundleID, manual: false) }
        }

        var random = SplitMix64(seed: 42)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        for offset in (0..<70).reversed() {
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let weekend = calendar.isDateInWeekend(day)
            // Un jour de semaine sur dix sans travail, pour que les graphiques respirent.
            let dayOff = !weekend && random.unit() < 0.1
            var blocks: [(start: Double, end: Double, pool: [DemoApp])] = []
            if weekend || dayOff {
                blocks.append((10.5, 12.5, leisure))
                if random.unit() < 0.5 { blocks.append((15, 17, leisure)) }
            } else {
                blocks.append((9, 12.5, work))
                blocks.append((13.75, 18.5, work))
            }
            if random.unit() < 0.7 { blocks.append((21, 22.75, leisure)) }

            for block in blocks {
                var time = day.addingTimeInterval((block.start + random.range(-0.3, 0.3)) * 3600)
                let end = min(day.addingTimeInterval((block.end + random.range(-0.4, 0.4)) * 3600), now)
                while time < end {
                    let app = pick(block.pool, &random)
                    let sessionEnd = min(time.addingTimeInterval(random.range(app.minutes.lowerBound, app.minutes.upperBound) * 60), end)
                    db.insertSession(bundleID: app.bundleID, appName: app.name, start: time, end: sessionEnd)
                    time = sessionEnd.addingTimeInterval(random.range(5, 90))
                }
            }
        }
    }

    /// Un dossier et trois vrais fichiers (notes, image, facture) dans un dossier temporaire,
    /// pour dessiner l'Étagère avec de vrais aperçus. Le dernier de la liste est sur le dessus de la pile.
    static func shelfFiles() -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("maxwell-demo-etagere")
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let photos = folder.appendingPathComponent("Photos vacances", isDirectory: true)
        try? FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)

        let notes = folder.appendingPathComponent("Notes réunion.txt")
        try? """
            Réunion produit — 22 octobre

            • Valider la maquette de l'accueil
            • Relancer la facture d'octobre
            • Préparer la démo de vendredi
            """.write(to: notes, atomically: true, encoding: .utf8)

        let mockup = folder.appendingPathComponent("Maquette accueil.png")
        try? landscapePNG().write(to: mockup)

        let invoice = folder.appendingPathComponent("Facture octobre.pdf")
        writeInvoicePDF(to: invoice)

        return [photos, notes, mockup, invoice]
    }

    /// Un paysage simple : ciel, soleil et collines.
    private static func landscapePNG() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 800, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let bounds = NSRect(x: 0, y: 0, width: 1200, height: 800)
        NSGradient(starting: NSColor(srgbRed: 0.98, green: 0.80, blue: 0.62, alpha: 1),
                   ending: NSColor(srgbRed: 0.45, green: 0.68, blue: 0.92, alpha: 1))?.draw(in: bounds, angle: 90)
        NSColor(srgbRed: 1, green: 0.93, blue: 0.70, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 780, y: 420, width: 180, height: 180)).fill()
        for (height, color) in [(360.0, NSColor(srgbRed: 0.36, green: 0.72, blue: 0.58, alpha: 1)),
                                (250.0, NSColor(srgbRed: 0.11, green: 0.62, blue: 0.46, alpha: 1))] {
            let hill = NSBezierPath()
            hill.move(to: NSPoint(x: 0, y: 0))
            hill.line(to: NSPoint(x: 0, y: height))
            hill.curve(to: NSPoint(x: 1200, y: height - 60),
                       controlPoint1: NSPoint(x: 400, y: height + 160),
                       controlPoint2: NSPoint(x: 800, y: height - 200))
            hill.line(to: NSPoint(x: 1200, y: 0))
            hill.close()
            color.setFill()
            hill.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }

    /// Une facture d'une page, au format A4.
    private static func writeInvoicePDF(to url: URL) {
        var page = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let context = CGContext(url as CFURL, mediaBox: &page, nil) else { return }
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        NSColor(srgbRed: 0x1D / 255, green: 0x9E / 255, blue: 0x75 / 255, alpha: 1).setFill()
        NSRect(x: 0, y: 722, width: 595, height: 120).fill()
        let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 40, weight: .bold),
                                                     .foregroundColor: NSColor.white]
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16),
                                                    .foregroundColor: NSColor.darkGray]
        let strong: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22, weight: .semibold),
                                                      .foregroundColor: NSColor.black]
        ("Facture" as NSString).draw(at: NSPoint(x: 48, y: 760), withAttributes: title)
        ("Octobre 2026 — n° 2026-10" as NSString).draw(at: NSPoint(x: 48, y: 670), withAttributes: body)
        let lines = ["Conception de l'accueil", "Prototype interactif", "Tests utilisateurs", "Suivi de projet"]
        for (index, line) in lines.enumerated() {
            let y = 590 - CGFloat(index) * 44
            (line as NSString).draw(at: NSPoint(x: 48, y: y), withAttributes: body)
            ("\(900 + index * 350) €" as NSString).draw(at: NSPoint(x: 460, y: y), withAttributes: body)
            NSColor(white: 0.88, alpha: 1).setFill()
            NSRect(x: 48, y: y - 14, width: 499, height: 1).fill()
        }
        ("Total : 5 700 €" as NSString).draw(at: NSPoint(x: 360, y: 380), withAttributes: strong)

        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
    }

    private static func pick(_ pool: [DemoApp], _ random: inout SplitMix64) -> DemoApp {
        var target = random.unit() * pool.reduce(0) { $0 + $1.weight }
        for app in pool {
            target -= app.weight
            if target <= 0 { return app }
        }
        return pool[pool.count - 1]
    }
}

/// Générateur pseudo-aléatoire déterministe : les captures restent identiques d'une fois sur l'autre.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    mutating func range(_ low: Double, _ high: Double) -> Double { low + (high - low) * unit() }
}
