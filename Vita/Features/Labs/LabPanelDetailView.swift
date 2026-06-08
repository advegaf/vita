import SwiftUI
import SwiftData
import QuickLook

/// One saved panel: values (out-of-range first), each with its range, flag color,
/// and a "vs last" delta; the overall read; the disclaimer; and "View original".
struct LabPanelDetailView: View {
    @Environment(\.modelContext) private var context
    let panel: LabPanel
    @State private var previewURL: URL?

    private var allPanels: [LabPanel] { LabService(context: context).panels() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VT.sSection) {
                header
                if !panel.summary.isEmpty { summaryCard }
                valuesCard
                Text(panel.disclaimer.isEmpty
                     ? "Educational, not medical advice. Discuss results with your clinician."
                     : panel.disclaimer)
                    .font(.system(size: 12)).foregroundStyle(VT.micro)
                if panel.scanData != nil {
                    Button { openOriginal() } label: {
                        Text("View original →").font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.dose)
                    }.buttonStyle(.plain)
                }
            }
            .padding(VT.sSection)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(VT.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($previewURL)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("PANEL").font(.system(size: 12, weight: .medium)).tracking(0.4)
                .textCase(.uppercase).foregroundStyle(VT.micro)
            Text("\(panel.effectiveDate.formatted(.dateTime.month(.abbreviated).day().year())).")
                .vtHeadlineStyle()
            if let lab = panel.sourceLabName {
                Text(lab).font(.system(size: 14)).foregroundStyle(VT.body)
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            vtLead("What stands out.", color: VT.dose)
            Text(panel.summary).font(.system(size: 15)).foregroundStyle(VT.body).lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    private var valuesCard: some View {
        let values = panel.orderedValues
        return VStack(spacing: 0) {
            ForEach(values.indices, id: \.self) { i in
                valueRow(values[i])
                if i < values.count - 1 { Rectangle().fill(VT.hairline).frame(height: 1) }
            }
        }
        .padding(.horizontal, VT.sCardPad).padding(.vertical, 6).vtCard()
    }

    private func valueRow(_ v: LabValue) -> some View {
        let delta = LabService.deltaVsPrevious(markerKey: v.markerKey, panel: panel, allPanels: allPanels)
        return HStack(spacing: 12) {
            Circle().fill(v.flag.color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(v.name.isEmpty ? v.markerKey : v.name)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.ink)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text("ref \(v.refDisplay) \(v.unit)")
                    .font(.system(size: 12)).vtTabular().foregroundStyle(VT.micro)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(vtFormatNumber(v.value)) \(v.unit)")
                    .font(.system(size: 16, weight: .semibold)).vtTabular()
                    .foregroundStyle(v.flag.isOutOfRange ? VT.overdue : VT.ink)
                if let delta, abs(delta) > 0.0001 {
                    HStack(spacing: 3) {
                        Image(systemName: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(vtFormatNumber(abs(delta))) vs last")
                            .font(.system(size: 11, weight: .medium)).vtTabular()
                    }
                    .foregroundStyle(VT.micro)
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func openOriginal() {
        guard let data = panel.scanData else { return }
        let ext = panel.scanMediaType == "application/pdf" ? "pdf" : "jpg"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lab-\(panel.id.uuidString)").appendingPathExtension(ext)
        try? data.write(to: url)
        previewURL = url
    }
}
