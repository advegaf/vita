import Foundation
import SwiftData
import WidgetKit

/// Builds + publishes the widget snapshot. Called wherever the day's truth changes:
/// app foreground/background, dose log/undo, stack edits. Pure builder + a thin
/// effectful publisher.
@MainActor
enum WidgetBridge {

    /// Pure: today's + tomorrow's slots from the live schedule + logs, plus the
    /// v2 extras (streak + 30-day adherence codes) for the new widget kinds.
    static func snapshot(items: [ProtocolItem], logs: [DoseLog],
                         now: Date = Date(), calendar: Calendar = .current) -> WidgetSnapshot {
        let today = calendar.startOfDay(for: now)
        let days = (0...1).compactMap { offset -> WidgetSnapshot.Day? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            var slots: [WidgetSnapshot.Slot] = []
            for item in items {
                for occ in ScheduleService.occurrences(for: item, on: day, calendar: calendar) {
                    let acted = logs.contains {
                        DoseLogger.matches($0, itemID: occ.itemID, dayStart: day,
                                           minutes: occ.minutes, calendar: calendar)
                    }
                    slots.append(WidgetSnapshot.Slot(name: item.displayName,
                                                     minutes: occ.minutes, acted: acted,
                                                     itemID: item.id))
                }
            }
            return WidgetSnapshot.Day(day: day, slots: slots.sorted { $0.minutes < $1.minutes })
        }
        return WidgetSnapshot(generatedAt: now, days: days,
                              streak: StreakService.currentStreak(items: items, logs: logs,
                                                                  asOf: now, calendar: calendar),
                              adherence: adherenceCodes(items: items, logs: logs,
                                                        asOf: now, calendar: calendar))
    }

    /// Last 30 days across the whole stack, oldest first:
    /// 0 rest · 1 all acted · 2 partial · 3 missed. Today never reads as missed
    /// (the day is still in progress), and days before an item existed don't
    /// count against it (per-item `addedAt` gate, mirroring `Adherence`).
    static func adherenceCodes(items: [ProtocolItem], logs: [DoseLog],
                               asOf now: Date = Date(),
                               calendar: Calendar = .current) -> [Int] {
        let today = calendar.startOfDay(for: now)
        let acted = Set(logs.filter { !$0.isPRN }.map {
            StreakService.actedKey(itemID: $0.itemID, day: $0.scheduledDayStart,
                                   minutes: $0.scheduledMinutes, calendar: calendar)
        })
        return (0..<30).reversed().map { back -> Int in
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { return 0 }
            var occurred = 0, done = 0
            for item in items where item.schedule?.frequency != .prn {
                guard day >= calendar.startOfDay(for: item.addedAt) else { continue }
                for occ in ScheduleService.occurrences(for: item, on: day, calendar: calendar) {
                    occurred += 1
                    if acted.contains(StreakService.actedKey(itemID: occ.itemID, day: day,
                                                             minutes: occ.minutes,
                                                             calendar: calendar)) { done += 1 }
                }
            }
            if occurred == 0 { return 0 }
            if done == occurred { return 1 }
            if calendar.isDate(day, inSameDayAs: today) { return done > 0 ? 2 : 0 } // in progress
            return done > 0 ? 2 : 3
        }
    }

    /// Effectful: fetch, build, write to the App Group, poke WidgetKit.
    static func update(context: ModelContext) {
        let items = (try? context.fetch(FetchDescriptor<ProtocolItem>())) ?? []
        let logs = (try? context.fetch(FetchDescriptor<DoseLog>())) ?? []
        snapshot(items: items, logs: logs).write()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Ingest widget-tapped doses into REAL DoseLogs (idempotent via the
    /// logger's occurrence upsert), then clear the ledger. Called on every app
    /// activation, before the snapshot rewrite.
    static func reconcilePendingLogs(context: ModelContext, directory: URL? = nil) {
        let pending = WidgetActions.read(directory: directory)
        guard !pending.isEmpty else { return }
        let items = (try? context.fetch(FetchDescriptor<ProtocolItem>())) ?? []
        let logger = DoseLogger(context: context)
        for p in pending {
            guard let item = items.first(where: { $0.id == p.itemID }),
                  let day = NotificationManager.date(fromDayKey: p.dayKey) else { continue }
            logger.log(item: item,
                       occurrence: DoseOccurrence(itemID: p.itemID, minutes: p.minutes),
                       on: day, status: .taken)
        }
        WidgetActions.clear(directory: directory)
    }
}
