import SwiftUI
import SwiftData

struct RootTabView: View {
    @State private var selection: AppTab = AppTab.initialForScreenshots
    private var router = NotificationRouter.shared
    @Query private var items: [ProtocolItem]
    @Query private var compounds: [CatalogCompound]

    var body: some View {
        TabView(selection: $selection) {
            Tab(value: AppTab.today) { TodayView() }
                label: { coloredLabel("Today", "sun.max", VT.dose) }
            Tab(value: AppTab.stack) { StackView() }
                label: { coloredLabel("Stack", "pills", VT.why) }
            Tab(value: AppTab.diary) { DiaryView() }
                label: { coloredLabel("Diary", "chart.xyaxis.line", VT.timing) }
            Tab(value: AppTab.chat) { ChatView() }
                label: { coloredLabel("Chat", "bubble.left.and.text.bubble.right", VT.dose) }
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

    /// The catalog compound for a reminder's item, or a placeholder from the item.
    private func detailCompound(_ item: ProtocolItem) -> CatalogCompound {
        if let c = compounds.first(where: { $0.slug == item.compoundSlug }) { return c }
        let c = CatalogCompound(slug: item.compoundSlug)
        c.name = item.displayName; c.categoryRaw = item.categoryRaw
        c.rxStatusRaw = item.rxStatusRaw; c.doseUnitRaw = item.doseUnitRaw
        return c
    }

    /// Tab label whose icon keeps its design accent at all times (the native
    /// Liquid Glass bar template-tints by default, so the symbol is pre-rendered
    /// with `.alwaysOriginal` in its color).
    private func coloredLabel(_ title: String, _ symbol: String, _ color: Color) -> some View {
        Label { Text(title) } icon: { Image(uiImage: Self.coloredIcon(symbol, color)) }
    }

    private static func coloredIcon(_ name: String, _ color: Color) -> UIImage {
        (UIImage(systemName: name) ?? UIImage())
            .withTintColor(UIColor(color), renderingMode: .alwaysOriginal)
    }
}

#Preview { RootTabView() }
