import WidgetKit
import SwiftUI

// Local tokens (the widget target stays self-contained — same hex values as VT).
private enum WT {
    static let canvas  = Color(red: 0xF1 / 255, green: 0xEE / 255, blue: 0xE9 / 255)
    static let ink     = Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1A / 255)
    static let body    = Color(red: 0x6E / 255, green: 0x6E / 255, blue: 0x6E / 255)
    static let micro   = Color(red: 0x9A / 255, green: 0x95 / 255, blue: 0x8C / 255)
    static let dose    = Color(red: 0x2B / 255, green: 0xB3 / 255, blue: 0xF3 / 255)
    static let why     = Color(red: 0x3E / 255, green: 0x2B / 255, blue: 0x22 / 255)
    static let overdue = Color(red: 0xC0 / 255, green: 0x59 / 255, blue: 0x3F / 255)
}

@main
struct VitaWidgetBundle: WidgetBundle {
    var body: some Widget {
        VitaTodayWidget()
        VitaStreakWidget()
        VitaAdherenceWidget()
    }
}

// MARK: - Shared timeline plumbing

struct TodayEntry: TimelineEntry {
    let date: Date
    /// nil = no snapshot yet (app never opened) OR a stale snapshot with no entry
    /// for this day (app unopened past tomorrow / timezone hop). Either way the
    /// widget must invite opening the app — never claim "A rest day."
    let state: WidgetSnapshot.State?
    /// The matched day's raw slots (interactive rows + upcoming list).
    let day: WidgetSnapshot.Day?
    let streak: Int?
    let adherence: [Int]?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now,
                   state: .init(logged: 2, total: 4, nextName: "BPC-157", nextMinutes: 21 * 60),
                   day: nil, streak: 6, adherence: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(entry(at: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        var entries = [entry(at: now)]
        // One more entry at midnight so the widget rolls to tomorrow's schedule even
        // if the app isn't opened; every in-app change rewrites + reloads anyway.
        let cal = Calendar.current
        if let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) {
            entries.append(entry(at: midnight))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
    private func entry(at date: Date) -> TodayEntry {
        let snap = WidgetSnapshot.read()
        return TodayEntry(date: date,
                          state: snap?.state(at: date),
                          day: snap?.day(at: date),
                          streak: snap?.streak,
                          adherence: snap?.adherence)
    }
}

private struct WidgetHeader: View {
    var body: some View {
        Text("VITA").font(.system(size: 10, weight: .semibold)).tracking(0.6)
            .foregroundStyle(WT.micro)
    }
}

private struct OpenAppHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader()
            Spacer()
            Text("Open Vita for today's plan.")
                .font(.system(size: 13)).foregroundStyle(WT.body)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The interactive checkmark that logs a dose right from the widget.
private struct LogButton: View {
    let slot: WidgetSnapshot.Slot
    let day: Date
    var body: some View {
        if slot.acted {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18)).foregroundStyle(WT.why)
        } else if let id = slot.itemID {
            Button(intent: LogDoseIntent(itemID: id,
                                         dayKey: WidgetSnapshot.dayKey(for: day),
                                         minutes: slot.minutes)) {
                Image(systemName: "circle")
                    .font(.system(size: 18)).foregroundStyle(WT.dose)
            }
            .buttonStyle(.plain)
        } else {
            Image(systemName: "circle")
                .font(.system(size: 18)).foregroundStyle(WT.micro)
        }
    }
}

// MARK: - Today widget (small · medium · lock screen)

