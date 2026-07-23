import SwiftUI
import SwiftData

/// M40 root: standard tabbed screens on the warm-white canvas with the
/// floating black-pill tab bar. (Replaces the M38/M39 immersive photo/card
/// architecture, removed per the user's design language.)
struct RootShell: View {
    @State private var selection: AppTab = AppTab.initialForScreenshots
    @State private var router = NotificationRouter.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query private var items: [ProtocolItem]
    @Query private var compounds: [CatalogCompound]

    @State private var mounted: Set<AppTab> = [AppTab.initialForScreenshots]
    /// The detail sheet is driven by this scene-gated copy of the router's
    /// pending id: presenting a modal while the foreground transition from a
    /// notification tap is still in flight crashes on device (M47), so the
    /// pending id is applied only once the scene is active, one runloop later.
    @State private var presentedItemID: UUID?
    /// scenePhase == .active is NOT a proxy for "the root view is in the window":
    /// on a cold launch from a notification tap the scene reports active before
    /// UIKit attaches the hosting controller, and presenting the sheet then
    /// crashes on device (M53). This flag flips only after first onAppear plus a
    /// short settle, and the presentation guard requires BOTH signals.
    @State private var uiReady = false
    var body: some View {
        // A lazy-once ZStack keeps pages alive after first visit, preserving
        // stacks, scroll positions, and chat state. Tab selection itself is
        // immediate: navigation must never animate the whole app window.
        // ONE FloatingTabBar instance insets the whole container.
        ZStack {
            ForEach(AppTab.allCases) { tab in
                if mounted.contains(tab) {
                    tabContent(tab)
                        .opacity(tab == selection ? 1 : 0)
                        // No drift: any vertical motion read as the window
                        // "pulling down" on switch (device feedback, M43b).
                        .allowsHitTesting(tab == selection)
                        .accessibilityHidden(tab != selection)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar(selection: $selection, hidesForChatInput: router.isChatInputFocused)
        }
        .onChange(of: selection) { _, tab in
            mounted.insert(tab)
            // Always-mounted tabs never fire ChatView.onDisappear, so the
            // chat-input flag (which hides the bar) is cleared here instead.
            if tab != .chat { router.isChatInputFocused = false }
        }
        .tint(VT.ink)
        .onChange(of: router.pendingTab) { _, tab in
            if let tab { selection = tab; router.pendingTab = nil }
        }
        .onChange(of: router.pendingDetailItemID) { _, id in applyPendingDetail(id) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { applyPendingDetail(router.pendingDetailItemID) }
        }
        .onAppear {
            // Cold-launch rescue (M53): the pending id is usually set BEFORE this
            // view subscribes, so neither onChange above fires for it. Flip
            // uiReady after a short settle; the onChange below re-checks the
            // pending id. (The re-check must NOT happen inside this Task: the
            // closure captures a stale view value whose scenePhase still reads
            // pre-activation, and the guard would skip forever.)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                uiReady = true
            }
        }
        .onChange(of: uiReady) { _, ready in
            if ready { applyPendingDetail(router.pendingDetailItemID) }
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
            get: { presentedItemID != nil },
            set: { if !$0 { presentedItemID = nil } }
        )) {
            // Only present for a LIVE item: a reminder for a since-removed (or
            // mid-delete, faulted) item must never reach CompoundDetailView, whose
            // dose card reads item.schedule and would trap in SwiftData (the M26
            // titrationDayStarts crash). Resolved with a fresh fetch because the
            // @Query array may not be populated yet on a cold-start tap.
            if let id = presentedItemID, let item = fetchItem(id), !item.isDeleted {
                NavigationStack {
                    CompoundDetailView(compound: detailCompound(item), item: item)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { presentedItemID = nil }
                                    .foregroundStyle(VT.ink)
                            }
                        }
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            } else {
                Color.clear.onAppear { presentedItemID = nil }
            }
        }
    }

    /// Applies a pending deep-link only while the scene is active AND the root
    /// view has settled in the window (uiReady), deferring one more runloop turn
    /// so the sheet never presents mid-transition. Three callers converge here
    /// (pending onChange, scenePhase onChange, onAppear settle); whichever signal
    /// lands last wins, and none can present early.
    private func applyPendingDetail(_ id: UUID?) {
        guard let id, scenePhase == .active, uiReady else { return }
        Task { @MainActor in
            presentedItemID = id
            router.pendingDetailItemID = nil
        }
    }

    /// Launch-safe item resolve (the lazy @Query can lag a cold-start tap).
    private func fetchItem(_ id: UUID) -> ProtocolItem? {
        var d = FetchDescriptor<ProtocolItem>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
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
