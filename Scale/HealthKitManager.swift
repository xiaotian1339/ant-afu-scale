import Foundation
import HealthKit

enum HealthKitSyncError: LocalizedError {
    case missingEntitlement
    case authorizationDenied

    var errorDescription: String? {
        switch self {
        case .missingEntitlement:
            return "健康权限不可用：当前签名缺少 HealthKit 能力。请用包含 HealthKit 的描述文件重签，并确保 Bundle ID 与描述文件一致。"
        case .authorizationDenied:
            return "没有健康写入权限，请在「健康」App 或系统设置里重新允许写入。"
        }
    }
}

/// 从 Apple「健康」读取到的个人身体资料
struct HealthProfileData {
    var heightCm: Double?
    var age: Int?
    var isMale: Bool?

    var hasAnyData: Bool {
        heightCm != nil || age != nil || isMale != nil
    }
}

/// 把测量结果写入 Apple「健康」App。
final class HealthKitManager {
    private let store = HKHealthStore()

    // 仅写入公开且与测量语义相符的四项。BMR 是每日估算，不是某时间段内实际消耗。
    // iOS 26 未提供骨量、体水分量、肌肉量对应的公开 HealthKit 类型。
    private let bodyMass = HKQuantityType(.bodyMass)
    private let bodyFat = HKQuantityType(.bodyFatPercentage)
    private let bmiType = HKQuantityType(.bodyMassIndex)
    private let leanMass = HKQuantityType(.leanBodyMass)
    private let heightType = HKQuantityType(.height)
    private let dateOfBirthType = HKCharacteristicType(.dateOfBirth)
    private let biologicalSexType = HKCharacteristicType(.biologicalSex)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// 请求写入权限（首次会弹系统授权页）。
    func requestAuthorization() async throws {
        guard isAvailable else { return }
        let types: Set<HKSampleType> = [bodyMass, bodyFat, bmiType, leanMass]
        do {
            try await store.requestAuthorization(toShare: types, read: [heightType, dateOfBirthType, biologicalSexType])
        } catch {
            throw mapError(error)
        }
    }

    /// 从 Apple「健康」异步读取最新的身高（厘米）
    func fetchLatestHeight() async throws -> Double? {
        guard isAvailable else { return nil }
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: heightType,
                                      predicate: nil,
                                      limit: 1,
                                      sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let heightCm = sample.quantity.doubleValue(for: .meterUnit(with: .centi))
                continuation.resume(returning: (heightCm * 10).rounded() / 10.0)
            }
            store.execute(query)
        }
    }

    /// 从 Apple「健康」读取出生日期并计算出当前年龄
    func fetchAge() -> Int? {
        guard isAvailable else { return nil }
        do {
            let components = try store.dateOfBirthComponents()
            guard let birthDate = Calendar.current.date(from: components) else { return nil }
            let ageComponents = Calendar.current.dateComponents([.year], from: birthDate, to: Date())
            return ageComponents.year
        } catch {
            return nil
        }
    }

    /// 从 Apple「健康」读取生理性别（true=男，false=女）
    func fetchBiologicalSex() -> Bool? {
        guard isAvailable else { return nil }
        do {
            let sexObject = try store.biologicalSex()
            switch sexObject.biologicalSex {
            case .male: return true
            case .female: return false
            default: return nil
            }
        } catch {
            return nil
        }
    }

    /// 一键从 Apple「健康」获取全部可用的个人资料
    func fetchUserProfile() async throws -> HealthProfileData {
        guard isAvailable else { return HealthProfileData() }
        let height = try? await fetchLatestHeight()
        let age = fetchAge()
        let isMale = fetchBiologicalSex()
        return HealthProfileData(heightCm: height, age: age, isMale: isMale)
    }

    /// 写入一次测量：体重、体脂率、BMI、去脂体重。
    func save(_ m: Measurement) async throws {
        guard isAvailable else { return }
        try await requestAuthorization()
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

        do {
            try await store.save(samples)
        } catch {
            throw mapError(error)
        }
    }

    private func mapError(_ error: Error) -> Error {
        let nsError = error as NSError
        let text = error.localizedDescription.lowercased()
        if text.contains("missing com.apple.developer.healthkit entitlement") {
            return HealthKitSyncError.missingEntitlement
        }
        if nsError.domain == HKErrorDomain,
           let code = HKError.Code(rawValue: nsError.code),
           code == .errorAuthorizationDenied {
            return HealthKitSyncError.authorizationDenied
        }
        return error
    }
}
