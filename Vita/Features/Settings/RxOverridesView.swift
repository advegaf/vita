import SwiftUI
import SwiftData

/// Settings sub-screen: toggle the ℞ badge for any catalog compound. Searchable.
/// Binary rx↔nonRx — the badge is the only visible effect; nothing is ever blocked.
/// Persists through SettingsActions.setRxOverride (override list + live compound).
struct RxOverridesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CatalogCompound.name) private var compounds: [CatalogCompound]
    @State private var query = ""

    private var filtered: [CatalogCompound] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return compounds }
        return compounds.filter {
            $0.name.lowercased().contains(q) || $0.aliases.contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VT.sCardGap) {
                Text("Toggle the ℞ badge for any compound. This only changes the label — nothing is ever blocked.")
                    .font(.system(size: 13)).foregroundStyle(VT.micro)
                searchPill
                LazyVStack(spacing: 8) {
                    ForEach(filtered) { row($0) }
                }
            }
            .padding(VT.sSection)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .dismissesKeyboardOnTap()
        .background(VT.canvas)
        .navigationTitle("Prescription flags")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var searchPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(VT.micro)
            TextField("Search", text: $query).foregroundStyle(VT.ink)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(VT.card, in: Capsule())
        .vtCardShadow()
    }

    private func row(_ c: CatalogCompound) -> some View {
        HStack(spacing: 12) {
            CompoundTile(category: c.category, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(c.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(VT.ink)
                    .lineLimit(1).minimumScaleFactor(0.85)
                if !c.subtitle.isEmpty {
                    Text(c.subtitle).font(.system(size: 12)).foregroundStyle(VT.micro).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            PillToggle(title: "℞", isOn: c.rxStatus == .rx, fillsWidth: false) {
                SettingsActions(context: context).setRxOverride(slug: c.slug, isRx: c.rxStatus != .rx)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12).vtCard()
    }
}
