import SwiftUI
import Charts

/// The Diary's wearable metrics (M42): sleep, HRV, resting HR, and respiratory
/// rate read live from Apple Health, where Oura/Whoop/Fitbit sync. Each card =
/// accent lead + latest value + a clipped 30-day sparkline. Read-only; nothing
/// is persisted.
struct WearablesSection: View {
    let series: VitalsSeries
    /// Health never asked yet → offer the connect flow (requests authorization).
    var onConnect: (() -> Void)? = nil
    /// Health asked but no readable data → deep-link to iOS Settings, since
    /// HealthKit hides read-grant status and re-asking is a silent no-op.
    var onOpenHealthSettings: (() -> Void)? = nil
    /// Oura API summary, present only when connected via OAuth (or in demo).
    /// nil leaves the section exactly as it was before Oura existed.
    var oura: OuraDailySummary? = nil
    /// Kicks off a vendor OAuth sign-in; the section itself stays view-only.
    var onConnectVendor: ((WearableVendor) -> Void)? = nil

    /// Preview-only overrides so #Previews can render every hub state without
    /// touching UserDefaults or the Keychain. nil = read the real source.
    var previewAuthRequested: Bool? = nil
    var previewOuraConnected: Bool? = nil

    private var healthConnected: Bool { !series.isEmpty }
    private var authRequested: Bool { previewAuthRequested ?? HealthKitService.authRequested }
    private var ouraConnected: Bool { previewOuraConnected ?? WearableAuthStore.isConnected(.oura) }

    /// Show the hub while any source is still unconnected; hide it once Health
    /// has data and Oura is connected, keeping the surface calm. Management of
    /// connected sources (incl. Disconnect) lives in Settings, not here.
    private var showHub: Bool {
        !(healthConnected && ouraConnected)
    }

    var body: some View {
        VStack(spacing: VT.sCardGap) {
            if showHub { hub }
            if !series.isEmpty {
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
            ouraCards
        }
    }

    // MARK: - Connect your wearables hub

    /// Lists ONLY the sources that are still unconnected. Each row drops out the
    /// moment its source connects; the whole card disappears once every source
    /// is connected. There is no Disconnect here — that moved to Settings.
    private var hub: some View {
        VStack(alignment: .leading, spacing: 14) {
            vtLead("Connect your wearables.", color: VT.dose)
            VStack(spacing: 14) {
                if !healthConnected { healthRow }
                if !ouraConnected { ouraRow }
            }
            Text("Read-only. Vita never writes back to your data.")
                .font(.system(size: 12)).foregroundStyle(VT.micro)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    /// Apple Health has two unconnected states. Never asked -> a Connect pill
    /// that requests authorization. Asked but no readable data -> the permission
    /// hint plus a deep link (re-asking would silently no-op).
    private var healthRow: some View {
        HStack(spacing: 12) {
            Circle().fill(VT.dose).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Health")
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(VT.ink)
                if authRequested {
                    Text("No data yet. Check Health permissions for Vita.")
                        .font(.system(size: 12)).foregroundStyle(VT.micro)
                }
            }
            Spacer(minLength: 12)
            if authRequested {
                Button("Open Settings") { onOpenHealthSettings?() }
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(VT.dose)
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)   // touch-target floor
            } else {
                connectPill { onConnect?() }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Oura is unconnected either because it is configured and awaiting sign-in
    /// (Connect pill) or because the developer app was never registered.
    private var ouraRow: some View {
        HStack(spacing: 12) {
            Circle().fill(WearableVendor.oura.isConfigured ? VT.dose : VT.hairline)
                .frame(width: 8, height: 8)
            Text("Oura")
                .font(.system(size: 15, weight: .medium)).foregroundStyle(VT.ink)
            Spacer(minLength: 12)
            if WearableVendor.oura.isConfigured {
                connectPill { onConnectVendor?(.oura) }
            } else {
                Text("Needs a one-time developer app setup.")
                    .font(.system(size: 12)).foregroundStyle(VT.micro)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 150, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func connectPill(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Connect")
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(VT.onInk)
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(VT.ink, in: Capsule())
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)   // touch-target floor
    }

    /// Readiness, sleep score, and temperature deviation from the Oura API.
    /// Rendered only when a summary is present; otherwise the section is unchanged.
    @ViewBuilder
    private var ouraCards: some View {
        if let oura, !oura.isEmpty {
            VStack(spacing: VT.sCardGap) {
                HStack(spacing: VT.sCardGap) {
                    WearableCard(lead: "Readiness.", color: VT.dose, unit: "",
                                 points: oura.readiness.map { DatedValue(day: $0.day, value: Double($0.score)) },
                                 decimals: 0)
                    WearableCard(lead: "Sleep score.", color: VT.catPurple, unit: "",
                                 points: oura.sleepScore.map { DatedValue(day: $0.day, value: Double($0.score)) },
                                 decimals: 0)
                }
                WearableCard(lead: "Temperature.", color: VT.timing, unit: "°C",
                             points: oura.temperatureDeviation.map { DatedValue(day: $0.day, value: $0.value) },
                             decimals: 1, signed: true)
            }
        }
    }

}

/// One compact wearable metric card: lead word, latest value, 30-day sparkline.
struct WearableCard: View {
    var lead: String
    var color: Color
    var unit: String
    var points: [DatedValue]
    var decimals: Int
    /// Prefix positive values with "+" (temperature deviation reads as +/- baseline).
    var signed: Bool = false

    private var latest: Double? { points.last?.value }

    private func format(_ v: Double) -> String {
        let s = String(format: "%.\(decimals)f", v)
        return (signed && v > 0) ? "+\(s)" : s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            vtLead(lead, color: color, size: 14)
            if let latest {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(format(latest))
                        .font(.vtDose).vtTabular().foregroundStyle(VT.ink)
                        .contentTransition(.numericText())
                    if !unit.isEmpty {
                        Text(unit).font(.system(size: 13, weight: .semibold)).foregroundStyle(VT.micro)
                    }
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
        VStack(spacing: VT.sSection) {
            // Hub with both rows: Health never asked (Connect) + Oura.
            WearablesSection(series: VitalsSeries(), onConnect: {}, onConnectVendor: { _ in },
                             previewAuthRequested: false, previewOuraConnected: false)

            // Hub with only the Health "check permissions" row (Oura connected,
            // so its row is gone). Health asked but nothing readable yet.
            WearablesSection(series: VitalsSeries(), onConnect: {}, onOpenHealthSettings: {},
                             onConnectVendor: { _ in },
                             previewAuthRequested: true, previewOuraConnected: true)

            // Hub absent: Health has data AND Oura connected. Only metric cards.
            WearablesSection(series: .demo(), onConnect: {}, oura: .demo(),
                             onConnectVendor: { _ in },
                             previewAuthRequested: true, previewOuraConnected: true)
        }
        .padding(VT.sSection)
    }
    .background(VT.canvas)
}
