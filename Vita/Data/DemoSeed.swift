#if DEBUG
import Foundation
import SwiftData

/// Debug-only: pre-populate a small stack so screenshots show a real Today.
/// Triggered by the `VITA_DEMO_STACK=1` launch env var. Never ships.
@MainActor
enum DemoSeed {
    static func populate(_ context: ModelContext) {
        // Mark onboarded so the demo stack skips the wizard.
        let settings = CatalogStore.fetchOrCreateSettings(context)
        let profile = CatalogStore.fetchOrCreateProfile(context, settings: settings)
        if profile.onboardedAt == nil { profile.onboardedAt = Date(); try? context.save() }

        let svc = StackService(context: context)
        guard svc.items().isEmpty else { return }
        let all = (try? context.fetch(FetchDescriptor<CatalogCompound>())) ?? []
        func compound(_ slug: String) -> CatalogCompound? { all.first { $0.slug == slug } }

        // Notification smoke test: a peptide due ~2 min from now.
        if ProcessInfo.processInfo.environment["VITA_NOTIF_TEST"] == "1", let bpc = compound("bpc-157") {
            let soon = Calendar.current.date(byAdding: .minute, value: 2, to: Date())!
            let c = Calendar.current.dateComponents([.hour, .minute], from: soon)
            var d = svc.draft(for: bpc)
            d.frequency = .daily
            d.times = [(c.hour ?? 0) * 60 + (c.minute ?? 0)]
            d.doseUnit = .mcg; d.doseAmount = 250
            svc.commit(d)
            return
        }

        // Vial-lifecycle demo (M37): one vial running low, one past its beyond-use day.
        if ProcessInfo.processInfo.environment["VITA_VIAL_DEMO"] == "1" {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let logger = DoseLogger(context: context)
            // Running low: 5 mg vial (20 doses), reconstituted 22 days ago, 18 taken → ~2 left.
            if let bpc = compound("bpc-157") {
                var d = svc.draft(for: bpc)
                d.frequency = .daily; d.times = [8 * 60]
                d.doseUnit = .mcg; d.doseAmount = 250
                d.hasVial = true; d.vialMg = 5; d.waterMl = 2; d.syringe = .u100
                svc.commit(d)
                if let item = svc.item(forSlug: "bpc-157"), let vial = item.vial {
                    vial.reconstitutedAt = cal.date(byAdding: .day, value: -22, to: today)!
                    item.addedAt = vial.reconstitutedAt
                    for daysAgo in 1...18 {
                        let day = cal.date(byAdding: .day, value: -daysAgo, to: today)!
                        logger.log(item: item, occurrence: DoseOccurrence(itemID: item.id, minutes: 8 * 60),
                                   on: day, status: .taken)
                    }
                }
            }
            // Past beyond-use: 10 mg vial reconstituted 31 days ago (BUD 28), barely used.
            if let tb = compound("tb-500") {
                var d = svc.draft(for: tb)
                d.frequency = .daily; d.times = [9 * 60]
                d.doseUnit = .mg; d.doseAmount = 0.5
                d.hasVial = true; d.vialMg = 10; d.waterMl = 2; d.syringe = .u100
                svc.commit(d)
                if let item = svc.item(forSlug: "tb-500"), let vial = item.vial {
                    vial.reconstitutedAt = cal.date(byAdding: .day, value: -31, to: today)!
                    item.addedAt = vial.reconstitutedAt
                }
            }
            context.saveLogged("VialDemo")
            NotificationManager.rebuild(context: context)
            return
        }

        // Cycles + titration demo (M9): a cycled daily peptide + a titrating GLP-1 ramp.
        if ProcessInfo.processInfo.environment["VITA_CYCLE_DEMO"] == "1" {
            let cal = Calendar.current
            // 8 weeks on / 4 weeks off, started 2 weeks ago → "On · week 3 of 8".
            if let cjc = compound("cjc-1295-ipamorelin") {
                var d = svc.draft(for: cjc)
                d.frequency = .daily
                d.times = [21 * 60]
                d.protocolStart = cal.date(byAdding: .day, value: -14, to: Date()) ?? Date()
                d.cycleEnabled = true
                d.cycleUnit = .weeks
                d.cycleOnValue = 8
                d.cycleOffValue = 4
                svc.commit(d)
            }
            // A cycled item currently in its OFF block → a quiet "resting" row on Today.
            if let tb = compound("tb-500") {
                var d = svc.draft(for: tb)
                d.frequency = .daily
                d.times = [8 * 60]
                d.protocolStart = cal.date(byAdding: .day, value: -5, to: Date()) ?? Date()   // day 5 of 5-on/2-off → resting
                d.cycleEnabled = true
                d.cycleUnit = .days
                d.cycleOnValue = 5
                d.cycleOffValue = 2
                svc.commit(d)
            }
            // Weekly GLP-1 ramp 0.25 → 0.5 → 1.0 mg, started 4 weeks ago → active 0.5, next 1.0 in 4 wks.
            // Slot at 12:00 AM so the pin reads overdue (with its duration) at any demo hour.
            if let sema = compound("semaglutide") {
                var d = svc.draft(for: sema)
                d.frequency = .weekly
                d.weekdays = [cal.component(.weekday, from: Date())]   // due today
                d.times = [0]
                d.doseUnit = .mg; d.doseAmount = 0.25
                d.protocolStart = cal.date(byAdding: .day, value: -28, to: Date()) ?? Date()
                d.titrationEnabled = true
                d.titrationSteps = [
                    TitrationStepDraft(weekN: 1, dose: 0.25),
                    TitrationStepDraft(weekN: 5, dose: 0.5),
                    TitrationStepDraft(weekN: 9, dose: 1.0),
                ]
                svc.commit(d)
            }
            return
        }

        // BPC-157 twice daily (AM + PM), with a vial set up so units show.
        if let bpc = compound("bpc-157") {
            var d = svc.draft(for: bpc)
            d.frequency = .daily
            d.times = [8 * 60, 21 * 60]
            d.doseUnit = .mcg; d.doseAmount = 250
            d.hasVial = true; d.vialMg = 5; d.waterMl = 2; d.syringe = .u100   // 250mcg → 10u
            svc.commit(d)
        }
        // CJC-1295+Ipamorelin nightly.
        if let cjc = compound("cjc-1295-ipamorelin") {
            var d = svc.draft(for: cjc)
            d.frequency = .daily
            d.times = [22 * 60]
            svc.commit(d)
        }
        // Semaglutide weekly (Sunday morning) — RX.
        if let sema = compound("semaglutide") {
            var d = svc.draft(for: sema)
            d.frequency = .weekly
            d.weekdays = [1]
            d.times = [9 * 60]
            svc.commit(d)
        }
        // PT-141 as-needed (PRN) — drives the "As needed" card.
        if let pt = compound("pt-141") {
            var d = svc.draft(for: pt)
            d.frequency = .prn
            svc.commit(d)
        }
        // Pre-log the BPC-157 morning dose so a taken pin + DotMeter progress show,
        // and backdate ten days of mixed history so the detail's Adherence card
        // (M13) has a real story: mostly taken, one skipped day, two missed.
        if let bpc = svc.item(forSlug: "bpc-157") {
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            bpc.addedAt = cal.date(byAdding: .day, value: -10, to: today)!
            let logger = DoseLogger(context: context)
            logger.log(item: bpc, occurrence: DoseOccurrence(itemID: bpc.id, minutes: 8 * 60), status: .taken)
            for daysAgo in 1...10 {
                guard ![3, 7].contains(daysAgo) else { continue }              // missed days
                let day = cal.date(byAdding: .day, value: -daysAgo, to: today)!
                let status: DoseStatus = daysAgo == 5 ? .skipped : .taken      // one skipped day
                for minutes in [8 * 60, 21 * 60] {                             // both daily slots
                    logger.log(item: bpc, occurrence: DoseOccurrence(itemID: bpc.id, minutes: minutes),
                               on: day, status: status)
                }
            }
        }
    }
}
#endif
