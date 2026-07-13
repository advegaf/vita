import SwiftUI
import SwiftData

struct StackView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\ProtocolItem.sortIndex), SortDescriptor(\ProtocolItem.addedAt)])
    private var items: [ProtocolItem]
    @Query private var compounds: [CatalogCompound]
    @Query private var allLogs: [DoseLog]

    private var bySlug: [String: CatalogCompound] {
        Dictionary(compounds.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// A quiet "N doses left" for a row whose vial is running low (nil otherwise).
    private func supplyHint(for item: ProtocolItem) -> String? {
        guard let vial = item.vial else { return nil }
        let logs = allLogs.filter { $0.compoundSlug == item.compoundSlug }
        let s = VialEngine.status(item: item, vial: vial, logs: logs, asOf: .now,
                                  iuPerMg: bySlug[item.compoundSlug]?.iuPerMg)
        guard s.isLow else { return nil }
        return VialEngine.supplyLine(s)
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
                                StackRow(item: item, compound: bySlug[item.compoundSlug],
                                         supplyHint: supplyHint(for: item))
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

    // M40 Journey-style header: big title + gray subtitle, black circular FAB.
    private var header: some View {
        HStack(alignment: .top) {
            ScreenHeader(eyebrow: "Stack",
                         title: items.isEmpty ? "Nothing added yet."
                                              : (items.count == 1 ? "One compound."
                                                                  : "\(items.count) compounds."))
            Spacer()
            Button { showCatalog = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(VT.onInk)
                    .frame(width: 44, height: 44)
                    .background(VT.ink, in: Circle())
                    .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a peptide")
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
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(VT.onInk)
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
    var supplyHint: String? = nil

    private var stackRowSubtitle: String {
        // Truncated: dose•units + a short cadence token (no verbose time-of-day; the
        // detail view shows the full schedule). Computed LIVE, not the stored label.
        let dose = item.doseWithDrawText(on: .now)
        let cadence = item.schedule.map { ScheduleService.cadenceShort(for: $0) } ?? "tap to set"
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
            // Fills the real available width and wraps WITHIN it — no .fixedSize
            // (which made the row wider than the screen → sideways "canvas" scroll).
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(VT.ink)
                    .lineLimit(2)
                Text(stackRowSubtitle)
                    .font(.system(size: 13)).vtTabular().foregroundStyle(VT.body)
                    .lineLimit(2)
                if let supplyHint {
                    Text(supplyHint)
                        .font(.system(size: 13)).vtTabular().foregroundStyle(VT.body)
                        .lineLimit(1)
                }
                // Cycle chip as a badge BELOW the subtitle (like Today): keeps its
                // fixed width out of the main row so the row never overflows.
                if let chip = cycleChipText {
                    CycleChip(text: chip, resting: isResting).padding(.top, 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
