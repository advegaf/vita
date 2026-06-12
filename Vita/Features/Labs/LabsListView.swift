import SwiftUI
import SwiftData

/// The panels list (newest first) → panel detail. Hosts the scan entry.
struct LabsListView: View {
    @Environment(\.modelContext) private var context
    @Query private var allPanels: [LabPanel]
    @State private var showScan = false

    private var panels: [LabPanel] { allPanels.sorted { $0.effectiveDate > $1.effectiveDate } }

    var body: some View {
        let markers = LabSeries.trendedMarkers(panels: panels)
        return ScrollView {
            VStack(alignment: .leading, spacing: VT.sCardGap) {
                HStack(alignment: .firstTextBaseline) {
                    ScreenHeader(eyebrow: "Labs", title: "Your bloodwork.")
                    Spacer()
                    CircleIconButton(systemName: "plus", label: "Scan labs") { showScan = true }
                }
                if panels.isEmpty {
                    empty
                } else {
                    if !markers.trended.isEmpty {
                        sectionLabel("Trends")
                        markerCard(markers.trended, quiet: false)
                        sectionLabel("Panels").padding(.top, 6)
                    }
                    ForEach(panels) { panel in
                        NavigationLink { LabPanelDetailView(panel: panel) } label: { row(panel) }
                            .buttonStyle(.pressableCard)
                    }
                    if !markers.single.isEmpty {
                        sectionLabel("More markers").padding(.top, 6)
                        markerCard(markers.single, quiet: true)
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

    // MARK: Marker trends (M11)

    private func sectionLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 12, weight: .medium)).tracking(0.4)
            .textCase(.uppercase).foregroundStyle(VT.micro)
    }

    /// One grouped, hairline-divided card of marker rows (matches the panel detail's
    /// values card so the two surfaces read as one family).
    private func markerCard(_ markers: [LabMarkerSummary], quiet: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(markers.indices, id: \.self) { i in
                NavigationLink {
                    MarkerTrendView(markerKey: markers[i].markerKey, markerName: markers[i].name)
                } label: {
                    markerRow(markers[i], quiet: quiet)
                }
                .buttonStyle(.pressableCard)
                if i < markers.count - 1 { Rectangle().fill(VT.hairline).frame(height: 1) }
            }
        }
        .padding(.horizontal, VT.sCardPad).padding(.vertical, 6).vtCard()
    }

    private func markerRow(_ s: LabMarkerSummary, quiet: Bool) -> some View {
        HStack(spacing: 12) {
            Circle().fill(s.latestFlag.color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name)
                    .font(.system(size: quiet ? 14 : 15, weight: .semibold)).foregroundStyle(VT.ink)
                    .lineLimit(2)                                    // uniform type: wrap, never shrink
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(s.pointCount) result\(s.pointCount == 1 ? "" : "s")")
                    .font(.system(size: 12)).vtTabular().foregroundStyle(VT.micro)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(vtFormatNumber(s.latestValue)) \(s.unit)")
                    .font(.system(size: quiet ? 14 : 16, weight: quiet ? .medium : .semibold)).vtTabular()
                    .foregroundStyle(quiet ? VT.micro : (s.latestFlag.isOutOfRange ? VT.overdue : VT.ink))
                if !quiet, let delta = s.delta, abs(delta) > 0.0001 {
                    HStack(spacing: 3) {
                        Image(systemName: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(vtFormatNumber(abs(delta))) vs last")
                            .font(.system(size: 11, weight: .medium)).vtTabular()
                    }
                    .foregroundStyle(VT.micro)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(VT.micro)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(s.name), latest \(vtFormatNumber(s.latestValue)) \(s.unit), \(s.latestFlag.label)")
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
