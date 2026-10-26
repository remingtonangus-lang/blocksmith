import Foundation
import simd

// P346 (Oct 16 19:50-19:52, the Ash Vault's set pieces: "the plane crash is not obvious enough", "make it so you could
// repair the plane, but you have to find rare parts", the dead "shouldn't look so futuristic... like 1940s soldiers",
// "they're kind of hovering and they're all holding guns", the knocked-out tanks "don't look like real tanks", "no man's
// land should be a biome", "why does the road end like that?"):
//   wrecks     the scenes' bomber, fighter and tanks are models now (AshWrecks), not heaps of blocks: a four-engined
//              bomber belly-landed and broken behind the wings (one wing torn off, the tail section thrown askew, bent
//              propellers, torn skin over the ribs, soot), a single-engined fighter nosed into the ground with a wing
//              snapped off, and Sherman-like medium tanks (cast turret, short 75, glacis, bogies, sprockets, tracks), one
//              with its turret blown off beside it, burnt and rusting. Each stands on scorched ground; hidden blocks
//              inside the hulls make them solid.
//   repair     the bomber's wreck holds a chest with Aero Engine Spares (rare: a few Ashguard stores carry one too).
//              Using spares by the crashed fighter fits them; with three fitted it stands repaired, a fighter he can
//              fly (the plane's own flight model). Kept with the world (TownLaw.state.vaultObj), no text.
//   the fallen 1940s Allied infantry of their own model: olive drab tunic, khaki trousers, canvas leggings, webbing and
//              canteen, a round steel helmet (or it lies knocked off beside him), lying flat on their backs on the
//              ground, a rifle fallen beside them. Nothing in their hands, nothing futuristic.
//   no man's land  the belt outside the Ember Line is its own place (VaultGround.noMansLand): ragged edges reaching
//              out to ~600, its own name on the place line, browner, closer fog, belts of wire on stakes, tank traps,
//              shattered trees and rain-filled shell holes.
//   roads      the axis roads run out to the vault's edge where they used to stop at the Ember Line's checkpoint walls
//              (now a gap in the wall, AshLines), and a road meeting an old save's ground runs on as a track.

// MARK: The wrecks

enum AshWrecks {
    static var mobs: [Mob] = []
    private static var built: [Int64: [Mob]] = [:]
    static let reach: Float = 150
    static let needSpares = 3
    static let fighterName = "Salvaged Fighter"
    static var repaired = 0                     // (counter)

    // A wreck model's place: world position (block centre, on the ground), heading, kind (0 bomber, 1 fighter, 2 tank,
    // 3 tank with its turret blown off).
    struct Spot { let pos: V3; let yaw: Float; let kind: Int; let seed: Int }

    static func yaw(_ s: AshScene) -> Float {
        let (fx, fz) = [(0, -1), (1, 0), (0, 1), (-1, 0)][s.face]
        return atan2f(Float(fx), Float(fz))                 // nose / front toward -v
    }

    // The scene's wrecks, as the generator lays them (the same numbers AshFront.build uses for their hidden cores).
    static func spots(_ s: AshScene, _ g: VaultGround) -> [Spot] {
        let (fx, fz) = [(0, -1), (1, 0), (0, 1), (-1, 0)][s.face]
        func X(_ u: Int, _ v: Int) -> Int { s.x + u * (-fz) + v * fx }
        func Z(_ u: Int, _ v: Int) -> Int { s.z + u * fx + v * fz }
        func base(_ u0: Int, _ v0: Int, _ u1: Int, _ v1: Int) -> Int {
            var lo = Int.max
            for (u, v) in [(u0, v0), (u1, v0), (u0, v1), (u1, v1), ((u0 + u1) / 2, (v0 + v1) / 2)] { lo = min(lo, g.top(X(u, v), Z(u, v))) }
            return lo
        }
        func at(_ u: Int, _ v: Int, _ y: Int) -> V3 { V3(Float(X(u, v)) + 0.5, Float(y + 1), Float(Z(u, v)) + 0.5) }
        let y0 = yaw(s), sd = Int(hash3(s.x, 0x3EC, s.z, 0x5A7) & 0xFFFF)
        switch s.kind {
        case 0: return [Spot(pos: at(0, -2, base(-2, -11, 2, 4)), yaw: y0, kind: 0, seed: sd)]
        case 1: return [Spot(pos: at(0, 2, base(-1, -3, 1, 6)), yaw: y0, kind: 1, seed: sd)]
        case 2:
            let off = hash3(s.x, 0x7A2, s.z, 0x5A8) % 3
            return tankPlaces.enumerated().map { (i, t) in
                let side = t.2
                let y = side ? base(t.0 - 3, t.1 - 2, t.0 + 3, t.1 + 2) : base(t.0 - 2, t.1 - 3, t.0 + 2, t.1 + 3)
                return Spot(pos: at(t.0, t.1, y), yaw: y0 + (side ? .pi / 2 : 0), kind: i == Int(off) ? 3 : 2, seed: sd + i * 977)
            }
        default: return []
        }
    }
    // The tank troop: (u, v, side-on).
    static let tankPlaces: [(Int, Int, Bool)] = [(0, -8, false), (4, 3, true), (-3, 11, false)]

    static func key(_ s: AshScene) -> String { "plane:\(s.x),\(s.z)" }
    // P435 (Oct 24 15:49, at a knocked-out tank: "I should be able to drive it though, or at least repair it"): a tank
    // whose turret is still on takes Track Spares (Ashguard stores and command posts carry them); with two fitted it
    // stands repaired, his to drive (AshSeat, as a Cinder Tank he has taken: the same gun, speed and sprint), drawn as
    // itself, clean.
    static let needTrack = 2
    static func tankKey(_ s: AshScene, _ i: Int) -> String { "tank:\(s.x),\(s.z):\(i)" }
    static func tankFixed(_ s: AshScene, _ i: Int) -> Bool { (TownLaw.state.vaultObj?[tankKey(s, i)] ?? 0) >= needTrack }
    static var tanksRepaired = 0                    // (counter)
    static func spares(_ s: AshScene) -> Int { TownLaw.state.vaultObj?[key(s)] ?? 0 }

