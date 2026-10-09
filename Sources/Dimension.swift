import Foundation
import Metal
import simd

// Dimensions: each has its own World (chunks, block entities, save folder), generator and
// entity managers. Only the dimension the player is in is simulated.

enum Dim: String, Codable, CaseIterable {
    case overworld, nether, end
    // The Deep (task 22): a whole 384-tall world stacked under the surface (DeepGen.swift, DeepSeam.swift).
    case deep

    var hasSky: Bool { self == .overworld }        // sun, moon, stars, clouds, daylight cycle
    // The Hollow a little brighter than the Emberdeep: its pale stone read grey-brown and the violite pillars as
    // black cut-outs (blind critic, run 362 end_top).
    // The Emberdeep 0.3 -> 0.4: away from lava its dark brick fortresses and blackstone bastions averaged 3-5 % of
    // full brightness and couldn't be read (blind critic, run 369).
    var ambient: Float {
        switch self { case .overworld: return 0; case .nether: return 0.4; case .end: return 0.42; case .deep: return 0.42 }
    }
    var fogColor: V3 {
        switch self {
        case .nether: return V3(0.2, 0.03, 0.03)
        case .deep: return V3(0.15, 0.075, 0.055)
        default: return V3(0.08, 0.05, 0.12)
        }
    }
    var folder: String? {
        switch self { case .overworld: return nil; case .nether: return "DIM-1"; case .end: return "DIM1"; case .deep: return "DIM-2" }
    }
    var displayName: String {
        switch self { case .overworld: return "Surface"; case .nether: return "The Emberdeep"; case .end: return "The Hollow"; case .deep: return "The Deep" }
    }
    // Hot, dry dimensions: water boils away, beds blow up.
    var ultrawarm: Bool { self == .nether || self == .deep }
    // Shown y = internal y - YOFF - yShift: the Deep continues the surface's numbers below its old floor (y -65 down to -448).
    var yShift: Int { self == .deep ? CH : 0 }
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
    init(dim: Dim, world: World) { self.dim = dim; self.world = world; mobs.load(from: world.save); drops.load(from: world.save) }
}
