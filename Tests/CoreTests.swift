import Foundation

@main
struct CoreTests {
    static func main() throws {
        let legacyProfile = try JSONDecoder().decode(UserProfile.self, from: Data("{\"heightCm\":180,\"age\":30,\"isMale\":true}".utf8))
        precondition(legacyProfile.autoSyncHealth)
        let measurement = BodyComposition.calculate(weightKg: 80, impedance: 500, profile: legacyProfile)
        precondition(abs(measurement.bmi - 24.7) < 0.1)
        precondition(measurement.bodyFatPercent == 16.5)
        precondition(measurement.bmr == 1813)
        let encoded = try JSONEncoder().encode(measurement)
        let restored = try JSONDecoder().decode(Measurement.self, from: encoded)
        precondition(restored == measurement && restored.id == measurement.id)
        precondition(Scale27.decode([]) == nil)
        precondition(Scale27.decode(Array(repeating: 0, count: 20)) == nil)
        var packet = Array(repeating: UInt8(0), count: 20)
        packet[0] = 0xAC
        packet[1] = 0x29
        let weight = UInt32(70_000) | (1 << 31)
        for i in 0..<4 { packet[2 + i] = UInt8((weight >> (24 - i * 8)) & 0xFF) }
        packet[18] = 213
        guard case let .weight(kg, stable)? = Scale27.decode(packet) else { fatalError("Expected weight packet") }
        precondition(kg == 70 && stable)
        let userPacket = [UInt8](Scale27.encodeUserInfo(deviceType: 0x29, profile: legacyProfile))
        precondition(userPacket.count == 20 && userPacket[9] == 180 && userPacket[12] == 30 && userPacket[18] == 0xD0)
        precondition(Int(userPacket[19]) == (userPacket[2..<19].reduce(0) { $0 + Int($1) } & 0xFF))
        print("PASS profile migration, calculation, history JSON roundtrip, packet validation, weight decoding, user packet checksum")
    }
}
