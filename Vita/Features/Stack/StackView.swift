import SwiftUI
import SwiftData

struct StackView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\ProtocolItem.sortIndex), SortDescriptor(\ProtocolItem.addedAt)])
    private var items: [ProtocolItem]
    @Query private var compounds: [CatalogCompound]

    private var bySlug: [String: CatalogCompound] {
        Dictionary(compounds.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
    }

    @State private var showCatalog = false
    @State private var debugDraft: DoseDraft?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VT.sCardGap) {
                    header
                    if items.isEmpty {
                        emptyState
                    } else {
                        ForEach(items) { item in
                            NavigationLink {
                                CompoundDetailView(compound: bySlug[item.compoundSlug] ?? placeholder(item),
                                                   item: item)
                            } label: {
                                StackRow(item: item, compound: bySlug[item.compoundSlug])
                            }
                            .buttonStyle(.pressableCard)
                            .contextMenu {
                                Button(role: .destructive) {
                                    StackService(context: context).remove(item)
                                } label: { Label("Remove", systemImage: "trash") }
                            }
                        }
                    }
                }
                .padding(VT.sSection)
            }
            .scrollIndicators(.hidden)
            .background(VT.canvas)
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["VITA_OPEN_DOSESHEET"] == "1",
               let item = items.first {
                debugDraft = StackService(context: context).draft(for: item)
            }
            #endif
        }
        .sheet(item: $debugDraft) { d in DoseSetupSheet(draft: d) }
        .sheet(isPresented: $showCatalog) {
            NavigationStack {
                CatalogBrowseView()
                    .navigationDestination(for: String.self) { slug in
                        if let c = compounds.first(where: { $0.slug == slug }) {
                            CompoundDetailView(compound: c)
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showCatalog = false }
                                .foregroundStyle(VT.ink)
                        }
                    }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            ScreenHeader(eyebrow: "Stack",
                         title: items.isEmpty ? "Your stack." : "\(items.count) in your stack.")
            Spacer()
            CircleIconButton(systemName: "plus", label: "Add a peptide") { showCatalog = true }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Nothing here yet.")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(VT.ink)
                .multilineTextAlignment(.center)
            Text("Browse the catalog to add what you're taking.")
                .font(.system(size: 15)).foregroundStyle(VT.body).multilineTextAlignment(.center)
            Button { showCatalog = true } label: {
                Text("Browse the catalog")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 28).padding(.vertical, 15)
                    .background(VT.ink, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity).padding(.top, 56)
    }

    private func placeholder(_ item: ProtocolItem) -> CatalogCompound {
        let c = CatalogCompound(slug: item.compoundSlug)
        c.name = item.displayName; c.categoryRaw = item.categoryRaw
        c.rxStatusRaw = item.rxStatusRaw; c.doseUnitRaw = item.doseUnitRaw
        return c
    }
}

struct StackRow: View {
    let item: ProtocolItem
    let compound: CatalogCompound?

    private var stackRowSubtitle: String {
        let active = item.effectiveDoseText(on: .now)
        let dose = item.effectiveDrawUnitsText(on: .now).map { "\(active) (\($0))" } ?? active
        let cadence = item.cadenceLabel.isEmpty ? "tap to set" : item.cadenceLabel
        return "\(dose), \(cadence)"
    }

    private var cycleChipText: String? {
        guard let rule = item.schedule, rule.hasCycle else { return nil }
        return ScheduleService.cycleStatus(for: rule, on: .now)?.chipText
    }
    private var isResting: Bool {
        guard let rule = item.schedule else { return false }
        return ScheduleService.isResting(rule, on: .now)
    }

    var body: some View {
        // Defense-in-depth: a row whose item was just deleted (swipe/context
        // remove, any background mutation) must render as nothing — touching a
        // deleted model's relationships traps in SwiftData (device crash log:
        // titrationDayStarts getter under StackRow.body).
        if item.isDeleted {
            EmptyView()
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            CompoundTile(category: item.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(VT.ink)
                    .lineLimit(1).minimumScaleFactor(0.85)
                Text(stackRowSubtitle)
                    .font(.system(size: 13)).vtTabular().foregroundStyle(VT.body)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            if let chip = cycleChipText { CycleChip(text: chip, resting: isResting) }
            if item.rxStatus == .rx {
                RxBadge()
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(VT.micro)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .vtCard()
    }
}
