import SwiftUI

/// Dashboard weight card: the current weight (kg/lb toggle inline) + a calm 30-day
/// delta ("↓ 2.1 lb · 30 days"). Tapping opens the body-entry sheet. The unit
/// toggle never writes data; storage stays canonical kg. The full chart lives in
/// the Trend card, so this card stays quiet.
struct WeightCard: View {
    let metrics: [BodyMetric]
    var onTap: () -> Void
    @AppStorage("vita.weightUnit") private var weightUnitRaw = WeightUnit.lb.rawValue

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                vtLead("Weight.", color: VT.why)
                if let kg = DiarySeries.latest(.weight, metrics: metrics) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(display(kg)).font(.vtDose).vtTabular().foregroundStyle(VT.ink)
                            .contentTransition(.numericText())
                        Button { weightUnitRaw = (unit == .kg ? WeightUnit.lb : .kg).rawValue } label: {
                            Text(unit.rawValue).font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.dose)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Tap to change unit")
                        Spacer()
                    }
                    deltaLine
                } else {
                    Text("Add your weight.").font(.system(size: 15)).foregroundStyle(VT.body)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(VT.sCardPad).vtCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// A quiet 30-day delta. Down = a small down-arrow, never red (weight change
    /// isn't framed as good/bad). Hidden until there are at least two samples.
    @ViewBuilder
    private var deltaLine: some View {
        let trend = DiarySeries.weightTrend(metrics: metrics, days: 30, asOf: Date())
        if let deltaKg = trend.deltaKg {
            let d = unit == .lb ? Units.kgToLb(deltaKg) : deltaKg
            let flat = abs(deltaKg) < 0.05
            HStack(spacing: 5) {
                Image(systemName: flat ? "minus" : (deltaKg > 0 ? "arrow.up.right" : "arrow.down.right"))
                    .font(.system(size: 12, weight: .bold))
                Text(flat ? "Steady over 30 days" : "\(Units.trim(abs(d))) \(unit.rawValue) over 30 days")
                    .font(.system(size: 13, weight: .medium)).vtTabular()
            }
            .foregroundStyle(VT.micro)
        }
    }

    private func display(_ kg: Double) -> String {
        Units.trim(unit == .lb ? Units.kgToLb(kg) : kg)
    }
}
