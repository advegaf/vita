import SwiftUI

/// The metrics the vitals surfaces show. Accents come from the closed category tint
/// set (D-14); missing metrics still render a tile so the grid never reflows.
enum VitalMetric: String, CaseIterable, Identifiable {
    case hrv, restingHR, sleep, respiratory
    var id: String { rawValue }

    var title: String {
        switch self {
        case .hrv: "HRV"; case .restingHR: "Resting HR"; case .sleep: "Sleep"; case .respiratory: "Respiratory"
        }
    }
    var unit: String {
        switch self {
        case .hrv: "ms"; case .restingHR: "bpm"; case .sleep: "h"; case .respiratory: "br/min"
        }
    }
    var accent: Color {
        switch self {
        case .hrv: VT.catBlue; case .restingHR: VT.catPink; case .sleep: VT.catPurple; case .respiratory: VT.catGray
        }
    }
    var oneDecimal: Bool { self == .sleep || self == .respiratory }

    func values(_ s: VitalsSeries) -> [DatedValue] {
        switch self {
        case .hrv: s.hrvMs; case .restingHR: s.restingHR; case .sleep: s.sleepHours; case .respiratory: s.respiratoryRate
        }
    }
}

/// Today's vitals section (M38). Leads with the single most important line (a
/// protocol-correlation or baseline insight), then three supporting stat tiles, and
/// taps into the detail sheet. Hidden entirely when Health is unavailable.
struct VitalsCard: View {
    let windows: [CompoundWindow]

    @State private var series: VitalsSeries?
    @State private var loading = true
    @AppStorage("vita.vitalsAuthRequested") private var authRequested = false
    @State private var showDetail = false
    private let provider = VitalsService.make()

    private let tiles: [VitalMetric] = [.hrv, .restingHR, .sleep]

    var body: some View {
        if provider.isAvailable {
            card.task { await load() }
                .sheet(isPresented: $showDetail) {
                    NavigationStack {
                        VitalsDetailView(series: series ?? VitalsSeries(), windows: windows)
                    }
                }
        }
    }

    @ViewBuilder
    private var card: some View {
        if loading {
            shell { tileRow.redacted(reason: .placeholder) }
        } else if let series, !series.isEmpty {
            Button { showDetail = true } label: {
                shell {
                    if let insight = VitalsInsightEngine.insights(series, windows: windows).first {
                        Text(insight.headline)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(insight.tone == .positive ? VT.why : VT.ink)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    tileRow(series)
                }
            }
            .buttonStyle(.plain)
        } else {
            shell { connectState }
        }
    }

    private func shell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                vtLead("Vitals.", color: VT.dose)
                Spacer()
                if series != nil, !(series?.isEmpty ?? true) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(VT.micro)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    private var tileRow: some View { tileRow(VitalsSeries()) }

    private func tileRow(_ s: VitalsSeries) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(tiles.enumerated()), id: \.element) { i, m in
                if i > 0 { Rectangle().fill(VT.hairline).frame(width: 1, height: 40) }
                StatTile(metric: m, series: s).frame(maxWidth: .infinity)
            }
        }
    }

    private var connectState: some View {
        Group {
            if authRequested {
                Text("No recent vitals in Apple Health.")
                    .font(.system(size: 14)).foregroundStyle(VT.body)
            } else {
                Button {
                    Task {
                        _ = await provider.requestAuthorization()
                        authRequested = true
                        await load()
                    }
                } label: {
                    Text("Connect Apple Health →")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.dose)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("From Apple Health. Whoop, Oura, and Fitbit can sync their data there.")
                .font(.system(size: 12)).foregroundStyle(VT.micro)
        }
    }

    private func load() async {
        loading = true
        series = await provider.series(days: 60)
        loading = false
        #if DEBUG
        if ProcessInfo.processInfo.environment["VITA_OPEN_VITALS"] == "1",
           !(series?.isEmpty ?? true) { showDetail = true }
        #endif
    }
}

/// One plain stat column (no sub-card): label, value + unit, delta vs the 30-day
/// baseline. Delta stays neutral: direction meaning differs per metric, so color
/// would mislead. A metric with no data shows "No data" and keeps its slot.
private struct StatTile: View {
    let metric: VitalMetric
    let series: VitalsSeries

    var body: some View {
        let s = metric.values(series)
        let recent = VitalsInsightEngine.recentAverage(s, asOf: Date())
        let base = VitalsInsightEngine.baseline(s, asOf: Date())
        return VStack(alignment: .leading, spacing: 3) {
            Text(metric.title.uppercased())
                .font(.system(size: 11, weight: .semibold)).tracking(0.4).foregroundStyle(VT.micro)
            if let recent {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(fmt(recent)).font(.system(size: 20, weight: .semibold)).vtTabular().foregroundStyle(VT.ink)
                    Text(metric.unit).font(.system(size: 13)).foregroundStyle(VT.micro)
                }
                if let base, base > 0 {
                    let pct = Int(((recent - base) / base * 100).rounded())
                    HStack(spacing: 2) {
                        Image(systemName: pct >= 0 ? "arrow.up" : "arrow.down")
                            .font(.system(size: 9, weight: .bold)).accessibilityHidden(true)
                        Text("\(abs(pct))% vs 30d").font(.system(size: 12))
                    }
                    .foregroundStyle(VT.body)
                }
            } else {
                Text("No data").font(.system(size: 13)).foregroundStyle(VT.micro)
            }
        }
        .padding(.horizontal, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11y(recent: recent, base: base))
    }

    private func fmt(_ v: Double) -> String {
        metric.oneDecimal ? String(format: "%.1f", v) : String(Int(v.rounded()))
    }
    private func a11y(recent: Double?, base: Double?) -> String {
        guard let recent else { return "\(metric.title), no recent data." }
        var t = "\(metric.title) \(fmt(recent)) \(metric.unit)."
        if let base, base > 0 {
            let pct = Int(((recent - base) / base * 100).rounded())
            t += " \(pct >= 0 ? "up" : "down") \(abs(pct)) percent versus 30 day baseline."
        }
        return t
    }
}
