import Foundation
import simd

// Radio spoofing (backlog C6): at the command console of a Greywall base or a Capital citadel, pose as the garrison
// on its radio net and ask for help. The faction really sends it: a supply crate dropped into the yard, or a fire
// mission (three shells, marked by red smoke) on your nearest waypoint. It works for a while: every request raises
// the net's suspicion (more for a repeat within a minute, a lot for an odd one: shells on their own base); it cools
// slowly. When it fills they know: the faction's bases go on alert, a hunter squad led by a Spec Ops trooper comes
// for you, and that console's net never answers again. Saved per world (Effects: "radioSus", "radioBurned").
enum RadioNet {
    static let perRequest: Float = 25
    static let repeatExtra: Float = 15        // a second request within `repeatWindow`
    static let repeatWindow: Double = 60
    static let oddExtra: Float = 60           // a fire mission on their own base
    static let coolPerSecond: Float = 1.0 / 20
    static let afterFoundOut: Float = 60         // where suspicion sits once the cover is blown (then cools as usual)
    static let dropDelay: Float = 8
    static let strikeDelay: Float = 6
    static let strikeReach: Float = 600       // waypoints farther than this from the console are out of the guns' range
    static let alertFor: Double = 600         // seconds the faction stays on alert once it knows
    static let hunterRange: Float = 50

    static func level(_ s: Float) -> String { s < 25 ? "calm" : s < 50 ? "wary" : s < 100 ? "suspicious" : "they know" }

    // The console's net: whose it is, its key, where a drop lands.
    struct Net { var faction: Faction; var key: String; var yard: V3; var area: (V3) -> Bool }

    static func net(_ g: Game, at p: IVec3) -> Net? {
        let q = V3(Float(p.x) + 0.5, Float(p.y), Float(p.z) + 0.5)
        if g.world.dim == .overworld, let sc = g.world.gen.structures,
           let s = sc.nearest(Greywall.kind, x: p.x, z: p.z, maxRegions: 1), s.contains(p.x, p.y, p.z) {
            let (cx, cz) = Greywall.centre(s)
            let t = Greywall.Tier.of(s), S = Greywall.yardY(s)
            let site = GreywallAlarmState.Site(cx: cx, cz: cz, S: S, tier: t)
            return Net(faction: .greywall, key: "greywall:\(cx),\(cz)", yard: V3(Float(cx) + 0.5, Float(S + 1), Float(cz + t.half - 5) + 0.5),
                       area: { Greywall.inside(site, $0, pad: 2) })
        }
        if let r = g.bases.records.values.first(where: { $0.inside(q) }) {
            return Net(faction: .steelhold, key: r.key, yard: r.plaza, area: { r.inside($0) })
        }
        return nil
    }
}

final class RadioState {
    var suspicion: [Int: Float] = [:]          // faction raw value -> 0...100
    var last: [Int: Double] = [:]              // faction -> clock of its last request
    var burned: Set<String> = []               // consoles whose net never answers again
    var alertUntil: [Int: Double] = [:]        // faction -> clock its bases stay on alert until
    var drops: [(at: V3, t: Float, table: String)] = []

    func alerted(_ f: Faction, _ clock: Double) -> Bool { (alertUntil[f.rawValue] ?? -1) > clock }

    // Effects save/load (strings in the world's extra dictionary).
    var saved: (String, String) {
        (suspicion.filter { $0.value > 0 }.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ";"),
         burned.sorted().joined(separator: ";"))
    }
    func load(_ sus: String, _ burnt: String) {
        suspicion = [:]
        for part in sus.split(separator: ";") {
            let kv = part.split(separator: ":")
            if kv.count == 2, let k = Int(kv[0]), let v = Float(kv[1]) { suspicion[k] = v }
        }
        burned = Set(burnt.split(separator: ";").map(String.init))
    }
}

extension Game {
    var radio: RadioState { bases.radio }

    // Use on a console: inside a faction's base, the radio net opens (and the console's radar picture as before).
    func radioUse(_ p: IVec3) -> Bool {
        guard Blocks.key(Blocks.groupBase[Int(world.block(p.x, p.y, p.z))]) == "command_console", let n = RadioNet.net(self, at: p) else { return false }
        openMenu(RadioMenu(game: self, console: p, net: n))
        return true
    }

