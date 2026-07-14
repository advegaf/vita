import SwiftUI

/// The dashboard check-in card: a compact prompt when today is un-logged, a tidy
/// summary once logged. Tapping anywhere opens the check-in sheet. The save bloom
/// plays here, keyed off `bloomToken` so it fires once per in-session save (never
/// on first load).
struct CheckInCard: View {
    let entry: DiaryEntry?
    let streak: Int
    var onTap: () -> Void

    private var logged: Bool { entry?.isLogged ?? false }

    var body: some View {
        Button(action: onTap) {
            if let e = entry, e.isLogged { summary(e) } else { prompt }
        }
        .buttonStyle(.pressableCard)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var prompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            vtLead("Check in.", color: VT.dose)
            Text("A minute on how today felt.")
                .font(.system(size: 15)).foregroundStyle(VT.body)
            Text("Check in")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(VT.onInk)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(VT.ink, in: Capsule())
                .padding(.top, 2)
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
