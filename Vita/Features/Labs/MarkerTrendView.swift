import SwiftUI
import SwiftData
import Charts

/// One marker's value across every saved panel (M11): a quiet reference band from
/// the latest panel's range, a monotone cyan line, clay points where a result sat
/// out of range, drag-scrub, and a 3-tick date strip. Reached from a panel's value
/// row or the Labs-list Trends index. Educational, never diagnostic.
struct MarkerTrendView: View {
    let markerKey: String
    var markerName: String = ""

    @Query private var allPanels: [LabPanel]
    @State private var selectedDate: Date?
    @State private var lastScrubID: UUID?
    @State private var showScan = false

    var body: some View {
        let s = LabSeries.series(markerKey: markerKey, panels: allPanels)
        let latest = s.points.last
        return ScrollView {
            VStack(alignment: .leading, spacing: VT.sSection) {
                header(latest)
                chartCard(s)
                captions(s, latest: latest)
            }
            .padding(VT.sSection)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(VT.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showScan) { LabScanFlow() }
    }

    /// A one-point trend's missing data is fixable right here — never a dead end.
    private var scanButton: some View {
        Button("Scan another panel →") { showScan = true }
            .font(.system(size: 14, weight: .semibold)).foregroundStyle(VT.dose)
            .buttonStyle(.plain)
    }

    /// Callers pass the printed name; fall back to the newest panel's printed name
    /// (then the raw key) so the headline never shows snake_case.
    private var displayName: String {
        if !markerName.isEmpty { return markerName }
        let named = allPanels
            .sorted { $0.effectiveDate > $1.effectiveDate }
            .compactMap { p in (p.values ?? []).first { $0.markerKey == markerKey && !$0.name.isEmpty } }
            .first
        return named?.name ?? markerKey
    }

    // MARK: Header

    private func header(_ latest: LabTrendPoint?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("MARKER").font(.system(size: 12, weight: .medium)).tracking(0.4)
                .textCase(.uppercase).foregroundStyle(VT.micro)
            Text("\(displayName).").vtHeadlineStyle()
                .lineLimit(2)   // fixed display size; tail-truncates past two lines
            if let latest {
                (Text("\(vtFormatNumber(latest.value)) \(latest.unit)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(latest.isOutOfRange ? VT.overdue : VT.ink)
                 + Text("  ·  \(latest.flag.label)  ·  \(latest.date.formatted(.dateTime.month(.abbreviated).day().year()))")
                    .font(.system(size: 14))
                    .foregroundColor(VT.body))
                .monospacedDigit()
                .padding(.top, 2)
                // The marker's natural next question lives one tap away: prefill
                // chat (never auto-send) with this value in context.
                Button("Ask vita about this →") {
                    NotificationRouter.shared.pendingChatPrompt =
                        "My latest \(displayName) was \(vtFormatNumber(latest.value)) \(latest.unit) (\(latest.flag.label.lowercased())). What does this marker mean and what can affect it?"
                    NotificationRouter.shared.pendingTab = .chat
                }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.dose)
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Chart card

    @ViewBuilder
    private func chartCard(_ s: LabSeries.Series) -> some View {
        let pts = s.points
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                vtLead("Trend.", color: VT.dose)
                Spacer()
                if let c = calloutText(pts) {
                    Text(c.text).font(.system(size: 14, weight: .semibold)).vtTabular()
                        .foregroundStyle(c.flagged ? VT.overdue : VT.dose)
                        .contentTransition(.numericText())
                }
            }
            if pts.isEmpty {
                VStack(spacing: 10) {
                    Text("No plottable results for this marker.")
                        .font(.system(size: 14)).foregroundStyle(VT.micro)
                    scanButton
                }
                .frame(maxWidth: .infinity).frame(height: 120)
            } else {
                if pts.count == 1 {
                    HStack {
                        Text("One result so far.")
                            .font(.system(size: 14)).foregroundStyle(VT.body)
                        Spacer()
                        scanButton
                    }
                }
                chart(pts)
                dateStrip(LabSeries.dateDomain(for: pts))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard(radius: VT.rFocusCard)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(displayName) trend, \(pts.count) result\(pts.count == 1 ? "" : "s")")
    }

    private func chart(_ pts: [LabTrendPoint]) -> some View {
        let domain = LabSeries.dateDomain(for: pts)
        let latest = pts.last
        return Chart {
            // Reference band FIRST so the line and points draw on top of it.
            if let lo = latest?.refLow, let hi = latest?.refHigh {
                RectangleMark(
                    xStart: .value("Start", domain.lowerBound),
                    xEnd: .value("End", domain.upperBound),
                    yStart: .value("Range low", lo),
                    yEnd: .value("Range high", hi))
                    .foregroundStyle(VT.why.opacity(0.07))
            } else if let bound = latest?.refLow ?? latest?.refHigh {
                RuleMark(y: .value("Range bound", bound))
                    .foregroundStyle(VT.hairline)
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
            if pts.count >= 2 {
                ForEach(pts) { p in
                    LineMark(x: .value("Date", p.date), y: .value("Value", p.value))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(VT.dose)
                }
            }
            ForEach(pts) { p in
                PointMark(x: .value("Date", p.date), y: .value("Value", p.value))
                    .foregroundStyle(p.isOutOfRange ? VT.overdue : VT.dose)
                    .symbolSize(60)
            }
            if let sel = selectedPoint(pts) {
                RuleMark(x: .value("Date", sel.date)).foregroundStyle(VT.hairline)
                PointMark(x: .value("Date", sel.date), y: .value("Value", sel.value))
                    .foregroundStyle(sel.isOutOfRange ? VT.overdue : VT.dose)
                    .symbolSize(90)
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: LabSeries.yDomain(points: pts, refLow: latest?.refLow, refHigh: latest?.refHigh))
        .chartXSelection(value: $selectedDate)
        .chartXAxis(.hidden)                                // dates live in the strip below
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                AxisValueLabel().font(.system(size: 11)).foregroundStyle(VT.micro)
            }
        }
        .frame(height: 170)
        .transition(.opacity)
        .onChange(of: selectedDate) { _, _ in
            guard let p = selectedPoint(pts) else { return }
            if lastScrubID != p.id {                        // sparse points: dedupe on identity, not day
                lastScrubID = p.id
                Haptics.segment()
            }
        }
    }

    /// Three calm date ticks: domain start / mid / end. Lab panels can span years,
    /// so the year is shown whenever the domain crosses one.
    private func dateStrip(_ domain: ClosedRange<Date>) -> some View {
        let cal = Calendar.current
        let crossesYear = cal.component(.year, from: domain.lowerBound)
            != cal.component(.year, from: domain.upperBound)
        let mid = Date(timeIntervalSince1970:
            (domain.lowerBound.timeIntervalSince1970 + domain.upperBound.timeIntervalSince1970) / 2)
        func label(_ d: Date) -> String {
            crossesYear
                ? d.formatted(.dateTime.month(.abbreviated).day().year())
                : d.formatted(.dateTime.month(.abbreviated).day())
        }
        return HStack(spacing: 0) {
            Text(label(domain.lowerBound)); Spacer()
            Text(label(mid)); Spacer()
            Text(label(domain.upperBound))
        }
        .font(.system(size: 11, weight: .medium)).foregroundStyle(VT.micro)
    }

    // MARK: Captions

    @ViewBuilder
    private func captions(_ s: LabSeries.Series, latest: LabTrendPoint?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if latest?.refLow != nil || latest?.refHigh != nil {
                Text("Range from your latest panel.")
                    .font(.system(size: 12)).foregroundStyle(VT.micro)
            }
            if s.skippedCount > 0 {
                Text("\(s.skippedCount) result\(s.skippedCount == 1 ? "" : "s") in another unit not shown.")
                    .font(.system(size: 12)).foregroundStyle(VT.micro)
            }
            Text("Educational, not medical advice. Discuss results with your clinician.")
                .font(.system(size: 12)).foregroundStyle(VT.micro)
        }
    }

    // MARK: Scrub

    private func selectedPoint(_ pts: [LabTrendPoint]) -> LabTrendPoint? {
        guard let sel = selectedDate, pts.count >= 2 else { return nil }
        return pts.min { abs($0.date.timeIntervalSince(sel)) < abs($1.date.timeIntervalSince(sel)) }
    }

    private func calloutText(_ pts: [LabTrendPoint]) -> (text: String, flagged: Bool)? {
        guard let t = selectedPoint(pts) ?? pts.last else { return nil }
        let date = t.date.formatted(.dateTime.month(.abbreviated).day())
        return ("\(date) · \(vtFormatNumber(t.value)) \(t.unit)", t.isOutOfRange)
    }
}
