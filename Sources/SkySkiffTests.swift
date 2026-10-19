import Foundation
import simd

// Sky Skiff checks (backlog A4; `questcheck --skiff-only`, and part of every questcheck run): the kit is crafted from
// ship parts; used on a roofed spot it says so and keeps the kit; used under open sky it inflates a skiff in front of
// the player (kit spent) hovering a step off the ground; it holds its height unpiloted, climbs on the balloons, flies
// on its propellers, can't hold height with an iron-loaded deck (weight matters), and comes back from a save where it
// was, block for block.
enum SkySkiffTests {
    static func run(game g: Game, check: (Bool, String) -> Void) {
        let w = g.world
        let enc0 = w.ships.encounters
        w.ships.encounters = false
        let craft = Recipes.match([Items.id("ship_balloon"), Items.id("ship_balloon"), Items.id("ship_balloon"),
                                   Items.id("ship_balloon"), Items.id("ship_helm"), Items.id("ship_balloon"),
                                   Items.id("ship_propeller"), Items.id("ship_engine"), Items.id("ship_propeller")], 3, 3)?.result
        check(craft.map { Items.key($0.item) } == SkySkiff.key, "skiff: five lift balloons, a helm, an engine and two propellers make a Sky Skiff Kit")

        let pos0 = g.player.pos, yaw0 = g.player.yaw, surv0 = g.survival, held0 = g.inventory.main[g.inventory.selected], toast0 = g.onToast
        let fly0 = g.player.flying
        var said = ""
        g.onToast = { said = $0 }
        var placed: [IVec3] = []
        defer {
            for q in placed { w.setBlock(q.x, q.y, q.z, AIR) }
            g.player.pos = pos0; g.player.yaw = yaw0; g.survival = surv0; g.inventory.main[g.inventory.selected] = held0; g.onToast = toast0
            g.player.flying = fly0; g.player.vel = .zero; w.ships.encounters = enc0      // (later checks walk and fight on foot)
        }
        g.survival = true
        g.inventory.main[g.inventory.selected] = ItemStack(Items.id(SkySkiff.key), 1)
        let ships0 = w.ships.list.count

        // Under a roof: no skiff, the kit kept.
        let fx = Int(floor(pos0.x)), fz = Int(floor(pos0.z)), fy = w.topY(fx, fz) + 1
        g.player.pos = V3(Float(fx) + 0.5, Float(fy), Float(fz) + 0.5); g.player.yaw = 0
        for z in (fz - 18)...(fz + 2) { for x in (fx - 9)...(fx + 9) where w.isAir(x, fy + 4, z) {
            w.setBlock(x, fy + 4, z, STONE); placed.append(IVec3(x, fy + 4, z))
        } }
        let roofed = g.skySkiffUse() && w.ships.list.count == ships0 && g.inventory.main[g.inventory.selected].count == 1 && said.contains("open sky")
        for q in placed { w.setBlock(q.x, q.y, q.z, AIR) }
        placed = []
        // A spot in the air (a platform over the ground: open sky whatever the terrain).
        let py = min(CH - 40, fy + 30)
        for z in (fz - 18)...(fz + 2) { for x in (fx - 9)...(fx + 9) where w.isAir(x, py - 1, z) {
            w.setBlock(x, py - 1, z, STONE); placed.append(IVec3(x, py - 1, z))
        } }
        g.player.pos = V3(Float(fx) + 0.5, Float(py), Float(fz) + 0.5); g.player.vel = .zero
        let used = g.skySkiffUse()
        guard let s = w.ships.list.dropFirst(ships0).first(where: { $0.name == SkySkiff.name }) else {
            check(false, "skiff: under a roof it says so (\(roofed)); under open sky it inflates (\(used), '\(said)')"); return
        }
        defer { if w.ships.list.contains(where: { $0 === s }) { w.ships.remove(s) } }
        let keel = s.toWorld(V3(0, s.localMin.y, 0)).y
        let ahead = s.pos.z < Float(fz) - 5 && abs(s.pos.x - Float(fx) - 0.5) < 1.5
        check(roofed && used && g.inventory.main[g.inventory.selected].isEmpty && ahead && s.helm != nil && s.balloons > 40 && s.engines == 1 && s.props.count == 3
              && keel > Float(py) && keel < Float(py) + 2,
              String(format: "skiff: under a roof it says so and keeps the kit (%@); under open sky it inflates ahead (kit spent), %d balloons, %.0f t, keel %.1f over the ground",
                     roofed ? "yes" : "no", s.balloons, s.mass, keel - Float(py)))

        // Flight (as ShipTest's airship: the ship physics at 60 Hz, the player off the deck).
        g.player.flying = true
        g.player.pos = s.pos + V3(14, 6, 14)
        func run(_ secs: Float) { for _ in 0..<Int(secs * 60) { w.ships.update(1.0 / 60, game: g) } }
        let lift = Float(s.balloons) * ShipTuning.balloonLift
        run(3)
        let y0 = s.pos.y
        run(3)
        let hovers = abs(s.pos.y - y0) < 0.6 && s.dirToWorld(V3(0, 1, 0)).y > 0.97
        s.autopilot = V3(0, 0, 1)
        let y1 = s.pos.y
        run(3)
        let climbed = s.pos.y - y1
        s.autopilot = V3(1, 0, 0)
        let a0 = s.pos
        run(6)
        let flew = simd_length(V2(s.pos.x - a0.x, s.pos.z - a0.z))
        s.autopilot = nil
        check(hovers && climbed > 4 && flew > 10,
              String(format: "skiff: it holds its height unpiloted (%@), climbs %.1f in 3 s on its balloons and flies %.1f blocks in 6 s on its propellers (lift %.0f t for %.0f t)",
                     hovers ? "yes" : "no", climbed, flew, lift, s.mass))

        // Persistence: saved and loaded back where it was, block for block (ShipManager.encode / decode, as a world save).
        let blocks = s.blockCount, at = s.pos, rot = s.rot.vector
        let data = w.ships.encode([s])
        w.ships.remove(s)
        let n1 = w.ships.list.count
        if let d = data { w.ships.decode(d) }
        let back = w.ships.list.dropFirst(n1).first { $0.name == SkySkiff.name }
        check(back != nil && back!.blockCount == blocks && simd_length(back!.pos - at) < 0.01 && simd_length(back!.rot.vector - rot) < 1e-3 && back!.helm != nil,
              "skiff: saved and loaded, it is back where it was left (\(back.map { "\($0.blockCount) of \(blocks) blocks" } ?? "missing"))")
        guard let b = back else { return }
        defer { w.ships.remove(b) }

        // Weight: iron on every free deck cell and it can't hold height even climbing.
        // (its flight can end over ground the harness never loaded, where a ship sleeps: load round it)
        _ = w.loadSync(center: b.pos, radius: 3)
        let iron = Blocks.id("iron_block")
        var cargo = 0
        for y in 0..<(b.grid.sy - 1) { for z in 0..<b.grid.sz { for x in 0..<b.grid.sx {
            guard b.grid.get(x, y + 1, z) == AIR, Blocks.key(b.grid.get(x, y, z)).hasSuffix("_planks") else { continue }
            for k in 1...2 where y + k < b.grid.sy && b.grid.get(x, y + k, z) == AIR { w.ships.setBlock(b, IVec3(x, y + k, z), iron); cargo += 1 }
        } } }
        b.autopilot = V3(0, 0, 1)
        run(1)
        let h0 = b.pos.y
        run(3)
        let sank = b.pos.y - h0
        let why = String(format: " [asleep %@, vel.y %.2f, lift %.2f, hoverY %.1f, kin %@]", b.asleep ? "y" : "n", b.vel.y, b.liftLevel, b.hoverY ?? -1, b.kinematic ? "y" : "n")
        b.autopilot = nil
        check(b.mass > Float(b.balloons) * ShipTuning.balloonLift && sank < -1,
              String(format: "skiff: loaded with %d iron blocks (%.0f t over %.0f t of lift) it sinks %.1f in 3 s with the balloons full", cargo, b.mass, Float(b.balloons) * ShipTuning.balloonLift, -sank) + why)
    }
}
