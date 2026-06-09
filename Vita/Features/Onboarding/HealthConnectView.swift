import SwiftUI
import SwiftData

/// Onboarding step: connect Apple Health so vita can factor in sleep, HRV, and
/// weight, plus a small editable age/sex/weight profile. Fully skippable —
/// generation still runs on goals + picked peptides (+ any entered profile).
struct HealthConnectView: View {
    @Bindable var model: OnboardingModel
    @Environment(\.modelContext) private var context

    @State private var connecting = false
    @State private var connected = false
    @State private var healthNote: String?
    @State private var ageText = ""
    @State private var sex = ""                 // "" | female | male | other
    @State private var weightText = ""
    @State private var heightCmText = ""        // when heightUnit == .cm
    @State private var feetText = ""            // when heightUnit == .ftIn
    @State private var inchesText = ""
    @FocusState private var editing: Bool

    // Shared, persisted unit prefs — default to imperial (lb / ft·in).
    @AppStorage("vita.weightUnit") private var weightUnitRaw = WeightUnit.lb.rawValue
    @AppStorage("vita.heightUnit") private var heightUnitRaw = HeightUnit.ftIn.rawValue
    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }
    private var heightUnit: HeightUnit { HeightUnit(rawValue: heightUnitRaw) ?? .ftIn }

    private let sexes = ["female", "male", "other"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: VT.sCardGap) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Step 4")
                            .font(.system(size: 12, weight: .medium)).tracking(0.4)
                            .textCase(.uppercase).foregroundStyle(VT.micro)
                        Text("Connect Apple Health?").vtHeadlineStyle()
                        Text("vita can factor in your sleep, HRV, and weight when it suggests a plan. Read-only, and you can skip.")
                            .font(.system(size: 16)).foregroundStyle(VT.body).padding(.top, 2)
                    }
                    .padding(.top, 8)

                    connectCard
                    profileCard
                }
                .padding(VT.sSection)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .dismissesKeyboardOnTap()

            // Hidden while typing so the keyboard never shoves them up mid-screen.
            if !editing {
                VStack(spacing: 10) {
                    CharcoalPillButton(title: "Continue", action: persistThenAdvance)
                    Button("Skip for now", action: model.advance)
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.micro)
                }
                .padding(.horizontal, VT.sSection).padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: editing)
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["VITA_HEALTH_FOCUS"] == "1" {
                try? await Task.sleep(nanoseconds: 500_000_000)
                editing = true
            }
            #endif
        }
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: connected ? "checkmark.seal.fill" : "heart.text.square")
                .font(.system(size: 34)).foregroundStyle(connected ? VT.why : VT.dose)
            Text(connected ? "Apple Health connected." : "Pull your recent vitals automatically.")
                .font(.system(size: 16)).foregroundStyle(VT.body).lineSpacing(3)
            if !connected {
                // Secondary action: a tonal (not solid) cyan pill, so the only
                // solid-filled surface in the app stays the charcoal pill.
                Button(action: connect) {
                    HStack(spacing: 8) {
                        if connecting { ProgressView().tint(VT.dose) }
                        Text(connecting ? "Connecting…" : "Connect Apple Health")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(VT.dose)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(VT.dose.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain).allowsHitTesting(!connecting)
            }
            if let healthNote {
                Text(healthNote).font(.system(size: 13)).foregroundStyle(VT.micro)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ABOUT YOU")
                .font(.system(size: 12, weight: .medium)).tracking(0.4)
                .textCase(.uppercase).foregroundStyle(VT.micro)
            vtPlainField("Age", text: $ageText, suffix: "yrs", keyboard: .numberPad, focus: $editing)
            VStack(alignment: .leading, spacing: 6) {
                Text("Sex").font(.system(size: 13)).foregroundStyle(VT.micro)
                HStack(spacing: 8) {
                    ForEach(sexes, id: \.self) { s in
                        PillToggle(title: s.capitalized, isOn: sex == s) {
                            sex = (sex == s ? "" : s)
                        }
                    }
                }
            }
            weightField
            heightField
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    private var weightField: some View {
        vtFieldShell("Weight") {
            TextField("", text: $weightText).keyboardType(.decimalPad).focused($editing)
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(VT.ink)
            vtUnitTab(weightUnit.rawValue, action: toggleWeightUnit)
        }
    }

    @ViewBuilder
    private var heightField: some View {
        if heightUnit == .cm {
            vtFieldShell("Height") {
                TextField("", text: $heightCmText).keyboardType(.decimalPad).focused($editing)
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(VT.ink)
                vtUnitTab("cm", action: toggleHeightUnit)
            }
        } else {
            vtFieldShell("Height") {
                TextField("ft", text: $feetText).keyboardType(.numberPad).focused($editing)
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(VT.ink)
                Text("ft").font(.system(size: 14)).foregroundStyle(VT.micro)
                TextField("in", text: $inchesText).keyboardType(.numberPad).focused($editing)
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(VT.ink)
                vtUnitTab("ft·in", action: toggleHeightUnit)
            }
        }
    }

    private func toggleWeightUnit() {
        if let v = Double(weightText) {
            weightText = weightUnit == .kg ? Units.trim(Units.kgToLb(v)) : Units.trim(Units.lbToKg(v))
        }
        weightUnitRaw = (weightUnit == .kg ? WeightUnit.lb : .kg).rawValue
    }

    private func toggleHeightUnit() {
        if heightUnit == .cm {
            if let cm = Double(heightCmText) {
                let fi = Units.cmToFeetInches(cm)
                feetText = String(fi.feet); inchesText = String(fi.inches)
            }
            heightUnitRaw = HeightUnit.ftIn.rawValue
        } else {
            if let f = Int(feetText) ?? (feetText.isEmpty ? 0 : nil),
               let i = Int(inchesText) ?? (inchesText.isEmpty ? 0 : nil), f + i > 0 {
                heightCmText = Units.trim(Units.feetInchesToCm(feet: f, inches: i))
            }
            heightUnitRaw = HeightUnit.cm.rawValue
        }
    }

    /// Fills the height field(s) from a cm value in whichever unit is active.
    private func fillHeight(_ cm: Double) {
        if heightUnit == .cm {
            if heightCmText.isEmpty { heightCmText = Units.trim(cm) }
        } else if feetText.isEmpty && inchesText.isEmpty {
            let fi = Units.cmToFeetInches(cm)
            feetText = String(fi.feet); inchesText = String(fi.inches)
        }
    }

    // MARK: - Actions

    private func connect() {
        connecting = true
        Task {
            let granted = await HealthKitService.shared.requestAuthorization()
            if granted {
                // Quick reads (weight + height + age + sex) fill the form fast…
                let v = await HealthKitService.shared.profileVitals()
                await MainActor.run {
                    if let w = v.weightKg, w > 0, weightText.isEmpty {
                        weightText = weightUnit == .kg ? Units.trim(w) : Units.trim(Units.kgToLb(w))
                    }
                    if let h = v.heightCm, h > 0 { fillHeight(h) }
                    if let a = v.ageYears, ageText.isEmpty { ageText = String(a) }
                    if let s = v.biologicalSex, sex.isEmpty { sex = s }
                    connected = true
                    connecting = false
                }
                // …the full vitals (sleep/HRV/steps) load in the background for AI grounding.
                let snap = await HealthKitService.shared.snapshot()
                await MainActor.run { model.healthSnapshot = snap }
            } else {
                await MainActor.run {
                    healthNote = HealthKitService.isAvailable
                        ? "Couldn't reach Apple Health. You can enter your details below."
                        : "Apple Health isn't available on this device."
                    connecting = false
                }
            }
        }
    }

    private func persistThenAdvance() {
        let settings = CatalogStore.fetchOrCreateSettings(context)
        let profile = CatalogStore.fetchOrCreateProfile(context, settings: settings)
        if let age = Int(ageText), age > 0, age < 130 {
            profile.birthDate = Calendar.current.date(byAdding: .year, value: -age, to: Date())
        }
        profile.biologicalSexRaw = sex.isEmpty ? nil : sex
        if let w = Double(weightText), w > 0 {
            profile.weightKg = weightUnit == .kg ? w : Units.lbToKg(w)
        }
        if heightUnit == .cm {
            if let cm = Double(heightCmText), cm > 0 { profile.heightCm = cm }
        } else {
            let f = Int(feetText) ?? 0, i = Int(inchesText) ?? 0
            if f + i > 0 { profile.heightCm = Units.feetInchesToCm(feet: f, inches: i) }
        }
        try? context.save()
        model.advance()
    }
}
