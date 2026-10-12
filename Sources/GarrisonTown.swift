import Foundation
import simd

// P48 (Oct 11 evening playtest): "military bases get a small town beside them, like the capital town: the player can
// shop there undetected, but the guards are on edge". Below each Capital citadel's south gate, across a road from it,
// a row of frontier buildings (general store, saloon, gunsmith, doctor and two houses, Village.buildLot) with two
// Capital troopers posted at the road's ends. The garrison leaves a visitor alone while they are in the row (the
// soldiers do not mark you there: GarrisonTown.shelters) but they are on edge: a weapon out for more than a few
// seconds, or a blow at anyone, and the whole row opens fire. Only on ground first generated with this rule
// (WorldRules.savedBeforeP44, the same guard as P44 and P62), so nothing explored grows half a building.
enum GarrisonTown {
    static let roadZ = 64                // the road's north edge, blocks south of the citadel's centre
    static let lotZ = 68                 // the buildings' fronts
    static let halfW = 32
    // (kind, shop, x offset)
    static let lots: [(Village.Kind, String, Int)] = [(.shop, "general", -30), (.saloon, "saloon", -19), (.shop, "gunsmith", -6),
                                                      (.shop, "doctor", 5), (.mediumHouse, "", 16), (.smallHouse, "", 25)]
    static let patience: Float = 4       // seconds with a weapon out before the guards open fire
    static let warnAt: Float = 1

    // Pieces for the citadel centred at (x, z) on a site of floor y0 (MilitaryBase.type).
    static func pieces(_ gen: WorldGen, _ x: Int, _ z: Int, _ seed: UInt64) -> [Piece] {
        let style = Village.style(gen.column(x, z + lotZ + 4).biome) ?? .plains
        let m = Village.mats(style)
        var out: [Piece] = []
        var rng = SRng(seed ^ 0x6A77 ^ (UInt64(UInt32(truncatingIfNeeded: x)) << 32 | UInt64(UInt32(truncatingIfNeeded: z))) &* 0x9E3779B97F4A7C15)   // each site its own row
        var built = 0
        for (kind, job, dx) in lots {
            let (w, d) = Village.size(kind)
            let ax = x + dx, az = z + lotZ
            let gy = gen.groundY(ax + w / 2, az + d / 2)
            var ok = gy > SEA
            for (cx, cz) in [(ax, az), (ax + w - 1, az), (ax, az + d - 1), (ax + w - 1, az + d - 1)] where ok {
                let c = gen.column(cx, cz)
                if c.biome.isOcean || c.biome == .river || abs(gen.groundY(cx, cz) - gy) > 4 { ok = false }
            }
            let lotSeed = rng.next()
            guard ok else { continue }
            let lot = Village.Lot(kind: kind, ax: ax, az: az, face: 0, w: w, d: d, y: gy + 1, seed: lotSeed, job: job, frontier: true)
            let (x0, z0, x1, z1) = Village.bounds(lot)
            out.append(Piece(min: IVec3(x0 - 3, lot.y - 12, z0 - 3), max: IVec3(x1 + 3, lot.y + 14, z1 + 3)) { w in
                w.low.off = true; defer { w.low.off = false }       // (no fill under the eaves: village houses build their own)
                Village.sealCaves(&w, x0 - 3, z0 - 3, x1 + 3, z1 + 3, top: lot.y + 6, floor: lot.y, depth: lot.y - 7)
                Village.buildLot(&w, lot, m, style)
            })
            built += 1
        }
        guard built >= 3 else { return [] }
        // The road along the fronts and up to the gate, the guards at its ends, the name board.
        let name = Townsfolk.townName(x, z + roadZ, seed: seed)
        let y = gen.groundY(x, z + roadZ)
        out.append(Piece(min: IVec3(x - halfW - 2, y - 8, z + CapitalBase.A), max: IVec3(x + halfW + 2, y + 8, z + roadZ + 3)) { w in
            w.low.off = true; defer { w.low.off = false }
            func path(_ px: Int, _ pz: Int) {
                guard w.inside(px, 0, pz) else { return }
                let gy = gen.groundY(px, pz)
                guard gy > SEA, !Blocks.isLiquid(w.get(px, gy, pz)) else { return }
                w.set(px, gy, pz, m.path)
                for k in 1...3 where !Blocks.collide[Int(w.get(px, gy + k, pz))] || CapitalBase.isLeaf(w.get(px, gy + k, pz)) { w.set(px, gy + k, pz, AIR) }
            }
            for pz in (z + roadZ)...(z + roadZ + 2) { for px in (x - halfW)...(x + halfW) { path(px, pz) } }
            for pz in (z + CapitalBase.A + 1)..<(z + roadZ) { for px in (x - 1)...(x + 1) { path(px, pz) } }
            for ex in [x - halfW + 1, x + halfW - 1] {
                let gy = gen.groundY(ex, z + roadZ + 1)
                w.mob("soldier_trooper", V3(Float(ex) + 0.5, Float(gy + 1), Float(z + roadZ + 1) + 0.5))
            }
            let sx = x + 3, sz = z + roadZ - 1, gy = gen.groundY(sx, sz)
            guard w.inside(sx, gy + 1, sz), gy > SEA else { return }
            w.set(sx, gy + 1, sz, m.fence)
            let sign = Village.blk("spruce_sign", Village.blk("oak_sign", AIR))
            guard sign != AIR else { return }
            w.set(sx, gy + 2, sz, sign + BlockID(1))
            let be = BlockEntity(.sign)
            be.lines = ["Welcome to", ShopMenu.fit(name, 88), "Keep your", "hands empty"]
            w.entities.append((IVec3(sx, gy + 2, sz), be))
        })
        return out
    }

