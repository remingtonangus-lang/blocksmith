import Foundation
import simd

// FAILURES.md 2's check (questcheck --elevator, and the full suite), tried the way he will: a lift built in the air (three
// landings six apart, a floor in front of each), with the car at the bottom and its doors open. He walks into the car,
// picks the top floor on its panel, and rides: the car comes away as one body and carries him up the shaft (never
// falling through, never leaving the car), stops at the top, the doors there open and the bottom's shut; he walks out.
// Called from the middle landing's button, the car comes down to it. And a column of his World's Lift Pads in a tower
// room becomes a lift with its car at the lowest pad.
enum ElevatorCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        guard Elevators.has() else { check(false, "elevator: no lift blocks"); return }
        let home = g.player.pos, wasSurvival = g.survival
        defer { g.player.pos = home; g.survival = wasSurvival; g.closeMenu() }
        let ox = Int(floor(home.x)) + 6, oz = Int(floor(home.z)) + 6, y0 = min(CH - 40, Int(floor(home.y)) + 60)
        let spot = V3(Float(ox) + 0.5, Float(y0 + 1), Float(oz) + 0.5)
        _ = w.loadSync(center: spot, radius: 3)
        g.survival = true; g.paused = false; g.menu = nil; g.alive = true; g.health = 20
        let stone = Blocks.id("stone")
        let landings = [y0, y0 + 6, y0 + 12]
        let u = IVec3(0, 0, 1), n = IVec3(-1, 0, 0)
        let foot0 = IVec3(ox, 0, oz)
        // A floor in front of each landing (four out from the doors, the shaft's width and one more each side).
        for F in landings { for j in -5...(-1) { for i in -1...2 { w.setBlock(ox - n.x * -j, F, oz + i, stone) } } }
        Elevators.build(foot0: foot0, u: u, n: n, landings: landings, wall: stone) { x, y, z, b in
            if let b { w.setBlock(x, y, z, b); return b }
            return w.block(x, y, z)
        }
        for _ in 0..<30 { g.tick(1.0 / 60) }
        guard let r = Elevators.run(w, near: IVec3(ox + 1, y0 + 1, oz)) else { check(false, "elevator: the lift built isn't found from its doors"); return }
        let s = r.shaft
        let open0 = Elevators.doorsAt(w, s, y0)
        check(s.landings == landings && s.car == y0 && open0 == 2,
              "elevator: a lift of \(s.landings.count) landings, its car at the bottom (\(s.car.map { "\($0 - y0)" } ?? "none")), the doors there open (stage \(open0))")
        // He walks in (from four out, toward the shaft) and picks the top floor on the panel.
        let p = g.player
        func walk(_ dir: IVec3, _ secs: Float) {
            p.flying = false; p.vel = .zero; p.yaw = atan2f(-Float(dir.x), -Float(dir.z)); p.pitch = 0
            var mi = MoveInput(); mi.forward = 1
            for _ in 0..<Int(secs * 60) { p.update(dt: 1.0 / 60, input: mi, world: w) }      // (the car stands as blocks)
        }
        p.pos = V3(Float(ox) + 4.5, Float(y0 + 1), Float(oz) + 1.0)
        walk(n, 1.6)
        func inCar() -> Bool {
            let lx = Float(ox) + 1 - p.pos.x, lz = p.pos.z - Float(oz)
            return lx > 0.2 && lx < 3 && lz > 0.2 && lz < 1.8
        }
        let walkedIn = inCar()
        let panelCell = s.foot(1, 1, y0 + 2)
        let pk = Elevators.key(w.block(panelCell.x, panelCell.y, panelCell.z))
        Elevators.use(g, panelCell)
        let menu = g.menu as? LiftMenu
        let rowNames = menu?.rows.map { $0.name } ?? []
        menu?.pressed(0)                                       // (top first)
        var rode = false, fell = false, left = false, maxY: Float = 0, frames = 0
        while frames < 60 * 16 {
            g.tick(1.0 / 60); frames += 1
            if w.ships.list.contains(where: { $0.name == Elevators.shipName && !$0.hidden }) { rode = true }
            maxY = max(maxY, p.pos.y)
            if p.pos.y < Float(y0) + 0.5 { fell = true }
            if !inCar() { left = true }
            if r.phase == 0 && r.shaft.car == y0 + 12 && frames > 60 { break }
        }
        let topOpen = Elevators.doorsAt(w, r.shaft, y0 + 12), bottomShut = Elevators.doorsAt(w, r.shaft, y0)
        let at = p.pos.y - Float(y0 + 13)
        check(walkedIn && pk == Elevators.panelKey && rowNames.count == 3 && rode && !fell && !left && abs(at) < 0.3 && topOpen == 2 && bottomShut == 0
              && !w.ships.list.contains { $0.name == Elevators.shipName },
              String(format: "elevator: he walks in (%@), picks the top floor on the panel (%@), and rides the car up as one body (%@, fell %@, left the car %@); at the top he stands at the landing (%.2f off), its doors open (%d), the bottom's shut (%d), in %.1f s",
                     walkedIn ? "yes" : "no", rowNames.joined(separator: ", "), rode ? "moved" : "never moved", fell ? "yes" : "no", left ? "yes" : "no", at, topOpen, bottomShut, Float(frames) / 60))
        // Out onto the top landing.
        walk(IVec3(-n.x, 0, -n.z), 1.6)
        let out = p.pos.x - Float(ox) > 1.5 && abs(p.pos.y - Float(y0 + 13)) < 0.3
        // Called from the middle landing's button.
        let btn = s.foot(Elevators.W, -2, y0 + 8)
        let bk = Elevators.key(w.block(btn.x, btn.y, btn.z))
        p.pos = V3(Float(ox) + 3.5, Float(y0 + 7), Float(oz) + 1.0)
        Elevators.use(g, btn)
        frames = 0
        while frames < 60 * 12 {
            g.tick(1.0 / 60); frames += 1
            if r.phase == 0 && r.shaft.car == y0 + 6 && frames > 60 { break }
        }
        let midOpen = Elevators.doorsAt(w, r.shaft, y0 + 6), topShut = Elevators.doorsAt(w, r.shaft, y0 + 12)
        let carAt = s.foot(0, 0, y0 + 6)
        check(out && bk == Elevators.callKey && r.shaft.car == y0 + 6 && midOpen == 2 && topShut == 0 && Elevators.key(w.block(carAt.x, carAt.y, carAt.z)) == Elevators.floorKey,
              "elevator: he walks out at the top (\(out)); the middle landing's button (\(bk)) calls the car down to it (car at \(r.shaft.car.map { "\($0 - y0)" } ?? "none"), doors open \(midOpen), the top's shut \(topShut))")

        // His World's towers: a room with a Lift Pad column three in from its west wall, a floor at each pad.
        guard let pad = Lift.pad else { check(false, "elevator: no lift pads"); return }
        let tx = ox + 30, tz = oz
        let pads = [y0, y0 + 7, y0 + 13]
        for y in y0...(y0 + 19) { for dz in -6...6 { for dx in -6...6 {
            let edge = abs(dx) == 6 || abs(dz) == 6
            let floorLevel = pads.contains(y) || y == y0 + 19
            w.setBlock(tx + dx, y, tz + dz, edge || floorLevel ? stone : AIR)
        } } }
        for y in pads { w.setBlock(tx - 3, y, tz, pad) }
        p.pos = V3(Float(tx) + 3.5, Float(y0 + 1), Float(tz) + 0.5)
        let done = Elevators.retrofit(w, IVec3(tx - 3, y0, tz), avoid: p.pos)
        let found = Elevators.shaft(w, near: IVec3(tx - 2, y0 + 1, tz))
        let padsLeft = pads.filter { w.block(tx - 3, $0, tz) == pad }.count
        check(done && found?.landings == pads && found?.car == y0 && padsLeft == 0,
              "elevator: a column of his World's Lift Pads in a tower room becomes a lift (\(done)): landings \(found?.landings.map { $0 - y0 } ?? []), its car at the lowest, \(padsLeft) pads left")
        // A citadel side tower of his (its ladder up the north of its middle, a pad on the roof garden): the lift goes
        // south of the middle, two deep, up to the top floor (the garden by the ladder, as in a new tower).
        let cx2 = ox + 60, cz2 = oz
        let pads2 = [y0, y0 + 7, y0 + 13, y0 + 20]
        for y in y0...(y0 + 21) { for dz in -6...6 { for dx in -6...6 {
            let edge = abs(dx) == 6 || abs(dz) == 6
            let floorLevel = [y0, y0 + 7, y0 + 13, y0 + 19].contains(y)
            w.setBlock(cx2 + dx, y, cz2 + dz, y > y0 + 19 ? AIR : (edge || floorLevel ? stone : AIR))
        } } }
        for y in (y0 + 1)...(y0 + 19) { w.setBlock(cx2, y, cz2 - 4, Blocks.id("ladder") + 1); w.setBlock(cx2, y, cz2 - 5, stone) }
        for y in pads2 { w.setBlock(cx2 - 3, y, cz2, pad) }
        let barrel = Blocks.id("barrel")
        w.setBlock(cx2 + 4, y0 + 14, cz2 + 3, barrel)                  // (his own on the third storey: it stays as he left it)
        p.pos = V3(Float(cx2) + 3.5, Float(y0 + 1), Float(cz2) - 2.5)
        let done2 = Elevators.retrofit(w, IVec3(cx2 - 3, y0, cz2), avoid: p.pos)
        let found2 = Elevators.shaft(w, near: IVec3(cx2 - 3, y0 + 1, cz2 + 1))
        let ladderKept = (y0 + 1...y0 + 19).allSatisfy { Blocks.groupBase[Int(w.block(cx2, $0, cz2 - 4))] == Blocks.id("ladder") }
        check(done2 && found2?.landings == [y0, y0 + 7, y0 + 13] && found2?.d == 2 && found2?.a == IVec3(cx2 - 3, 0, cz2 + 2) && ladderKept,
              "elevator: in a citadel side tower of his it stands south of the middle, two deep (\(found2?.d ?? 0)), floors \(found2?.landings.map { $0 - y0 } ?? []) (the garden by the ladder, kept: \(ladderKept))")
        // P510: its empty storeys furnished as a new tower's (a guard post, a signals room); his own left alone; never
        // a table in his cell.
        func k(_ x: Int, _ y: Int, _ z: Int) -> String { Elevators.key(w.block(cx2 + x, y, cz2 + z)) }
        let guardDesk = k(-3, y0 + 1, -4) == "command_console", signals = k(5, y0 + 8, -4) == "data_cabinet" && k(2, y0 + 8, -4) == "command_console"
        var leftAlone = true
        for z in -5...5 { for x in -5...5 where !(x == 4 && z == 3) && k(x, y0 + 14, z).hasSuffix("_bed") { leftAlone = false } }
        let hisCell = k(3, y0 + 1, -3), roomsUsed = Set((-5...5).flatMap { x in (-5...5).map { z in k(x, y0 + 8, z) } }).count
        check(guardDesk && signals && leftAlone && hisCell == "air" && roomsUsed >= 4,
              "elevator: his citadel's empty storeys become rooms (a guard post \(guardDesk), signals \(signals), \(roomsUsed) kinds of block on it); the storey he'd furnished is left (\(leftAlone)); nothing in his cell (\(hisCell))")
        Elevators.runs.removeAll()
    }
}
