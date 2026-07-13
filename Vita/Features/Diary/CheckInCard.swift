import SwiftUI

/// The dashboard check-in card: a compact prompt when today is un-logged, a tidy
/// summary once logged. Tapping anywhere opens the check-in sheet. The save bloom
/// plays here, keyed off `bloomToken` so it fires once per in-session save (never
/// on first load).
struct CheckInCard: View {
    let entry: DiaryEntry?
    let streak: Int
    var onTap: () -> Void
    /// M40: an emoji on the mood row opens the check-in with that mood preset.
    var onMood: ((Int) -> Void)? = nil

    private var logged: Bool { entry?.isLogged ?? false }

    var body: some View {
        if let e = entry, e.isLogged {
            Button(action: onTap) { summary(e) }
                .buttonStyle(.pressableCard)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
        } else {
            prompt   // the mood row needs per-emoji buttons, so no outer button
        }
    }

    /// The Lumina mood row: "How are you feeling today?" + big emoji quick-set.
    private static let moods: [(emoji: String, label: String, rating: Int)] = [
        ("😄", "Great", 9), ("🙂", "Good", 7), ("😐", "Okay", 5),
        ("😕", "Low", 3), ("😣", "Rough", 1),
    ]

    private var prompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How are you feeling today?")
                .font(.system(size: 18, weight: .bold)).foregroundStyle(VT.ink)
            HStack(spacing: 6) {
                ForEach(Self.moods, id: \.rating) { m in
                    Button {
                        Haptics.press()
                        (onMood ?? { _ in onTap() })(m.rating)
                    } label: {
                        Text(m.emoji)
                            .font(.system(size: 34))
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(VT.aiTint.opacity(0.55),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Feeling \(m.label)")
                }
            }
            Button(action: onTap) {
                Text("Full check-in")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(VT.ink)
                    .underline()
                    .frame(minHeight: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard(radius: VT.rFocusCard)
    }

    private func summary(_ e: DiaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                vtLead("Logged today.", color: VT.why)
                Spacer()
                Text("Edit").font(.system(size: 14, weight: .semibold)).foregroundStyle(VT.dose)
            }
            HStack(spacing: 16) {
                ForEach([DiaryMetric.energy, .sleep, .mood, .libido]) { m in
                    HStack(spacing: 5) {
                        Circle().fill(m.accent).frame(width: 7, height: 7)
                        Text("\(e.rating(for: m))")
                            .font(.system(size: 16, weight: .semibold)).vtTabular().foregroundStyle(VT.ink)
                    }
                }
            }
            HStack {
                Text(sideEffectLine(e)).font(.system(size: 13)).foregroundStyle(VT.micro)
                Spacer()
                if streak > 0 {
                    Text("\(streak)-day streak.")
                        .font(.system(size: 13, weight: .medium)).vtTabular().foregroundStyle(VT.micro)
                        .contentTransition(.numericText())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard(radius: VT.rFocusCard)
    }

    private func sideEffectLine(_ e: DiaryEntry) -> String {
        let n = e.sideEffectsRaw.count
        if n == 0 { return "No side-effects noted." }
        return n == 1 ? "1 side-effect noted." : "\(n) side-effects noted."
    }
}
