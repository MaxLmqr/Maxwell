import Foundation

enum Period: String, CaseIterable, Identifiable {
    case day = "Jour"
    case week = "Semaine"
    case month = "Mois"

    var id: String { rawValue }

    private var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }

    /// Granularité du graphique : heures pour un jour, jours sinon.
    var bucketComponent: Calendar.Component { self == .day ? .hour : .day }

    func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: component, for: date)!
    }

    func shift(_ date: Date, by value: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: component, value: value, to: date)!
    }

    func buckets(of interval: DateInterval, calendar: Calendar = .current) -> [DateInterval] {
        var result: [DateInterval] = []
        var start = interval.start
        while start < interval.end {
            let end = calendar.date(byAdding: bucketComponent, value: 1, to: start)!
            result.append(DateInterval(start: start, end: min(end, interval.end)))
            start = end
        }
        return result
    }

    var comparisonLabel: String {
        switch self {
        case .day: "vs hier"
        case .week: "vs semaine passée"
        case .month: "vs mois dernier"
        }
    }

    /// Période précédente, tronquée à la même durée écoulée si la période est en cours
    /// (lundi 11 h se compare à lundi 11 h, pas à toute la semaine passée).
    func previousInterval(before interval: DateInterval, now: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        let previous = self.interval(containing: shift(interval.start, by: -1, calendar: calendar), calendar: calendar)
        guard interval.contains(now) else { return previous }
        let elapsed = now.timeIntervalSince(interval.start)
        return DateInterval(start: previous.start, duration: min(elapsed, previous.duration))
    }

    /// « Samedi 24 octobre », « 19 – 25 octobre », « Octobre 2026 ».
    func title(for interval: DateInterval, calendar: Calendar = .current) -> String {
        let start = interval.start
        let title: String
        switch self {
        case .day:
            title = start.formatted(.dateTime.weekday(.wide).day().month(.wide))
        case .week:
            let last = interval.end.addingTimeInterval(-1)
            if calendar.isDate(start, equalTo: last, toGranularity: .month) {
                title = "\(start.formatted(.dateTime.day())) – \(last.formatted(.dateTime.day().month(.wide)))"
            } else {
                let format = Date.FormatStyle.dateTime.day().month(.abbreviated)
                title = "\(start.formatted(format)) – \(last.formatted(format))"
            }
        case .month:
            title = start.formatted(.dateTime.month(.wide).year())
        }
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    /// Libellé d'une barre du graphique, pour l'info-bulle.
    func bucketTitle(for start: Date) -> String {
        switch self {
        case .day:
            let hour = Calendar.current.component(.hour, from: start)
            return "\(hour) h – \(hour + 1) h"
        case .week, .month:
            let title = start.formatted(.dateTime.weekday(.wide).day().month(.wide))
            return title.prefix(1).uppercased() + title.dropFirst()
        }
    }
}

/// Évolution en pourcentage, ou « — » si la période de référence est quasi vide.
func formatDelta(_ current: TimeInterval, _ previous: TimeInterval) -> String {
    guard previous >= 60 else { return "—" }
    let change = Int(((current - previous) / previous * 100).rounded())
    return change >= 0 ? "+ \(change) %" : "− \(-change) %"
}

/// Part d'un total, arrondie ; une part non nulle n'est jamais affichée « 0 % ».
func formatShare(_ fraction: Double) -> String {
    if fraction > 0 && fraction < 0.005 { return "< 1 %" }
    return "\(Int((fraction * 100).rounded())) %"
}

func formatDuration(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds / 60)
    if minutes < 1 { return "< 1 min" }
    if minutes < 60 { return "\(minutes) min" }
    return String(format: "%d h %02d", minutes / 60, minutes % 60)
}
