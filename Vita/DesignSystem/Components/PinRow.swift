import SwiftUI

enum DoseState: Equatable { case due, overdue, taken, skipped }

/// A checkmark as a single stroked path, so `.trim(from:0,to:p)` draws it on
/// (the SF Symbol can't trim). Two segments: down to the vertex, up to the tip.
struct Checkmark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: 0.16 * w, y: 0.53 * h))
        p.addLine(to: CGPoint(x: 0.42 * w, y: 0.75 * h))
        p.addLine(to: CGPoint(x: 0.84 * w, y: 0.28 * h))
        return p
    }
}

/// A dose "pin" in a time block, driven by external `state` (M4: derived from the
/// persistent log). Taking keeps the sacred north-star ritual: the ring fills the
/// accent, a checkmark stroke-draws, success haptic, the row settles to "done".
/// Skip is calm (dim + "skipped", soft haptic only); long-press → Skip/Undo.
struct PinRow: View {
    var name: String
    var dose: String          // "100 mcg"
    var time: String          // "7:00"
    var accent: Color = VT.dose
    var category: PeptideCategory = .other
    var state: DoseState = .due
    var cycleChip: String? = nil      // "wk 3/8" when this item is cycling
    var overdueText: String? = nil    // "overdue · 2h 15m" (preformatted by the parent)
    var onTake: () -> Void = {}
    var onSkip: () -> Void = {}
    var onUndo: () -> Void = {}
    var onOpenDetail: (() -> Void)? = nil   // tap the name/dose area → compound detail
    /// Rotation (injectables only): "→ right abdomen" before, the stamped site after.
    var siteText: String? = nil
    /// Long-press override: log at an explicit site instead of the suggestion.
    var onTakeAtSite: ((InjectionSite) -> Void)? = nil
    var onEdit: (() -> Void)? = nil   // long-press → "Adjust timing" (opens the dose sheet)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressed = false
    @State private var checkProgress: CGFloat = 0   // 0→1 draws the checkmark on

    private var isTaken: Bool { state == .taken }
    private var isSkipped: Bool { state == .skipped }
    private var isActed: Bool { isTaken || isSkipped }