    // A request on a net. Returns what the radio says back.
    @discardableResult
    func radioRequest(_ n: RadioNet.Net, strike: Bool) -> (ok: Bool, text: String) {
        let f = n.faction.rawValue
        if radio.burned.contains(n.key) { return (false, "Unknown station. Get off this net.") }
        var target = n.yard
        var odd = false
        if strike {
            guard let pin = MapCache.shared.nearestPin(player.pos.x, player.pos.z) else {
                return (false, "Fire mission needs a grid: set a waypoint on your map first")
            }
            target = V3(Float(pin.x) + 0.5, 0, Float(pin.z) + 0.5)
            guard simd_length(V2(target.x - n.yard.x, target.z - n.yard.z)) <= RadioNet.strikeReach else {
                return (false, "That grid is out of our guns' range (600 blocks)")
            }
            let x = Int(floor(target.x)), z = Int(floor(target.z))
            guard world.isLoaded(x, z) else { return (false, "Can't range that grid: go closer to it") }
            target.y = Float(world.topY(x, z) + 1)
            odd = n.area(target)
        }
        var add = RadioNet.perRequest
        if let t = radio.last[f], clock - t < RadioNet.repeatWindow { add += RadioNet.repeatExtra }
        if odd { add += RadioNet.oddExtra }
        radio.last[f] = clock
        let sus = min(100, (radio.suspicion[f] ?? 0) + add)
        radio.suspicion[f] = sus
        if sus >= 100 { radioFoundOut(n); return (false, "\"Station, authenticate.\" They know. Hunters are coming.") }
        if strike {
            for k in 0..<3 {
                let off = V3(Rand.float(in: -4...4), 0, Rand.float(in: -4...4))
                ashStrikes.append(AshStrike(at: target + off, t: RadioNet.strikeDelay + Float(k) * 0.6, power: 1.3, from: nil,
                                            by: n.faction == .greywall ? "Greywall artillery" : "Capital artillery"))
            }
            return (true, "\"Fire mission received. Shot, over.\" Shells on your waypoint in \(Int(RadioNet.strikeDelay)) s")
        }
        let x = Int(floor(n.yard.x)), z = Int(floor(n.yard.z))
        let ground = world.isLoaded(x, z) ? Float(world.topY(x, z) + 1) : n.yard.y
        radio.drops.append((V3(n.yard.x, ground, n.yard.z), RadioNet.dropDelay, n.faction == .greywall ? "greywall_supply" : "steelhold_supply"))
        return (true, "\"Copy, a crate is on its way to your yard.\"")
    }

    // Found out: the console's net is dead, the faction on alert, a hunter squad on its way.
    func radioFoundOut(_ n: RadioNet.Net) {
        radio.burned.insert(n.key)
        radio.suspicion[n.faction.rawValue] = RadioNet.afterFoundOut   // cools from here: the next console isn't burnt on its first call
        radio.alertUntil[n.faction.rawValue] = clock + RadioNet.alertFor
        for k in bases.records.keys where n.faction == .steelhold {
            if let r = bases.records[k], simd_length(r.centre - player.pos) < 1500, r.alert.rawValue < BaseAlert.alert.rawValue { bases.records[k]?.alert = .alert }
        }
        let a = Rand.float(in: 0..<(2 * .pi))
        let c = player.pos + V3(cosf(a), 0, sinf(a)) * RadioNet.hunterRange
        let tag = n.faction == .greywall ? "@grey" : ""
        for (i, k) in ["soldier_officer", "soldier_trooper", "soldier_trooper", "soldier_marksman"].enumerated() {
            let x = Int(floor(c.x)) + i - 2, z = Int(floor(c.z)) + (i % 2)
            let y = world.isLoaded(x, z) ? Float(world.topY(x, z) + 1) : player.pos.y
            guard let m = Mob.structureMob(k + tag, at: V3(Float(x) + 0.5, y, Float(z) + 0.5)) else { continue }
            if n.faction == .steelhold { m.faction = Faction.steelhold.rawValue }
            m.leash = nil
            if i == 0 { m.setTroop(.specOps, rearm: true) }
            m.persistent = false
            m.aggro = true
            m.soldierBrain.ready = true
            m.soldierBrain.lastSeen = player.pos; m.soldierBrain.seenAgo = 0
            m.lockTime = 60
            m.customName = i == 0 ? "Hunter Lead" : nil
            mobs.mobs.append(m)
        }
        onToast?("Your radio cover is blown: a hunter squad is coming for you")
        sfx(.gun(10), 1, at: player.pos)
    }

