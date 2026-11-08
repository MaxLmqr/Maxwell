import Foundation

/// Le Récap d'une période : son Temps actif, sa comparaison avec la période précédente,
/// ses Catégories classées et sa répartition jour par jour (ou heure par heure).
/// Une valeur calculée en une fois à partir de la base ; rien n'y est mis en forme.
struct Recap {
    /// Un Jour actif compte au moins ce Temps actif.
    static let activeDayThreshold: TimeInterval = 60
    /// En dessous de ce Temps actif, la période précédente ne permet pas de comparer.
    static let comparisonThreshold: TimeInterval = 60
    /// En dessous de ce temps sur la période, un Site est replié dans le détail de sa Catégorie.
    static let smallSiteDuration: TimeInterval = 10 * 60
    /// Nombre de Catégories principales ; les suivantes forment « les autres ».
    static let principalCount = 4

    /// Évolution du Temps actif par rapport à la période précédente.
    enum Change: Equatable {
        /// La période précédente compte moins de `comparisonThreshold`.
        case notEnoughData
        /// Pourcentage arrondi : + 12 pour une hausse de 12 %.
        case percent(Int)

        init(current: TimeInterval, previous: TimeInterval) {
            guard previous >= Recap.comparisonThreshold else { self = .notEnoughData; return }
            self = .percent(Int(((current - previous) / previous * 100).rounded()))
        }
    }

    struct Category: Identifiable {
        let id: CategoryID
        let name: String
        let symbol: String
        let duration: TimeInterval
        /// Rang dans la période, 0 pour la plus utilisée.
        let rank: Int
        let swatch: Theme.Swatch
        /// Les Apps et les Sites de la Catégorie, du plus long au plus court.
        let subjects: [AppUsage]
        /// Les petits Sites, repliés derrière « Tout afficher ». Vide quand la Catégorie
        /// n'a que de petits Sites : ils sont alors tous montrés.
        let foldedSites: [AppUsage]
        var isPrincipal: Bool { rank < Recap.principalCount }
        /// Les Apps et les Sites montrés d'emblée dans le détail.
        var visibleSubjects: [AppUsage] {
            foldedSites.isEmpty ? subjects : subjects.filter { !$0.isSmallSite }
        }
    }

    /// Un jour du Récap d'une semaine ou d'un mois, une heure de celui d'un jour.
    struct Bucket: Identifiable {
        let interval: DateInterval
        let byCategory: [CategoryID: TimeInterval]
        /// Temps des Catégories qui ne sont pas principales sur la période.
        let others: TimeInterval
        var total: TimeInterval { byCategory.values.reduce(0, +) }
        var isActive: Bool { total >= Recap.activeDayThreshold }
        var id: Date { interval.start }
    }

    let period: Period
    let interval: DateInterval
    let total: TimeInterval
    /// Temps actif de la période précédente, coupée à la même durée écoulée si la période est en cours.
    let previousTotal: TimeInterval
    /// Toutes les Catégories ayant du temps sur la période, de la plus utilisée à la moins utilisée.
    let categories: [Category]
    let buckets: [Bucket]
    /// Nombre d'Apps utilisées : un navigateur compte une fois, quel que soit le nombre de ses Sites.
    let appCount: Int

    var principal: ArraySlice<Category> { categories.prefix(Self.principalCount) }
    var others: ArraySlice<Category> { categories.dropFirst(Self.principalCount) }
    var othersDuration: TimeInterval { others.reduce(0) { $0 + $1.duration } }

    var change: Change { Change(current: total, previous: previousTotal) }

    /// Temps actif moyen par Jour actif (par heure active dans le Récap d'un jour).
    var activeDayAverage: TimeInterval {
        let active = buckets.filter(\.isActive).count
        return active > 0 ? total / Double(active) : 0
    }

    func category(_ id: CategoryID) -> Category? { categories.first { $0.id == id } }

    /// Le Récap de la `period` qui contient `date`. `now` coupe la période précédente
    /// quand la période est en cours : lundi 11 h se compare à lundi 11 h.
    init(db: Database, period: Period, containing date: Date, now: Date = Date(), calendar: Calendar = .current) {
        self.period = period
        interval = period.interval(containing: date, calendar: calendar)
        let previous = period.previousInterval(before: interval, now: now, calendar: calendar)
        previousTotal = db.visibleSessions(in: previous).reduce(0) { $0 + $1.duration(in: previous) }

        // Une seule lecture de la base : tout le reste se compte à partir de ces Sessions.
        let sessions = db.visibleSessions(in: interval)
        let bucketIntervals = period.buckets(of: interval, calendar: calendar)
        var byCategory: [CategoryID: TimeInterval] = [:]
        var bySubject: [Subject: AppUsage] = [:]
        var byBucket = [[CategoryID: TimeInterval]](repeating: [:], count: bucketIntervals.count)
        for session in sessions {
            let duration = session.duration(in: interval)
            byCategory[session.categoryID, default: 0] += duration
            let previousUsage = bySubject[session.subject]
            // Pour un Site visité dans plusieurs navigateurs, on garde le même navigateur que l'ancienne
            // requête (le plus grand identifiant) et le nom de l'App le plus grand pour une App.
            bySubject[session.subject] = AppUsage(
                bundleID: max(previousUsage?.bundleID ?? session.bundleID, session.bundleID),
                site: session.site,
                name: session.site ?? max(previousUsage?.name ?? session.appName, session.appName),
                categoryID: session.categoryID,
                duration: (previousUsage?.duration ?? 0) + duration)
            for (index, bucket) in bucketIntervals.enumerated()
            where bucket.start < session.end && session.start < bucket.end {
                byBucket[index][session.categoryID, default: 0] += session.duration(in: bucket)
            }
        }
        let usage = bySubject.values
            .filter { $0.duration >= 1 }
            .sorted { $0.duration > $1.duration }

        let known = db.categories()
        let byID = Dictionary(uniqueKeysWithValues: known.map { ($0.id, $0) })
        let swatches = Theme.swatches(for: known)
        categories = byCategory
            .filter { $0.value >= 1 }
            .sorted { $0.value > $1.value }
            .enumerated()
            .map { rank, item in
                let subjects = usage.filter { $0.categoryID == item.key }
                let small = subjects.filter(\.isSmallSite)
                let folds = !small.isEmpty && small.count < subjects.count
                return Category(id: item.key,
                                name: byID[item.key]?.name ?? "À classer",
                                symbol: byID[item.key]?.symbol ?? Maxwell.Category.uncategorizedSymbol,
                                duration: item.value, rank: rank,
                                swatch: swatches[item.key, default: Theme.uncategorized],
                                subjects: subjects, foldedSites: folds ? small : [])
            }
        total = categories.reduce(0) { $0 + $1.duration }
        appCount = Set(usage.map(\.bundleID)).count

        let principalIDs = Set(categories.prefix(Self.principalCount).map(\.id))
        buckets = zip(bucketIntervals, byBucket).map { bucket, byCategory in
            let others = byCategory.filter { !principalIDs.contains($0.key) }.values.reduce(0, +)
            return Bucket(interval: bucket, byCategory: byCategory, others: others)
        }
    }
}

extension AppUsage {
    var isSmallSite: Bool { site != nil && duration < Recap.smallSiteDuration }
}