    var body: some View {
        HStack(spacing: 12) {
            // Leading content opens detail on tap; the knob (its own Button) keeps
            // logging. Long-press context menu still works over the whole row.
            Button { onOpenDetail?() } label: {
                HStack(spacing: 12) {
                    CompoundTile(category: category, size: 34)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isActed ? VT.body : VT.ink)
                            .strikethrough(isTaken, color: VT.micro)
                            .lineLimit(2)
                        // Dose owns its own line (full width, never wraps); the cycle
                        // chip drops below it as a deliberate badge, not crowding it.
                        Text(isSkipped ? "skipped" : dose)
                            .font(.system(size: 13)).vtTabular()
                            .foregroundStyle(VT.body)
                            .lineLimit(1)
                        if let siteText, !isSkipped {
                            Text(siteText)
                                .font(.system(size: 12)).foregroundStyle(VT.micro)
                                .lineLimit(1)
                        }
                        if let cycleChip, !isActed {
                            CycleChip(text: cycleChip).padding(.top, 1)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressableCard)
            .disabled(onOpenDetail == nil)
            .accessibilityLabel("\(name), \(isSkipped ? "skipped" : dose)")
            .accessibilityHint("Opens details")

            Spacer()

            if !isSkipped {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(time)
                        .font(.system(size: 13, weight: .medium)).vtTabular()
                        .foregroundStyle(state == .overdue ? VT.overdue : VT.micro)
                    if state == .overdue {
                        Text(overdueText ?? "overdue")
                            .font(.system(size: 11, weight: .medium)).vtTabular()
                            .foregroundStyle(VT.overdue)
                    }
                }
            }

            knob
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .vtCard()
        .opacity(isTaken ? 0.6 : (isSkipped ? 0.55 : 1))
        .contextMenu {
            if isActed {
                Button { quiet(onUndo) } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
            } else {
                Button { quiet(onSkip) } label: { Label("Skip", systemImage: "minus.circle") }
                if let onTakeAtSite {
                    Menu {
                        ForEach(InjectionSite.allCases, id: \.self) { s in
                            Button(s.label) { Haptics.commit(); onTakeAtSite(s) }
                        }
                    } label: { Label("Log at site", systemImage: "scope") }
                }
            }
            if let onEdit {
                Divider()
                Button { onEdit() } label: { Label("Adjust timing", systemImage: "clock") }
            }
        }
        .animation(reduceMotion ? VMotion.reduced : VMotion.pinCommit, value: state)
        .onChange(of: state) { _, newValue in
            // One smooth fill: the ring blooms (opacity+scale, pinCommit) and the
            // check draws itself on in the same beat. No second bounce, no pop.
            if newValue == .taken {
                if reduceMotion { checkProgress = 1 }
                else { withAnimation(.easeOut(duration: 0.4)) { checkProgress = 1 } }
            } else {
                checkProgress = 0
            }
        }
        .onAppear { checkProgress = isTaken ? 1 : 0 }
    }

    private var knob: some View {
        Button(action: knobTap) {
            ZStack {
                Circle().stroke(ringColor, lineWidth: 2).opacity(isActed ? 0 : 1)
                Circle().fill(isSkipped ? VT.micro.opacity(0.35) : VT.why)
                    .opacity(isActed ? 1 : 0)
                    .scaleEffect(isTaken ? 1 : (isSkipped ? 1 : 0.7))   // fill blooms in
                if isTaken {
                    // In dark mode the knob fill (VT.why) flips to a light tan, so a
                    // white check would vanish — use a dark warm ink there instead.
                    Checkmark()
                        .trim(from: 0, to: checkProgress)
                        .stroke(VT.onInk,
                                style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                        .frame(width: 15, height: 15)
                } else if isSkipped {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(VT.body)
                        .transition(.opacity)
                }
            }
            .frame(width: 30, height: 30)
            .scaleEffect(pressed ? 0.94 : 1)
            .frame(width: 44, height: 44)          // >=44pt tap target around the 30pt knob
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !isActed { pressed = true } }
                .onEnded { _ in pressed = false }
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: pressed)
        .accessibilityLabel("\(name), \(dose), \(accessibilityState)")
    }

    private func knobTap() {
        if isActed {
            quiet(onUndo)                 // tap a taken/skipped knob → quiet undo
        } else {
            Haptics.commit()              // sacred take: success haptic, ring blooms + check draws on
            onTake()
        }
    }

    private func quiet(_ action: () -> Void) {
        Haptics.press()                   // soft only — the ritual stays exclusive to taking
        action()
    }

    private var ringColor: Color {
        switch state {
        case .due: VT.body.opacity(0.4)
        case .overdue: VT.overdue
        case .taken, .skipped: .clear
        }
    }

    private var accessibilityState: String {
        switch state {
        case .due: "tap to log"
        case .overdue: "overdue, tap to log"
        case .taken: "logged"
        case .skipped: "skipped"
        }
    }
}

#Preview {
    VStack(spacing: VT.sCardGap) {
        PinRow(name: "Ipamorelin", dose: "100 mcg", time: "7:00", category: .muscleRecovery, state: .due)
        PinRow(name: "CJC-1295 + Ipamorelin", dose: "0.5 mg (draw 20u)", time: "8:00",
               category: .muscleRecovery, state: .due, cycleChip: "Week 2/12")   // dose one line, chip below
        PinRow(name: "BPC-157", dose: "250 mcg", time: "8:00", category: .muscleRecovery,
               state: .overdue, overdueText: "2h 15m late")
        PinRow(name: "CJC-1295", dose: "100 mcg", time: "10:30", category: .muscleRecovery, state: .taken)
        PinRow(name: "Semax", dose: "300 mcg", time: "9:00", category: .cognitive, state: .skipped)
    }
    .padding(24)
    .background(VT.canvas)
}
