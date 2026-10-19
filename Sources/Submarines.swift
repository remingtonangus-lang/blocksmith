import Foundation
import simd

// Submarines, mines and sonar (backlog C8).
// - Ballast tanks (ShipBlocks, ShipPhysics): under water a hull's tanks flood to dive and blow to surface, and hold a depth
//   while nobody steers; any built hull with a helm, a propeller and enough tanks is a submarine.
// - The Submarine Kit (iron, glass, a helm, an engine, a propeller, ballast): used at the water's edge it floats a small
//   ready-made boat: a plank hull with ports, seventeen tanks in its keel, the helm forward, an open hatch on top.
// - Torpedoes: a ship's cannon under water looses a torpedo instead of a shell (ShipCombat: level, self-driven, 5 s).
// - Sea mines: a horned iron ball on a chain. A player or a moving vessel within reach sets it off after a short tick.
//   Craftable; generated round the Sunken Dreadnought wrecks (G20) as a field guarding the hulk.
// - Sonar: the navy's frigates hear a submarine running fast (over 3 blocks a second) or firing within 140 blocks, ping
//   it and drop depth charges that sink and burst at its depth; one creeping slowly and quietly below is not heard.
enum Submarine {
    static let kitKey = "submarine_kit"
    static let name = "Submarine"
    static let torpedoSpeed: Float = 18
    static let torpedoLife: Float = 5
    static let chargeSink: Float = 6
    static let sonarRange: Float = 140
    static let loudSpeed: Float = 3
    static let sonarEvery: Double = 6
    static let mineKey = "sea_mine"
    static let mineReach: Float = 2.2

    // Bow -Z, like every vessel blueprint: 9 long, 3 wide, 4 high; the helm forward, the screw astern.
    static func blueprint() -> Blueprint {
        let b = Blueprint()
        let plate = "spruce_planks"
        for z in -4...4 { for y in 0...3 { for x in -1...1 {
            let shell = abs(x) == 1 || y == 0 || y == 3 || abs(z) == 4
            if shell { b.set(x, y, z, plate) }
        } } }
        // Ports along the sides, tanks in the keel, the hatch on top amidships.
        for z in [-2, 0, 2] { b.set(-1, 2, z, "glass"); b.set(1, 2, z, "glass") }
        for z in -3...3 { for x in -1...1 where !(x == 0 && z == 1) && (x != 0 || z % 2 == 0) { b.set(x, 0, z, "ship_ballast") } }
        b.set(0, 0, 1, "ship_engine")
        b.set(0, 1, -3, "ship_helm[south]")
        b.set(0, 1, 5, "ship_propeller[south]")
        b.clear(0, 3, 0)
        return b
    }

    // Right-click with the kit facing water: the boat floats in front of the player.
    static func use(_ g: Game) -> Bool {
        let held = g.inventory.main[g.inventory.selected]
        guard !held.isEmpty, Items.has(kitKey), held.item == Items.id(kitKey) else { return false }
        guard let s = deploy(g) else { return true }
        if g.survival {
            g.inventory.main[g.inventory.selected].count -= 1
            if g.inventory.main[g.inventory.selected].count <= 0 { g.inventory.main[g.inventory.selected] = .empty }
        }
        g.sfx(.splash, 0.9, at: s.pos)
        g.onToast?("The submarine is afloat")
        return true
    }

    // The water surface in a column (array y of the top water block), or nil when the top isn't water 4+ deep.
    static func surface(_ w: World, _ x: Int, _ z: Int) -> Int? {
        let top = w.topY(x, z)
        for y in stride(from: min(CH - 1, top + 2), through: max(1, top - 2), by: -1) where Blocks.fluidKind[Int(w.block(x, y, z))] == 1 {
            for d in 1...4 where Blocks.fluidKind[Int(w.block(x, y - d, z))] != 1 { return nil }
            return y
        }
        return nil
    }

    @discardableResult
    static func deploy(_ g: Game) -> Ship? {
        let w = g.world
        let quarter = (g.player.yaw / (.pi / 2)).rounded() * (.pi / 2)
        let fwd = V3(-sinf(quarter), 0, -cosf(quarter))
        let c = g.player.pos + fwd * 8
        let cx = Int(floor(c.x)), cz = Int(floor(c.z))
        var level = Int.min
        for dz in -5...5 { for dx in -5...5 {
            guard w.isLoaded(cx + dx, cz + dz), let s = surface(w, cx + dx, cz + dz) else {
                g.onToast?("Too shallow"); return nil
            }
            level = max(level, s)
        } }
        let s = w.ships.spawn(blueprint(), at: V3(c.x, Float(level) + 1, c.z), yaw: quarter, name: name, role: "")
        s.role = nil
        s.pos.y += Float(level) - 1 - s.toWorld(V3(0, s.localMin.y, 0)).y      // keel two below the surface: it floats up
        s.prevPos = s.pos
        s.updateBounds()
        s.initialBlocks = s.blockCount
        return s
    }
}

extension Game {
    func submarineUse() -> Bool { Submarine.use(self) }

    // Mines and sonar, every tick (CapitalBases.basesTick).
    func submarinesTick(_ dt: Float) {
        Submarine.mineTimer += Double(dt)
        if Submarine.mineTimer >= 0.2 { Submarine.mineTimer = 0; minesCheck() }
        sonarTick()
        enemySubTick(dt)
    }

