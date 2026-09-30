import Foundation
import Metal
import simd

// Dimensions: each has its own World (chunks, block entities, save folder), generator and
// entity managers. Only the dimension the player is in is simulated.

enum Dim: String, Codable, CaseIterable {
    case overworld, nether, end

    var hasSky: Bool { self == .overworld }        // sun, moon, stars, clouds, daylight cycle
    var ambient: Float { self == .nether ? 0.3 : (self == .end ? 0.3 : 0) }
    var fogColor: V3 { self == .nether ? V3(0.2, 0.03, 0.03) : V3(0.08, 0.05, 0.12) }
    var folder: String? { self == .overworld ? nil : (self == .nether ? "DIM-1" : "DIM1") }
    var displayName: String { self == .overworld ? "Surface" : (self == .nether ? "The Emberdeep" : "The Hollow") }
}

protocol TerrainGenerator: AnyObject {
    func generate(cx: Int, cz: Int) -> [BlockID]
    func tints(cx: Int, cz: Int) -> [UInt32]
    func column(_ x: Int, _ z: Int) -> (height: Int, biome: Biome)
    var structures: StructureCache? { get }
}

extension TerrainGenerator {
    var structures: StructureCache? { nil }
}

final class DimensionState {
    let dim: Dim
    let world: World
    let mobs = MobManager()
    let drops = ItemEntityManager()
    let projectiles = ProjectileManager()
    let tnts = TNTManager()
    init(dim: Dim, world: World) { self.dim = dim; self.world = world; mobs.load(from: world.save) }
}