    // Once a second (AshFallen.refresh): the wrecks near the player as drawn models.
    static func refresh(_ g: Game, _ dg: DeepGen) {
        let p = g.player.pos
        var want = Set<Int64>()
        for s in AshFront.scenes(Int(p.x - reach), Int(p.z - reach), Int(p.x + reach), Int(p.z + reach), pad: 0, ground: dg.ground) where s.kind <= 2 {
            let k = StructureCache.key(s.x, s.z)
            if s.kind == 1 && spares(s) >= needSpares { continue }           // flown away
            want.insert(k)
            if built[k] != nil { continue }
            built[k] = spots(s, dg.ground).enumerated().filter { !(s.kind == 2 && tankFixed(s, $0.offset)) }.map { $0.element }.map { sp in
                let m = Mob(.ashBehemoth, at: sp.pos)
                m.wreck = Int8(sp.kind)
                m.yaw = sp.yaw
                m.variant = sp.seed
                m.health = 1
                m.onGround = true
                return m
            }
        }
        built = built.filter { want.contains($0.key) }
        mobs = built.values.flatMap { $0 }
    }
    static func clear() { if !mobs.isEmpty || !built.isEmpty { mobs = []; built = [:] } }

    // P464 (Oct 25 19:36-19:38, "the plane, when it gets repaired, needs to look just like it looked when it wasn't
    // repaired"): a Salvaged Fighter is drawn as the wreck's own fighter, whole and clean (fighterWholeParts: both
    // wings, its gear down, the propeller turning), at the hull's pose; its blocks fly and collide as before, unseen.
    // Broken up past a sixth of its blocks it shows its blocks again. Each ship step (ShipManager.update), on the main
    // thread; the mob writer draws skinMobs.
    static let skinScale: Float = 1.45                  // the model's 10-block fuselage over the 16-block hull
    private static var skins: [Int: Mob] = [:]
    private static var skinOrigin: [Int: V3] = [:]      // ship space of the model's origin (hull centre line, wheels)
    static var skinsOff = ProcessInfo.processInfo.environment["BS_FIGHTERBLOCKS"] != nil     // (looks work: the blocks)
    static var skinMobs: [Mob] = []
    static func syncSkins(_ w: World) {
        if w.ships.isEmpty && skins.isEmpty { if !skinMobs.isEmpty { skinMobs = [] }; return }
        var out: [Mob] = []
        for s in w.ships.list where s.name == fighterName && s.parent == nil {
            if skinOrigin[s.id] == nil, let h = s.helm {
                // The helm stands at (0, 2, -3) of salvagedFighter's plan; the model's origin is the plan's (0, 0, 0)
                // cell, centred.
                skinOrigin[s.id] = V3(Float(h.x) + 0.5, Float(h.y) - 2, Float(h.z) + 3.5)
            }
            guard let o = skinOrigin[s.id], !skinsOff, s.blockCount * 6 >= s.initialBlocks * 5 else { s.hidden = false; continue }
            s.hidden = true
            let m: Mob
            if let have = skins[s.id] { m = have } else {
                m = Mob(.ashBehemoth, at: s.pos)
                m.wreck = 5
                m.health = 1
                m.onGround = true
                m.scale = skinScale
                skins[s.id] = m
            }
            // The hull's turn as yaw, then roll, then pitch (the mob writer turns a part by Rz * Rx about its pivot,
            // the body by its yaw): the yaw that leaves the right wing level in the body's own frame.
            let r = s.dirToWorld(V3(1, 0, 0)), u = s.dirToWorld(V3(0, 1, 0)), b = s.dirToWorld(V3(0, 0, 1))
            let yaw = atan2f(-r.z, r.x)
            let cy = cosf(yaw), sy = sinf(yaw)
            let rx = r.x * cy - r.z * sy
            let uz = u.x * sy + u.z * cy, bz = b.x * sy + b.z * cy
            m.yaw = yaw
            m.boatRock = V2(atan2f(uz, bz), atan2f(r.y, rx))
            let c = V3(0, 4 * skinScale / 16, 0)                 // (the turn's centre: BoatLooks.rock's, scaled)
            m.pos = s.toWorld(o + c) - c
            m.walkPhase += w.ships.pilot === s || s.engines > 0 && simd_length(s.vel) > 1 ? 0.9 : 0       // the propeller
            out.append(m)
        }
        if skins.count > out.count {
            let live = Set(w.ships.list.map { $0.id })
            skins = skins.filter { live.contains($0.key) }
            skinOrigin = skinOrigin.filter { live.contains($0.key) }
        }
        skinMobs = out
    }
    // P464 (Oct 25 19:35, "I repaired a cinder tank, but the problem is the old tank that was broke and remained in its
    // place"): a scene's wrecks are built again (the repaired one left out), and the solid core hidden in that hull goes.
    static func rebuild(_ s: AshScene, _ g: Game, clearing sp: Spot?) {
        built[StructureCache.key(s.x, s.z)] = nil
        guard let sp = sp else { return }
        let bx = Int(floorf(sp.pos.x)), by = Int(floorf(sp.pos.y)), bz = Int(floorf(sp.pos.z))
        let fx = Int(roundf(-sinf(sp.yaw))), fz = Int(roundf(-cosf(sp.yaw)))
        for a in -1...1 where g.world.builtBlock(bx - a * fx, by, bz - a * fz) != AIR { g.world.setBlock(bx - a * fx, by, bz - a * fz, AIR) }
    }
}

