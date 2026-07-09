import SwiftUI
import SwiftData

struct RootTabView: View {
    @State private var selection: AppTab = AppTab.initialForScreenshots
    private var router = NotificationRouter.shared
    @Query private var items: [ProtocolItem]
    @Query private var compounds: [CatalogCompound]

    var body: some View {
        // The system Liquid Glass bar is hidden; ConcaveTabBar replaces it with a
        // carved-into-the-canvas surface. The bar is inset PER TAB (an inset on the
        // TabView itself does not reach the pages' safe areas, which left bottom
        // content like Chat's input behind the bar).
        TabView(selection: $selection) {
            Tab(value: AppTab.today) { withBar { TodayView() } } label: { EmptyView() }
            Tab(value: AppTab.stack) { withBar { StackView() } } label: { EmptyView() }
            Tab(value: AppTab.diary) { withBar { DiaryView() } } label: { EmptyView() }
            Tab(value: AppTab.chat) { withBar { ChatView() } } label: { EmptyView() }
        }
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

    /// Wraps a tab's content with the hidden system bar + the concave replacement.
    /// The bar ignores the keyboard so it stays put while inputs float above it.
    private func withBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .toolbarVisibility(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ConcaveTabBar(selection: $selection)
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

#Preview { RootTabView() }
