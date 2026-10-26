import Foundation
import simd

// P461 (Oct 25 16:43: "Just make it so blocks like metal and stuff just slowly melt in when put in lava... if I like drop
// this drop ship into the volcano, the lava just degrades it"): questcheck --lavamelt fills a stone basin beside him with
// lava (23 across, 4 deep) and
//   - drops a small tub in (a 5x5 floor and a rim, planks on one side, warship hull plate on the other): it should ride
//     the lava, its planks melt first and its plate later, nothing dropping;
//   - lets a taken Capital Dropship down over it with nobody at the controls: it should settle into the lava and lose
//     blocks.
enum LavaMeltCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        _ = w.loadSync(center: g.player.pos, radius: 5)
        let n = 25
        let x0 = Int(floor(g.player.pos.x)) + 14, z0 = Int(floor(g.player.pos.z)) - n / 2
        var floorY = 0
        for x in x0..<(x0 + n) { for z in z0..<(z0 + n) { floorY = max(floorY, w.topY(x, z)) } }
        var old: [(Int, Int, Int, BlockID)] = []
        func put(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) { old.append((x, y, z, w.block(x, y, z))); w.setBlock(x, y, z, b) }
        for y in (floorY + 1)...(floorY + 24) { for z in z0..<(z0 + n) { for x in x0..<(x0 + n) {
            let edge = x == x0 || x == x0 + n - 1 || z == z0 || z == z0 + n - 1
            put(x, y, z, y == floorY + 1 || (edge && y <= floorY + 5) ? STONE : (y <= floorY + 5 ? LAVA : AIR))
        } } }
        defer { for (x, y, z, b) in old.reversed() { w.setBlock(x, y, z, b) } }
        let lavaTop = Float(floorY + 5) + 0.875
        let mid = V3(Float(x0) + Float(n) / 2, 0, Float(z0) + Float(n) / 2)
        let plate = Blocks.id("warship_hull"), planks = Blocks.id("oak_planks")
        let times = [plate, Blocks.id("warship_panel"), Blocks.id("armored_glass"), Blocks.id("light_panel"), Blocks.id("steel_grating"),
                     Blocks.id("ship_engine"), planks, Blocks.id("iron_block")]
            .map { "\(Blocks.key($0)) " + (ShipManager.meltTime($0).map { String(format: "%.0f s", $0) } ?? "never") }
        print("lavamelt: melt times " + times.joined(separator: ", "))

        // The tub.
        let bp = Blueprint()
        for x in 0..<5 { for z in 0..<5 {
            let k = x < 2 ? "oak_planks" : "warship_hull"
            bp.set(x, 0, z, k)
            if x == 0 || x == 4 || z == 0 || z == 4 { bp.set(x, 1, z, k) }
        } }
        let drops0 = g.drops.items.count
        let s = w.ships.spawn(bp, at: mid + V3(0, lavaTop + 3, 0), yaw: 0, name: "Tub", role: "tub")
        func count(_ b: BlockID) -> Int {
            var c = 0
            for y in 0..<s.grid.sy { for z in 0..<s.grid.sz { for x in 0..<s.grid.sx where s.grid.get(x, y, z) == b { c += 1 } } }
            return c
        }
        let p0 = count(planks), h0 = count(plate)
        var bottomAt5: Float = 0, plankHalfAt: Float = -1, plateFirstAt: Float = -1, t: Float = 0
        var log: [String] = []
        while t < 60 {
            w.ships.update(1.0 / 60, game: g)
            t += 1.0 / 60
            let gone = !w.ships.list.contains { $0 === s } || s.blockCount == 0
            if plankHalfAt < 0 && (gone || count(planks) <= p0 / 2) { plankHalfAt = t }
            if plateFirstAt < 0 && (gone || count(plate) < h0) { plateFirstAt = t }
            if abs(t - 5) < 0.009 { bottomAt5 = s.worldMin.y }
            if Int((t * 60).rounded()) % 600 == 0 { log.append(String(format: "%.0f s: bottom %.2f, planks %d, plate %d", t, s.worldMin.y, count(planks), count(plate))) }
            if gone { break }
        }
        w.ships.remove(s)
        let rides = bottomAt5 > Float(floorY + 2) + 0.3 && bottomAt5 < lavaTop
        check(rides && plankHalfAt > 0 && plateFirstAt > plankHalfAt && g.drops.items.count == drops0,
              String(format: "lavamelt: a tub dropped in lava rides it (bottom %.2f at 5 s, lava top %.2f, its floor %d), half its planks gone at %.1f s, its first hull plate at %.1f s, %d dropped; ",
                     bottomAt5, lavaTop, floorY + 2, plankHalfAt, plateFirstAt, g.drops.items.count - drops0) + log.joined(separator: "; "))

        // The taken dropship let down over the lava.
        let n0 = w.ships.list.count
        w.ships.callDropship(faction: .steelhold, from: mid + V3(0, lavaTop + 12, 0), to: mid + V3(0, lavaTop + 12, -60), game: g, sync: true)
        guard let d = w.ships.list.dropFirst(n0).first(where: { $0.role == "dropship" && $0.parent == nil }) else {
            check(false, "lavamelt: a Capital Dropship spawns"); return
        }
        defer {
            for t in w.ships.list where t === d || t.parent === d { w.ships.remove(t) }
            w.ships.capState.removeValue(forKey: d.id)
        }
        d.captured = true
        d.vel = .zero; d.angVel = .zero
        let b0 = d.blockCount, melted0 = ShipManager.melted
        var lowest = Float.infinity, at30 = 0
        var dlog: [String] = []
        for k in 1...(60 * 60) {
            w.ships.update(1.0 / 60, game: g)
            lowest = min(lowest, d.worldMin.y)
            if k % 600 == 0 { dlog.append("\(k / 60) s: \(d.blockCount) left (\(ShipManager.melted - melted0) melted)") }
            if k == 60 * 30 { at30 = d.blockCount }
        }
        // Slowly: most of it still there after half a minute, but going.
        check(lowest < lavaTop - 0.5 && ShipManager.melted > melted0 && at30 * 2 > b0 && d.blockCount < b0,
              String(format: "lavamelt: a taken dropship left over the lava settles into it (keel down to %.2f, lava top %.2f) and melts slowly: %d of its %d blocks left at 30 s, %d at 60 s; ",
                     lowest, lavaTop, at30, b0, d.blockCount) + dlog.joined(separator: "; "))
    }
}
