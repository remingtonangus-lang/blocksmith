import Foundation
import simd

// The Ashguard: the army holding the Ash Vault at the bottom of the Deep (task 22). Sites, units and the war's state.
enum AshWar {
    static let types: [StructureType] = []
    static func starts(seed: UInt64) -> [StructureStart] { [] }
    // Distance (blocks) from (x, z) to the nearest site's footprint: terrain flattens and keeps pillars and lava away.
    static func clearance(_ x: Int, _ z: Int) -> Float {
        max(0, sqrtf(Float(x * x + z * z)) - 120)
    }
}
