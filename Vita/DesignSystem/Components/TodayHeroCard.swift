import SwiftUI

/// The Today hero (M38, Fields-style): a compact three-ring cluster beside a
/// calm status headline and a legend with the numbers. Replaces the DotMeter
/// row — doses today, streak, and 7-day adherence all live here now.
struct TodayHeroCard: View {
    var snapshot: TodayRingsSnapshot
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 18) {
            RingCluster(rings: [
                (VT.dose, appeared ? snapshot.doseProgress : 0.02),
                (VT.timing, appeared ? snapshot.streakProgress : 0.02),
                (VT.why, appeared ? snapshot.weekProgress : 0.02),
            ])
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.headline)
                        .font(VFont.display(20, weight: .bold, relativeTo: .title3))
                        .foregroundStyle(VT.ink)
                        .contentTransition(.numericText())
                    Text(snapshot.subline)
                        .font(.system(size: 13)).foregroundStyle(VT.micro)
                }
                VStack(alignment: .leading, spacing: 4) {
                    legendRow(VT.dose, "Doses", "\(snapshot.dosesActed)/\(snapshot.dosesTotal)")
                    legendRow(VT.timing, "Streak", "\(snapshot.streakDays)d")
                    legendRow(VT.why, "Week", snapshot.weekPercentText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(VT.sCardPad)
        .vtCard(radius: VT.rFocusCard)
        .onAppear {
            guard !appeared else { return }
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.spring(response: 0.9, dampingFraction: 0.85).delay(0.15)) {
                    appeared = true
                }
            }
        }
        .animation(reduceMotion ? VMotion.reduced : VMotion.pinCommit, value: snapshot)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(snapshot.headline) \(snapshot.dosesActed) of \(snapshot.dosesTotal) doses, \(snapshot.streakDays) day streak, week \(snapshot.weekPercentText).")
    }

    private func legendRow(_ color: Color, _ label: String, _ value: String) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(VT.body)
            Spacer(minLength: 12)
            Text(value).font(.system(size: 13, weight: .semibold)).vtTabular()
                .foregroundStyle(VT.ink)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: 132)
    }
}

/// Three concentric progress arcs, outermost first. Tracks are the ring color
/// at low opacity; caps are round. True zero renders as just the track (a
/// seeded cap floats like a stray dot); anything above zero keeps a 2% floor
/// so the cap stays visible.
struct RingCluster: View {
    var rings: [(color: Color, progress: Double)]

    private let lineWidth: CGFloat = 9
    private let gap: CGFloat = 4

    var body: some View {
        ZStack {
            ForEach(rings.indices, id: \.self) { i in
                let inset = CGFloat(i) * (lineWidth + gap)
                Circle()
                    .stroke(rings[i].color.opacity(0.16), lineWidth: lineWidth)
                    .padding(inset)
                Circle()
                    .trim(from: 0, to: rings[i].progress <= 0 ? 0 : max(0.02, min(1, rings[i].progress)))
                    .stroke(rings[i].color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(inset)
            }
        }
        .frame(width: 96, height: 96)
        .accessibilityHidden(true)
    }
}

#Preview("On track") {
    VStack(spacing: VT.sCardGap) {
        TodayHeroCard(snapshot: {
            var s = TodayRingsSnapshot()
            s.dosesActed = 1; s.dosesTotal = 2; s.streakDays = 6
            s.weekLogged = 11; s.weekScheduled = 12
            return s
        }())
        TodayHeroCard(snapshot: {
            var s = TodayRingsSnapshot()
            s.dosesTotal = 2; s.overdueCount = 1; s.streakDays = 12
            s.weekLogged = 9; s.weekScheduled = 12
            return s
        }())
    }
    .padding(VT.sSection)
    .background(VT.canvas)
}

#Preview("Dark") {
    TodayHeroCard(snapshot: {
        var s = TodayRingsSnapshot()
        s.dosesActed = 2; s.dosesTotal = 2; s.streakDays = 21
        s.weekLogged = 12; s.weekScheduled = 12
        return s
    }())
    .padding(VT.sSection)
    .background(VT.canvas)
    .preferredColorScheme(.dark)
}
