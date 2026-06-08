import SwiftUI

/// Diary dashboard card for labs: latest panel + flagged count, or a scan prompt.
/// Tapping navigates to the Labs list (the parent wraps it in a NavigationLink).
struct LabsCard: View {
    let panels: [LabPanel]

    private var latest: LabPanel? { panels.max { $0.effectiveDate < $1.effectiveDate } }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                vtLead("Labs.", color: VT.why)
                if let latest {
                    Text(latest.effectiveDate.formatted(.dateTime.month(.abbreviated).day().year()))
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(VT.ink)
                    Text(latest.flaggedCount > 0
                         ? "\(latest.flaggedCount) value\(latest.flaggedCount == 1 ? "" : "s") out of range"
                         : "All values in range")
                        .font(.system(size: 13)).foregroundStyle(latest.flaggedCount > 0 ? VT.overdue : VT.body)
                } else {
                    Text("Scan your bloodwork.")
                        .font(.system(size: 15)).foregroundStyle(VT.body)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(VT.micro)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
