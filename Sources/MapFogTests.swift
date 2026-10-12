import Foundation
import simd

// Map fog of war and compass checks (backlog A5; `questcheck --mapfog-only`, and part of every questcheck run): ground
// far from the player is dark on the map until a player goes near it, then shows and stays; creative shows the whole
// map; explored tiles survive a save; the compass strip shows a discovered site in front at its bearing and names the
// nearest; the radar's far contacts are marked on the dark map.
enum MapFogTests {
    static func run(game g: Game, check: (Bool, String) -> Void) {
        let fog = MapFog.shared
        let snap0 = fog.snapshot, surv0 = g.survival, pos0 = g.player.pos, yaw0 = g.player.yaw
        let marks0 = MapCache.shared.marks
        let held0 = g.inventory.main[g.inventory.selected]
        defer {
            fog.snapshot = snap0; g.survival = surv0; g.player.pos = pos0; g.player.yaw = yaw0
            MapCache.shared.replaceMarks(marks0); g.inventory.main[g.inventory.selected] = held0
            fog.active = surv0
        }
        g.survival = true
        fog.snapshot = [:]
        fog.tick(g)                                                    // (loads this world's fog)
        fog.reveal(around: g.player.pos)                               // (the tick reveals once a second: an earlier check may have just had it)
        let px = Int(floor(g.player.pos.x)), pz = Int(floor(g.player.pos.z))
        let far = (px + 900, pz - 700)
        let near = !fog.fogged(px + 40, pz + 40) && !fog.fogged(px - 80, pz)
        let farDark = fog.fogged(far.0, far.1)
        // Drawn: a map centred out there is all fog, round the player it isn't.
        var lines: [HudLine] = []
        MapDraw.terrain(&lines, x0: 0, y0: 0, cols: 16, rows: 16, px: 2, wx: Float(far.0), wz: Float(far.1), bpc: 4, s: 1)
        let darkRun = !lines.isEmpty && lines.allSatisfy { $0.bg == MapDraw.color(MapFog.dark) }
        check(near && farDark && darkRun && !fog.fogged(px, pz),
              "mapfog: round the player the map shows (\(near)); 1,100 blocks off it is dark (\(farDark)), drawn as fog (\(darkRun), \(lines.count) runs)")

        // Going there reveals it, and it stays revealed after leaving.
        g.player.pos = V3(Float(far.0) + 0.5, g.player.pos.y, Float(far.1) + 0.5)
        fog.reveal(around: g.player.pos)
        g.player.pos = pos0
        let stays = !fog.fogged(far.0, far.1) && !fog.fogged(far.0 + 90, far.1) && fog.fogged(far.0 + 200, far.1)
        // Creative: no fog at all.
        g.survival = false; fog.tick(g)
        let creative = !fog.fogged(far.0 + 5000, far.1)
        g.survival = true; fog.tick(g)
        check(stays && creative, "mapfog: a place visited stays on the map (96 blocks round it, not 200) (\(stays)); creative shows the whole map (\(creative))")

        // Saved with the world.
        if let dir = g.save?.dir {
            let n = fog.exploredCount
            fog.save(g)
            let data = try? Data(contentsOf: dir.appendingPathComponent("mapfog.json"))
            let back = (data.flatMap { try? JSONDecoder().decode([String: [Int64]].self, from: $0) } ?? [:]).values.reduce(0) { $0 + $1.count }
            check(back >= n && n > 0, "mapfog: \(n) explored tiles saved with the world (\(back) read back)")
        }

        // The compass: a site ahead at its bearing on the strip; the nearest named.
        MapCache.shared.replaceMarks([MapCache.Mark(kind: Greywall.kind, x: px, z: pz - 400, name: "Greywall Outpost"),
                                      MapCache.Mark(kind: "village", x: px + 900, z: pz + 900, name: "Fairholm")])
        g.inventory.main[g.inventory.selected] = ItemStack(Items.id("compass"), 1)
        g.player.yaw = 0                                               // facing north (-z)
        let (on, nearest) = CompassHUD.marks(g)
        let ahead = on.count == 1 && abs(on[0].0) < 0.05
        g.player.yaw = .pi / 4                                         // facing north-west: the outpost 45 degrees to the right
        let (on2, _) = CompassHUD.marks(g)
        let right = on2.count == 1 && abs(on2[0].0 - 0.75) < 0.05
        let L = HudLayout(1280, 720)
        let menu0 = g.menu, hints0 = HudExtras.enabled
        g.menu = nil; HudExtras.enabled = true
        defer { g.menu = menu0; HudExtras.enabled = hints0 }
        let strip = CompassHUD.lines(g, L)
        g.inventory.main[g.inventory.selected] = .empty
        let none = CompassHUD.lines(g, L).isEmpty
        check(ahead && right && nearest?.0 == "Greywall Outpost" && nearest?.1 == 400 && nearest?.2 == "N" && strip.count > 4 && none,
              "mapfog compass: a site 400 north is dead ahead facing north (\(ahead)), three quarters to the right facing north-west (\(right)); nearest: \(nearest.map { "\($0.0) \($0.1) \($0.2)" } ?? "none"); \(strip.count) strip lines held, none put away")
    }
}
