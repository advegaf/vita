import Foundation
import SwiftData

/// One lab scan to interpret: EXIF-stripped jpeg OR pdf bytes + its wire media type.
struct LabScanInput: Sendable, Equatable {
    var imageData: Data
    var mediaType: String      // "image/jpeg" | "application/pdf"
}

/// Reads a scan via Claude vision, persists panels, and derives flags/deltas.
/// Mirrors DiaryService: `@MainActor struct` + pure `nonisolated static` helpers.
@MainActor
struct LabService {
    let context: ModelContext

    // MARK: - Pure flag computation (deterministic; ignores the model's flag_raw)

    nonisolated static func computeFlag(value: Double, refLow: Double?, refHigh: Double?) -> LabFlag {
        switch (refLow, refHigh) {
        case let (lo?, hi?):
            if value < lo { return .low }
            if value > hi { return .high }
            return .normal
        case let (lo?, nil):
            return value < lo ? .low : .normal
        case let (nil, hi?):
            return value > hi ? .high : .normal
        case (nil, nil):
            return .unknown
        }
    }

    // MARK: - Interpret (Claude vision)

    func interpret(imageData: Data, mediaType: String) async throws -> LabPanelDTO {
        try await ClaudeServiceFactory.make().interpretLabs(LabScanInput(imageData: imageData, mediaType: mediaType))
    }

    // MARK: - Persist (review-edited DTO → panel + values, flags recomputed)

    @discardableResult
    func savePanel(_ dto: LabPanelDTO, scanData: Data?, mediaType: String?, at when: Date = Date()) -> LabPanel {
        let panel = LabPanel()
        panel.scannedAt = when
        panel.panelDate = Self.parseDate(dto.panelDate)
        panel.sourceLabName = (dto.sourceLabName?.isEmpty == true) ? nil : dto.sourceLabName
        panel.summary = dto.summary
        panel.disclaimer = dto.disclaimer
        panel.scanData = scanData
        panel.scanMediaType = mediaType
        context.insert(panel)                                  // insert BEFORE wiring the relationship
        for v in dto.values where !v.markerKey.isEmpty {
            let lv = LabValue()
            lv.markerKey = v.markerKey; lv.name = v.name
            lv.value = v.value; lv.unit = v.unit
            lv.refLow = v.refLow; lv.refHigh = v.refHigh; lv.refText = v.refText
            lv.flagRaw = v.flagRaw
            lv.flagComputedRaw = Self.computeFlag(value: v.value, refLow: v.refLow, refHigh: v.refHigh).rawValue
            context.insert(lv)
            lv.panel = panel                                   // inverse only AFTER both inserted
        }
        context.saveLogged("LabService")
        return panel
    }

    // MARK: - Fetch + delta

    func panels() -> [LabPanel] {
        let all = (try? context.fetch(FetchDescriptor<LabPanel>())) ?? []
        return all.sorted { $0.effectiveDate > $1.effectiveDate }   // newest first
    }

    /// Signed change for a marker vs the most-recent strictly-older panel that has it.
    nonisolated static func deltaVsPrevious(markerKey: String, panel: LabPanel,
                                            allPanels: [LabPanel]) -> Double? {
        guard let current = (panel.values ?? []).first(where: { $0.markerKey == markerKey }) else { return nil }
        let anchor = panel.effectiveDate
        let prior = allPanels
            .filter { $0.id != panel.id && $0.effectiveDate < anchor }
            .sorted { $0.effectiveDate > $1.effectiveDate }
        for p in prior {
            if let pv = (p.values ?? []).first(where: { $0.markerKey == markerKey }) {
                return current.value - pv.value             // + up, - down
            }
        }
        return nil
    }

    nonisolated static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withFullDate]
        if let d = iso.date(from: s) { return d }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}
