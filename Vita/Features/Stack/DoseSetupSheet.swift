import SwiftUI

/// Captures dose · frequency · time(s) when adding a peptide, and reopens to edit.
/// Finalizes a `DoseDraft` through `StackService.commit`.
struct DoseSetupSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State var draft: DoseDraft
    var rangeText: String? = nil          // "250-500 mcg" educational caption
    var about: String? = nil              // 2-3 sentence educational description
    var onCommit: () -> Void = {}

    @State private var typing = false
    @State private var typed = ""
    @State private var showCalculator = false
    @State private var advancedExpanded = false
    @State private var detent: PresentationDetent = .medium
    @FocusState private var doseFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: VT.sSection) {
                    title
                    if let about, !about.isEmpty { aboutSection(about) }
                    doseSection
                    if draft.doseUnit.supportsUnitTracking { vialSection }
                    frequencySection
                    if draft.frequency == .weekly { weekdaySection }
                    if draft.frequency != .prn { timesSection }
                    advancedSection.id("advanced")
                    CharcoalPillButton(title: draft.isEditing ? "Save" : "Add to stack") {
                        StackService(context: context).commit(draft)
                        Haptics.commit()
                        onCommit()
                        dismiss()
                    }
                    .padding(.top, 4)
                }
                .padding(VT.sSection)
            }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.environment["VITA_DOSESHEET_ADVANCED"] == "1" {
                    detent = .large
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation { proxy.scrollTo("advanced", anchor: .top) }
                    }
                }
                #endif
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(VT.canvas)
        .contentShape(Rectangle())
        .onTapGesture { if typing { commitTyped() } else { hideKeyboard() } }  // tap outside commits + dismisses
        .onChange(of: doseFocused) { _, focused in
            if !focused && typing { commitTyped() }       // blur commits
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showCalculator) {
            ReconCalculatorView(
                seedVialMg: draft.vialMg, seedWaterMl: draft.waterMl, seedSyringe: draft.syringe,
                seedDoseMg: draft.doseUnit.toMg(draft.doseAmount)
            ) { vialMg, waterMl, syringe in
                draft.hasVial = true
                draft.vialMg = vialMg; draft.waterMl = waterMl; draft.syringe = syringe
            }
        }
    }

    // MARK: Vial (optional, drives syringe units)

    @ViewBuilder
    private var vialSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                vtLead("Units.", color: VT.dose)
                Spacer()
                if draft.hasVial {
                    Button("Remove vial") { withAnimation { draft.hasVial = false } }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(VT.micro)
                }
            }

            if draft.hasVial {
                vialField("Vial", value: $draft.vialMg, suffix: "mg", step: 1)
                vialField("Bac. water", value: $draft.waterMl, suffix: "mL", step: 0.5)
                HStack(spacing: 8) {
                    ForEach(SyringeType.allCases, id: \.self) { s in
                        PillToggle(title: s.label, isOn: draft.syringe == s) { draft.syringe = s }
                    }
                }
                if let units = draft.drawUnitsText {
                    Text(units)
                        .font(.system(size: 15, weight: .semibold)).vtTabular()
                        .foregroundStyle(VT.dose)
                } else {
                    Text("Enter vial size and water to see units.")
                        .font(.system(size: 13)).foregroundStyle(VT.micro)
                }
                Button { showCalculator = true } label: {
                    Text("Open calculator →")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.dose)
                }
                .buttonStyle(.plain).padding(.top, 2)
            } else {
                Button {
                    withAnimation {
                        draft.hasVial = true
                        if draft.vialMg == 0 { draft.vialMg = 5 }
                        if draft.waterMl == 0 { draft.waterMl = 2 }
                    }
                    Haptics.press()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                        Text("Add vial for unit tracking")
                    }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.dose)
                }
                .buttonStyle(.plain)
                Text("Track doses as syringe units (e.g. 10u) instead of mg.")
                    .font(.system(size: 13)).foregroundStyle(VT.micro)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    private func vialField(_ label: String, value: Binding<Double>, suffix: String, step: Double) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(VT.body)
            Spacer()
            Button { value.wrappedValue = max(0, value.wrappedValue - step); Haptics.press() } label: {
                Image(systemName: "minus").font(.system(size: 13, weight: .bold)).foregroundStyle(VT.ink)
                    .frame(width: 32, height: 32).background(VT.canvas, in: Circle())
            }.buttonStyle(.plain)
            Text("\(vtFormatNumber(value.wrappedValue)) \(suffix)")
                .font(.system(size: 16, weight: .semibold)).vtTabular().foregroundStyle(VT.ink)
                .frame(minWidth: 64)
            Button { value.wrappedValue += step; Haptics.press() } label: {
                Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(VT.ink)
                    .frame(width: 32, height: 32).background(VT.canvas, in: Circle())
            }.buttonStyle(.plain)
        }
    }

    private func aboutSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            vtLead("About.", color: VT.why)
            Text(text)
                .font(.system(size: 15)).foregroundStyle(VT.body)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            Text("Educational, not medical advice.")
                .font(.system(size: 12)).foregroundStyle(VT.micro)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(draft.isEditing ? "ADJUST" : "ADD")
                .font(.system(size: 12, weight: .medium)).tracking(0.4)
                .textCase(.uppercase).foregroundStyle(VT.micro)
            Text("\(draft.displayName).").vtHeadlineStyle()
        }
    }

    // MARK: Dose

    private var doseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            vtLead("Dose.", color: VT.dose)
            // Edge-anchored: − far left, + far right, value centered between them.
            HStack(spacing: 0) {
                stepButton("minus") { step(-1) }
                Spacer(minLength: 12)
                Group {
                    if typing {
                        TextField("", text: $typed)
                            .font(.vtDose).vtTabular().foregroundStyle(VT.ink)
                            .keyboardType(.decimalPad).multilineTextAlignment(.center)
                            .focused($doseFocused)
                    } else {
                        Text("\(vtFormatNumber(draft.doseAmount)) \(draft.doseUnit.label)")
                            .font(.vtDose).vtTabular().foregroundStyle(VT.ink)
                            .contentTransition(.numericText())
                            .onTapGesture { beginTyping() }
                    }
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 12)
                stepButton("plus") { step(1) }
            }
            if let rangeText {
                Text("Educational range \(rangeText)")
                    .font(.system(size: 13)).foregroundStyle(VT.micro)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    private func beginTyping() {
        typed = vtFormatNumber(draft.doseAmount)
        typing = true
        DispatchQueue.main.async { doseFocused = true }
    }

    // MARK: Frequency

    private var frequencySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            vtLead("Frequency.", color: VT.timing)
            let cols = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(Frequency.allCases, id: \.self) { f in
                    PillToggle(title: f.label, isOn: draft.frequency == f) {
                        withAnimation(VMotion.segmentExpand) { draft.frequency = f }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    private var weekdaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ON THESE DAYS")
                .font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(VT.micro)
            HStack(spacing: 0) {
                ForEach(1...7, id: \.self) { wd in
                    let names = ["", "S", "M", "T", "W", "T", "F", "S"]
                    let on = draft.weekdays.contains(wd)
                    Button {
                        if on { draft.weekdays.remove(wd) } else { draft.weekdays.insert(wd) }
                        Haptics.press()
                    } label: {
                        Text(names[wd])
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(on ? .white : VT.body)
                            .frame(width: 40, height: 40)
                            .background(on ? VT.timing : VT.ink.opacity(0.06), in: Circle())
                            .frame(maxWidth: .infinity, minHeight: 44)   // even distribution + 44pt tap
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Self.fullDay(wd))
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    // MARK: Times

    private var timesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            vtLead("Timing.", color: VT.why)
            HStack(spacing: 8) {
                ForEach(DayBlock.allCases, id: \.self) { block in
                    PillToggle(title: block.title, isOn: draft.blocks.contains(block), onColor: VT.why) {
                        var b = draft.blocks
                        if b.contains(block) { b.remove(block) } else { b.insert(block) }
                        draft.blocks = b
                    }
                }
            }
            ForEach(draft.times.indices, id: \.self) { i in
                timeRow(i)
            }
            if draft.times.isEmpty {
                Text("Pick a time of day above.")
                    .font(.system(size: 13)).foregroundStyle(VT.micro)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    private func timeRow(_ i: Int) -> some View {
        let binding = Binding<Date>(
            get: { dateFromMinutes(draft.times[i]) },
            set: { draft.times[i] = minutesFrom($0); draft.times.sort() }
        )
        return HStack {
            Image(systemName: blockIcon(DayBlock.from(minutes: draft.times[i])))
                .foregroundStyle(VT.micro)
            DatePicker("", selection: binding, displayedComponents: .hourAndMinute)
                .labelsHidden()
            Spacer()
        }
    }

    // MARK: Helpers

    private func stepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.press(); action() }) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold)).foregroundStyle(VT.ink)
                .frame(width: 40, height: 40).background(VT.canvas, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func step(_ dir: Double) {
        let inc: Double = switch draft.doseUnit { case .mcg: 50; case .mg: 0.25; case .iu: 0.5 }
        draft.doseAmount = max(0, draft.doseAmount + dir * inc)
    }

    private func commitTyped() {
        if let v = Double(typed.replacingOccurrences(of: ",", with: ".")) { draft.doseAmount = max(0, v) }
        typing = false
        doseFocused = false
    }

    private func dateFromMinutes(_ m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }
    private func minutesFrom(_ d: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
    private func blockIcon(_ b: DayBlock) -> String { b.symbol }

    private static func fullDay(_ wd: Int) -> String {
        ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][wd]
    }

    // MARK: Advanced (cycle + titration, M9)

    private var doseInc: Double { switch draft.doseUnit { case .mcg: 50; case .mg: 0.25; case .iu: 0.5 } }
    private var hairline: some View { Rectangle().fill(VT.hairline).frame(height: 1).padding(.vertical, 2) }

    private var advancedSummary: String? {
        var bits: [String] = []
        if draft.cycleEnabled, draft.cycleOnValue > 0, draft.cycleOffValue > 0 {
            bits.append("Cycle · \(draft.cycleOnValue) on / \(draft.cycleOffValue) off")
        }
        if draft.titrationEnabled, !draft.titrationSteps.isEmpty {
            let n = draft.titrationSteps.count
            bits.append("Titration · \(n) step\(n == 1 ? "" : "s")")
        }
        return bits.isEmpty ? nil : bits.joined(separator: " · ")
    }

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: advancedExpanded ? 14 : 0) {
            Button {
                withAnimation(VMotion.segmentExpand) { advancedExpanded.toggle() }
                Haptics.press()
            } label: {
                HStack {
                    vtLead("Advanced.", color: VT.micro)
                    Spacer()
                    if !advancedExpanded, let s = advancedSummary {
                        Text(s).font(.system(size: 13)).foregroundStyle(VT.micro).lineLimit(1)
                    }
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(VT.micro).rotationEffect(.degrees(advancedExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Advanced cycle and titration options")
            if advancedExpanded {
                hairline; protocolStartRow
                hairline; cycleBlock
                hairline; titrationBlock
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
        .onAppear { advancedExpanded = draft.cycleEnabled || draft.titrationEnabled }
    }

    private var protocolStartRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PROTOCOL START").font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(VT.micro)
            DatePicker("", selection: $draft.protocolStart, displayedComponents: .date).labelsHidden()
            Text("Cycle and dose steps count from here.").font(.system(size: 12)).foregroundStyle(VT.micro)
        }
    }

    private var cycleBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            vtLead("Cycle.", color: VT.dose)
            HStack(spacing: 8) {
                PillToggle(title: "Off", isOn: !draft.cycleEnabled, onColor: VT.dose) { draft.cycleEnabled = false }
                PillToggle(title: "On", isOn: draft.cycleEnabled, onColor: VT.dose) {
                    draft.cycleEnabled = true
                    if draft.cycleOnValue == 0 { draft.cycleOnValue = 5; draft.cycleOffValue = 2; draft.cycleUnit = .days }
                }
            }
            if draft.cycleEnabled {
                HStack(spacing: 8) {
                    PillToggle(title: "Days", isOn: draft.cycleUnit == .days, onColor: VT.dose) { draft.cycleUnit = .days }
                    PillToggle(title: "Weeks", isOn: draft.cycleUnit == .weeks, onColor: VT.dose) { draft.cycleUnit = .weeks }
                }
                cycleStepperRow("On", $draft.cycleOnValue)
                cycleStepperRow("Off", $draft.cycleOffValue)
                Text("\(draft.cycleOnValue) \(draft.cycleUnit.label) on, \(draft.cycleOffValue) \(draft.cycleUnit.label) off")
                    .font(.system(size: 13)).foregroundStyle(VT.micro)
            }
        }
    }

    private func cycleStepperRow(_ label: String, _ value: Binding<Int>) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(VT.body)
            Spacer()
            stepperMini("minus") { value.wrappedValue = max(0, value.wrappedValue - 1) }
            Text("\(value.wrappedValue) \(draft.cycleUnit.short)")
                .font(.system(size: 16, weight: .semibold)).vtTabular().foregroundStyle(VT.ink).frame(minWidth: 56)
            stepperMini("plus") { value.wrappedValue += 1 }
        }
    }

    private var titrationBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            vtLead("Titration.", color: VT.dose)
            HStack(spacing: 8) {
                PillToggle(title: "Off", isOn: !draft.titrationEnabled, onColor: VT.dose) { draft.titrationEnabled = false }
                PillToggle(title: "On", isOn: draft.titrationEnabled, onColor: VT.dose) {
                    draft.titrationEnabled = true
                    if draft.titrationSteps.isEmpty {
                        draft.titrationSteps = [TitrationStepDraft(weekN: 1, dose: draft.doseAmount)]
                    }
                }
            }
            if draft.titrationEnabled {
                ForEach($draft.titrationSteps) { $step in titrationStepRow($step) }
                Button {
                    let lastWeek = draft.titrationSteps.map(\.weekN).max() ?? 0
                    let lastDose = draft.titrationSteps.last?.dose ?? draft.doseAmount
                    draft.titrationSteps.append(TitrationStepDraft(weekN: lastWeek + 2, dose: lastDose))
                    Haptics.press()
                } label: {
                    HStack(spacing: 6) { Image(systemName: "plus.circle"); Text("Add a step") }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.dose)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func titrationStepRow(_ step: Binding<TitrationStepDraft>) -> some View {
        HStack(spacing: 6) {
            Text("Wk").font(.system(size: 12)).foregroundStyle(VT.micro)
            stepperMini("minus") { step.wrappedValue.weekN = max(1, step.wrappedValue.weekN - 1) }
            Text("\(step.wrappedValue.weekN)").font(.system(size: 15, weight: .semibold)).vtTabular().frame(minWidth: 20)
            stepperMini("plus") { step.wrappedValue.weekN += 1 }
            Spacer()
            stepperMini("minus") { step.wrappedValue.dose = max(0, step.wrappedValue.dose - doseInc) }
            Text("\(vtFormatNumber(step.wrappedValue.dose)) \(draft.doseUnit.label)")
                .font(.system(size: 14, weight: .semibold)).vtTabular().foregroundStyle(VT.ink).frame(minWidth: 60)
            stepperMini("plus") { step.wrappedValue.dose += doseInc }
            Button {
                draft.titrationSteps.removeAll { $0.id == step.wrappedValue.id }; Haptics.press()
            } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(VT.micro)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
        }
    }

    private func stepperMini(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: { Haptics.press(); action() }) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(VT.ink)
                .frame(width: 28, height: 28).background(VT.canvas, in: Circle())
        }
        .buttonStyle(.plain)
    }
}