extension Game {
    // Using Aero Engine Spares by a crashed fighter: fit them (up to the three it needs); the third flies it.
    func aeroSparesUse() -> Bool {
        guard Items.key(held.item) == "aero_spares" else { return false }
        guard dim.dim == .deep, DeepGen.inVault(player.pos.y), let dg = world.gen as? DeepGen else { sfx(.click, 0.4); return true }
        let p = player.pos
        guard let s = AshFront.scenes(Int(p.x) - 12, Int(p.z) - 12, Int(p.x) + 12, Int(p.z) + 12, pad: 0, ground: dg.ground)
                .first(where: { $0.kind == 1 && simd_length(V2(Float($0.x) + 0.5 - p.x, Float($0.z) + 0.5 - p.z)) < 10 }) else {
            sfx(.click, 0.4)
            return true
        }
        var have = AshWrecks.spares(s)
        guard have < AshWrecks.needSpares else { return true }
        let fit = min(AshWrecks.needSpares - have, held.count)
        if survival { inventory.main[inventory.selected].count -= fit; if inventory.main[inventory.selected].count <= 0 { inventory.main[inventory.selected] = .empty } }
        have += fit
        var m = TownLaw.state.vaultObj ?? [:]
        m[AshWrecks.key(s)] = have
        TownLaw.state.vaultObj = m
        guard let sp = AshWrecks.spots(s, dg.ground).first else { return true }
        sfx(.place(.metal), 1, at: sp.pos)
        if have >= AshWrecks.needSpares {
            // Patched up: the wreck is gone and the fighter stands on its wheels where it lay.
            let ship = world.ships.spawn(AshWrecks.salvagedFighter(), at: sp.pos + V3(0, 1.2, 0), yaw: sp.yaw, name: AshWrecks.fighterName, role: "capplane")
            // P464 (Oct 25 19:38, "the plane keeps getting thrusted into the air and then it breaks when it hits the
            // ground"): it was set down at the gouge where the wreck nosed in, so its wings and tail stood in the field
            // round it and the contacts threw it up. Its wheels now go down on the highest ground under it.
            AshWrecks.setDown(ship, world)
            ship.initialBlocks = ship.blockCount
            FlightModel.attach(ship)
            sfx(.engineStart, 1, at: sp.pos)
            AshWrecks.repaired += 1
            AshWrecks.refresh(self, dg)
        }
        return true
    }
}

extension Game {
    // Using Track Spares by a knocked-out tank (turret still on): fit them; the second puts it back on its tracks.
    func trackSparesUse() -> Bool {
        guard Items.key(held.item) == "track_spares" else { return false }
        guard dim.dim == .deep, DeepGen.inVault(player.pos.y), let dg = world.gen as? DeepGen else { sfx(.click, 0.4); return true }
        let p = player.pos
        var best: (AshScene, Int, AshWrecks.Spot)?
        var bd: Float = 6
        for s in AshFront.scenes(Int(p.x) - 30, Int(p.z) - 30, Int(p.x) + 30, Int(p.z) + 30, pad: 0, ground: dg.ground) where s.kind == 2 {
            for (i, sp) in AshWrecks.spots(s, dg.ground).enumerated() where sp.kind == 2 && !AshWrecks.tankFixed(s, i) {
                let d = simd_length(V2(sp.pos.x - p.x, sp.pos.z - p.z))
                if d < bd { bd = d; best = (s, i, sp) }
            }
        }
        guard let (s, i, sp) = best else { sfx(.click, 0.4); return true }
        let key = AshWrecks.tankKey(s, i)
        var m = TownLaw.state.vaultObj ?? [:]
        var have = m[key] ?? 0
        let fit = min(AshWrecks.needTrack - have, held.count)
        if survival { inventory.main[inventory.selected].count -= fit; if inventory.main[inventory.selected].count <= 0 { inventory.main[inventory.selected] = .empty } }
        have += fit
        m[key] = have
        TownLaw.state.vaultObj = m
        sfx(.place(.metal), 1, at: sp.pos)
        swing = 1
        guard have >= AshWrecks.needTrack else { return true }
        let t = Mob(.ashTank, at: sp.pos)
        t.wreck = 4
        t.variant = sp.seed
        t.yaw = sp.yaw
        t.ashSetup()
        t.soldierBrain.turret = sp.yaw
        t.owner = true
        t.aggro = false
        t.persistent = true
        t.health = t.spec.health
        mobs.mobs.append(t)
        sfx(.engineStart, 1, at: sp.pos)
        particles.smoke(at: sp.pos + V3(0, 2.2, 0))
        AshWrecks.tanksRepaired += 1
        AshWrecks.rebuild(s, self, clearing: sp)
        AshWrecks.refresh(self, dg)
        return true
    }
}

extension AshWrecks {
    // Sets a spawned craft's wheels down just clear of the highest ground under its footprint.
    static func setDown(_ s: Ship, _ w: World) {
        s.updateBounds()
        let y0 = Int(floorf(s.worldMin.y))
        var top = y0 - 4
        for z in Int(floorf(s.worldMin.z))...Int(floorf(s.worldMax.z)) { for x in Int(floorf(s.worldMin.x))...Int(floorf(s.worldMax.x)) {
            for y in stride(from: y0 + 6, through: max(top + 1, y0 - 4), by: -1) where w.solidAt(x, y, z) { top = max(top, y); break }
        } }
        VehicleWorks.settle(s, on: V3(s.pos.x, Float(top + 1) - 0.5, s.pos.z))     // (wheels 0.1 over it)
    }

