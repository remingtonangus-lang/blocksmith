import Foundation
import simd

// Sky isles (backlog C7, the sky layer): rare lenses of rock and turf floating high over the overworld (displayed y
// 236-260), each with a few trees and a broken Skyward Shrine: a ring of cracked pillars round a chest of sky loot (lift
// balloons, propellers, a Sky Skiff kit now and then, gold, a Grapple Line). Reached with a flyer (the Sky Skiff, A4) or
// the Grapple Line, which hooks a block or a vessel's deck up to 24 blocks off and reels its holder there. The Capital's
// frigates already patrol the sky; an isle shows on the map from 160 blocks (they are seen from far). Only on ground no
// save generated before them (structure-guard-skyisle.txt), so none is ever cut off at the edge of explored land.
enum SkyIsle {
    static let kind = "sky_isle"
    static let spacing = 40, separation = 12
    static let presence: Float = 0.4
    static let minSpawn: Float = 800                       // never this near the spawn
    static let lowTop = 300, highTop = 324                 // the turf's height (array y; displayed y - 64)
    static let seen = 160                                  // blocks: an isle goes on the map from this far

    static func b(_ k: String, _ alt: String = "stone") -> BlockID { Blocks.has(k) ? Blocks.id(k) : Blocks.id(alt) }

    // The shape of one isle: centre, turf height, radius per heading, depth of the underside.
    struct Shape {
        let x: Int, z: Int, top: Int, r: Int, depth: Int, seed: UInt32
        // Radius toward (dx, dz): a lumpy outline (two harmonics of a seeded wobble).
        func radius(_ dx: Int, _ dz: Int) -> Float {
            let a = atan2f(Float(dz), Float(dx))
            let w = 0.14 * sinf(3 * a + Float(seed % 97)) + 0.09 * sinf(5 * a + Float(seed % 61))
            return Float(r) * (1 + w)
        }
        // The column's turf top and rock bottom at (dx, dz), or nil off the isle.
        func column(_ dx: Int, _ dz: Int) -> (top: Int, bottom: Int)? {
            let d = simd_length(V2(Float(dx), Float(dz))), R = radius(dx, dz)
            guard d <= R else { return nil }
            let f = d / R                                        // 0 centre .. 1 rim
            let top = self.top + Int((1.6 * (1 - f * f)).rounded()) - (f > 0.92 ? 1 : 0)
            let lump = hashf(x + dx, z + dz, 7301, seed)
            let bottom = self.top - Int((Float(depth) * powf(1 - f, 1.35) + lump * 2).rounded()) - 1
            return (top, min(bottom, top - 1))
        }
    }

    static func shape(_ seed: UInt64, _ cx: Int, _ cz: Int) -> Shape {
        var rng = SRng(seed)
        let r = 10 + Int(rng.float() * 8)
        let top = lowTop + Int(rng.float() * Float(highTop - lowTop))
        return Shape(x: cx * CS + 8, z: cz * CS + 8, top: top, r: r, depth: r + 4 + Int(rng.float() * 6), seed: UInt32(truncatingIfNeeded: seed))
    }

    // MARK: Placement

    static func type(_ gen: WorldGen) -> StructureType {
        StructureType(name: kind, spacing: spacing, separation: separation, salt: 47021893, reach: 2) { [unowned gen] seed, cx, cz in
            let rx = floorDiv(cx, spacing), rz = floorDiv(cz, spacing)
            guard hashf(rx, rz, 9300, UInt32(truncatingIfNeeded: gen.seed)) < presence else { return nil }
            let o = Game.spawnOrigin(seed: gen.seed)
            guard simd_length(V2(Float(cx * CS + 8 - o.0), Float(cz * CS + 8 - o.1))) >= minSpawn else { return nil }
            // Ground saved before the isles keeps its empty sky (an isle half over saved chunks would be cut off).
            if let sc = gen.structures, !sc.clear(cx: cx, cz: cz, reach: 2, guardSet: sc.legacySkyIsle) { return nil }
            let s = shape(seed, cx, cz)
            // Clear of the tallest ground below (a mountain peak under a low isle).
            for (dx, dz) in [(0, 0), (s.r, 0), (-s.r, 0), (0, s.r), (0, -s.r)] where gen.column(s.x + dx, s.z + dz).height > s.top - s.depth - 24 { return nil }
            let m = s.r + 4
            return StructureStart(kind: kind, pieces: [Piece(min: IVec3(s.x - m, s.top - s.depth - 4, s.z - m), max: IVec3(s.x + m, s.top + 12, s.z + m)) { w in
                build(&w, s, seed)
            }], anchor: IVec3(s.x, s.top + 1, s.z + 3))
        }
    }

