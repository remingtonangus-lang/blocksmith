import Foundation
import simd

// FAILURES.md 1's check (questcheck --garagedoor, and the full suite), tried the way he will: at a fresh ammo depot's
// first magazine, the garage door is one panel five wide and four high; used from outside, it swings up and in as one
// body and lies under the vault's crown; then the whole opening is clear for a vehicle (a box 4.4 wide, 3.9 high driven
// through), he walks in and back out, and the inside button shuts it (the opening closed again). An old P507 shutter
// (a 3 by 3 of full cells, as his World saved them) opens and shuts the same way.
enum GarageDoorCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        guard g.dim.dim == .overworld, let gen = w.gen as? WorldGen, let sc = gen.structures,
              let gt = sc.types.first(where: { $0.name == Greywall.kind }) else { check(false, "garagedoor: needs the overworld's structures"); return }
        let px = Int(floor(g.player.pos.x)), pz = Int(floor(g.player.pos.z))
        let rx0 = floorDiv(px, Greywall.spacing * CS), rz0 = floorDiv(pz, Greywall.spacing * CS)
        var found: Depots.Site?
        search: for r in 0...10 { for rz in (rz0 - r)...(rz0 + r) { for rx in (rx0 - r)...(rx0 + r) where max(abs(rx - rx0), abs(rz - rz0)) == r {
            guard let base = sc.start(gt, regionX: rx, regionZ: rz), let s = Depots.site(gen, sc, base), !s.fuel else { continue }
            found = s; break search
        } } }
        guard let s = found else { check(false, "garagedoor: an ammo depot within ten regions"); return }
        func X(_ a: Int) -> Int { s.side > 0 ? s.x0 + a : s.x1 - a }
        let S = s.S, mb = 8, Z = s.z0 + mb
        let home = g.player.pos, active0 = w.activeCenter, wasSurvival = g.survival
        defer { g.player.pos = home; w.activeCenter = active0; g.survival = wasSurvival; g.mobs.mobs.removeAll() }
        let outside = V3(Float(X(17)) + 0.5, Float(S + 1), Float(Z) + 0.5)
        g.player.pos = outside; w.activeCenter = outside
        g.survival = false; g.paused = false; g.menu = nil; g.alive = true
        _ = w.loadSync(center: outside, radius: 4)
        g.mobs.mobs.removeAll()
        let inward = V3(Float(X(12) - X(13)), 0, 0)
        func cells(_ a: Int, _ ys: ClosedRange<Int>, _ off: Int) -> [IVec3] {
            var out: [IVec3] = []
            for y in ys { for b in (mb - off)...(mb + off) { out.append(IVec3(X(a), S + y, s.z0 + b)) } }
            return out
        }
        let opening = cells(13, 1...4, 2)
        let up = opening.filter { (2...5).contains(GarageDoors.state(w.block($0.x, $0.y, $0.z))) }.count
        check(up == 20, "garagedoor: a fresh ammo depot's magazine has one garage door five wide and four high (\(up) of 20 cells are its upright panel)")
        // The vehicle: a box 4.4 wide and 3.9 high driven in through the opening, from 4 out to 4 in.
        func driveThrough() -> Bool {
            for k in 0...16 {
                let a = 17 - Float(k) * 0.5
                let cx = s.side > 0 ? Float(s.x0) + a + 0.5 : Float(s.x1) - a + 0.5
                let mn = V3(cx - 1.5, Float(S + 1) + 0.05, Float(Z) + 0.5 - 2.2), mx = V3(cx + 1.5, Float(S + 1) + 3.95, Float(Z) + 0.5 + 2.2)
                if w.collides(mn, mx) { return false }
            }
            return true
        }
        let blockedShut = !driveThrough()
        // Used from outside, by its middle.
        let p = g.player
        p.pos = outside; p.vel = .zero; p.flying = false
        let t0 = w.ships.list.count
        GarageDoors.use(g, IVec3(X(13), S + 2, Z))
        var body = false, rose: Float = 0, frames = 0
        while frames < 60 * 5 {
            g.tick(1.0 / 60); frames += 1
            g.mobs.mobs.removeAll()
            if let d = w.ships.list.first(where: { $0.name == GarageDoors.shipName }) {
                body = true
                if !d.hidden { rose = max(rose, d.worldMin.y - Float(S + 1)) }
            } else if body { break }
        }
        let clear = opening.filter { !Blocks.collide[Int(w.block($0.x, $0.y, $0.z))] }.count
        let stow = cells(12, 5...5, 2) + cells(11, 5...5, 2) + cells(10, 5...5, 2) + cells(9, 5...5, 2)
        let lying = stow.filter { (6...9).contains(GarageDoors.state(w.block($0.x, $0.y, $0.z))) }.count
        let drives = driveThrough()
        check(blockedShut && body && rose > 2.5 && clear == 20 && lying == 20 && drives && !w.ships.list.contains { $0.name == GarageDoors.shipName } && w.ships.list.count == t0,
              String(format: "garagedoor: used, the whole door swings up as one body (%@, its foot %.1f up) and lies under the crown (%d of 20 cells); the opening is clear (%d of 20) and a vehicle 4.4 wide drives through (%@, shut it %@)",
                     body ? "moved" : "no body", rose, lying, clear, drives ? "yes" : "no", blockedShut ? "couldn't" : "could"))
        // He walks in and back out.
        func walk(_ dir: V3, _ secs: Float) {
            p.flying = false; p.vel = .zero; p.yaw = atan2f(-dir.x, -dir.z); p.pitch = 0
            var mi = MoveInput(); mi.forward = 1
            for _ in 0..<Int(secs * 60) { p.update(dt: 1.0 / 60, input: mi, world: w) }
        }
        p.pos = outside
        walk(inward, 3)
        let inA = s.side > 0 ? p.pos.x - Float(s.x0) : Float(s.x1) - p.pos.x + 1
        walk(-inward, 4)
        let outA = s.side > 0 ? p.pos.x - Float(s.x0) : Float(s.x1) - p.pos.x + 1
        check(inA < 11 && outA > 15, String(format: "garagedoor: he walks in through it (to a %.1f, inside past 11) and back out (to a %.1f)", inA, outA))
        // The inside button shuts it.
        let btn = IVec3(X(12), S + 2, s.z0 + mb - 3)
        let pressed = Blocks.shape[Int(w.block(btn.x, btn.y, btn.z))] == "button"
        p.pos = V3(Float(X(11)) + 0.5, Float(S + 1), Float(Z) + 0.5)
        _ = g.useCircuit(btn)
        frames = 0; body = false
        while frames < 60 * 5 {
            g.tick(1.0 / 60); frames += 1
            g.mobs.mobs.removeAll()
            if w.ships.list.contains(where: { $0.name == GarageDoors.shipName }) { body = true } else if body { break }
        }
        let shut = opening.filter { (2...5).contains(GarageDoors.state(w.block($0.x, $0.y, $0.z))) }.count
        let stowLeft = stow.filter { GarageDoors.isDoor(w.block($0.x, $0.y, $0.z)) }.count
        check(pressed && body && shut == 20 && stowLeft == 0 && !driveThrough(),
              "garagedoor: the button inside shuts it (button \(pressed), swung \(body), \(shut) of 20 cells back across the opening, \(stowLeft) left overhead)")
        // His World's old shutters: a 3 by 3 of full cells in the second magazine's headwall.
        let mb2 = 22, Z2 = s.z0 + mb2
        let con = w.block(X(13), S + 6, Z2)
        for y in 1...4 { for b in (mb2 - 2)...(mb2 + 2) { w.setBlock(X(13), S + y, s.z0 + b, abs(b - mb2) <= 1 && y <= 3 ? Blocks.id(Depots.shutter) : con) } }
        let old = cells(13, 1...3, 1).map { IVec3($0.x, $0.y, $0.z - mb + mb2) }.filter { GarageDoors.state(w.block($0.x, $0.y, $0.z)) == 0 }.count
        p.pos = V3(Float(X(16)) + 0.5, Float(S + 1), Float(Z2) + 0.5)
        GarageDoors.use(g, IVec3(X(13), S + 1, Z2))
        for _ in 0..<(60 * 5) { g.tick(1.0 / 60); g.mobs.mobs.removeAll() }
        let oldOpen = cells(13, 1...3, 1).map { IVec3($0.x, $0.y, $0.z - mb + mb2) }.filter { !Blocks.collide[Int(w.block($0.x, $0.y, $0.z))] }.count
        let oldStow = [12, 11, 10].reduce(0) { n, a in n + cells(a, 4...4, 1).map { IVec3($0.x, $0.y, $0.z - mb + mb2) }.filter { (6...9).contains(GarageDoors.state(w.block($0.x, $0.y, $0.z))) }.count }
        GarageDoors.use(g, IVec3(X(11), S + 4, Z2))
        for _ in 0..<(60 * 5) { g.tick(1.0 / 60); g.mobs.mobs.removeAll() }
        let oldShut = cells(13, 1...3, 1).map { IVec3($0.x, $0.y, $0.z - mb + mb2) }.filter { (2...5).contains(GarageDoors.state(w.block($0.x, $0.y, $0.z))) }.count
        check(old == 9 && oldOpen == 9 && oldStow == 9 && oldShut == 9,
              "garagedoor: an old 3 by 3 shutter from a P507 save opens as one door (\(oldOpen) of 9 clear, \(oldStow) of 9 lying inside) and shuts again (\(oldShut) of 9)")
    }
}