    // Every frame (CapitalBases.basesTick): suspicion cools, crates land, shells fall (outside the Deep, which runs its own).
    func radioTick(_ dt: Float) {
        for k in 0...6 { if let v = radio.suspicion[k], v > 0, v < 100 { radio.suspicion[k] = max(0, v - RadioNet.coolPerSecond * dt) } }   // (no copy of the dictionary per frame)
        var i = 0
        while i < radio.drops.count {
            radio.drops[i].t -= dt
            let d = radio.drops[i]
            if d.t > 0 {
                if Rand.float(in: 0..<1) < dt * 10 {                         // green smoke where it will land
                    particles.add(Particle(pos: d.at + V3(Rand.float(in: -0.3...0.3), 0.2, Rand.float(in: -0.3...0.3)), vel: V3(0, 2.5, 0), life: 0.6,
                                           maxLife: 0.6, layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1, size: 0.2, gravity: -1,
                                           color: V3(0.3, 2.2, 0.4), collide: false, glow: true))
                }
                i += 1; continue
            }
            radio.drops.remove(at: i)
            radioLand(d.at, table: d.table)
        }
        if dim.dim != .deep && !ashStrikes.isEmpty { ashShellTick(dt) }
    }

    // A crate lands: a chest on the first free cell at the drop point, filled from the table.
    func radioLand(_ at: V3, table: String) {
        var p = IVec3(Int(floor(at.x)), Int(floor(at.y)), Int(floor(at.z)))
        guard world.isLoaded(p.x, p.z) else { return }
        var n = 0
        while world.block(p.x, p.y, p.z) != AIR && n < 8 { p.y += 1; n += 1 }
        world.setBlock(p.x, p.y, p.z, Blocks.id("chest"))
        let be = world.entity(p, .chest)
        var rng = SRng(UInt64(bitPattern: Int64(p.x &* 73856093 ^ p.z &* 19349663 ^ Int(clock))) | 1)
        Loot.fill(be.container, table: table, rng: &rng)
        particles.explosion(at: V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5), power: 0.2)
        sfx(.chestClose, 1, at: V3(Float(p.x) + 0.5, Float(p.y), Float(p.z) + 0.5))
        onToast?("A supply crate lands")
    }
}

final class RadioMenu: ListMenu {
    let console: IVec3
    let net: RadioNet.Net
    init(game g: Game, console p: IVec3, net n: RadioNet.Net) {
        console = p; net = n
        super.init(n.faction == .greywall ? "Greywall Radio Net" : "Capital Radio Net", game: g)
        subtitle = "You are posing as this base's garrison."
        say(g.radio.burned.contains(n.key) ? "Unknown station. Get off this net." : "The net is listening.", good: !g.radio.burned.contains(n.key))
    }
    var sus: Float { game.radio.suspicion[net.faction.rawValue] ?? 0 }
    override var rows: [Row] {
        corner = "Suspicion: " + RadioNet.level(sus)
        let dead = game.radio.burned.contains(net.key)
        return [
            Row(name: "Listen in", detail: "Patrols and sites on your radar for 30 s", value: "", enabled: true),
            Row(name: "Request a supply drop", detail: "A crate into the yard", value: dead ? "dead" : "+25", enabled: !dead, good: !dead),
            Row(name: "Fire mission on my waypoint", detail: "Three shells, 600 blocks reach", value: dead ? "dead" : "+25", enabled: !dead, good: !dead),
        ]
    }
    override func pressed(_ i: Int) {
        switch i {
        case 0:
            _ = game.consoleUse(console)
            game.closeMenu()
        case 1, 2:
            let r = game.radioRequest(net, strike: i == 2)
            say(r.text, good: r.ok)
        default: break
        }
    }
    override func tick() {
        super.tick()
        let c = V3(Float(console.x) + 0.5, Float(console.y), Float(console.z) + 0.5)
        if simd_length(c - game.player.pos) > 6 { game.closeMenu() }
    }
}
