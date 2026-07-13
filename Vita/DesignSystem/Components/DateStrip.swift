import SwiftUI

/// Journey-style 7-day strip (M40): circular day chips with a tiny weekday
/// label above the number. Past fully-acted days wear a small green check
/// badge; today is a larger BLACK circle (the language's "current" marker);
/// future days are plain. Pure display — day completeness comes in from the
/// caller (derived via ScheduleService/Adherence day logic).
struct DateStrip: View {
    struct Day: Identifiable {
        let date: Date
        let isToday: Bool
        let isDone: Bool
        var id: Date { date }
    }

    var days: [Day]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                chip(day).frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private func chip(_ day: Day) -> some View {
        VStack(spacing: 5) {
            Text(day.date, format: .dateTime.weekday(.abbreviated))
                .font(.system(size: 11, weight: day.isToday ? .semibold : .medium))
                .foregroundStyle(day.isToday ? VT.ink : VT.micro)
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(day.isToday ? AnyShapeStyle(VT.ink) : AnyShapeStyle(VT.card))
                    .frame(width: day.isToday ? 46 : 38, height: day.isToday ? 46 : 38)
                    .shadow(color: VT.shadowColor, radius: 6, y: 3)
                    .overlay {
                        Text(day.date, format: .dateTime.day())
                            .font(.system(size: day.isToday ? 16 : 14,
                                          weight: day.isToday ? .bold : .medium))
                            .vtTabular()
                            .foregroundStyle(day.isToday ? VT.onInk : VT.ink)
                    }
                if day.isDone && !day.isToday {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(VT.onInk)
                        .frame(width: 14, height: 14)
                        .background(VT.delta, in: Circle())
                        .offset(x: 3, y: -2)
                }
            }
            .frame(height: 48)
        }
    }

    private var accessibilitySummary: String {
        let done = days.filter(\.isDone).count
        return "Week strip, \(done) of \(days.count) days complete."
    }

    /// The default window: 5 past days, today, tomorrow.
    static func week(asOf now: Date = .now, isDayDone: (Date) -> Bool,
                     calendar: Calendar = .current) -> [Day] {
        let today = calendar.startOfDay(for: now)
        return (-5...1).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return Day(date: date, isToday: offset == 0, isDone: offset < 0 && isDayDone(date))
        }
    }
}

#Preview {
    DateStrip(days: DateStrip.week(isDayDone: { _ in Bool.random() }))
        .padding(VT.sSection)
        .background(VT.canvas)
}
