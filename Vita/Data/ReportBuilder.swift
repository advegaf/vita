import Foundation

/// Pure builder for the shareable physician/coach report (stack, adherence, weight,
/// latest labs). Everything takes plain arrays and an injected `now`, so the whole
/// report is deterministic and testable without a container. Rendering lives in
/// ReportView/ReportPDF; this file never touches UI.
enum ReportBuilder {

    struct Counts: Equatable { var logged: Int; var scheduled: Int }

    struct StackLine: Equatable {
        var name: String
        var doseText: String       // effective (titration-aware) dose
        var cadence: String
        var sinceText: String      // "since Jun 12"
        var isPRN: Bool
    }

    struct AdherenceLine: Equatable {
        var name: String
        var d30: Counts
        var d90: Counts
        var isPRN: Bool
        var prn30: Int             // PRN items: uses in the last 30 days
    }

    struct WeightSection: Equatable {
        var currentText: String    // "82.4 kg" / "181.7 lb"
        var delta30Text: String?   // "-1.2 kg over 30 days"
        var delta90Text: String?
    }

    struct LabRow: Equatable {
        var name: String
        var valueText: String
        var refText: String
        var flagText: String       // "high" / "low" / ""
        var isOutOfRange: Bool
    }

    struct LabsSection: Equatable {
        var dateText: String       // "June 2, 2026"
        var labName: String?
        var rows: [LabRow]
    }

    struct Report: Equatable {
        var generatedText: String  // "Generated July 8, 2026"
        var profileLine: String?   // "34 yr, male, 82 kg" (only fields that exist)
        var stack: [StackLine]
        var adherence: [AdherenceLine]
        var weight: WeightSection?
        var labs: LabsSection?
        var disclaimer: String
    }

    /// One rendered page's worth of content (pure pagination — testable).
    struct ReportPage: Equatable {
        var stack: [StackLine]
        var adherence: [AdherenceLine]
        var weight: WeightSection?
        var labs: LabsSection?
        var isFirst: Bool
    }

    static let disclaimerText = "Personal records kept in Vita. Educational, not medical advice."

    // MARK: Build

    static func build(items: [ProtocolItem], logs: [DoseLog], metrics: [BodyMetric],
                      panels: [LabPanel], profile: UserProfile?, weightUnit: WeightUnit,
                      now: Date = Date(), calendar: Calendar = .current) -> Report {
        let sorted = items.sorted { $0.sortIndex < $1.sortIndex }

        let stack = sorted.map { item in
            StackLine(
                name: item.displayName,
                doseText: item.effectiveDoseText(on: now, calendar: calendar),
                cadence: item.schedule.map { ScheduleService.cadenceLabel(for: $0) } ?? "",
                sinceText: "since \(item.addedAt.formatted(.dateTime.month(.abbreviated).day()))",
                isPRN: item.schedule?.frequency == .prn)
        }

        let adherence = sorted.map { item in
            let itemLogs = logs.filter { $0.itemID == item.id }
            let s30 = Adherence.summary(item: item, logs: itemLogs, days: 30, asOf: now, calendar: calendar)
            let s90 = Adherence.summary(item: item, logs: itemLogs, days: 90, asOf: now, calendar: calendar)
            return AdherenceLine(
                name: item.displayName,
                d30: Counts(logged: s30.logged, scheduled: s30.scheduled),
                d90: Counts(logged: s90.logged, scheduled: s90.scheduled),
                isPRN: item.schedule?.frequency == .prn,
                prn30: Adherence.prnCount(item: item, logs: itemLogs, days: 30, asOf: now, calendar: calendar))
        }

        var weight: WeightSection?
        let t30 = DiarySeries.weightTrend(metrics: metrics, days: 30, asOf: now, calendar: calendar)
        if let currentKg = t30.currentKg {
            let t90 = DiarySeries.weightTrend(metrics: metrics, days: 90, asOf: now, calendar: calendar)
            weight = WeightSection(
                currentText: weightText(currentKg, unit: weightUnit),
                delta30Text: t30.deltaKg.map { "\(deltaText($0, unit: weightUnit)) over 30 days" },
                delta90Text: t90.deltaKg.map { "\(deltaText($0, unit: weightUnit)) over 90 days" })
        }

        var labs: LabsSection?
        if let latest = panels.max(by: { $0.effectiveDate < $1.effectiveDate }) {
            labs = LabsSection(
                dateText: latest.effectiveDate.formatted(.dateTime.month(.wide).day().year()),
                labName: latest.sourceLabName,
                rows: latest.orderedValues.map { v in
                    LabRow(name: v.name, valueText: v.valueDisplay, refText: v.refDisplay,
                           flagText: v.flag == .high ? "high" : (v.flag == .low ? "low" : ""),
                           isOutOfRange: v.flag == .high || v.flag == .low)
                })
        }

        return Report(
            generatedText: "Generated \(now.formatted(.dateTime.month(.wide).day().year()))",
            profileLine: profileLine(profile, weightUnit: weightUnit, now: now, calendar: calendar),
            stack: stack, adherence: adherence, weight: weight, labs: labs,
            disclaimer: disclaimerText)
    }

