import SwiftUI
import SwiftData

/// The focused daily check-in (M8a) — same shell as DoseSetupSheet. Four signature
/// 1–10 sliders, a tap-to-tag side-effect set, and an optional note. Save upserts
/// today's `DiaryEntry`. Sliders seed from an existing entry or a neutral 5.
struct CheckInSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let existing: DiaryEntry?
    var onSaved: () -> Void = {}

    @State private var energy = 5
    @State private var sleep = 5
    @State private var mood = 5
    @State private var libido = 5
    @State private var sideEffects: Set<SideEffect> = []
    @State private var note = ""
    @FocusState private var noteFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VT.sSection) {
                title
                slidersCard
                sideEffectsCard
                noteCard
                CharcoalPillButton(title: (existing?.isLogged ?? false) ? "Update" : "Save",
                                   action: save)
                    .padding(.top, 4)
            }
            .padding(VT.sSection)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(VT.canvas)
        .dismissesKeyboardOnTap()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: seed)
    }

    private var title: some View {
        ScreenHeader(eyebrow: "Check in", title: "How are you today?")
    }

    private var slidersCard: some View {
        VStack(alignment: .leading, spacing: VT.sCardGap) {
            MetricSlider(metric: .energy, value: $energy)
            MetricSlider(metric: .sleep, value: $sleep)
            MetricSlider(metric: .mood, value: $mood)
            MetricSlider(metric: .libido, value: $libido)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    private var sideEffectsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            vtLead("Anything off?", color: VT.overdue)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
                      alignment: .leading, spacing: 8) {
                ForEach(SideEffect.allCases, id: \.self) { s in
                    PillToggle(title: s.label, isOn: sideEffects.contains(s)) {
                        if sideEffects.contains(s) { sideEffects.remove(s) } else { sideEffects.insert(s) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            vtLead("Note.", color: VT.why)
            TextField("Anything to remember? (optional)", text: $note, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: 16)).foregroundStyle(VT.ink)
                .focused($noteFocused)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(VT.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    private func seed() {
        guard let e = existing else { return }
        energy = e.energy > 0 ? e.energy : 5
        sleep = e.sleep > 0 ? e.sleep : 5
        mood = e.mood > 0 ? e.mood : 5
        libido = e.libido > 0 ? e.libido : 5
        sideEffects = Set(e.sideEffects)
        note = e.note
    }

    private func save() {
        DiaryService(context: context).upsertToday(
            energy: energy, sleep: sleep, mood: mood, libido: libido,
            sideEffects: Array(sideEffects),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines))
        Haptics.commit()
        onSaved()
        dismiss()
    }
}
