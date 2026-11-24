import Foundation

/// Ce que Maxwell comprend d'une ligne tapée pour créer une Tâche :
/// « Relancer Paul demain avant vendredi #Ventes ! ».
///
/// Les dates ne sont lues qu'en fin de ligne, pour ne pas couper un titre comme
/// « Préparer la réunion de demain » : une date précédée de « de », « du » ou « des » reste dans le titre.
struct QuickEntry: Equatable {
    var title: String
    var when: When?
    var deadline: Day?
    var projectName: String?
    var flagged = false

    static func parse(_ text: String, today: Day, calendar: Calendar = .current) -> QuickEntry {
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var entry = QuickEntry(title: "")

        // #Projet et ! où qu'ils soient.
        words.removeAll { word in
            guard word.hasPrefix("#"), word.count > 1, word.dropFirst().first?.isLetter == true else { return false }
            entry.projectName = String(word.dropFirst())
            return true
        }
        if words.contains("!") {
            entry.flagged = true
            words.removeAll { $0 == "!" }
        } else if let last = words.last, last.hasSuffix("!"), !last.hasSuffix("!!") {
            entry.flagged = true
            words[words.count - 1] = String(last.dropLast())
        }

        // Les dates, de la fin vers le début, tant qu'il y en a.
        let reader = DateReader(today: today, calendar: calendar)
        reading: while !words.isEmpty {
            for length in stride(from: min(5, words.count), through: 1, by: -1) {
                let phrase = words.suffix(length).joined(separator: " ")
                guard let match = reader.read(phrase) else { continue }
                let previous = words.dropLast(length).last?.lowercased()
                if let previous, ["de", "du", "des"].contains(previous) { break reading }
                switch match {
                case .when(let when) where entry.when == nil: entry.when = when
                case .deadline(let day) where entry.deadline == nil: entry.deadline = day
                default: break reading
                }
                words.removeLast(length)
                continue reading
            }
            break
        }

        entry.title = words.joined(separator: " ")
        return entry
    }
}

/// Reconnaît une expression de date en français.
private struct DateReader {
    enum Match {
        case when(When)
        case deadline(Day)
    }

    let today: Day
    let calendar: Calendar

    private static let weekdays = ["dimanche": 1, "lundi": 2, "mardi": 3, "mercredi": 4, "jeudi": 5, "vendredi": 6, "samedi": 7]
    private static let months: [String: Int] = [
        "janvier": 1, "janv": 1, "jan": 1, "février": 2, "fevrier": 2, "févr": 2, "fevr": 2, "fév": 2, "fev": 2,
        "mars": 3, "avril": 4, "avr": 4, "mai": 5, "juin": 6, "juillet": 7, "juil": 7,
        "août": 8, "aout": 8, "septembre": 9, "sept": 9, "sep": 9, "octobre": 10, "oct": 10,
        "novembre": 11, "nov": 11, "décembre": 12, "decembre": 12, "déc": 12, "dec": 12,
    ]
    private static let numbers = ["un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5,
                                  "six": 6, "sept": 7, "huit": 8, "neuf": 9, "dix": 10, "quinze": 15]

    func read(_ phrase: String) -> Match? {
        let text = phrase.lowercased().replacingOccurrences(of: "’", with: "'")
        if text.hasPrefix("avant ") {
            guard case .day(let day) = when(String(text.dropFirst(6))) else { return nil }
            return .deadline(day)
        }
        return when(text).map(Match.when)
    }

    private func when(_ text: String) -> When? {
        if text == "un jour" { return .someday }
        return day(text).map(When.day)
    }

