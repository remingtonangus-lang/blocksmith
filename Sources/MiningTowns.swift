import Foundation
import simd

// Mining towns (backlog C12). The genre's abandoned mineshafts are retired on new ground (OverworldStructures.mineshaft:
// ground a save had generated before C12 keeps its old shafts, StructureCache.legacyC12); in their place the bigger
// towns work a real mine at the edge of town:
//   headframe   a timber head frame over a 3x3 shaft past the end of a street, a plank deck railed round the opening,
//               a sign with the mine's name, a ladder all the way down the shaft
//   No. 1 level 24 blocks down: two drifts out of the shaft on rails with mine carts, timber supports every 4 blocks
//               (lamps on every other one), the expedition stores at the foot of the shaft (TNT in the powder niche,
//               the stores chest: dynamite, lamps, rails, picks, food) and miners at the faces
//   No. 2 level deep under the town (y -34): the main drift runs to the deep vein, a chamber walled with gold,
//               titanium, emerald and redstone ore; the side drift is blocked by an old cave-in, and past it a gas
//               pocket sits at the end of the drift beside a gold seam
//   loose ground  stretches of drift ceiling held up by lagging boards with gravel above: break the boards (or blast
//               them) and the gravel comes down; knock out a support post and the ceiling over it caves in
//   gas         firedamp pockets (MiningTowns.tick, once a second): inside one you choke (nausea, poison); a naked
//               flame in it (a torch, flint and steel or a fire charge in hand, a torch or fire placed in it, a gun fired
//               in it) sets it off; a lantern is a safety lamp, it warns you as you come near and never sets it off
//   miners      townsfolk (role "miner", save tag "villager:miner") who work the faces day and night
// The mine's own drifts are company ground, not town property (TownLaw.isTownOwned): digging, blasting and taking
// the stores breaks no law. The head frame on the surface is the town's.
final class Mine {
    struct Drift { let level: Int; let x: Int; let z: Int; let dx: Int; let dz: Int; let len: Int }
    let shaft: IVec3                     // centre column x, z; y = the deck (ground) level
    let out: (Int, Int)                  // the way out of town (the street's direction); the ladder hangs on that side
    let levels: [Int]                    // floor (walking) heights of No. 1 and No. 2 levels
    var drifts: [Drift] = []
    var gas: [IVec3] = []
    var vein = IVec3(0, 0, 0)            // the deep vein chamber's centre (floor level)
    var loose: [IVec3] = []              // lagging boards with gravel above
    var supports: [IVec3] = []           // the support posts' foot blocks
    var stores = IVec3(0, 0, 0)          // the stores chest
    var powder = IVec3(0, 0, 0)          // the lower block of TNT in the powder niche
    var caveIn: [IVec3] = []             // the old cave-in's gravel
    var miners: [V3] = []
    var carts: [V3] = []
    let name: String
    var lots = 0                         // the town's lot count when it was laid out
    init(shaft: IVec3, out: (Int, Int), levels: [Int], name: String) { self.shaft = shaft; self.out = out; self.levels = levels; self.name = name }

    // A drift cell (s along, w across, h up from the floor) in world coordinates.
    static func at(_ d: Drift, _ s: Int, _ w: Int, _ h: Int) -> IVec3 {
        let ax = abs(d.dz), az = abs(d.dx)
        return IVec3(d.x + d.dx * s + ax * w, d.level + h, d.z + d.dz * s + az * w)
    }
    // The drift a point lies in (within the carved tunnel and its shell), with its s and w.
    func drift(at p: IVec3) -> (Drift, Int, Int)? {
        for d in drifts where p.y >= d.level - 1 && p.y <= d.level + 6 {
            let rx = p.x - d.x, rz = p.z - d.z
            let s = rx * d.dx + rz * d.dz, w = rx * abs(d.dz) + rz * abs(d.dx)
            if s >= 0 && s < d.len + 8 && abs(w) <= 4 { return (d, s, w) }
        }
        return nil
    }
    // Underground mine workings: the shaft below the deck, the drifts, the vein chamber.
    func underground(_ p: IVec3) -> Bool {
        guard p.y < shaft.y - 3 else { return false }
        if abs(p.x - shaft.x) <= 2 && abs(p.z - shaft.z) <= 2 && p.y >= levels.last! - 1 { return true }
        return drift(at: p) != nil
    }
}

