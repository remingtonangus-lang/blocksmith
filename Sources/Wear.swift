import Foundation
import simd

// Material-aware block damage (STATUS Future ideas #4; session H, docs/status/world-fx.md). Built on the existing
// progressive block chipping (World.damage: face << 5 | level 1...7 of 8):
//   stone  cracks in visible stages first (levels 1-3 are crack decals on the whole block), then chips (4-7);
//   metal  never chips: it dents (decal stages from the damage level);
//   glass  cracks, then shatters into shard particles;
//   wood   chips as before, and scorches next to fire (World.scorch, 3 decal stages) until it chars through into a
//          smouldering charcoal block (Fire.swift), which cools to charcoal or burns away.
// Explosions leave soot (scorch stage 1-2) on the blocks round the crater. Everything is decals drawn in the blended
// entity pass (no new mesh data, no per-block vertex flags) plus a few rules, so it stays cheap.
enum WearKind: UInt8 { case none = 0, stone, wood, glass, metal }

enum Wear {
    // Per block state. A stopgap classification from sound materials and names: session B owns the shared
    // per-block BlockMaterial table (strength / mass / kind); when it lands this reads its kind instead.
    static let kind: [WearKind] = {
        var t = [WearKind](repeating: .none, count: Blocks.count)
        for i in 1..<Blocks.count {
            let id = BlockID(i)
            if Blocks.hardness[i] < 0 || Blocks.isLiquid(id) { continue }
            let k = Blocks.key(Blocks.groupBase[i])
            if k.contains("glass") {
                t[i] = (k.hasPrefix("tinted") || k.hasPrefix("armored")) ? .stone : .glass     // bulletproof glass cracks
                continue
            }
            if k.hasPrefix("steel") || k.hasSuffix("_plating") || k == "steel_grating" { t[i] = .metal; continue }
            switch soundMat(id) {
            case .metal: t[i] = .metal
            case .wood: t[i] = .wood
            case .stone, .deepslate, .netherrack, .bone: t[i] = .stone
            default: break
            }
        }
        return t
    }()

    static let charcoal: BlockID = Blocks.id("charcoal_block")
    static let smolder: BlockID = Blocks.id("smoldering_charcoal")
    static let crackLayers = (1...4).map { Int(Tex.id("wear_crack_\($0)")) }
    static let scorchLayers = (1...3).map { Int(Tex.id("wear_scorch_\($0)")) }
    static let dentLayers = (1...3).map { Int(Tex.id("wear_dent_\($0)")) }
    static let shardLayer = Int(Tex.id("fx_shard"))

    // The chipped geometry the mesher and collision use for a damage entry (0: the block stays whole and shows a
    // decal instead).
    @inline(__always) static func chipVisual(_ v: UInt8, _ id: BlockID) -> UInt8 {
        let lv = Int(v & 31)
        switch kind[Int(id)] {
        case .metal, .glass: return 0
        case .stone: return lv <= 3 ? 0 : (v & 0xE0) | UInt8(min(7, (lv - 3) * 2 - 1))
        default: return v
        }
    }

    // Decal layer for a damaged block (nil: none, or the chips show instead).
    static func decalLayer(level lv: Int, scorch: Int, id: BlockID) -> Int? {
        let k = kind[Int(id)]
        if lv > 0 {
            switch k {
            case .stone: if lv <= 3 { return crackLayers[lv - 1] }
            case .glass: return crackLayers[min(3, lv)]
            case .metal: return dentLayers[min(2, (lv - 1) / 2)]
            default: break
            }
            if chipVisual(UInt8(lv), id) != 0 { return nil }
        }
        if scorch > 0 { return scorchLayers[min(2, scorch - 1)] }
        return nil
    }
}

// MARK: World state (World.scorch, World.wearVersion)