    /// Pure pagination: page 1 carries stack + adherence (chunking long stacks);
    /// weight + labs ride the last page.
    static func pages(_ r: Report, maxStackRows: Int = 12, maxLabRows: Int = 18) -> [ReportPage] {
        var pages: [ReportPage] = []
        var stackChunks = stride(from: 0, to: max(r.stack.count, 1), by: maxStackRows).map {
            Array(r.stack.dropFirst($0).prefix(maxStackRows))
        }
        if stackChunks.isEmpty { stackChunks = [[]] }
        for (i, chunk) in stackChunks.enumerated() {
            pages.append(ReportPage(stack: chunk,
                                    adherence: i == stackChunks.count - 1 ? r.adherence : [],
                                    weight: nil, labs: nil, isFirst: i == 0))
        }
        // Weight + labs on the final page (append to it; labs overflow gets its own).
        pages[pages.count - 1].weight = r.weight
        if let labs = r.labs {
            if labs.rows.count <= maxLabRows {
                pages[pages.count - 1].labs = labs
            } else {
                var first = labs; first.rows = Array(labs.rows.prefix(maxLabRows))
                pages[pages.count - 1].labs = first
                var rest = labs; rest.rows = Array(labs.rows.dropFirst(maxLabRows))
                pages.append(ReportPage(stack: [], adherence: [], weight: nil,
                                        labs: rest, isFirst: false))
            }
        }
        return pages
    }

    // MARK: Formatting helpers (pure)

    static func weightText(_ kg: Double, unit: WeightUnit) -> String {
        unit == .lb ? "\(Units.trim(Units.kgToLb(kg))) lb" : "\(Units.trim(kg)) kg"
    }

    static func deltaText(_ deltaKg: Double, unit: WeightUnit) -> String {
        let v = unit == .lb ? Units.kgToLb(deltaKg) : deltaKg
        let sign = v >= 0 ? "+" : ""
        return "\(sign)\(Units.trim(v)) \(unit == .lb ? "lb" : "kg")"
    }

    static func profileLine(_ profile: UserProfile?, weightUnit: WeightUnit,
                            now: Date, calendar: Calendar = .current) -> String? {
        guard let profile else { return nil }
        var bits: [String] = []
        if let dob = profile.birthDate,
           let age = calendar.dateComponents([.year], from: dob, to: now).year {
            bits.append("\(age) yr")
        }
        if let sex = profile.biologicalSexRaw { bits.append(sex) }
        if let kg = profile.weightKg, kg > 0 { bits.append(weightText(kg, unit: weightUnit)) }
        return bits.isEmpty ? nil : bits.joined(separator: ", ")
    }
}
