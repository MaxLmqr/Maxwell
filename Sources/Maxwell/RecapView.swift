import Charts
import SwiftUI

struct RecapView: View {
    @EnvironmentObject private var tracker: Tracker
    @EnvironmentObject private var categorizer: Categorizer
    @EnvironmentObject private var navigation: RecapNavigation
    @State private var hovered: CategoryID?
    @State private var expanded: Set<CategoryID> = []
    @State private var selectedBucket: Date?

    /// `previewHovered` sert aux captures : il simule le survol d'une catégorie.
    init(previewHovered: CategoryID? = nil) {
        _hovered = State(initialValue: previewHovered)
    }

    struct Bucket: Identifiable {
        let interval: DateInterval
        let byCategory: [CategoryID: TimeInterval]
        var total: TimeInterval { byCategory.values.reduce(0, +) }
        var id: Date { interval.start }
    }

    var body: some View {
        // Lire ces valeurs abonne la vue aux ticks du tracker et aux changements de catégories.
        let now = tracker.lastUpdate
        let _ = categorizer.revision
        let db = tracker.db
        let period = navigation.period
        let interval = period.interval(containing: navigation.referenceDate)
        let isCurrent = interval.contains(Date())
        let ranking = CategoryRanking(durations: db.durationByCategory(in: interval), categories: db.categories())
        let usage = db.usageByApp(in: interval)
        let previousTotal = db.totalDuration(in: period.previousInterval(before: interval, now: now))
        let buckets = period.buckets(of: interval).map {
            Bucket(interval: $0, byCategory: db.durationByCategory(in: $0))
        }
        let activeBuckets = buckets.filter { $0.total >= 60 }.count
        let average = activeBuckets > 0 ? ranking.total / Double(activeBuckets) : 0

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(period.title(for: interval))
                        .font(.system(size: 22, weight: .semibold))
                    if let subtitle = subtitle(period: period, interval: interval, isCurrent: isCurrent) {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(alignment: .top, spacing: 44) {
                    metric("Temps actif") { BigNumber(formatDuration(ranking.total), size: 36) }
                    if period == .day {
                        metric("Apps utilisées") { Text("\(Set(usage.map(\.bundleID)).count)") }
                    } else {
                        metric("Par jour actif") { Text(formatDuration(average)) }
                    }
                    metric(period.comparisonLabel) { DeltaLabel(current: ranking.total, previous: previousTotal) }
                    Spacer(minLength: 0)
                }

                RecapChart(period: period, interval: interval, buckets: buckets, ranking: ranking, hovered: hovered,
                           average: period == .day ? nil : average, selected: $selectedBucket)
                    .frame(height: 210)

                categories(ranking: ranking, usage: usage)
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .frame(minWidth: 560, minHeight: 620)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { navigation.referenceDate = period.shift(navigation.referenceDate, by: -1) } label: {
                    Label("Précédent", systemImage: "chevron.left")
                }
                .help("Période précédente")
                Button { navigation.referenceDate = period.shift(navigation.referenceDate, by: 1) } label: {
                    Label("Suivant", systemImage: "chevron.right")
                }
                .help("Période suivante")
                .disabled(isCurrent)
            }
            ToolbarItem(placement: .principal) {
                Picker("Période", selection: $navigation.period) {
                    ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Aujourd'hui") { navigation.referenceDate = Date() }
                    .disabled(isCurrent)
            }
        }
    }

    private func subtitle(period: Period, interval: DateInterval, isCurrent: Bool) -> String? {
        switch period {
        case .day:
            return isCurrent ? "Aujourd'hui" : nil
        case .week:
            let week = Calendar.current.component(.weekOfYear, from: interval.start)
            return isCurrent ? "Semaine \(week) · en cours" : "Semaine \(week)"
        case .month:
            return isCurrent ? "Mois en cours" : nil
        }
    }

