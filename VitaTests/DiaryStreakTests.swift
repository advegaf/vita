import XCTest
import SwiftData
@testable import Vita

@MainActor
final class DiaryStreakTests: XCTestCase {

    private var container: ModelContainer!
    private func makeContext() -> ModelContext {
        container = VitaContainer.make(inMemory: true)
        return container.mainContext
    }

    private func entry(_ ctx: ModelContext, daysAgo: Int, rated: Bool = true) -> DiaryEntry {
        let e = DiaryEntry()
        e.dayStart = Calendar.current.date(byAdding: .day, value: -daysAgo,
                                           to: Calendar.current.startOfDay(for: Date()))!
        if rated { e.energy = 6 }
        ctx.insert(e)
        return e
    }

    func testConsecutiveDays() {
        let ctx = makeContext()
        _ = entry(ctx, daysAgo: 0); _ = entry(ctx, daysAgo: 1); _ = entry(ctx, daysAgo: 2)
        let all = (try? ctx.fetch(FetchDescriptor<DiaryEntry>())) ?? []
        XCTAssertEqual(DiaryStreak.current(entries: all, asOf: Date()), 3)
    }

    func testTodayUnloggedDoesNotBreak() {
        let ctx = makeContext()
        _ = entry(ctx, daysAgo: 1); _ = entry(ctx, daysAgo: 2)   // today missing
        let all = (try? ctx.fetch(FetchDescriptor<DiaryEntry>())) ?? []
        XCTAssertEqual(DiaryStreak.current(entries: all, asOf: Date()), 2)
    }

    func testGapBreaks() {
        let ctx = makeContext()
        _ = entry(ctx, daysAgo: 0); _ = entry(ctx, daysAgo: 1); _ = entry(ctx, daysAgo: 3)  // day 2 missing
        let all = (try? ctx.fetch(FetchDescriptor<DiaryEntry>())) ?? []
        XCTAssertEqual(DiaryStreak.current(entries: all, asOf: Date()), 2)
    }

    func testNoEntries() {
        XCTAssertEqual(DiaryStreak.current(entries: [], asOf: Date()), 0)
    }

    func testUnratedEntryIsNotDone() {
        let ctx = makeContext()
        _ = entry(ctx, daysAgo: 0, rated: false)   // exists but no rating/note/side-effect
        _ = entry(ctx, daysAgo: 1, rated: true)
        let all = (try? ctx.fetch(FetchDescriptor<DiaryEntry>())) ?? []
        // today unrated (not done) → skipped; yesterday rated → streak 1.
        XCTAssertEqual(DiaryStreak.current(entries: all, asOf: Date()), 1)
    }

    func testNoteOnlyCountsAsLogged() {
        let ctx = makeContext()
        let e = entry(ctx, daysAgo: 0, rated: false); e.note = "tired"
        let all = (try? ctx.fetch(FetchDescriptor<DiaryEntry>())) ?? []
        XCTAssertEqual(DiaryStreak.current(entries: all, asOf: Date()), 1)
    }
}