    // The repaired fighter: a single-engined, low-winged fighter, flown from its cockpit (bow -Z), in the crashed
    // one's colours (P435): bare aluminium, an olive anti-glare panel ahead of the bubble canopy, and a dark cowl ring round
    // the propeller.
    static func salvagedFighter() -> Blueprint {
        let b = Blueprint()
        let skin = Blocks.has("fighter_skin") ? "fighter_skin" : "light_gray_concrete"
        let trim = Blocks.has("fighter_trim") ? "fighter_trim" : "green_terracotta"
        let wing = Blocks.has("fighter_wing") ? "fighter_wing" : "ship_wing"
        let glass = "glass"
        b.box(-1, 1, 1, 1, -6, 8, skin)                                    // belly
        b.box(-1, 1, 2, 3, -6, 1, skin)                                    // cowling and cockpit sides
        b.box(-1, 1, 3, 3, -6, -4, trim)                                   // the anti-glare panel on the cowling
        for z in -3...0 { for y in 2...3 { b.clear(0, y, z) } }
        for z in -3...0 { b.set(0, 4, z, glass); b.set(-1, 3, z, glass); b.set(1, 3, z, glass) }
        b.box(0, 0, 2, 2, 1, 8, skin)                                      // the spine to the tail
        b.set(0, 1, -5, "ship_engine"); b.set(0, 1, -4, "ship_engine")
        b.set(0, 1, -7, "ship_propeller[south]")
        b.set(0, 2, -7, skin)                                              // spinner
        b.set(-1, 1, -7, trim); b.set(1, 1, -7, trim)                      // the cowl ring
        for x in -7...7 where abs(x) > 1 { for z in -1...1 where !(abs(x) == 7 && z == 1) { b.set(x, 1, z, wing) } }
        for x in -3...3 where x != 0 { for z in 7...8 { b.set(x, 2, z, wing) } }
        b.box(0, 0, 3, 4, 7, 8, skin)                                      // fin
        b.set(-2, 0, -1, "ship_wheel"); b.set(2, 0, -1, "ship_wheel"); b.set(0, 0, 7, "ship_wheel")
        b.set(0, 2, -3, "ship_helm[south]")
        b.crew = [V3(0.5, 2, -1.5)]
        return b
    }
}

// MARK: Models (1/16 block, feet at y 0, front toward -Z)

func ashWreckParts(_ m: Mob) -> [Part] {
    var p: [Part] = []
    let sd = m.variant
    // A part's colour, burnt in patches (soot, rust, scorched paint) by its own hash.
    var k = 0
    func burnt(_ c: V3) -> V3 {
        k += 1
        let h = hash3(sd, k, 0x5B, 0xB0E)
        switch h % 7 {
        case 0, 1: return c * 0.32 + V3(0.02, 0.02, 0.02)          // soot
        case 2: return simd_mix(c, V3(0.33, 0.19, 0.11), V3(repeating: 0.7))   // rust
        case 3: return c * 0.62
        default: return c * (0.86 + Float(h >> 8 & 15) / 100)
        }
    }
    func add(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pat: Float = 4,
             pivot: V3 = .zero, rx: Float = 0, rz: Float = 0, ry: Float = 0, burn: Bool = true) {
        p.append(Part(mn: V3(min(x0, x1), min(y0, y1), min(z0, z1)), mx: V3(max(x0, x1), max(y0, y1), max(z0, z1)), pivot: pivot,
                      rotX: rx, rotZ: rz, color: burn ? burnt(c) : c, pattern: pat, rotY: ry))
    }
    let soot = V3(0.05, 0.045, 0.04)
    switch m.wreck {
    case 0: bomberParts(add, soot, sd)
    case 1: fighterParts(add, soot, sd)
    case 5:
        // P464: a Salvaged Fighter in flight (syncSkins), tilted to the hull.
        fighterWholeParts(add, spin: m.walkPhase)
        BoatLooks.rock(&p, pitch: m.boatRock.x, roll: m.boatRock.y)
    case 4:
        // P435: a repaired one, driven: clean paint, the turret and gun on his aim.
        let b = m.soldierBrain
        shermanParts(add, soot, sd, turretOff: false, live: (b.turret - m.yaw, b.pitch))
    default: shermanParts(add, soot, sd, turretOff: m.wreck == 3)
    }
    return p
}

typealias WreckAdd = (Float, Float, Float, Float, Float, Float, V3, Float, V3, Float, Float, Float, Bool) -> Void