extension World {
    // Removes damage and scorch at a cell whose block changed.
    func clearWear(_ p: IVec3) {
        var changed = false
        if !damage.isEmpty, damage.removeValue(forKey: p) != nil { changed = true }
        if !scorch.isEmpty, scorch.removeValue(forKey: p) != nil { changed = true }
        if changed { wearVersion &+= 1 }
    }

    // Raises the scorch stage of a full block (1...3); a soot mark on stone, a burn on wood.
    func addScorch(_ p: IVec3, to stage: Int) {
        let id = block(p.x, p.y, p.z)
        guard Blocks.render[Int(id)] == RenderType.cube.rawValue, Wear.kind[Int(id)] != .glass, id != Wear.charcoal, id != Wear.smolder else { return }
        let cur = Int(scorch[p] ?? 0)
        let s = min(3, max(cur, stage))
        if s == cur { return }
        if scorch.count > 8192 && cur == 0 { return }
        scorch[p] = UInt8(s)
        wearVersion &+= 1
    }

    // The damage entries the mesher and collision see (decal-only stages left out, levels mapped per material).
    @inline(__always) func visualDamage(_ p: IVec3) -> UInt8? {
        guard let v = damage[p] else { return nil }
        let vis = Wear.chipVisual(v, block(p.x, p.y, p.z))
        return vis & 31 == 0 ? nil : vis
    }
}

// MARK: Game rules (mining, bullets, blasts)

extension Game {
    // One step of damage landing on a block face: records it (decal or chips) and throws the material's debris.
    // Returns true when the block gave way (glass shattering).
    @discardableResult
    func wearHit(_ p: IVec3, level: Int, normal n: IVec3, async: Bool = false, quiet: Bool = false, shatter: Bool = true) -> Bool {
        let b = world.block(p.x, p.y, p.z)
        guard Blocks.render[Int(b)] == RenderType.cube.rawValue, Blocks.hardness[Int(b)] >= 0 else { return false }
        let face = n.x > 0 ? 0 : (n.x < 0 ? 1 : (n.y > 0 ? 2 : (n.y < 0 ? 3 : (n.z > 0 ? 4 : 5))))
        let nv = V3(Float(n.x), Float(n.y), Float(n.z))
        let c = V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5 + nv * 0.5
        if shatter && Wear.kind[Int(b)] == .glass && level >= 3 { shatterGlass(p, from: -nv); return true }
        if async { world.chipAsync(p, level: level, face: face) } else { world.chip(p, level: level, face: face) }
        if quiet { return false }
        switch Wear.kind[Int(b)] {
        case .metal:
            particles.sparks(at: c, normal: nv, count: 5)
            sfx(.bulletImpact(.metal), 0.6, at: c)
        case .glass:
            particles.shards(at: c, normal: nv, count: 4, tint: Wear.glassTint(b))
            sfx(.iceCrack, 0.5, at: c)
        case .stone:
            particles.chipBits(b, at: c, normal: nv, face: face, count: level <= 3 ? 3 : 6)
            particles.dust(b, at: c, count: 3, spread: 0.3)
            sfx(.hit(soundMat(b)), 0.7, at: c)
        default:
            particles.chipBits(b, at: c, normal: nv, face: face, count: 6)
            particles.dust(b, at: c, count: 3, spread: 0.3)
            sfx(.hit(soundMat(b)), 0.7, at: c)
        }
        return false
    }

    // Glass gives way: the block bursts into shards flung along `dir` (the way the hit was travelling).
    func shatterGlass(_ p: IVec3, from dir: V3, sound: Bool = true) {
        let b = world.block(p.x, p.y, p.z)
        guard Wear.kind[Int(b)] == .glass else { return }
        let c = V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5
        world.setBlock(p.x, p.y, p.z, AIR)
        particles.shards(at: c, normal: dir, count: 14, tint: Wear.glassTint(b), burst: true)
        if sound { sfx(.glassBreak, 0.9, at: c) }
        fx.wear.shattered += 1
    }

