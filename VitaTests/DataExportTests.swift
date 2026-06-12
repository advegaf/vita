import XCTest
import SwiftData
@testable import Vita

@MainActor
final class DataExportTests: XCTestCase {

    private var container: ModelContainer!   // retained — a dropped in-memory container traps on use
    private func ctx() -> ModelContext {
        container = VitaContainer.make(inMemory: true)
        return container.mainContext
    }

    func testCSVEscaping() {
        XCTAssertEqual(DataExport.csvField("plain"), "plain")
        XCTAssertEqual(DataExport.csvField("a,b"), "\"a,b\"")
        XCTAssertEqual(DataExport.csvField("say \"hi\""), "\"say \"\"hi\"\"\"")
        XCTAssertEqual(DataExport.csvField("line\nbreak"), "\"line\nbreak\"")
    }

    func testDosesCSVRows() {
        let log = DoseLog()
        log.displayName = "CJC-1295, DAC"            // comma forces quoting
        log.doseText = "200 mcg"
        log.scheduledDayStart = Calendar.current.startOfDay(for: Date())
        log.scheduledMinutes = 9 * 60 + 5
        log.statusRaw = "taken"
        let csv = DataExport.dosesCSV(logs: [log])
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines[0], "date,time,compound,dose,status,as_needed,logged_at")
        XCTAssertTrue(lines[1].contains("09:05"))
        XCTAssertTrue(lines[1].contains("\"CJC-1295, DAC\""))
        XCTAssertTrue(lines[1].contains(",taken,no,"))
    }

    func testJSONRoundTripsWithCounts() throws {
        let c = ctx()
        let item = ProtocolItem(); item.compoundSlug = "bpc-157"; item.displayName = "BPC-157"
        c.insert(item)
        let r = ScheduleRule(); r.frequencyRaw = "daily"; r.timeSlotsMinutes = [480]
        r.titrationDayStarts = [0, 7]; r.titrationDoses = [0.25, 0.5]
        c.insert(r); item.schedule = r

        let log = DoseLog(); log.compoundSlug = "bpc-157"; log.displayName = "BPC-157"
        c.insert(log)
        let entry = DiaryEntry(); entry.energy = 7; c.insert(entry)
        let metric = BodyMetric(); metric.kindRaw = "weight"; metric.valueCanonical = 80
        c.insert(metric)
        LabService(context: c).savePanel(
            LabPanelDTO(panelDate: "2026-05-20", sourceLabName: "Quest",
                        values: [.init(markerKey: "tsh", name: "TSH", value: 2.1, unit: "mIU/L",
                                       refLow: 0.4, refHigh: 4.0)],
                        summary: "s", disclaimer: "d"),
            scanData: nil, mediaType: nil)

        let data = try DataExport.json(
            items: [item], logs: [log], entries: [entry], metrics: [metric],
            panels: (try c.fetch(FetchDescriptor<LabPanel>())), appVersion: "1.0 (1)")

        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let export = try dec.decode(DataExport.Export.self, from: data)
        XCTAssertEqual(export.stack.count, 1)
        XCTAssertEqual(export.stack[0].titration.map(\.dose), [0.25, 0.5])
        XCTAssertEqual(export.doseLogs.count, 1)
        XCTAssertEqual(export.diary.count, 1)
        XCTAssertEqual(export.bodyMetrics[0].unit, "kg")
        XCTAssertEqual(export.labPanels[0].values[0].markerKey, "tsh")
        XCTAssertFalse(export.disclaimer.isEmpty)

        // Dates serialize as ISO-8601 strings (portable), not epoch numbers.
        let raw = String(data: data, encoding: .utf8)!
        XCTAssertTrue(raw.contains("\"exportedAt\" : \""))
    }

    func testWriteFilesNaming() throws {
        let urls = try DataExport.writeFiles(json: Data("{}".utf8), csv: "a,b",
                                             now: Date(timeIntervalSince1970: 1_750_000_000))
        XCTAssertEqual(urls.count, 2)
        XCTAssertTrue(urls[0].lastPathComponent.hasSuffix(".json"))
        XCTAssertTrue(urls[1].lastPathComponent.hasSuffix(".csv"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls[0].path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls[1].path))  // the CSV really lands on disk
        try? FileManager.default.removeItem(at: urls[0])
        try? FileManager.default.removeItem(at: urls[1])
    }
}
