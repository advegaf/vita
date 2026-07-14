import SwiftUI
import SwiftData

/// M40 root: standard tabbed screens on the warm-white canvas with the
/// floating black-pill tab bar. (Replaces the M38/M39 immersive photo/card
/// architecture, removed per the user's design language.)
struct RootShell: View {
    @State private var selection: AppTab = AppTab.initialForScreenshots
    private var router = NotificationRouter.shared
    @Query private var items: [ProtocolItem]
    @Query private var compounds: [CatalogCompound]

    @State private var mounted: Set<AppTab> = [AppTab.initialForScreenshots]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // M43: a lazy-once ZStack instead of TabView — pages stay alive after
        // first visit (stacks, scroll positions, chat state survive) and the
        // switch is a calm crossfade + drift instead of TabView's hard cut.
        // ONE FloatingTabBar instance insets the whole container.
        ZStack {
            ForEach(AppTab.allCases) { tab in
                if mounted.contains(tab) {
                    tabContent(tab)
                        .opacity(tab == selection ? 1 : 0)
                        .offset(y: tab == selection ? 0 : 8)
                        .allowsHitTesting(tab == selection)
                        .accessibilityHidden(tab != selection)
                }
            }
        }
        .animation(reduceMotion ? VMotion.reduced : .spring(duration: 0.35, bounce: 0),
                   value: selection)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar(selection: $selection)
        }
        .onChange(of: selection) { _, tab in mounted.insert(tab) }
        .tint(VT.ink)
        .onChange(of: router.pendingTab) { _, tab in
            if let tab { selection = tab; router.pendingTab = nil }
        }
        .task {
            #if DEBUG
            if let v = ProcessInfo.processInfo.environment["VITA_OPEN_DETAIL"] {
                try? await Task.sleep(nanoseconds: 600_000_000)
                router.pendingDetailItemID = (v == "1" ? items.first
                                              : items.first { $0.compoundSlug == v })?.id
            }
            #endif
        }
        .sheet(isPresented: Binding(
            get: { router.pendingDetailItemID != nil },
            set: { if !$0 { router.pendingDetailItemID = nil } }
        )) {
            // Only present for a LIVE item: a reminder for a since-removed (or
            // mid-delete, faulted) item must never reach CompoundDetailView, whose
            // dose card reads item.schedule and would trap in SwiftData (the M26
            // titrationDayStarts crash). If it can't resolve, clear the pending id.
            if let id = router.pendingDetailItemID,
               let item = items.first(where: { $0.id == id }), !item.isDeleted {
                NavigationStack {
                    CompoundDetailView(compound: detailCompound(item), item: item)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { router.pendingDetailItemID = nil }
                                    .foregroundStyle(VT.ink)
                            }
                        }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            } else {
                Color.clear.onAppear { router.pendingDetailItemID = nil }
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: AppTab) -> some View {
        switch tab {
        case .today: TodayView()
        case .stack: StackView()
        case .diary: DiaryView()
        case .chat:  ChatView()
        }
    }

    /// The catalog compound for a reminder's item, or a placeholder from the item.
    private func detailCompound(_ item: ProtocolItem) -> CatalogCompound {
        if let c = compounds.first(where: { $0.slug == item.compoundSlug }) { return c }
        let c = CatalogCompound(slug: item.compoundSlug)
        c.name = item.displayName; c.categoryRaw = item.categoryRaw
        c.rxStatusRaw = item.rxStatusRaw; c.doseUnitRaw = item.doseUnitRaw
        return c
    }
}

#Preview { RootShell() }