    // Blast damage by material (Explosion.explode): `shaken` holds the blocks a ray stopped at and the share of
    // their cost it carried. Glass shatters, metal dents, stone cracks then chips, wood chips; soot on the crater rim.
    func blastWear(center c: V3, power: Float, shaken: [IVec3: Float], destroyed: Set<IVec3>) {
        let w = world
        var bits = 0, soot = 0
        for (b, share) in shaken where !destroyed.contains(b) && share > 0.15 {
            let id = w.block(b.x, b.y, b.z)
            guard Blocks.render[Int(id)] == RenderType.cube.rawValue, Blocks.hardness[Int(id)] >= 0 else { continue }
            let d = c - (V3(Float(b.x), Float(b.y), Float(b.z)) + 0.5)
            let ad = simd_abs(d)
            let face = ad.x >= ad.y && ad.x >= ad.z ? (d.x > 0 ? 0 : 1) : (ad.y >= ad.z ? (d.y > 0 ? 2 : 3) : (d.z > 0 ? 4 : 5))
            let nrm = [V3(1, 0, 0), V3(-1, 0, 0), V3(0, 1, 0), V3(0, -1, 0), V3(0, 0, 1), V3(0, 0, -1)][face]
            let kind = Wear.kind[Int(id)]
            if kind == .glass {
                if share > 0.3 { shatterGlass(b, from: -nrm, sound: bits < 6); bits += 1; continue }
            }
            w.chipAsync(b, level: max(1, min(6, Int(share * 7))), face: face)
            // Soot where the fireball licked: the face toward the blast, within reach of the flames.
            if kind != .glass && simd_length(d) < power * 0.9 + 1 && soot < 400 {
                w.addScorch(b, to: share > 0.6 ? 2 : 1)
                soot += 1
            }
            bits += 1
            if bits <= 30 {
                let at = V3(Float(b.x), Float(b.y), Float(b.z)) + 0.5 + nrm * 0.5
                switch kind {
                case .metal: particles.sparks(at: at, normal: nrm, count: 2)
                case .glass: particles.shards(at: at, normal: nrm, count: 2, tint: Wear.glassTint(id))
                default: particles.chipBits(id, at: at, normal: nrm, face: face, count: 2)
                }
            }
        }
        // The crater rim: every full block left facing the hole is sooted (darker near the centre).
        for b in destroyed where soot < 600 {
            for d in World.allDirs {
                let q = b + d
                if destroyed.contains(q) { continue }
                let dist = simd_length(c - (V3(Float(q.x), Float(q.y), Float(q.z)) + 0.5))
                w.addScorch(q, to: dist < power * 0.6 + 1 ? 2 : 1)
                soot += 1
            }
        }
    }
}

extension Wear {
    // Shard colour for a glass block: clear glass pale cyan, stained glass its dye.
    static func glassTint(_ id: BlockID) -> V3 {
        let k = Blocks.key(Blocks.groupBase[Int(id)])
        for (name, _) in BlockRegistry.colors where k.hasPrefix(name + "_stained") {
            if let h = BlockRegistry.colorHex[name] {
                return V3(Float((h >> 16) & 255), Float((h >> 8) & 255), Float(h & 255)) / 255 * 0.8 + 0.2
            }
        }
        return V3(0.85, 0.95, 1)
    }
}

// MARK: Debris

extension ParticleManager {
    // Glass shards: bright slivers flung out along the normal (a burst flings them wider), spinning down.
    func shards(at c: V3, normal n: V3, count: Int, tint: V3, burst: Bool = false) {
        for _ in 0..<count {
            let side = V3(Rand.float(in: -1...1), Rand.float(in: -1...1), Rand.float(in: -1...1)) * (burst ? 0.5 : 0.25)
            let v: V3 = n * Rand.float(in: 1...(burst ? 4.5 : 2.5)) + side * 5 + V3(0, Rand.float(in: 0.5...2), 0)
            add(Particle(pos: c + side, vel: v, life: Rand.float(in: 0.7...1.5), maxLife: 1.5, layer: Wear.shardLayer,
                         uv0: V2(0, 0), uvSize: 1, size: Rand.float(in: 0.05...0.12), gravity: 20, color: tint, collide: true))
        }
    }

