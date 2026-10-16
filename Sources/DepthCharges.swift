import Foundation
import simd

// P278 (Oct 14 19:33-19:34, "we're gonna have submarines though, we need like depth charges"). Original content.
//   the charge   a Depth Charge (TNT, an iron ingot and gunpowder make two). Used from a boat, a ship's deck or its helm,
//                it rolls over the side behind you and sinks.
//   the rack     a Depth Charge Rack: two drums on sloping rails, set on any hull (front inboard, like a cannon). Using
//                it rolls a charge from the pack off its back; sneak-use turns its depth dial (shallow 8, middle 16, deep
//                28 blocks under the surface: one, two or three clicks, and the brass pointer climbs). From the helm, use
//                drops one from every rack aboard.
//   the burst    a charge sinks at Submarine.chargeSink and bursts at its set depth, on the seabed, against a hull or
//                within 2.5 blocks of one: a deep underwater boom, a white plume thrown up from the surface over it, the
//                pressure wave (hulls within 7 blocks take a second blast on their near side; swimmers and sea creatures
//                within 10 are hurt; everyone near feels it).
//   the navy     frigates already answer a loud submarine with charges (Submarines.sonarTick); theirs carry the same
//                boom, plume and pressure wave now.
enum DepthCharge {
    static let key = "depth_charge"
    static let rackKey = "depth_charge_rack"
    static let depths: [Float] = [8, 16, 28]
    static let handDepth: Float = 12
    static let power: Float = 3.5
    static let shockReach: Float = 10
    static let hullShock: Float = 7
    static let proximity: Float = 2.5
    static let boatOwner = -7                        // (no ship has this id: a charge from a boat or the shore)

    // A rack state: facing k (0 north ... 3 east), depth setting d (0...2).
    static func rackState(_ base: BlockID, facing k: Int, depth d: Int) -> BlockID { base + BlockID(d * 4 + k) }
    static let rackBase: BlockID = Blocks.has(rackKey) ? Blocks.id(rackKey) : BlockID.max
    static func rackInfo(_ id: BlockID) -> (facing: Int, depth: Int)? {
        let base = rackBase
        guard Int(id) < Blocks.groupBase.count, Blocks.groupBase[Int(id)] == base else { return nil }
        let o = Int(id - base)
        return (o % 4, min(2, o / 4))
    }
    // The way a rack's front faces in its ship's frame.
    static func front(_ k: Int) -> V3 { [V3(0, 0, -1), V3(0, 0, 1), V3(-1, 0, 0), V3(1, 0, 0)][max(0, min(3, k))] }
}

extension BlockRegistry {
    func registerDepthChargeBlocks() {
        func turned(_ boxes: [Box], _ f: Int) -> [Box] {
            boxes.map { b in
                func p(_ x: Int, _ z: Int) -> (Int, Int) {
                    switch f {
                    case 1: return (16 - x, 16 - z)
                    case 2: return (z, 16 - x)
                    case 3: return (16 - z, x)
                    default: return (x, z)
                    }
                }
                let a = p(Int(b.x0), Int(b.z0)), c = p(Int(b.x1), Int(b.z1))
                return Box(min(a.0, c.0), Int(b.y0), min(a.1, c.1), max(a.0, c.0), Int(b.y1), max(a.1, c.1), tex: b.tex)
            }
        }
        func t6(_ n: String) -> [UInt16] { Array(repeating: Tex.id(n), count: 6) }
        var rack = BlockDef(DepthCharge.rackKey, "Depth Charge Rack")
        rack.tex = ["ship_metal"]; rack.render = .model; rack.layer = .cutout; rack.opaque = false; rack.hardness = 3
        rack.tool = .pickaxe; rack.requiresTool = true; rack.sound = .stone; rack.skyStop = false; rack.resistance = 6
        let metal = t6("ship_metal"), dark = t6("ship_wood_dark"), brass = t6("ship_brass"), drum = t6("depth_charge_drum")
        // Front (the dial) toward -Z; the rails run down toward +Z, where the charges roll off.
        let frame = [Box(1, 0, 0, 15, 2, 16, tex: dark), Box(1, 2, 0, 3, 7, 16, tex: metal), Box(13, 2, 0, 15, 7, 16, tex: metal),
                     Box(3, 2, 14, 13, 4, 16, tex: metal), Box(5, 2, 0, 11, 12, 2, tex: metal)]
        let drums = [Box(4, 2, 3, 12, 10, 8, tex: drum), Box(4, 2, 8, 12, 10, 13, tex: drum), Box(7, 10, 4, 9, 11, 7, tex: brass)]
        for d in 0..<3 {
            let pointer = Box(7, 4 + d * 3, 0, 9, 6 + d * 3, 1, tex: brass)
            for (k, dir) in ["north", "south", "west", "east"].enumerated() {
                var s = rack
                s.name = d == 0 ? (k == 0 ? rack.name : "\(rack.name)[\(dir)]") : "\(rack.name)[\(dir),d\(d)]"
                s.group = rack.name
                s.hidden = d != 0 || k != 0
                s.boxes = turned(frame + drums + [pointer], k)
                add(s)
            }
        }
    }
}

