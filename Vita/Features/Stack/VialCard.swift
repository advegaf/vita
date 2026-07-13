import SwiftUI

/// The vial-lifecycle card (M37): leads with the decision-relevant number (doses left),
/// then the supply bar, run-out projection, contents, and beyond-use awareness. All math
/// lives in `VialEngine`; this view only renders its `Status` and routes the actions.
struct VialCard: View {
    let item: ProtocolItem
    let vial: Vial
    let logs: [DoseLog]
    var iuPerMg: Double?
    var onStartSameSize: () -> Void        // reconstitute a fresh vial, same size/water
    var onAdjust: () -> Void               // open the setup sheet to change size/water
    var onOpenCalculator: () -> Void
    var onDismissLegacyNudge: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showNewVialConfirm = false

    private var status: VialEngine.Status {
        VialEngine.status(item: item, vial: vial, logs: logs, asOf: .now, iuPerMg: iuPerMg)
    }

    var body: some View {
        let s = status
        let showLegacyNudge = s.isLegacy && vial.legacyNudgeDismissedAt == nil

        VStack(alignment: .leading, spacing: 12) {
            vtLead("Vial.", color: VT.dose)

            if showLegacyNudge {
                legacyNudge
            } else {
                supplyHeadline(s)
            }

            contentsLine(s)
            budLine(s)
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(s))
        .confirmationDialog("Start a new vial?", isPresented: $showNewVialConfirm,
                            titleVisibility: .visible) {
            Button("Start new vial (same size and water)") { Haptics.commit(); onStartSameSize() }
            Button("Adjust size or water") { onAdjust() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This resets supply tracking to a fresh vial.")
        }
    }

    // MARK: Primary status

    @ViewBuilder
    private func supplyHeadline(_ s: VialEngine.Status) -> some View {
        if let line = VialEngine.supplyLine(s) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(line)
                    .font(.system(size: 17, weight: .semibold)).vtTabular()
                    .foregroundStyle(s.isOverdrawn ? VT.body : VT.ink)
                    .contentTransition(.numericText())
                if let n = s.dosesRemaining, n >= 1, !s.isOverdrawn {
                    Text("at current dose").font(.system(size: 13)).foregroundStyle(VT.micro)
                }
            }
            .animation(reduceMotion ? .none : VMotion.reduced, value: s.dosesRemaining)

            SupplyBar(fraction: s.fractionRemaining)
                .animation(reduceMotion ? .none : .spring(response: 0.35, dampingFraction: 0.85),
                           value: s.fractionRemaining)

            if let runOut = VialEngine.runOutLine(s) {
                Text(runOut).font(.system(size: 13)).vtTabular().foregroundStyle(VT.body)
            }
        }
    }

    private var legacyNudge: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("Start a new vial to begin supply tracking.")
                .font(.system(size: 14)).foregroundStyle(VT.body)
            Spacer(minLength: 8)
            Button(action: onDismissLegacyNudge) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold))
                    .foregroundStyle(VT.micro).frame(width: 28, height: 28)
                    .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
    }

    // MARK: Secondary lines

    /// M40: the vial's facts as dotted key-value rows (confirm-sheet pattern).
    @ViewBuilder
    private func contentsLine(_ s: VialEngine.Status) -> some View {
        VStack(spacing: 0) {
            DottedKVRow("Vial", "\(vtFormatNumber(vial.vialMg)) mg")
            DottedKVRow("Water", "\(vtFormatNumber(vial.waterMl)) mL")
            if let u = item.effectiveDrawUnits(on: .now) {
                DottedKVRow("Draw", "\(vtFormatUnits(u)) units")
            }
        }
    }

    @ViewBuilder
    private func budLine(_ s: VialEngine.Status) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(VialEngine.budLine(s))
                .font(.system(size: 12))
                .foregroundStyle(s.isPastBUD ? VT.overdue : VT.micro)
            if s.isPastBUD {
                Text("Many references suggest about \(s.budDays) days refrigerated. Check your source.")
                    .font(.system(size: 12)).foregroundStyle(VT.micro)
            }
        }
    }

    private var actions: some View {
        HStack {
            Button { showNewVialConfirm = true } label: {
                Text("Start new vial")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.ink)
                    .underline()
                    .frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Spacer()
            Button(action: onOpenCalculator) {
                Text("Open calculator →")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.ink)
                    .underline()
                    .frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }

    private func accessibilityText(_ s: VialEngine.Status) -> String {
        if s.isLegacy && vial.legacyNudgeDismissedAt == nil {
            return "Vial. Start a new vial to begin supply tracking."
        }
        var bits = ["Vial supply."]
        bits.append("About \(Int((s.fractionRemaining * 100).rounded())) percent remaining.")
        if let line = VialEngine.supplyLine(s) { bits.append(line + ".") }
        if let runOut = VialEngine.runOutLine(s) { bits.append(runOut + ".") }
        bits.append(VialEngine.budLine(s) + ".")
        return bits.joined(separator: " ")
    }
}

#Preview {
    let container = VitaContainer.make(inMemory: true)
    let ctx = container.mainContext
    let item = ProtocolItem()
    item.compoundSlug = "bpc-157"; item.displayName = "BPC-157"
    item.doseAmount = 250; item.doseUnitRaw = "mcg"
    ctx.insert(item)
    let rule = ScheduleRule()
    rule.frequencyRaw = "daily"; rule.timeSlotsMinutes = [480]
    ctx.insert(rule); rule.item = item; item.schedule = rule
    let vial = Vial()
    vial.compoundSlug = "bpc-157"; vial.vialMg = 5; vial.waterMl = 2
    vial.concentrationMgPerMl = 2.5
    vial.reconstitutedAt = Date(timeIntervalSinceNow: -12 * 86_400)
    ctx.insert(vial); vial.item = item; item.vial = vial

    return ScrollView {
        VialCard(item: item, vial: vial, logs: [], iuPerMg: nil,
                 onStartSameSize: {}, onAdjust: {}, onOpenCalculator: {}, onDismissLegacyNudge: {})
            .padding()
    }
    .background(VT.canvas)
    .modelContainer(container)
}
