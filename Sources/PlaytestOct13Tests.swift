import Foundation
import simd

// Oct 12 evening / Oct 13 morning playtest items (docs/roadmap/backlog.md P146-P174) on a sky strip; questcheck
// `--oct13-only`.
//   P150       rounds the player didn't fire (soldiers, companions, wall turrets) pass through livestock
//   P147/P166  a galloping horse follows the ground down one-block steps (no fall and thump every step)
//   P153/P164  a 3-4 block drop is taken; a 1-block gap is squeezed through; under a 2-high overhang the rider ducks;
//              low bushes are trampled
enum PlaytestOct13Tests {
    static func run(_ g: Game, check: (Bool, String) -> Void) {
        let w = g.world
        let wasRiding = g.riding, wasPos = g.player.pos, wasSurvival = g.survival, savedMobs = g.mobs.mobs
        defer {
            g.riding = wasRiding; g.player.pos = wasPos; g.survival = wasSurvival; g.mobs.mobs = savedMobs
            g.player.moveYaw = nil; g.rideInput = MoveInput(); g.mobs.rebuildIndex()
        }
        let sx = Int(floor(g.player.pos.x)), sz = Int(floor(g.player.pos.z))
        _ = w.loadSync(center: V3(Float(sx), 200, Float(sz)), radius: 5)
        let Y = min(CH - 30, w.topY(sx, sz) + 60)
        let stone = Blocks.id("stone"), leaves = Blocks.id("oak_leaves")
        let z0 = sz + 63, z1 = sz - 64
        func clear() {
            w.deferRemesh = true
            for z in z1...z0 { for x in sx - 3...sx + 3 {
                for y in Y - 8...Y + 6 where w.block(x, y, z) != AIR { w.setBlock(x, y, z, AIR) }
                w.setBlock(x, Y, z, stone)
            } }
            w.deferRemesh = false
        }
        clear()
        defer { w.deferRemesh = true; for z in z1...z0 { for x in sx - 3...sx + 3 { for y in Y - 8...Y + 6 { w.setBlock(x, y, z, AIR) } } }; w.deferRemesh = false }
        let lane0 = V3(Float(sx) + 0.5, Float(Y + 1), Float(z0) - 1.5)

        // P189: a document found and read is kept whole in the journal, listed on its contents page.
        do {
            let was = g.journal
            g.journal = []
            let j = DeepJournals.all["capital_duty_log"]
            if let j { g.logDocument(j.title, j.pages); g.logDocument(j.title, j.pages) }
            g.logMessage("A test message")
            let pages = g.journalPages
            check(j != nil && Items.has("town_pamphlet") && g.journal.count == 2 && pages.first?.contains("2. Capital Duty Log") == true
                  && Array(pages.dropFirst().prefix(j?.pages.count ?? 0)) == j?.pages && pages.last?.contains("A test message") == true,
                  "P189: a Capital Duty Log read is kept whole in the journal (contents page, its \(j?.pages.count ?? 0) pages, then messages)")
            g.journal = was
        }

        // P150: livestock.
        do {
            let cow = Mob(.cow, at: lane0 + V3(0, 0, -6))
            g.mobs.mobs = [cow]; g.mobs.rebuildIndex()
            let o = lane0 + V3(0, 0.8, 0), d = V3(0, 0, -1)
            let soldier = Armory.mobHit(g, o, d, 12, shooter: nil, friendly: true, spareStock: true)
            let player = Armory.mobHit(g, o, d, 12, shooter: nil, friendly: false, spareStock: false)
            let mine = Slug(pos: o, vel: d, kind: .bullet, damage: 4, fromPlayer: true, shooter: nil, by: "Player", life: 1, gravity: 0)
            let turret = Slug(pos: o, vel: d, kind: .bullet, damage: 4, fromPlayer: true, shooter: nil, by: "your wall turret", life: 1, gravity: 0)
            let pal = Slug(pos: o, vel: d, kind: .bullet, damage: 4, fromPlayer: true, shooter: ObjectIdentifier(cow), by: "Companion", life: 1, gravity: 0)
            check(soldier == nil && player?.0 === cow && Armory.playersOwn(mine) && !Armory.playersOwn(turret) && !Armory.playersOwn(pal) && MobKind.cow.livestock && !MobKind.zombie.livestock,
                  "P150: a soldier's round passes through a cow, the player's own hits it; wall turret and companion rounds spare it too")
            g.mobs.mobs = []; g.mobs.rebuildIndex()
        }

        func horse() -> Mob {
            let h = Mob(.horse, at: lane0)
            h.variant = (15 << 4) | (8 << 8)
            h.breed = HorseBreed.saddlebred.rawValue
            h.owner = true; h.saddled = true; h.persistent = true; h.health = 30
            h.yaw = 0
            g.riding = h; g.player.yaw = 0; g.player.moveYaw = nil
            g.player.pos = h.pos + V3(0, h.height * 0.75, 0)
            return h
        }
        let dt: Float = 1.0 / 72
        // Gallops north (-z) until `stop` says so or 12 s pass; `each` sees every tick.
        func ride(_ h: Mob, until stop: () -> Bool, each: () -> Void = {}) {
            for i in 0..<Int(12 / dt) {
                var mi = MoveInput(forward: 1)
                mi.spur = i == 2 || i == 20
                g.rideInput = mi
                let y0 = h.pos.y, wasGround = h.onGround
                h.update(dt, game: g)
                h.easeStep(fromY: y0, wasGround: wasGround, dt)
                each()
                if stop() || g.riding !== h { break }
            }
        }
        g.survival = true

        // P147/P166: a long slope of one-block steps, one every 3 blocks.
        do {
            clear()
            let top = z0 - 12
            w.deferRemesh = true
            for k in 0..<60 { for x in sx - 3...sx + 3 {
                let drop = min(8, k / 3)
                w.setBlock(x, Y, top - k, AIR); w.setBlock(x, Y - drop, top - k, stone)
            } }
            w.deferRemesh = false
            let h = horse()
            var air = 0, worstDrawn: Float = 0, lastDrawn = h.pos.y + h.viewDY, steps = 0, lastY = h.pos.y
            ride(h, until: { h.pos.z < Float(top - 58) }) {
                if h.pos.z < Float(top) && h.pos.z > Float(top - 56) {
                    if !h.onGround { air += 1 }
                    let dy = h.pos.y + h.viewDY
                    worstDrawn = max(worstDrawn, abs(dy - lastDrawn) / dt)
                    if h.pos.y < lastY - 0.5 { steps += 1 }
                }
                lastDrawn = h.pos.y + h.viewDY; lastY = h.pos.y
            }
            check(h.pos.z < Float(top - 50) && steps >= 6 && air <= 3 && worstDrawn < 9,
                  String(format: "P147: a gallop down %d one-block steps stays on the ground (%d airborne ticks) and the drawn horse sinks at most %.1f b/s", steps, air, worstDrawn))
            g.riding = nil
        }

        // P153/P164: a 4-block drop is taken.
        do {
            clear()
            let edge = z0 - 20
            w.deferRemesh = true
            for z in z1...edge { for x in sx - 3...sx + 3 { w.setBlock(x, Y, z, AIR); w.setBlock(x, Y - 4, z, stone) } }
            w.deferRemesh = false
            let h = horse()
            ride(h, until: { h.pos.z < Float(edge - 15) })
            check(h.pos.z < Float(edge - 10) && h.pos.y < Float(Y - 2), String(format: "P153: the horse takes a 4-block drop at a gallop (z %.1f past %d)", h.pos.z, edge))
            g.riding = nil
        }

        // P164: a 1-block gap in a wall, a 2-high overhang and a row of bushes.
        do {
            clear()
            let wall = z0 - 20, roof = z0 - 40, bush = z0 - 60
            w.deferRemesh = true
            for x in sx - 3...sx + 3 {
                for y in Y + 1...Y + 4 where x != sx { w.setBlock(x, y, wall, stone) }
                for z in roof - 3...roof { w.setBlock(x, Y + 3, z, stone) }
                w.setBlock(x, Y + 1, bush, leaves)
            }
            w.deferRemesh = false
            let h = horse()
            var ducked: Float = 0
            ride(h, until: { h.pos.z < Float(bush - 6) }) { if h.pos.z < Float(roof + 1) && h.pos.z > Float(roof - 3) { ducked = max(ducked, h.hs.duck) } }
            check(h.pos.z < Float(bush - 4) && ducked > 0.3 && h.hs.trampled > 0,
                  String(format: "P164: through a 1-block gap, under a 2-high overhang (rider ducks %.2f) and through a bush (%d trampled), z %.1f", ducked, h.hs.trampled, h.pos.z))
            g.riding = nil
        }
    }

