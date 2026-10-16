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

    // T15: a broken wreck lost her bow above the hold, and she won't float with it open. A hull in a shipwreck
    // structure is "open" while two or more slices across her length rise less than four blocks over the keel
    // (the hatches midships still have decked sides; the snapped bow has nothing above its lowest planks).
    static func openBow(_ w: World, _ cells: [IVec3]) -> Bool {
        guard let c0 = cells.first, w.dim == .overworld, let sc = w.gen.structures,
              let st = sc.nearest("shipwreck", x: c0.x, z: c0.z, maxRegions: 1), st.contains(c0.x, c0.y, c0.z) else { return false }
        var lo = c0, hi = c0
        for c in cells { lo = IVec3(min(lo.x, c.x), min(lo.y, c.y), min(lo.z, c.z)); hi = IVec3(max(hi.x, c.x), max(hi.y, c.y), max(hi.z, c.z)) }
        let alongX = hi.x - lo.x >= hi.z - lo.z
        var top: [Int: Int] = [:]                          // slice -> highest cell
        for c in cells {
            let k = alongX ? c.x : c.z
            top[k] = max(top[k] ?? Int.min, c.y)
        }
        return top.values.filter { $0 < lo.y + 4 }.count >= 2
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
        if !fresh.isEmpty { g.onToast?("Auto-turret online") }
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
        guard g.dim.dim == .overworld else { return }
        clock += dt
        guard clock >= 0.25 else { return }
        let step = clock
        clock = 0
        if !g.world.ships.isEmpty { shipTick(g, step) }
        guard !sites.isEmpty else { return }
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

    // T15: on a ship too. A cannon of a hull next to a computer of the same hull is an auto-turret that rides with
    // her (the hull's own crew and passengers are never its targets).
    static var shipCool: [Int: Float] = [:]           // ship id * 256 + cannon index
    static var shipKnown: Set<Int> = []
    static var shipShots = 0
    static func shipTick(_ g: Game, _ step: Float) {
        for s in g.world.ships.list where !s.cannons.isEmpty && !s.kinematic && !s.wrecked {
            if s.role != nil && !s.captured { continue }   // a faction's vessel: its own gunners work the guns
            for (i, (p, _)) in s.cannons.enumerated() {
                let c = IVec3(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)))
                guard around.contains(where: { isComputer(s.grid.get(c.x + $0.x, c.y + $0.y, c.z + $0.z)) }) else { continue }
                let key = s.id &* 256 &+ i
                if !shipKnown.contains(key) {
                    shipKnown.insert(key)
                    if simd_length(s.pos - g.player.pos) < 64 { g.onToast?("Ship auto-turret online") }
                }
                let left = (shipCool[key] ?? 0) - step
                shipCool[key] = left
                guard left <= 0 else { continue }
                let muzzle = s.toWorld(p + V3(0, 0.2, 0))
                let root = s.root
                var best: (Mob, Float)?
                for m in g.mobs.mobs where hostile(m, g) {
                    let aim = m.pos + V3(0, m.height * 0.5, 0)
                    let d = simd_length(aim - muzzle)
                    guard d < range, d > 2, best == nil || d < best!.1 else { continue }
                    guard simd_length(m.pos - g.player.pos) > 5 else { continue }
                    if g.world.ships.standing(on: m.pos)?.root === root { continue }
                    guard g.world.canSee(muzzle + simd_normalize(aim - muzzle) * 0.9, aim) else { continue }
                    best = (m, d)
                }
                guard let (m, d) = best else { continue }
                fire(g, from: muzzle, at: m.pos + V3(0, m.height * 0.5, 0) + m.vel * (d / 40), dist: d, owner: root.id)
                shipCool[key] = reload
                shipShots += 1
            }
        }
    }

    // A shell on a lobbed line to the target (40 blocks a second, gravity 20, aimed high by the drop).
    static func fire(_ g: Game, from muzzle: V3, at aim: V3, dist: Float, owner: Int = -7) {
        let speed: Float = 40, grav: Float = 20
        let t = dist / speed
        var dir = aim - muzzle
        dir.y += 0.5 * grav * t * t
        let start = muzzle + simd_normalize(dir) * 0.9
        let sh = Shell(pos: start, vel: simd_normalize(dir) * speed, owner: owner, power: power)
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

// P144 / P263: the first time the player steers a hull that can't go. P328 (NO TEXT): the repairs book that listed each
// missing part, its recipe and where it goes is gone; the helm answers instead (Wrecks.hintTick), and the world's own
// ships and raisable wrecks show what a working hull carries. Once a second (the HUD tick).
extension Wrecks {
    static var guided: Set<Int> = []

    // What a built hull lacks (P263: the rules the physics uses: drives, engines for them, a balloon for each sixth of a
    // big hull or a rotor), or nil when it has what it needs. `canMove`: it moves already and lacks only lift.
    struct Guide { let canMove: Bool }
    static func guide(_ s: Ship) -> Guide? {
        // P325 (e): a commandeered Capital vessel (a kinematic hull) isn't a built ship: nothing to make up.
        if s.kinematic { return nil }
        let flier = s.name.contains("Dropship") || s.name.contains("Launch") || s.name.contains("Skiff") || s.balloons > 0 || !s.rotors.isEmpty || !s.wings.isEmpty
        let tonnes = s.mass                                       // (ship mass is in tonnes, ShipPhysics)
        let lift = max(1, Int((tonnes / ShipTuning.liftPerBalloon(tonnes)).rounded(.up)))
        let wheelDrives = s.wheels.isEmpty ? 0 : Int(ceil(sqrtf(Float(s.wheels.count))))
        let drives = s.props.count + wheelDrives
        let enginesNeeded = drives == 0 && s.rotors.isEmpty ? 0 : max(1, (drives + ShipTuning.perEngine - 1) / ShipTuning.perEngine)
        let rotor = !s.rotors.isEmpty
        let moves = s.helm != nil && !(drives == 0 && s.sails == 0 && !rotor) && !((drives > 0 || rotor) && s.engines < enginesNeeded)
        let flies = !flier || s.balloons >= lift || (rotor && s.engines > 0 && !s.props.isEmpty) || s.flight?.kind == .plane
        let lacksLift = flier && !flies && (!rotor || s.props.isEmpty)
        guard !moves || lacksLift else { return nil }
        return Guide(canMove: moves)
    }

    static func hintTick(_ g: Game) {
        // Taking the helm of a hull that can't go: a dead clunk at the helm and the hull groans; one that moves but is
        // short of lift only groans (its climb does nothing). Once per hull a session.
        if let s = g.world.ships.pilot, s.parent == nil, g.menu == nil, !guided.contains(s.id), let gd = guide(s) {
            guided.insert(s.id)
            Settings.shared.mastHint = true
            if !gd.canMove { g.sfx(.dispenseFail, 0.9, at: s.pos) }
            g.sfx(.hullCreak, 0.7, at: s.pos)
        }
        // P283 / NO TEXT (P328): the "a wreck you can raise" hint is gone, and with it its search of the 1900 blocks round
        // the player every frame (most of the HUD stage's time on the Quest replay); the wreck's rotten planks show it.
    }
}

// Q2c-console-19 (his notes: "How do I make a rocket?", "Service rifle, what does it shoot?"): the inventory tooltip's
// extra lines: for ammunition the guns it fits. P328 (NO TEXT): the "how do I get it" lines (the recipe, the furnace
// input, where ammunition comes from) are gone; the crafting book keeps the recipes. Worked out once per item.
enum ItemHelp {
    private static var cache: [ItemID: [String]] = [:]
    private static var statCache: [ItemID: [String]] = [:]
    // Q2c-console-48: what the item does, in numbers to compare: attack, what a pickaxe mines, armour, food, fuel.
    static func stats(_ s: ItemStack) -> [String] {
        if let c = statCache[s.item] { return c }
        var out: [String] = []
        let d = s.def, k = Items.key(s.item)
        func num(_ f: Float) -> String { f == f.rounded() ? "\(Int(f))" : String(format: "%.1f", f) }
        if Guns.index(s.item) == nil && d.attack > 1 {
            let hearts = d.attack / 2
            var line = "Attack: \(num(d.attack)) (\(num(hearts)) heart\(hearts == 1 ? "" : "s"))"
            if abs(d.attackSpeed - 4) > 0.05 { line += ", \(num(d.attackSpeed)) swings a second" }
            out.append(line)
        }
        if d.tool == .pickaxe {
            // (the game's own names for the ores: several are renamed from the reference)
            func n(_ k: String) -> String { Items.has(k) ? Items.name(Items.id(k)) : k.replacingOccurrences(of: "_", with: " ") }
            let mines = ["Mines \(n("stone")) and \(n("coal_ore"))", "Mines \(n("iron_ore")), \(n("copper_ore")) and \(n("lapis_ore"))",
                         "Mines \(n("gold_ore")), \(n("diamond_ore")), \(n("redstone_ore")) and \(n("emerald_ore"))",
                         "Mines \(n("obsidian")) and \(n("ancient_debris")) too", "Mines everything"]
            out.append(mines[max(0, min(mines.count - 1, d.tier))])
        }
        if d.armorSlot != nil && d.armor > 0 {
            out.append("Armour: +\(d.armor)" + (d.toughness > 0 ? ", toughness \(num(d.toughness))" : ""))
        }
        if let f = d.food {
            out.append("Food: +\(f.hunger) hunger" + (f.saturation >= Float(f.hunger) * 1.2 ? ", filling" : ""))

            if ["rotten_flesh", "chicken", "spider_eye", "pufferfish", "poisonous_potato"].contains(k) { out.append("Risky: can make you sick") }
        }
        let fuel = Recipes.fuel(s.item)
        if fuel > 0 && d.food == nil {
            out.append(fuel >= 200 ? "Fuel: smelts \(fuel / 200) item\(fuel / 200 == 1 ? "" : "s")" : "Fuel: smelts part of an item")
        }
        statCache[s.item] = out
        return out
    }
    static func lines(_ s: ItemStack) -> [String] {
        if let c = cache[s.item] { return c }
        var out: [String] = []
        let k = Items.key(s.item)
        if Guns.ammo.contains(where: { $0.0 == k }) {
            let guns = Guns.all.enumerated().filter { $0.element.ammo == k && !Guns.isRetired($0.offset) && Items.has($0.element.key) }.map { $0.element.name }
            if !guns.isEmpty { out.append("For: " + guns.joined(separator: ", ")) }
        }
        cache[s.item] = out
        return out
    }
}
