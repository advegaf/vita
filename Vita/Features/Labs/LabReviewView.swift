import SwiftUI
import SwiftData

/// Review-and-edit before saving: Claude vision can misread a value, so every
/// extracted reading is editable here; the high/low/normal flag recomputes live
/// from the edited number. Save persists the panel + the original scan.
struct LabReviewView: View {
    @Environment(\.modelContext) private var context
    let dto: LabPanelDTO
    var scan: (data: Data, mediaType: String)?
    var onSaved: () -> Void

    @State private var rows: [LabPanelDTO.Value] = []
    @State private var seeded = false
    @FocusState private var editing: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VT.sSection) {
                ScreenHeader(eyebrow: "Review", title: "Check the readings.")
                metaCard
                if !dto.summary.isEmpty { summaryCard }
                valuesCard
                Text(dto.disclaimer.isEmpty
                     ? "Educational, not medical advice. Discuss results with your clinician."
                     : dto.disclaimer)
                    .font(.system(size: 12)).foregroundStyle(VT.micro)
                CharcoalPillButton(title: "Save panel", action: save)
            }
            .padding(VT.sSection)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .dismissesKeyboardOnTap()
        .background(VT.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if !seeded { rows = dto.values; seeded = true } }
    }

    private var metaCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                vtLead("Panel.", color: VT.why)
                Spacer()
                Text("\(rows.count) values").font(.system(size: 13)).foregroundStyle(VT.micro)
            }
            Text([dto.sourceLabName, displayDate].compactMap { $0 }.joined(separator: ", "))
                .font(.system(size: 15)).foregroundStyle(VT.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            vtLead("What stands out.", color: VT.dose)
            Text(dto.summary).font(.system(size: 15)).foregroundStyle(VT.body).lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    private var valuesCard: some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { i in
                valueRow(i)
                if i < rows.count - 1 {
                    Rectangle().fill(VT.hairline).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, VT.sCardPad).padding(.vertical, 6).vtCard()
    }

    private func valueRow(_ i: Int) -> some View {
        let v = rows[i]
        // Qualitative ("Negative") rows aren't numeric: muted dot, word shown read-only.
        let flag = v.hasNumericValue
            ? LabService.computeFlag(value: v.value, refLow: v.refLow, refHigh: v.refHigh)
            : LabFlag.unknown
        return HStack(spacing: 12) {
            Circle().fill(flag.color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(v.name.isEmpty ? v.markerKey : v.name)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.ink)
                    .lineLimit(2)                                    // uniform type: wrap, never shrink
                    .fixedSize(horizontal: false, vertical: true)
                Text("ref \(LabValueRefText.display(refLow: v.refLow, refHigh: v.refHigh, refText: v.refText)) \(v.unit)")
                    .font(.system(size: 12)).vtTabular().foregroundStyle(VT.micro)
            }
            Spacer()
            if v.hasNumericValue {
                TextField("", value: $rows[i].value, format: .number)
                    .keyboardType(.decimalPad).focused($editing)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 17, weight: .semibold)).vtTabular().foregroundStyle(VT.ink)
                    .frame(width: 76)
                Text(v.unit).font(.system(size: 13)).foregroundStyle(VT.micro).frame(minWidth: 36, alignment: .leading)
            } else {
                Text(v.qualitative ?? "n/a")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(VT.ink)
            }
        }
        .padding(.vertical, 12)
    }

    private var displayDate: String? {
        guard let d = LabService.parseDate(dto.panelDate) else { return nil }
        return d.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func save() {
        var edited = dto
        edited.values = rows
        LabService(context: context).savePanel(edited, scanData: scan?.data, mediaType: scan?.mediaType)
        Haptics.commit()
        onSaved()
    }
}

/// Shared reference-range display (used by review + detail).
enum LabValueRefText {
    static func display(refLow: Double?, refHigh: Double?, refText: String?) -> String {
        if let lo = refLow, let hi = refHigh { return "\(vtFormatNumber(lo))–\(vtFormatNumber(hi))" }
        if let t = refText, !t.isEmpty { return t }
        if let lo = refLow { return "≥ \(vtFormatNumber(lo))" }
        if let hi = refHigh { return "≤ \(vtFormatNumber(hi))" }
        return "n/a"
    }
}
