import SwiftUI
import SwiftData

/// The Diary dashboard (M42): the measured-data hub. Wearable metrics (sleep,
/// HRV, resting HR, respiratory rate) read live from Apple Health where Oura /
/// Whoop / Fitbit sync, plus weight (Health backfill or manual), body-metric
/// trends, and lab results. The subjective check-in was removed by request.
struct DiaryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DiaryEntry.dayStart, order: .reverse) private var entries: [DiaryEntry]
    @Query(sort: \BodyMetric.measuredAt, order: .reverse) private var metrics: [BodyMetric]
    @Query private var labPanels: [LabPanel]

    @State private var showBodyEntry = false
    @State private var vitals = VitalsSeries()
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
        .task { await loadVitals() }
    }

    /// Live wearable series: demo seed for screenshots, else a read-only
    /// Apple Health fan-out (empty when unauthorized/no data).
    private func loadVitals() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["VITA_DIARY_DEMO"] != nil {
            vitals = .demo()
            return
        }
        #endif
        vitals = await HealthKitService.shared.vitalsSeries(days: 30)
    }

    private func content(now: Date) -> some View {
        return ScrollView {
            VStack(alignment: .leading, spacing: VT.sCardGap) {
                header
                WearablesSection(series: vitals, onConnect: {
                    Task {
                        _ = await HealthKitService.shared.requestAuthorization()
                        await loadVitals()
                    }
                })
                WeightCard(metrics: metrics) { showBodyEntry = true }
                TrendCard(metric: $trendMetric, entries: entries, metrics: metrics, now: now,
                          onEmptyAction: { showBodyEntry = true })
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
        .sheet(isPresented: $showBodyEntry) {
            BodyEntrySheet()
        }
    }

    private var header: some View {
        ScreenHeader(eyebrow: "Diary", title: "Your body's numbers.")
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