// A four-engined bomber, belly-landed: nose and centre section with the left wing and its two engines, the right wing
// broken off past its inner engine and lying behind, the tail section broken away and slewed, its fin up. Bare metal
// and olive drab, grey underneath, scorched.
private func bomberParts(_ add: WreckAdd, _ soot: V3, _ sd: Int) {
    let od = V3(0.30, 0.31, 0.2), grey = V3(0.44, 0.45, 0.45), alu = V3(0.62, 0.63, 0.63), dark = V3(0.06, 0.06, 0.07)
    let glass = V3(0.18, 0.22, 0.24), rubber = V3(0.05, 0.05, 0.05)
    func b(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pat: Float = 4,
           pv: V3 = .zero, rx: Float = 0, rz: Float = 0, ry: Float = 0, burn: Bool = true) { add(x0, y0, z0, x1, y1, z1, c, pat, pv, rx, rz, ry, burn) }
    let roll: Float = 0.06
    let pv = V3(0, 0, 0)
    // Fuselage, nose to the break (z -170 ... 60), a rounded section of two boxes, belly in the ground.
    for (z0, z1) in [(Float(-150), Float(-90)), (-90, -30), (-30, 20), (20, 62)] {
        b(-15, -4, z0, 15, 24, z1, od, pv: pv, rz: roll)
        b(-12, -6, z0, 12, 30, z1, od, pv: pv, rz: roll)
        b(-12, -6.5, z0, 12, -2, z1, grey, pv: pv, rz: roll)
    }
    // Torn skin over the ribs on the right flank and the roof behind the wings.
    b(13, 6, -10, 15.6, 22, 30, dark, 0, pv: pv, rz: roll, burn: false)
    for z in stride(from: Float(-8), through: 28, by: 7) { b(14.5, 5, z, 16, 23, z + 1.2, alu, 8, pv: pv, rz: roll) }
    b(-6, 29.5, 22, 6, 30.8, 58, dark, 0, pv: pv, rz: roll, burn: false)
    // The nose: crumpled glazing and the bombardier's frame, the top turret's glass behind the cockpit.
    b(-10, -4, -168, 10, 18, -150, glass, 11, pv: pv, rx: 0.12, rz: roll, burn: false)
    b(-11, 17, -168, 11, 19, -150, od, pv: pv, rx: 0.12, rz: roll)
    b(-9, 24, -112, 9, 34, -92, glass, 11, pv: pv, rz: roll, burn: false)            // cockpit glazing
    b(-6, 30, -72, 6, 36, -60, glass, 11, pv: pv, rz: roll, burn: false)             // top turret
    b(-1, 33, -78, 1, 34.5, -56, dark, 8, pv: pv, rz: roll)
    // The left wing, whole: root to tip, tapering, two engines in nacelles with bent propellers.
    let wy: Float = 4
    b(-15, wy, -48, -80, wy + 5, 4, od, pv: pv, rz: roll)
    b(-80, wy - 0.5, -42, -150, wy + 3.5, -6, od, pv: pv, rz: roll + 0.03)
    b(-150, wy - 1, -38, -200, wy + 2.5, -14, od, pv: pv, rz: roll + 0.05)
    b(-80, wy - 1, -6, -150, wy + 0.5, 0, alu, 8, pv: pv, rz: roll)                  // a flap hanging down
    for (cx, bent) in [(Float(-58), Float(0.5)), (Float(-112), Float(-0.7))] {
        b(cx - 8, wy - 7, -82, cx + 8, wy + 9, -40, od, pv: pv, rz: roll)            // nacelle
        b(cx - 9, wy - 8, -86, cx + 9, wy + 10, -80, dark, 8, pv: pv, rz: roll)      // cowling ring
        b(cx - 2, wy - 1, -90, cx + 2, wy + 3, -86, alu, 8, pv: pv, rz: roll)        // hub
        // Three blades, bent back where they struck the ground.
        let hub = V3(cx, wy + 1, -88)
        b(cx - 1.2, wy + 3, -89, cx + 1.2, wy + 30, -87, dark, 8, pv: hub, rx: bent * 0.6, rz: roll)
        b(cx - 1.2, wy - 26, -89, cx + 1.2, wy - 1, -87, dark, 8, pv: hub, rx: -bent, rz: roll + 2.1)
        b(cx - 1.2, wy - 26, -89, cx + 1.2, wy - 1, -87, dark, 8, pv: hub, rx: bent, rz: roll - 2.1)
        b(cx - 3, wy - 9, -60, cx - 1, wy - 7, -44, soot, 0, pv: pv, rz: roll, burn: false)      // exhaust soot
    }
    // The right wing: the stub to the inner engine, burnt out, its outer panel torn off and lying behind.
    b(15, wy, -48, 72, wy + 5, 4, od, pv: pv, rz: roll)
    b(48, wy - 7, -82, 64, wy + 9, -40, soot, 4, pv: pv, rz: roll)
    b(47, wy - 8, -86, 65, wy + 10, -80, dark, 8, pv: pv, rz: roll)
    b(70, wy - 2, -46, 76, wy + 7, 2, alu, 8, pv: pv, rz: roll)                      // torn edge
    let ow = V3(110, 0, 100)
    b(80, 0, 80, 190, 4, 118, od, pv: ow, rz: -0.08, ry: 0.5)
    b(105, -2, 74, 125, 12, 84, dark, 8, pv: ow, ry: 0.5)                            // outer engine, torn off with it
    // The tail section: broken away and slewed, its stub open, the fin standing, a stabiliser in the ground.
    let tp = V3(0, 0, 84)
    let ty: Float = 0.42
    b(-12, -3, 70, 12, 24, 150, od, pv: tp, rz: -0.1, ry: ty)
    b(-9, -4, 150, 9, 20, 210, od, pv: tp, rz: -0.1, ry: ty)
    b(-11, 0, 69, 11, 22, 71, dark, 0, pv: tp, rz: -0.1, ry: ty, burn: false)         // the open break
    b(-2, 18, 150, 2, 92, 200, od, pv: tp, rx: 0.05, rz: -0.1, ry: ty)              // fin
    b(-2, 60, 168, 2, 92, 204, od, pv: tp, rz: -0.1, ry: ty)
    b(-78, 6, 182, 78, 10, 206, od, pv: tp, rz: -0.13, ry: ty)                      // stabilisers
    b(-4, 4, 204, 4, 16, 214, glass, 11, pv: tp, ry: ty, burn: false)                // tail gunner's glass
    // Main wheel half buried, debris.
    b(-62, -6, -40, -50, 8, -26, rubber, 0, pv: pv, burn: false)
    var h = UInt32(truncatingIfNeeded: sd) | 1
    for _ in 0..<10 {
        h = h &* 1664525 &+ 1013904223
        let x = Float(Int(h >> 8 % 360) - 180), z = Float(Int(h >> 17 % 360) - 120), s = Float(3 + Int(h % 9))
        b(x, -1, z, x + s * 2, s * 0.4, z + s, h % 3 == 0 ? alu : od, 8, ry: Float(h % 100) / 30)
    }
}