    private func metric<Value: View>(_ label: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Caption(label)
            value()
                .font(.system(size: 20))
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func categories(ranking: CategoryRanking, usage: [AppUsage]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Catégories").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Gérer…") { Windows.showCategories() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)

            if ranking.entries.isEmpty {
                Text("Aucune activité sur cette période.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            } else {
                let longest = ranking.entries[0].duration
                VStack(spacing: 2) {
                    ForEach(ranking.entries) { entry in
                        let apps = usage.filter { $0.categoryID == entry.id }
                        let isOpen = expanded.contains(entry.id)
                        CategoryRow(entry: entry, subjects: apps.map(\.subject), longest: longest,
                                    total: ranking.total, isHovered: hovered == entry.id, isExpanded: isOpen)
                            .onHover { inside in
                                if inside { hovered = entry.id } else if hovered == entry.id { hovered = nil }
                            }
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    if isOpen { expanded.remove(entry.id) } else { expanded.insert(entry.id) }
                                }
                            }
                        if isOpen {
                            VStack(spacing: 0) {
                                ForEach(apps) { app in
                                    AppRow(app: app, share: app.duration / entry.duration, iconSize: 16)
                                        .categoryMenu(for: app.subject, current: app.categoryID)
                                }
                            }
                            .padding(.leading, 50)
                            .padding(.trailing, 30)
                            .padding(.bottom, 6)
                        }
                    }
                }
            }
        }
    }
}

private struct CategoryRow: View {
    let entry: CategoryRanking.Entry
    let subjects: [Subject]
    let longest: TimeInterval
    let total: TimeInterval
    let isHovered: Bool
    let isExpanded: Bool

    var body: some View {
        HStack(spacing: 12) {
            CategoryBadge(symbol: entry.symbol, fill: entry.fill, glyph: entry.glyph, size: 28)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(entry.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    AppIconStack(subjects: subjects, size: 15)
                    Spacer(minLength: 8)
                    Text(formatDuration(entry.duration))
                        .font(.system(size: 13))
                    Text(formatShare(total > 0 ? entry.duration / total : 0))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
                .monospacedDigit()
                GeometryReader { geo in
                    Capsule()
                        .fill(entry.rank < CategoryRanking.colorCount ? entry.fill : Color.primary.opacity(0.16))
                        .frame(width: max(geo.size.width * entry.duration / longest, 3))
                }
                .frame(height: 4)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.05 : 0)))
        .contentShape(Rectangle())
    }
}

/// Barres empilées par catégorie, avec la moyenne en pointillés.
/// Au survol d'une catégorie, seule sa part reste en couleur ; au survol d'une barre, une info-bulle donne le total.
private struct RecapChart: View {
    let period: Period
    let interval: DateInterval
    let buckets: [RecapView.Bucket]
    let ranking: CategoryRanking
    let hovered: CategoryID?
    let average: TimeInterval?
    @Binding var selected: Date?

    private struct Segment: Identifiable {
        let id: String
        let bucket: Date
        let start: Double
        let end: Double
        let fill: Color
    }

    private var unit: (divisor: Double, label: String) { period == .day ? (60, "min") : (3600, "h") }