    // The citadel whose row holds (x, z), if any (only citadels that built one).
    static func citadel(_ g: Game, x: Int, z: Int) -> StructureStart? {
        guard g.dim.dim == .overworld, let sc = g.world.gen.structures,
              let s = sc.nearest("military_base", x: x, z: z, maxRegions: 1), s.pieces.count > 1 else { return nil }
        let cx = s.anchor.x, cz = s.anchor.z - CapitalBase.podium - 8
        guard abs(x - cx) <= halfW + 2, z >= cz + roadZ - 2, z <= cz + lotZ + 12 else { return nil }
        return s
    }

    static var inRow = false             // the player is in a garrison row (set each second)
    static var tense: Float = 0          // seconds with a weapon out in the row
    static var opened = false            // the row has opened fire (until the player has been away a minute)
    static var away: Float = 0
    static var warned = false
    static var forceRow: Bool?           // the host check stands the player in a row
    private static var worldID: ObjectIdentifier?   // a new world starts calm

    static func weaponOut(_ g: Game) -> Bool {
        let k = Items.key(g.held.item)
        return g.heldGun != nil || k == "bow" || k == "crossbow" || VRMelee.isSwingWeapon(k)
    }

    // Once a second.
    static func tick(_ g: Game, _ dt: Float) {
        let id = ObjectIdentifier(g.world)
        if worldID != id { worldID = id; inRow = false; tense = 0; opened = false; away = 0; warned = false }
        let p = g.player.pos
        inRow = g.survival && (forceRow ?? (citadel(g, x: Int(floor(p.x)), z: Int(floor(p.z))) != nil))
        guard inRow else {
            away += dt
            if away > 60 { opened = false }
            tense = 0; warned = false
            return
        }
        away = 0
        guard !opened else { return }
        // Any soldier hurt or already fighting here: the row is open.
        if g.mobs.mobs.contains(where: { Soldier.rank($0.kind) != nil && $0.factionValue == .steelhold && $0.aggro && simd_length($0.pos - p) < 64 }) {
            open(g); return
        }
        if weaponOut(g) {
            tense += dt
            if tense >= warnAt && !warned { warned = true; g.onToast?("The guards watch your hands. Put that away") }
            if tense >= patience { open(g) }
        } else {
            tense = max(0, tense - dt * 2)
            if tense == 0 { warned = false }
        }
    }

    static func open(_ g: Game) {
        opened = true
        g.onToast?("The garrison opens fire!")
        for m in g.mobs.mobs where Soldier.rank(m.kind) != nil && m.factionValue == .steelhold && simd_length(m.pos - g.player.pos) < 64 {
            m.aggro = true; m.lockTime = max(m.lockTime, 20)
        }
    }

    // The garrison leaves the player be: a calm soldier does not mark them while they are in the row.
    static func shelters(_ g: Game, _ m: Mob) -> Bool {
        inRow && !opened && !m.aggro && m.factionValue == .steelhold
    }
}