// A single-engined fighter nosed into the ground: tail up, propeller buried, the right wing snapped off beside it.
private func fighterParts(_ add: WreckAdd, _ soot: V3, _ sd: Int) {
    let alu = V3(0.6, 0.62, 0.63), od = V3(0.28, 0.3, 0.19), dark = V3(0.06, 0.06, 0.07), glass = V3(0.2, 0.25, 0.28)
    func b(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pat: Float = 8,
           pv: V3 = .zero, rx: Float = 0, rz: Float = 0, ry: Float = 0, burn: Bool = true) { add(x0, y0, z0, x1, y1, z1, c, pat, pv, rx, rz, ry, burn) }
    // Everything tilts nose-down about the nose, which is in the ground.
    let nose = V3(0, 0, -78), pitch: Float = -0.36, roll: Float = 0.14
    func t(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pat: Float = 8, burn: Bool = true) {
        b(x0, y0, z0, x1, y1, z1, c, pat, pv: nose, rx: pitch, rz: roll, burn: burn)
    }
    t(-9, -8, -78, 9, 10, -46, alu)                                 // engine cowling
    t(-9.5, 8, -78, 9.5, 10.5, -40, od)                             // the olive anti-glare panel
    t(-10, -9, -82, 10, 11, -78, dark)                              // cowl ring
    t(-8, -6, -46, 8, 16, 34, alu)                                  // fuselage
    t(-6, -4, 34, 6, 12, 78, alu)
    t(-6, 16, -16, 6, 23, 10, glass, 11, burn: false)               // the bubble canopy, cracked
    t(-6.5, 22, -10, 6.5, 23.5, -8, dark, 8)
    t(-5, -12, -4, 5, -6, 28, alu)                                  // the belly scoop
    t(-1.5, 12, 66, 1.5, 42, 80, alu)                               // fin and rudder
    t(-30, 6, 68, 30, 8.5, 80, alu)                                 // tailplane
    t(-90, -4, -30, -8, -0.5, 4, alu)                               // left wing, whole
    t(-90, -4.5, -6, -50, -3, 4, od, 8)                             // a scorched aileron
    t(8, -4, -30, 34, -0.5, 4, alu)                                 // the right wing's stub
    t(32, -6, -32, 36, 0, 6, dark)                                  // its torn edge
    t(-36, -14, -16, -30, -4, -10, dark, 0)                         // a leg of the undercarriage, wrenched down
    t(-4, -6, -6, 4, -3, 10, soot, 0, burn: false)
    // The propeller: hub and three blades curled back in the ground.
    let hub = V3(0, 1, -84)
    b(-2.5, -2, -86, 2.5, 4, -82, alu, 8, pv: nose, rx: pitch, rz: roll)
    b(-1.5, 3, -86, 1.5, 32, -84, dark, 8, pv: hub, rx: pitch - 0.9, rz: roll + 0.3)
    b(-1.5, -28, -86, 1.5, -2, -84, dark, 8, pv: hub, rx: pitch + 0.8, rz: roll + 2.0)
    b(-1.5, -28, -86, 1.5, -2, -84, dark, 8, pv: hub, rx: pitch + 0.8, rz: roll - 2.0)
    // The snapped wing lying flat on the ground off to the right, and scorched earth round the nose.
    b(50, 0, -20, 110, 3.5, 12, alu, 8, pv: V3(80, 0, -4), ry: 0.7)
    b(50, 0, -20, 58, 4, 12, dark, 8, pv: V3(80, 0, -4), ry: 0.7)
}

// The same fighter whole and clean (P464, a Salvaged Fighter: syncSkins), on its wheels, level, laid out over the
// salvagedFighter plan at AshWrecks.skinScale: nose at the propeller (plan z -7), the canopy over the helm, wings the
// plan's span, the fin over its tail. No part turns on its own (the hull's pitch and roll go on every part).
private func fighterWholeParts(_ add: WreckAdd, spin: Float) {
    let alu = V3(0.6, 0.62, 0.63), od = V3(0.28, 0.3, 0.19), dark = V3(0.06, 0.06, 0.07), glass = V3(0.2, 0.25, 0.28)
    let rubber = V3(0.05, 0.05, 0.05)
    func b(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pat: Float = 8) {
        add(x0, y0, z0, x1, y1, z1, c, pat, .zero, 0, 0, 0, false)
    }
    b(-9, 7, -86, 9, 25, -50, alu)                          // engine cowling
    b(-9.5, 25, -86, 9.5, 27.5, -40, od)                    // the olive anti-glare panel
    b(-10, 6, -90, 10, 26, -86, dark)                       // cowl ring
    b(-2.5, 13, -95, 2.5, 19, -90, alu)                     // spinner
    // The propeller: four blades, turning (two looks a quarter apart; a blur of dark at speed).
    if Int(spin) % 2 == 0 {
        b(-1.5, 3, -94, 1.5, 29, -92, dark); b(-14, 14.5, -94, 14, 17.5, -92, dark)
    } else {
        b(-10, 6, -94, 10, 26, -92.5, dark, 0); b(-1, 15, -94, 1, 17, -92, dark)
    }
    b(-8, 9, -50, 8, 31, 34, alu)                           // fuselage
    b(-6, 11, 34, 6, 27, 94, alu)                           // to the tail
    b(-6, 31, -36, 6, 38, -10, glass, 11)                   // the bubble canopy
    b(-6.5, 37, -30, 6.5, 38.5, -28, dark)                  // its frame
    b(-5, 4, -10, 5, 9, 22, alu)                            // the belly scoop
    b(-1.5, 27, 78, 1.5, 57, 94, alu)                       // fin and rudder
    b(-30, 21, 80, 30, 23.5, 94, alu)                       // tailplane
    b(-83, 11, -17, -8, 14.5, 17, alu)                      // wings
    b(8, 11, -17, 83, 14.5, 17, alu)
    b(-83, 10.5, 7, -50, 11, 17, od, 4); b(50, 10.5, 7, 83, 11, 17, od, 4)      // ailerons
    for x: Float in [-1, 1] {                               // the main gear: legs and wheels
        b(x * 29.5 - 1.5, 6, -8, x * 29.5 + 1.5, 11, -5, dark)
        b(x * 29.5 - 3.5, 0, -10, x * 29.5 + 3.5, 8, -2, rubber, 0)
    }
    b(-1, 4, 87, 1, 11, 89, dark)                           // tail wheel
    b(-2, 0, 85, 2, 4, 91, rubber, 0)
}

