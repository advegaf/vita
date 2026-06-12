import SwiftUI

/// A quiet 30-day adherence grid — one 7pt dot per calendar day, oldest → newest,
/// wrapping in rows. Speaks the DotMeter's dot language: taken = brown fill,
/// skipped = hollow brown ring, missed = faint clay, unscheduled/rest = near-
/// invisible. Never a chart, never a ring.
struct AdherenceGrid: View {
    let days: [AdherenceDay]
    var perRow: Int = 15

    private var rows: [[AdherenceDay]] {
        stride(from: 0, to: days.count, by: perRow).map {
            Array(days[$0..<min($0 + perRow, days.count)])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(rows[r].indices, id: \.self) { i in
                        dot(rows[r][i])
                    }
                }
            }
        }
        .accessibilityHidden(true)   // the parent card carries the spoken summary
    }

    @ViewBuilder
    private func dot(_ day: AdherenceDay) -> some View {
        switch day {
        case .taken:
            Circle().fill(VT.why).frame(width: 7, height: 7)
        case .skipped:
            Circle().stroke(VT.why, lineWidth: 1.5).frame(width: 7, height: 7)
        case .missed:
            Circle().fill(VT.overdue.opacity(0.35)).frame(width: 7, height: 7)
        case .notScheduled:
            Circle().fill(VT.ink.opacity(0.06)).frame(width: 7, height: 7)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 20) {
        AdherenceGrid(days:
            [.taken, .taken, .missed, .taken, .notScheduled, .notScheduled, .taken,
             .taken, .skipped, .taken, .taken, .missed, .notScheduled, .taken, .taken,
             .taken, .taken, .taken, .skipped, .notScheduled, .notScheduled, .taken,
             .taken, .taken, .missed, .taken, .taken, .notScheduled, .taken, .taken])
        AdherenceGrid(days: Array(repeating: .notScheduled, count: 26) + [.taken, .taken, .notScheduled, .taken])
    }
    .padding(24)
    .background(VT.canvas)
}
