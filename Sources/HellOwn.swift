import Foundation
import simd

// P292 (a, d, e): hell is its own. The creatures copied from the reference game's nether (the wailer, cinderwisp,
// blight, blight skeleton, boarlings and their brutes and undead, tuskers, rot tuskers, magmastriders and lava blobs)
// never spawn again, and any an old save or an old spawner still holds is replaced, where it stands, by the hell
// creature that took over its part:
//   wailer (a flier that shot fire from far off)       -> Searwing (circles high and dives)
//   cinderwisp (the fortress's ranged guard, rods)      -> Slagthrower (lobs slag; drops the Cinder Rods now)
//   blight skeleton (the fortress's sword)             -> Brand Knight
//   boarling brute                                      -> Brand Champion
//   boarling, undead boarling                           -> Brand Squire in hell (a plain zombie on the surface)
//   tusker, rot tusker, lava blob                       -> Scorchling packs in hell (gone elsewhere)
//   the blight (boss) and the magmastrider              -> gone (the Brand Commander is hell's boss)
// And nothing in hell carries a gun: the Ashguard live below the Sealrock, so an Ashguard soldier set in the hell band
// (an old keep's strongroom detail, the seal dig's sentry) takes the matching Brand Order rank, and an Ashguard vehicle
// there is gone.
// P418 (Remington, Oct 23 21:06: "We gotta get rid of Enderman. They can't be in the game"): the voidwalker is retired
// the same way, everywhere, with no heir: it never spawns, and one an old save, a spawner or an egg still holds is gone
// (void pearls still come from boarling barter and the cleric's trades).
extension MobKind {
    static let retiredHellKinds: [MobKind] = [.ghast, .blaze, .wither, .witherSkeleton, .piglin, .piglinBrute, .zombifiedPiglin,
                                              .hoglin, .zoglin, .strider, .magmaCube, .enderman]
    var retiredHell: Bool {
        switch self {
        case .ghast, .blaze, .wither, .witherSkeleton, .piglin, .piglinBrute, .zombifiedPiglin, .hoglin, .zoglin, .strider, .magmaCube,
             .enderman: return true
        default: return false
        }
    }

    // What this kind is where it stands: itself, a retired kind's heir, or nil when it is simply gone.
    func living(inHell: Bool) -> MobKind? {
        switch self {
        case .ghast: return .searwing
        case .blaze: return .slagthrower
        case .witherSkeleton: return .brandKnight
        case .piglinBrute: return .brandChampion
        case .piglin, .zombifiedPiglin: return inHell ? .brandSquire : .zombie
        case .hoglin, .zoglin, .magmaCube: return inHell ? .scorchling : nil
        case .wither, .strider, .enderman: return nil
        default: return self
        }
    }

    // The Brand Order rank that holds an Ashguard soldier's post in hell.
    var orderPost: MobKind? {
        switch Soldier.rank(self) {
        case 0: return .brandSquire
        case 1, 2: return .brandKnight
        case 3, 4: return .brandChampion
        case .some: return .brandSquire
        default: return ashVehicle ? nil : self
        }
    }
}

extension World {
    // The hell band: the Emberdeep, or the Deep between the Sealrock and the upper crust.
    func inHellBand(_ p: V3) -> Bool { dim == .nether || (dim == .deep && DeepGen.inHell(p.y)) }
}

enum HellFate { case keep, gone, becomes(Mob) }

extension Mob {
    // P292: what this mob becomes where it stands (a retired kind anywhere; an Ashguard post in hell).
    func hellFate(_ w: World) -> HellFate {
        let hell = w.inHellBand(pos)
        let k: MobKind?
        if kind.retiredHell { k = kind.living(inHell: hell) }
        else if hell && (kind.ashVehicle || (Soldier.rank(kind) != nil && faction == Faction.ashguard.rawValue)) { k = kind.orderPost }
        else { return .keep }
        guard let into = k else { return .gone }
        let n = Mob(into, at: pos)
        n.yaw = yaw
        n.persistent = persistent
        n.customName = customName
        n.power = power
        n.leash = leash
        if warden {
            // The Keep Castellan (DeepGates.swift): the same boss, now a Brand Champion, with the health it had.
            n.health = Int(Float(health) / Float(max(1, spec.health)) * 240)
            n.wardenRaged = wardenRaged
            n.makeKeepWarden(loading: true)
        }
        HellRetire.converted += 1
        return .becomes(n)
    }
}

enum HellRetire {
    static var converted = 0, removed = 0
}

extension MobManager {
    // Once a tick (MobManager.update): only does anything while a retired kind is about.
    func retireHellIfNeeded(_ g: Game) {
        guard MobKind.retiredHellKinds.contains(where: { !of($0).isEmpty }) else { return }
        retireHell(g)
        rebuildIndex()
    }

    func retireHell(_ g: Game) {
        var add: [Mob] = []
        var gone = Set<ObjectIdentifier>()
        for m in mobs where m.kind.retiredHell {
            if case .becomes(let n) = m.hellFate(g.world) { add.append(n) } else { HellRetire.removed += 1 }
            gone.insert(ObjectIdentifier(m))
            if g.riding === m { g.dismount() }
        }
        guard !gone.isEmpty else { return }
        for m in mobs where m.mount.map({ gone.contains(ObjectIdentifier($0)) }) == true { m.mount = nil; m.jockey = false }
        mobs.removeAll { gone.contains(ObjectIdentifier($0)) }
        mobs += add
    }

    // A mob coming into the world from a save record or a structure: its P292 fate.
    func admit(_ m: Mob, _ w: World) {
        switch m.hellFate(w) {
        case .keep: mobs.append(m)
        case .becomes(let n): mobs.append(n)
        case .gone: HellRetire.removed += 1
        }
    }

    // Hell's natural spawns by land (EmberGen's five biomes; HellLands.swift): which of hell's own a spawn attempt
    // leans to. 0 order patrol, 1 scorchling pack, 2 slagthrower, 3 searwings.
    static func hellLean(_ b: Biome) -> [Int] {
        switch b {
        // (P436: weighted toward each land's own two, HellBiomeMobs.swift)
        case .soulSandValley: return [10, 30, 5, 55]           // the Ash Dunes: Dune Crawlers, Ash Wraiths in the open sky
        case .crimsonForest: return [35, 15, 25, 25]           // the Charwood Thicket: the order, Lurkers and Emberkites
        case .warpedForest: return [20, 55, 5, 20]             // the Gloamwood: Gloamlings and Gloamwings (peaceable)
        case .basaltDeltas: return [10, 35, 45, 10]            // the Ghostglass Spires: Shard Skitters, Glass Wights
        default: return [30, 35, 20, 15]                       // the Cinder Plains: Cinder Hounds and Slagthrowers
        }
    }
}

extension SpawnEggs {
    // P292: eggs of retired kinds stay registered (old saves keep their stacks; one used hatches the heir) but are
    // left out of the creative palette.
    static func retired(_ id: ItemID) -> Bool { kindOf[id]?.retiredHell == true }
}
