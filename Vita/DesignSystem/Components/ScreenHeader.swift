import SwiftUI

extension String {
    /// nil when the string is empty/whitespace — for optional-chaining fallbacks
    /// ("preferredName?.nilIfEmpty ?? default").
    var nilIfEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

/// The standard screen header (M40, Journey-style): a huge bold title with a
/// calm gray subtitle underneath. The single source for the title+subtitle
/// pattern used by Stack / Diary / Chat / the entry sheets (Today keeps its
/// greeting mini-header + editorial hero; onboarding keeps StepScaffold).
struct ScreenHeader: View {
    let eyebrow: String   // the view/section name — rendered as the BIG title
    let title: String     // the status/descriptor sentence — rendered as the gray subtitle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(VFont.display(32, weight: .bold, relativeTo: .largeTitle))
                .tracking(-0.6)
                .foregroundStyle(VT.ink)
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(VT.body)
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
