import Combine
import Foundation

/// D'où les vues tirent leurs Récaps. Elle prévient ses observateurs à chaque tick du suivi
/// et à chaque changement de Catégorie : une vue qui l'observe se rafraîchit d'elle-même,
/// sans avoir à connaître le Tracker, le Categorizer ni la base.
@MainActor
final class RecapSource: ObservableObject {
    /// L'heure du dernier tick du suivi : c'est le « maintenant » des Récaps.
    @Published private(set) var now: Date

    private let db: Database
    private var subscriptions: Set<AnyCancellable> = []

    init(db: Database, tracker: Tracker, categorizer: Categorizer) {
        self.db = db
        now = tracker.lastUpdate
        tracker.$lastUpdate
            .sink { [weak self] in self?.now = $0 }
            .store(in: &subscriptions)
        categorizer.$revision
            .dropFirst()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
    }

    /// Le Récap de la `period` qui contient `date`, tel qu'il est maintenant.
    func recap(_ period: Period, containing date: Date) -> Recap {
        Recap(db: db, period: period, containing: date, now: now)
    }
}
