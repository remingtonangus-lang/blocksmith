import Foundation
import simd
import Metal

// P455 (Oct 25 14:19-14:25, the Ironstride Siege Carriage: "the trees are bullying it too much... this thing just blasts
// through trees"): a heavy hull driven into trees and a timber wall pushes through them on its engine; a light car is
// stopped by the trunks. Played through Game.tick (the physics, the contacts and Momentum.shove).
//   questcheck --shovecheck
enum QuestShoveCheck {
    static func run() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        TextureGen.registerAll()
        var fails = 0
        func check(_ ok: Bool, _ what: String) { print("\(ok ? "ok  " : "FAIL") shovecheck: \(what)"); if !ok { fails += 1 } }

        let w = World(seed: 4797859299361840175, device: sharedSystemDevice, save: nil)
        FieldTerrain.newWorlds = true; w.makeFieldWorld()
        w.renderDistance = 4
        let g = Game(world: w, save: nil, persistent: false)
        g.smoothTerrain = true
        SmoothTerrain.use(world: true, world: w)
        g.paused = false; g.menu = nil
        g.player.pos = V3(-496.5, 72 + Float(YOFF), 6102.5)
        g.player.flying = true
        _ = w.loadSync(center: g.player.pos, radius: 4)
        g.tick(1.0 / 72)
        func top(_ x: Int, _ z: Int) -> Int {
            var y = CH - 1
            while y > 1 && !w.groundAt(x, y, z) && w.builtBlock(x, y, z) == AIR { y -= 1 }
            return y
        }
        // Trees are tree wood (TreeWood); a plain log is timber, a solid block like the planks.
        let log = TreeWood.of(Blocks.id("oak_log"))
        let logKey = Blocks.key(Blocks.groupBase[Int(log)])
        // A level place for each drive (the land at a fixed spot changes with the generator: Nov 15, the old spot had
        // become a slope five blocks high off the carriage's bow, and the check had failed unseen since).
        let px = Int(floor(g.player.pos.x)), pz = Int(floor(g.player.pos.z))
        let R = 60
        var hm = [Int](repeating: 0, count: (2 * R + 1) * (2 * R + 1))
        for dz in -R...R { for dx in -R...R { hm[(dz + R) * (2 * R + 1) + dx + R] = top(px + dx, pz + dz) } }
        func level(halfX: Int, halfZ: Int, awayFrom: (Int, Int)?) -> (Int, Int, Int) {
            var best = (px, pz, Int.max)
            for cz in stride(from: -R + halfZ, through: R - halfZ, by: 2) { for cx in stride(from: -R + halfX, through: R - halfX, by: 2) {
                if let a = awayFrom, abs(px + cx - a.0) < halfX + 14 { continue }
                var lo = Int.max, hi = Int.min
                for dz in stride(from: -halfZ, through: halfZ, by: 2) { for dx in stride(from: -halfX, through: halfX, by: 2) {
                    let h = hm[(cz + dz + R) * (2 * R + 1) + cx + dx + R]
                    lo = min(lo, h); hi = max(hi, h)
                } }
                if hi - lo < best.2 { best = (px + cx, pz + cz, hi - lo) }
            } }
            return best
        }
        var ghosts = 0
        var wallLeft = (0, 0)

