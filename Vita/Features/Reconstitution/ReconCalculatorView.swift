import SwiftUI

/// Standalone reconstitution calculator. Enter vial size, water, dose and syringe;
/// see "draw to X units" live. Prefills from a compound/item; an optional `onSave`
/// callback lets a stack item persist these as its vial (or a dose sheet take the
/// numbers back). With no callback it's a pure scratchpad. Educational, not medical.
struct ReconCalculatorView: View {
    var compound: CatalogCompound? = nil
    var item: ProtocolItem? = nil
    /// Explicit seeds (e.g. from an in-progress dose draft); win over compound/item prefill.
    var seedVialMg: Double? = nil
    var seedWaterMl: Double? = nil
    var seedSyringe: SyringeType? = nil
    var seedDoseMg: Double? = nil
    /// (vialMg, waterMl, syringe). Present → a "Save as vial" / "Use these" pill shows.
    var onSave: ((Double, Double, SyringeType) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var vialMg: Double = 5
    @State private var waterMl: Double = 2
    @State private var dose: Double = 0          // in the active display unit (mg or IU)
    @State private var useIU = false
    @State private var syringe: SyringeType = .u100

    @State private var typed = ""
    @State private var field: Field? = nil
    @FocusState private var focus: Field?
    private enum Field: Hashable { case dose, vial, water }

    /// The dose in milligrams for the math (IU mode converts at ~3 IU/mg).
    private var doseMg: Double { useIU ? ReconstitutionCalculator.mgFromIU(dose) : dose }
    private var result: ReconResult {
        ReconstitutionCalculator.result(doseMg: doseMg, vialMg: vialMg, waterMl: waterMl, syringe: syringe)
    }
    private var blocksSave: Bool {
        result.warnings.contains(.doseExceedsVial) || result.warnings.contains(.zeroInput)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VT.sSection) {
                    title
                    resultCard
                    vialCard
                    doseCard
                    if onSave != nil {
                        CharcoalPillButton(title: item != nil ? "Save as vial" : "Use these") {
                            onSave?(vialMg, waterMl, syringe)
                            Haptics.commit()
                            dismiss()
                        }
                        .opacity(blocksSave ? 0.4 : 1)
                        .disabled(blocksSave)
                        .padding(.top, 4)
                    }
                }
                .padding(VT.sSection)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(VT.canvas)
            .contentShape(Rectangle())
            .onTapGesture { if field != nil { commitTyped() } else { hideKeyboard() } }
            .onChange(of: focus) { _, f in if f == nil && field != nil { commitTyped() } }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(VT.ink)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: prefill)
    }

    // MARK: Result

    private var resultCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            vtLead("Draw.", color: VT.dose)
            if result.warnings.contains(.zeroInput) {
                Text("Enter vial size and water.")
                    .font(.vtDose).vtTabular().foregroundStyle(VT.micro)
            } else {
                Text("\(vtFormatUnits(result.roundedUnits)) units")
                    .font(.vtDose).vtTabular().foregroundStyle(VT.ink)
                    .contentTransition(.numericText())
                Text("\(vtFormatNumber(result.concentrationMgPerMl)) mg/mL (\(syringe.label))")
                    .font(.system(size: 14, weight: .semibold)).vtTabular().foregroundStyle(VT.dose)
            }
            ForEach(warningLines, id: \.self) { line in
                Text(line).font(.system(size: 13)).foregroundStyle(VT.overdue)
            }
            Text("Educational, not medical advice.")
                .font(.system(size: 12)).foregroundStyle(VT.micro)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    private var warningLines: [String] {
        result.warnings.compactMap {
            switch $0 {
            case .doseExceedsVial: "Dose is larger than the whole vial. Check your numbers."
            case .belowResolution: "Under 1 unit, hard to measure accurately."
            case .zeroInput: nil
            }
        }
    }

    // MARK: Vial card

    private var vialCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            vtLead("Vial.", color: VT.timing)
            numberRow("Vial size", value: $vialMg, suffix: "mg", step: 1, field: .vial)
            numberRow("Bac. water", value: $waterMl, suffix: "mL", step: 0.5, field: .water)
            HStack(spacing: 8) {
                ForEach(SyringeType.allCases, id: \.self) { s in
                    PillToggle(title: s.label, isOn: syringe == s) { syringe = s }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    // MARK: Dose card (mg ↔ IU)

    private var doseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                vtLead("Dose.", color: VT.dose)
                Spacer()
                Button {
                    withAnimation { useIU.toggle() }
                    // Convert the displayed amount so the underlying mg stays put.
                    Haptics.press()
                } label: {
                    Text(useIU ? "IU" : "mg")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(VT.dose)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(VT.canvas, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 0) {
                stepButton("minus") { stepDose(-1) }
                Spacer(minLength: 12)
                Group {
                    if field == .dose {
                        TextField("", text: $typed)
                            .font(.vtDose).vtTabular().foregroundStyle(VT.ink)
                            .keyboardType(.decimalPad).multilineTextAlignment(.center)
                            .focused($focus, equals: .dose)
                    } else {
                        Text("\(vtFormatNumber(dose)) \(useIU ? "IU" : "mg")")
                            .font(.vtDose).vtTabular().foregroundStyle(VT.ink)
                            .contentTransition(.numericText())
                            .onTapGesture { beginTyping(.dose, dose) }
                    }
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 12)
                stepButton("plus") { stepDose(1) }
            }
            if useIU {
                Text("≈ 3 IU per mg (HGH-class approximation).")
                    .font(.system(size: 13)).foregroundStyle(VT.micro)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("CALCULATOR")
                .font(.system(size: 12, weight: .medium)).tracking(0.4)
                .textCase(.uppercase).foregroundStyle(VT.micro)
            Text(compound.map { "\($0.name)." } ?? "Reconstitution.").vtHeadlineStyle()
        }
    }

    // MARK: Reusable number row (stepper + tap-to-type)

    private func numberRow(_ label: String, value: Binding<Double>, suffix: String,
                           step: Double, field f: Field) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(VT.body)
            Spacer()
            Button { value.wrappedValue = max(0, value.wrappedValue - step); Haptics.press() } label: {
                Image(systemName: "minus").font(.system(size: 13, weight: .bold)).foregroundStyle(VT.ink)
                    .frame(width: 32, height: 32).background(VT.canvas, in: Circle())
            }.buttonStyle(.plain)
            Group {
                if field == f {
                    TextField("", text: $typed)
                        .font(.system(size: 16, weight: .semibold)).vtTabular().foregroundStyle(VT.ink)
                        .keyboardType(.decimalPad).multilineTextAlignment(.center)
                        .focused($focus, equals: f)
                        .frame(minWidth: 64)
                } else {
                    Text("\(vtFormatNumber(value.wrappedValue)) \(suffix)")
                        .font(.system(size: 16, weight: .semibold)).vtTabular().foregroundStyle(VT.ink)
                        .frame(minWidth: 64)
                        .onTapGesture { beginTyping(f, value.wrappedValue) }
                }
            }
            Button { value.wrappedValue += step; Haptics.press() } label: {
                Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(VT.ink)
                    .frame(width: 32, height: 32).background(VT.canvas, in: Circle())
            }.buttonStyle(.plain)
        }
    }

    private func stepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.press(); action() }) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold)).foregroundStyle(VT.ink)
                .frame(width: 40, height: 40).background(VT.canvas, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func stepDose(_ dir: Double) {
        let inc: Double = useIU ? 0.5 : 0.25
        dose = max(0, dose + dir * inc)
    }

    // MARK: Typing

    private func beginTyping(_ f: Field, _ current: Double) {
        typed = vtFormatNumber(current)
        field = f
        DispatchQueue.main.async { focus = f }
    }

    private func commitTyped() {
        if let f = field, let v = Double(typed.replacingOccurrences(of: ",", with: ".")) {
            let clamped = max(0, v)
            switch f {
            case .dose: dose = clamped
            case .vial: vialMg = clamped
            case .water: waterMl = clamped
            }
        }
        field = nil
        focus = nil
    }

    // MARK: Prefill

    private func prefill() {
        if let v = item?.vial {
            vialMg = v.vialMg; waterMl = v.waterMl; syringe = v.syringe
        } else {
            vialMg = compound?.defaultVialSizeMg ?? compound?.availableVialSizesMg.first ?? 5
            waterMl = compound?.recommendedWaterMl ?? 2
        }
        // Dose in mg: from the item if set, else the compound midpoint.
        if let item, item.doseAmount > 0, let mg = item.doseUnit.toMg(item.doseAmount) {
            dose = mg
        } else if let lo = compound?.typicalDoseLow, let hi = compound?.typicalDoseHigh,
                  let unit = compound?.doseUnit, let mg = unit.toMg((lo + hi) / 2) {
            dose = mg
        }
        // Explicit seeds (dose sheet) override the catalog/item prefill.
        if let v = seedVialMg, v > 0 { vialMg = v }
        if let w = seedWaterMl, w > 0 { waterMl = w }
        if let s = seedSyringe { syringe = s }
        if let d = seedDoseMg, d > 0 { dose = d }
    }
}

#Preview {
    ReconCalculatorView()
}
