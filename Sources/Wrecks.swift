import Foundation
import simd

// P93 (Oct 12 AM playtest): pirates and wrecks.
// - Wrecks you can raise: a broken shipwreck on ground first generated with this rule (WorldRules.p69) is rotten in
//   places instead of holed: Rotten Planks where the holes were and below the waterline too. A Ship Helm placed on
//   it assembles the hull like any ship (Ships.assemble), but not while a rotten plank is part of it: the helm says
//   how many are left. Replace them (any planks) and the hull comes free of the seabed and floats.
// - Cannons are crafted (ShipBlocks), and fired from a ship you steer they now use Cannonballs (iron and gunpowder,
//   four a craft) in survival.
// - A cannon set next to a computer taken from a base (a command console, a Greywall terminal or server rack) is an
//   auto-turret: every 2.5 s it fires at the nearest hostile within 28 blocks it can see, with shells that hurt but
//   don't break blocks. Sites are noted when either block is placed, and saved ("autoTurrets").
enum Wrecks {
    static let rotten = "ship_wood_rotten"
    static let cannonball = "cannonball"
    static var rottenID: BlockID { Blocks.has(rotten) ? Blocks.id(rotten) : AIR }

    // Rotten planks in a hull about to be assembled.
    static func rottenCount(_ w: World, _ cells: [IVec3]) -> Int {
        let r = rottenID
        guard r != AIR else { return 0 }
        return cells.reduce(0) { $0 + (w.rawBlock($1.x, $1.y, $1.z) == r ? 1 : 0) }
    }

    // Survival: a ship's guns fire only with cannonballs in the pilot's pack, one each.
    static func cannonballs(_ g: Game) -> Int {
        guard Items.has(cannonball) else { return 0 }
        let id = Items.id(cannonball)
        var n = 0
        for i in 0..<g.inventory.main.count where g.inventory.main[i].item == id { n += g.inventory.main[i].count }
        return n
    }
    static func useCannonballs(_ g: Game, _ n: Int) {
        guard Items.has(cannonball), n > 0 else { return }
        let id = Items.id(cannonball)
        var left = n
        let inv = g.inventory.main
        for i in 0..<inv.count where left > 0 && inv[i].item == id {
            var s = inv[i]
            let take = min(left, s.count)
            s.count -= take
            inv[i] = s.count > 0 ? s : ItemStack()
            left -= take
        }
    }
}

// MARK: Auto-turrets

enum AutoTurrets {
    static let range: Float = 28
    static let reload: Float = 2.5
    static let power: Float = 2.2
    static var sites: Set<IVec3> = []                 // cannon cells
    static var cool: [IVec3: Float] = [:]
    private static var clock: Float = 0

