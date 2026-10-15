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
                    if simd_length(s.pos - g.player.pos) < 64 { g.onToast?("Ship auto-turret online: the computer aims the cannon at hostiles within \(Int(range)) blocks") }
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

// P144 (Oct 12 20:56, "directions on how to repair them if it's your first time, or some way to make a mast"): the
// first time the player comes up to a raisable wreck, and the first time they steer a hull with nothing to drive it,
// a toast says what to do. Once a second (the HUD tick).
extension Wrecks {
    static var guided: Set<Int> = []

    // "3 Iron Ingot, 1 Furnace, 3 Cobblestone" for the first recipe that makes `key`.
    static func recipeText(_ key: String) -> String {
        guard let r = Recipes.all.first(where: { Items.key($0.result.item) == key }) else { return "found, not crafted" }
        var n: [String: Int] = [:], order: [String] = []
        for c in (r.shapeless.isEmpty ? r.cells.compactMap { $0 } : r.shapeless) {
            if n[c] == nil { order.append(c) }
            n[c, default: 0] += 1
        }
        func name(_ k: String) -> String {
            if k.hasPrefix("#") { return "any " + k.dropFirst().replacingOccurrences(of: "_", with: " ") }
            return Items.has(k) ? Items.name(Items.id(k)) : k.replacingOccurrences(of: "_", with: " ")
        }
        return order.map { "\(n[$0]!) \(name($0))" }.joined(separator: ", ") + (r.shapeless.isEmpty ? " (crafting table)" : "")
    }

    // The guide's pages and whether the hull can already move, or nil when it has what it needs (P263, Oct 14
    // 12:17-12:18, a repeat of P225: "lift plumes 0 of 10", "weighs 600 tons", "why do I need lift if it already
    // drove"). The first page lists what the hull has and what it lacks, split into moving and flying; each missing part
    // gets a page saying what it does, how many more, its recipe and where it goes; weight is given in blocks with the
    // lift rule the physics uses (ShipTuning.liftPerBalloon), and the rotor is offered as the other way to fly.
    struct Guide { let pages: [String]; let canMove: Bool }
    static func guide(_ s: Ship) -> Guide? {
        let flier = s.name.contains("Dropship") || s.name.contains("Launch") || s.name.contains("Skiff") || s.balloons > 0 || !s.rotors.isEmpty || !s.wings.isEmpty
        let tonnes = s.mass                                       // (ship mass is in tonnes, ShipPhysics)
        let per = ShipTuning.liftPerBalloon(tonnes)
        let lift = max(1, Int((tonnes / per).rounded(.up)))
        let wheelDrives = s.wheels.isEmpty ? 0 : Int(ceil(sqrtf(Float(s.wheels.count))))
        let drives = s.props.count + wheelDrives
        let enginesNeeded = drives == 0 && s.rotors.isEmpty ? 0 : max(1, (drives + ShipTuning.perEngine - 1) / ShipTuning.perEngine)
        let rotor = !s.rotors.isEmpty
        let powered = s.engines >= enginesNeeded
        let canMove = s.helm != nil && ((drives > 0 && s.engines > 0) || s.sails > 0)
        let flies = !flier || s.balloons >= lift || (rotor && s.engines > 0 && !s.props.isEmpty) || s.flight?.kind == .plane
        typealias Line = (key: String, label: String, have: Int, need: Int, what: String, where: String)
        var move: [Line] = [], fly: [Line] = []
        if s.helm == nil {
            move.append(("ship_helm", "Ship Helm", 0, 1, "you steer from it: take it and the throttle and steering are yours",
                         "on deck, where you stand to steer; it faces the bow"))
        }
        if drives == 0 && s.sails == 0 && !rotor {
            move.append(("ship_propeller", "Propeller", 0, 1, "pushes the hull along when an engine turns it",
                         "on the stern (the back face), behind the hull, facing out"))
        }
        if (drives > 0 || rotor) && !powered {
            move.append(("ship_engine", "Engine", s.engines, max(1, enginesNeeded),
                         "turns the propellers, wheels and rotor; one engine drives up to \(ShipTuning.perEngine) propellers or wheels",
                         "anywhere inside the hull, touching it"))
        }
        if flier && !flies {
            if rotor {
                if s.props.isEmpty {
                    fly.append(("ship_propeller", "Tail Propeller", 0, 1, "stops a rotor craft spinning round under its rotor (the tail rotor)",
                                "at the tail, facing sideways"))
                }
            } else {
                fly.append(("ship_balloon", "Lift Balloon", s.balloons, lift,
                            "holds the hull up in the air: \(Int(per)) tonnes each for this hull; with enough of them the climb control lifts it",
                            "on the deck or the roof, spread out (any number of blocks high)"))
            }
        }
        guard !move.isEmpty || !fly.isEmpty else { return nil }
        func have(_ n: Int, _ one: String) -> String { "\(n) \(one)\(n == 1 ? "" : "s")" }
        var has: [String] = [s.helm != nil ? "helm" : "no helm"]
        if !s.props.isEmpty { has.append(have(s.props.count, "propeller")) }
        if s.engines > 0 || drives > 0 { has.append(have(s.engines, "engine")) }
        if !s.wheels.isEmpty { has.append("wheels") }
        if s.sails > 0 { has.append("sails") }
        if s.balloons > 0 { has.append(have(s.balloons, "balloon")) }
        if rotor { has.append("a rotor head") }
        var first = "\(s.name.uppercased())\n\nHas: \(has.joined(separator: ", ")).\n\n"
        if move.isEmpty { first += "It can already \(s.sails > 0 && drives == 0 ? "sail" : "move") under its own power.\n\n" }
        else { first += "To move it needs:\n" + move.map { "- \($0.label): \($0.have) of \($0.need)" }.joined(separator: "\n") + "\n\n" }
        if !fly.isEmpty {
            first += "To fly it also needs:\n" + fly.map { "- \($0.label): \($0.have) of \($0.need)" }.joined(separator: "\n")
            if !rotor { first += "\n(or a Rotor Head instead of balloons: see Weight and Lift)" }
            first += "\n\n"
        }
        first += "Next pages: each part, what it does, its recipe and where it goes. Then take the helm again."
        var pages = [first]
        for l in move + fly {
            pages.append("\(l.label.uppercased())\n\nWhat it does: \(l.what).\n\nNeeded: \(max(1, l.need - l.have)) more\n\nRecipe: \(recipeText(l.key))\n\nWhere: \(l.where)")
        }
        if flier && !flies && !rotor {
            pages.append("WEIGHT AND LIFT\n\nThis hull is \(s.blockCount) blocks, and each block weighs about a tonne: \(Int(tonnes.rounded())) tonnes. "
                + "A balloon holds up 60 tonnes, or a sixth of the hull on a big one, so this hull needs \(lift). Breaking off loose or torn blocks lowers that.\n\n"
                + "Or fly it like a helicopter: one Rotor Head on the roof over the middle, an Engine, and a Propeller facing sideways at the tail. "
                + "A rotor lifts a hull of any size.\n\nRotor Head: \(recipeText("ship_rotor"))")
        }
        if !flier && move.contains(where: { $0.key == "ship_propeller" }) { pages.append("OR SAILS\n\n" + mastHow) }
        // P225: cannons need shot, and nothing said where it goes.
        if !s.cannons.isEmpty { pages.append(cannonHow(s.cannons.count)) }
        return Guide(pages: pages, canMove: move.isEmpty)
    }