    // MARK: Building

    static func build(_ w: inout StructWriter, _ s: Shape, _ seed: UInt64) {
        var rng = SRng(seed &+ 0x51C1)
        let stone = b("stone"), dirt = b("dirt"), grass = b("grass_block"), cobble = b("cobblestone"), andesite = b("andesite")
        let m = s.r + 3
        for dz in -m...m { for dx in -m...m {
            guard let c = s.column(dx, dz) else { continue }
            let x = s.x + dx, z = s.z + dz
            for y in c.bottom...c.top {
                let fromTop = c.top - y
                let blk: BlockID = fromTop == 0 ? grass : fromTop <= 2 ? dirt
                    : (hashf(x, y, z, s.seed) < 0.12 ? andesite : (hashf(x, y, z, s.seed &+ 1) < 0.06 ? cobble : stone))
                w.set(x, y, z, blk)
            }
        } }
        // Trees on the turf away from the shrine.
        let log = b("oak_log"), leaves = b("oak_leaves")
        let trees = 2 + Int(rng.float() * 3)
        for i in 0..<trees {
            let a = Float(i) / Float(trees) * 2 * .pi + rng.float() * 0.8
            let d = Float(s.r) * (0.5 + rng.float() * 0.2)
            let tx = Int((cosf(a) * d).rounded()), tz = Int((sinf(a) * d).rounded())
            guard let c = s.column(tx, tz) else { continue }
            let h = 4 + Int(rng.float() * 2)
            for y in 1...h { w.set(s.x + tx, c.top + y, s.z + tz, log) }
            for ly in (h - 1)...(h + 1) { for lz in -2...2 { for lx in -2...2 {
                let rr = ly == h + 1 ? 1 : 2
                guard abs(lx) <= rr, abs(lz) <= rr, !(abs(lx) == 2 && abs(lz) == 2), lx != 0 || lz != 0 || ly > h else { continue }
                w.set(s.x + tx + lx, c.top + ly, s.z + tz + lz, leaves)
            } } }
        }
        // The Skyward Shrine: a 7x7 cracked floor, eight pillars (some broken), a chest in the middle.
        let brick = b("stone_bricks"), cracked = b("cracked_stone_bricks", "stone_bricks"), mossy = b("mossy_stone_bricks", "stone_bricks")
        let top = s.top + 1                                              // the turf top at the centre is s.top + 1 (the dome)
        for dz in -3...3 { for dx in -3...3 {
            let h = hashf(s.x + dx, top, s.z + dz, s.seed &+ 2)
            w.set(s.x + dx, top, s.z + dz, h < 0.25 ? cracked : h < 0.4 ? mossy : brick)
            for y in (top + 1)...(top + 4) { w.set(s.x + dx, y, s.z + dz, AIR) }
        } }
        for (i, (px, pz)) in [(-3, -3), (0, -3), (3, -3), (3, 0), (3, 3), (0, 3), (-3, 3), (-3, 0)].enumerated() {
            if (px == 0 && pz == 3) { continue }                         // the way in (south)
            let ph = hashf(i, 3, 1, s.seed &+ 3) < 0.4 ? 1 + Int(hashf(i, 3, 2, s.seed) * 2) : 3
            for y in 1...ph { w.set(s.x + px, top + y, s.z + pz, y == ph && ph < 3 ? cracked : brick) }
        }
        w.chest(s.x, top + 1, s.z, loot: kind, seed: rng.next(), facing: 0)
    }

    // MARK: Loot

    static let loot: [String: (rolls: ClosedRange<Int>, entries: [(String, Int, Int, Int)])] = [
        kind: (4...7, [("ship_balloon", 1, 4, 14), ("ship_propeller", 1, 2, 8), ("ship_engine", 1, 1, 4), ("sky_skiff_kit", 1, 1, 3),
                       (GrappleLine.key, 1, 1, 8), ("gold_ingot", 1, 4, 12), ("diamond", 1, 2, 4), ("emerald", 1, 3, 8),
                       ("feather", 2, 6, 10), ("string", 2, 6, 10), ("compass", 1, 1, 6), ("golden_apple", 1, 1, 3),
                       ("experience_bottle", 1, 3, 6)]),
    ]

