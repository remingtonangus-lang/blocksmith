import Foundation
import simd
import Metal

// P455 (Oct 25 14:21, the Ironstride Siege Carriage: "entering from the bottom gives a weird reaction"). On foot at a
// parked carriage: walking and jumping under its belly (no jolt, not taken aboard), then climbing the stern ladder to
// the cab door (on the deck, aboard). Played through shipPlayerUpdate and the ship step, as the game does.
//   questcheck --boardcheck
enum QuestBoardCheck {
    static func run() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        TextureGen.registerAll()
        var fails = 0
        func check(_ ok: Bool, _ what: String) { print("\(ok ? "ok  " : "FAIL") boardcheck: \(what)"); if !ok { fails += 1 } }

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
        var gy = 0
        for dz in -30...30 { for dx in -16...16 {
            var y = CH - 1
            while y > 1 && !w.groundAt(-500 + dx, y, 6110 + dz) && w.builtBlock(-500 + dx, y, 6110 + dz) == AIR { y -= 1 }
            gy = max(gy, y)
        } }
        let s = w.ships.spawn(Vessels.carriage(), at: V3(-499.5, Float(gy) + 6, 6110.5), yaw: 0, name: "Ironstride Siege Carriage", role: "")
        for _ in 0..<216 { g.tick(1.0 / 72) }                    // (settles on its wheels)
        let cx = (s.localMin.x + s.localMax.x) / 2
        let back = s.dirToWorld(V3(0, 0, -1))
        print(String(format: "boardcheck: carriage local x %.1f..%.1f y %.1f..%.1f z %.1f..%.1f, at %.1f %.1f %.1f", s.localMin.x, s.localMax.x,
                     s.localMin.y, s.localMax.y, s.localMin.z, s.localMax.z, s.pos.x, s.pos.y, s.pos.z))

        // Plays the player for `secs` with input `mi` (and jumps every `hop` s), from a local start point.
        func play(_ start: V3, _ secs: Float, forward: Float, hop: Float, _ name: String) -> (jolt: Float, top: Float, aboard: Bool, end: V3) {
            g.player.flying = false
            g.player.pos = s.toWorld(start)
            g.player.vel = .zero
            g.player.yaw = atan2f(-back.x, -back.z)
            w.ships.aboard = nil
            var jolt: Float = 0, top: Float = -99
            var last = g.player.pos
            let n = Int(secs * 72)
            for i in 0..<n {
                var mi = MoveInput()
                mi.forward = forward
                mi.jump = hop > 0 && i % Int(hop * 72) < 6
                g.health = 20
                g.shipPlayerUpdate(1.0 / 72, mi)
                w.ships.update(1.0 / 72, game: g)
                let step = simd_length(g.player.pos - last)
                jolt = max(jolt, step)
                last = g.player.pos
                let l = s.toLocal(g.player.pos)
                top = max(top, l.y - s.localMin.y)
                if i % 72 == 71 {
                    print(String(format: "boardcheck:   %@ %.0f s: local %.1f %.1f %.1f (%.1f over its bottom), aboard %@, on ground %@", name, Float(i + 1) / 72,
                                 l.x - cx, l.y, l.z, l.y - s.localMin.y, w.ships.aboard === s ? "yes" : "no", g.player.onGround ? "yes" : "no"))
                }
            }
            return (jolt, top, w.ships.aboard === s, s.toLocal(g.player.pos))
        }
        // Under the belly, between the wheels: walk toward the bow and jump now and then.
        let under = play(V3(cx, s.localMin.y + 0.1, s.localMin.z + 18.5), 6, forward: 1, hop: 1.5, "under the belly")
        check(under.jolt < 0.6, String(format: "under its belly nothing throws him about (biggest move in a tick %.2f)", under.jolt))
        check(under.top < 3, String(format: "under its belly he stays under it (feet up to %.1f over its bottom; the hull is 3 up)", under.top))
        // At the stern, facing the ladder: climb, then walk in at the door.
        let climb = play(V3(cx, s.localMin.y + 0.1, s.localMax.z + 0.9), 10, forward: 1, hop: 0, "up the stern ladder")
        check(climb.top >= 6.9 && climb.aboard, String(format: "the stern ladder takes him up to the deck (feet up to %.1f over its bottom, the deck at 7; aboard %@)",
                                                         climb.top, climb.aboard ? "yes" : "no"))
        check(climb.jolt < 0.6, String(format: "climbing aboard nothing throws him about (biggest move in a tick %.2f)", climb.jolt))
        print(fails == 0 ? "boardcheck: all passed" : "boardcheck: \(fails) failed")
        return fails == 0 ? 0 : 1
    }
}