    static func cannonHow(_ n: Int) -> String {
        "CANNON SHOT\n\nThis hull carries \(n) cannon\(n == 1 ? "" : "s"). Each shot takes one Cannonball from the pack of whoever steers: "
            + "there is no loading slot, keep them in your inventory.\n\nRecipe: \(recipeText(cannonball)) makes 4.\n\n"
            + "Fire: attack while at the helm; every cannon that is ready fires and takes one ball."
    }
    static let mastHow = "A mast: stand logs or fences upright on deck and hang wool on them - wool sails catch the wind while you steer (or fit a propeller and an engine)"
    static func hintTick(_ g: Game) {
        let st = Settings.shared
        // P220 (Oct 13 19:08-19:14, "the engine block and light panel requirements are unclear"): taking the helm of a
        // hull that can't go (no drive, or propellers with no engine, or too few balloons to lift a flier) opens the
        // repair guide: each missing part, how many, its recipe and where it goes. Once per hull a session.
        if let s = g.world.ships.pilot, s.parent == nil, g.menu == nil, !guided.contains(s.id), let gd = guide(s) {
            guided.insert(s.id)
            st.mastHint = true
            if gd.canMove {
                // P263 (g): it drives or sails already: no book in his face, the guide waits in the journal.
                g.logDocument("Repairs: \(s.name)", gd.pages, cat: .notes)
                g.onToast?("The \(s.name) can move, but not fly yet: what it needs is in your journal (Repairs)")
            } else {
                var book = ItemStack(Items.id("written_book"), 1)
                book.label = "Repairs: \(s.name)"
                book.pages = gd.pages
                g.openMenu(BookMenu(game: g, stack: book, source: .hand(-1)))
            }
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

// Q2c-console-19 (his notes: "How do I make a rocket?", "Service rifle, what does it shoot?"): the inventory tooltip's
// "how do I get it" lines: the first crafting recipe ("Made from: ..."), a furnace input ("Smelt: ..."), and for
// ammunition the guns it fits and where it comes from. Worked out once per item.
enum ItemHelp {
    private static var cache: [ItemID: [String]] = [:]
    static func lines(_ s: ItemStack) -> [String] {
        if let c = cache[s.item] { return c }
        var out: [String] = []
        let k = Items.key(s.item)
        if Recipes.all.contains(where: { Items.key($0.result.item) == k }) {
            out.append("Made from: " + Wrecks.recipeText(k))
        } else if let src = Recipes.smelting.first(where: { $0.value == k }) ?? Recipes.smeltingExtra.first(where: { $0.value == k }) {
            out.append("Smelt: \(Items.has(src.key) ? Items.name(Items.id(src.key)) : src.key.replacingOccurrences(of: "_", with: " ")) in a furnace")
        }
        if Guns.ammo.contains(where: { $0.0 == k }) {
            let guns = Guns.all.enumerated().filter { $0.element.ammo == k && !Guns.isRetired($0.offset) && Items.has($0.element.key) }.map { $0.element.name }
            if !guns.isEmpty { out.append("For: " + guns.joined(separator: ", ")) }
            out.append("Get it: " + Guns.ammoSource(k))
        }
        cache[s.item] = out
        return out
    }
}