// A Sherman-like medium tank, knocked out: a cast turret with a short 75 and its mantlet, the hull's sloped glacis,
// three vertical-volute bogies a side with their return rollers, front drive sprockets and rear idlers, a hull gun, the
// engine deck, hatches thrown open. `turretOff`: the turret blown off and lying upside down beside it.
private func shermanParts(_ add: WreckAdd, _ soot: V3, _ sd: Int, turretOff: Bool, live: (Float, Float)? = nil) {
    let od = V3(0.29, 0.3, 0.19), dark = V3(0.06, 0.06, 0.06), steel = V3(0.2, 0.2, 0.19), rubber = V3(0.07, 0.07, 0.07)
    let fixed = live != nil                                              // P435: repaired (no soot, rust or thrown track)
    func b(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pat: Float = 4,
           pv: V3 = .zero, rx: Float = 0, rz: Float = 0, ry: Float = 0, burn: Bool = true) {
        if fixed && c == soot { return }
        add(x0, y0, z0, x1, y1, z1, c, pat, pv, rx, rz, ry, burn && !fixed)
    }
    let h = UInt32(truncatingIfNeeded: sd) &* 2654435761
    // Tracks, bogies, sprockets and idlers, both sides (one track broken and run off behind on some).
    let broken = h % 3 == 0 && !fixed
    for s: Float in [-1, 1] {
        let xo: Float = s < 0 ? -21 : 14.5, xi = xo + 6.5
        let slack = broken && s > 0
        b(xo, 0, -40, xi, 2.5, slack ? 18 : 40, steel, 8)                    // the ground run
        if !slack { b(xo, 15, -44, xi, 17.5, 38, steel, 8) }                // the top run
        b(xo, 4, -48, xi, 15, -42, steel, 8)                                // round the sprocket
        b(xo, 2.5, 38, xi, 15, 44, steel, 8)                                // round the idler
        if slack { b(xo, 0, 44, xi, 1.5, 96, steel, 8, pv: V3(xo, 0, 44), ry: s * 0.12) }      // thrown off behind
        b(xo - 0.6, 6, -48, xi + 0.6, 16, -38, dark, 8)                     // drive sprocket
        b(xo - 0.6, 5, 36, xi + 0.6, 14, 45, dark, 8)                       // idler
        for bz: Float in [-26, 0, 26] {
            b(xo - 0.8, 6, bz - 7, xi + 0.8, 13, bz + 7, od)                // bogie bracket and volute springs
            for wz: Float in [-4.5, 4.5] { b(xo - 1.2, 1, bz + wz - 4, xi + 1.2, 9, bz + wz + 4, rubber, 0, burn: false) }   // road wheels
            b(xo - 0.4, 13, bz + 2, xi + 0.4, 15.5, bz + 6, dark, 8)        // return roller
        }
    }
    // Hull: lower hull between the tracks, the sponsons over them, the glacis and the rounded transmission cover.
    b(-14.5, 3, -40, 14.5, 17, 44, od)
    b(-21, 17, -26, 21, 32, 44, od)
    b(-21, 17, -44, 21, 20, -26, od, pv: V3(0, 17, -44), rx: -0.62)    // glacis, sloped back
    b(-20, 19, -40, 20, 31, -26, od)                                    // (filling under it)
    b(-16, 6, -48, 16, 20, -40, od)                                     // transmission cover
    b(-14, 8, -50, 14, 18, -48, od)
    b(-21.6, 19, -12, -21, 28, 4, od); b(21, 19, -12, 21.6, 28, 4, od)  // appliqué plates
    b(7, 21, -40, 12, 26, -36, dark, 8)                                 // the hull gun's ball
    b(8.8, 22.8, -54, 10.2, 24.2, -38, dark, 8)
    // Driver's and co-driver's hatches, thrown open.
    b(-14, 32, -26, -5, 33, -18, od); b(-14, 32, -18, -5, 41, -17, od)
    b(5, 32, -26, 14, 33, -18, od)
    // Engine deck: grille, tools, the rear plate.
    b(-15, 32, 24, 15, 32.6, 42, dark, 8)
    b(-21, 20, 44, 21, 32, 46, od)
    b(-20, 32, 6, -17, 33, 30, V3(0.3, 0.2, 0.12), 0)                   // a shovel's haft along the deck
    // Turret: a cast, rounded turret on its ring, the mantlet and short 75, hatches open, a heavy MG on the roof.
    let turn = Float(Int(h >> 8 % 120) - 60) / 100
    let droop: Float = -0.06 - Float(h >> 4 % 10) / 100
    let pv = V3(0, 32, 2)
    var ry = live?.0 ?? turn, rz: Float = 0, lift = V3.zero
    if turretOff {
        // Blown off: thrown down on its side beside the hull, half dug in, its ring a black hole in the deck.
        b(-11, 32, -10, 11, 32.6, 14, soot, 0, burn: false)
        lift = V3(44, -32, 6)
        rz = 0.4
        ry = 0.8
    }
    func tb(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pat: Float = 4, gun: Bool = false) {
        add(x0 + lift.x, y0 + lift.y, z0 + lift.z, x1 + lift.x, y1 + lift.y, z1 + lift.z, c, pat, pv + lift, gun ? (live?.1 ?? droop) : 0, rz, ry, !fixed)
    }
    tb(-15, 32, -14, 15, 37, 18, od)
    tb(-13.5, 37, -12, 13.5, 42, 20, od)
    tb(-11, 42, -9, 11, 45, 14, od)
    tb(-8, 32, 18, 8, 41, 23, od)                                       // the bustle
    tb(-8, 33, -19, 8, 42, -13, od)                                     // mantlet
    tb(-1.4, 35.5, -66, 1.4, 38.3, -19, dark, 8, gun: true)             // the 75
    tb(-1.8, 35.1, -68, 1.8, 38.7, -64, dark, 8, gun: true)
    tb(-10, 45, 3, -3, 47, 10, od)                                      // commander's hatch ring
    tb(-10, 47, 10, -3, 55, 11, od)                                     // ... its lid thrown open
    tb(3, 45, 2, 9, 46, 8, od)
    tb(-1, 45, 14, 1, 52, 16, dark, 8)                                  // the roof MG on its pintle
    tb(-0.7, 51, -6, 0.7, 52.4, 16, dark, 8)
    tb(-4, 44, -6, -2, 46, -4, dark, 8); tb(2, 44, -6, 4, 46, -4, dark, 8)    // periscopes
    // Soot over the deck, a scorched patch round it.
    b(-12, 33, -24, 6, 33.4, 2, soot, 0, burn: false)
}

// MARK: The fallen

