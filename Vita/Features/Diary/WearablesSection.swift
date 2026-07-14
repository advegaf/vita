import SwiftUI
import Charts

/// The Diary's wearable metrics (M42): sleep, HRV, resting HR, and respiratory
/// rate read live from Apple Health, where Oura/Whoop/Fitbit sync. Each card =
/// accent lead + latest value + a clipped 30-day sparkline. Read-only; nothing
/// is persisted.
struct WearablesSection: View {
    let series: VitalsSeries
    /// Health available but nothing readable yet → offer the connect flow.
    var onConnect: (() -> Void)? = nil

    var body: some View {
        if series.isEmpty {
            connectCard
        } else {
            VStack(spacing: VT.sCardGap) {
                HStack(spacing: VT.sCardGap) {
                    WearableCard(lead: "Sleep.", color: VT.catPurple, unit: "h",
                                 points: series.sleepHours, decimals: 1)
                    WearableCard(lead: "HRV.", color: VT.dose, unit: "ms",
                                 points: series.hrvMs, decimals: 0)
                }
                HStack(spacing: VT.sCardGap) {
                    WearableCard(lead: "Resting HR.", color: VT.timing, unit: "bpm",
                                 points: series.restingHR, decimals: 0)
                    WearableCard(lead: "Breath.", color: VT.why, unit: "br/min",
                                 points: series.respiratoryRate, decimals: 1)
                }
            }
        }
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            vtLead("Wearables.", color: VT.dose)
            Text("Sleep, HRV, and heart rate from your Oura ring or watch, via Apple Health.")
                .font(.system(size: 14)).foregroundStyle(VT.body).lineSpacing(2)
            if let onConnect {
                Button(action: onConnect) {
                    Text("Connect Apple Health")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.onInk)
                        .frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(VT.ink, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            Text("Read-only. Vita never writes to Health.")
                .font(.system(size: 12)).foregroundStyle(VT.micro)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }
}

/// One compact wearable metric card: lead word, latest value, 30-day sparkline.
struct WearableCard: View {
    var lead: String
    var color: Color
    var unit: String
    var points: [DatedValue]
    var decimals: Int

    private var latest: Double? { points.last?.value }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            vtLead(lead, color: color, size: 14)
            if let latest {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(String(format: "%.\(decimals)f", latest))
                        .font(.vtDose).vtTabular().foregroundStyle(VT.ink)
                        .contentTransition(.numericText())
                    Text(unit).font(.system(size: 13, weight: .semibold)).foregroundStyle(VT.micro)
                }
                sparkline
            } else {
                Text("No data yet.")
                    .font(.system(size: 13)).foregroundStyle(VT.micro)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16).vtCard()
        .accessibilityElement(children: .combine)
    }

    private var sparkline: some View {
        Chart(points, id: \.day) { p in
            LineMark(x: .value("Day", p.day, unit: .day), y: .value(lead, p.value))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .foregroundStyle(color)
        }
        .chartYScale(domain: yDomain)
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .frame(height: 34)
        .clipped()   // never let a mark escape the card (the trend-chart leak)
        .accessibilityHidden(true)
    }

    private var yDomain: ClosedRange<Double> {
        let vs = points.map(\.value)
        guard let lo = vs.min(), let hi = vs.max(), hi > lo else {
            let v = vs.first ?? 0
            return (v - 1)...(v + 1)
        }
        let pad = (hi - lo) * 0.2
        return (lo - pad)...(hi + pad)
    }
}

extension VitalsSeries {
    /// Deterministic demo series for screenshots (VITA_DIARY_DEMO) — plausible
    /// Oura-like values, generated without touching HealthKit.
    static func demo(asOf now: Date = .now) -> VitalsSeries {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        func series(_ base: Double, _ swing: Double, _ round: Double = 0.1) -> [DatedValue] {
            (0..<30).reversed().compactMap { back in
                guard let day = cal.date(byAdding: .day, value: -back, to: today) else { return nil }
                let phase = Double(back) * 0.7
                let raw = base + swing * (0.6 * sin(phase) + 0.4 * cos(phase * 1.7))
                return DatedValue(day: day, value: (raw / round).rounded() * round)
            }
        }
        return VitalsSeries(hrvMs: series(52, 9, 1),
                            restingHR: series(56, 3, 1),
                            respiratoryRate: series(13.4, 0.7),
                            sleepHours: series(7.2, 0.9))
    }
}

#Preview {
    ScrollView {
        VStack(spacing: VT.sCardGap) {
            WearablesSection(series: .demo())
            WearablesSection(series: VitalsSeries(), onConnect: {})
        }
        .padding(VT.sSection)
    }
    .background(VT.canvas)
}
