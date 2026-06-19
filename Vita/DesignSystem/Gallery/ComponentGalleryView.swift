import SwiftUI

/// A live gallery of every design-system component, on cream, with real sample data.
struct ComponentGalleryView: View {
    @State private var dim = "dose"
    @State private var blk = "midday"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VT.sSection) {
                section("Candy segmented control") {
                    CandySegmentedControl(segments: CandySegmentedControl.dimensionSegments, selection: $dim)
                    CandySegmentedControl(segments: CandySegmentedControl.dayBlockSegments, selection: $blk)
                }
                section("Cards") {
                    DoseCard(doseValue: "Draw to 20 units",
                             doseSub: "0.25 mg, subcutaneous",
                             protocolLine: "**5 days on, 2 off**, week **3 of 8**")
                    InfoCard(lead: "Timing.", leadColor: VT.timing,
                             text: "Mornings, **empty stomach**, **30 min** before food.")
                    InfoCard(lead: "Why.", leadColor: VT.why,
                             text: "A **GLP-1 receptor agonist**.",
                             footnote: "Educational, not medical advice.")
                }
                section("Pins (tap a knob)") {
                    PinRow(name: "Ipamorelin", dose: "100 mcg", time: "7:00", category: .muscleRecovery, state: .due)
                    PinRow(name: "BPC-157", dose: "250 mcg", time: "8:00", category: .muscleRecovery, state: .overdue)
                    PinRow(name: "CJC-1295", dose: "100 mcg", time: "10:30", category: .muscleRecovery, state: .taken)
                }
                section("Badges & dots") {
                    HStack(spacing: 16) {
                        RxBadge()
                        CategoryDot(category: .cognitive, size: 12)
                        CategoryDot(category: .sexualHealth, size: 12)
                        CategoryDot(category: .generalHealth, size: 12)
                    }
                }
                section("Meter & primary action") {
                    DotMeter(filled: 3, total: 4)
                    CharcoalPillButton(title: "Log today's dose") {}
                }
            }
            .padding(VT.sSection)
        }
        .scrollIndicators(.hidden)
        .background(VT.canvas)
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: VT.sCardGap) {
            Text(title)
                .font(.system(size: 12, weight: .semibold)).tracking(0.4)
                .textCase(.uppercase).foregroundStyle(VT.micro)
            content()
        }
    }
}

#Preview { ComponentGalleryView() }
