import Foundation
import simd

// The Ashguard's sites in the Ash Vault (task 22), laid out like a field army's rear area around its headquarters:
// the citadel (HQ) at x 0, z 0 where the roads meet; a tank column staged on the east road; motor pools, fuel depots,
// supply hubs and artillery batteries in a ring around it; pillbox outposts further out; small patrol camps everywhere
// else in the vault. Everything black, marked in red with the Ashguard's own ember mark (a red diamond split by a black
// bar). Units arrive as structure mobs ("key[@ash][:variant][^heading]", AshWar.spawnPending).

extension BlockRegistry {
    func registerAshguardBlocks() {
        func block(_ n: String, _ disp: String, side: String? = nil, top: String? = nil, h: Float, emit: UInt8 = 0, snd: SoundMat = .stone) {
            guard !has(n) else { return }
            var d = BlockDef(n, disp)
            let s = side ?? n
            d.tex = [s, s, top ?? s, top ?? s, s, s]
            d.hardness = h; d.resistance = h < 0 ? 3_600_000 : 30; d.tool = .pickaxe; d.requiresTool = true; d.sound = snd; d.emit = emit
            add(d)
        }
        block("ash_concrete", "Ashcrete", h: 4)
        block("ash_plating", "Ash Plating", h: 6)
        block("ash_mark", "Ember Mark Plate", h: 3)
        block("ash_lamp", "Red Signal Lamp", h: 1, emit: 13, snd: .glass)
        block("ash_crate", "Ashguard Crate", side: "ash_crate", top: "ash_crate_top", h: 2, snd: .wood)
        block("ash_sandbags", "Sandbags", h: 1, snd: .sand)
        block("ash_lift", "Lift Plate", h: -1, emit: 15)
        if !has("ash_mortar") {
            // A mortar tube on its baseplate (the gap pass: the crews beside one lob shells, AshArmy.swift).
            var d = BlockDef("ash_mortar", "Ashguard Mortar")
            d.tex = ["ash_mortar", "ash_mortar", "ash_mortar_top", "ash_mortar", "ash_mortar", "ash_mortar"]
            // P318: the breech handle at the tube's foot (use it to spike the tube: AshSabotage.swift).
            d.render = .model; d.opaque = false; d.boxes = [Box(2, 0, 2, 14, 2, 14), Box(6, 2, 6, 10, 15, 10), Box(10, 3, 7, 14, 5, 9), Box(13, 2, 7, 15, 7, 9)]
            d.hardness = 3; d.tool = .pickaxe; d.sound = .metal
            add(d)
            // A spiked tube: split and blackened, the handle gone.
            var s = BlockDef("ash_mortar_spiked", "Spiked Mortar")
            s.tex = ["ash_mortar_spiked", "ash_mortar_spiked", "ash_mortar_top", "ash_mortar_spiked", "ash_mortar_spiked", "ash_mortar_spiked"]
            s.render = .model; s.opaque = false; s.boxes = [Box(2, 0, 2, 14, 2, 14), Box(6, 2, 6, 10, 9, 10), Box(5, 9, 6, 7, 12, 10), Box(9, 9, 6, 11, 11, 10)]
            s.hardness = 3; s.tool = .pickaxe; s.sound = .metal
            add(s)
        }
        // The last war (AshLines.swift, AshFinal.swift): banners, the citadel's standard, the lines' wire, the
        // Chancellor's Bunker (its concrete and blast door break for nothing; the door opens when the last battle is won).
        // Cloth hangs flat: the base state shows its picture on the -Z and +Z faces (a wall facing north or south),
        // "[x]" on -X and +X; the other faces are plain edge. The +Z and +X faces carry the mirror tile, so a 3x3
        // standard laid out by AshWar.standard reads right from both sides (the picture is mirror-symmetric).
        func cloth(_ n: String, _ disp: String, tex: String, mirror: String? = nil) {
            guard !has(n) else { return }
            let e = "ash_banner_edge", m = mirror ?? tex
            var d = BlockDef(n, disp)
            d.tex = [e, e, e, e, m, tex]
            d.hardness = 0.8; d.sound = .wool
            add(d)
            var x = d
            x.name = n + "[x]"; x.group = n; x.hidden = true
            x.tex = [m, tex, e, e, e, e]
            add(x)
        }
        cloth("ash_banner_top", "Ashguard Banner", tex: "ash_banner_top")
        cloth("ash_banner_mark", "Ashguard Banner", tex: "ash_banner_mark")
        cloth("ash_banner", "Ashguard Banner", tex: "ash_banner")
        cloth("ash_banner_end", "Ashguard Banner", tex: "ash_banner_end")
        for i in 0..<9 { cloth("ash_standard_\(i)", "Ashguard Standard", tex: "ash_standard_\(i)", mirror: "ash_standard_\(i / 3 * 3 + 2 - i % 3)") }
        block("ash_bunkercrete", "Bunker Concrete", h: -1)
        block("ash_blastdoor", "Blast Door", h: -1)
        if !has("ash_wire") {
            var d = BlockDef("ash_wire", "Barbed Wire")
            d.tex = ["ash_wire"]; d.render = .cross; d.layer = .cutout; d.opaque = false; d.collide = false
            d.hardness = 1.5; d.tool = .sword; d.sound = .metal
            add(d)
        }
        // P326 (b): the wrecks of the last war's set pieces (AshFront.swift): burnt steel, scorched olive-drab plate, an
        // aircraft's riveted skin.
        block("wreck_hull", "Burnt Hull Plate", h: 5, snd: .metal)
        block("wreck_olive", "Scorched Armour Plate", h: 5, snd: .metal)
        block("wreck_alu", "Torn Aircraft Skin", h: 3, snd: .metal)
        if !has("ash_drum") {
            var d = BlockDef("ash_drum", "Fuel Drum")
            d.tex = ["ash_drum_side", "ash_drum_side", "ash_drum_top", "ash_drum_top", "ash_drum_side", "ash_drum_side"]
            // P318: a brass bung on top (put a flame to it: AshSabotage.swift).
            d.render = .model; d.opaque = false; d.boxes = [Box(2, 0, 2, 14, 15, 14), Box(9, 15, 4, 12, 16, 7)]
            d.hardness = 2; d.tool = .pickaxe; d.sound = .stone
            add(d)
        }
    }
}