    // Sparks off struck metal (bloom in Fancy).
    func sparks(at c: V3, normal n: V3, count: Int) {
        let layer = Int(Tex.id("smoke"))
        for _ in 0..<count {
            let side = V3(Rand.float(in: -1...1), Rand.float(in: -1...1), Rand.float(in: -1...1))
            let v: V3 = n * Rand.float(in: 2...5) + side * 3
            add(Particle(pos: c, vel: v, life: Rand.float(in: 0.12...0.35), maxLife: 0.35, layer: layer, uv0: V2(0, 0), uvSize: 1,
                         size: 0.035, gravity: 14, color: V3(1.5, 1.05, 0.45), collide: true, glow: true))
        }
    }
}

// MARK: Decals

// World-space quads for every damaged / scorched face near the camera, rebuilt when the damage maps change or the
// camera has moved on; written into the blended entity pass every frame.
final class WearDecals {
    struct Quad { var p: (V3, V3, V3, V3); var layer: Int32; var lit: Bool; var cell: IVec3 }
    var quads: [Quad] = []
    var version = -1
    var centre = V3(0, -1000, 0)
    var builtAt = -1.0
    static let maxQuads = 3000
    static let range: Float = 64

    func rebuild(_ w: World, eye: V3) {
        quads.removeAll(keepingCapacity: true)
        version = w.wearVersion
        centre = eye
        if w.damage.isEmpty && w.scorch.isEmpty { return }
        var cells = Set<IVec3>()
        for p in w.damage.keys { cells.insert(p) }
        for p in w.scorch.keys { cells.insert(p) }
        let r2 = WearDecals.range * WearDecals.range
        var near: [(Float, IVec3)] = []
        for p in cells {
            let d = V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5 - eye
            let dd = simd_length_squared(d)
            if dd < r2 { near.append((dd, p)) }
        }
        if near.count * 3 > WearDecals.maxQuads { near.sort { $0.0 < $1.0 } }
        let CT = Mesher.cornerTable, NT = Mesher.normalTable
        let e: Float = 0.004
        for (_, p) in near {
            if quads.count >= WearDecals.maxQuads { break }
            let id = w.block(p.x, p.y, p.z)
            guard Blocks.render[Int(id)] == RenderType.cube.rawValue else { continue }
            let lv = Int((w.damage[p] ?? 0) & 31)
            guard let layer = Wear.decalLayer(level: lv, scorch: Int(w.scorch[p] ?? 0), id: id) else { continue }
            let lit = Wear.dentLayers.contains(layer)
            let o = V3(Float(p.x), Float(p.y), Float(p.z))
            for f in 0..<6 {
                let q = IVec3(p.x + NT[f * 3], p.y + NT[f * 3 + 1], p.z + NT[f * 3 + 2])
                let nb = w.block(q.x, q.y, q.z)
                if Blocks.opaque[Int(nb)] || (nb == id && Blocks.cullSame[Int(id)]) { continue }
                var ps: [V3] = []
                for k in 0..<4 {
                    let ci = (f * 4 + k) * 3
                    ps.append(o + V3(CT[ci] == 1 ? 1 + e : -e, CT[ci + 1] == 1 ? 1 + e : -e, CT[ci + 2] == 1 ? 1 + e : -e))
                }
                quads.append(Quad(p: (ps[0], ps[1], ps[2], ps[3]), layer: Int32(layer), lit: lit, cell: q))
            }
        }
    }
}

