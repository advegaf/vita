import SwiftUI
import SwiftData

/// Root navigation: three content tabs behind a floating PillDock + a circular AI
/// button that presents chat as a sheet (chat is not a tab). The system tab bar is
/// hidden; content scrolls under the dock like it did under the old glass bar.
struct RootTabView: View {
    @State private var selection: AppTab = AppTab.initialForScreenshots
    private var router = NotificationRouter.shared
    @Query private var items: [ProtocolItem]
    @Query private var compounds: [CatalogCompound]

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: AppTab.home) { TodayView().toolbarVisibility(.hidden, for: .tabBar) }
                label: { Label("Home", systemImage: "house.fill") }
            Tab(value: AppTab.data) { DiaryView().toolbarVisibility(.hidden, for: .tabBar) }
                label: { Label("Data", systemImage: "chart.bar.fill") }
            Tab(value: AppTab.protocolTab) { StackView().toolbarVisibility(.hidden, for: .tabBar) }
                label: { Label("Protocol", systemImage: "list.bullet.rectangle.portrait.fill") }
        }
        .overlay(alignment: .bottom) {
            PillDock(selection: $selection, onAI: { router.showChat = true })
                .padding(.bottom, 4)
        }
        .onChange(of: router.pendingTab) { _, tab in
            if let tab { selection = tab; router.pendingTab = nil }
        }
        .sheet(isPresented: Binding(
            get: { router.showChat },
            set: { router.showChat = $0 }
        )) {
            ChatView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .task {
            #if DEBUG
            if let v = ProcessInfo.processInfo.environment["VITA_OPEN_DETAIL"] {
                try? await Task.sleep(nanoseconds: 600_000_000)
                router.pendingDetailItemID = (v == "1" ? items.first
                                              : items.first { $0.compoundSlug == v })?.id
            }
            if ProcessInfo.processInfo.environment["VITA_OPEN_CHAT"] == "1" {
                try? await Task.sleep(nanoseconds: 400_000_000)
                router.showChat = true
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