struct VitaTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VitaTodayWidget", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(WT.canvas, for: .widget)
        }
        .configurationDisplayName("Today's doses")
        .description("Your day at a glance — log the next dose right here.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular: circularView
        case .accessoryRectangular: rectangularView
        default:
            if let s = entry.state {
                family == .systemMedium ? AnyView(mediumView(s)) : AnyView(smallView(s))
            } else {
                AnyView(OpenAppHint())
            }
        }
    }

    // MARK: Lock screen

    private var circularView: some View {
        Gauge(value: Double(entry.state?.logged ?? 0),
              in: 0...Double(max(entry.state?.total ?? 1, 1))) {
            Text("V.")
        } currentValueLabel: {
            if let m = entry.state?.nextMinutes {
                Text(WidgetSnapshot.timeText(minutes: m)).font(.system(size: 11, weight: .semibold))
            } else {
                Text("\(entry.state?.logged ?? 0)/\(entry.state?.total ?? 0)")
            }
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let s = entry.state, let name = s.nextName, let m = s.nextMinutes {
                Text("NEXT · \(s.logged) of \(s.total)").font(.system(size: 11, weight: .semibold))
                Text(name).font(.system(size: 14, weight: .bold)).lineLimit(1)
                Text(WidgetSnapshot.timeText(minutes: m)).font(.system(size: 12, weight: .semibold))
            } else if let s = entry.state, s.allDone {
                Text("VITA").font(.system(size: 11, weight: .semibold))
                Text("All done for today.").font(.system(size: 14, weight: .bold))
            } else {
                Text("VITA").font(.system(size: 11, weight: .semibold))
                Text("Open Vita for today's plan.").font(.system(size: 13))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Home screen

    private func dots(_ s: WidgetSnapshot.State) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<min(s.total, 8), id: \.self) { i in
                Circle().fill(i < s.logged ? WT.why : WT.ink.opacity(0.12))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func smallView(_ s: WidgetSnapshot.State) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                WidgetHeader()
                Spacer()
                if s.total > 0 {
                    Text("\(s.logged) of \(s.total)")
                        .font(.system(size: 11, weight: .medium)).monospacedDigit()
                        .foregroundStyle(WT.micro)
                }
            }
            if s.total > 0 { dots(s) }
            Spacer(minLength: 2)
            if s.isRestDay {
                Text("A rest day.").font(.system(size: 15, weight: .bold)).foregroundStyle(WT.ink)
            } else if s.allDone {
                Text("All done for today.").font(.system(size: 15, weight: .bold)).foregroundStyle(WT.ink)
                Text("Nicely done.").font(.system(size: 12)).foregroundStyle(WT.micro)
            } else if let name = s.nextName, let minutes = s.nextMinutes {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Next").font(.system(size: 11, weight: .semibold)).foregroundStyle(WT.dose)
                        Text(name).font(.system(size: 15, weight: .bold))
                            .foregroundStyle(WT.ink).lineLimit(1).minimumScaleFactor(0.8)
                        Text(WidgetSnapshot.timeText(minutes: minutes))
                            .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(WT.dose)
                    }
                    Spacer(minLength: 0)
                    if let day = entry.day,
                       let slot = day.slots.first(where: { !$0.acted }) {
                        LogButton(slot: slot, day: day.day)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func mediumView(_ s: WidgetSnapshot.State) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                WidgetHeader()
                Spacer()
                if s.total > 0 {
                    HStack(spacing: 6) {
                        dots(s)
                        Text("\(s.logged) of \(s.total)")
                            .font(.system(size: 11, weight: .medium)).monospacedDigit()
                            .foregroundStyle(WT.micro)
                    }
                }
            }
            if s.isRestDay {
                Spacer()
                Text("A rest day.").font(.system(size: 17, weight: .bold)).foregroundStyle(WT.ink)
                Spacer()
            } else if s.allDone {
                Spacer()
                Text("All done for today.").font(.system(size: 17, weight: .bold)).foregroundStyle(WT.ink)
                Text("Nicely done.").font(.system(size: 12)).foregroundStyle(WT.micro)
                Spacer()
            } else if let day = entry.day {
                // Upcoming, tappable: up to three un-acted doses, log right here.
                let upcoming = Array(day.slots.filter { !$0.acted }.prefix(3))
                ForEach(Array(upcoming.enumerated()), id: \.offset) { _, slot in
                    HStack(spacing: 10) {
                        Text(WidgetSnapshot.timeText(minutes: slot.minutes))
                            .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(WT.dose)
                            .frame(width: 64, alignment: .leading)
                        Text(slot.name)
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(WT.ink)
                            .lineLimit(1).minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                        LogButton(slot: slot, day: day.day)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Streak widget (small)

struct VitaStreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VitaStreakWidget", provider: TodayProvider()) { entry in
            StreakWidgetView(entry: entry)
                .containerBackground(WT.canvas, for: .widget)
        }
        .configurationDisplayName("Streak")
        .description("Your current all-logged day streak.")
        .supportedFamilies([.systemSmall])
    }
}

struct StreakWidgetView: View {
    let entry: TodayEntry
    var body: some View {
        if let streak = entry.streak {
            VStack(alignment: .leading, spacing: 4) {
                WidgetHeader()
                Spacer(minLength: 0)
                Text("\(streak)")
                    .font(.system(size: 44, weight: .heavy)).monospacedDigit()
                    .foregroundStyle(WT.ink)
                Text(streak == 1 ? "day streak." : "day streak.")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(WT.why)
                if let s = entry.state, s.total > 0 {
                    Text("\(s.logged) of \(s.total) today")
                        .font(.system(size: 11)).monospacedDigit().foregroundStyle(WT.micro)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            OpenAppHint()
        }
    }
}

// MARK: - 30-day adherence widget (medium)

struct VitaAdherenceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "VitaAdherenceWidget", provider: TodayProvider()) { entry in
            AdherenceWidgetView(entry: entry)
                .containerBackground(WT.canvas, for: .widget)
        }
        .configurationDisplayName("Last 30 days")
        .description("Your month at a glance: logged, partial, and rest days.")
        .supportedFamilies([.systemMedium])
    }
}

struct AdherenceWidgetView: View {
    let entry: TodayEntry

    private func color(_ code: Int) -> Color {
        switch code {
        case 1: WT.why                      // all acted
        case 2: WT.dose                     // partial
        case 3: WT.overdue.opacity(0.35)    // missed (calm clay, never red)
        default: WT.ink.opacity(0.08)       // rest / before tracking
        }
    }

    var body: some View {
        if let days = entry.adherence, days.contains(where: { $0 != 0 }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    WidgetHeader()
                    Spacer()
                    if let streak = entry.streak, streak > 0 {
                        Text("\(streak)-day streak")
                            .font(.system(size: 11, weight: .medium)).monospacedDigit()
                            .foregroundStyle(WT.why)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(0..<2, id: \.self) { row in
                        HStack(spacing: 7) {
                            ForEach(0..<15, id: \.self) { col in
                                let i = row * 15 + col
                                Circle().fill(color(i < days.count ? days[i] : 0))
                                    .frame(width: 9, height: 9)
                            }
                        }
                    }
                }
                Text("Last 30 days.")
                    .font(.system(size: 11)).foregroundStyle(WT.micro)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            OpenAppHint()
        }
    }
}
