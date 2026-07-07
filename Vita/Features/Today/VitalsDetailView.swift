import SwiftUI
import Charts

/// Vitals drill-in (M38): a 30-day chart per metric, the educational insights, and a
/// one-tap "Ask vita" that PREFILLS chat (never auto-sends, so the API key is never
/// invoked without the user). Presented as a sheet; wrapped in its own NavigationStack
/// by the caller for the title + Done bar.
struct VitalsDetailView: View {
    let series: VitalsSeries
    var windows: [CompoundWindow] = []

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var metric: VitalMetric = .hrv
    @State private var selectedDay: Date?
    @State private var lastScrubDay: Date?

    private let days = 30

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VT.sCardGap) {
                chartCard
                insightsSection
                footer
            }
            .padding(VT.sSection)
        }
        .scrollIndicators(.hidden)
        .background(VT.canvas)
        .navigationTitle("Vitals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }

    // MARK: Chart

    private var chartCard: some View {
        let pts = points
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                vtLead("Trend.", color: metric.accent)
                Spacer()
                if let c = calloutText(pts) {
                    Text(c).font(.system(size: 14, weight: .semibold)).vtTabular()
                        .foregroundStyle(metric.accent).contentTransition(.numericText())
                }
            }
            chipRow
            chart(pts)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    private var chipRow: some View {
        HStack(spacing: 8) {
            ForEach(VitalMetric.allCases) { m in
                let on = m == metric
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { metric = m }
                    selectedDay = nil
                    Haptics.segment()
                } label: {
                    Text(m.title).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(on ? .white : VT.body)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(on ? m.accent : VT.ink.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(m.title)
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    @ViewBuilder
    private func chart(_ pts: [Point]) -> some View {
        if pts.count < 2 {
            Text("Not enough \(metric.title) data yet.")
                .font(.system(size: 14)).foregroundStyle(VT.micro)
                .frame(maxWidth: .infinity).frame(height: 170)
        } else {
            VStack(spacing: 8) {
                Chart {
                    if let base = VitalsInsightEngine.baseline(metric.values(series), asOf: Date()) {
                        RuleMark(y: .value("Baseline", base))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .foregroundStyle(VT.micro.opacity(0.5))
                    }
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
                        RuleMark(x: .value("Day", sel.day, unit: .day)).foregroundStyle(VT.hairline)
                        PointMark(x: .value("Day", sel.day, unit: .day), y: .value(metric.title, sel.value))
                            .foregroundStyle(metric.accent).symbolSize(80)
                    }
                }
                .chartXScale(domain: domain)
                .chartYScale(domain: yDomain(pts))
                .chartXSelection(value: $selectedDay)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                        AxisValueLabel().font(.system(size: 11)).foregroundStyle(VT.micro)
                    }
                }
                .frame(height: 170)
                .id(metric)
                .transition(.opacity)
                .accessibilityLabel("\(metric.title) trend, last 30 days")
                .onChange(of: selectedDay) { _, _ in
                    guard let p = selectedPoint(pts) else { return }
                    if lastScrubDay == nil || !Calendar.current.isDate(p.day, inSameDayAs: lastScrubDay!) {
                        lastScrubDay = p.day; Haptics.segment()
                    }
                }
                dateStrip
            }
        }
    }

    private var dateStrip: some View {
        HStack(spacing: 0) {
            Text(domain.lowerBound.formatted(.dateTime.month(.abbreviated).day()))
            Spacer()
            Text(domain.upperBound.formatted(.dateTime.month(.abbreviated).day()))
        }
        .font(.system(size: 11, weight: .medium)).foregroundStyle(VT.micro)
    }

    // MARK: Insights

    private var insightsSection: some View {
        let insights = VitalsInsightEngine.insights(series, windows: windows)
        return VStack(alignment: .leading, spacing: VT.sCardGap) {
            if insights.isEmpty || tooThin {
                VStack(alignment: .leading, spacing: 6) {
                    vtLead("Insights.", color: VT.dose)
                    Text("Baselines form after about two weeks of data.")
                        .font(.system(size: 14)).foregroundStyle(VT.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(VT.sCardPad).vtCard()
            } else {
                ForEach(insights) { insight in
                    VStack(alignment: .leading, spacing: 6) {
                        vtLead("Insight.", color: toneColor(insight.tone))
                        Text(insight.headline)
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(insight.detail)
                            .font(.system(size: 14)).foregroundStyle(VT.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(VT.sCardPad).vtCard()
                }
                Button(action: askVita) {
                    Text("Ask vita about this →")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.dose)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("From Apple Health. Whoop, Oura, and Fitbit can sync their data there.")
                .font(.system(size: 12)).foregroundStyle(VT.micro)
            Text("Educational, not medical advice.")
                .font(.system(size: 12)).foregroundStyle(VT.micro)
        }
    }

    private func toneColor(_ tone: VitalInsight.Tone) -> Color {
        switch tone { case .attention: VT.overdue; case .info: VT.dose; case .positive: VT.why }
    }

    /// Prefills chat with a grounded question the USER sends (never auto-invoked).
    private func askVita() {
        let ground = VitalsInsightEngine.groundingLine(series) ?? ""
        let lead = VitalsInsightEngine.insights(series, windows: windows).first?.headline ?? "my recent vitals"
        NotificationRouter.shared.pendingChatPrompt =
            "Educationally, what could explain this alongside my stack? \(lead) (\(ground))"
        NotificationRouter.shared.pendingTab = .chat
        dismiss()
    }

    // MARK: Derivations

    private typealias Point = (day: Date, value: Double)

    private var tooThin: Bool {
        VitalMetric.allCases.allSatisfy { VitalsInsightEngine.baseline($0.values(series), asOf: Date()) == nil }
    }

    private var points: [Point] {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -(days - 1), to: cal.startOfDay(for: Date())) ?? Date()
        return metric.values(series).filter { $0.day >= start }.map { ($0.day, $0.value) }
    }

    private func selectedPoint(_ pts: [Point]) -> Point? {
        guard let sel = selectedDay else { return nil }
        return pts.min { abs($0.day.timeIntervalSince(sel)) < abs($1.day.timeIntervalSince(sel)) }
    }

    private var domain: ClosedRange<Date> {
        let cal = Calendar.current
        let end = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        return start...end
    }

    private func yDomain(_ pts: [Point]) -> ClosedRange<Double> {
        let vals = pts.map(\.value)
        guard let lo = vals.min(), let hi = vals.max() else { return 0...1 }
        let span: Double = metric == .sleep ? 2 : (metric == .respiratory ? 3 : 10)
        return TrendDomain.padded(min: lo, max: hi, minSpan: span)
    }

    private func calloutText(_ pts: [Point]) -> String? {
        guard !pts.isEmpty, let t = selectedPoint(pts) ?? pts.last else { return nil }
        let date = t.day.formatted(.dateTime.month(.abbreviated).day())
        let v = metric.oneDecimal ? String(format: "%.1f", t.value) : String(Int(t.value.rounded()))
        return "\(date), \(v) \(metric.unit)"
    }
}
