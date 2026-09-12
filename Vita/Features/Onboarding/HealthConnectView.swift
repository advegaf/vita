import SwiftUI
import SwiftData

/// Onboarding step: a small editable age/sex/weight/height profile that helps
/// ground generation. Skippable; generation still runs on goals + picked
/// peptides.
///
/// This screen deliberately carries NO Apple Health affordance. A custom screen
/// that talks about Health while letting the user leave without the system
/// permission sheet violates App Review 5.1.1(iv) (rejected on 1.0.0 build 7).
/// Health is connected from Diary and Settings, where the Connect button raises
/// the system sheet directly with nothing in between.
struct HealthConnectView: View {
    @Bindable var model: OnboardingModel
    @Environment(\.modelContext) private var context

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
                        Text("A bit about you.").vtHeadlineStyle()
                        Text("Age, sex, and body measurements help Vita size its educational suggestions. Every field is optional.")
                            .font(.system(size: 16)).foregroundStyle(VT.body).padding(.top, 2)
                    }
                    .padding(.top, 8)

                    profileCard
                }
                .padding(VT.sSection)
                // The docked Continue pill sits below the scroll; give the last
                // field (Height) room to clear it at rest instead of tucking under.
                .padding(.bottom, VT.sSection)
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
            if ProcessInfo.processInfo.environment["VITA_PROFILE_FOCUS"] == "1" {
                try? await Task.sleep(nanoseconds: 500_000_000)
                editing = true
            }
            #endif
        }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 14) {
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
        if let v = Units.parseDouble(weightText) {
            weightText = weightUnit == .kg ? Units.trim(Units.kgToLb(v)) : Units.trim(Units.lbToKg(v))
        }
        weightUnitRaw = (weightUnit == .kg ? WeightUnit.lb : .kg).rawValue
    }

    private func toggleHeightUnit() {
        if heightUnit == .cm {
            if let cm = Units.parseDouble(heightCmText) {
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

    // MARK: - Actions

    private func persistThenAdvance() {
        let settings = CatalogStore.fetchOrCreateSettings(context)
        let profile = CatalogStore.fetchOrCreateProfile(context, settings: settings)
        if let age = Int(ageText), age > 0, age < 130 {
            profile.birthDate = Calendar.current.date(byAdding: .year, value: -age, to: Date())
        }
        profile.biologicalSexRaw = sex.isEmpty ? nil : sex
        if let w = Units.parseDouble(weightText), w > 0 {
            profile.weightKg = weightUnit == .kg ? w : Units.lbToKg(w)
        }
        if heightUnit == .cm {
            if let cm = Units.parseDouble(heightCmText), cm > 0 { profile.heightCm = cm }
        } else {
            let f = Int(feetText) ?? 0, i = Int(inchesText) ?? 0
            if f + i > 0 { profile.heightCm = Units.feetInchesToCm(feet: f, inches: i) }
        }
        try? context.save()
        model.advance()
    }
}
