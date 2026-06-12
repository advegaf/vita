import Foundation

/// Pure builders for the user-data export (M15). Everything the app records —
/// stack, dose logs, diary, body metrics, lab values — as one JSON backup plus a
/// spreadsheet-friendly doses CSV. Lab scan images are deliberately excluded
/// (they stay on-device). All functions take plain arrays so they unit-test
/// without a container.
enum DataExport {

    // MARK: JSON (full-fidelity backup)

    struct Export: Codable {
        var exportedAt: Date
        var appVersion: String
        var disclaimer: String
        var stack: [StackItem]
        var doseLogs: [DoseEntry]
        var diary: [DiaryDay]
        var bodyMetrics: [BodyEntry]
        var labPanels: [Panel]
    }
    struct StackItem: Codable {
        var compound: String, name: String
        var doseAmount: Double, doseUnit: String
        var frequency: String, timesMinutes: [Int], weekdays: [Int]
        var cycleOnDays: Int, cycleOffDays: Int
        var titration: [TitrationStep]
        var addedAt: Date
    }
    struct TitrationStep: Codable { var dayStart: Int; var dose: Double }
    struct DoseEntry: Codable {
        var compound: String, name: String, dose: String
        var day: Date, minutes: Int, status: String, isPRN: Bool, loggedAt: Date
    }
    struct DiaryDay: Codable {
        var day: Date
        var energy: Int, sleep: Int, mood: Int, libido: Int
        var sideEffects: [String], note: String, loggedAt: Date
    }
    struct BodyEntry: Codable {
        var kind: String, value: Double, unit: String, measuredAt: Date, source: String
    }
    struct Panel: Codable {
        var date: Date, lab: String?, summary: String
        var values: [PanelValue]
    }
    struct PanelValue: Codable {
        var markerKey: String, name: String, value: Double, unit: String
        var refLow: Double?, refHigh: Double?, refText: String?, flag: String
    }

    static func json(items: [ProtocolItem], logs: [DoseLog], entries: [DiaryEntry],
                     metrics: [BodyMetric], panels: [LabPanel],
                     appVersion: String, now: Date = Date()) throws -> Data {
        let export = Export(
            exportedAt: now,
            appVersion: appVersion,
            disclaimer: "Educational records, not medical advice.",
            stack: items.map { item in
                let r = item.schedule
                return StackItem(
                    compound: item.compoundSlug, name: item.displayName,
                    doseAmount: item.doseAmount, doseUnit: item.doseUnit.label,
                    frequency: r?.frequency.rawValue ?? "daily",
                    timesMinutes: r?.timeSlotsMinutes.sorted() ?? [],
                    weekdays: r?.weekdays.sorted() ?? [],
                    cycleOnDays: r?.cycleOnDays ?? 0, cycleOffDays: r?.cycleOffDays ?? 0,
                    titration: (r?.titrationSteps ?? []).map { TitrationStep(dayStart: $0.dayStart, dose: $0.dose) },
                    addedAt: item.addedAt)
            },
            doseLogs: logs.sorted { $0.loggedAt < $1.loggedAt }.map {
                DoseEntry(compound: $0.compoundSlug, name: $0.displayName, dose: $0.doseText,
                          day: $0.scheduledDayStart, minutes: $0.scheduledMinutes,
                          status: $0.statusRaw, isPRN: $0.isPRN, loggedAt: $0.loggedAt)
            },
            diary: entries.sorted { $0.dayStart < $1.dayStart }.map {
                DiaryDay(day: $0.dayStart, energy: $0.energy, sleep: $0.sleep,
                         mood: $0.mood, libido: $0.libido, sideEffects: $0.sideEffectsRaw,
                         note: $0.note, loggedAt: $0.loggedAt)
            },
            bodyMetrics: metrics.sorted { $0.measuredAt < $1.measuredAt }.map {
                BodyEntry(kind: $0.kindRaw, value: $0.valueCanonical,
                          unit: $0.kindRaw == BodyMetricKind.weight.rawValue ? "kg" : "cm",
                          measuredAt: $0.measuredAt, source: $0.sourceRaw)
            },
            labPanels: panels.sorted { $0.effectiveDate < $1.effectiveDate }.map { p in
                Panel(date: p.effectiveDate, lab: p.sourceLabName, summary: p.summary,
                      values: p.orderedValues.map {
                          PanelValue(markerKey: $0.markerKey, name: $0.name, value: $0.value,
                                     unit: $0.unit, refLow: $0.refLow, refHigh: $0.refHigh,
                                     refText: $0.refText, flag: $0.flag.rawValue)
                      })
            })
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(export)
    }

    // MARK: Doses CSV (spreadsheet-friendly)

    static func dosesCSV(logs: [DoseLog], calendar: Calendar = .current) -> String {
        var rows = ["date,time,compound,dose,status,as_needed,logged_at"]
        let iso = ISO8601DateFormatter()
        for log in logs.sorted(by: { $0.loggedAt < $1.loggedAt }) {
            let c = calendar.dateComponents([.year, .month, .day], from: log.scheduledDayStart)
            let date = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            let time = log.isPRN ? "" : String(format: "%02d:%02d", log.scheduledMinutes / 60, log.scheduledMinutes % 60)
            rows.append([date, time, csvField(log.displayName), csvField(log.doseText),
                         log.statusRaw, log.isPRN ? "yes" : "no", iso.string(from: log.loggedAt)]
                .joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    /// RFC-4180 escaping: quote fields containing commas/quotes/newlines, double the quotes.
    static func csvField(_ s: String) -> String {
        guard s.contains(",") || s.contains("\"") || s.contains("\n") else { return s }
        return "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    // MARK: Files

    /// Writes both export files to a temp dir and returns their URLs (JSON first).
    static func writeFiles(json: Data, csv: String, now: Date = Date()) throws -> [URL] {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let stamp = df.string(from: now)
        let dir = FileManager.default.temporaryDirectory
        let jsonURL = dir.appendingPathComponent("Vita export \(stamp).json")
        let csvURL = dir.appendingPathComponent("Vita doses \(stamp).csv")
        try json.write(to: jsonURL)
        // Data(_.utf8) never fails — `data(using:)?.write` was a silent no-op
        // (shared CSV missing) whenever encoding returned nil.
        try Data(csv.utf8).write(to: csvURL)
        return [jsonURL, csvURL]
    }
}