    // P169 (Oct 13: short freezes while galloping across new ground, one big at 10:11): his world's seed, from where
    // he rode, at a gallop's speed and a mid render distance; every tick over 40 ms with its stages (TickProf).
    static func freezes(_ g: Game, check: (Bool, String) -> Void) {
        let r = HitchProbe.run(device: g.world.device, seed: 3931512493184456980, walk: 60, stand: 20, speed: 15, over: 40, rd: 10,
                               start: V2(9768, -13387))
        for s in r.slow.prefix(6) { print(String(format: "freeze: %.0f ms at %.1f s: %@", s.ms, s.at, s.stages)) }
        let worst = r.slow.first?.ms ?? 0
        check(worst < 150, String(format: "P169: a 60 s gallop over new ground at distance 10: %d ticks over 40 ms, worst %.0f ms (of %d ticks)",
                                  r.slow.count, worst, r.ticks))
    }

    // P173: what stands south of World376's 9110 -13846 within 1800 blocks (the "odd tower in the distance"): every
    // structure start of every type, with its height above the ground.
    static func towers(_ g: Game) {
        let w = World(seed: 3931512493184456980, device: g.world.device, save: nil)
        guard let sc = (w.gen as? WorldGen)?.structures else { print("tower: no structures"); return }
        let x = 9110, z = -13846
        for t in sc.types {
            let span = t.spacing * CS
            let n = 1800 / span + 1
            let rx0 = floorDiv(x, span), rz0 = floorDiv(z, span)
            for rz in (rz0 - n)...(rz0 + n) { for rx in (rx0 - n)...(rx0 + n) {
                guard let st = sc.start(t, regionX: rx, regionZ: rz) else { continue }
                let cx = (st.min.x + st.max.x) / 2, cz = (st.min.z + st.max.z) / 2
                let d = simd_length(V2(Float(cx - x), Float(cz - z)))
                guard d < 1800, cz > z - 200 else { continue }
                print("tower: \(st.kind) at \(cx) \(cz), \(Int(d)) blocks, y \(st.min.y)-\(st.max.y) (\(st.max.y - st.min.y) tall)")
            } }
        }
    }

}