        func drive(_ bp: Blueprint, _ name: String, at x0: Int, _ z0: Int, seconds: Float) -> (Ship, Int, Int, Float) {
            var gy = 0
            for dz in -30...30 { for dx in -16...16 { gy = max(gy, top(x0 + dx, z0 + dz)) } }
            let s = w.ships.spawn(bp, at: V3(Float(x0) + 0.5, Float(gy) + 6, Float(z0) + 0.5), yaw: 0, name: name, role: "")
            for _ in 0..<144 { g.tick(1.0 / 72) }                    // (settles on its wheels)
            // Which way it drives (its helm's heading), on the nearer axis.
            let fw = s.dirToWorld(s.fwd)
            let alongZ = abs(fw.z) >= abs(fw.x)
            let sg: Int = (alongZ ? fw.z : fw.x) < 0 ? -1 : 1
            let ahead = V3(alongZ ? 0 : Float(sg), 0, alongZ ? Float(sg) : 0)
            // A row of trunks four high across its path, two blocks off its bow, and a plank wall three behind them.
            let bow = alongZ ? (sg < 0 ? Int(floor(s.worldMin.z)) : Int(floor(s.worldMax.z))) : (sg < 0 ? Int(floor(s.worldMin.x)) : Int(floor(s.worldMax.x)))
            let line = bow + 2 * sg
            let span = alongZ ? Int(floor(s.worldMin.x))...Int(floor(s.worldMax.x)) : Int(floor(s.worldMin.z))...Int(floor(s.worldMax.z))
            func cell(_ a: Int, _ k: Int) -> (Int, Int) { alongZ ? (a, line + k * sg) : (line + k * sg, a) }
            print(String(format: "shovecheck: %@ heading %.2f %.2f %.2f, bounds x %.1f..%.1f z %.1f..%.1f, trunks at %@ %d", name, fw.x, fw.y, fw.z,
                         s.worldMin.x, s.worldMax.x, s.worldMin.z, s.worldMax.z, alongZ ? "z" : "x", line))
            w.restoring = true
            for a in span where a % 2 == 0 { let (x, z) = cell(a, 0); let b = top(x, z) + 1; for y in b..<(b + 4) { w.setBlock(x, y, z, log) } }
            for a in span { let (x, z) = cell(a, 3); let b = top(x, z) + 1; for y in b..<(b + 3) { w.setBlock(x, y, z, Blocks.id("oak_planks")) } }
            w.restoring = false
            func count() -> Int {
                var n = 0
                for a in span { for k in [0, 3] {
                    let (x, z) = cell(a, k)
                    for y in (top(x, z) - 6)...(top(x, z) + 6) {
                        let key = Blocks.key(Blocks.groupBase[Int(w.builtBlock(x, y, z))])
                        if key == logKey || key == "oak_planks" { n += 1 }
                    }
                } }
                return n
            }
            let n0 = count(), p0 = s.pos, calls0 = Momentum.shoveCalls
            Momentum.traceRest = true
            s.autopilot = V3(1, 0, 0)
            for i in 0..<Int(seconds * 72) {
                g.tick(1.0 / 72)
                if i % 144 == 143 {
                    print(String(format: "shovecheck:   %.0f s: %.1f along, speed %.2f, ease %.2f, grounded %@, pushes %d, side contacts %d", Float(i + 1) / 72,
                                 simd_dot(s.pos - p0, ahead), simd_length(s.vel), s.throttleEase, s.grounded ? "yes" : "no", Momentum.shoveCalls - calls0, Momentum.sideContacts))
                    let rs = Momentum.rest
                    print(String(format: "shovecheck:     asleep %@, contacts %d (up %d, of them not at a wheel %d, on other hulls %d; one at %.1f %.1f %.1f), hull bottom %.2f, vel %.2f %.2f %.2f, pushing %@, store %.1f",
                                 s.asleep ? "yes" : "no", rs.0, rs.1, rs.2, rs.3, rs.4.x, rs.4.y, rs.4.z, s.worldMin.y, s.vel.x, s.vel.y, s.vel.z, s.pushing ? "yes" : "no", s.shoveStore))
                    let (cp, cn, into) = Momentum.lastSide
                    let inb = cp - cn * 0.3
                    print(String(format: "shovecheck:     last side contact at %.1f %.1f %.1f normal %.2f %.2f %.2f into %.2f, block there %@, bow %.1f", cp.x, cp.y, cp.z, cn.x, cn.y, cn.z, into,
                                 Blocks.key(w.builtBlock(Int(floor(inb.x)), Int(floor(inb.y)), Int(floor(inb.z)))), alongZ ? (sg < 0 ? s.worldMin.z : s.worldMax.z) : (sg < 0 ? s.worldMin.x : s.worldMax.x)))
                }
            }
            s.autopilot = nil
            // Where it ended up against what is left of the rows.
            print(String(format: "shovecheck:   ended with bounds y %.1f..%.1f, bow %.1f; heading %.2f %.2f %.2f", s.worldMin.y, s.worldMax.y,
                         alongZ ? (sg < 0 ? s.worldMin.z : s.worldMax.z) : (sg < 0 ? s.worldMin.x : s.worldMax.x), s.dirToWorld(s.fwd).x, s.dirToWorld(s.fwd).y, s.dirToWorld(s.fwd).z))
            for k in [0, 3] {
                var row = ""
                for a in span {
                    let (x, z) = cell(a, k)
                    var n = 0
                    for y in (top(x, z) - 6)...(top(x, z) + 6) {
                        let key = Blocks.key(Blocks.groupBase[Int(w.builtBlock(x, y, z))])
                        if key == logKey || key == "oak_planks" { n += 1 }
                    }
                    row += "\(n)"
                }
                print("shovecheck:   row \(k == 0 ? "trunks" : "wall  ") left per column: \(row) (ground top at middle \(top(cell(span.lowerBound + span.count / 2, k).0, cell(span.lowerBound + span.count / 2, k).1)))")
            }
            // Row blocks sharing a cell with its hull (driven through without being shoved aside).
            var inside = 0
            for a in span { for k in [0, 3] {
                let (x, z) = cell(a, k)
                for y in (top(x, z) - 6)...(top(x, z) + 6) {
                    let key = Blocks.key(Blocks.groupBase[Int(w.builtBlock(x, y, z))])
                    guard key == logKey || key == "oak_planks" else { continue }
                    let l = s.toLocal(V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5))
                    if s.grid.get(Int(floor(l.x)), Int(floor(l.y)), Int(floor(l.z))) != AIR {
                        inside += 1
                        print(String(format: "shovecheck:   inside its hull: %@ at %d %d %d (hull bottom %.2f)", key, x, y, z, s.worldMin.y))
                    }
                }
            } }
            ghosts = inside
            // The plank wall where its wheels ran, the four outer columns each side (P455: the wheels rode up over it;
            // the middle passes under the carriage's belly, clear of its hull, and is left standing).
            var planks = 0
            let cols = Array(span)
            for a in cols.prefix(4) + cols.suffix(4) {
                let (x, z) = cell(a, 3)
                for y in (top(x, z) - 6)...(top(x, z) + 6) where Blocks.key(Blocks.groupBase[Int(w.builtBlock(x, y, z))]) == "oak_planks" { planks += 1 }
            }
            wallLeft = (planks, 24)
            return (s, n0, count(), simd_dot(s.pos - p0, ahead))
        }
        let shoved0 = Momentum.shoved
        let bigAt = level(halfX: 10, halfZ: 30, awayFrom: nil)
        print("shovecheck: the carriage's place \(bigAt.0) \(bigAt.1), the land \(bigAt.2) blocks from lowest to highest under its run")
        let (big, b0, b1, bMoved) = drive(Vessels.carriage(), "Ironstride Siege Carriage", at: bigAt.0, bigAt.1 + 10, seconds: 10)
        print(String(format: "shovecheck: the siege carriage (mass %.0f) broke %d of %d trunk and plank blocks and drove %.1f blocks", big.mass, b0 - b1, b0, bMoved))
        // (the rows two and five blocks off its bow, then the spruce wood beyond: his 14:19 "blasts through trees")
        check(bMoved > 12, String(format: "the siege carriage drives on past both rows (%.1f blocks in 10 s; it was held at 9.1 by a tree against its upper works)", bMoved))
        check(ghosts == 0, "nothing it drove past is left standing inside its hull (\(ghosts) blocks)")
        check(wallLeft.0 * 2 <= wallLeft.1, "its wheels break through the plank wall rather than riding over it (\(wallLeft.0) of \(wallLeft.1) planks left in their tracks; 21 before)")
        check(Momentum.shoved - shoved0 >= 10, "Momentum.shove broke what was in its way (\(Momentum.shoved - shoved0) blocks)")
        // Ledger 146 (Nov 15 08:36, the carriage "stuck in the trees"): a felled tree lying across its way is a body, not
        // blocks, so Momentum.shove never broke it and the carriage pushed a pile of trunks. A heavy driven hull smashes it.
        do {
            let fw0 = big.dirToWorld(big.fwd)
            let fw = simd_normalize(V3(fw0.x, 0, fw0.z))
            let mid = (big.worldMin + big.worldMax) * 0.5
            let half = (abs(fw.z) >= abs(fw.x) ? big.worldMax.z - big.worldMin.z : big.worldMax.x - big.worldMin.x) * 0.5
            let tree = Blueprint()
            tree.box(0, 6, 0, 0, 0, 0, "oak_log")
            let at = mid + fw * (half + 4)
            let body = w.ships.spawn(tree, at: V3(at.x, big.worldMin.y + 3, at.z), yaw: 0, name: Felling.name, role: "")
            for _ in 0..<144 { g.tick(1.0 / 72) }
            let c0 = Felling.crushed, p0 = big.pos
            let lying = w.ships.list.contains(where: { $0 === body })
            big.autopilot = V3(1, 0, 0)
            for _ in 0..<(5 * 72) { g.tick(1.0 / 72) }
            big.autopilot = nil
            let gone = !w.ships.list.contains(where: { $0 === body })
            let moved = simd_dot(big.pos - p0, fw)
            check(Momentum.oldCrush ? true : (lying && gone && Felling.crushed > c0 && moved > 4),
                  String(format: "a felled tree lying across the carriage's way (there before: %@) is smashed (gone: %@, %d bodies crushed) and it drives on (%.1f blocks in 5 s)", lying ? "yes" : "no", gone ? "yes" : "no", Felling.crushed - c0, moved))
        }
        w.ships.remove(big)

        // A light car: four wheels, an engine and a seat.
        let car = Blueprint()
        for (x, z) in [(0, 0), (2, 0), (0, 3), (2, 3)] { car.set(x, 0, z, "ship_wheel") }
        car.box(0, 1, 0, 2, 1, 3, "oak_planks")
        car.set(1, 2, 1, "ship_helm[south]"); car.set(1, 2, 3, "ship_engine")
        let shoved1 = Momentum.shoved
        let carAt = level(halfX: 4, halfZ: 12, awayFrom: (bigAt.0, bigAt.1))
        print("shovecheck: the car's place \(carAt.0) \(carAt.1), the land \(carAt.2) blocks from lowest to highest")
        let (small, s0, s1, sMoved) = drive(car, "car", at: carAt.0, carAt.1 + 4, seconds: 4)
        print(String(format: "shovecheck: the light car (mass %.0f) broke %d of %d and drove %.1f blocks", small.mass, s0 - s1, s0, sMoved))
        check(Momentum.shoved == shoved1 || small.mass / 100 >= 2, "a light car is stopped by trunks (it cannot shift a log)")
        w.ships.remove(small)
        print(fails == 0 ? "shovecheck: all passed" : "shovecheck: \(fails) failed")
        return fails == 0 ? 0 : 1
    }
}
