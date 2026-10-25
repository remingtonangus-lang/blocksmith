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
        let log = Blocks.id("oak_log")
        var ghosts = 0

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
                        if key == "oak_log" || key == "oak_planks" { n += 1 }
                    }
                } }
                return n
            }
            let n0 = count(), p0 = s.pos, calls0 = Momentum.shoveCalls
            s.autopilot = V3(1, 0, 0)
            for i in 0..<Int(seconds * 72) {
                g.tick(1.0 / 72)
                if i % 144 == 143 {
                    print(String(format: "shovecheck:   %.0f s: %.1f along, speed %.2f, ease %.2f, grounded %@, pushes %d, side contacts %d", Float(i + 1) / 72,
                                 simd_dot(s.pos - p0, ahead), simd_length(s.vel), s.throttleEase, s.grounded ? "yes" : "no", Momentum.shoveCalls - calls0, Momentum.sideContacts))
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
                        if key == "oak_log" || key == "oak_planks" { n += 1 }
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
                    guard key == "oak_log" || key == "oak_planks" else { continue }
                    let l = s.toLocal(V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5))
                    if s.grid.get(Int(floor(l.x)), Int(floor(l.y)), Int(floor(l.z))) != AIR { inside += 1 }
                }
            } }
            ghosts = inside
            return (s, n0, count(), simd_dot(s.pos - p0, ahead))
        }
        let shoved0 = Momentum.shoved
        let (big, b0, b1, bMoved) = drive(Vessels.carriage(), "Ironstride Siege Carriage", at: -500, 6110, seconds: 10)
        print(String(format: "shovecheck: the siege carriage (mass %.0f) broke %d of %d trunk and plank blocks and drove %.1f blocks", big.mass, b0 - b1, b0, bMoved))
        // (the rows two and five blocks off its bow, then the spruce wood beyond: his 14:19 "blasts through trees")
        check(bMoved > 12, String(format: "the siege carriage drives on past both rows (%.1f blocks in 10 s; it was held at 9.1 by a tree against its upper works)", bMoved))
        check(ghosts == 0, "nothing it drove past is left standing inside its hull (\(ghosts) blocks)")
        check(Momentum.shoved - shoved0 >= 10, "Momentum.shove broke what was in its way (\(Momentum.shoved - shoved0) blocks)")
        w.ships.remove(big)

        // A light car: four wheels, an engine and a seat.
        let car = Blueprint()
        for (x, z) in [(0, 0), (2, 0), (0, 3), (2, 3)] { car.set(x, 0, z, "ship_wheel") }
        car.box(0, 1, 0, 2, 1, 3, "oak_planks")
        car.set(1, 2, 1, "ship_helm[south]"); car.set(1, 2, 3, "ship_engine")
        let shoved1 = Momentum.shoved
        let (small, s0, s1, sMoved) = drive(car, "car", at: -470, 6080, seconds: 4)
        print(String(format: "shovecheck: the light car (mass %.0f) broke %d of %d and drove %.1f blocks", small.mass, s0 - s1, s0, sMoved))
        check(Momentum.shoved == shoved1 || small.mass / 100 >= 2, "a light car is stopped by trunks (it cannot shift a log)")
        w.ships.remove(small)
        print(fails == 0 ? "shovecheck: all passed" : "shovecheck: \(fails) failed")
        return fails == 0 ? 0 : 1
    }
}