extension TextureGen {
    static func ashPainters(_ p: inout [String: Painter]) {
        // Ashcrete: black cast concrete, faint form-board lines.
        p["ash_concrete"] = { x, y in
            var k: Float = 0.96 + 0.06 * r(x / 3, y / 3, 3301) + 0.03 * r(x, y, 3302)
            if y % 8 == 7 { k *= 0.82 }
            return hex(0x26262A, k)
        }
        // Ash plating: black steel panels, rivets at the seams.
        p["ash_plating"] = { x, y in
            if x == 0 || y == 0 { return hex(0x121214) }
            if (x == 2 || x == 13) && (y == 2 || y == 13) { return hex(0x4A4A50) }
            return hex(0x222226, 0.95 + 0.08 * r(x / 4, y / 2, 3303))
        }
        // The ember mark: a red plate with a black-edged diamond split by a black bar (the Ashguard's own sign).
        p["ash_mark"] = { x, y in
            let cx = Float(x) - 7.5, cy = Float(y) - 7.5
            let d = abs(cx) + abs(cy)
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x1A1A1C) }
            if d < 6.6 && abs(cx) < 1 { return hex(0x101012) }
            if d < 6.6 { return hex(0xC81E1E, 0.95 + 0.05 * r(x, y, 3304)) }
            if d < 7.6 { return hex(0x101012) }
            return hex(0x9E1616, 0.95 + 0.05 * r(x, y, 3305))
        }
        p["ash_lamp"] = { x, y in
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x18181A) }
            if x == 8 || y == 8 { return hex(0x2A1010) }
            let c = Float(abs(x - 8) + abs(y - 8))
            return hex(0xFF5A3C, 1.05 - c * 0.04)
        }
        // The lift home (after victory): a glowing plate in a red ring.
        p["ash_lift"] = { x, y in
            let d = max(abs(Float(x) - 7.5), abs(Float(y) - 7.5))
            if d > 6.5 { return hex(0x1A1A1C) }
            if d > 5 { return hex(0xD02A1E) }
            return hex(0xFFD9A0, 0.9 + 0.1 * r(x, y, 3311))
        }
        p["ash_crate"] = { x, y in
            if x == 0 || x == 15 || y == 0 || y == 15 { return hex(0x2A2018) }
            if y == 7 || y == 8 { return hex(0xA81C1C, 0.95 + 0.05 * r(x, y, 3306)) }
            return hex(0x3A2E22, 0.92 + 0.1 * r(x, y / 4, 3307))
        }
        p["ash_crate_top"] = { x, y in
            if x == 0 || x == 15 || y == 0 || y == 15 { return hex(0x2A2018) }
            return hex(0x3A2E22, 0.92 + 0.1 * r(x / 4, y, 3308))
        }
        p["ash_sandbags"] = { x, y in
            let row = y / 4, off = row % 2 == 0 ? 0 : 4
            if y % 4 == 3 || (x + off) % 8 == 7 { return hex(0x2E2A24) }
            return hex(0x4E483E, 0.9 + 0.1 * r(x / 2, y, 3309) + 0.05 * Float(y % 4 == 0 ? 1 : 0))
        }
        p["ash_mortar"] = { x, y in
            if y == 3 || y == 12 { return hex(0x9E1616) }
            return hex(0x2A2A2E, 0.9 + 0.12 * Float(abs(x - 8)) / 8 + 0.04 * r(x, y, 3312))
        }
        p["ash_mortar_spiked"] = { x, y in
            if y == 3 { return hex(0x5A1414) }
            return hex(0x18181A, 0.8 + 0.25 * r(x, y, 3314) + 0.06 * Float(abs(x - 8)) / 8)
        }
        p["ash_mortar_top"] = { x, y in
            let d = max(abs(Float(x) - 7.5), abs(Float(y) - 7.5))
            return d < 2.5 ? hex(0x060607) : hex(0x2A2A2E, 0.95 + 0.06 * r(x, y, 3313))
        }
        p["ash_drum_side"] = { x, y in
            if y >= 6 && y <= 8 { return hex(0xB81E1E) }
            if y == 2 || y == 12 { return hex(0x101012) }
            return hex(0x242428, 0.9 + 0.12 * Float(abs(x - 8)) / 8)
        }
        // Banners (the last war): red cloth, black edging, the ember mark (a black diamond split by a bar) on a white disc.
        func cloth(_ x: Int, _ y: Int) -> V4 { hex(0xA81616, 0.9 + 0.08 * r(x, y / 3, 3320) + 0.05 * Float((x + y) % 2)) }
        func emblem(_ cx: Float, _ cy: Float, _ rad: Float) -> V4? {
            let d = abs(cx) + abs(cy)
            if cx * cx + cy * cy > rad * rad { return nil }
            if d < rad * 0.82 && (abs(cx) < rad * 0.13 || d > rad * 0.52) { return hex(0x0E0E10) }
            return hex(0xE8E4DA, 0.97 + 0.03 * r(Int(cx * 3), Int(cy * 3), 3321))
        }
        p["ash_banner_edge"] = { x, y in cloth(x, y) }
        p["ash_banner"] = { x, y in x == 1 || x == 14 ? hex(0x101012) : cloth(x, y) }
        p["ash_banner_top"] = { x, y in
            if y <= 1 { return hex(0x2A2A2E, 0.9 + 0.2 * Float(x % 4 == 0 ? 1 : 0)) }
            if y == 3 || x == 1 || x == 14 { return hex(0x101012) }
            return cloth(x, y)
        }
        p["ash_banner_mark"] = { x, y in
            if let e = emblem(Float(x) - 7.5, Float(y) - 7.5, 6.6) { return e }
            return x == 1 || x == 14 ? hex(0x101012) : cloth(x, y)
        }
        p["ash_banner_end"] = { x, y in
            if y >= 14 { return x % 2 == 0 ? hex(0x101012) : hex(0x6A0E0E) }
            if y == 12 || x == 1 || x == 14 { return hex(0x101012) }
            return cloth(x, y)
        }
        // The citadel's 3x3 standard: one 48-pixel picture over nine blocks (tile i = column i % 3, row i / 3 from the top).
        for i in 0..<9 {
            let ox = (i % 3) * 16, oy = (i / 3) * 16
            p["ash_standard_\(i)"] = { x, y in
                let X = ox + x, Y = oy + y
                if X <= 1 || Y <= 1 || X >= 46 || Y >= 46 { return hex(0x101012) }
                if let e = emblem(Float(X) - 23.5, Float(Y) - 23.5, 17) { return e }
                return cloth(X, Y)
            }
        }
        // Bunker concrete: heavy poured concrete with shuttering lines and tie holes; the blast door: riveted steel
        // leaves with red-and-black hazard bands.
        p["ash_bunkercrete"] = { x, y in
            if (x == 3 || x == 12) && (y == 4 || y == 11) { return hex(0x16161A) }
            var k: Float = 0.95 + 0.07 * r(x / 2, y / 2, 3322) + 0.03 * r(x, y, 3323)
            if y % 8 == 0 { k *= 0.84 }
            return hex(0x3A3A40, k)
        }
        p["ash_blastdoor"] = { x, y in
            if x == 7 || x == 8 { return hex(0x101012) }
            if y <= 2 || y >= 13 { return ((x + y) / 3) % 2 == 0 ? hex(0xB01A14) : hex(0x141416) }
            if (x == 2 || x == 13) && y % 3 == 0 { return hex(0x5A5A60) }
            return hex(0x2C2C30, 0.94 + 0.08 * r(x / 3, y, 3324))
        }
        // Barbed wire: two twisted strands with barbs, the rest see-through.
        p["ash_wire"] = { x, y in
            let strand = (y == 4 + (x / 2) % 2) || (y == 11 - (x / 2) % 2)
            let barb = (x % 5 == 2) && (abs(y - 4) <= 1 || abs(y - 11) <= 1)
            if strand || barb { return hex(0x5E5A56, 0.85 + 0.25 * r(x, y, 3325)) }
            return TextureGen.clear
        }
        // P326: wreck plating: burnt steel (soot, rust blooms, a rivet line), olive drab blistered and blackened, an
        // aircraft's grey skin in riveted panels streaked with soot.
        p["wreck_hull"] = { x, y in
            if (x == 1 || x == 14) && y % 4 == 2 { return hex(0x4A3E36) }
            if r(x / 2, y / 2, 3330) > 0.74 { return hex(0x6A3A20, 0.8 + 0.25 * r(x, y, 3331)) }
            return hex(0x2A2624, 0.75 + 0.35 * r(x / 3, y / 3, 3332) + 0.06 * r(x, y, 3333))
        }
        p["wreck_olive"] = { x, y in
            let soot = r(x / 4, y / 3, 3334)
            if soot > 0.7 { return hex(0x1E1C18, 0.8 + 0.3 * r(x, y, 3335)) }
            if r(x, y, 3336) > 0.93 { return hex(0x6A4A2A) }                       // chipped to rust
            if y == 0 || x == 0 { return hex(0x3A3C24) }
            return hex(0x4E5232, 0.88 + 0.16 * r(x / 2, y / 2, 3337) - 0.25 * max(0, soot - 0.5))
        }
        p["wreck_alu"] = { x, y in
            if y % 8 == 0 || x == 0 { return hex(0x5E6264) }                       // panel seams
            if (y % 8 == 2 || y % 8 == 6) && x % 3 == 1 { return hex(0x6E7274) }    // rivets
            let streak = r(x, y / 6, 3338)
            if streak > 0.78 { return hex(0x2A2A2A, 0.8 + 0.3 * r(x, y, 3339)) }
            return hex(0x8A8E90, 0.9 + 0.12 * r(x / 4, y / 4, 3340))
        }
        p["ash_drum_top"] = { x, y in
            if (x - 10) * (x - 10) + (y - 5) * (y - 5) < 4 { return hex(0xB8903C, 0.9 + 0.15 * r(x, y, 3311)) }   // P318: the brass bung
            return hex(0x1C1C1E, 0.95 + 0.05 * r(x, y, 3310))
        }
    }
}

struct AshSite {
    let kind: String          // hq, staging, motorpool, fueldepot, supply, battery, outpost, camp
    let x: Int, z: Int
    let r: Int                // footprint half-size (square)
    let face: Int             // heading (degrees, 0 = toward -z, 90 = toward +x) the site faces (away from the HQ)
}

extension AshWar {
    static let ground = DeepGen.floorBase      // sites stand on the levelled vault floor
    static let ringRoad = 230
    static let campSpacing = 20                // chunks
    static let campInner = 560                 // camps only beyond the ring of outposts