extension Game {
    // Damage decals (Renderer, blended pass after the weather).
    func writeWear(_ wr: inout EntityWriter, eye: V3) {
        let w = world
        let dec = fx.decals
        // Rebuilt when the damage changes (at most 10 times a second: gunfire chips every frame) or the camera moves on.
        let moved = simd_length(eye - dec.centre) > 16
        if moved || (dec.version != w.wearVersion && (clock - dec.builtAt > 0.1 || clock < dec.builtAt)) {
            dec.rebuild(w, eye: eye)
            dec.builtAt = clock
        }
        if dec.quads.isEmpty { return }
        let uvs = [V2(0, 1), V2(1, 1), V2(1, 0), V2(0, 0)]
        let day = daylight
        let fadeFrom = WearDecals.range * 0.75
        for q in dec.quads {
            let mid = (q.p.0 + q.p.2) * 0.5
            let dist = simd_length(mid - eye)
            if dist > WearDecals.range { continue }
            let a = dist < fadeFrom ? 1 : max(0, 1 - (dist - fadeFrom) / (WearDecals.range - fadeFrom))
            var col = V4(1, 1, 1, a)
            if q.lit {
                // Dents carry highlights: lit like the face they sit on.
                let l = w.lightAt(q.cell.x, q.cell.y, q.cell.z)
                let k = max(Float(l.sky) / 15 * day, Float(l.block) / 15) * 0.9 + 0.1
                col = V4(k, k, k, a)
            }
            wr.quad([q.p.0 - eye, q.p.1 - eye, q.p.2 - eye, q.p.3 - eye], uvs, Int(q.layer), col)
        }
    }
}

// Counters for checks and the HUD debug line.
struct WearStats { var shattered = 0; var charred = 0; var burnedAway = 0 }

// MARK: Blocks (charcoal from fire, snow layers from storms)

extension BlockRegistry {
    func registerWorldFXBlocks() {
        // Charred through wood: smouldering (glows, cools in a few fire ticks) then charcoal (crumbles to charcoal lumps).
        var ch = BlockDef("charcoal_block", "Charcoal Block")
        ch.tex = ["charcoal_block"]; ch.hardness = 0.8; ch.tool = .axe; ch.sound = .wood; ch.flammable = true
        add(ch)
        var sm = BlockDef("smoldering_charcoal", "Smouldering Charcoal")
        sm.tex = ["smoldering_charcoal"]; sm.hardness = 0.6; sm.tool = .axe; sm.sound = .wood; sm.emit = 7; sm.hidden = true
        sm.damage = 1
        add(sm)
        // Flood water (Flood.swift): a water source of its own so the flood model can always find and drain it.
        var fw = BlockDef("flood_water", "Water")
        fw.render = .liquid; fw.layer = .translucent; fw.tex = ["water"]; fw.opaque = false; fw.collide = false
        fw.skyStop = true; fw.replaceable = true; fw.fluid = 0; fw.hardness = -1; fw.hidden = true; fw.sound = .snow
        fw.fluidKind = 1
        add(fw)
        // Its shoreline: a half-height flowing state where the flood surface meets lower open ground (no water walls).
        var fe = fw
        fe.name = "flood_water_edge"; fe.fluid = 3
        add(fe)
        // Deep snow: layers 2...7 above the one-layer "snow" (8 layers make a snow block). Storms pile it up, sun and
        // warmth melt it back (Storms.swift). The deeper ones are solid underfoot.
        for k in 2...7 {
            var s = BlockDef("snow_layers_\(k)", "Snow")
            s.tex = ["snow_block"]; s.render = .model; s.opaque = false; s.hardness = 0.1 + 0.02 * Float(k); s.tool = .shovel
            s.sound = .snow; s.boxes = [Box(0, 0, 0, 16, 2 * k, 16)]; s.skyStop = false; s.group = "snow_layers"; s.hidden = true
            s.collide = k >= 3
            add(s)
        }
    }
}
