import SwiftUI
import SwiftData

/// Weight + waist + arm entry (M8a). Decimal fields with inline unit toggles
/// (weight kg/lb shared with the dashboard; measurements cm/in). Each non-empty
/// field appends a `BodyMetric` in canonical units (kg / cm).
struct BodyEntrySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var onSaved: () -> Void = {}

    @AppStorage("vita.weightUnit") private var weightUnitRaw = WeightUnit.lb.rawValue
    @AppStorage("vita.measureUnit") private var measureUnitRaw = MeasurementUnit.inch.rawValue

    @State private var weightText = ""
    @State private var waistText = ""
    @State private var armText = ""
    @FocusState private var editing: Bool
    @State private var detent: PresentationDetent = .medium

    private var weightUnit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lb }
    private var measureUnit: MeasurementUnit { MeasurementUnit(rawValue: measureUnitRaw) ?? .inch }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: VT.sSection) {
                    title
                    entriesCard.id("entries")
                    if HealthKitService.isAvailable {
                        Text("Apple Health weight syncs automatically.")
                            .font(.system(size: 13)).foregroundStyle(VT.micro)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    CharcoalPillButton(title: "Save", action: save).padding(.top, 4)
                }
                .padding(VT.sSection)
            }
            // Same keyboard rescue as the dose sheet (M50): the medium detent
            // pinches focused fields under the keyboard.
            .onChange(of: editing) { _, focused in
                guard focused else { return }
                detent = .large
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    withAnimation { proxy.scrollTo("entries", anchor: .center) }
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(VT.canvas)
        .dismissesKeyboardOnTap()
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
    }

    private var title: some View {
        ScreenHeader(eyebrow: "Measure", title: "Log your numbers.")
    }

    private var entriesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Weight", text: $weightText, unit: weightUnit.rawValue) {
                if let v = Units.parseDouble(weightText) {
                    weightText = Units.trim(weightUnit == .kg ? Units.kgToLb(v) : Units.lbToKg(v))
                }
                weightUnitRaw = (weightUnit == .kg ? WeightUnit.lb : .kg).rawValue
            }
            field("Waist", text: $waistText, unit: measureUnit.rawValue, action: toggleMeasure)
            field("Arm", text: $armText, unit: measureUnit.rawValue, action: toggleMeasure)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    private func toggleMeasure() {
        let toInches = measureUnit == .cm
        func conv(_ v: Double) -> Double { toInches ? Units.cmToInches(v) : Units.inchesToCm(v) }
        if let w = Units.parseDouble(waistText) { waistText = Units.trim(conv(w)) }
        if let a = Units.parseDouble(armText) { armText = Units.trim(conv(a)) }
        measureUnitRaw = (measureUnit == .cm ? MeasurementUnit.inch : .cm).rawValue
    }

    private func field(_ label: String, text: Binding<String>, unit: String,
                       action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 13)).foregroundStyle(VT.micro)
            HStack(spacing: 8) {
                TextField("", text: text).keyboardType(.decimalPad).focused($editing)
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(VT.ink)
                Button(action: action) {
                    Text(unit).font(.system(size: 14, weight: .semibold)).foregroundStyle(VT.dose)
                }
                .buttonStyle(.plain).accessibilityHint("Tap to change unit")
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(VT.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func save() {
        let diary = DiaryService(context: context)
        if let w = Units.parseDouble(weightText), w > 0 {
            diary.addBodyMetric(.weight, valueCanonical: weightUnit == .kg ? w : Units.lbToKg(w))
        }
        if let wa = Units.parseDouble(waistText), wa > 0 {
            diary.addBodyMetric(.waist, valueCanonical: measureUnit == .cm ? wa : Units.inchesToCm(wa))
        }
        if let a = Units.parseDouble(armText), a > 0 {
            diary.addBodyMetric(.arm, valueCanonical: measureUnit == .cm ? a : Units.inchesToCm(a))
        }
        Haptics.commit()
        onSaved()
        dismiss()
    }
}