extension TextureGen {
    static func depthChargePainters(_ p: inout [String: Painter]) {
        // An olive steel drum: two raised hoops, a seam and stencilled rivets.
        p["depth_charge_drum"] = { x, y in
            if y == 3 || y == 12 { return hex(0x6E7A5E) }
            if y == 4 || y == 13 { return hex(0x2C3326) }
            if x == 7 && y > 4 && y < 12 { return hex(0x343C2D) }
            if (x == 2 || x == 13) && y % 3 == 1 { return hex(0x8A9078) }
            return hex(0x4A5640, 0.88 + 0.12 * r(x, y, 2690))
        }
    }
}

extension Recipes {
    static func depthChargeRecipes() -> [Recipe?] {
        [shapeless(["tnt", "iron_ingot", "gunpowder"], DepthCharge.key, 2),
         shaped(["I I", "ICI", "PPP"], ["I": "iron_ingot", "C": "chain", "P": "#planks"], DepthCharge.rackKey)]
    }
}

extension ItemRegistry {
    func registerDepthChargeItems() {
        guard !has(DepthCharge.key) else { return }
        var d = ItemDef(DepthCharge.key, "Depth Charge")
        d.sprite = Sprite(mask: "depth_charge", base: 0x2E332A, extras: ["c": 0x4A5640, "d": 0x6E7A5E, "e": 0xA8823A])
        d.maxStack = 16
        add(d)
    }
}

extension Game {
    var depthChargesHeld: Int {
        guard Items.has(DepthCharge.key) else { return 0 }
        let id = Items.id(DepthCharge.key)
        var n = 0
        for i in 0..<inventory.main.count where inventory.main[i].item == id { n += inventory.main[i].count }
        return n
    }

    private func takeDepthCharge() -> Bool {
        if !survival { return true }
        guard Items.has(DepthCharge.key) else { return false }
        let id = Items.id(DepthCharge.key)
        let inv = inventory.main
        // The one in hand first, then the pack.
        let sel = inventory.selected
        for i in [sel] + Array(0..<inv.count) where inv[i].item == id && inv[i].count > 0 {
            var s = inv[i]
            s.count -= 1
            inv[i] = s.count > 0 ? s : ItemStack()
            return true
        }
        return false
    }

    // The y a charge dropped at p bursts at: `depth` under the water's surface below it (or 40 down, where it meets
    // the ground first).
    private func fuseY(below p: V3, depth: Float) -> Float {
        let x = Int(floor(p.x)), z = Int(floor(p.z))
        var y = Int(floor(p.y))
        let stop = max(1, y - 40)
        while y > stop {
            let b = world.rawBlock(x, y, z)
            if Blocks.fluidKind[Int(b)] == 1 { return Float(y + 1) - depth }
            if Blocks.collide[Int(b)] { break }
            y -= 1
        }
        return p.y - 40
    }

    private func launchCharge(at p: V3, vel: V3, owner: Int, depth: Float) {
        let sh = Shell(pos: p, vel: vel, owner: owner, power: DepthCharge.power)
        sh.kind = 5; sh.gravity = 0; sh.life = 16
        sh.fuseY = fuseY(below: p, depth: depth)
        world.ships.shells.append(sh)
        sfx(.place(.metal), 0.7, at: p)
        sfx(.hit(.metal), 0.6, at: p)
    }

