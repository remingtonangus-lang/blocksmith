import Foundation
import simd

// D51: track one objective; contract, bounty, horse, ship and vehicle markers; notes stamped on the map.
//   tracking   Pause > Track a Target lists what you can follow: the story's next objective, your taken contracts,
//              the nearest gang leader at large (his bounty), your horse, your ships and your vehicles, and your notes
//              and waypoints. Pick one: a marker rides the top of the HUD at its bearing with the distance (at the
//              edge, with an arrow, when it's behind you), and a gold beacon of light rises over it in the world
//              (within 600 blocks). With nothing picked, the story's objective is followed. Kept with the world.
//   markers    taken contracts ($), the gang leader at large (X), your horse (Y), ships (^) and vehicles (=) are
//              kept on the world map as they move.
//   notes      the same list stamps a note where you stand (Camp, Danger, Loot, Ore, Water, Home) as a * on the map,
//              or clears the notes and waypoints within 32 blocks.
enum Waymarks {
    struct Target { let kind: String; let key: String; let name: String; let pos: V3 }
    static let noteNames = ["Camp", "Danger", "Loot", "Ore", "Water", "Home"]
    static let beaconRange: Float = 600
    static var cache: (Double, Target?) = (-1e9, nil)
    static var marksAt: Double = -1e9
    static var beacons = 0                                     // (harness)

    static var trackedKey: String? {
        get { TownLaw.state.tracked }
        set { TownLaw.state.tracked = newValue }
    }

    static func v(_ x: Int, _ z: Int, _ y: Float) -> V3 { V3(Float(x) + 0.5, y, Float(z) + 0.5) }

    // Everything you could follow now.
    static func candidates(_ g: Game) -> [Target] {
        guard g.dim.dim == .overworld else { return [] }
        let py = g.player.pos.y
        var out: [Target] = []
        if let t = Spine.target { out.append(Target(kind: "objective", key: "objective", name: "Story: " + t.name, pos: v(t.x, t.z, py))) }
        for (key, c) in Contracts.all where c.taken && !c.paid && !c.failed {
            let at = c.done ? nil : (c.target ?? c.destAt)
            guard let a = at, a.count >= 2 else { continue }
            let what = c.kind == "camp" ? "Clear a bandit camp" : (c.kind == "defend" ? "Defend \(c.board)" : "\(c.kind.capitalizedFirst) to \(c.dest ?? "town")")
            out.append(Target(kind: "contract", key: key, name: "Contract: " + what, pos: v(a[0], a[1], py)))
        }
        if let (gg, _, _) = GangLeaders.wanted(g, from: IVec3(Int(g.player.pos.x), 0, Int(g.player.pos.z))), let p = leaderPos(g, gg) {
            out.append(Target(kind: "bounty", key: gg.leader, name: "Bounty: \(gg.leader) (\(Money.format(gg.bounty)))", pos: p))
        }
        if let h = horsePos(g) { out.append(Target(kind: "my_horse", key: "horse", name: "Your horse", pos: h.1)) }
        for s in g.world.ships.list where g.world.ships.isYours(s) && !s.wrecked {
            let land = VehicleDepot.usesFuel(s)
            out.append(Target(kind: land ? "my_vehicle" : "my_ship", key: "\(s.id)", name: (land ? "Vehicle: " : "Ship: ") + s.name, pos: s.pos))
        }
        for m in MapCache.shared.marks where m.kind == "note" || m.kind == "pin" {
            out.append(Target(kind: m.kind, key: "\(m.x),\(m.z)", name: (m.kind == "note" ? "Note: " : "Waypoint: ") + (m.name ?? "\(m.x), \(m.z)"), pos: v(m.x, m.z, py)))
        }
        return out
    }

    static func leaderPos(_ g: Game, _ gg: GangLeaders.Gang) -> V3? {
        guard let sc = g.world.gen.structures else { return nil }
        let px = Int(g.player.pos.x), pz = Int(g.player.pos.z)
        return sc.nearest("wild_camp", x: px, z: pz, maxRegions: 3, accept: { $0.kind == "camp_outlaws" && GangLeaders.gang(at: $0.anchor).leader == gg.leader })
            .map { v($0.anchor.x, $0.anchor.z, Float($0.anchor.y)) }
    }

    // The bonded horse, loaded or stored out in the world.
    static func horsePos(_ g: Game) -> (String, V3)? {
        guard g.horseBond != 0 else { return nil }
        if let r = g.riding, r.bond == g.horseBond { return nil }
        if let m = g.mobs.mobs.first(where: { $0.bond == g.horseBond && $0.health > 0 }) { return (m.customName ?? "Your horse", m.pos) }
        for (_, list) in g.mobs.stored {
            if let r = list.first(where: { $0.extra?["bond"] == g.horseBond }), r.p.count >= 3 { return (r.name ?? "Your horse", V3(r.p[0], r.p[1], r.p[2])) }
        }
        return nil
    }

    // The target being followed: the one picked, or the story's objective.
    static func current(_ g: Game) -> Target? {
        if g.clock - cache.0 < 0.5 { return cache.1 }
        let all = candidates(g)
        var t: Target?
        if let k = trackedKey {
            let parts = k.split(separator: "|", maxSplits: 1).map(String.init)
            if parts.count == 2 { t = all.first { $0.kind == parts[0] && $0.key == parts[1] } }
        }
        if t == nil { t = all.first { $0.kind == "objective" } }
        cache = (g.clock, t)
        return t
    }