enum MiningTowns {
    static let minLots = 15                 // a town with this many lots or more works a mine (C13 will tie it to size)
    static let level1Depth = 24
    static let level2Y = YOFF - 34          // y -34 shown
    static let gasRadius: Float = 3.5

    // MARK: Layout (Village.layout)

    // Picks a site past the end of a street and adds the mine's pieces. `ends`: each street's outer end.
    static func add(_ gen: WorldGen, ox: Int, oz: Int, lots: Int, ends: [(Int, Int, Int, Int, Int, Bool)],
                    occupied: inout Set<IVec2Key>, pieces: inout [Piece], seed: UInt64, town: String) -> Mine? {
        guard lots >= minLots else { return nil }
        if let sc = gen.structures, !sc.clear(cx: floorDiv(ox, CS), cz: floorDiv(oz, CS), reach: 7, guardSet: sc.legacyC12) { return nil }
        var site: (Int, Int, Int, Int, Int)? = nil
        search: for main in [true, false] {
            for e in ends where e.5 == main {
                for push in [5, 7, 9] {
                    let sx = e.0 + e.3 * push, sz = e.1 + e.4 * push
                    guard abs(sx - ox) <= 70 && abs(sz - oz) <= 70 else { continue }
                    var ok = true
                    for z in (sz - 4)...(sz + 4) { for x in (sx - 4)...(sx + 4) where occupied.contains(IVec2Key(x, z)) { ok = false } }
                    guard ok else { continue }
                    let gy = gen.groundY(sx, sz)
                    guard gy >= SEA + 1 else { continue }
                    for (dx, dz) in [(-4, -4), (4, -4), (-4, 4), (4, 4), (0, 4), (0, -4), (4, 0), (-4, 0)] {
                        let y = gen.groundY(sx + dx, sz + dz)
                        if abs(y - gy) > 2 || y < SEA { ok = false; break }
                    }
                    if ok { site = (sx, sz, gy, e.3, e.4); break search }
                }
            }
        }
        guard let (sx, sz, gy, ex, ez) = site else { return nil }
        for z in (sz - 4)...(sz + 4) { for x in (sx - 4)...(sx + 4) { occupied.insert(IVec2Key(x, z)) } }
        let l1 = gy - level1Depth, l2 = level2Y
        let mine = Mine(shaft: IVec3(sx, gy, sz), out: (ex, ez), levels: [l1, l2], name: "\(town) Mine")
        mine.lots = lots
        var rng = SRng(seed ^ 0x313E)
        let tx = -ex, tz = -ez                    // toward town
        let px = ez, pz = ex                      // across (either side: by the seed)
        let side = rng.chance(0.5) ? 1 : -1
        let len1 = rng.range(24, 30), len2 = rng.range(18, 22), lenDeep = rng.range(28, 34), lenSide = rng.range(20, 24)
        mine.drifts = [
            Mine.Drift(level: l1, x: sx + tx * 2, z: sz + tz * 2, dx: tx, dz: tz, len: len1),
            Mine.Drift(level: l1, x: sx + px * side * 2, z: sz + pz * side * 2, dx: px * side, dz: pz * side, len: len2),
            Mine.Drift(level: l2, x: sx + tx * 2, z: sz + tz * 2, dx: tx, dz: tz, len: lenDeep),
            Mine.Drift(level: l2, x: sx + px * side * 2, z: sz + pz * side * 2, dx: px * side, dz: pz * side, len: lenSide),
        ]
        // Fittings worked out here so the mine's record matches what is built.
        let d1 = mine.drifts[0], d2 = mine.drifts[1], deep = mine.drifts[2], sideD = mine.drifts[3]
        for d in mine.drifts { for s in stride(from: 2, to: d.len - 1, by: 4) { for w in [-1, 1] { mine.supports.append(Mine.at(d, s, w, 0)) } } }
        for (d, s0) in [(d1, 11), (deep, 15)] { for s in (s0)...(s0 + 2) { for w in -1...1 { mine.loose.append(Mine.at(d, s, w, 4)) } } }
        mine.stores = Mine.at(d2, 1, 2, 0)
        mine.powder = Mine.at(d2, 1, -2, 0)
        for s in 8...10 { for w in -1...1 { for h in 0...3 { mine.caveIn.append(Mine.at(sideD, s, w, h)) } } }
        mine.gas = [Mine.at(sideD, sideD.len - 3, 0, 1)]
        mine.vein = Mine.at(deep, deep.len + 3, 0, 0)
        func centre(_ p: IVec3) -> V3 { V3(Float(p.x) + 0.5, Float(p.y), Float(p.z) + 0.5) }
        mine.miners = [centre(Mine.at(d1, d1.len - 2, 0, 0)), centre(Mine.at(d2, d2.len - 2, 0, 0)), centre(Mine.at(deep, 3, 0, 0))]
        mine.carts = [centre(Mine.at(d1, 5, 0, 0)), centre(Mine.at(deep, 4, 0, 0))]

        // Pieces: the shaft first (the drifts open through its lining), then the drifts, then the surface.
        let g = Blocks.id
        let planks = g("oak_planks"), log = g("oak_log"), fence = g("oak_fence"), lantern = Blocks.id("lantern")
        let ladder = g("ladder") + BlockID(ez > 0 ? 0 : (ez < 0 ? 1 : (ex > 0 ? 2 : 3)))
        pieces.append(Piece(min: IVec3(sx - 2, l2 - 1, sz - 2), max: IVec3(sx + 2, gy - 1, sz + 2)) { w in
            for y in (l2 - 1)...(gy - 1) { for dz in -2...2 { for dx in -2...2 {
                let x = sx + dx, z = sz + dz
                guard w.inside(x, y, z) else { continue }
                if abs(dx) == 2 || abs(dz) == 2 || y == l2 - 1 {
                    let b = w.get(x, y, z)
                    if !Blocks.opaque[Int(b)] || Blocks.isLiquid(b) || (dx == ex * 2 && dz == ez * 2) { w.set(x, y, z, planks) }
                } else { w.set(x, y, z, AIR) }
            } } }
            for y in [l1 - 1] { for dz in -1...1 { for dx in -1...1 where !(dx == ex && dz == ez) && w.inside(sx + dx, y, sz + dz) {
                w.set(sx + dx, y, sz + dz, planks)                                   // the No. 1 landing round the ladder
            } } }
            for y in l2...(gy - 1) where w.inside(sx + ex, y, sz + ez) { w.set(sx + ex, y, sz + ez, ladder) }
        })
        for (k, d) in mine.drifts.enumerated() {
            let deepMain = k == 2, sideDeep = k == 3
            let loose = Set(mine.loose)
            let caveIn = sideDeep ? Set(mine.caveIn) : []
            let gasEnd = sideDeep, vein = deepMain ? mine.vein : nil
            let reach = d.len + (deepMain ? 7 : 0)
            let a = Mine.at(d, 0, -4, -1), b = Mine.at(d, reach, 4, 7)
            let dseed = rng.next()
            let storesAt = k == 1 ? mine.stores : nil, powderAt = k == 1 ? mine.powder : nil
            pieces.append(Piece(min: IVec3(min(a.x, b.x), a.y, min(a.z, b.z)), max: IVec3(max(a.x, b.x), b.y, max(a.z, b.z))) { w in
                carveDrift(&w, d, planks: planks, log: log, fence: fence, lantern: lantern, loose: loose)
                if let v = vein { veinChamber(&w, d, v, fence: fence, lantern: lantern, seed: dseed) }
                for c in caveIn where w.inside(c.x, c.y, c.z) { w.set(c.x, c.y, c.z, GRAVEL) }
                if gasEnd {
                    // A gold seam in the face past the gas, and a warning on the near side of the old fall.
                    for s in (d.len - 4)...(d.len - 1) { for ww in -2...2 { for h in -1...4 {
                        let c = Mine.at(d, s, ww, h)
                        guard w.inside(c.x, c.y, c.z), abs(ww) == 2 || h == -1 || h == 4 || s == d.len - 1 else { continue }
                        if hash3(c.x, c.y, c.z, 0x601D) % 3 == 0 { w.set(c.x, c.y, c.z, blk("deepslate_gold_ore", GOLD_ORE)) }
                    } } }
                    let sp = Mine.at(d, 6, 1, 0)
                    if w.inside(sp.x, sp.y, sp.z) {
                        let sign = blk("spruce_sign", blk("oak_sign", AIR))
                        if sign != AIR {
                            w.set(sp.x, sp.y, sp.z, sign + BlockID(facing(-d.dx, -d.dz)))
                            let be = BlockEntity(.sign)
                            be.lines = ["Old fall.", "Gas beyond.", "No naked", "flames!"]
                            w.entities.append((sp, be))
                        }
                    }
                }
                if let c = storesAt, w.inside(c.x, c.y, c.z) {
                    w.chest(c.x, c.y, c.z, loot: "mine_stores", seed: dseed, facing: facing(-(c.x - Mine.at(d, 1, 0, 0).x), -(c.z - Mine.at(d, 1, 0, 0).z)))
                }
                if let p = powderAt { for h in 0...1 where w.inside(p.x, p.y + h, p.z) { w.set(p.x, p.y + h, p.z, g("tnt")) } }
            })
        }
        // P132 (Oct 12 PM, "the railroads... connected to each other a lot better... through a mine shaft really quickly
        // by putting down a mine cart"): on each level the two drifts' tracks join round the shaft's corner, so a cart
        // runs from one face to the other without being carried across.
        for (a, b) in [(mine.drifts[0], mine.drifts[1]), (mine.drifts[2], mine.drifts[3])] {
            let cells = MiningTowns.link(a, b)
            let xs = cells.map { $0.x }, zs = cells.map { $0.z }
            pieces.append(Piece(min: IVec3(xs.min()!, a.level - 1, zs.min()!), max: IVec3(xs.max()!, a.level + 3, zs.max()!)) { w in
                MiningTowns.layLink(&w, a, b, planks: planks)
            })
        }
        // Miners and carts (placed with the chunk they stand in).
        let miners = mine.miners, carts = mine.carts
        let spots = miners + carts
        pieces.append(Piece(min: IVec3(Int(floor(spots.map { $0.x }.min()!)), l2, Int(floor(spots.map { $0.z }.min()!))),
                            max: IVec3(Int(floor(spots.map { $0.x }.max()!)), l1 + 1, Int(floor(spots.map { $0.z }.max()!)))) { w in
            for p in miners { w.mob("villager:miner", p) }
            for p in carts { w.mob("minecart", p + V3(0, 0.1, 0)) }
        })
        // The head frame: a railed deck round the opening, four corner posts, a beam frame with a sheave over the shaft.
        let name = mine.name
        pieces.append(Piece(min: IVec3(sx - 4, gy - 6, sz - 4), max: IVec3(sx + 4, gy + 9, sz + 4)) { w in
            for dz in -3...3 { for dx in -3...3 {
                let x = sx + dx, z = sz + dz
                guard w.inside(x, gy, z) else { continue }
                for y in (gy + 1)...(gy + 9) { w.set(x, y, z, AIR) }
                if abs(dx) <= 1 && abs(dz) <= 1 { w.set(x, gy, z, dx == ex && dz == ez ? ladder : AIR); continue }
                w.set(x, gy, z, planks)
                w.pillarDown(x, gy - 1, z, COBBLE, minY: gy - 6)
                if abs(dx) == 2 && abs(dz) == 2 { for y in (gy + 1)...(gy + 7) { w.set(x, y, z, log) } }
                else if abs(dx) == 2 || abs(dz) == 2 {
                    if !(dx == ex * 2 && dz == ez * 2) { w.set(x, gy + 1, z, fence) }   // the way onto the ladder
                    if abs(dx) <= 2 && abs(dz) <= 2 { w.set(x, gy + 7, z, planks) }
                }
            } }
            if w.inside(sx, gy + 7, sz) {
                for k in -2...2 { w.set(sx + abs(ez) * k, gy + 7, sz + abs(ex) * k, planks) }
                w.set(sx, gy + 8, sz, g("oak_planks"))
                if Blocks.has("chain") { for y in (gy + 2)...(gy + 6) { w.set(sx, y, sz, g("chain")) } }
            }
            let sp = IVec3(sx + tx * 3 + px, gy + 1, sz + tz * 3 + pz)
            if w.inside(sp.x, sp.y, sp.z) {
                let sign = blk("spruce_sign", blk("oak_sign", AIR))
                guard sign != AIR else { return }
                w.set(sp.x, sp.y, sp.z, sign + BlockID(facing(tx, tz)))
                let be = BlockEntity(.sign)
                be.lines = [ShopMenu.fit(name, 88), "Shaft No. 1", "Two levels", "Mind the gas"]
                w.entities.append((sp, be))
            }
        })
        return mine
    }

