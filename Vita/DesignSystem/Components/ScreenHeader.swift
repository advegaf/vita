import SwiftUI

/// The standard screen header — a tiny UPPERCASE eyebrow over a period-punctuated
/// Inter Tight headline, left-aligned. The single source for the eyebrow+headline
/// pattern used by Stack / Diary / Chat / the entry sheets (Today keeps its
/// TopBarPill + count; onboarding keeps StepScaffold).
struct ScreenHeader: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow)
                .font(.system(size: 12, weight: .medium)).tracking(0.4)
                .textCase(.uppercase).foregroundStyle(VT.micro)
            Text(title).vtHeadlineStyle()
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: VT.sSection) {
        ScreenHeader(eyebrow: "Diary", title: "How are you today?")
        ScreenHeader(eyebrow: "Stack", title: "4 in your stack.")
    }
    .padding(VT.sSection)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(VT.canvas)
}
