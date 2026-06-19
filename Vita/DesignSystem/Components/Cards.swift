import SwiftUI

/// Generic white info card: a period-punctuated colored lead word inline with gray body.
struct InfoCard: View {
    var lead: String
    var leadColor: Color
    var text: String
    var footnote: String? = nil   // e.g. the standing "Educational, not medical advice."

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            (vtLead(lead, color: leadColor) + Text(" ") + vtBody(text))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let footnote {
                Text(footnote)
                    .font(.system(size: 12))
                    .foregroundStyle(VT.micro)
            }
        }
        .padding(VT.sCardPad)
        .vtCard()
    }
}

/// Card 1 — "Dose." (cyan). Deliberately the tallest card. Fuses Dose + Protocol
/// (the user's "tightly paired" steer) separated by a warm hairline.
struct DoseCard: View {
    var doseValue: String        // e.g. "Draw to 20 units"
    var doseSub: String          // e.g. "0.25 mg · subcutaneous"
    var protocolLine: String     // e.g. "**5 days on, 2 off** · week **3 of 8**"
    var onOpenCalculator: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            vtLead("Dose.", color: VT.dose)
            Text(doseValue)
                .font(.vtDose).vtTabular()
                .foregroundStyle(VT.ink)
            Text(doseSub).font(.system(size: 15)).foregroundStyle(VT.body)

            Rectangle().fill(VT.hairline).frame(height: 1).padding(.vertical, 4)

            Text("PROTOCOL")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(VT.micro)
            vtBody(protocolLine).vtTabular()

            Button(action: onOpenCalculator) {
                Text("Open calculator →")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(VT.dose)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad)
        .vtCard()
    }
}

/// Home next-dose focus card (radius 24). Live countdown + docked charcoal pill.
struct FocusCard: View {
    var peptide: String
    var doseLine: String         // "Draw to 20 units · 0.25 mg"
    var due: Date
    var onLog: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                vtLead("Up next.", color: VT.dose, size: 14)
                CountdownText(target: due)
                    .font(.system(size: 14, weight: .semibold)).vtTabular()
                    .foregroundStyle(VT.body)
            }
            Text(peptide).font(.vtPicker).foregroundStyle(VT.ink)
            Text(doseLine).font(.system(size: 15)).vtTabular().foregroundStyle(VT.body)
            CharcoalPillButton(title: "Log dose", action: onLog)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad)
        .vtCard(radius: VT.rFocusCard)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: VT.sCardGap) {
            FocusCard(peptide: "Semaglutide", doseLine: "0.25 mg (Draw to 20 units)",
                      due: Date().addingTimeInterval(3600 * 3 + 1200))
            DoseCard(doseValue: "Draw to 20 units",
                     doseSub: "0.25 mg, subcutaneous",
                     protocolLine: "**5 days on, 2 off**, week **3 of 8**")
            InfoCard(lead: "Timing.", leadColor: VT.timing,
                     text: "Mornings, on an **empty stomach**. At least **30 min** before food.")
            InfoCard(lead: "Why.", leadColor: VT.why,
                     text: "A **GLP-1 receptor agonist** that slows gastric emptying and blunts appetite signals.")
        }
        .padding(VT.sSection)
    }
    .background(VT.canvas)
}