    // The expedition stores at the foot of the shaft.
    static let loot: [String: (rolls: ClosedRange<Int>, entries: [(String, Int, Int, Int)])] = [
        "mine_stores": (6...9, [("tnt", 2, 5, 22), ("torch", 8, 16, 14), ("lantern", 1, 2, 12), ("rail", 6, 16, 12), ("bread", 2, 5, 12),
                                ("iron_pickaxe", 1, 1, 8), ("flint_and_steel", 1, 1, 6), ("ladder", 4, 12, 8), ("coal", 3, 8, 8),
                                ("cooked_beef", 1, 3, 6), ("minecart", 1, 1, 3), ("iron_shovel", 1, 1, 4)]),
    ]

    static func blk(_ n: String, _ fallback: BlockID) -> BlockID { Blocks.has(n) ? Blocks.id(n) : fallback }
    // Block facing index (0 north -Z, 1 south +Z, 2 west -X, 3 east +X) of a direction.
    static func facing(_ dx: Int, _ dz: Int) -> Int { dz < 0 ? 0 : (dz > 0 ? 1 : (dx < 0 ? 2 : 3)) }

    // A 3-wide, 4-tall drift: rails down the middle, supports every 4 blocks (posts and a cap beam; a lamp on every
    // other one), a lined floor and walls where it crosses a cave or water, lagging and gravel over the loose stretches.
    static func carveDrift(_ w: inout StructWriter, _ d: Mine.Drift, planks: BlockID, log: BlockID, fence: BlockID, lantern: BlockID,
                           loose: Set<IVec3>) {
        let rail = Blocks.id("rail") + (d.dx != 0 ? 1 : 0)
        for s in 0..<d.len { for ww in -2...2 { for h in -1...4 {
            let c = Mine.at(d, s, ww, h)
            guard w.inside(c.x, c.y, c.z) else { continue }
            let shell = abs(ww) == 2 || h == -1 || h == 4
            let b = w.get(c.x, c.y, c.z)
            if shell {
                if Blocks.isLiquid(b) || (h == -1 && !Blocks.collide[Int(b)]) || (!Blocks.opaque[Int(b)] && h != 4) { w.set(c.x, c.y, c.z, h == -1 ? planks : STONE) }
                else if h == 4 && (!Blocks.collide[Int(b)] || Blocks.isLiquid(b)) { w.set(c.x, c.y, c.z, STONE) }
            } else { w.set(c.x, c.y, c.z, AIR) }
        } } }
        for s in 0..<d.len {
            let c = Mine.at(d, s, 0, 0)
            if w.inside(c.x, c.y, c.z) { w.set(c.x, c.y, c.z, rail) }
            if s % 4 == 2 && s < d.len - 1 {
                let lamp = (s / 4) % 2 == 0
                for ww in [-1, 1] {
                    for h in 0...2 {
                        let p = Mine.at(d, s, ww, h)
                        guard w.inside(p.x, p.y, p.z) else { continue }
                        w.set(p.x, p.y, p.z, lamp && ww == 1 ? (h == 2 ? lantern : fence) : log)
                    }
                }
                for ww in -1...1 { let p = Mine.at(d, s, ww, 3); if w.inside(p.x, p.y, p.z) { w.set(p.x, p.y, p.z, planks) } }
            }
            // Loose ground: lagging boards in the roof with gravel packed above.
            for ww in -1...1 {
                let p = Mine.at(d, s, ww, 4)
                guard loose.contains(p), w.inside(p.x, p.y, p.z) else { continue }
                w.set(p.x, p.y, p.z, planks)
                for h in 5...6 where w.inside(p.x, d.level + h, p.z) { w.set(p.x, d.level + h, p.z, GRAVEL) }
            }
        }
    }

