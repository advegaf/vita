import SwiftUI

/// The NEXT pending dose as a solid black card (M40, Journey-style): the
/// design language marks "current" with black. White text, compound tile,
/// a radio knob that logs (same ritual semantics as PinRow's knob), and a
/// chevron into the detail.
struct NextDoseCard: View {
    var name: String
    var doseLine: String        // "250 mcg • 10u"
    var timeText: String        // "8:00 AM"
    var siteLine: String?       // "→ left thigh"
    var category: PeptideCategory
    var overdueText: String?    // "1h 5m late" (nil when on time)
    var onLog: () -> Void
    var onOpenDetail: () -> Void

    @State private var pressed = false

    var body: some View {
        HStack(spacing: 14) {
            knob
            CompoundTile(category: category, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(VT.onInk)
                    .lineLimit(2)
                Text(overdueText.map { "Planned at \(timeText) • \($0)" } ?? "Planned at \(timeText)")
                    .font(.system(size: 13, weight: .medium)).vtTabular()
                    .foregroundStyle(overdueText == nil ? VT.onInk.opacity(0.62) : VT.timing)
                Text(siteLine.map { "\(doseLine)  \($0)" } ?? doseLine)
                    .font(.system(size: 13)).vtTabular()
                    .foregroundStyle(VT.onInk.opacity(0.78))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onOpenDetail() }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(VT.onInk.opacity(0.5))
        }
        .padding(.horizontal, 16).padding(.vertical, 16)
        .background(VT.ink, in: RoundedRectangle(cornerRadius: VT.rFocusCard, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        .accessibilityElement(children: .contain)
    }

    /// The log knob: an open white ring that fills on tap.
    private var knob: some View {
        Button {
            pressed = true
            onLog()
        } label: {
            ZStack {
                Circle().strokeBorder(VT.onInk.opacity(0.55), lineWidth: 2)
                if pressed {
                    Circle().fill(VT.onInk).padding(5)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(VT.ink)
                }
            }
            .frame(width: 30, height: 30)
            .contentShape(Circle().inset(by: -8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log \(name)")
    }
}

#Preview {
    VStack(spacing: VT.sCardGap) {
        NextDoseCard(name: "BPC-157", doseLine: "250 mcg • 10u", timeText: "8:00 AM",
                     siteLine: "→ left thigh", category: .muscleRecovery,
                     overdueText: nil, onLog: {}, onOpenDetail: {})
        NextDoseCard(name: "TB-500", doseLine: "0.5 mg • 10u", timeText: "9:00 AM",
                     siteLine: nil, category: .muscleRecovery,
                     overdueText: "1h 5m late", onLog: {}, onOpenDetail: {})
    }
    .padding(VT.sSection)
    .background(VT.canvas)
}