    // The fixed layout around the HQ (same in every world: the citadel always stands at 0, 0).
    static let sites: [AshSite] = {
        var s: [AshSite] = [AshSite(kind: "hq", x: 0, z: 0, r: 46, face: 0),
                            AshSite(kind: "staging", x: 104, z: 13, r: 32, face: 90),
                            AshSite(kind: "motorpool", x: 150, z: -112, r: 32, face: 90),
                            AshSite(kind: "motorpool", x: -128, z: 152, r: 32, face: 270),
                            AshSite(kind: "fueldepot", x: -168, z: -118, r: 28, face: 0),
                            AshSite(kind: "fueldepot", x: 186, z: 144, r: 28, face: 180),
                            AshSite(kind: "supply", x: 262, z: -42, r: 26, face: 90),
                            AshSite(kind: "supply", x: -58, z: 268, r: 26, face: 180),
                            AshSite(kind: "battery", x: 44, z: -300, r: 22, face: 0),
                            AshSite(kind: "battery", x: -300, z: 46, r: 22, face: 270),
                            AshSite(kind: "battery", x: 236, z: 262, r: 22, face: 135)]
        s += townSites + [airfield]                                           // the gap pass (AshVault.swift)
        for k in 0..<8 {
            let a = (Float(k) * 45 + 22.5) * .pi / 180
            s.append(AshSite(kind: "outpost", x: Int(sinf(a) * 470), z: Int(-cosf(a) * 470), r: 16, face: k * 45 + 22))
        }
        return s
    }()

    // P326 (c): bases modelled on the period's real kinds: two heavy flak batteries guarding the citadel's approaches and
    // a heavy-water plant (its hall of electrolysis cells under a dam's penstocks), inside the Ember Line. A world whose
    // vault a save had already explored there goes without (frontOff, set as the vault loads: World.init).
    static let frontSites: [AshSite] = [AshSite(kind: "flak", x: -220, z: 290, r: 24, face: 180),
                                        AshSite(kind: "flak", x: 270, z: -230, r: 24, face: 90),
                                        AshSite(kind: "heavywater", x: -240, z: -230, r: 30, face: 0),
                                        AshSite(kind: "prisoncamp", x: 160, z: 300, r: 34, face: 180)]    // P347 (PrisonCamp.swift)
    static var frontOff = [Bool](repeating: false, count: frontSites.count)
    static func setFront(_ g: DeepGuard) {
        frontOff = frontSites.map { !g.clear(floorDiv($0.x, CS), floorDiv($0.z, CS), $0.r / CS + 2) }
    }

    // The black pads the army's sites stood on are trampled earth now (P326): coarse dirt with packed mud.
    static let padDirt = Blocks.id("coarse_dirt"), padMud = Blocks.has("packed_mud") ? Blocks.id("packed_mud") : Blocks.id("coarse_dirt")
    @inline(__always) static func padBlock(_ x: Int, _ z: Int) -> BlockID { hash3(x, 3, z, 0xA5) % 4 == 0 ? padMud : padDirt }
    // The site (before P326) whose pad covers (x, z): fixed sites, the lines' bunkers and checkpoints, patrol camps.
    static func padSite(_ x: Int, _ z: Int) -> AshSite? {
        for s in sites + AshLines.sites where abs(x - s.x) <= s.r && abs(z - s.z) <= s.r { return s }
        let span = campSpacing * CS
        let rx = floorDiv(x, span), rz = floorDiv(z, span)
        for oz in -1...1 { for ox in -1...1 {
            if let c = camp(regionX: rx + ox, regionZ: rz + oz), abs(x - c.x) <= c.r && abs(z - c.z) <= c.r { return c }
        } }
        return nil
    }

    // A patrol camp in this 20-chunk region, if any (beyond the outposts, off the roads).
    static func camp(regionX rx: Int, regionZ rz: Int) -> AshSite? {
        let h = hash3(rx, 13, rz, 0xA5C4)
        guard h % 4 != 0 else { return nil }
        let span = campSpacing * CS
        let x = rx * span + 40 + Int(h >> 4 % UInt32(span - 80)), z = rz * span + 40 + Int(h >> 14 % UInt32(span - 80))
        guard x * x + z * z > campInner * campInner, abs(x) > 24, abs(z) > 24 else { return nil }
        // Clear of the towns, the airfield and the rail lines (AshVault.swift).
        for t in townSites + [airfield] where abs(x - t.x) < t.r + 40 && abs(z - t.z) < t.r + 40 { return nil }
        guard railDistance(x, z) > 24 else { return nil }
        let face = Int(atan2f(Float(x), -Float(z)) * 180 / .pi)
        return AshSite(kind: "camp", x: x, z: z, r: 12, face: face)
    }

    // Roads: the two axes through the HQ (they run on through the whole vault, so following one always leads to the
    // citadel) and the ring road joining the sites.
    @inline(__always) static func roadDistance(_ x: Int, _ z: Int) -> Float {
        let axis = Float(min(abs(x), abs(z)))
        let d = sqrtf(Float(x * x + z * z))
        return min(axis, abs(d - Float(ringRoad)))
    }
    static func isRoad(_ x: Int, _ z: Int) -> Bool { roadDistance(x, z) < 2.6 }

    // Distance to the nearest site footprint or road: the vault floor flattens and keeps pillars, creeks, shell holes and
    // woods away. `front: false`: without P326's sites (the ground old saves were made with).
    static func clearance(_ x: Int, _ z: Int, front: Bool = true) -> Float {
        var best = min(roadDistance(x, z) - 3, railDistance(x, z) - 4, AshLines.distance(x, z))
        for s in sites {
            let dx = max(0, abs(x - s.x) - s.r), dz = max(0, abs(z - s.z) - s.r)
            best = min(best, sqrtf(Float(dx * dx + dz * dz)))
            if best <= 0 { return 0 }
        }
        if front {
            for (i, s) in frontSites.enumerated() where !frontOff[i] {
                let dx = max(0, abs(x - s.x) - s.r), dz = max(0, abs(z - s.z) - s.r)
                best = min(best, sqrtf(Float(dx * dx + dz * dz)))
                if best <= 0 { return 0 }
            }
        }
        let span = campSpacing * CS
        let rx = floorDiv(x, span), rz = floorDiv(z, span)
        for oz in -1...1 { for ox in -1...1 {
            guard let c = camp(regionX: rx + ox, regionZ: rz + oz) else { continue }
            let dx = max(0, abs(x - c.x) - c.r), dz = max(0, abs(z - c.z) - c.r)
            best = min(best, sqrtf(Float(dx * dx + dz * dz)))
        } }
        return max(0, best)
    }

    // `guardSet`: vault chunks a save generated before the towns, rail and airfield arrived (AshVault.swift).
    static func starts(seed: UInt64, guardSet: DeepGuard = DeepGuard()) -> [StructureStart] {
        (sites + AshLines.sites + frontSites).map { start($0, seed: seed, guardSet: guardSet) } + railStarts(guardSet: guardSet) + [AshFinal.start()]
    }

    static let campType = StructureType(name: "ash_camp", spacing: campSpacing, separation: 0, salt: 0, reach: 1) { seed, cx, cz in
        let span = campSpacing
        guard let c = camp(regionX: floorDiv(cx, span), regionZ: floorDiv(cz, span)) else { return nil }
        return start(c, seed: seed)
    }
    static var types: [StructureType] { [campType] }

    static func start(_ s: AshSite, seed: UInt64, guardSet: DeepGuard = DeepGuard()) -> StructureStart {
        let pseed = seed ^ UInt64(UInt32(bitPattern: Int32(truncatingIfNeeded: s.x &* 7919 &+ s.z &* 104729)))
        let lo = IVec3(s.x - s.r - 2, ground - 6, s.z - s.r - 2), hi = IVec3(s.x + s.r + 2, ground + 30, s.z + s.r + 2)
        let late = s.kind == "town" || s.kind == "airfield"
        let front = frontSites.firstIndex { $0.x == s.x && $0.z == s.z }
        return StructureStart(kind: "ash_" + s.kind, pieces: [Piece(min: lo, max: hi) { w in
            // A town or the airfield whose ground a save had already generated in part is left out whole (P326's sites
            // too: frontOff).
            if late && !guardSet.clear(floorDiv(s.x, CS), floorDiv(s.z, CS), s.r / CS + 2) { return }
            if let i = front, frontOff[i] { return }
            AshWar.build(&w, s, pseed)
        }],
                              anchor: IVec3(s.x, ground + 1, s.z))
    }
}

// MARK: Builders

