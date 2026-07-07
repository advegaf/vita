import Foundation

/// The effectful vitals seam (M38). Isolates HealthKit behind a protocol so the demo
/// and tests can inject deterministic data, mirroring `ClaudeService.make()`.
protocol VitalsProviding: Sendable {
    var isAvailable: Bool { get }
    func requestAuthorization() async -> Bool
    func series(days: Int) async -> VitalsSeries
}

struct HealthVitalsProvider: VitalsProviding {
    var isAvailable: Bool { HealthKitService.isAvailable }
    func requestAuthorization() async -> Bool { await HealthKitService.shared.requestAuthorization() }
    func series(days: Int) async -> VitalsSeries { await HealthKitService.shared.vitalsSeries(days: days) }
}

#if DEBUG
/// Deterministic demo series (VITA_VITALS_DEMO) with a recent HRV dip + resting-HR
/// rise, so screenshots always show a real insight. No randomness — stable per run.
struct DemoVitalsProvider: VitalsProviding {
    var isAvailable: Bool { true }
    func requestAuthorization() async -> Bool { true }

    func series(days: Int) async -> VitalsSeries {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func build(_ base: Double, amp: Double, period: Double,
                   recentShift: Double = 0, recentDays: Int = 10) -> [DatedValue] {
            (0..<days).map { i in
                let back = days - 1 - i                     // i=0 oldest, i=days-1 today
                let day = cal.date(byAdding: .day, value: -back, to: today)!
                let wave = amp * sin(Double(i) / period)
                let shift = back < recentDays ? recentShift : 0
                return DatedValue(day: day, value: base + wave + shift)
            }
        }
        return VitalsSeries(
            hrvMs: build(52, amp: 4, period: 6, recentShift: -12),
            restingHR: build(58, amp: 2, period: 7, recentShift: 4),
            respiratoryRate: build(14, amp: 0.6, period: 5),
            sleepHours: build(7.1, amp: 0.5, period: 4, recentShift: -0.6))
    }
}
#endif

enum VitalsService {
    static func make() -> VitalsProviding {
        #if DEBUG
        if ProcessInfo.processInfo.environment["VITA_VITALS_DEMO"] == "1" {
            return DemoVitalsProvider()
        }
        #endif
        return HealthVitalsProvider()
    }
}
