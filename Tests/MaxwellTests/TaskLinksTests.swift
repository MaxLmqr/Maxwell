import Foundation
import Testing
@testable import Maxwell

@Suite("Liens des Tâches")
struct TaskLinksTests {
    @Test func linksAreFoundInTitleAndNote() {
        let task = TaskItem(id: 1, title: "Relire https://github.com/max/maxwell/pull/12",
                            note: "Fil : https://dixpourcent.slack.com/archives/C01/p123 et www.example.org",
                            createdAt: Date(), position: 1)
        #expect(task.links.map(\.host) == ["github.com", "dixpourcent.slack.com", "www.example.org"])
    }

    @Test func mailAddressesStayText() {
        #expect(TaskLinks.links(in: "Écrire à paul@example.com").isEmpty)
    }

    @Test func eachLinkAppearsOnce() {
        #expect(TaskLinks.links(in: "https://a.com https://a.com").count == 1)
    }

    @Test(arguments: [
        ("https://dixpourcent.slack.com/archives/C01/p123", "slack"),
        ("https://mail.google.com/mail/u/0/#inbox/abc", "gmail"),
        ("https://docs.google.com/document/d/1", "google docs"),
        ("https://www.lemonde.fr/article", "lemonde.fr"),
    ])
    func linksHaveAShortName(url: String, label: String) {
        #expect(TaskLinks.label(for: URL(string: url)!) == label)
    }

    @Test func aLongLinkIsShortenedButStaysClickable() {
        let text = TaskLinks.shortened("Relire https://github.com/max/maxwell/pull/12 ce soir")
        #expect(String(text.characters) == "Relire github ↗ ce soir")
        #expect(text.runs.compactMap(\.link) == [URL(string: "https://github.com/max/maxwell/pull/12")!])
    }
}

@Suite("Morceaux d'un titre")
struct TaskLinkSegmentsTests {
    @Test func aTitleIsCutAroundItsLinks() {
        let url = URL(string: "https://github.com/max/maxwell/pull/12")!
        #expect(TaskLinks.segments(of: "Relire \(url.absoluteString) ce soir")
            == [.text("Relire "), .link(url), .text(" ce soir")])
        #expect(TaskLinks.segments(of: "Sans lien") == [.text("Sans lien")])
    }
}