    static func track(_ g: Game, _ t: Target?) {
        trackedKey = t.map { $0.kind + "|" + $0.key }
        cache = (-1e9, nil)
        g.onToast?(t.map { "Tracking \($0.name)" } ?? "Tracking the story's objective")
    }

    // MARK: HUD and beacon

    // Renderer.buildHUD: (bearing from straight ahead in radians, label, colour) of the tracked target.
    static func hud(_ g: Game) -> (Float, String, V4)? {
        guard g.dim.dim == .overworld, let t = current(g) else { return nil }
        let dx = t.pos.x - g.player.pos.x, dz = t.pos.z - g.player.pos.z
        let d = (dx * dx + dz * dz).squareRoot()
        guard d > 4 else { return nil }
        var rel = atan2f(dx, -dz) + g.player.yaw
        rel = rel.truncatingRemainder(dividingBy: 2 * .pi)
        if rel > .pi { rel -= 2 * .pi } else if rel < -.pi { rel += 2 * .pi }
        let name = t.name.split(separator: ":").last.map { String($0).trimmingCharacters(in: .whitespaces) } ?? t.name
        let label = "\(name) \(Int(d)) m"
        return (rel, label, MapCache.style(t.kind).1)
    }

    // Once a second (TownLaw.tick): the beacon over the target, and the map's moving marks every five seconds.
    static func tick(_ g: Game) {
        guard g.dim.dim == .overworld else { return }
        if let t = current(g) {
            let d = simd_length(V2(t.pos.x - g.player.pos.x, t.pos.z - g.player.pos.z))
            if d > 12 && d < beaconRange {
                let x = Int(floor(t.pos.x)), z = Int(floor(t.pos.z))
                let ground: Float = g.world.isLoaded(x, z) ? Float(g.world.topY(x, z)) + 1 : t.pos.y
                let col = MapCache.style(t.kind).1
                let smoke = Int(Tex.id("smoke"))
                let size: Float = 0.5 + d / 120
                for i in 0..<20 {
                    let h = Float(i) * (2 + d / 60)
                    g.particles.add(Particle(pos: V3(t.pos.x, ground + h, t.pos.z), vel: V3(0, 1.5, 0), life: 1.1, maxLife: 1.1, layer: smoke,
                                             uv0: .zero, uvSize: 1, size: size * (0.8 + 0.2 * sinf(Float(g.clock) * 3 + Float(i))), gravity: 0,
                                             color: V3(col.x, col.y, col.z) * 1.4, collide: false, glow: true))   // Q2: lit, reads at night
                }
                beacons += 1
            }
        }
        guard g.clock - marksAt >= 5 else { return }
        marksAt = g.clock
        func q(_ f: Float) -> Int { Int(floor(f / 8)) * 8 + 4 }        // to 8 blocks (fewer map writes as things move)
        let all = candidates(g)
        for kind in ["contract", "bounty", "my_horse", "my_ship", "my_vehicle"] {
            let list = all.filter { $0.kind == kind }.prefix(12).map { t in
                MapCache.Mark(kind: kind, x: q(t.pos.x), z: q(t.pos.z), name: t.name.split(separator: ":").last.map { String($0).trimmingCharacters(in: .whitespaces) })
            }
            MapCache.shared.setMarks(g, kind: kind, Array(list))
        }
    }
}

extension Game {
    func openTrackMenu() { openMenu(TrackMenu(game: self)) }
}

final class TrackMenu: ListMenu {
    enum Act { case track(Waymarks.Target?), note(String), clear }
    var acts: [Act] = []
    init(game g: Game) {
        super.init("Track a Target", game: g)
        subtitle = g.dim.dim == .overworld ? "Follow one on the HUD and by its beacon, or stamp a note on the map" : "Nothing to track out here"
    }
    override var rows: [Row] {
        acts = []
        var out: [Row] = []
        let cur = Waymarks.current(game)
        let p = game.player.pos
        for t in Waymarks.candidates(game) {
            acts.append(.track(t))
            let on = cur?.kind == t.kind && cur?.key == t.key
            let d = Int(simd_length(V2(t.pos.x - p.x, t.pos.z - p.z)))
            out.append(Row(name: t.name, detail: on ? "Tracking" : "\(d) m", value: "", enabled: true, good: on))
        }
        if Waymarks.trackedKey != nil {
            acts.append(.track(nil))
            out.append(Row(name: "Back to the story's objective", detail: "", value: "", enabled: true, good: true))
        }
        if game.dim.dim == .overworld {
            for n in Waymarks.noteNames {
                acts.append(.note(n))
                out.append(Row(name: "Stamp a note here: \(n)", detail: "On the map", value: "", enabled: true, good: true))
            }
            acts.append(.clear)
            out.append(Row(name: "Clear notes and waypoints here", detail: "Within 32 blocks", value: "", enabled: true, good: false))
        }
        return out
    }
    override func pressed(_ i: Int) {
        _ = rows
        guard i < acts.count else { return }
        let p = game.player.pos
        switch acts[i] {
        case .track(let t):
            Waymarks.track(game, t); game.closeMenu()
        case .note(let n):
            MapCache.shared.addNote(game, x: Int(floor(p.x)), z: Int(floor(p.z)), name: n)
            say("\(n) stamped on the map", good: true)
        case .clear:
            let n = MapCache.shared.removeNotes(game, x: Int(floor(p.x)), z: Int(floor(p.z)), near: 32)
            say(n > 0 ? "Cleared \(n) from the map" : "Nothing marked here", good: n > 0)
        }
    }
}