    // The track joining two drifts that leave the shaft at right angles on one level (P132): from the first drift's
    // mouth (shaft + 2t) sideways to the corner past the shaft (shaft + 2t + 2p), then back along t into the second
    // drift's mouth (shaft + 2p). Returned in order, both mouths included.
    static func link(_ a: Mine.Drift, _ b: Mine.Drift) -> [IVec3] {
        let t = IVec3(a.dx, 0, a.dz), p = IVec3(b.dx, 0, b.dz)
        let a0 = IVec3(a.x, a.level, a.z), b0 = IVec3(b.x, b.level, b.z)
        return [a0, a0 + p, a0 + p + p, b0 + t, b0]
    }

    // Rail shape (Rails.exits) joining two horizontal directions.
    static func railShape(_ d0: IVec3, _ d1: IVec3) -> Int {
        let ns = (d0.x == 0 ? 1 : 0) + (d1.x == 0 ? 1 : 0)
        if ns == 2 { return 0 }
        if ns == 0 { return 1 }
        let z = d0.x == 0 ? d0.z : d1.z, x = d0.x == 0 ? d1.x : d0.x
        if z > 0 { return x > 0 ? 6 : 7 }
        return x < 0 ? 8 : 9
    }

    static func layLink(_ w: inout StructWriter, _ a: Mine.Drift, _ b: Mine.Drift, planks: BlockID) {
        let cells = link(a, b)
        let rail = Blocks.id("rail")
        for c in cells where !(c == cells.first || c == cells.last) {
            for h in -1...3 where w.inside(c.x, c.y + h, c.z) { w.set(c.x, c.y + h, c.z, h == -1 ? planks : AIR) }
        }
        // Each cell's shape from its two neighbours along the track (the mouths: the link and their own drift).
        for (i, c) in cells.enumerated() where w.inside(c.x, c.y, c.z) {
            let prev = i > 0 ? cells[i - 1] : c + IVec3(a.dx, 0, a.dz)
            let next = i < cells.count - 1 ? cells[i + 1] : c + IVec3(b.dx, 0, b.dz)
            w.set(c.x, c.y, c.z, rail + BlockID(railShape(prev - c, next - c)))
        }
    }

