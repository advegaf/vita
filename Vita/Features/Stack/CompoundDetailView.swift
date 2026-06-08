import SwiftUI
import SwiftData

/// Seed-data detail card. Catalog mode (`item == nil`) → "Add to stack".
/// Stack mode (`item != nil`) → editable dose + remove. Honest: shows the
/// educational range; real "draw to X units" needs a vial (set in the dose sheet
/// or the reconstitution calculator).
struct CompoundDetailView: View {
    let compound: CatalogCompound
    var item: ProtocolItem? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var inStack = false
    @State private var setupDraft: DoseDraft?
    @State private var showCalculator = false

    private var isStackMode: Bool { item != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VT.sCardGap) {
                header
                doseCard
                timingCard
                InfoCard(lead: "Why.", leadColor: VT.why,
                         text: compound.about ?? compound.mechanismBlurb ?? "Educational information about this compound.",
                         footnote: "Educational, not medical advice.")
                action
            }
            .padding(VT.sSection)
        }
        .scrollIndicators(.hidden)
        .background(VT.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { inStack = StackService(context: context).isInStack(compound.slug) }
        .sheet(item: $setupDraft) { d in
            DoseSetupSheet(draft: d, rangeText: compound.doseRangeText, about: compound.about) {
                inStack = StackService(context: context).isInStack(compound.slug)
            }
        }
        .sheet(isPresented: $showCalculator) {
            ReconCalculatorView(compound: compound, item: item,
                                onSave: item != nil ? { saveVial($0, $1, $2) } : nil)
        }
    }

    private func openSetup() {
        let svc = StackService(context: context)
        if let item { setupDraft = svc.draft(for: item) }
        else if let existing = svc.item(forSlug: compound.slug) { setupDraft = svc.draft(for: existing) }
        else { setupDraft = svc.draft(for: compound) }
    }

    private func saveVial(_ vialMg: Double, _ waterMl: Double, _ syringe: SyringeType) {
        guard let item else { return }
        let svc = StackService(context: context)
        var d = svc.draft(for: item)
        d.hasVial = true; d.vialMg = vialMg; d.waterMl = waterMl; d.syringe = syringe
        svc.commit(d)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PEPTIDE")
                .font(.system(size: 12, weight: .medium)).tracking(0.4)
                .textCase(.uppercase).foregroundStyle(VT.micro)
            HStack(spacing: 8) {
                Text(compound.name)
                    .font(.vtPicker).foregroundStyle(VT.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if compound.rxStatus == .rx { RxBadge() }
                Spacer(minLength: 0)
            }
            if !compound.subtitle.isEmpty {
                Text(compound.subtitle).font(.system(size: 14)).foregroundStyle(VT.body)
            }
        }
    }

    // MARK: Dose card (mode-aware)

    private var doseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            vtLead("Dose.", color: VT.dose)

            if isStackMode, let item {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.effectiveDoseText(on: .now)).font(.vtDose).vtTabular().foregroundStyle(VT.ink)
                    Spacer()
                    Button(action: openSetup) {
                        Text("Edit dose")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(VT.dose)
                    }.buttonStyle(.plain)
                }
                if let units = item.effectiveDrawUnitsText(on: .now) {
                    Text(units.replacingOccurrences(of: "draw ", with: "Draw to "))
                        .font(.system(size: 14, weight: .semibold)).vtTabular().foregroundStyle(VT.dose)
                }
                if let next = ScheduleService.nextTitration(for: item, on: .now) {
                    Text("→ next: \(vtFormatNumber(next.dose)) \(item.doseUnit.label) in \(next.weeksAway) wk\(next.weeksAway == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(VT.dose)
                }
                if let rule = item.schedule, rule.hasCycle,
                   let status = ScheduleService.cycleStatus(for: rule, on: .now) {
                    CycleRibbon(status: status).padding(.top, 6)
                }
            } else {
                Text(compound.doseRangeText ?? "Educational range varies")
                    .font(.vtDose).vtTabular().foregroundStyle(VT.ink)
            }
            if let range = compound.doseRangeText {
                Text("Educational range \(range)")
                    .font(.system(size: 13)).foregroundStyle(VT.micro)
            }

            Rectangle().fill(VT.hairline).frame(height: 1).padding(.vertical, 4)
            Text("PROTOCOL")
                .font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(VT.micro)
            Text(protocolLine).font(.system(size: 15)).foregroundStyle(VT.body)

            if isStackMode, let item, let rule = item.schedule, rule.hasTitration {
                Rectangle().fill(VT.hairline).frame(height: 1).padding(.vertical, 4)
                Text("TITRATION")
                    .font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(VT.micro)
                TitrationLadder(steps: ScheduleService.titrationLadder(for: item, on: .now))
                    .padding(.top, 2)
            }

            Button { showCalculator = true } label: {
                Text("Open calculator →")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.dose)
            }
            .buttonStyle(.plain).padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad)
        .vtCard()
    }

    private var protocolLine: String {
        if let item, !item.cadenceLabel.isEmpty { return item.cadenceLabel }
        return compound.defaultCadenceLabel.map { "Typically \($0)." } ?? "Set when added to your stack."
    }

    // MARK: Timing card

    @ViewBuilder
    private var timingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            (vtLead("Timing.", color: VT.timing) + Text(" ") + vtBody(timingText))
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: openSetup) {
                Text("Adjust timing reminder →")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.timing)
            }
            .buttonStyle(.plain)
        }
        .padding(VT.sCardPad).vtCard()
    }

    private var timingText: String {
        let cadence = compound.defaultCadenceLabel ?? "as part of your plan"
        let route = compound.primaryRoute?.label ?? "subcutaneous"
        return "Typically **\(cadence)**, \(route)."
    }

    // MARK: Action

    @ViewBuilder
    private var action: some View {
        if isStackMode {
            Button(role: .destructive) {
                if let item { StackService(context: context).remove(item); dismiss() }
            } label: {
                Text("Remove from stack")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(VT.overdue)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
            }
            .buttonStyle(.plain).padding(.top, 4)
        } else if inStack {
            HStack(spacing: 8) { Image(systemName: "checkmark"); Text("In stack") }
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 17)
                .background(VT.why, in: Capsule()).padding(.top, 4)
        } else {
            CharcoalPillButton(title: "Add to stack") { openSetup() }.padding(.top, 4)
        }
    }
}
