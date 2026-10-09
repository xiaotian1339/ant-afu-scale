import Foundation
import HealthKit

/// 把测量结果写入 Apple「健康」App。
final class HealthKitManager {
    private let store = HKHealthStore()

    private let bodyMass = HKQuantityType(.bodyMass)
    private let bodyFat = HKQuantityType(.bodyFatPercentage)
    private let bmiType = HKQuantityType(.bodyMassIndex)
    private let leanMass = HKQuantityType(.leanBodyMass)
    private let boneMassIdentifier = HKQuantityTypeIdentifier(rawValue: "HKQuantityTypeIdentifierBoneMass")
    private let bodyWaterMassIdentifier = HKQuantityTypeIdentifier(rawValue: "HKQuantityTypeIdentifierBodyWaterMass")

    private var boneMass: HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: boneMassIdentifier)
    }

    private var bodyWaterMass: HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: bodyWaterMassIdentifier)
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// 请求写入权限（首次会弹系统授权页）。
    func requestAuthorization() async throws {
        guard isAvailable else { return }
        var types: Set<HKSampleType> = [bodyMass, bodyFat, bmiType, leanMass]
        if let boneMass { types.insert(boneMass) }
        if let bodyWaterMass { types.insert(bodyWaterMass) }
        try await store.requestAuthorization(toShare: types, read: [])
    }

    /// 写入一次测量：体重、体脂率、BMI、去脂体重。
    func save(_ m: Measurement) async throws {
        guard isAvailable else { return }
        let date = m.date
        var samples: [HKQuantitySample] = []

        samples.append(HKQuantitySample(
            type: bodyMass,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: m.weightKg),
            start: date, end: date))

        samples.append(HKQuantitySample(
            type: bodyFat,
            quantity: HKQuantity(unit: .percent(), doubleValue: m.bodyFatPercent / 100.0),
            start: date, end: date))

        samples.append(HKQuantitySample(
            type: bmiType,
            quantity: HKQuantity(unit: .count(), doubleValue: m.bmi),
            start: date, end: date))

        samples.append(HKQuantitySample(
            type: leanMass,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: m.leanBodyMassKg),
            start: date, end: date))

        if let boneMass {
            samples.append(HKQuantitySample(
                type: boneMass,
                quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: m.boneMassKg),
                start: date, end: date))
        }

        if let bodyWaterMass {
            samples.append(HKQuantitySample(
                type: bodyWaterMass,
                quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: m.bodyWaterKg),
                start: date, end: date))
        }

        try await store.save(samples)
    }
}
