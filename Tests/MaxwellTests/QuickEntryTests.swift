import Foundation
import Testing
@testable import Maxwell

@Suite("Saisie rapide")
struct QuickEntryTests {
    /// Mercredi 25 novembre 2026.
    private let today = Day(year: 2026, month: 11, day: 25)
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func parse(_ text: String) -> QuickEntry {
        QuickEntry.parse(text, today: today, calendar: calendar)
    }

    private func day(_ month: Int, _ day: Int, _ year: Int = 2026) -> When {
        .day(Day(year: year, month: month, day: day))
    }

    @Test func aTitleAloneIsJustATitle() {
        #expect(parse("  Acheter du pain  ") == QuickEntry(title: "Acheter du pain"))
    }

    @Test(arguments: [
        ("aujourd'hui", 11, 25), ("aujourd’hui", 11, 25), ("demain", 11, 26), ("après-demain", 11, 27),
        ("vendredi", 11, 27), ("mercredi", 12, 2), ("lundi prochain", 11, 30), ("ce week-end", 11, 28),
        ("semaine prochaine", 11, 30), ("dans 3 jours", 11, 28), ("dans une semaine", 12, 2),
        ("le 3 déc", 12, 3), ("3 décembre", 12, 3), ("le 1er décembre", 12, 1), ("le 3/12", 12, 3),
        ("le 30", 11, 30), ("mois prochain", 12, 1),
    ])
    func datesAtTheEndBecomeTheWhen(phrase: String, month: Int, dayOfMonth: Int) {
        let entry = parse("Appeler Paul \(phrase)")
        #expect(entry.title == "Appeler Paul")
        #expect(entry.when == day(month, dayOfMonth))
    }

    @Test func aPastDateWithoutYearMeansNextYear() {
        #expect(parse("Impôts 3 mars").when == day(3, 3, 2027))
        #expect(parse("Payer le loyer le 2").when == day(12, 2))
    }

    @Test func avantSetsTheDeadline() {
        let entry = parse("Rendre le rapport demain avant vendredi")
        #expect(entry.title == "Rendre le rapport")
        #expect(entry.when == day(11, 26))
        #expect(entry.deadline == Day(year: 2026, month: 11, day: 27))
    }

    @Test func projectAndFlagAreReadAnywhere() {
        let entry = parse("Relancer #Ventes Paul demain !")
        #expect(entry == QuickEntry(title: "Relancer Paul", when: day(11, 26), projectName: "Ventes", flagged: true))
        #expect(parse("Appeler le client!").flagged)
        #expect(parse("Appeler le client!").title == "Appeler le client")
    }

    @Test func undefinedIsSomeday() {
        let entry = parse("Apprendre le piano un jour")
        #expect(entry.title == "Apprendre le piano")
        #expect(entry.when == .someday)
    }

    @Test func aDateInsideTheTitleStaysInTheTitle() {
        #expect(parse("Préparer la réunion de demain") == QuickEntry(title: "Préparer la réunion de demain"))
        #expect(parse("Demain on verra le devis") == QuickEntry(title: "Demain on verra le devis"))
        #expect(parse("Lire le chapitre 3") == QuickEntry(title: "Lire le chapitre 3"))
    }

    @Test func aDateAloneLeavesNoTitle() {
        #expect(parse("demain").title.isEmpty)
    }
}