    // The deep vein: a 7x7 chamber past the end of the main No. 2 drift, its walls, roof and floor rich in ore.
    static func veinChamber(_ w: inout StructWriter, _ d: Mine.Drift, _ v: IVec3, fence: BlockID, lantern: BlockID, seed: UInt64) {
        let ores: [(String, BlockID, Int)] = [("deepslate_gold_ore", GOLD_ORE, 30), ("deepslate_diamond_ore", DIAMOND_ORE, 14),
                                              ("deepslate_redstone_ore", blk("redstone_ore", STONE), 22), ("emerald_ore", STONE, 8),
                                              ("deepslate_iron_ore", blk("iron_ore", STONE), 26)]
        let total = ores.reduce(0) { $0 + $1.2 }
        for s in (d.len - 1)...(d.len + 7) { for ww in -4...4 { for h in -1...5 {
            let c = Mine.at(d, s, ww, h)
            guard w.inside(c.x, c.y, c.z) else { continue }
            let shell = abs(ww) == 4 || h == -1 || h == 5 || s == d.len + 7 || (s == d.len - 1 && abs(ww) >= 2)
            if !shell { w.set(c.x, c.y, c.z, AIR); continue }
            if s == d.len - 1 && abs(ww) < 2 { continue }
            let r = Int(hash3(c.x, c.y, c.z, UInt32(truncatingIfNeeded: seed)) % 100)
            if r < 45 {
                var k = Int(hash3(c.z, c.x, c.y, 0x0E7E) % UInt32(total))
                var pick = ores[0]
                for o in ores { if k < o.2 { pick = o; break }; k -= o.2 }
                w.set(c.x, c.y, c.z, blk(pick.0, pick.1))
            } else if !Blocks.opaque[Int(w.get(c.x, c.y, c.z))] || Blocks.isLiquid(w.get(c.x, c.y, c.z)) {
                w.set(c.x, c.y, c.z, blk("deepslate", STONE))
            }
        } } }
        // Lamps on posts in the four corners.
        for (ww, s) in [(-3, d.len), (3, d.len), (-3, d.len + 6), (3, d.len + 6)] {
            let p = Mine.at(d, s, ww, 0)
            guard w.inside(p.x, p.y, p.z) else { continue }
            w.set(p.x, p.y, p.z, fence); w.set(p.x, p.y + 1, p.z, lantern)
        }
        _ = v
    }