    // A rack rolls one charge off its back. Returns false when the pack has none.
    @discardableResult
    func rackDrop(_ s: Ship, _ cell: IVec3, _ id: BlockID) -> Bool {
        guard let (k, d) = DepthCharge.rackInfo(id) else { return false }
        let centre = s.toWorld(V3(Float(cell.x), Float(cell.y), Float(cell.z)) + 0.5)
        guard takeDepthCharge() else {
            sfx(.dispenseFail, 0.8, at: centre)
            return false
        }
        let back = s.rot.act(-DepthCharge.front(k))
        launchCharge(at: centre + back * 0.9 + V3(0, 0.1, 0), vel: back * 2.5 + s.root.vel, owner: s.root.id, depth: DepthCharge.depths[d])
        return true
    }

    // Ship interaction on a rack: use drops, sneak-use turns the dial.
    func rackUse(_ s: Ship, _ cell: IVec3, _ id: BlockID, sneak: Bool) -> Bool {
        guard let (k, d) = DepthCharge.rackInfo(id) else { return false }
        let centre = s.toWorld(V3(Float(cell.x), Float(cell.y), Float(cell.z)) + 0.5)
        if sneak {
            let nd = (d + 1) % 3
            world.ships.setBlock(s, cell, DepthCharge.rackState(Blocks.id(DepthCharge.rackKey), facing: k, depth: nd))
            for i in 0...nd { sfx(.click, 1.1 + Float(i) * 0.15, at: centre) }
            sfx(.lever, 0.6, at: centre)
            return true
        }
        rackDrop(s, cell, id)
        return true
    }

    // At the helm: every rack aboard lets one go (as many as there are charges). False when the ship has no racks.
    func dropFromRacks(_ s: Ship) -> Bool {
        let r = s.root
        var racks: [(Ship, IVec3, BlockID)] = []
        for part in [r] + world.ships.turrets(of: r) {
            let g = part.grid
            for i in 0..<g.blocks.count where g.blocks[i] != AIR && DepthCharge.rackInfo(g.blocks[i]) != nil {
                let x = i % g.sx, z = (i / g.sx) % g.sz, y = i / (g.sx * g.sz)
                racks.append((part, IVec3(x, y, z), g.blocks[i]))
            }
        }
        guard !racks.isEmpty else { return false }
        for (ps, c, b) in racks { if !rackDrop(ps, c, b) { break } }
        return true
    }

    // Use with a charge in hand: from the helm through the racks (or over the stern), from a deck or a boat over the
    // side behind you.
    func depthChargeUse() -> Bool {
        guard Items.has(DepthCharge.key), held.item == Items.id(DepthCharge.key) else { return false }
        let ships = world.ships
        let flat = simd_normalize(V3(player.look.x, 0, player.look.z) + V3(0.0001, 0, 0))
        if let s = ships.pilot {
            if dropFromRacks(s) { swing = 1; return true }
            let r = s.root
            let stern = r.toWorld(V3(r.com.x, r.localMin.y + 1, r.localMax.z + 1.2))
            guard takeDepthCharge() else { return true }
            launchCharge(at: stern, vel: r.rot.act(V3(0, 0, 2)) + r.vel, owner: r.id, depth: DepthCharge.handDepth)
            swing = 1
            return true
        }
        let inBoat = riding?.kind == .boat
        guard inBoat || ships.aboard != nil else { return false }
        // Aimed at a rack on the deck: the rack takes it (Game.shipInteract -> rackUse).
        if let (ts, tc, _) = ships.target, DepthCharge.rackInfo(ts.grid.get(tc.x, tc.y, tc.z)) != nil { return false }
        let from = player.pos + V3(0, inBoat ? 0.6 : 1.0, 0) + flat * (inBoat ? -1.6 : 1.2)
        let carrier = riding?.vel ?? ships.aboard?.root.vel ?? V3(0, 0, 0)
        guard takeDepthCharge() else { return true }
        launchCharge(at: from, vel: flat * (inBoat ? -1.5 : 2) + carrier, owner: ships.aboard?.root.id ?? DepthCharge.boatOwner,
                     depth: DepthCharge.handDepth)
        swing = 1
        return true
    }