struct AshKit {
    let concrete = Blocks.id("ash_concrete"), plating = Blocks.id("ash_plating"), mark = Blocks.id("ash_mark")
    let lamp = Blocks.id("ash_lamp"), crate = Blocks.id("ash_crate"), bags = Blocks.id("ash_sandbags"), drum = Blocks.id("ash_drum")
    let bars = Blocks.has("iron_bars") ? Blocks.id("iron_bars") : AIR
    let chain = Blocks.has("chain") ? Blocks.id("chain") : AIR
    let floor = Blocks.id("polished_blackstone"), basalt = Blocks.id("smooth_basalt"), black = Blocks.id("blackstone")
    let blackWool = Blocks.has("black_wool") ? Blocks.id("black_wool") : Blocks.id("blackstone")
    let redWool = Blocks.has("red_wool") ? Blocks.id("red_wool") : Blocks.id("ash_mark")
    let fire = Blocks.has("campfire") ? Blocks.id("campfire") : Blocks.id("ash_lamp")
    let console = Blocks.has("command_console") ? Blocks.id("command_console") : Blocks.id("ash_plating")
    let table = Blocks.id("crafting_table")
    let mortar = Blocks.id("ash_mortar")
    let whiteWool = Blocks.has("white_wool") ? Blocks.id("white_wool") : Blocks.id("ash_plating")
}

extension AshWar {
    // Cloth (AshSites' banners and the 3x3 standard) in world coordinates; `normalX`: the cloth faces along x.
    static let clothNames = ["ash_banner_top", "ash_banner_mark", "ash_banner", "ash_banner_end"] + (0..<9).map { "ash_standard_\($0)" }
    static let cloth: [String: (BlockID, BlockID)] = {
        var t: [String: (BlockID, BlockID)] = [:]
        for n in clothNames { t[n] = (Blocks.id(n), Blocks.id(n + "[x]")) }
        return t
    }()
    @inline(__always) static func cloth(_ n: String, _ normalX: Bool) -> BlockID { let p = cloth[n]!; return normalX ? p.1 : p.0 }

    // A long banner hanging from `top`: the rod, the mark, cloth, the fringe.
    static func banner(_ w: inout StructWriter, x: Int, z: Int, top: Int, len: Int = 4, normalX: Bool) {
        w.set(x, top, z, cloth("ash_banner_top", normalX))
        w.set(x, top - 1, z, cloth("ash_banner_mark", normalX))
        if len > 3 { for y in (top - len + 2)...(top - 2) { w.set(x, y, z, cloth("ash_banner", normalX)) } }
        w.set(x, top - len + 1, z, cloth("ash_banner_end", normalX))
    }

    // The 3x3 standard centred on (x, z), its top row at `top`. Column 0 of the picture goes at +x (cloth facing along
    // z) or -z (facing along x): that reads right from the -Z / -X side, and the mirror tiles on the +Z / +X faces
    // make the other side read right too.
    static func standard(_ w: inout StructWriter, x: Int, z: Int, top: Int, normalX: Bool) {
        for i in 0..<9 {
            let c = i % 3
            let b = cloth("ash_standard_\(i)", normalX)
            if normalX { w.set(x, top - i / 3, z + c - 1, b) } else { w.set(x + 1 - c, top - i / 3, z, b) }
        }
    }

    // Local frame: (u, v) with v pointing the way the site faces; the writer clips to the chunk being generated.
    struct Frame {
        let s: AshSite
        let fx: Int, fz: Int            // facing unit vector (rounded to the nearest axis)
        init(_ s: AshSite) {
            self.s = s
            let f = ((s.face % 360) + 360 + 45) % 360 / 90
            (fx, fz) = [(0, -1), (1, 0), (0, 1), (-1, 0)][f]
        }
        // u to the right of the facing, v forward.
        func x(_ u: Int, _ v: Int) -> Int { s.x + u * (-fz) + v * fx }
        func z(_ u: Int, _ v: Int) -> Int { s.z + u * fx + v * fz }
        var heading: Int { fx == 1 ? 90 : (fx == -1 ? 270 : (fz == 1 ? 180 : 0)) }
    }

