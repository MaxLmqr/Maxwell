import Charts
import SwiftUI

struct RecapView: View {
    @EnvironmentObject private var source: RecapSource
    @EnvironmentObject private var navigation: RecapNavigation
    @State private var hovered: CategoryID?
    @State private var expanded: Set<CategoryID> = []
    /// Catégories dont le détail montre aussi les petits sites.
    @State private var showingAll: Set<CategoryID> = []
    @State private var selectedBucket: Date?

    /// `previewHovered` et `previewExpanded` servent aux captures :
    /// ils simulent le survol d'une catégorie et le détail ouvert d'une autre.
    init(previewHovered: CategoryID? = nil, previewExpanded: CategoryID? = nil) {
        _hovered = State(initialValue: previewHovered)
        _expanded = State(initialValue: Set([previewExpanded].compactMap { $0 }))
    }

    var body: some View {
        let period = navigation.period
        let recap = source.recap(period, containing: navigation.referenceDate)
        let interval = recap.interval
        let isCurrent = interval.contains(Date())

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
                    metric("Temps actif") { BigNumber(formatDuration(recap.total), size: 36) }
                    if period == .day {
                        metric("Apps utilisées") { Text("\(recap.appCount)") }
                    } else {
                        metric("Par jour actif") { Text(formatDuration(recap.activeDayAverage)) }
                    }
                    metric(period.comparisonLabel) { DeltaLabel(change: recap.change) }
                    Spacer(minLength: 0)
                }

                RecapChart(period: period, recap: recap, hovered: hovered,
                           average: period == .day ? nil : recap.activeDayAverage, selected: $selectedBucket)
                    .frame(height: 210)

                categories(recap: recap)
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
    private func categories(recap: Recap) -> some View {
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

            if recap.categories.isEmpty {
                Text("Aucune activité sur cette période.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            } else {
                let longest = recap.categories[0].duration
                VStack(spacing: 2) {
                    ForEach(recap.categories) { entry in
                        let isOpen = expanded.contains(entry.id)
                        CategoryRow(entry: entry, subjects: entry.subjects.map(\.subject), longest: longest,
                                    total: recap.total, isHovered: hovered == entry.id, isExpanded: isOpen)
                            .onHover { inside in
                                if inside { hovered = entry.id } else if hovered == entry.id { hovered = nil }
                            }
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    if isOpen { expanded.remove(entry.id) } else { expanded.insert(entry.id) }
                                }
                            }
                        if isOpen {
                            let folded = entry.foldedSites
                            let showsAll = showingAll.contains(entry.id) || folded.isEmpty
                            VStack(spacing: 0) {
                                ForEach(showsAll ? entry.subjects : entry.visibleSubjects) { app in
                                    AppRow(app: app, share: app.duration / entry.duration, iconSize: 16)
                                        .categoryMenu(for: app.subject, current: app.categoryID)
                                }
                                if !folded.isEmpty {
                                    SmallSitesToggle(count: folded.count, showsAll: showsAll) {
                                        withAnimation(.easeOut(duration: 0.15)) {
                                            if showsAll { showingAll.remove(entry.id) } else { showingAll.insert(entry.id) }
                                        }
                                    }
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
    let entry: Recap.Category
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
                        .fill(entry.isPrincipal ? entry.swatch.fill : Color.primary.opacity(0.16))
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

/// Bas du détail d'une catégorie : montre ou cache ses petits sites.
private struct SmallSitesToggle: View {
    let count: Int
    let showsAll: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Button(action: action) {
                HStack(spacing: 6) {
                    Text(showsAll ? "Afficher moins" : "Tout afficher")
                        .foregroundStyle(Theme.accent)
                    if !showsAll {
                        Text("\(count) site\(count > 1 ? "s" : "") de moins de \(formatDuration(Recap.smallSiteDuration))")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .font(.system(size: 12))
        // Aligné sur les noms, après l'icône de 16 pt.
        .padding(.leading, 26)
        .padding(.vertical, 4)
    }
}

/// Barres empilées par catégorie, avec la moyenne en pointillés.
/// Au survol d'une catégorie, seule sa part reste en couleur ; au survol d'une barre, une info-bulle donne le total.
private struct RecapChart: View {
    let period: Period
    let recap: Recap
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

    private var buckets: [Recap.Bucket] { recap.buckets }
    private var interval: DateInterval { recap.interval }

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

    private func tooltip(for bucket: Recap.Bucket) -> some View {
        let main = bucket.byCategory.max { $0.value < $1.value }.flatMap { recap.category($0.key) }
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
        let principal = Array(recap.principal)
        for bucket in buckets where bucket.total >= 1 {
            var parts: [(key: String, value: Double, fill: Color)]
            if let hovered, let entry = recap.category(hovered) {
                let value = bucket.byCategory[hovered] ?? 0
                // Hors des quatre premières, la ligne est grise : le survol aussi, pour ne pas
                // emprunter la teinte d'une catégorie colorée.
                let highlight = entry.isPrincipal ? entry.swatch.fill : Color.primary.opacity(0.4)
                parts = [("h", value, highlight), ("rest", bucket.total - value, Theme.emptyBar)]
            } else {
                parts = principal.map { ("\($0.id)", bucket.byCategory[$0.id] ?? 0, $0.fill) }
                parts.append(("others", bucket.others, Theme.othersFill))
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
            ForEach(categorizer.categories()) { category in
                Button {
                    categorizer.assign(category.id, to: subject)
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
