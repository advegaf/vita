import SwiftUI
import SwiftData

/// The Diary dashboard (M8a). A calm, glanceable screen matching the Today tab's
/// one-focus language: eyebrow + dynamic headline, then a compact Check-in card,
/// a Weight card, and the hero Trend chart. Daily check-in is captured in a focused
/// sheet; weight + measurements in another. Apple Health weight is backfilled
/// read-only on first open. Replaces the M0 placeholder.
struct DiaryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DiaryEntry.dayStart, order: .reverse) private var entries: [DiaryEntry]
    @Query(sort: \BodyMetric.measuredAt, order: .reverse) private var metrics: [BodyMetric]
    @Query private var labPanels: [LabPanel]

    @State private var showCheckIn = false
    @State private var showBodyEntry = false
    @State private var trendMetric: DiaryMetric = .weight
    @State private var didBackfill = false
    @State private var debugOpenLabs = false
    @State private var debugOpenMarker: String?

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { ctx in
                content(now: ctx.date)
            }
        }
        .task { await backfillOnce() }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["VITA_DIARY_SHEET"] == "1" {
                try? await Task.sleep(nanoseconds: 500_000_000)
                showCheckIn = true
            }
            #endif
        }
    }

    private func content(now: Date) -> some View {
        let today = entries.first { Calendar.current.isDate($0.dayStart, inSameDayAs: now) }
        let streak = DiaryStreak.current(entries: entries, asOf: now)
        return ScrollView {
            VStack(alignment: .leading, spacing: VT.sCardGap) {
                header(logged: today?.isLogged ?? false)
                CheckInCard(entry: today, streak: streak) {
                    showCheckIn = true
                }
                WeightCard(metrics: metrics) { showBodyEntry = true }
                TrendCard(metric: $trendMetric, entries: entries, metrics: metrics, now: now,
                          onEmptyAction: {
                              if trendMetric.isRating { showCheckIn = true } else { showBodyEntry = true }
                          })
                NavigationLink { LabsListView() } label: { LabsCard(panels: labPanels) }
                    .buttonStyle(.pressableCard)
            }
            .padding(VT.sSection)
            .padding(.bottom, 24)   // clear the floating Liquid Glass tab bar
        }
        .scrollIndicators(.hidden)
        .background(VT.canvas)
        .navigationDestination(isPresented: $debugOpenLabs) { LabsListView() }
        .navigationDestination(isPresented: Binding(
            get: { debugOpenMarker != nil },
            set: { if !$0 { debugOpenMarker = nil } }
        )) {
            if let key = debugOpenMarker { MarkerTrendView(markerKey: key) }
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["VITA_OPEN_LABS"] == "1" {
                try? await Task.sleep(nanoseconds: 500_000_000)
                debugOpenLabs = true
            }
            if let key = ProcessInfo.processInfo.environment["VITA_OPEN_MARKER"] {
                try? await Task.sleep(nanoseconds: 500_000_000)
                debugOpenMarker = key
            }
            #endif
        }
        .sheet(isPresented: $showCheckIn) {
            CheckInSheet(existing: today)
        }
        .sheet(isPresented: $showBodyEntry) {
            BodyEntrySheet()
        }
    }

    private func header(logged: Bool) -> some View {
        ScreenHeader(eyebrow: "Diary", title: logged ? "Logged today." : "How are you today?")
            .padding(.bottom, 2)
    }

    /// Read-only Health weight backfill, once per session. A no-op if Health is
    /// unavailable/unauthorized (the query simply returns nothing).
    private func backfillOnce() async {
        guard !didBackfill else { return }
        didBackfill = true
        guard HealthKitService.isAvailable else { return }
        let samples = await HealthKitService.shared.weightSamples(daysBack: 90)
        guard !samples.isEmpty else { return }
        DiaryService(context: context).mergeHealthWeights(samples)
    }
}
