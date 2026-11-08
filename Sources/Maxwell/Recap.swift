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
    }

    struct Category: Identifiable {
        let id: CategoryID
        let name: String
        let symbol: String
        let duration: TimeInterval
        /// Rang dans la période, 0 pour la plus utilisée.
        let rank: Int
        let swatch: Theme.Swatch
        /// Les Apps et les Sites montrés d'emblée dans le détail, du plus long au plus court.
        let subjects: [AppUsage]
        /// Les petits Sites, repliés derrière « Tout afficher ». Vide quand la Catégorie
        /// n'a que de petits Sites : ils sont alors tous montrés.
        let foldedSites: [AppUsage]
        var isPrincipal: Bool { rank < Recap.principalCount }
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

    var change: Change {
        guard previousTotal >= Self.comparisonThreshold else { return .notEnoughData }
        return .percent(Int(((total - previousTotal) / previousTotal * 100).rounded()))
    }

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
        previousTotal = db.totalDuration(in: period.previousInterval(before: interval, now: now, calendar: calendar))

        let ranking = CategoryRanking(durations: db.durationByCategory(in: interval), categories: db.categories())
        let usage = db.usageByApp(in: interval)
        total = ranking.total
        categories = ranking.entries.map { entry in
            let subjects = usage.filter { $0.categoryID == entry.id }
            let small = subjects.filter(\.isSmallSite)
            let folds = !small.isEmpty && small.count < subjects.count
            return Category(id: entry.id, name: entry.name, symbol: entry.symbol, duration: entry.duration,
                            rank: entry.rank, swatch: entry.swatch,
                            subjects: folds ? subjects.filter { !$0.isSmallSite } : subjects,
                            foldedSites: folds ? small : [])
        }
        appCount = Set(usage.map(\.bundleID)).count

        let principalIDs = Set(categories.prefix(Self.principalCount).map(\.id))
        buckets = period.buckets(of: interval, calendar: calendar).map { bucket in
            let byCategory = db.durationByCategory(in: bucket)
            let others = byCategory.filter { !principalIDs.contains($0.key) }.values.reduce(0, +)
            return Bucket(interval: bucket, byCategory: byCategory, others: others)
        }
    }
}

extension AppUsage {
    var isSmallSite: Bool { site != nil && duration < Recap.smallSiteDuration }
}