    static func build(_ w: inout StructWriter, _ s: AshSite, _ seed: UInt64) {
        var rng = SRng(seed | 1)
        let k = AshKit()
        let f = Frame(s)
        let y0 = ground
        func put(_ u: Int, _ y: Int, _ v: Int, _ b: BlockID) { w.set(f.x(u, v), y, f.z(u, v), b) }
        func box(_ u0: Int, _ y0: Int, _ v0: Int, _ u1: Int, _ y1: Int, _ v1: Int, _ b: BlockID) {
            let xa = f.x(u0, v0), xb = f.x(u1, v1), za = f.z(u0, v0), zb = f.z(u1, v1)
            w.fill(min(xa, xb), y0, min(za, zb), max(xa, xb), y1, max(za, zb), b)
        }
        func unit(_ name: String, _ u: Float, _ v: Float, heading: Int? = nil, y: Int = y0 + 1) {
            let x = Float(s.x) + u * Float(-f.fz) + v * Float(f.fx) + 0.5, z = Float(s.z) + u * Float(f.fx) + v * Float(f.fz) + 0.5
            let hd = ((heading ?? 0) + f.heading) % 360
            w.mob(name + "^\(hd)", V3(x, Float(y), z))
        }
        func soldier(_ rank: String, _ u: Float, _ v: Float, y: Int = y0 + 1) { unit("soldier_\(rank)@ash", u, v, y: y) }
        // A walled building: walls of `wall`, flat roof, doorway in the front (v1) wall, slit windows.
        func building(_ u0: Int, _ v0: Int, _ u1: Int, _ v1: Int, h: Int, wall: BlockID, roof: BlockID, door: Int = 0) {
            box(u0, y0 + 1, v0, u1, y0 + h, v1, wall)
            box(u0 + 1, y0 + 1, v0 + 1, u1 - 1, y0 + h - 1, v1 - 1, AIR)
            box(u0, y0 + h, v0, u1, y0 + h, v1, roof)
            box(u0 + 1, y0, v0 + 1, u1 - 1, y0, v1 - 1, k.floor)
            let mid = (u0 + u1) / 2 + door
            box(mid - 1, y0 + 1, v1, mid + 1, y0 + 3, v1, AIR)
            put(mid - 2, y0 + 3, v1 + 1, k.lamp); put(mid + 2, y0 + 3, v1 + 1, k.lamp)
            for u in stride(from: u0 + 3, to: u1 - 1, by: 4) where abs(u - mid) > 2 {
                put(u, y0 + 3, v0, k.bars); put(u, y0 + 3, v1, k.bars)
            }
            for v in stride(from: v0 + 3, to: v1 - 1, by: 4) { put(u0, y0 + 3, v, k.bars); put(u1, y0 + 3, v, k.bars) }
            put((u0 + u1) / 2, y0 + h - 1, (v0 + v1) / 2, k.lamp)
        }
        // A roofed shed open at the front, for parked vehicles.
        func shed(_ u0: Int, _ v0: Int, _ u1: Int, _ v1: Int, h: Int) {
            box(u0, y0 + 1, v0, u1, y0 + h - 1, v0, k.plating)
            for u in stride(from: u0, through: u1, by: 6) { box(u, y0 + 1, v1, u, y0 + h - 1, v1, k.plating) }
            box(u0, y0 + 1, v0, u0, y0 + h - 1, v1, k.plating); box(u1, y0 + 1, v0, u1, y0 + h - 1, v1, k.plating)
            box(u0, y0 + h, v0, u1, y0 + h, v1, k.plating)
            for u in stride(from: u0 + 3, to: u1, by: 6) { put(u, y0 + h - 1, (v0 + v1) / 2, k.lamp) }
        }
        func sandbagRing(_ u: Int, _ v: Int, _ r: Int, open: Bool = true) {
            for du in -r...r { for dv in -r...r where max(abs(du), abs(dv)) == r {
                if open && dv == r && abs(du) <= 1 { continue }
                box(u + du, y0 + 1, v + dv, u + du, y0 + (abs(du) == r || abs(dv) == r ? 2 : 1), v + dv, k.bags)
            } }
        }
        // Does cloth facing along u (or v) face along world x?
        func normalX(_ alongU: Bool) -> Bool { alongU ? f.fz != 0 : f.fx != 0 }
        // A long banner hanging down a wall face from `top` (the wall's face along v, or along u with `alongU`).
        func banner(_ u: Int, _ v: Int, top: Int, len: Int = 4, alongU: Bool = false) {
            AshWar.banner(&w, x: f.x(u, v), z: f.z(u, v), top: top, len: len, normalX: normalX(alongU))
        }
        // The 3x3 standard on a wall face, centred on (u, v), its top row at `top`.
        func standard(_ u: Int, _ v: Int, top: Int, alongU: Bool = false) {
            AshWar.standard(&w, x: f.x(u, v), z: f.z(u, v), top: top, normalX: normalX(alongU))
        }
        // A flag: a pole flying the 3x3 standard and a lamp on top.
        func flag(_ u: Int, _ v: Int, h: Int) {
            box(u, y0 + 1, v, u, y0 + h, v, k.chain == AIR ? k.bars : k.chain)
            standard(u + 2, v, top: y0 + h)
            put(u, y0 + h + 1, v, k.lamp)
        }
        func tank(_ u0: Int, _ v0: Int, _ r: Int, h: Int) {
            // A fuel tank: black plated cylinder with a red band and the ember mark.
            for du in -r...r { for dv in -r...r where du * du + dv * dv <= r * r {
                let edge = du * du + dv * dv > (r - 1) * (r - 1)
                for y in (y0 + 1)...(y0 + h) {
                    if edge { put(u0 + du, y, v0 + dv, y == y0 + 3 ? k.redWool : k.plating) }
                    else if y == y0 + h { put(u0 + du, y, v0 + dv, k.plating) }
                }
            } }
            put(u0, y0 + 5, v0 + r, k.mark)
            put(u0, y0 + h + 1, v0, k.lamp)
        }
        func drums(_ u0: Int, _ v0: Int, _ n: Int, _ m: Int) {
            for a in 0..<n { for b in 0..<m where rng.int(5) != 0 { put(u0 + a, y0 + 1, v0 + b, k.drum) } }
        }
        func crates(_ u0: Int, _ v0: Int, _ n: Int, _ m: Int) {
            for a in 0..<n { for b in 0..<m {
                let h = 1 + rng.int(3)
                box(u0 + a, y0 + 1, v0 + b, u0 + a, y0 + h, v0 + b, k.crate)
            } }
        }
        func chest(_ u: Int, _ v: Int, _ loot: String, y: Int = y0 + 1) {
            w.chest(f.x(u, v), y, f.z(u, v), loot: loot, seed: rng.next(), facing: 0)
        }
        func lampPost(_ u: Int, _ v: Int) { box(u, y0 + 1, v, u, y0 + 3, v, k.plating); put(u, y0 + 4, v, k.lamp) }

        // Pad: levelled, trampled earth (P326: it was black stone) over dirt, open air above.
        let r = s.r
        w.fill(s.x - r, y0 + 1, s.z - r, s.x + r, y0 + 28, s.z + r, AIR)
        w.fill(s.x - r, y0 - 4, s.z - r, s.x + r, y0 - 4, s.z + r, EMBERSLATE)
        w.fill(s.x - r, y0 - 3, s.z - r, s.x + r, y0 - 1, s.z + r, DIRT)
        for dz in -r...r { for dx in -r...r {
            let x = s.x + dx, z = s.z + dz
            guard w.inside(x, y0, z) else { continue }
            w.set(x, y0, z, AshWar.isRoad(x, z) ? k.floor : AshWar.padBlock(x, z))
        } }

        switch s.kind {
        case "town": buildTown(&w, s, f, &rng)
        case "airfield": buildAirfield(&w, s, f, &rng)
        case "hq":
            // Perimeter wall with crenels and lamps, four gates on the roads, corner towers.
            let a = 42
            for i in -a...a {
                for (u, v) in [(i, -a), (i, a), (-a, i), (a, i)] {
                    if abs(i) <= 4 { continue }                                     // gates
                    box(u, y0 + 1, v, u, y0 + 6, v, k.concrete)
                    if i % 2 == 0 { put(u, y0 + 7, v, k.concrete) }
                    if i % 8 == 0 { put(u, y0 + 7, v, k.lamp) }
                }
            }
            for (u, v) in [(-a, -a), (a, -a), (-a, a), (a, a)] {
                box(u - 2, y0 + 1, v - 2, u + 2, y0 + 12, v + 2, k.concrete)
                box(u - 1, y0 + 2, v - 1, u + 1, y0 + 12, v + 1, AIR)
                box(u - 2, y0 + 12, v - 2, u + 2, y0 + 12, v + 2, k.plating)
                for du in -2...2 { for dv in -2...2 where max(abs(du), abs(dv)) == 2 { put(u + du, y0 + 13, v + dv, k.bars) } }
                put(u, y0 + 13, v, k.lamp)
                soldier("marksman", Float(u), Float(v), y: y0 + 13)
            }
            for (u, v) in [(-6, -a), (6, -a), (-6, a), (6, a), (-a, -6), (-a, 6), (a, -6), (a, 6)] {
                box(u, y0 + 1, v, u, y0 + 8, v, k.plating); put(u, y0 + 9, v, k.lamp); put(u, y0 + 6, v, k.mark)
            }
            // The last war: long red banners down the outside of the wall, a lintel over each gate carrying the 3x3
            // standard, facing out.
            for i in stride(from: -36, through: 36, by: 12) where abs(i) > 8 {
                banner(i, a + 1, top: y0 + 6); banner(i, -a - 1, top: y0 + 6); banner(a + 1, i, top: y0 + 6, alongU: true); banner(-a - 1, i, top: y0 + 6, alongU: true)
            }
            box(-5, y0 + 7, a, 5, y0 + 10, a, k.concrete); box(-5, y0 + 7, -a, 5, y0 + 10, -a, k.concrete)
            box(a, y0 + 7, -5, a, y0 + 10, 5, k.concrete); box(-a, y0 + 7, -5, -a, y0 + 10, 5, k.concrete)
            standard(0, a + 1, top: y0 + 10); standard(0, -a - 1, top: y0 + 10)
            standard(a + 1, 0, top: y0 + 10, alongU: true); standard(-a - 1, 0, top: y0 + 10, alongU: true)
            // The command bunker in the middle: thick ashcrete, sandbagged roof, the Marshal's map room.
            box(-13, y0 + 1, -10, 13, y0 + 8, 10, k.concrete)
            box(-11, y0 + 1, -8, 11, y0 + 6, 8, AIR)
            box(-11, y0, -8, 11, y0, 8, k.floor)
            box(-13, y0 + 9, -10, 13, y0 + 9, 10, k.bags)
            box(-2, y0 + 1, 10, 2, y0 + 4, 10, AIR)
            standard(0, 11, top: y0 + 8)
            banner(-6, 11, top: y0 + 7); banner(6, 11, top: y0 + 7)
            for (u, v) in [(-8, -5), (8, -5), (-8, 5), (8, 5), (0, -6)] { put(u, y0 + 6, v, k.lamp) }
            box(-3, y0 + 1, -2, 3, y0 + 1, 2, k.console)
            // P314: (a row of crafting tables stood on the map console here as its "map table"; gone)
            box(-11, y0 + 1, -8, -9, y0 + 3, -8, k.console); box(9, y0 + 1, -8, 11, y0 + 3, -8, k.console)
            chest(-10, -6, "ash_command"); chest(10, -6, "ash_command"); chest(-10, 6, "ash_armory"); chest(10, 6, "ash_armory")
            for (u, v) in [(-13, -10), (13, -10), (-13, 10), (13, 10)] { put(u, y0 + 10, v, k.lamp) }
            flag(-5, 16, h: 16); flag(5, 16, h: 16)
            unit("ash_marshal", 0, -4, heading: 180)
            soldier("officer", -6, 2); soldier("officer", 6, 2); soldier("ironclad", -4, 8); soldier("ironclad", 4, 8)
            // The Marshal's Guard (the Deep expansion: an army harder than any surface garrison): a heavy company drawn
            // up north of the bunker, two tanks holding the north gate road, troopers at the gates.
            for u in stride(from: -14, through: 14, by: 4) { soldier("ironclad", Float(u), -16) }
            unit("ash_tank", -6, -32, heading: 0); unit("ash_tank", 6, -32, heading: 0)
            for (u, v) in [(-3, -38), (3, -38), (-38, 3), (38, -3)] { soldier("trooper", Float(u), Float(v)) }
            // Barracks (north-west, north-east), motor yard (south-east), gun pits and fuel (south-west).
            building(-36, -34, -12, -22, h: 6, wall: k.plating, roof: k.concrete)
            building(12, -34, 36, -22, h: 6, wall: k.plating, roof: k.concrete)
            chest(-34, -32, "ash_supply"); chest(34, -32, "ash_supply")
            for (u, v) in [(-30, -26), (-18, -26), (18, -26), (30, -26), (-24, -18), (24, -18)] { soldier(rng.chance(0.5) ? "trooper" : "recruit", Float(u), Float(v)) }
            shed(12, 14, 38, 24, h: 6)
            unit("ash_tank", 16, 19, heading: 180); unit("ash_tank", 22, 19, heading: 180); unit("ash_tank", 28, 19, heading: 180)
            unit("ash_halftrack", 34, 19, heading: 180)
            unit("ash_tank", 24, 31, heading: 0); unit("ash_halftrack", 32, 31, heading: 0)
            soldier("trooper", 18, 28); soldier("recruit", 30, 28)
            for (u, v) in [(-32, 18), (-18, 18)] {
                sandbagRing(u, v, 3)
                unit("ash_artillery", Float(u), Float(v), heading: 180)
                soldier("recruit", Float(u + 2), Float(v - 2))
            }
            drums(-36, 28, 5, 4); drums(-28, 30, 4, 3)
            unit("ash_truck:fuel", -16, 32, heading: 90)
            crates(-12, 28, 3, 2)
            for (u, v) in [(-20, -12), (20, -12), (-20, 12), (20, 12), (0, -30), (0, 30), (-30, 0), (30, 0)] { lampPost(u, v) }
            for (u, v) in [(-3, -40), (3, 40), (-40, 3), (40, -3)] { soldier("trooper", Float(u), Float(v)) }
        case "staging":
            // A tank column on the road shoulder, ready to roll: six tanks nose to tail, two trucks, crates.
            for i in 0..<6 { unit("ash_tank", -8, Float(-24 + i * 9), heading: 0) }
            unit("ash_truck", 6, -20, heading: 0); unit("ash_truck", 6, 6, heading: 0)
            crates(4, -4, 2, 3); crates(4, 14, 2, 2)
            for v in stride(from: -26, through: 26, by: 13) { lampPost(-14, v) }
            soldier("officer", 2, 0); soldier("trooper", 2, 10); soldier("recruit", 2, -12)
        case "motorpool":
            // Fenced lot: two vehicle sheds, a repair gantry, drums; tanks and half-tracks lined up.
            for i in -30...30 {
                for (u, v) in [(i, -30), (i, 30), (-30, i), (30, i)] where !(v == 30 && abs(i) <= 5) {
                    put(u, y0 + 1, v, k.concrete); put(u, y0 + 2, v, k.bars); put(u, y0 + 3, v, k.bars)
                    if i % 10 == 0 { put(u, y0 + 4, v, k.lamp) }
                }
            }
            shed(-26, -26, 2, -14, h: 6); shed(6, -26, 26, -14, h: 6)
            for (i, u) in [-22, -15, -8].enumerated() { unit(i == 2 ? "ash_halftrack" : "ash_tank", Float(u), -20, heading: 180) }
            for u in [10, 17, 23] { unit("ash_tank", Float(u), -20, heading: 180) }
            unit("ash_halftrack", -10, 8, heading: 0); unit("ash_truck", 4, 8, heading: 0); unit("ash_truck", 12, 8, heading: 0)
            box(-24, y0 + 1, 4, -24, y0 + 8, 4, k.plating); box(-16, y0 + 1, 4, -16, y0 + 8, 4, k.plating)
            box(-24, y0 + 8, 4, -16, y0 + 8, 4, k.plating); box(-20, y0 + 5, 4, -20, y0 + 7, 4, k.chain)
            drums(16, 16, 6, 3); crates(-26, 18, 4, 3)
            chest(-6, 22, "ash_supply")
            soldier("trooper", 0, -6); soldier("recruit", -18, 12); soldier("recruit", 20, 2); soldier("marksman", 0, 26); soldier("officer", -4, 14)
        case "fueldepot":
            // Four big fuel tanks, a pump house, drum stacks, tanker trucks; a tank on guard.
            for (u, v) in [(-14, -14), (14, -14), (-14, 6), (14, 6)] { tank(u, v, 6, h: 8) }
            building(-4, -6, 4, 2, h: 5, wall: k.concrete, roof: k.plating)
            drums(-24, 18, 8, 3); drums(12, 18, 8, 3)
            for u in [-6, 0, 6] { unit("ash_truck:fuel", Float(u), 18, heading: 0) }
            unit("ash_tank", 0, 24, heading: 0)
            sandbagRing(-22, -24, 2); sandbagRing(22, -24, 2)
            soldier("trooper", -22, -24); soldier("trooper", 22, -24); soldier("recruit", 0, 10); soldier("marksman", -10, 22)
            chest(0, -4, "ash_fuel")
            for (u, v) in [(-26, -26), (26, -26), (-26, 26), (26, 26)] { lampPost(u, v) }
        case "supply":
            // Two warehouses, crate yards, trucks at the loading bay.
            building(-22, -20, -2, -8, h: 6, wall: k.plating, roof: k.concrete)
            building(2, -20, 22, -8, h: 6, wall: k.plating, roof: k.concrete)
            chest(-20, -18, "ash_supply"); chest(-4, -18, "ash_armory"); chest(4, -18, "ash_supply"); chest(20, -18, "ash_supply")
            crates(-20, -16, 4, 3); crates(10, -16, 5, 3)
            crates(-22, 4, 6, 4); crates(14, 4, 6, 4)
            unit("ash_truck", -8, 4, heading: 0); unit("ash_truck", 0, 4, heading: 0); unit("ash_truck", 8, 4, heading: 0)
            unit("ash_halftrack", 0, 16, heading: 0)
            soldier("trooper", -12, 0); soldier("recruit", 12, 0); soldier("recruit", -18, 14); soldier("officer", 4, -4); soldier("marksman", 18, 16)
            for (u, v) in [(-24, -24), (24, -24), (-24, 22), (24, 22)] { lampPost(u, v) }
        case "battery":
            // Four field guns in sandbag pits facing out, an ammunition dugout behind them.
            for (i, u) in [-15, -5, 5, 15].enumerated() {
                sandbagRing(u, 6, 3)
                unit("ash_artillery", Float(u), 6, heading: 0)
                soldier(i % 2 == 0 ? "trooper" : "recruit", Float(u + 2), 3)
            }
            building(-6, -16, 6, -8, h: 4, wall: k.concrete, roof: k.bags)
            chest(-4, -14, "ash_armory"); chest(4, -14, "ash_supply")
            soldier("officer", 0, -4); soldier("marksman", -18, -6)
            lampPost(-20, -10); lampPost(20, -10)
        case "outpost":
            // A pillbox with a firing slit, a sandbag trench ring and a few men; sometimes a half-track.
            box(-3, y0 + 1, -3, 3, y0 + 4, 3, k.concrete)
            box(-2, y0 + 1, -2, 2, y0 + 3, 2, AIR)
            box(-2, y0 + 3, 3, 2, y0 + 3, 3, AIR)
            put(0, y0 + 1, -3, AIR); put(0, y0 + 2, -3, AIR)
            box(-3, y0 + 5, -3, 3, y0 + 5, 3, k.bags); put(0, y0 + 6, 0, k.lamp); put(0, y0 + 3, -4, k.mark)
            chest(-2, -2, "ash_supply")
            sandbagRing(0, 0, 9)
            soldier("marksman", 0, 1); soldier("trooper", -6, 5); soldier("recruit", 6, 5); soldier("trooper", 0, -7)
            if rng.chance(0.5) { unit("ash_halftrack", 12, 0, heading: 0) }
            lampPost(-12, -12); lampPost(12, 12)
        case "bunker":
            // A line MG bunker straddling the trench: thick concrete, a firing slit facing out, the door at the back, a
            // sandbagged roof, sandbag wings; an Ashsaw crew inside and a banner on the back wall.
            box(-4, y0 + 1, -3, 4, y0 + 4, 3, k.concrete)
            box(-3, y0 + 1, -2, 3, y0 + 3, 2, AIR)
            box(-3, y0, -2, 3, y0, 2, k.floor)
            box(-2, y0 + 2, 3, 2, y0 + 2, 3, AIR)
            box(0, y0 + 1, -3, 0, y0 + 2, -3, AIR)
            box(-4, y0 + 5, -3, 4, y0 + 5, 3, k.bags)
            put(-3, y0 + 3, -2, k.lamp)
            box(-6, y0 + 1, 1, -5, y0 + 2, 3, k.bags); box(5, y0 + 1, 1, 6, y0 + 2, 3, k.bags)
            banner(2, -4, top: y0 + 4, len: 3); banner(-2, -4, top: y0 + 4, len: 3)
            chest(3, -2, "ash_supply")
            // The Last Line's eight sit inside the citadel's battle (its garrisons count against that budget,
            // AshVaultGapTests' biggest battle): the MG crew alone there.
            soldier("ironclad", 0, 1)
            if s.x * s.x + s.z * s.z > 200 * 200 {
                soldier("recruit", -2, 0)
                if rng.chance(0.5) { soldier("trooper", 2, -1) }
            }
        case "checkpoint", "lastgate":
            // A road through a line: a red-and-white barrier, a guard hut, an MG nest, a flag; the Last Line's gates
            // also hold a tank dug in behind an earth berm.
            let last = s.kind == "lastgate"
            // (the boom is raised high: the road stays open underneath it, tanks and the Behemoth included)
            box(-4, y0 + 1, 4, -4, y0 + 5, 4, k.plating); box(4, y0 + 1, 4, 4, y0 + 5, 4, k.plating)
            for u in -3...3 { put(u, y0 + 5, 4, u % 2 == 0 ? k.redWool : k.whiteWool) }
            building(last ? -7 : -9, -4, last ? -5 : -6, 2, h: 4, wall: k.concrete, roof: k.plating)
            sandbagRing(last ? 5 : 6, 3, 1)
            if !last { soldier("ironclad", 6, 3) }                              // (the Last Line's gates: the tank alone, inside the citadel battle's budget)
            if !last { soldier("officer", -2, 1); soldier("trooper", 2, 2); soldier("recruit", -3, 6) }
            if last {
                // beside the road (it stays open), its gun over the berm
                box(3, y0 + 1, -1, 9, y0 + 2, -1, k.black)                        // the berm
                box(3, y0 + 1, -2, 3, y0 + 1, -6, k.black); box(9, y0 + 1, -2, 9, y0 + 1, -6, k.black)
                unit("ash_tank", 6, -4, heading: 0)
            } else {
                flag(6, -7, h: 9)
                if rng.chance(0.6) { unit("ash_halftrack", -5, -6, heading: 0) }
            }
            lampPost(-6, 6); lampPost(6, 6)
        case "flak":
            // P326 (c): a heavy flak battery: six guns in sandbagged pits on a ring round the command post and its range
            // finder, two searchlights, ammunition bunkers, the crews' hut, the battery's flag.
            for i in 0..<6 {
                let a = Float(i) * Float.pi / 3 + 0.3
                let u = Int((sinf(a) * 14).rounded()), v = Int((-cosf(a) * 14).rounded())
                sandbagRing(u, v, 3)
                unit("ash_artillery", Float(u), Float(v), heading: Int(a * 180 / .pi))
                soldier(i % 2 == 0 ? "trooper" : "recruit", Float(u) + 1.5, Float(v) + 1.5)
            }
            sandbagRing(0, 0, 4)
            box(0, y0 + 1, 0, 0, y0 + 2, 0, k.plating)
            box(-3, y0 + 3, 0, 3, y0 + 3, 0, k.plating)
            put(-3, y0 + 4, 0, k.bars); put(3, y0 + 4, 0, k.bars)
            soldier("officer", 1, -2); soldier("marksman", -2, 1)
            for (u, v) in [(-20, -20), (20, 20)] {
                box(u - 1, y0 + 1, v - 1, u + 1, y0 + 1, v + 1, k.plating)
                put(u, y0 + 2, v, k.plating); put(u, y0 + 3, v, k.lamp)
                put(u + 1, y0 + 3, v, k.bars); put(u - 1, y0 + 3, v, k.bars)
            }
            building(-24, 8, -18, 16, h: 4, wall: k.concrete, roof: k.bags)
            building(18, -16, 24, -8, h: 4, wall: k.concrete, roof: k.bags)
            chest(-22, 10, "ash_armory"); chest(22, -12, "ash_supply")
            building(-8, -24, 8, -18, h: 5, wall: k.plating, roof: k.concrete)
            chest(-6, -22, "ash_supply")
            drums(10, 16, 3, 2); crates(-14, 18, 2, 2)
            flag(-18, -16, h: 10)
            lampPost(-22, 22); lampPost(22, -22)
        case "heavywater":
            // P326 (c): a heavy-water plant, modelled on the period's hydro-electric ones: a dam at the back, three
            // penstocks stepping down to the hall, the hall's two long rows of electrolysis cells wired to a bus bar,
            // a transformer yard, a drum store, a wire fence with guard towers and a gate.
            let glass = Blocks.id("glass"), iron = Blocks.id("iron_block"), copper = Blocks.id("copper_block")
            let wire = Blocks.has("ash_wire") ? Blocks.id("ash_wire") : k.bars
            box(-26, y0 + 1, -28, 26, y0 + 22, -24, k.concrete)
            box(-26, y0 + 23, -28, 26, y0 + 23, -28, k.concrete); box(-26, y0 + 23, -24, 26, y0 + 23, -24, k.concrete)
            for u in stride(from: -24, through: 24, by: 8) { put(u, y0 + 24, -24, k.lamp) }
            for pu in [-13, -1, 11] {
                for t in 0...16 {
                    let v = -23 + t, y = y0 + 20 - t
                    box(pu, y, v, pu + 1, y + 1, v, iron)
                    if t % 5 == 2 { box(pu, y0 + 1, v, pu + 1, y - 1, v, k.concrete) }
                }
            }
            building(-24, -6, 24, 14, h: 11, wall: k.concrete, roof: k.plating)
            for u in stride(from: -21, through: 21, by: 4) where abs(u) > 2 {
                box(u, y0 + 5, 14, u, y0 + 9, 14, glass); box(u, y0 + 5, -6, u, y0 + 9, -6, glass)
            }
            for v in stride(from: -3, through: 11, by: 4) { box(-24, y0 + 5, v, -24, y0 + 9, v, glass); box(24, y0 + 5, v, 24, y0 + 9, v, glass) }
            for v in [0, 7] {
                for u in stride(from: -20, through: 20, by: 2) {
                    put(u, y0 + 1, v, iron); put(u, y0 + 2, v, copper)
                    put(u, y0 + 3, v, k.chain == AIR ? k.bars : k.chain)
                }
                box(-20, y0 + 4, v, 20, y0 + 4, v, copper)
            }
            box(-23, y0 + 1, -5, -18, y0 + 4, -5, k.plating)                   // the office at the hall's end
            box(-18, y0 + 1, -5, -18, y0 + 4, 2, k.plating)
            put(-18, y0 + 1, -2, AIR); put(-18, y0 + 2, -2, AIR)
            chest(-22, -4, "ash_command")
            for (u, v) in [(-24, 20), (-20, 20), (-16, 20)] {
                box(u, y0 + 1, v, u + 1, y0 + 2, v + 1, iron)
                put(u - 1, y0 + 1, v, k.bars); put(u + 2, y0 + 1, v + 1, k.bars)
                put(u, y0 + 3, v, copper)
            }
            for u in -27...(-13) { put(u, y0 + 1, 17, k.bars); put(u, y0 + 1, 24, k.bars) }
            drums(12, 18, 6, 3); crates(18, 22, 3, 2)
            chest(20, 18, "ash_supply")
            unit("ash_truck", 8, 23, heading: 0)
            // The fence (wire on posts) with a gate on the road in, and a tower at each corner.
            for i in -29...29 {
                for (u, v) in [(i, -29), (i, 29), (-29, i), (29, i)] where !(v == 29 && abs(i) <= 3) {
                    put(u, y0 + 1, v, i % 4 == 0 ? k.plating : wire)
                    if i % 4 == 0 { put(u, y0 + 2, v, k.plating) }
                }
            }
            box(-4, y0 + 1, 29, -4, y0 + 5, 29, k.plating); box(4, y0 + 1, 29, 4, y0 + 5, 29, k.plating)
            for u in -3...3 { put(u, y0 + 5, 29, u % 2 == 0 ? k.redWool : k.whiteWool) }
            for (u, v) in [(-27, -21), (27, -21), (-27, 27), (27, 27)] {
                for (du, dv) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] { box(u + du, y0 + 1, v + dv, u + du, y0 + 7, v + dv, k.plating) }
                box(u - 1, y0 + 8, v - 1, u + 1, y0 + 8, v + 1, k.plating)
                for du in -1...1 { for dv in -1...1 where du != 0 || dv != 0 { put(u + du, y0 + 9, v + dv, k.bars) } }
                put(u, y0 + 10, v, k.lamp)
                soldier("marksman", Float(u), Float(v), y: y0 + 9)
            }
            soldier("officer", -20, -2); soldier("trooper", -6, 18); soldier("trooper", 6, 18); soldier("recruit", 0, 4)
            soldier("trooper", -6, 27); soldier("trooper", 6, 27)
            unit("ash_tank", -8, 25, heading: 0)
            lampPost(-10, 18); lampPost(10, 18)
        case "prisoncamp":
            // P347 (PrisonCamp.swift): the Ashguard's prison camp. A double wire fence on stakes with one gate, four
            // watchtowers, the gatehouse and the guards' block, a bare roll-call ground, four long huts of raw planks
            // with two tiers of bare bunks, the prisoners in them.
            let wire = Blocks.has("ash_wire") ? Blocks.id("ash_wire") : k.bars
            func wood(_ n: String) -> BlockID { Blocks.has(n) ? Blocks.id(n) : k.crate }
            let stake = wood("spruce_fence"), log = wood("spruce_log"), plank = wood("spruce_planks"), raw = wood("oak_planks")
            let dark = wood("dark_oak_planks"), slab = Blocks.has("spruce_slab") ? Blocks.id("spruce_slab") : plank
            // The fences: outer at 33, inner at 30, three blocks apart; the gate in the front (v = +) of both.
            for (e, gap) in [(33, 3), (30, 3)] {
                for i in -e...e {
                    for (u, v) in [(i, -e), (i, e), (-e, i), (e, i)] where !(v == e && abs(i) <= gap) {
                        let post = i % 3 == 0 || abs(i) == e
                        box(u, y0 + 1, v, u, y0 + 3, v, post ? stake : wire)
                        if post { put(u, y0 + 4, v, stake) } else { put(u, y0 + 4, v, AIR) }
                    }
                }
            }
            // The gate: posts and a beam over the gap, the two leaves of wire standing open.
            for e in [33, 30] {
                box(-4, y0 + 1, e, -4, y0 + 5, e, log); box(4, y0 + 1, e, 4, y0 + 5, e, log)
                box(-4, y0 + 6, e, 4, y0 + 6, e, log)
                put(-4, y0 + 5, e - 1, k.lamp); put(4, y0 + 5, e - 1, k.lamp)
            }
            box(-5, y0 + 1, 31, -5, y0 + 3, 32, wire); box(5, y0 + 1, 31, 5, y0 + 3, 32, wire)
            // Watchtowers at the inner corners: four legs, a railed platform, a roof, a lamp and a sentry.
            for (u, v) in [(-27, -27), (27, -27), (-27, 27), (27, 27)] {
                for (du, dv) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] { box(u + du, y0 + 1, v + dv, u + du, y0 + 11, v + dv, log) }
                box(u - 2, y0 + 8, v - 2, u + 2, y0 + 8, v + 2, plank)
                for du in -2...2 { for dv in -2...2 where max(abs(du), abs(dv)) == 2 { put(u + du, y0 + 9, v + dv, stake) } }
                box(u - 2, y0 + 12, v - 2, u + 2, y0 + 12, v + 2, dark)
                put(u, y0 + 11, v, k.lamp)
                for y in (y0 + 1)...(y0 + 7) { put(u + 1, y, v, Blocks.has("ladder") ? Blocks.id("ladder") : AIR) }
                put(u + 1, y0 + 8, v, AIR)
                soldier("marksman", Float(u), Float(v), y: y0 + 9)
            }
            // The prisoners' huts at the back: long, low, raw planks, a dark roof, a door to the ground and slits for
            // light; inside, two tiers of bare bunks down both walls.
            var n = 0
            for (u0, u1) in [(-26, -19), (-14, -7), (7, 14), (19, 26)] {
                let v0 = -24, v1 = -6
                box(u0, y0 + 1, v0, u1, y0 + 4, v1, raw)
                box(u0 + 1, y0 + 1, v0 + 1, u1 - 1, y0 + 4, v1 - 1, AIR)
                box(u0, y0 + 5, v0, u1, y0 + 5, v1, dark)
                box(u0 + 1, y0 + 6, v0, u1 - 1, y0 + 6, v1, dark)
                for u in [u0, u1] { for v in stride(from: v0 + 1, through: v1, by: 4) { box(u, y0 + 1, v, u, y0 + 4, v, log) } }
                for v in stride(from: v0 + 3, to: v1 - 1, by: 4) { put(u0, y0 + 3, v, AIR); put(u1, y0 + 3, v, AIR) }
                let mid = (u0 + u1) / 2
                box(mid, y0 + 1, v1, mid, y0 + 2, v1, AIR)
                put(mid + 1, y0 + 4, v1 + 1, k.lamp)
                for v in (v0 + 1)...(v1 - 2) {
                    for u in [u0 + 1, u1 - 1] { put(u, y0 + 1, v, slab); put(u, y0 + 3, v, plank) }
                    if (v - v0) % 3 == 0 { put(u0 + 1, y0 + 2, v, stake); put(u1 - 1, y0 + 2, v, stake) }
                }
                // The prisoners: some sitting on the bunks' edge, some standing in the aisle.
                for (j, v) in stride(from: v0 + 3, to: v1 - 2, by: 3).enumerated() {
                    let left = (j + n) % 2 == 0
                    let su = Float(left ? u0 + 2 : u1 - 2) + (left ? -0.3 : 0.3)
                    unit("soldier_crew:prisoner_sit", su, Float(v), heading: left ? 90 : 270)
                    if j % 2 == 1 { unit("soldier_crew:prisoner", Float(mid), Float(v) + 1, heading: (j * 70) % 360) }
                }
                n += 1
            }
            // A few standing out on the roll-call ground.
            for (u, v) in [(-4, -2), (-2, -2), (0, -2), (2, -2), (4, -2)] { unit("soldier_crew:prisoner", Float(u), Float(v), heading: 180) }
            // The gatehouse, the guards' block (the commandant's office and papers) and the yard's guards.
            building(8, 18, 14, 26, h: 4, wall: k.concrete, roof: k.plating)
            building(-26, 8, -12, 22, h: 5, wall: k.concrete, roof: k.plating)
            chest(-24, 10, "ash_command"); chest(-14, 10, "ash_armory")
            soldier("officer", -20, 14); soldier("trooper", -16, 18)
            soldier("trooper", 10, 22); soldier("recruit", -6, 27); soldier("recruit", 6, 27)
            soldier("trooper", -10, 2); soldier("trooper", 10, 2); soldier("marksman", 0, 10)
            for (u, v) in [(-16, 0), (16, 0), (-8, 14), (8, 10), (-7, 24)] { lampPost(u, v) }
            unit("ash_truck", 20, 26, heading: 0)
        default:
            // Patrol camp: a black canvas tent, a fire, crates, three men; now and then a tank or half-track.
            for i in 0...3 {
                box(-4 + i, y0 + 1 + i, -3, -4 + i, y0 + 1 + i, 3, k.blackWool)
                box(4 - i, y0 + 1 + i, -3, 4 - i, y0 + 1 + i, 3, k.blackWool)
            }
            box(0, y0 + 5, -3, 0, y0 + 5, 3, k.blackWool)
            put(0, y0 + 4, 3, k.mark)
            put(0, y0 + 1, 7, k.fire)
            crates(5, -5, 2, 2)
            chest(-2, -2, "ash_supply")
            soldier("trooper", -2, 6); soldier("recruit", 2, 8); soldier(rng.chance(0.3) ? "marksman" : "recruit", 3, 4)
            let roll = rng.int(8)
            if roll < 2 { unit("ash_tank", -8, 6, heading: 0) } else if roll < 4 { unit("ash_halftrack", -8, 6, heading: 0) }
            lampPost(6, 9)
        }
        // Every site's board at its front corner (the gap pass, DE8): what it is, in the Ashguard's words.
        let boards: [String: [String]] = ["hq": ["ASHGUARD CITADEL", "Command of the", "Ash Marshal", "Halt or be fired on"],
                                          "staging": ["FIRST ARMOURED", "Column ready", "to roll", ""],
                                          "motorpool": ["MOTOR POOL", "Fuel is rationed.", "Engines run cold.", ""],
                                          "fueldepot": ["FUEL DEPOT", "No flame within", "fifty paces", ""],
                                          "supply": ["SUPPLY DEPOT", "Shells out,", "nothing back", ""],
                                          "battery": ["GUN BATTERY", "Ranged on every", "road in", ""],
                                          "outpost": ["OUTPOST", "Report anything", "that moves", ""],
                                          "camp": ["PATROL CAMP", "Lamps out at", "the second bell", ""],
                                          "flak": ["FLAK BATTERY", "", "", ""],
                                          "heavywater": ["HEAVY WATER", "PLANT", "", ""]]
        if let lines = boards[s.kind] {
            AshWar.sign(&w, f.x(s.r - 1, s.r - 1), y0 + 1, f.z(s.r - 1, s.r - 1), facing: (f.fx, f.fz), lines)
        }
    }
}
