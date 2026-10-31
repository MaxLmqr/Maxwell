import ServiceManagement
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var tracker: Tracker
    @EnvironmentObject private var categorizer: Categorizer
    @EnvironmentObject private var notifier: RecapNotifier
    @EnvironmentObject private var shelf: ShelfController
    @Environment(\.dismiss) private var dismiss
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        let now = tracker.lastUpdate
        let _ = categorizer.revision
        let db = tracker.db
        let today = Period.day.interval(containing: now)
        let ranking = CategoryRanking(durations: db.durationByCategory(in: today), categories: db.categories())
        let yesterday = db.totalDuration(in: Period.day.previousInterval(before: today, now: now))
        let usage = db.usageByApp(in: today)
        let hours = Period.day.buckets(of: today).map { db.totalDuration(in: $0) }
        let others = ranking.entries.dropFirst(CategoryRanking.colorCount)

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Aujourd'hui")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                status
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                BigNumber(formatDuration(ranking.total), size: 32)
                if yesterday >= 60 {
                    HStack(spacing: 4) {
                        DeltaLabel(current: ranking.total, previous: yesterday)
                        Text("vs hier")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)

            ShareBar(ranking: ranking)
                .padding(.top, 12)

            if ranking.entries.isEmpty {
                Text("Ton activité apparaîtra ici.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            } else {
                VStack(spacing: 4) {
                    ForEach(ranking.colored) { entry in
                        CategoryLine(entry: entry,
                                     bundleIDs: usage.filter { $0.categoryID == entry.id }.map(\.bundleID))
                    }
                }
                .padding(.top, 12)
                if !others.isEmpty {
                    Text("\(others.count) autre\(others.count > 1 ? "s" : "") · \(formatDuration(others.reduce(0) { $0 + $1.duration }))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 32)
                        .padding(.top, 4)
                }
            }

            DayRhythm(hours: hours, currentHour: Calendar.current.component(.hour, from: now))
                .padding(.top, 18)

            Divider()
                .padding(.top, 14)
                .padding(.bottom, 6)

            footer
        }
        .padding(16)
        .frame(width: 300)
        .onChange(of: launchAtLogin) { _, enabled in
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Maxwell login item error: \(error)")
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    @ViewBuilder private var status: some View {
        if tracker.isSuspended {
            StatusPill(text: "En pause", dot: nil)
        } else if tracker.isIdle {
            StatusPill(text: "Inactif", dot: nil)
        } else if let name = tracker.currentAppName {
            StatusPill(text: name, dot: Theme.accent)
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Button { Windows.showRecap() } label: {
                HStack {
                    Text("Ouvrir le récap")
                    Spacer()
                    Text("⌘R").foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(MenuRowButtonStyle())
            .keyboardShortcut("r")

            Menu {
                Button("Ouvrir l'Étagère") {
                    shelf.openFromMenu()
                    dismiss()
                }
                Button("Catégories…") { Windows.showCategories() }
                Divider()
                Toggle("Secouer pour ouvrir l'Étagère", isOn: $shelf.opensOnShake)
                Toggle("Notifications de récap", isOn: $notifier.enabled)
                Toggle("Lancer au démarrage", isOn: $launchAtLogin)
                Divider()
                if let updater = Updater.shared {
                    Button("Rechercher les mises à jour…") { updater.checkForUpdates() }
                }
                Button("Quitter Maxwell") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(.secondary)
            .fixedSize()
            .padding(.horizontal, 6)
            .help("Réglages")
        }
        .padding(.horizontal, -8)
        .background {
            // ⌘Q reste disponible quand le menu est ouvert.
            Button("") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
                .opacity(0)
                .allowsHitTesting(false)
        }
    }
}

private struct StatusPill: View {
    let text: String
    let dot: Color?

    var body: some View {
        HStack(spacing: 5) {
            if let dot {
                Circle().fill(dot).frame(width: 6, height: 6)
            }
            Text(text).lineLimit(1)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

/// Répartition de la journée entre les catégories principales ; les pastilles en dessous servent de légende.
private struct ShareBar: View {
    let ranking: CategoryRanking

    var body: some View {
        let others = ranking.entries.dropFirst(CategoryRanking.colorCount).reduce(0) { $0 + $1.duration }
        let segments = ranking.colored.map { ($0.duration, $0.fill) } + (others > 0 ? [(others, Theme.othersFill)] : [])
        let total = ranking.total

        GeometryReader { geo in
            let available = geo.size.width - 2 * Double(max(segments.count - 1, 0))
            HStack(spacing: 2) {
                if segments.isEmpty {
                    Rectangle().fill(Theme.emptyBar)
                } else {
                    ForEach(segments.indices, id: \.self) { i in
                        Rectangle()
                            .fill(segments[i].1)
                            .frame(width: max(available * segments[i].0 / total, 2))
                    }
                }
            }
        }
        .frame(height: 8)
        .clipShape(Capsule())
    }
}

private struct CategoryLine: View {
    let entry: CategoryRanking.Entry
    let bundleIDs: [String]

    var body: some View {
        HStack(spacing: 10) {
            CategoryBadge(symbol: entry.symbol, fill: entry.fill, glyph: entry.glyph, size: 22)
            Text(entry.name).lineLimit(1)
            AppIconStack(bundleIDs: bundleIDs, size: 15)
            Spacer(minLength: 8)
            Text(formatDuration(entry.duration))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.system(size: 13))
    }
}

/// Les 24 heures de la journée : la hauteur de chaque barre est le temps actif dans l'heure.
private struct DayRhythm: View {
    let hours: [TimeInterval]
    let currentHour: Int
    private let height: CGFloat = 26

    var body: some View {
        VStack(spacing: 5) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(hours.indices, id: \.self) { h in
                    let active = hours[h] >= 60
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(active ? (h == currentHour ? Theme.accent : Color.primary.opacity(0.22)) : Theme.emptyBar)
                        .frame(height: active ? max(height * min(hours[h] / 3600, 1), 3) : 3)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: height, alignment: .bottom)

            GeometryReader { geo in
                ForEach([0, 6, 12, 18, 24], id: \.self) { h in
                    Text("\(h) h")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize()
                        .position(x: min(max(geo.size.width * CGFloat(h) / 24, 9), geo.size.width - 11), y: 6)
                }
            }
            .frame(height: 12)
        }
    }
}
