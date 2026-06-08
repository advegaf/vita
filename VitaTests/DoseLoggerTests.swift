import XCTest
import SwiftData
@testable import Vita

@MainActor
final class DoseLoggerTests: XCTestCase {

    private var container: ModelContainer!   // retained — a dropped in-memory container traps on use
    private func makeContext() -> ModelContext {
        container = VitaContainer.make(inMemory: true)
        return container.mainContext
    }

    private func makeItem(_ ctx: ModelContext, slug: String = "bpc-157") -> ProtocolItem {
        let item = ProtocolItem()
        item.compoundSlug = slug
        item.displayName = "BPC-157"
        item.doseAmount = 250
        item.doseUnitRaw = "mcg"
        ctx.insert(item)
        return item
    }

    private func occ(_ item: ProtocolItem, _ minutes: Int) -> DoseOccurrence {
        DoseOccurrence(itemID: item.id, minutes: minutes)
    }

    func testLogUpsertFlipsStatusNotDuplicate() throws {
        let ctx = makeContext()
        let item = makeItem(ctx)
        let logger = DoseLogger(context: ctx)
        let o = occ(item, 480)

        logger.log(item: item, occurrence: o, status: .taken)
        logger.log(item: item, occurrence: o, status: .skipped)   // same occurrence → upsert

        let all = try ctx.fetch(FetchDescriptor<DoseLog>())
        XCTAssertEqual(all.count, 1)                               // not duplicated
        XCTAssertEqual(all.first?.status, .skipped)               // flipped
    }

    func testUndoDeletes() throws {
        let ctx = makeContext()
        let item = makeItem(ctx)
        let logger = DoseLogger(context: ctx)
        let o = occ(item, 480)

        logger.log(item: item, occurrence: o, status: .taken)
        XCTAssertNotNil(logger.logged(itemID: item.id, minutes: 480))
        logger.undo(item: item, occurrence: o)
        XCTAssertNil(logger.logged(itemID: item.id, minutes: 480))
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<DoseLog>()).count, 0)
    }

    func testPRNAppendsMultiple() throws {
        let ctx = makeContext()
        let item = makeItem(ctx, slug: "pt-141")
        let logger = DoseLogger(context: ctx)

        logger.logPRN(item: item)
        logger.logPRN(item: item)                                 // PRN logs append (multiple/day)

        let all = try ctx.fetch(FetchDescriptor<DoseLog>())
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.allSatisfy { $0.isPRN })
        XCTAssertNotNil(logger.lastPRN(itemID: item.id))
    }

    func testMatchPredicate() {
        let log = DoseLog()
        log.itemID = UUID()
        log.scheduledMinutes = 480
        let day = Calendar.current.startOfDay(for: Date())
        log.scheduledDayStart = day
        XCTAssertTrue(DoseLogger.matches(log, itemID: log.itemID, dayStart: day, minutes: 480))
        XCTAssertFalse(DoseLogger.matches(log, itemID: log.itemID, dayStart: day, minutes: 481))
        XCTAssertFalse(DoseLogger.matches(log, itemID: UUID(), dayStart: day, minutes: 480))
        log.isPRN = true
        XCTAssertFalse(DoseLogger.matches(log, itemID: log.itemID, dayStart: day, minutes: 480))
    }

    func testStateDerivation() {
        let ctx = makeContext()
        let item = makeItem(ctx)
        let logger = DoseLogger(context: ctx)
        let today = Calendar.current.startOfDay(for: Date())
        let logs0: [DoseLog] = []

        // No log, slot in the future → due; in the past → overdue.
        let nowNoon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: today)!
        XCTAssertEqual(ScheduleService.state(itemID: item.id, minutes: 13 * 60, day: today, logs: logs0, now: nowNoon), .due)
        XCTAssertEqual(ScheduleService.state(itemID: item.id, minutes: 8 * 60, day: today, logs: logs0, now: nowNoon), .overdue)

        // After taking → taken.
        logger.log(item: item, occurrence: occ(item, 8 * 60), on: today, status: .taken)
        let logs = (try? ctx.fetch(FetchDescriptor<DoseLog>())) ?? []
        XCTAssertEqual(ScheduleService.state(itemID: item.id, minutes: 8 * 60, day: today, logs: logs, now: nowNoon), .taken)
    }
}