    static func isCannon(_ b: BlockID) -> Bool { Blocks.key(Blocks.groupBase[Int(b)]) == "ship_cannon" }
    static func isComputer(_ b: BlockID) -> Bool {
        let k = Blocks.key(Blocks.groupBase[Int(b)])
        return k == "command_console" || k == "greywall_terminal" || k == "greywall_server"
    }
    static let around = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1), IVec3(0, 1, 0), IVec3(0, -1, 0)]
    static func wired(_ w: World, _ c: IVec3) -> Bool {
        guard isCannon(w.block(c.x, c.y, c.z)) else { return false }
        return around.contains { isComputer(w.block(c.x + $0.x, c.y + $0.y, c.z + $0.z)) }
    }

    // A block was placed: a cannon by a computer, or a computer by cannons, makes (or adds to) a turret.
    static func placed(_ g: Game, _ p: IVec3) {
        let w = g.world, b = w.block(p.x, p.y, p.z)
        var found: [IVec3] = []
        if isCannon(b) && wired(w, p) { found.append(p) }
        if isComputer(b) { for d in around { let c = p + d; if wired(w, c) { found.append(c) } } }
        guard !found.isEmpty else { return }
        let fresh = found.filter { !sites.contains($0) }
        for c in found { sites.insert(c) }
        if !fresh.isEmpty { g.onToast?("Auto-turret online: the computer aims the cannon at hostiles within \(Int(range)) blocks") }
    }

    static func save(_ d: inout [String: String]) {
        if !sites.isEmpty { d["autoTurrets"] = sites.map { "\($0.x),\($0.y),\($0.z)" }.joined(separator: ";") }
    }
    static func load(_ d: [String: String]) {
        sites = []; cool = [:]
        for s in (d["autoTurrets"] ?? "").split(separator: ";") {
            let v = s.split(separator: ",").compactMap { Int($0) }
            if v.count == 3 { sites.insert(IVec3(v[0], v[1], v[2])) }
        }
    }

    static func hostile(_ m: Mob, _ g: Game) -> Bool {
        guard m.health > 0, m.kind.hostile else { return false }
        // Soldiers and the neutral kinds only while they're after the player; monsters always.
        let k = m.kind.key, b = m.spec.behavior
        if k.hasPrefix("soldier_") || k.hasPrefix("ash_") || b == .neutral || b == .piglin || b == .enderman { return m.aggro && m.lockTime > 0 }
        return true
    }

    // Once a frame (cheap: a handful of sites, each looked at every `reload` seconds).
    static func tick(_ g: Game, _ dt: Float) {
        guard !sites.isEmpty, g.dim.dim == .overworld else { return }
        clock += dt
        guard clock >= 0.25 else { return }
        let step = clock
        clock = 0
        let w = g.world
        var gone: [IVec3] = []
        for c in sites {
            guard w.isLoaded(c.x, c.z) else { continue }
            guard wired(w, c) else { gone.append(c); continue }
            let left = (cool[c] ?? 0) - step
            cool[c] = left
            guard left <= 0 else { continue }
            let muzzle = V3(Float(c.x) + 0.5, Float(c.y) + 0.7, Float(c.z) + 0.5)
            var best: (Mob, Float)?
            for m in g.mobs.mobs where hostile(m, g) {
                let aim = m.pos + V3(0, m.height * 0.5, 0)
                let d = simd_length(aim - muzzle)
                guard d < range, d > 2, best == nil || d < best!.1 else { continue }
                guard simd_length(m.pos - g.player.pos) > 5 else { continue }          // the blast would catch the player
                guard w.canSee(muzzle + simd_normalize(aim - muzzle) * 0.9, aim) else { continue }
                best = (m, d)
            }
            guard let (m, d) = best else { continue }
            fire(g, from: muzzle, at: m.pos + V3(0, m.height * 0.5, 0) + m.vel * (d / 40), dist: d)
            cool[c] = reload
        }
        for c in gone { sites.remove(c); cool[c] = nil }
    }

    // A shell on a lobbed line to the target (40 blocks a second, gravity 20, aimed high by the drop).
    static func fire(_ g: Game, from muzzle: V3, at aim: V3, dist: Float) {
        let speed: Float = 40, grav: Float = 20
        let t = dist / speed
        var dir = aim - muzzle
        dir.y += 0.5 * grav * t * t
        let start = muzzle + simd_normalize(dir) * 0.9
        let sh = Shell(pos: start, vel: simd_normalize(dir) * speed, owner: -7, power: power)
        sh.gravity = grav
        sh.gentle = true
        g.world.ships.shells.append(sh)
        g.sfx(.shipCannon, 0.8, at: muzzle)
        g.particles.smoke(at: start)
    }
}

extension ItemRegistry {
    func registerWreckItems() {
        if !has(Wrecks.cannonball) {
            var d = ItemDef(Wrecks.cannonball, "Cannonball")
            d.sprite = Sprite(mask: "ball", base: 0x34363A, extras: [:])
            d.maxStack = 64
            add(d)
        }
    }
}

// P144 (Oct 12 20:56, "directions on how to repair them if it's your first time, or some way to make a mast"): the
// first time the player comes up to a raisable wreck, and the first time they steer a hull with nothing to drive it,
// a toast says what to do. Once a second (the HUD tick).
extension Wrecks {
    static let mastHow = "A mast: stand logs or fences upright on deck and hang wool on them - wool sails catch the wind while you steer (or fit a propeller and an engine)"
    static func hintTick(_ g: Game) {
        let st = Settings.shared
        if !st.mastHint, let s = g.world.ships.pilot, s.parent == nil, s.sails == 0, s.props.isEmpty, s.wheels.isEmpty, s.balloons == 0, s.flight == nil {
            st.mastHint = true
            g.onToast?("This hull has nothing to drive it. " + mastHow)
        }
        guard !st.wreckHint, g.dim.dim == .overworld, rottenID != AIR else { return }
        let p = g.player.pos, px = Int(floor(p.x)), py = Int(floor(p.y)), pz = Int(floor(p.z))
        let r = rottenID
        for y in (py - 6)...(py + 4) { for z in (pz - 6)...(pz + 6) { for x in (px - 6)...(px + 6) where g.world.rawBlock(x, y, z) == r {
            st.wreckHint = true
            g.onToast?("A wreck you can raise: replace its Rotten Planks with any planks, then place a Ship Helm on deck. " + mastHow)
            return
        } } }
    }
}
