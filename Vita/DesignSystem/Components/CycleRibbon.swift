import SwiftUI

/// Cycle progress for the detail Dose card: "Week 3 of 8" + a thin bar +
/// "N days left", or "Resting". Resting reads quiet (micro), never
/// alarming; on reads cyan (dose/protocol context). Never a ring (the design
/// forbids progress rings). Driven by `ScheduleService.CycleStatus`; no SwiftData.
struct CycleRibbon: View {
    let status: ScheduleService.CycleStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var resting: Bool { status.phase == .resting }
    private var tint: Color { resting ? VT.micro : VT.dose }
    private var unitWord: String { status.unitIsWeeks ? "week" : "day" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 6, height: 6)
                Text(resting ? "Resting" : "\(unitWord.capitalized) \(status.indexInUnit) of \(status.totalUnits)")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(VT.ink)
                Spacer()
                Text("\(status.daysLeftInPhase) day\(status.daysLeftInPhase == 1 ? "" : "s") left")
                    .font(.system(size: 12)).vtTabular().foregroundStyle(VT.micro)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(VT.ink.opacity(0.08)).frame(height: 4)
                    Capsule().fill(tint).frame(width: max(0, geo.size.width * status.fraction), height: 4)
                }
            }
            .frame(height: 4)
            .animation(reduceMotion ? VMotion.reduced : VMotion.segmentExpand, value: status.fraction)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(resting
            ? "Resting, \(status.daysLeftInPhase) days left"
            : "On, \(unitWord) \(status.indexInUnit) of \(status.totalUnits), \(status.daysLeftInPhase) days left")
    }
}

/// Compact cycle chip for Stack/Today rows ("wk 3/8" / "rest"). Mirrors the RxBadge
/// capsule grammar so it sits beside it naturally.
struct CycleChip: View {
    let text: String
    var resting: Bool = false
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold)).vtTabular()
            .foregroundStyle(resting ? VT.micro : VT.dose)
            // Never wrap "wk 12/52" to two lines: demand intrinsic width so the
            // sibling subtitle compresses instead of the chip.
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background((resting ? VT.micro : VT.dose).opacity(0.12), in: Capsule())
            .accessibilityLabel(resting ? "Resting" : "Cycle \(text)")
    }
}

#Preview {
    VStack(alignment: .leading, spacing: VT.sSection) {
        CycleRibbon(status: .init(phase: .on, unitIsWeeks: true, indexInUnit: 3, totalUnits: 8,
                                  fraction: 0.25, daysLeftInPhase: 5, resumesOn: nil, chipText: "wk 3/8"))
        CycleRibbon(status: .init(phase: .resting, unitIsWeeks: true, indexInUnit: 1, totalUnits: 8,
                                  fraction: 0.8, daysLeftInPhase: 2, resumesOn: Date(), chipText: "rest"))
        HStack { CycleChip(text: "wk 3/8"); CycleChip(text: "rest", resting: true) }
    }
    .padding(VT.sSection).vtCard().padding(VT.sSection).background(VT.canvas)
}