    // A player or a moving vessel close to a sea mine sets it off.
    func minesCheck() {
        guard Blocks.has(Submarine.mineKey), dim.dim == .overworld else { return }
        let mine = Blocks.id(Submarine.mineKey), wetMine = Blocks.wet[Int(mine)]
        var hot: [IVec3] = []
        func scan(_ lo: V3, _ hi: V3) {
            let r = Submarine.mineReach
            let x0 = Int(floor(lo.x - r)), x1 = Int(floor(hi.x + r)), y0 = Int(floor(lo.y - r)), y1 = Int(floor(hi.y + r))
            let z0 = Int(floor(lo.z - r)), z1 = Int(floor(hi.z + r))
            let ya = max(0, y0), yb = min(CH - 1, y1)       // a body below the world or above it has nothing to set off
            guard ya <= yb, (x1 - x0 + 1) * (yb - ya + 1) * (z1 - z0 + 1) <= 8000 else { return }
            for y in ya...yb { for z in z0...z1 { for x in x0...x1 where world.builtBlock(x, y, z) == mine || (wetMine != AIR && world.builtBlock(x, y, z) == wetMine) { hot.append(IVec3(x, y, z)) } } }
        }
        if survival || !Submarine.creativeSafe {
            for i in 0..<max(1, coop.seatCount) { let p = coop.seatPlayer(i, self).pos; scan(p, p + V3(0, 1.8, 0)) }
        }
        for s in world.ships.list where s.parent == nil && !s.asleep && !s.kinematic && simd_length(s.vel) > 0.3 { scan(s.worldMin, s.worldMax) }
        for q in Set(hot) {
            world.setBlock(q.x, q.y, q.z, world.rawBlock(q.x, q.y, q.z) == mine ? AIR : WATER)
            let at = V3(Float(q.x) + 0.5, Float(q.y) + 0.5, Float(q.z) + 0.5)
            sfx(.click, 1, at: at)
            Explosion.explode(at: at, power: 4, game: self)                 // (blasts any hull in reach too)
        }
    }

    // The navy's sonar: a loud submarine within reach is pinged and depth-charged.
    func sonarTick() {
        guard let sub = world.ships.pilot?.root, sub.ballast > 0, sub.submerged > 1 else { return }
        let loud = simd_length(sub.vel) > Submarine.loudSpeed || clock - Submarine.lastShot < 4
        guard loud else { return }
        for f in world.ships.list where f.parent == nil && !f.wrecked && !f.captured && (f.role == "capfrigate" || f.role == "warfrigate") {
            guard simd_length(f.pos - sub.pos) < Submarine.sonarRange else { continue }
            if clock - (Submarine.lastPing[f.id] ?? -100) < Submarine.sonarEvery { continue }
            Submarine.lastPing[f.id] = clock
            if let st = world.ships.capState[f.id] { st.pingAt = sub.pos; st.pingT = 0 }     // she steers to the ping
            sfx(.click, 1.3, at: sub.pos)
            onToast?("Sonar ping: the navy has heard you")
            depthCharges(from: f, at: sub.pos)
        }
    }

    // Two charges thrown from the frigate at the target, sinking to its depth. The throw is timed with the real flight
    // (ShipCombat): a free fall through the air to the water's surface over the target, then a sink at chargeSink.
    func depthCharges(from f: Ship, at t: V3) {
        let top = V3(f.pos.x, max(f.worldMin.y, t.y + 4), f.pos.z)
        let tx = Int(floor(t.x)), tz = Int(floor(t.z))
        var wy = Int(floor(t.y))
        while wy < CH - 1 && Blocks.fluidKind[Int(world.rawBlock(tx, wy + 1, tz))] == 1 { wy += 1 }
        let surface = min(top.y, Float(wy + 1))
        for k in 0..<2 {
            let aim = t + V3(Float(k) * 3 - 1.5, 0, Float(k) * 2 - 1)
            let air = max(0, top.y - surface), water = max(0, surface - (t.y + 0.5))
            let tf = max(0.3, (2 * air / 20).squareRoot() + water / Submarine.chargeSink)
            let vel = V3((aim.x - top.x) / tf, 0, (aim.z - top.z) / tf)
            let sh = Shell(pos: top, vel: vel, owner: f.root.id, power: 3)
            sh.kind = 5; sh.gravity = 0; sh.fuseY = t.y + 0.5; sh.life = 14
            world.ships.shells.append(sh)
        }
    }
}

extension Submarine {
    static var mineTimer: Double = 0
    static var lastShot: Double = -100            // a torpedo fired (sonar hears it)
    static var lastPing: [Int: Double] = [:]
    static var creativeSafe = true                // creative players don't set mines off (vessels still do)
}

extension ItemRegistry {
    func registerSubmarineItems() {
        guard !has(Submarine.kitKey) else { return }
        var d = ItemDef(Submarine.kitKey, "Submarine Kit")
        d.sprite = Sprite(mask: "submarine", base: 0x4E565E, extras: ["c": 0x2E3338, "d": 0x8A9096, "e": 0xA8823A, "f": 0x2F5F96, "g": 0x5A8CC4])
        d.maxStack = 1
        add(d)
    }
}