    // MARK: Play

    // The mine of the town nearest a point, if it has one.
    static func mine(_ g: Game, near p: V3) -> Mine? {
        guard g.dim.dim == .overworld, let sc = g.world.gen.structures,
              let s = sc.nearest("village", x: Int(floor(p.x)), z: Int(floor(p.z)), maxRegions: 1) else { return nil }
        return s.plan as? Mine
    }
    static func key(_ p: IVec3) -> String { "\(p.x),\(p.y),\(p.z)" }
    static func spent(_ p: IVec3) -> Bool { TownLaw.state.minesSpent?.contains(key(p)) == true }
    static var warned: Set<String> = []        // pockets the safety lamp has warned of (this session)
    static var choking: Set<String> = []
    static var ignitions = 0

    static let nakedFlames: Set<String> = ["torch", "soul_torch", "flint_and_steel", "fire_charge", "campfire", "soul_campfire"]

    // Once a second (TownLaw.tick): gas pockets near the player.
    static func tick(_ g: Game) {
        guard g.alive, let m = mine(g, near: g.player.pos) else { return }
        let held = Items.key(g.held.item)
        for c in m.gas where !spent(c) {
            let centre = V3(Float(c.x) + 0.5, Float(c.y) + 0.5, Float(c.z) + 0.5)
            let d = simd_length(g.player.pos + V3(0, 1, 0) - centre)
            let k = key(c)
            guard d < gasRadius + 6 else { choking.remove(k); continue }
            if d < gasRadius {
                if nakedFlames.contains(held) || flameIn(g, c) { ignite(g, c); continue }
                g.applyEffect(.nausea, amp: 0, seconds: 8)
                g.applyEffect(.poison, amp: 0, seconds: 3)
                if !choking.contains(k) { choking.insert(k); g.onToast?("Firedamp! Get clear of the gas.") }
            } else {
                choking.remove(k)
                if flameIn(g, c) { ignite(g, c); continue }
                if held == "lantern" && !warned.contains(k) {
                    warned.insert(k)
                    g.onToast?("Your lamp's flame burns tall and blue: gas ahead.")
                }
            }
        }
    }