// A fallen Allied infantryman of 1940: modelled standing (feet at y 0, face toward -Z, back at z +4) and drawn on his back
// (Mob.lying turns model z into height: the back on the ground). Olive drab tunic, khaki trousers, canvas leggings and
// brown boots, webbing belt, braces and canteen, a round steel helmet with its brim (or knocked off beside his head),
// arms flung out, his rifle on the ground beside him.
func fallenAlliedParts(_ m: Mob) -> [Part] {
    let h = hash3(Int(m.pos.x * 16), 0xFA1, Int(m.pos.z * 16), 0xA11)
    let tunic = V3(0.33, 0.31, 0.2) * (0.9 + Float(h & 7) / 50), trousers = V3(0.45, 0.4, 0.28), canvas = V3(0.55, 0.5, 0.36)
    let web = V3(0.47, 0.44, 0.3), boots = V3(0.26, 0.16, 0.09), helmet = V3(0.27, 0.29, 0.2), wood = V3(0.38, 0.23, 0.12)
    let metal = V3(0.13, 0.13, 0.13), skin = Livery.skins[Int(h >> 4) % Livery.skins.count] * 0.8
    var p: [Part] = []
    func b(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pat: Float = 6,
           pv: V3 = .zero, rx: Float = 0, rz: Float = 0, ry: Float = 0) {
        p.append(Part(mn: V3(x0, y0, z0), mx: V3(x1, y1, z1), pivot: pv, rotX: rx, rotZ: rz, color: c, pattern: pat, rotY: ry))
    }
    let side: Float = h & 0x100 != 0 ? 1 : -1                     // the rifle's side
    let splay = 0.08 + Float(h >> 9 & 7) / 40
    // Legs (splayed), leggings and boots, toes up.
    for s: Float in [-1, 1] {
        let pv = V3(s * 2, 12, 2), rz = s * splay * (s == side ? 0.6 : 1)
        b(s < 0 ? -4 : 0.3, 4, 0.6, s < 0 ? -0.3 : 4, 12.5, 4, trousers, 6, pv: pv, rz: rz)
        b(s < 0 ? -4.3 : 0, 1.5, 0.3, s < 0 ? 0 : 4.3, 6, 4.2, canvas, 6, pv: pv, rz: rz)
        b(s < 0 ? -4.2 : 0.1, 0, -1.5, s < 0 ? -0.1 : 4.2, 2, 4.2, boots, 10, pv: pv, rz: rz)
    }
    // Tunic, belt with pouches, braces, canteen on the hip.
    b(-4.5, 12, 0, 4.5, 23.5, 4, tunic)
    b(-4.8, 11.5, -0.4, 4.8, 13.6, 4.2, web)
    b(-4, 11.8, -1.2, -1.2, 14, -0.3, web); b(1.2, 11.8, -1.2, 4, 14, -0.3, web)
    b(-3.2, 13.6, -0.3, -2.1, 23.5, 0, web); b(2.1, 13.6, -0.3, 3.2, 23.5, 0, web)
    b(-3, 20, -0.25, 3, 21.5, 0, tunic * 0.8)                      // pocket flaps
    b(4.7, 10.5, 1, 6.6, 13.8, 3.6, helmet * 0.9, 0)               // canteen
    // Arms flung out from the shoulders, hands open.
    let armL = 0.35 + Float(h >> 12 & 15) / 20, armR = 0.3 + Float(h >> 16 & 15) / 12
    b(-7.4, 12.5, 0.6, -4.5, 23.5, 3.6, tunic, 6, pv: V3(-5.9, 23, 2), rz: -armL)
    b(-7.2, 10.2, 0.8, -4.7, 12.5, 3.4, skin, 0, pv: V3(-5.9, 23, 2), rz: -armL)
    b(4.5, 12.5, 0.6, 7.4, 23.5, 3.6, tunic, 6, pv: V3(5.9, 23, 2), rz: armR)
    b(4.7, 10.2, 0.8, 7.2, 12.5, 3.4, skin, 0, pv: V3(5.9, 23, 2), rz: armR)
    // Collar, head turned a little, the helmet on or knocked off.
    b(-2, 23.5, 0.4, 2, 24.5, 3.6, tunic * 0.85)
    let tilt = Float(Int(h >> 20 & 15) - 7) / 30
    let hp = V3(0, 24, 2)
    b(-3, 24, -2, 3, 30, 4, skin, 0, pv: hp, ry: tilt)
    b(-2.2, 27.3, -2.15, -0.8, 27.8, -2, V3(0.1, 0.08, 0.06), 0, pv: hp, ry: tilt)
    b(0.8, 27.3, -2.15, 2.2, 27.8, -2, V3(0.1, 0.08, 0.06), 0, pv: hp, ry: tilt)
    if h % 3 != 0 {
        b(-3.7, 28.6, -2.6, 3.7, 31.6, 4.4, helmet, 4, pv: hp, ry: tilt)            // the dome
        b(-4.4, 28.1, -3.3, 4.4, 28.8, 5.1, helmet * 0.9, 4, pv: hp, ry: tilt)      // its brim
        b(-3.1, 25.2, -1.8, -2.9, 28.4, -1.5, web, 6, pv: hp, ry: tilt)            // chin strap
    } else {
        let x0: Float = -side * 7
        b(x0 - 3.7, 26, 1, x0 + 3.7, 32, 4, helmet, 4)                              // knocked off, lying beside him
        b(x0 - 4.4, 25.4, 0.4, x0 + 4.4, 32.6, 1, helmet * 0.9, 4)
    }
    // The rifle on the ground beside him: stock, receiver, fore end and barrel.
    let rx0 = side * 10.5, rp = V3(rx0, 18, 3.5), ang = side * (0.1 + Float(h >> 24 & 7) / 30)
    b(rx0 - 1.3, 2, 3, rx0 + 1.3, 12, 4.1, wood, 10, pv: rp, rz: ang)
    b(rx0 - 0.9, 12, 2.8, rx0 + 0.9, 17, 4.1, metal, 8, pv: rp, rz: ang)
    b(rx0 - 0.8, 17, 3.1, rx0 + 0.8, 27, 4.1, wood, 10, pv: rp, rz: ang)
    b(rx0 - 0.4, 17, 2.5, rx0 + 0.4, 33, 3.1, metal, 8, pv: rp, rz: ang)
    b(rx0 - 0.5, 10, 2.6, rx0 + 0.5, 22, 2.9, web, 6, pv: rp, rz: ang)              // its sling
    return p
}
