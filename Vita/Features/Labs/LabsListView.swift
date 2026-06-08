import SwiftUI
import SwiftData

/// The panels list (newest first) → panel detail. Hosts the scan entry.
struct LabsListView: View {
    @Environment(\.modelContext) private var context
    @Query private var allPanels: [LabPanel]
    @State private var showScan = false

    private var panels: [LabPanel] { allPanels.sorted { $0.effectiveDate > $1.effectiveDate } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VT.sCardGap) {
                HStack(alignment: .firstTextBaseline) {
                    ScreenHeader(eyebrow: "Labs", title: "Your bloodwork.")
                    Spacer()
                    CircleIconButton(systemName: "plus", label: "Scan labs") { showScan = true }
                }
                if panels.isEmpty {
                    empty
                } else {
                    ForEach(panels) { panel in
                        NavigationLink { LabPanelDetailView(panel: panel) } label: { row(panel) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(VT.sSection)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(VT.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showScan) { LabScanFlow() }
    }

    private func row(_ panel: LabPanel) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text([panel.sourceLabName, dateText(panel)].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(VT.ink).lineLimit(1)
                Text(panel.flaggedCount > 0
                     ? "\(panel.flaggedCount) out of range · \((panel.values ?? []).count) values"
                     : "\((panel.values ?? []).count) values, all in range")
                    .font(.system(size: 13)).foregroundStyle(VT.body)
            }
            Spacer(minLength: 4)
            if panel.flaggedCount > 0 {
                Text("\(panel.flaggedCount)")
                    .font(.system(size: 13, weight: .bold)).vtTabular().foregroundStyle(.white)
                    .frame(minWidth: 22, minHeight: 22)
                    .background(VT.overdue, in: Circle())
            }
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(VT.micro)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .vtCard()
    }

    private func dateText(_ panel: LabPanel) -> String {
        panel.effectiveDate.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Text("No labs yet.")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(VT.ink)
            Text("Scan a photo or PDF of your bloodwork and Vita will read it.")
                .font(.system(size: 15)).foregroundStyle(VT.body).multilineTextAlignment(.center)
            CharcoalPillButton(title: "Scan labs") { showScan = true }.frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity).padding(.top, 48)
    }
}
