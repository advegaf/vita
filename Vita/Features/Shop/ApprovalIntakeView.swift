import SwiftUI
import SwiftData

/// UI-only medical-approval intake (M36). Collects the request and moves the gate to
/// `.pending`. The real provider review + record-keeping is the backend phase.
struct ApprovalIntakeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var fullName = ""
    @State private var dob = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now
    @State private var isAdult = false
    @State private var underCare = false
    @State private var consent = false
    @FocusState private var nameFocused: Bool

    private var canSubmit: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty && isAdult && consent
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VT.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: VT.sCardGap) {
                        ScreenHeader(eyebrow: "Approval", title: "Request approval.")
                        Text("A licensed provider reviews your information before any order ships. Educational, not medical advice.")
                            .font(.system(size: 13)).foregroundStyle(VT.micro)
                            .fixedSize(horizontal: false, vertical: true)

                        card {
                            field("Full name") {
                                TextField("Your name", text: $fullName)
                                    .foregroundStyle(VT.ink).focused($nameFocused)
                            }
                            divider
                            HStack {
                                Text("Date of birth").font(.system(size: 15)).foregroundStyle(VT.body)
                                Spacer()
                                DatePicker("", selection: $dob, displayedComponents: .date).labelsHidden()
                            }
                        }

                        card {
                            toggleRow("I am 18 or older", $isAdult)
                            divider
                            toggleRow("Currently under a doctor's care", $underCare)
                            divider
                            toggleRow("I understand these products are dispensed only after provider approval, and this app is educational, not medical advice.", $consent)
                        }

                        CharcoalPillButton(title: "Submit request") { submit() }
                            .opacity(canSubmit ? 1 : 0.4).disabled(!canSubmit)
                            .padding(.top, 4)
                    }
                    .padding(VT.sSection)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .dismissesKeyboardOnTap()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(VT.ink)
                }
            }
        }
    }

    private func submit() {
        let settings = CatalogStore.fetchOrCreateSettings(context)
        settings.shopApproval = .pending
        context.saveLogged("ApprovalIntake")
        Haptics.commit()
        dismiss()
    }

    // MARK: Bits

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(VT.sCardPad).vtCard()
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(VT.body)
            Spacer()
            content().multilineTextAlignment(.trailing)
        }
    }

    private func toggleRow(_ label: String, _ on: Binding<Bool>) -> some View {
        Button { on.wrappedValue.toggle(); Haptics.press() } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: on.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20)).foregroundStyle(on.wrappedValue ? VT.why : VT.micro)
                Text(label).font(.system(size: 14)).foregroundStyle(VT.ink)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
    }

    private var divider: some View { Rectangle().fill(VT.hairline).frame(height: 1) }
}
