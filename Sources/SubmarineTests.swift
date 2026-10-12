import Foundation
import simd

// Submarine, mine and sonar checks (backlog C8; `questcheck --submarine-only`, and part of every questcheck run), in a
// walled pool of water built high over the ground:
//   kit      crafted from ship parts; used at the pool's edge it floats a submarine ahead with its tanks, helm and screw
//   ballast  diving on the helm takes it down, it holds that depth on its own, climbing brings it back to the surface
//   torpedo  its bow cannon under water looses a torpedo, which runs level and fast
//   sonar    a frigate overhead ignores a quiet boat, pings a loud one and drops two charges that burst at its depth
//   mine     a sea mine goes off when a player comes within reach
enum SubmarineTests {
    static func run(game g: Game, check: (Bool, String) -> Void) {
        let w = g.world
        let enc0 = w.ships.encounters, fly0 = g.player.flying
        w.ships.encounters = false
        let craft = Recipes.match([Items.id("iron_ingot"), Items.id("glass"), Items.id("iron_ingot"),
                                   Items.id("ship_helm"), Items.id("ship_engine"), Items.id("ship_propeller"),
                                   Items.id("ship_ballast"), Items.id("ship_ballast"), Items.id("ship_ballast")], 3, 3)?.result
        check(craft.map { Items.key($0.item) } == Submarine.kitKey, "submarine: iron, glass, a helm, an engine, a propeller and three ballast tanks make a Submarine Kit")

        let pos0 = g.player.pos, yaw0 = g.player.yaw, surv0 = g.survival, held0 = g.inventory.main[g.inventory.selected]
        let toast0 = g.onToast, health0 = g.health, safe0 = Submarine.creativeSafe, menu0 = g.menu
        var said = ""
        g.onToast = { said = $0 }
        var placed: [IVec3] = []
        let ships0 = w.ships.list.count
        defer {
            for q in placed { w.setBlock(q.x, q.y, q.z, AIR) }
            while w.ships.list.count > ships0, let s = w.ships.list.last { w.ships.remove(s) }
            w.ships.shells.removeAll(); w.ships.pilot = nil
            g.player.pos = pos0; g.player.yaw = yaw0; g.survival = surv0; g.inventory.main[g.inventory.selected] = held0
            g.onToast = toast0; g.health = health0; Submarine.creativeSafe = safe0; g.menu = menu0
            w.ships.encounters = enc0; g.player.flying = fly0; g.player.vel = .zero      // (later checks walk and fight on foot)
        }
        g.survival = true
        g.inventory.main[g.inventory.selected] = ItemStack(Items.id(Submarine.kitKey), 1)

        // A pool 11 wide, 69 long and 11 deep, walled in stone, high over the ground (long enough for a depth charge
        // thrown from 80 blocks off to come down in it).
        let fx = Int(floor(pos0.x)), fz = Int(floor(pos0.z))
        let py = min(CH - 40, w.topY(fx, fz) + 20)
        _ = w.loadSync(center: V3(Float(fx), Float(py), Float(fz) - 30), radius: 6)
        for z in (fz - 66)...(fz + 4) { for x in (fx - 6)...(fx + 6) { for y in py...(py + 12) {
            let wall = x == fx - 6 || x == fx + 6 || z == fz - 66 || z == fz + 4 || y == py
            w.setBlock(x, y, z, wall ? STONE : (y <= py + 11 ? WATER : AIR)); placed.append(IVec3(x, y, z))
        } } }
        let surfaceY = Float(py + 12)                      // the top of the water
        g.player.pos = V3(Float(fx) + 0.5, Float(py + 13), Float(fz) + 4.5); g.player.vel = .zero; g.player.yaw = 0; g.player.flying = true
        let used = g.submarineUse()
        guard let s = w.ships.list.dropFirst(ships0).first(where: { $0.name == Submarine.name }) else {
            check(false, "submarine: the kit floats a submarine at the pool's edge (\(used), '\(said)')"); return
        }
        func run(_ secs: Float) { for _ in 0..<Int(secs * 60) { w.ships.update(1.0 / 60, game: g) } }
        run(4)
        let floatY = s.pos.y
        let ahead = s.pos.z < Float(fz) - 3 && abs(s.pos.x - Float(fx) - 0.5) < 1.5
        let top = s.worldMax.y
        check(used && g.inventory.main[g.inventory.selected].isEmpty && ahead && s.ballast >= 10 && s.helm != nil && s.props.count >= 1
              && top > surfaceY - 0.5 && top < surfaceY + 3.5,
              String(format: "submarine: the kit floats a submarine ahead (kit spent), %d tanks, its deck %.1f over the water", s.ballast, top - surfaceY))

        // Dive on the helm, hold the depth with nobody steering, climb back up.
        s.autopilot = V3(0, 0, -1); run(3.5)
        s.autopilot = nil; run(0.6)
        let held = s.pos.y
        run(4)
        let drift = abs(s.pos.y - held), deep = floatY - s.pos.y
        let under = s.worldMax.y < surfaceY - 0.5
        s.autopilot = V3(0, 0, 1); run(5)
        s.autopilot = nil; run(2)
        let back = abs(s.pos.y - floatY)
        let surfaced = s.worldMax.y > surfaceY - 0.2
        check(deep > 2 && drift < 1 && under && surfaced,
              String(format: "submarine: dives %.1f blocks on the helm (all under: %@), holds it (%.2f drift in 4 s), climbs back to the surface (%@, %.2f off its float)",
                     deep, under ? "yes" : "no", drift, surfaced ? "deck out" : "still under", back))

        // A torpedo from a bow cannon under water.
        let bp = Submarine.blueprint()
        bp.set(0, 1, -5, "ship_cannon[south]")
        let t = w.ships.spawn(bp, at: V3(Float(fx) + 0.5, Float(py + 5), Float(fz) - 6), yaw: 0, name: "torpedo test", role: "")
        t.reload = 0
        w.ships.shells.removeAll()
        let fired = w.ships.fire(t, pitch: 0, game: g)
        let torp = w.ships.shells.first
        let t0 = torp?.pos ?? .zero
        w.ships.remove(t)
        if torp != nil { for _ in 0..<10 { w.ships.updateShells(0.05, game: g) } }
        let ran = torp.map { simd_length(V2($0.pos.x - t0.x, $0.pos.z - t0.z)) } ?? 0
        let level = torp.map { abs($0.pos.y - t0.y) } ?? 99
        check(fired == 1 && torp?.kind == 4 && ran > 6 && level < 0.3 && g.clock - Submarine.lastShot < 1,
              String(format: "submarine: a cannon under water looses a torpedo (kind %d), which runs %.1f blocks level (%.2f drop) in 0.5 s",
                     torp?.kind ?? -1, ran, level))
        w.ships.shells.removeAll()

        // Sonar: a frigate 80 blocks off hears a loud boat and not a quiet one, and its charges come down on it.
        s.autopilot = V3(0, 0, -1); run(2.5); s.autopilot = nil; run(0.5)
        let fb = Blueprint()
        fb.box(-2, 2, 0, 1, -2, 2, "oak_planks")
        let f = w.ships.spawn(fb, at: s.pos + V3(0, 22, -80), yaw: 0, name: "sonar frigate", role: "warfrigate")
        f.kinematic = true
        w.ships.pilot = s
        Submarine.lastPing = [:]; Submarine.lastShot = -100
        s.vel = V3(0, 0, -1)
        g.sonarTick()
        let quiet = w.ships.shells.isEmpty
        s.vel = V3(0, 0, -4)
        said = ""
        g.sonarTick()
        let charges = w.ships.shells.filter { $0.kind == 5 }
        w.ships.pilot = nil
        let depth = s.pos.y
        var last: [ObjectIdentifier: V3] = [:]
        var tt: Float = 0
        while tt < 14 && w.ships.shells.contains(where: { $0.kind == 5 }) {
            for c in charges { last[ObjectIdentifier(c)] = c.pos }
            w.ships.updateShells(0.05, game: g); tt += 0.05
        }
        let bursts = charges.compactMap { last[ObjectIdentifier($0)] }.filter { $0.y > s.worldMin.y - 2 && $0.y < s.worldMax.y + 2 }.count      // at its depth, or on its hull
        check(quiet && charges.count == 2 && said.contains("Sonar") && bursts == 2,
              "submarine: sonar ignores a quiet boat (\(quiet)), pings a loud one ('\(said)') and drops \(charges.count) charges, \(bursts) bursting at its depth (\(String(format: "%.1f", depth)); last seen at \(charges.compactMap { last[ObjectIdentifier($0)] }.map { String(format: "%.1f,%.1f,%.1f", $0.x, $0.y, $0.z) }), frigate keel \(String(format: "%.1f", f.worldMin.y)), \(String(format: "%.1f", tt)) s)")
        w.ships.remove(f)
        w.ships.remove(s)
        w.ships.shells.removeAll()

        // A sea mine in the middle of the pool goes off when a player swims within reach.
        let mine = IVec3(fx, py + 6, fz - 40)
        w.setBlock(mine.x, mine.y, mine.z, Blocks.id(Submarine.mineKey)); placed.append(mine)
        g.player.pos = V3(Float(fx) + 0.5, Float(py + 6), Float(fz) - 46.5)
        g.minesCheck()
        let calm = w.block(mine.x, mine.y, mine.z) == Blocks.id(Submarine.mineKey)
        g.player.pos = V3(Float(fx) + 0.5, Float(py + 5), Float(fz) - 41.5)
        g.health = 20
        g.minesCheck()
        let gone = w.block(mine.x, mine.y, mine.z) != Blocks.id(Submarine.mineKey)
        // A body falling out of the world (or far above it) has nothing to set off, and doesn't stop the check.
        g.player.pos = V3(Float(fx) + 0.5, -90, Float(fz) + 0.5); g.minesCheck()
        g.player.pos = V3(Float(fx) + 0.5, Float(CH + 40), Float(fz) + 0.5); g.minesCheck()
        check(calm && gone && g.health < 20, String(format: "submarine: a sea mine waits for a swimmer 6 away (%@) and goes off at 2 (%@), health %d",
                                                   calm ? "yes" : "no", gone ? "yes" : "no", g.health))
    }
}
