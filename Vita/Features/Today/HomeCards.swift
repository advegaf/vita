import SwiftUI

/// Home hero + summary cards (reference language: colored full-bleed hero cards
/// with gauge arcs, a white biomarker summary with a tri-color segment bar, and
/// "help us know you better" setup rows).

// MARK: - Gauge arc (¾ circle, used by both hero cards)

struct GaugeArc: Shape {
    var fraction: Double   // 0...1
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let start = Angle(degrees: 135)
        let end = Angle(degrees: 135 + 270 * min(1, max(0, fraction)))
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                 radius: min(rect.width, rect.height) / 2,
                 startAngle: start, endAngle: end, clockwise: false)
        return p
    }
}

// MARK: - Score hero card

struct HealthScoreCard: View {
    let result: HealthScore.Result

    private var bg: Color {
        if !result.hasLabs { return VT.dose }
        switch result.score {
        case 80...: return Color(light: "1E8A5B", dark: "1E8A5B")   // deep optimal green
        case 60..<80: return Color(light: "2B7FB8", dark: "2B7FB8") // deep vita blue
        default: return Color(light: "B84A78", dark: "B84A78")      // deep attention rose
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Text("Score")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
            ZStack {
                GaugeArc(fraction: 1)
                    .stroke(.white.opacity(0.25), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                GaugeArc(fraction: Double(result.score) / 100)
                    .stroke(.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                VStack(spacing: 0) {
                    Text("\(result.score)")
                        .font(.system(size: 40, weight: .bold)).vtTabular()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("out of 100")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(width: 120, height: 120)
            Text(result.hasLabs ? "From your labs and logging" : "Add bloodwork to sharpen this")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(VT.sCardPad)
        .background(bg, in: RoundedRectangle(cornerRadius: VT.rFocusCard, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Wellness score \(result.score) out of 100")
    }
}

// MARK: - Adherence hero card

struct AdherenceHeroCard: View {
    let logged: Int
    let scheduled: Int

    private var fraction: Double { scheduled > 0 ? Double(logged) / Double(scheduled) : 1 }

    var body: some View {
        VStack(spacing: 6) {
            Text("Adherence")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
            ZStack {
                GaugeArc(fraction: 1)
                    .stroke(.white.opacity(0.25), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                GaugeArc(fraction: fraction)
                    .stroke(.white, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                VStack(spacing: 0) {
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.system(size: 36, weight: .bold)).vtTabular()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text("30 days")
                        .font(.system(size: 13)).foregroundStyle(.white.opacity(0.85))
                }
            }
            .frame(width: 120, height: 120)
            Text(scheduled > 0 ? "\(logged) of \(scheduled) scheduled days" : "Nothing scheduled yet")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(VT.sCardPad)
        .background(Color(light: "2F5D50", dark: "2F5D50"),
                    in: RoundedRectangle(cornerRadius: VT.rFocusCard, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Adherence \(Int((fraction * 100).rounded())) percent over 30 days")
    }
}

// MARK: - Biomarker summary

struct BiomarkerSummaryCard: View {
    let result: HealthScore.Result
    var onExplore: () -> Void

    var body: some View {
        Button(action: onExplore) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Your biomarkers")
                        .font(.system(size: 20, weight: .semibold)).foregroundStyle(VT.ink)
                    Spacer()
                    HStack(spacing: 3) {
                        Text("Explore").font(.system(size: 14)).foregroundStyle(VT.body)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(VT.micro)
                    }
                }
                HStack(spacing: 22) {
                    stat(result.total, "Total")
                    stat(result.optimal, "Optimal")
                    stat(result.normal, "Normal")
                    stat(result.outOfRange, "Out of Range")
                }
                segmentBar
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(VT.sCardPad).vtCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel("Your biomarkers. \(result.total) total, \(result.optimal) optimal, \(result.normal) normal, \(result.outOfRange) out of range. Opens Data.")
    }

    private func stat(_ n: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(n)").font(.system(size: 24, weight: .semibold)).vtTabular().foregroundStyle(VT.ink)
            Text(label).font(.system(size: 12)).foregroundStyle(VT.micro)
                .lineLimit(1).fixedSize()
        }
    }

    private var segmentBar: some View {
        GeometryReader { geo in
            let total = max(result.total, 1)
            let w = geo.size.width - 8   // two 4pt gaps
            HStack(spacing: 4) {
                if result.optimal > 0 {
                    Capsule().fill(VT.optimal).frame(width: w * Double(result.optimal) / Double(total))
                }
                if result.normal > 0 {
                    Capsule().fill(VT.normal).frame(width: w * Double(result.normal) / Double(total))
                }
                if result.outOfRange > 0 {
                    Capsule().fill(VT.outOfRange).frame(width: w * Double(result.outOfRange) / Double(total))
                }
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Setup row ("Help us know you better")

struct SetupCard: View {
    let title: String
    let symbol: String
    var action: () -> Void

    var body: some View {
        Button(action: { Haptics.press(); action() }) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium)).foregroundStyle(VT.ink)
                    .frame(width: 44, height: 44)
                    .background(VT.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title)
                    .font(.system(size: 16, weight: .medium)).foregroundStyle(VT.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(VT.micro)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .vtCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                HealthScoreCard(result: .init(score: 73, optimal: 12, normal: 6,
                                              outOfRange: 2, hasLabs: true))
                AdherenceHeroCard(logged: 26, scheduled: 29)
            }
            BiomarkerSummaryCard(result: .init(score: 73, optimal: 12, normal: 6,
                                               outOfRange: 2, hasLabs: true), onExplore: {})
            SetupCard(title: "Connect Apple Health", symbol: "heart.fill") {}
            SetupCard(title: "Scan your bloodwork", symbol: "doc.text.viewfinder") {}
        }
        .padding(VT.sSection)
    }
    .background(VT.canvas)
}
