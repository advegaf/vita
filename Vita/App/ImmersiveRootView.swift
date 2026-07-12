import SwiftUI
import SwiftData

/// M38 root: the Fields-style immersive layout. A full-bleed photo backdrop
/// with the brand pill + view title header on it, and a permanently-presented
/// two-detent system sheet (the "card") hosting all four views. The system
/// sheet is deliberate: UIKit's sheet/scroll arbitration provides Maps-style
/// scroll-to-expand, interruption, and rubber-banding that pure SwiftUI can't
/// reproduce (validated by SpikeCardView + CardSpikeUITests).
///
/// Chrome (photo parallax, scrim, header fade, glass bar) is a pure function of
/// the sheet's continuously-observed top edge. Interactive drags stream that
/// geometry per frame; programmatic detent changes report endpoints only, so
/// large jumps are animated here with a matching spring.
struct ImmersiveRootView: View {
    // Screenshot-iterated: 0.62 left a dead photo band; 0.70 was better; 0.75
    // per device feedback ("make it come up a little more") — the card starts
    // right under the title block.
    static let restFraction: CGFloat = 0.75

    @State private var selection: AppTab = .initialForScreenshots
    @State private var mounted: Set<AppTab> = [AppTab.initialForScreenshots]
    @State private var cardPresented = true
    @State private var detent: PresentationDetent = .fraction(ImmersiveRootView.restFraction)
    private let detents: Set<PresentationDetent> = [.fraction(ImmersiveRootView.restFraction), .large]
    @State private var showSettings = false
    @State private var sheetTopY: CGFloat = 10_000
    @State private var geometryInitialized = false