    private func day(_ text: String) -> Day? {
        switch text {
        case "aujourd'hui", "auj", "ce soir": return today
        case "demain": return today.adding(1, .day, calendar: calendar)
        case "après-demain", "apres-demain": return today.adding(2, .day, calendar: calendar)
        case "ce week-end", "ce weekend", "week-end", "weekend": return today.weekend(calendar: calendar)
        case "semaine prochaine", "la semaine prochaine": return next(weekday: 2)
        case "mois prochain", "le mois prochain":
            let first = Day(year: today.year, month: today.month, day: 1)
            return first.adding(1, .month, calendar: calendar)
        default: break
        }

        var words = text.split(separator: " ").map(String.init)
        // « lundi », « lundi prochain »
        if words.last == "prochain" || words.last == "prochaine" { words.removeLast() }
        if words.count == 1, let weekday = Self.weekdays[words[0]] { return next(weekday: weekday) }

        // « dans 3 jours », « dans une semaine »
        if words.count == 3, words[0] == "dans", let n = Int(words[1]) ?? Self.numbers[words[1]] {
            let unit = words[2]
            if unit.hasPrefix("jour") { return today.adding(n, .day, calendar: calendar) }
            if unit.hasPrefix("semaine") { return today.adding(n, .weekOfYear, calendar: calendar) }
            if unit == "mois" { return today.adding(n, .month, calendar: calendar) }
            if unit.hasPrefix("an") { return today.adding(n, .year, calendar: calendar) }
            return nil
        }

        // « le 3 », « 3 déc », « le 1er décembre 2027 », « 3/12 », « le 3/12/2027 »
        if words.first == "le" { words.removeFirst() }
        guard let first = words.first else { return nil }
        if words.count == 1, first.contains("/") {
            let parts = first.split(separator: "/").map { Int($0) }
            guard parts.count >= 2, parts.count <= 3, let d = parts[0], let m = parts[1] else { return nil }
            let year = parts.count == 3 ? parts[2].map { $0 < 100 ? 2000 + $0 : $0 } : nil
            guard parts.count == 2 || year != nil else { return nil }
            return date(day: d, month: m, year: year)
        }
        guard let d = Int(first.replacingOccurrences(of: "er", with: "")) else { return nil }
        switch words.count {
        case 1:
            // « le 3 » seul : le prochain 3 du mois. Sans « le », un nombre seul reste dans le titre.
            guard text.hasPrefix("le ") else { return nil }
            return date(day: d, month: today.month, year: nil, rollingMonth: true)
        case 2, 3:
            guard let m = Self.months[words[1].trimmingCharacters(in: CharacterSet(charactersIn: "."))] else { return nil }
            if words.count == 3 {
                guard let year = Int(words[2]), year > 1999 else { return nil }
                return date(day: d, month: m, year: year)
            }
            return date(day: d, month: m, year: nil)
        default:
            return nil
        }
    }

    private func next(weekday: Int) -> Day { today.next(weekday: weekday, calendar: calendar) }

    /// Sans année, une date déjà passée désigne l'an prochain (ou le mois prochain avec `rollingMonth`).
    private func date(day: Int, month: Int, year: Int?, rollingMonth: Bool = false) -> Day? {
        guard (1...31).contains(day), (1...12).contains(month) else { return nil }
        func valid(_ y: Int, _ m: Int) -> Day? {
            let components = DateComponents(year: y, month: m, day: day)
            guard components.isValidDate(in: calendar) else { return nil }
            return Day(year: y, month: m, day: day)
        }
        if let year { return valid(year, month) }
        if rollingMonth {
            for offset in 0..<12 {
                let start = Day(year: today.year, month: today.month, day: 1).adding(offset, .month, calendar: calendar)
                if let candidate = valid(start.year, start.month), candidate >= today { return candidate }
            }
            return nil
        }
        if let candidate = valid(today.year, month), candidate >= today { return candidate }
        return valid(today.year + 1, month)
    }
}

extension Day {
    /// Le prochain jour de la semaine, toujours après `self` : « lundi » dit un lundi veut dire dans 7 jours.
    func next(weekday: Int, calendar: Calendar = .current) -> Day {
        var gap = (weekday - self.weekday(calendar: calendar) + 7) % 7
        if gap == 0 { gap = 7 }
        return adding(gap, .day, calendar: calendar)
    }

    /// Le samedi qui vient, ou `self` si c'est déjà le week-end.
    func weekend(calendar: Calendar = .current) -> Day {
        let weekday = self.weekday(calendar: calendar)
        return weekday == 7 || weekday == 1 ? self : next(weekday: 7, calendar: calendar)
    }
}