    // MARK: Discovery (WorldMap: from 160 blocks, any height)

    static func discover(_ g: Game, _ sc: StructureCache, at p: V3) {
        guard let t = sc.types.first(where: { $0.name == kind }) else { return }
        let span = spacing * CS
        let rx0 = floorDiv(Int(p.x), span), rz0 = floorDiv(Int(p.z), span)
        for rz in (rz0 - 1)...(rz0 + 1) { for rx in (rx0 - 1)...(rx0 + 1) {
            guard let s = sc.start(t, regionX: rx, regionZ: rz) else { continue }
            let c = V2(Float(s.min.x + s.max.x) / 2, Float(s.min.z + s.max.z) / 2)
            if simd_length(c - V2(p.x, p.z)) < Float(seen) { MapCache.shared.discover(g, kind: kind, x: Int(c.x), z: Int(c.y)) }
        } }
    }
}

// The Grapple Line (C7): cast at a block or a vessel within 24 blocks, it hooks there and reels its holder in (16 blocks a
// second, no fall damage on the way); right click again, sneaking, or arriving lets go. On a ship the hook follows the
// deck as it moves.
enum GrappleLine {
    static let key = "grapple_line"
    static let reach: Float = 24
    static let speed: Float = 16

    final class Hook {
        var at: V3                               // world point (block hooks)
        weak var ship: Ship?
        var local: V3 = .zero                    // ship-space point (ship hooks)
        var time: Float = 0
        init(at: V3) { self.at = at }
        var point: V3 { ship.map { $0.toWorld(local) } ?? at }
    }
}

extension Game {
    // Right click holding a Grapple Line: cast, or let go of a hook already set.
    func grappleUse() -> Bool {
        let held = inventory.main[inventory.selected]
        guard !held.isEmpty, Items.key(held.item) == GrappleLine.key else { return false }
        if grapple != nil { grapple = nil; sfx(.click, 0.5, at: player.pos); return true }
        let o = player.eye, d = player.look
        var best: (Float, GrappleLine.Hook)?
        if let h = world.raycast(o, d, maxDist: GrappleLine.reach) {
            let c = V3(Float(h.hit.x), Float(h.hit.y), Float(h.hit.z)) + 0.5 + V3(Float(h.normal.x), Float(h.normal.y), Float(h.normal.z)) * 0.5
            best = (simd_length(c - o), GrappleLine.Hook(at: c))
        }
        for s in world.ships.list where !s.wrecked {
            guard let r = s.raycast(o, d, maxDist: GrappleLine.reach, world: world), r.t < (best?.0 ?? .infinity) else { continue }
            let hook = GrappleLine.Hook(at: o + d * r.t)
            hook.ship = s
            hook.local = V3(Float(r.cell.x), Float(r.cell.y), Float(r.cell.z)) + 0.5 + V3(Float(r.normal.x), Float(r.normal.y), Float(r.normal.z)) * 0.5
            best = (r.t, hook)
        }
        guard let (_, hook) = best else { onToast?("Nothing within reach of the line"); return true }
        grapple = hook
        sfx(.crossbowShoot, 0.7, at: player.pos)
        return true
    }

    // Every tick: reel the holder toward the hook.
    func grappleTick(_ dt: Float) {
        guard let h = grapple else { return }
        h.time += dt
        let held = inventory.main[inventory.selected]
        let to = h.point - player.pos
        let d = simd_length(to)
        if held.isEmpty || Items.key(held.item) != GrappleLine.key || !alive || player.sneaking || d < 1.6 || d > GrappleLine.reach + 8 || h.time > 6 {
            grapple = nil
            if d < 1.6 { player.vel = V3(0, max(0, player.vel.y), 0) }
            return
        }
        player.vel = to / d * GrappleLine.speed
        player.airPeak = player.pos.y                   // no fall damage from the reel
    }
}

extension ItemRegistry {
    func registerSkyIsleItems() {
        guard !has(GrappleLine.key) else { return }
        var d = ItemDef(GrappleLine.key, "Grapple Line")
        d.sprite = Sprite(mask: "fishing_rod", base: 0x5A5F66, extras: ["s": 0xC8B890, "c": 0x8A9098])
        d.maxStack = 1
        add(d)
    }
}
