#if DEBUG
import Foundation
import SwiftData

/// Debug-only: seed two lab panels (an older one so "vs last" deltas show) for
/// screenshots. `VITA_LABS_DEMO=1`. Never ships.
@MainActor
enum LabDemoSeed {
    static func populate(_ context: ModelContext) {
        let settings = CatalogStore.fetchOrCreateSettings(context)
        let profile = CatalogStore.fetchOrCreateProfile(context, settings: settings)
        if profile.onboardedAt == nil { profile.onboardedAt = Date() }
        settings.labConsentedAt = Date()

        let existing = (try? context.fetch(FetchDescriptor<LabPanel>())) ?? []
        guard existing.isEmpty else { return }

        let svc = LabService(context: context)
        let cal = Calendar.current
        let now = Date()

        // Oldest panel (~6 months ago) so trended markers chart 3-point stories
        // (glucose drifting high, LDL rising, vitamin D declining into clay).
        svc.savePanel(LabPanelDTO(
            panelDate: nil, sourceLabName: "LabCorp",
            values: [
                .init(markerKey: "glucose_fasting", name: "Glucose, Fasting", value: 92, unit: "mg/dL", refLow: 70, refHigh: 99),
                .init(markerKey: "ldl_cholesterol", name: "LDL Cholesterol", value: 115, unit: "mg/dL", refLow: nil, refHigh: 100),
                .init(markerKey: "vitamin_d", name: "Vitamin D, 25-OH", value: 34, unit: "ng/mL", refLow: 30, refHigh: 100),
                .init(markerKey: "tsh", name: "TSH", value: 1.7, unit: "mIU/L", refLow: 0.4, refHigh: 4.0),
                .init(markerKey: "testosterone_total", name: "Testosterone, Total", value: 480, unit: "ng/dL", refLow: 264, refHigh: 916),
            ],
            summary: "Everything sat in range except LDL. Educational only.",
            disclaimer: "Educational, not medical advice. Discuss results with your clinician."),
            scanData: nil, mediaType: nil,
            at: cal.date(byAdding: .day, value: -184, to: now)!)

        // Older panel (~3 months ago).
        svc.savePanel(LabPanelDTO(
            panelDate: nil, sourceLabName: "LabCorp",
            values: [
                .init(markerKey: "glucose_fasting", name: "Glucose, Fasting", value: 96, unit: "mg/dL", refLow: 70, refHigh: 99),
                .init(markerKey: "ldl_cholesterol", name: "LDL Cholesterol", value: 122, unit: "mg/dL", refLow: nil, refHigh: 100),
                .init(markerKey: "vitamin_d", name: "Vitamin D, 25-OH", value: 28, unit: "ng/mL", refLow: 30, refHigh: 100),
                .init(markerKey: "tsh", name: "TSH", value: 1.9, unit: "mIU/L", refLow: 0.4, refHigh: 4.0),
                .init(markerKey: "testosterone_total", name: "Testosterone, Total", value: 540, unit: "ng/dL", refLow: 264, refHigh: 916),
            ],
            summary: "LDL and vitamin D sat just outside the printed ranges. Educational only.",
            disclaimer: "Educational, not medical advice. Discuss results with your clinician."),
            scanData: nil, mediaType: nil,
            at: cal.date(byAdding: .day, value: -92, to: now)!)

        // Recent panel.
        svc.savePanel(LabPanelDTO(
            panelDate: "2026-05-20", sourceLabName: "Quest Diagnostics",
            values: [
                .init(markerKey: "glucose_fasting", name: "Glucose, Fasting", value: 104, unit: "mg/dL", refLow: 70, refHigh: 99, flagRaw: "H"),
                .init(markerKey: "hdl_cholesterol", name: "HDL Cholesterol", value: 41, unit: "mg/dL", refLow: 40, refHigh: nil),
                .init(markerKey: "ldl_cholesterol", name: "LDL Cholesterol", value: 138, unit: "mg/dL", refLow: nil, refHigh: 100, flagRaw: "H"),
                .init(markerKey: "triglycerides", name: "Triglycerides", value: 90, unit: "mg/dL", refLow: nil, refHigh: 150),
                .init(markerKey: "tsh", name: "TSH", value: 2.1, unit: "mIU/L", refLow: 0.4, refHigh: 4.0),
                .init(markerKey: "vitamin_d", name: "Vitamin D, 25-OH", value: 22, unit: "ng/mL", refLow: 30, refHigh: 100, flagRaw: "L"),
                .init(markerKey: "testosterone_total", name: "Testosterone, Total", value: 612, unit: "ng/dL", refLow: 264, refHigh: 916),
            ],
            summary: "A few values sit outside the printed ranges: fasting glucose and LDL read high, vitamin D reads low. Educational only.",
            disclaimer: "Educational, not medical advice. Discuss results with your clinician."),
            scanData: nil, mediaType: nil, at: now)
    }
}
#endif