    // A torch, fire or lit campfire placed in the pocket.
    static func flameIn(_ g: Game, _ c: IVec3) -> Bool {
        let r = Int(gasRadius)
        for y in (c.y - 1)...(c.y + 2) { for z in (c.z - r)...(c.z + r) { for x in (c.x - r)...(c.x + r) {
            let k = Blocks.key(Blocks.groupBase[Int(g.world.block(x, y, z))])
            if k == "torch" || k == "wall_torch" || k == "fire" || k == "campfire" || k == "soul_torch" { return true }
        } } }
        return false
    }

    static func ignite(_ g: Game, _ c: IVec3) {
        if TownLaw.state.minesSpent == nil { TownLaw.state.minesSpent = [] }
        TownLaw.state.minesSpent?.append(key(c))
        ignitions += 1
        g.onToast?("The gas went up!")
        Explosion.explode(at: V3(Float(c.x) + 0.5, Float(c.y) + 0.5, Float(c.z) + 0.5), power: 4, game: g, fire: true)
    }

    // A shot fired (TownLaw.gunfire): the muzzle flash sets off gas around it.
    static func spark(_ g: Game, at p: V3) {
        guard let m = mine(g, near: p) else { return }
        for c in m.gas where !spent(c) {
            if simd_length(p - V3(Float(c.x) + 0.5, Float(c.y) + 0.5, Float(c.z) + 0.5)) < gasRadius + 0.5 { ignite(g, c) }
        }
    }

    static var caveIns = 0
    // Game.breakBlock: a support post knocked out brings its cap beam and the roof above down.
    static func broke(_ g: Game, _ p: IVec3, _ b: BlockID) {
        let k = Blocks.key(Blocks.groupBase[Int(b)])
        guard k.hasSuffix("_log") || k.hasSuffix("_fence"), let m = mine(g, near: V3(Float(p.x), Float(p.y), Float(p.z))),
              let (d, s, w) = m.drift(at: p), abs(w) == 1, s % 4 == 2, p.y >= d.level && p.y <= d.level + 2 else { return }
        caveIns += 1
        g.onToast?("The timbers give way. Cave-in!")
        for ww in -1...1 {
            let beam = Mine.at(d, s, ww, 3)
            g.world.setBlock(beam.x, beam.y, beam.z, AIR)
            for h in 4...5 {
                let r = Mine.at(d, s, ww, h)
                g.world.setBlock(r.x, r.y, r.z, GRAVEL)
            }
        }
    }
}
