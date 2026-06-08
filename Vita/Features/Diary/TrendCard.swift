import SwiftUI
import Charts

/// The hero 30-day trend (M8a). A monotone line with a soft area wash in the active
/// metric's accent, a scrollable chip row swapping the series, a fixed 30-day domain
/// framed by `TrendDomain.padded`, a clean date strip below, and drag-scrub
/// (`chartXSelection`) with a value callout. Switching metrics REPLACES the chart
/// (a cheap cross-fade via `.id(metric)`) rather than interpolating marks between
/// unrelated datasets — so it stays snappy. Body metrics render in display units.
struct TrendCard: View {
    @Binding var metric: DiaryMetric
    let entries: [DiaryEntry]
    let metrics: [BodyMetric]
    var now: Date = Date()

    @State private var selectedDay: Date?
    @State private var lastScrubDay: Date?
    @AppStorage("vita.weightUnit") private var weightUnitRaw = WeightUnit.lb.rawValue
    @AppStorage("vita.measureUnit") private var measureUnitRaw = MeasurementUnit.inch.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let chips: [DiaryMetric] = [.weight, .energy, .sleep, .mood, .libido, .waist, .arm]
    private let days = 30
    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }
    private var measureUnit: MeasurementUnit { MeasurementUnit(rawValue: measureUnitRaw) ?? .inch }

    var body: some View {
        let pts = points   // computed ONCE per render, threaded into header/chart
        return VStack(alignment: .leading, spacing: 14) {
            header(pts)
            chipRow
            chart(pts)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard(radius: VT.rFocusCard)
        .accessibilityElement(children: .contain)
    }

    private func header(_ pts: [Point]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            vtLead("Trend.", color: metric.accent)
            Spacer()
            if let c = calloutText(pts) {
                Text(c).font(.system(size: 14, weight: .semibold)).vtTabular()
                    .foregroundStyle(metric.accent).contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.title) trend, last 30 days")
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { m in
                    let on = m == metric
                    Button {
                        // Light cross-fade; NOT a spring on the chart marks (that lags).
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { metric = m }
                        selectedDay = nil
                        Haptics.segment()
                    } label: {
                        HStack(spacing: 5) {
                            Circle().fill(on ? Color.white : m.accent).frame(width: 6, height: 6)
                            Text(m.title).font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(on ? .white : VT.body)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(on ? m.accent : VT.ink.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(m.title)
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func chart(_ pts: [Point]) -> some View {
        if pts.isEmpty {
            Text("Your trend fills in as you check in.")
                .font(.system(size: 14)).foregroundStyle(VT.micro)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity).frame(height: 170)
        } else {
            VStack(spacing: 8) {
                Chart {
                    ForEach(pts, id: \.day) { p in
                        AreaMark(x: .value("Day", p.day, unit: .day), y: .value(metric.title, p.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(.linearGradient(
                                colors: [metric.accent.opacity(0.14), metric.accent.opacity(0.0)],
                                startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Day", p.day, unit: .day), y: .value(metric.title, p.value))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                            .foregroundStyle(metric.accent)
                    }
                    if let sel = selectedPoint(pts) {
                        RuleMark(x: .value("Day", sel.day, unit: .day))
                            .foregroundStyle(VT.hairline)
                        PointMark(x: .value("Day", sel.day, unit: .day), y: .value(metric.title, sel.value))
                            .foregroundStyle(metric.accent).symbolSize(80)
                    }
                }
                .chartXScale(domain: domain)
                .chartYScale(domain: yDomain(pts))
                .chartXSelection(value: $selectedDay)
                .chartXAxis(.hidden)                                // date labels live in dateStrip
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                        AxisValueLabel().font(.system(size: 11)).foregroundStyle(VT.micro)
                    }
                }
                .frame(height: 170)
                .id(metric)                                         // replace, don't interpolate marks
                .transition(.opacity)
                .onChange(of: selectedDay) { _, _ in
                    guard let p = selectedPoint(pts) else { return }
                    if lastScrubDay == nil || !Calendar.current.isDate(p.day, inSameDayAs: lastScrubDay!) {
                        lastScrubDay = p.day
                        Haptics.segment()
                    }
                }
                dateStrip
            }
        }
    }

    /// Three calm date ticks below the plot — start / mid / end.
    private var dateStrip: some View {
        HStack(spacing: 0) {
            Text(domain.lowerBound.formatted(.dateTime.month(.abbreviated).day()))
            Spacer()
            Text(midDate.formatted(.dateTime.month(.abbreviated).day()))
            Spacer()
            Text(domain.upperBound.formatted(.dateTime.month(.abbreviated).day()))
        }
        .font(.system(size: 11, weight: .medium)).foregroundStyle(VT.micro)
    }

    private var midDate: Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: -(days / 2), to: cal.startOfDay(for: now)) ?? now
    }

    // MARK: Derivations

    private typealias Point = (day: Date, value: Double)

    /// Present points in DISPLAY units (body metrics converted from canonical).
    private var points: [Point] {
        DiarySeries.series(metric, entries: entries, metrics: metrics, days: days, asOf: now)
            .compactMap { p in p.value.map { (p.day, displayValue($0)) } }
    }

    private func selectedPoint(_ pts: [Point]) -> Point? {
        guard let sel = selectedDay else { return nil }
        return pts.min { abs($0.day.timeIntervalSince(sel)) < abs($1.day.timeIntervalSince(sel)) }
    }

    private var domain: ClosedRange<Date> {
        let cal = Calendar.current
        let end = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        return start...end
    }

    private func yDomain(_ pts: [Point]) -> ClosedRange<Double> {
        if metric.isRating { return 0.5...10.5 }
        let vals = pts.map(\.value)
        guard let lo = vals.min(), let hi = vals.max() else { return 0...1 }
        let floor: Double = metric == .weight ? 6 : 3   // display units (lb / in) — min vertical room
        return TrendDomain.padded(min: lo, max: hi, minSpan: floor)
    }

    private func calloutText(_ pts: [Point]) -> String? {
        guard !pts.isEmpty else { return nil }
        let t = selectedPoint(pts) ?? pts.last
        guard let t else { return nil }
        let date = t.day.formatted(.dateTime.month(.abbreviated).day())
        if metric.isRating { return "\(date) · \(Int(t.value.rounded()))/10" }
        return "\(date) · \(Units.trim(t.value)) \(unitLabel)"
    }

    private var unitLabel: String {
        switch metric {
        case .weight: weightUnit.rawValue
        case .waist, .arm: measureUnit.rawValue
        default: "/10"
        }
    }

    private func displayValue(_ canonical: Double) -> Double {
        switch metric {
        case .weight: weightUnit == .lb ? Units.kgToLb(canonical) : canonical
        case .waist, .arm: measureUnit == .inch ? Units.cmToInches(canonical) : canonical
        default: canonical
        }
    }
}