    // ShipCombat, a depth charge bursting at p: the boom, the plume, the pressure wave (Explosion.explode follows).
    func depthChargeBurst(at p: V3, power: Float, owner: Int) {
        // The surface over it.
        let x = Int(floor(p.x)), z = Int(floor(p.z))
        var y = Int(floor(p.y))
        var top: Int?
        for _ in 0..<48 {
            let b = world.rawBlock(x, y, z)
            if Blocks.fluidKind[Int(b)] != 1 { break }
            top = y + 1
            y += 1
        }
        sfx(.depthBoom, 1, at: p)
        if let t = top {
            let depth = Float(t) - p.y
            let s = V3(p.x, Float(t), p.z)
            if depth < 32 {
                // The plume: a white column thrown up, taller the nearer the surface, and spray falling back round it.
                let k = 1 - depth / 32
                let puff = Int(Tex.id("puff"))
                for i in 0..<70 {
                    let up = Rand.float(in: 6...16) * (0.5 + 0.5 * k)
                    let side = Rand.float(in: 0...(i < 40 ? 0.9 : 3.2))
                    let a = Rand.float(in: 0..<(2 * .pi))
                    let at = s + V3(cosf(a) * side * 0.4, Rand.float(in: 0...0.6), sinf(a) * side * 0.4)
                    let v = V3(cosf(a) * side, i < 40 ? up : up * 0.45, sinf(a) * side)
                    particles.add(Particle(pos: at, vel: v, life: Rand.float(in: 1.6...2.8), maxLife: 2.8, layer: puff, uv0: V2(0, 0),
                                           uvSize: 1, size: Rand.float(in: 0.6...1.4), gravity: 9.5, color: V3(0.92, 0.96, 1),
                                           collide: false, glow: false))
                }
                sfx(.shipSplash, 1.2, at: s)
            }
            for _ in 0..<20 { particles.bubble(at: p + V3(Rand.float(in: -2...2), Rand.float(in: -1...3), Rand.float(in: -2...2))) }
        }
        // The pressure wave: hulls near take a second blast on their side toward it.
        for s in world.ships.list where s.parent == nil && s.root.id != owner {
            let q = simd_clamp(p, s.worldMin, s.worldMax)
            let d = simd_length(q - p)
            guard d < DepthCharge.hullShock, d > 0.5 else { continue }
            world.ships.blast(at: q + simd_normalize(p - q) * 0.4, power: power * 0.75 * (1 - d / DepthCharge.hullShock) + 1, game: self)
        }
        // Swimmers and sea creatures.
        let reach = DepthCharge.shockReach
        let wet = { (v: V3) -> Bool in Blocks.fluidKind[Int(self.world.rawBlock(Int(floor(v.x)), Int(floor(v.y)), Int(floor(v.z))))] == 1 }
        let pd = simd_length(player.pos + V3(0, 0.9, 0) - p)
        if pd < reach * 3 { addShake(min(1, 0.8 * (1 - pd / (reach * 3)) + 0.15)) }
        if pd < reach && wet(player.pos + V3(0, 0.9, 0)) && world.ships.aboardOrPilot == nil {
            let k: Float = 1 - pd / reach
            hurtPlayer(Int((k * 12).rounded()) + 1, from: p, cause: "was crushed by a depth charge", knockback: 0, type: .explosion)
        }
        for m in mobs.mobs where m.health > 0 && m.kind != .boat && m.kind.spec.behavior != .vehicle {
            let c = m.pos + V3(0, m.height * 0.5, 0)
            let d = simd_length(c - p)
            guard d < reach, wet(c) else { continue }
            m.hit(from: p, damage: Int(((1 - d / reach) * 14).rounded()) + 1, knockback: 0)
        }
    }
}

extension ShipManager {
    // The ship the player rides or steers, if any.
    var aboardOrPilot: Ship? { pilot ?? aboard }
    // A depth charge within reach of any hull but its own sets off (ShipCombat).
    func nearHull(_ p: V3, except: Int, reach: Float) -> Bool {
        for s in list where s.root.id != except {
            if p.x > s.worldMin.x - reach && p.x < s.worldMax.x + reach && p.y > s.worldMin.y - reach && p.y < s.worldMax.y + reach
                && p.z > s.worldMin.z - reach && p.z < s.worldMax.z + reach { return true }
        }
        return false
    }
}
