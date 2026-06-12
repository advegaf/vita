import Foundation

/// The tiny contract between the app and the home-screen widget: today's (and
/// tomorrow's) dose slots with their acted state, written to the App Group as JSON
/// whenever anything changes. The widget never touches SwiftData — no store
/// migration, no schema coupling; it just renders this. THIS FILE IS COMPILED INTO
/// BOTH TARGETS (app + widget) via project.yml.
struct WidgetSnapshot: Codable, Equatable {
    struct Slot: Codable, Equatable {
        var name: String
        var minutes: Int      // minutes-from-midnight
        var acted: Bool       // taken or skipped
        // v2 (optional so v1 JSON still decodes): the interactive log button's
        // intent payload.
        var itemID: UUID?
    }
    struct Day: Codable, Equatable {
        var day: Date         // startOfDay
        var slots: [Slot]     // sorted by minutes
    }

    var generatedAt: Date
    var days: [Day]           // [today, tomorrow]
    // v2 extras (optional: v1 JSON on disk keeps decoding).
    var streak: Int?          // current all-acted day streak
    /// Last 30 days, oldest first: 0 rest · 1 all acted · 2 partial · 3 missed.
    var adherence: [Int]?

    static let appGroupID = "group.com.example.vita"

    static func fileURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("widget-snapshot.json")
    }

    func write() {
        guard let url = Self.fileURL() else { return }   // no App Group → widget shows placeholder
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try? (try? enc.encode(self))?.write(to: url, options: .atomic)
    }

    static func read() -> WidgetSnapshot? {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(WidgetSnapshot.self, from: data)
    }

    // MARK: Pure presentation derivation (unit-tested app-side)

    struct State: Equatable {
        var logged: Int
        var total: Int
        var nextName: String?
        var nextMinutes: Int?
        var isRestDay: Bool { total == 0 }
        var allDone: Bool { total > 0 && logged == total }
    }

    /// What the widget should show at `date`: the matching day's progress and the
    /// first un-acted slot (an overdue slot is still "next" — it wants acting).
    /// Returns nil when the snapshot has no entry for that day — a STALE snapshot
    /// (the app unopened past tomorrow, or a timezone hop), which must read as
    /// "open the app", never be mistaken for a genuine rest day.
    func state(at date: Date, calendar: Calendar = .current) -> State? {
        guard let day = days.first(where: { calendar.isDate($0.day, inSameDayAs: date) }) else {
            return nil
        }
        let logged = day.slots.filter(\.acted).count
        let next = day.slots.first { !$0.acted }
        return State(logged: logged, total: day.slots.count,
                     nextName: next?.name, nextMinutes: next?.minutes)
    }

    /// The matched day's raw slots (for the interactive/upcoming widget rows).
    func day(at date: Date, calendar: Calendar = .current) -> Day? {
        days.first { calendar.isDate($0.day, inSameDayAs: date) }
    }

    /// y*10000+m*100+d — the same zone-independent day key the notification
    /// payloads use; the widget's log intent carries it back to the app.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    /// "9:00 PM" for a slot.
    static func timeText(minutes: Int) -> String {
        let h24 = minutes / 60, m = minutes % 60
        let h12 = h24 % 12 == 0 ? 12 : h24 % 12
        return String(format: "%d:%02d %@", h12, m, h24 < 12 ? "AM" : "PM")
    }
}
