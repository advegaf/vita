import XCTest
import SwiftData
@testable import Vita

@MainActor
final class ReportBuilderTests: XCTestCase {

    private var container: ModelContainer!   // retained — dropped in-memory container traps
    private func makeContext() -> ModelContext {
        container = VitaContainer.make(inMemory: true)
        return container.mainContext
    }

    private let cal = Calendar.current
    private let now = Date(timeIntervalSince1970: 1_780_000_000)   // fixed → stable text

    private func makeItem(_ ctx: ModelContext, name: String = "BPC-157",
                          sortIndex: Int = 0) -> ProtocolItem {
        let item = ProtocolItem()
        item.compoundSlug = name.lowercased()
        item.displayName = name
        item.doseAmount = 250
        item.doseUnitRaw = "mcg"
        item.sortIndex = sortIndex
        let r = ScheduleRule()
        r.frequencyRaw = Frequency.daily.rawValue
        r.timeSlotsMinutes = [480]
        ctx.insert(item); ctx.insert(r)
        r.item = item; item.schedule = r
        return item
    }

    func testEmptySectionsAreNil() {
        let ctx = makeContext()
        let item = makeItem(ctx)
        let r = ReportBuilder.build(items: [item], logs: [], metrics: [], panels: [],
                                    profile: nil, weightUnit: .kg, now: now)
        XCTAssertNil(r.weight)          // no metrics
        XCTAssertNil(r.labs)            // no panels
        XCTAssertNil(r.profileLine)     // no profile
        XCTAssertEqual(r.stack.count, 1)
        XCTAssertEqual(r.adherence.count, 1)
        XCTAssertEqual(r.disclaimer, ReportBuilder.disclaimerText)
    }

    func testGeneratedTextStableWithInjectedNow() {
        let ctx = makeContext()
        let r1 = ReportBuilder.build(items: [makeItem(ctx)], logs: [], metrics: [], panels: [],
                                     profile: nil, weightUnit: .kg, now: now)
        XCTAssertTrue(r1.generatedText.hasPrefix("Generated "))
        let r2 = ReportBuilder.build(items: [], logs: [], metrics: [], panels: [],
                                     profile: nil, weightUnit: .kg, now: now)
        XCTAssertEqual(r1.generatedText, r2.generatedText)
    }

    func testAdherenceMatchesEngine() {
        let ctx = makeContext()
        let item = makeItem(ctx)
        let logger = DoseLogger(context: ctx)
        for daysAgo in 1...5 {
            let day = cal.date(byAdding: .day, value: -daysAgo, to: Date())!
            logger.log(item: item, occurrence: DoseOccurrence(itemID: item.id, minutes: 480),
                       on: day, status: .taken)
        }
        let logs = (try? ctx.fetch(FetchDescriptor<DoseLog>())) ?? []
        let r = ReportBuilder.build(items: [item], logs: logs, metrics: [], panels: [],
                                    profile: nil, weightUnit: .kg, now: Date())
        let expected = Adherence.summary(item: item, logs: logs, days: 30, asOf: Date())
        XCTAssertEqual(r.adherence.first?.d30,
                       .init(logged: expected.logged, scheduled: expected.scheduled))
    }

    func testWeightUnitConversionAndDelta() {
        XCTAssertEqual(ReportBuilder.weightText(82.0, unit: .kg), "82 kg")
        XCTAssertTrue(ReportBuilder.weightText(82.0, unit: .lb).hasSuffix(" lb"))
        XCTAssertTrue(ReportBuilder.deltaText(-1.5, unit: .kg).hasPrefix("-"))
        XCTAssertTrue(ReportBuilder.deltaText(1.5, unit: .kg).hasPrefix("+"))
    }

    func testPaginationChunksLongStacks() {
        let stack = (0..<13).map {
            ReportBuilder.StackLine(name: "Item \($0)", doseText: "1 mg", cadence: "Daily",
                                    sinceText: "since Jun 1", isPRN: false)
        }
        let r = ReportBuilder.Report(generatedText: "Generated", profileLine: nil,
                                     stack: stack, adherence: [], weight: nil, labs: nil,
                                     disclaimer: ReportBuilder.disclaimerText)
        let pages = ReportBuilder.pages(r, maxStackRows: 12)
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].stack.count, 12)
        XCTAssertEqual(pages[1].stack.count, 1)
        XCTAssertEqual(pages[0].stack.first?.name, "Item 0")     // order preserved
        XCTAssertEqual(pages[1].stack.first?.name, "Item 12")
        XCTAssertTrue(pages[0].isFirst)
        XCTAssertFalse(pages[1].isFirst)
    }

    func testPDFWriteProducesFile() throws {
        let ctx = makeContext()
        let r = ReportBuilder.build(items: [makeItem(ctx)], logs: [], metrics: [], panels: [],
                                    profile: nil, weightUnit: .kg, now: now)
        let url = try ReportPDF.write(report: r, now: now)
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size, 1000, "PDF should be non-trivial")
        try? FileManager.default.removeItem(at: url)
    }
}