    var body: some View {
        let maxTotal = buckets.map(\.total).max() ?? 0
        let top = period == .day ? 60 : max(maxTotal / unit.divisor * 1.08, 1)
        let segments = makeSegments(gap: top * 0.012)
        let selectedBucket = buckets.first { $0.interval.start == selected }

        Chart {
            ForEach(segments) { segment in
                BarMark(
                    x: .value("Date", segment.bucket, unit: period.bucketComponent),
                    yStart: .value(unit.label, segment.start),
                    yEnd: .value(unit.label, segment.end),
                    width: .ratio(period == .week ? 0.5 : 0.62)
                )
                .cornerRadius(2.5, style: .continuous)
                .foregroundStyle(segment.fill)
            }

            if let average, average >= 60, hovered == nil {
                RuleMark(y: .value("Moyenne", average / unit.divisor))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.8))
                    .annotation(position: .top, alignment: .trailing, spacing: 3) {
                        Text("moyenne \(formatDuration(average))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(nsColor: .windowBackgroundColor).opacity(0.9), in: Capsule())
                    }
            }

            if let bucket = selectedBucket, bucket.total >= 60 {
                BarMark(
                    x: .value("Date", bucket.interval.start, unit: period.bucketComponent),
                    yStart: .value(unit.label, 0),
                    yEnd: .value(unit.label, bucket.total / unit.divisor)
                )
                .foregroundStyle(.clear)
                .annotation(position: .top, spacing: 6,
                            overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                    tooltip(for: bucket)
                }
            }
        }
        .chartXScale(domain: interval.start...interval.end)
        .chartYScale(domain: 0...top)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.primary.opacity(0.08))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v)) \(unit.label)")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    }
                }
            }
        }
        .chartXAxis { xAxis }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            guard let plot = proxy.plotFrame else { return }
                            let x = location.x - geo[plot].origin.x
                            if let date: Date = proxy.value(atX: x) {
                                selected = buckets.first { $0.interval.contains(date) }?.interval.start
                            }
                        case .ended:
                            selected = nil
                        }
                    }
            }
        }
    }

    @AxisContentBuilder private var xAxis: some AxisContent {
        switch period {
        case .day:
            AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                AxisValueLabel(centered: true) {
                    if let date = value.as(Date.self) {
                        axisText("\(Calendar.current.component(.hour, from: date)) h", emphasized: false)
                    }
                }
            }
        case .week:
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel(centered: true) {
                    if let date = value.as(Date.self) {
                        axisText(date.formatted(.dateTime.weekday(.abbreviated)),
                                 emphasized: Calendar.current.isDateInToday(date))
                    }
                }
            }
        case .month:
            // Un repère par lundi, placé à midi pour tomber au milieu de la barre du jour.
            AxisMarks(values: buckets.map(\.interval.start).filter {
                Calendar.current.component(.weekday, from: $0) == Calendar.current.firstWeekday
            }.map { $0.addingTimeInterval(12 * 3600) }) { value in
                AxisValueLabel(centered: false, anchor: .top) {
                    if let date = value.as(Date.self) {
                        axisText(date.formatted(.dateTime.day().month(.abbreviated)), emphasized: false)
                    }
                }
            }
        }
    }

    private func axisText(_ text: String, emphasized: Bool) -> some View {
        Text(text)
            .font(.system(size: 10, weight: emphasized ? .semibold : .regular))
            .foregroundStyle(emphasized ? Color.primary : Color(nsColor: .tertiaryLabelColor))
    }

    private func tooltip(for bucket: RecapView.Bucket) -> some View {
        let main = bucket.byCategory.max { $0.value < $1.value }.flatMap { ranking.entry($0.key) }
        return VStack(alignment: .leading, spacing: 2) {
            Text(period.bucketTitle(for: bucket.interval.start))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(formatDuration(bucket.total))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
            if let main {
                Text("Surtout \(main.name)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }

    /// Empile les quatre catégories principales puis « les autres », avec un léger jour entre chaque part.
    private func makeSegments(gap: Double) -> [Segment] {
        var segments: [Segment] = []
        let topCategories = Array(ranking.colored)
        for bucket in buckets where bucket.total >= 1 {
            var parts: [(key: String, value: Double, fill: Color)]
            if let hovered, ranking.entry(hovered) != nil {
                let value = bucket.byCategory[hovered] ?? 0
                parts = [("h", value, Theme.accent), ("rest", bucket.total - value, Theme.emptyBar)]
            } else {
                let values = topCategories.map { bucket.byCategory[$0.id] ?? 0 }
                parts = zip(topCategories, values).map { ("\($0.id)", $1, $0.fill) }
                parts.append(("others", bucket.total - values.reduce(0, +), Theme.othersFill))
            }

            var y = 0.0
            let visible = parts.map { (key: $0.key, value: $0.value / unit.divisor, fill: $0.fill) }.filter { $0.value > 0.0001 }
            for (index, part) in visible.enumerated() {
                let end = y + part.value
                let isLast = index == visible.count - 1
                let drawnEnd = isLast || part.value <= gap * 2 ? end : end - gap
                segments.append(Segment(id: "\(bucket.id.timeIntervalSince1970)-\(part.key)",
                                        bucket: bucket.interval.start, start: y, end: drawnEnd, fill: part.fill))
                y = end
            }
        }
        return segments
    }
}

extension View {
    /// Clic droit sur une app ou un site : changer sa catégorie.
    func categoryMenu(for subject: Subject, current: CategoryID) -> some View {
        modifier(CategoryMenu(subject: subject, current: current))
    }
}

private struct CategoryMenu: ViewModifier {
    @EnvironmentObject private var categorizer: Categorizer
    let subject: Subject
    let current: CategoryID

    func body(content: Content) -> some View {
        content.contextMenu {
            Text("Catégorie")
            ForEach(categorizer.db.categories()) { category in
                Button {
                    categorizer.db.setCategory(category.id, for: subject, manual: true)
                    categorizer.changed()
                } label: {
                    if category.id == current {
                        Label(category.name, systemImage: "checkmark")
                    } else {
                        Text(category.name)
                    }
                }
            }
            Divider()
            Button("Gérer les catégories…") { Windows.showCategories() }
        }
    }
}
