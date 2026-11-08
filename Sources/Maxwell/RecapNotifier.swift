import AppKit
import UserNotifications

/// Envoie le récap de la semaine le lundi à 9 h et celui du mois le 1er à 9 h.
/// Si le Mac dort à ce moment-là, la notification part au réveil.
@MainActor
final class RecapNotifier: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "recapNotificationsEnabled")
            if enabled { requestAuthorization() }
        }
    }

    private let db: Database
    private let sendHour = 9
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    init(db: Database) {
        self.db = db
        enabled = UserDefaults.standard.object(forKey: "recapNotificationsEnabled") as? Bool ?? true
    }

    func start() {
        UNUserNotificationCenter.current().delegate = self
        if enabled { requestAuthorization() }
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        check()
    }

    private func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("Maxwell notification authorization error: \(error)") }
        }
    }

    private func check(now: Date = Date()) {
        guard enabled else { return }
        let calendar = Calendar.current
        for period in [Period.week, .month] {
            let current = period.interval(containing: now)
            let sendTime = calendar.date(byAdding: .hour, value: sendHour, to: current.start)!
            let key = "lastRecapSent.\(period.rawValue)"
            guard now >= sendTime,
                  UserDefaults.standard.double(forKey: key) < current.start.timeIntervalSince1970
            else { continue }
            UserDefaults.standard.set(current.start.timeIntervalSince1970, forKey: key)
            send(period, for: period.interval(containing: period.shift(current.start, by: -1)))
        }
    }

    private func send(_ period: Period, for interval: DateInterval) {
        let recap = Recap(db: db, period: period, containing: interval.start)
        guard recap.total >= Recap.activeDayThreshold else { return }
        let top = recap.categories.prefix(3).map { "\($0.name) \(formatDuration($0.duration))" }

        let content = UNMutableNotificationContent()
        content.title = period == .week ? "Ta semaine" : "Ton mois"
        content.subtitle = period.title(for: interval)
        content.body = "\(formatDuration(recap.total)) actives (\(formatDelta(recap.change))) · \(top.joined(separator: ", "))"
        content.userInfo = ["period": period.rawValue, "date": interval.start.timeIntervalSince1970]

        let request = UNNotificationRequest(identifier: "recap-\(period.rawValue)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { NSLog("Maxwell notification error: \(error)") }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let period = (info["period"] as? String).flatMap(Period.init(rawValue:))
        let date = (info["date"] as? Double).map(Date.init(timeIntervalSince1970:))
        await MainActor.run { Windows.showRecap(period: period, date: date) }
    }
}
