import Foundation
import HealthKit

/// Recent Apple Health vitals used to ground protocol generation + chat. All
/// optional — Health may be unauthorized, unavailable, or sparse.
struct HealthSnapshot: Sendable, Equatable {
    var weightKg: Double?
    var heightCm: Double?
    var avgRestingHR: Double?      // bpm
    var avgHRVms: Double?          // SDNN, ms
    var avgSleepHours: Double?     // per night, last 7d
    var avgDailySteps: Double?

    /// One-line summary for the grounding block, or nil if entirely empty.
    var summaryLine: String? {
        var bits: [String] = []
        if let weightKg, weightKg > 0 { bits.append(String(format: "weight %.0f kg", weightKg)) }
        if let heightCm, heightCm > 0 { bits.append(String(format: "height %.0f cm", heightCm)) }
        if let avgRestingHR { bits.append(String(format: "resting HR %.0f bpm", avgRestingHR)) }
        if let avgHRVms { bits.append(String(format: "HRV %.0f ms", avgHRVms)) }
        if let avgSleepHours { bits.append(String(format: "sleep %.1f h", avgSleepHours)) }
        if let avgDailySteps { bits.append(String(format: "%.0f steps/day", avgDailySteps)) }
        return bits.isEmpty ? nil : bits.joined(separator: ", ")
    }
}

/// Read-only HealthKit access (HR/HRV, sleep, weight, steps) + basic
/// characteristics (DOB, biological sex). Confined to an actor; HKHealthStore
/// stays internal. No raw samples are persisted in M3a — Health is the source.
actor HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var t: Set<HKObjectType> = []
        if let m = HKObjectType.quantityType(forIdentifier: .bodyMass) { t.insert(m) }
        if let hr = HKObjectType.quantityType(forIdentifier: .restingHeartRate) { t.insert(hr) }
        if let hrv = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) { t.insert(hrv) }
        if let ht = HKObjectType.quantityType(forIdentifier: .height) { t.insert(ht) }
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { t.insert(steps) }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { t.insert(sleep) }
        t.insert(HKObjectType.characteristicType(forIdentifier: .dateOfBirth)!)
        t.insert(HKObjectType.characteristicType(forIdentifier: .biologicalSex)!)
        return t
    }

    func requestAuthorization() async -> Bool {
        guard Self.isAvailable else { return false }
        return await withCheckedContinuation { cont in
            store.requestAuthorization(toShare: [], read: readTypes) { ok, _ in cont.resume(returning: ok) }
        }
    }

    /// DOB-derived age + biological sex from HealthKit characteristics.
    func characteristics() -> (ageYears: Int?, biologicalSex: String?) {
        guard Self.isAvailable else { return (nil, nil) }
        var age: Int?
        if let dob = try? store.dateOfBirthComponents(),
           let y = Calendar.current.date(from: dob).map({ Calendar.current.dateComponents([.year], from: $0, to: Date()).year }) {
            age = y ?? nil
        }
        var sex: String?
        if let s = try? store.biologicalSex() {
            switch s.biologicalSex {
            case .female: sex = "female"
            case .male: sex = "male"
            case .other: sex = "other"
            default: sex = nil
            }
        }
        return (age, sex)
    }

    func snapshot() async -> HealthSnapshot {
        guard Self.isAvailable else { return HealthSnapshot() }
        async let weight = latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo))
        async let height = latestQuantity(.height, unit: .meterUnit(with: .centi))
        async let hr = avgQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), days: 7)
        async let hrv = avgQuantity(.heartRateVariabilitySDNN, unit: HKUnit.secondUnit(with: .milli), days: 7)
        async let steps = avgDailySum(.stepCount, unit: .count(), days: 7)
        async let sleep = avgSleepHours(days: 7)
        return await HealthSnapshot(
            weightKg: weight, heightCm: height, avgRestingHR: hr, avgHRVms: hrv,
            avgSleepHours: sleep, avgDailySteps: steps)
    }

    /// Quick profile-fill reads — weight + height + DOB/sex only (no sleep/HRV/steps),
    /// so connect / re-sync returns fast.
    func profileVitals() async -> (weightKg: Double?, heightCm: Double?, ageYears: Int?, biologicalSex: String?) {
        guard Self.isAvailable else { return (nil, nil, nil, nil) }
        async let w = latestQuantity(.bodyMass, unit: .gramUnit(with: .kilo))
        async let h = latestQuantity(.height, unit: .meterUnit(with: .centi))
        let chars = characteristics()
        return (await w, await h, chars.ageYears, chars.biologicalSex)
    }

    /// All bodyMass weigh-ins over the last N days as Sendable tuples (uuid, kg,
    /// date), ascending. Read-only — never writes Health. Drives the ~90-day
    /// weight backfill + ongoing reads (idempotent merge by uuid downstream).
    func weightSamples(daysBack: Int = 90) async -> [(uuid: String, kg: Double, date: Date)] {
        guard Self.isAvailable, let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return [] }
        let pred = HKQuery.predicateForSamples(withStart: daysAgo(daysBack), end: Date())
        let unit = HKUnit.gramUnit(with: .kilo)
        return await withCheckedContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [sort]) { _, samples, _ in
                let out = (samples as? [HKQuantitySample] ?? [])
                    .map { (uuid: $0.uuid.uuidString, kg: $0.quantity.doubleValue(for: unit), date: $0.endDate) }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    // MARK: - Queries

    private func latestQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        return await withCheckedContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let v = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit)
                cont.resume(returning: v)
            }
            store.execute(q)
        }
    }

    private func avgQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        let pred = HKQuery.predicateForSamples(withStart: daysAgo(days), end: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred,
                                      options: .discreteAverage) { _, stats, _ in
                cont.resume(returning: stats?.averageQuantity()?.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    private func avgDailySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: id) else { return nil }
        let pred = HKQuery.predicateForSamples(withStart: daysAgo(days), end: Date())
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred,
                                      options: .cumulativeSum) { _, stats, _ in
                guard let total = stats?.sumQuantity()?.doubleValue(for: unit) else {
                    cont.resume(returning: nil); return
                }
                cont.resume(returning: total / Double(days))
            }
            store.execute(q)
        }
    }

    private func avgSleepHours(days: Int) async -> Double? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        let pred = HKQuery.predicateForSamples(withStart: daysAgo(days), end: Date())
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, samples, _ in
                let asleep = (samples as? [HKCategorySample] ?? []).filter { isAsleep($0.value) }
                guard !asleep.isEmpty else { cont.resume(returning: nil); return }
                let seconds = asleep.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
                cont.resume(returning: seconds / 3600.0 / Double(days))
            }
            store.execute(q)
        }
    }

    private func daysAgo(_ d: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -d, to: Date()) ?? Date()
    }
}

/// True for any "asleep" sleep-analysis category value (core/deep/REM/unspecified).
private func isAsleep(_ value: Int) -> Bool {
    [
        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
        HKCategoryValueSleepAnalysis.asleepREM.rawValue,
    ].contains(value)
}