    private var router = NotificationRouter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: [SortDescriptor(\ProtocolItem.sortIndex), SortDescriptor(\ProtocolItem.addedAt)])
    private var items: [ProtocolItem]
    @Query private var logs: [DoseLog]
    @Query private var compounds: [CatalogCompound]

    var body: some View {
        GeometryReader { geo in
            let progress = progress(in: geo)
            ZStack(alignment: .top) {
                BackdropView(progress: progress)
                // The title block floats CENTERED between the brand pill and
                // the resting card's top edge (the spacers split the leftover
                // photo band evenly), instead of hugging the pill.
                VStack(alignment: .leading, spacing: 0) {
                    TopBarPill(onMenu: { showSettings = true })
                    Spacer(minLength: 8)
                    ImmersiveHeader(selection: $selection,
                                    eyebrow: eyebrow,
                                    subtitle: subtitle,
                                    progress: progress)
                    Spacer(minLength: 8)
                }
                .frame(height: max(0, detentGeometry(in: geo).restY - geo.safeAreaInsets.top - 8))
                .padding(.horizontal, VT.sSection)
                .padding(.top, 8)
                // opacity(0) does NOT stop hit-testing or accessibility: once
                // the card covers the faded header, take it out of both so an
                // invisible picker can't be focused behind the sheet.
                .allowsHitTesting(progress < 0.6)
                .accessibilityHidden(progress > 0.6)
            }
            .sheet(isPresented: $cardPresented) {
                cardHost(progress: progress)
            }
        }
        // The photo layer never moves for the keyboard — and the progress math
        // depends on stable base geometry (a keyboard-shrunk GeometryReader
        // corrupted the derived detent positions while Chat was typing).
        .ignoresSafeArea(.keyboard)
        // The card must be impossible to lose (memory pressure, presentation
        // conflicts): whatever dismisses it, put it back.
        .onChange(of: cardPresented) { _, shown in
            if !shown { cardPresented = true }
        }
        .onChange(of: router.pendingTab) { _, tab in
            guard let tab else { return }
            withAnimation(reduceMotion ? VMotion.reduced : .spring(response: 0.4, dampingFraction: 1)) {
                selection = tab
            }
            router.pendingTab = nil
        }
        .onChange(of: selection) { _, tab in mounted.insert(tab) }
        .task {
            #if DEBUG
            if let v = ProcessInfo.processInfo.environment["VITA_OPEN_DETAIL"] {
                try? await Task.sleep(nanoseconds: 600_000_000)
                router.pendingDetailItemID = (v == "1" ? items.first
                                              : items.first { $0.compoundSlug == v })?.id
            }
            if ProcessInfo.processInfo.environment["VITA_OPEN_SETTINGS"] == "1" {
                try? await Task.sleep(nanoseconds: 400_000_000)
                showSettings = true
            }
            if ProcessInfo.processInfo.environment["VITA_DETENT"] == "large" {
                try? await Task.sleep(nanoseconds: 600_000_000)
                detent = .large
            }
            #endif
        }
    }

    // MARK: Sheet progress (0 = rest, 1 = expanded; slight overshoot allowed)

    /// The two detents' resolved top-edge positions in global coordinates.
    /// Formula validated against the spike's measured values (rest 370 /
    /// large 62 on the 874pt canvas).
    private func detentGeometry(in geo: GeometryProxy) -> (restY: CGFloat, largeY: CGFloat) {
        let safeTop = geo.safeAreaInsets.top
        let height = geo.size.height + safeTop + geo.safeAreaInsets.bottom
        let largeY = safeTop + 10
        return (height - Self.restFraction * (height - largeY), largeY)
    }

    /// Sheet progress derived from the observed sheet top: 0 = rest, 1 = large.
    private func progress(in geo: GeometryProxy) -> CGFloat {
        let (restY, largeY) = detentGeometry(in: geo)
        guard restY > largeY + 1 else { return 0 }
        let raw = (restY - sheetTopY) / (restY - largeY)
        return min(1.2, max(-0.2, raw))
    }

    // MARK: Header copy

    private var currentBlock: DayBlock {
        let c = Calendar.current.dateComponents([.hour, .minute], from: .now)
        return DayBlock.from(minutes: (c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    private var eyebrow: String {
        switch selection {
        case .today: currentBlock.greeting
        case .stack: "Your protocol"
        case .diary: "How you're doing"
        case .chat:  "Ask vita"
        }
    }

    private var subtitle: String? {
        switch selection {
        case .today:
            return TodayRings.snapshot(items: items, logs: logs, asOf: .now).remainingLine
        case .stack:
            if items.isEmpty { return "Nothing added yet." }
            return items.count == 1 ? "One compound." : "\(items.count) compounds."
        case .diary:
            return "Check-ins, weight, and trends."
        case .chat:
            return "Educational, not medical advice."
        }
    }

    // MARK: Card

    @ViewBuilder
    private func cardHost(progress: CGFloat) -> some View {
        ZStack {
            ForEach(AppTab.allCases) { tab in
                if mounted.contains(tab) {
                    tabContent(tab)
                        .opacity(tab == selection ? 1 : 0)
                        .offset(y: tab == selection ? 0 : 10)
                        .allowsHitTesting(tab == selection)
                        .accessibilityHidden(tab != selection)
                }
            }
        }
        .safeAreaPadding(.top, 10)   // clear the notch
        .overlay(alignment: .top) { notch }
        // At rest the card's fold sliced content raw (the diary chart "leaked"
        // out the bottom edge): a soft canvas dissolve at the visible fold,
        // gone once the card expands. Chat is exempt — its floating input
        // footer carries its own fade and must not be washed out.
        .overlay(alignment: .bottom) {
            if selection != .chat {
                // Offset past the home-indicator inset: the overlay aligns to
                // the CONTENT bottom, and axis labels rendering inside the
                // safe-area band below it escaped the first two attempts.
                LinearGradient(stops: [.init(color: VT.canvas.opacity(0), location: 0),
                                       .init(color: VT.canvas, location: 0.55)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 118)
                    .offset(y: 34)
                    .opacity(1 - min(1, max(0, progress)))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .background(SheetTuner { _ in })
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { y in
            guard geometryInitialized else {
                sheetTopY = y
                geometryInitialized = true
                return
            }
            // Interactive drags stream small per-frame deltas (track directly);
            // programmatic/settle changes arrive as one jump (animate the chrome).
            if abs(y - sheetTopY) > 40 {
                withAnimation(reduceMotion ? VMotion.reduced : .spring(response: 0.45, dampingFraction: 1)) {
                    sheetTopY = y
                }
            } else {
                sheetTopY = y
            }
        }
        .presentationDetents(detents, selection: $detent)
        .presentationBackgroundInteraction(.enabled(upThrough: .large))
        .presentationCornerRadius(36)
        .presentationBackground(VT.canvas)
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled()
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: Binding(
            get: { router.pendingDetailItemID != nil },
            set: { if !$0 { router.pendingDetailItemID = nil } }
        )) {
            detailSheet
        }
        // No keyboard detent dance: the sheet controller drops selection changes
        // issued during the keyboard's own presentation (verified empirically —
        // the M38 "auto-expand" never actually moved the card; the old bar's
        // hiding masked it). The system already keeps the focused field above
        // the keyboard, the header stays visible and usable, and the card
        // doesn't jump around while you type.
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

    private var notch: some View {
        Capsule()
            .fill(VT.hairline)
            .frame(width: 42, height: 5)
            .padding(.top, 8)
            .accessibilityHidden(true)
    }

    /// Only present detail for a LIVE item: a reminder for a since-removed (or
    /// mid-delete, faulted) item must never reach CompoundDetailView, whose dose
    /// card reads item.schedule and would trap in SwiftData (the M26
    /// titrationDayStarts crash). If it can't resolve, clear the pending id.
    @ViewBuilder
    private var detailSheet: some View {
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

    /// The catalog compound for a reminder's item, or a placeholder from the item.
    private func detailCompound(_ item: ProtocolItem) -> CatalogCompound {
        if let c = compounds.first(where: { $0.slug == item.compoundSlug }) { return c }
        let c = CatalogCompound(slug: item.compoundSlug)
        c.name = item.displayName; c.categoryRaw = item.categoryRaw
        c.rxStatusRaw = item.rxStatusRaw; c.doseUnitRaw = item.doseUnitRaw
        return c
    }
}

#Preview { ImmersiveRootView() }
