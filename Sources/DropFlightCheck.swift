import Foundation
import simd

// P461's check (questcheck --dropflight): a taken Capital Dropship left in the air 30 blocks up comes down and rests
// on the ground; flown ahead with sprint held it reaches its overdrive speed and tears through a wall of leaves and
// planks in its way; rammed into a stone wall it stops there and loses plating; its helm is only taken from inside.
enum DropFlightCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        guard g.dim.dim == .overworld else { check(false, "dropflight: needs the overworld"); return }
        let w = g.world
        let home = g.player.pos
        _ = w.loadSync(center: home, radius: 5)
        let n0 = w.ships.list.count
        let gx = Int(floor(home.x)), gz = Int(floor(home.z))
        let start = V3(home.x, Float(w.topY(gx, gz)) + 30, home.z)
        w.ships.callDropship(faction: .steelhold, from: start, to: start + V3(0, 0, -60), game: g, sync: true)
        guard let s = w.ships.list.dropFirst(n0).first(where: { $0.role == "dropship" && $0.parent == nil }) else {
            check(false, "dropflight: a Capital Dropship spawns"); return
        }
        defer {
            if w.ships.pilot === s { w.ships.pilot = nil }
            for t in w.ships.list where t === s || t.parent === s { w.ships.remove(t) }
            w.ships.capState.removeValue(forKey: s.id)
        }
        s.captured = true
        s.vel = .zero; s.angVel = .zero
        for _ in 0..<(60 * 14) { w.ships.update(1.0 / 60, game: g) }
        let cx = Int(floor(s.pos.x)), cz = Int(floor(s.pos.z))
        let rest = s.worldMin.y - Float(Capital.firmTop(w, cx, cz) + 1)
        check(abs(rest) < 0.6 && simd_length(s.vel) < 1,
              String(format: "dropflight: left 30 blocks up with nobody at the controls it comes down and rests (keel %.2f over the ground, %.1f m/s)", rest, simd_length(s.vel)))
        // A wall of leaves and planks 10 blocks ahead of the nose, as high as the hull.
        let fw = s.dirToWorld(V3(0, 0, -1))
        let fh = simd_normalize(V3(fw.x, 0, fw.z) + V3(1e-5, 0, 0)), side = V3(-fh.z, 0, fh.x)
        let wallAt = s.pos + fh * 20
        var placed = 0
        for k in -6...6 { for dy in 0...6 {
            let p = wallAt + side * Float(k)
            let x = Int(floor(p.x)), z = Int(floor(p.z)), y = Int(floor(s.worldMin.y)) + dy
            if w.block(x, y, z) == AIR { w.setBlock(x, y, z, Blocks.id(dy % 2 == 0 ? "oak_leaves" : "oak_planks")); placed += 1 }
        } }
        let crushed0 = ShipManager.crushed
        w.ships.pilot = s
        var top: Float = 0
        for _ in 0..<(60 * 3) {
            s.throttle = 1; s.boost = true; s.climb = 0; s.steer = 0; s.strafe = 0
            w.ships.update(1.0 / 60, game: g)
            top = max(top, simd_length(V2(s.vel.x, s.vel.z)))
        }
        let crushed = ShipManager.crushed - crushed0
        // (Its top speed in the clear: at 83 m/s three seconds over the ground ends in the first hillside it rams.)
        s.pos.y += 40; s.prevPos = s.pos; s.updateBounds()
        for _ in 0..<(60 * 3) {
            s.throttle = 1; s.boost = true; s.climb = 0; s.steer = 0; s.strafe = 0
            w.ships.update(1.0 / 60, game: g)
            top = max(top, simd_length(V2(s.vel.x, s.vel.z)))
        }
        w.ships.pilot = nil
        check(top > 70 && crushed >= 10,
              String(format: "dropflight: flown ahead in overdrive it reaches %.0f m/s (P499: 83 = 300 km/h; 55 without) and crushed %d of the %d leaf and plank blocks in its way", top, crushed, placed))
        // Ramming: a stone wall 30 blocks ahead, wider and taller than the hull, flown into in overdrive. It stops at the
        // wall (it flew through), loses plating where it struck, and the wall stands.
        do {
            let fw = s.dirToWorld(V3(0, 0, -1))
            let fh = simd_normalize(V3(fw.x, 0, fw.z) + V3(1e-5, 0, 0)), side = V3(-fh.z, 0, fh.x)
            let half = max(s.worldMax.x - s.worldMin.x, s.worldMax.z - s.worldMin.z) * 0.5
            let wallAt = s.pos + fh * (half + 30)
            _ = w.loadSync(center: wallAt, radius: 3)                 // (the leaf run took it past the loaded ground)
            var stone: [IVec3] = []
            for k in -14...14 { for dy in -2...14 { for t in 0...1 {
                let p = wallAt + side * Float(k) + fh * Float(t)
                let c = IVec3(Int(floor(p.x)), Int(floor(s.worldMin.y)) + dy, Int(floor(p.z)))
                if !stone.contains(c) { w.setBlock(c.x, c.y, c.z, Blocks.id("stone_bricks")); stone.append(c) }
            } } }
            let rams0 = ShipManager.rams, torn0 = ShipManager.ramTorn, blocks0 = s.blockCount
            w.ships.pilot = s
            var fast: Float = 0, past = -Float.infinity
            for _ in 0..<(60 * 4) {
                s.throttle = 1; s.boost = true; s.climb = 0; s.steer = 0; s.strafe = 0
                w.ships.update(1.0 / 60, game: g)
                fast = max(fast, simd_dot(s.vel, fh))
                past = max(past, simd_dot(s.pos - wallAt, fh))
            }
            w.ships.pilot = nil
            let standing = stone.filter { w.block($0.x, $0.y, $0.z) != AIR }.count
            let rams = ShipManager.rams - rams0, torn = ShipManager.ramTorn - torn0
            check(past < 0 && rams >= 1 && torn >= 1 && standing == stone.count,
                  String(format: "dropflight: rammed into a stone wall at %.0f m/s it stops at it (its centre at most %.1f blocks short of the wall's face, %.1f the hull's half length), hits it %d times, tears %d plates off (%d -> %d blocks); the wall stands (%d of %d)",
                         fast, -past, half, rams, torn, blocks0, s.blockCount, standing, stone.count))
            for c in stone { w.setBlock(c.x, c.y, c.z, AIR) }
        }
        // Mounting: let down to rest, its helm is not taken from the ground just outside the hull, only from inside.
        do {
            _ = w.loadSync(center: s.pos, radius: 3)
            for _ in 0..<(60 * 10) { w.ships.update(1.0 / 60, game: g) }
            guard let stand = g.helmStand(s) else { check(false, "dropflight: the dropship has a helm"); return }
            let helm = s.toWorld(stand)
            let ox = s.worldMax.x + 1.5, oz = helm.z
            let outside = V3(ox, Float(w.topY(Int(floor(ox)), Int(floor(oz))) + 1), oz)
            let pos0 = g.player.pos, aboard0 = w.ships.aboard
            defer { g.player.pos = pos0; w.ships.aboard = aboard0 }
            w.ships.aboard = nil
            g.player.pos = outside
            let fromGround = g.commandeerable() === s
            g.player.pos = helm + V3(0, 0.05, 0)
            let fromHelm = g.commandeerable() === s
            check(!fromGround && fromHelm,
                  String(format: "dropflight: its helm is taken from inside (%@) but not from the ground beside the hull, %.1f blocks from the helm (%@)",
                         fromHelm ? "yes" : "no", simd_length(outside - helm), fromGround ? "taken: wrong" : "refused"))
        }
        // P499 (Oct 30 20:35, flying the Meridian: "the drop ship should chase, chase my ship and just start firing at me
        // relentlessly"): a Capital Dropship whose target runs at 40 m/s gives chase and keeps close to it.
        do {
            let n1 = w.ships.list.count
            let a0 = s.pos + V3(0, 30, 0)
            guard w.ships.callDropship(faction: .steelhold, from: a0, to: a0 + V3(0, 0, -60), game: g, sync: true),
                  let d = w.ships.list.dropFirst(n1).first(where: { $0.role == "dropship" && $0.parent == nil }),
                  let st = w.ships.capState[d.id] else { check(false, "dropflight: a second dropship spawns to give chase"); return }
            defer {
                for t in w.ships.list where t === d || t.parent === d { w.ships.remove(t) }
                w.ships.capState.removeValue(forKey: d.id)
            }
            let runner = Mob(.horse, at: a0 + V3(40, 0, 0))
            runner.vel = V3(40, 0, 0)
            st.phase = 4; st.phaseT = 0; st.retarget = 1e9
            st.target = CapTarget(point: runner.pos, vel: runner.vel, ship: nil, mob: runner)
            var worst: Float = 0, fastest: Float = 0
            let pos0 = g.player.pos
            defer { g.player.pos = pos0 }
            for i in 0..<(60 * 10) {
                runner.pos += runner.vel / 60
                g.player.pos = runner.pos + V3(0, 40, 0)          // (a ship past his active distance sleeps: P376)
                w.ships.update(1.0 / 60, game: g)
                if i > 60 * 6 { worst = max(worst, simd_length(V2(d.pos.x - runner.pos.x, d.pos.z - runner.pos.z))) }
                fastest = max(fastest, simd_length(V2(d.vel.x, d.vel.z)))
            }
            check(worst < 80 && fastest > 35 && st.phase == 4,
                  String(format: "dropflight: a dropship gives chase to a target running at 40 m/s (up to %.0f m/s; at most %.0f blocks off it over the last 4 s of 10; phase %d)", fastest, worst, st.phase))
        }
        // P504 (Nov 1 07:50:43, a Capital city: "the drop ship is still morphing through buildings when it flies"): a
        // tower 80 blocks tall across its way in. It goes over it, never through it.
        do {
            let n1 = w.ships.list.count
            let a0 = s.pos + V3(0, 20, 0)
            let far = a0 + V3(0, 0, -170)
            guard w.ships.callDropship(faction: .steelhold, from: a0, to: far, game: g, sync: true),
                  let d = w.ships.list.dropFirst(n1).first(where: { $0.role == "dropship" && $0.parent == nil }),
                  let st = w.ships.capState[d.id] else { check(false, "dropflight: a third dropship spawns to fly at a tower"); return }
            var tower: [IVec3] = []
            defer {
                for t in w.ships.list where t === d || t.parent === d { w.ships.remove(t) }
                w.ships.capState.removeValue(forKey: d.id)
                for c in tower { w.setBlock(c.x, c.y, c.z, AIR) }
            }
            let tx = Int(floor(a0.x)), tz = Int(floor(a0.z)) - 70
            _ = w.loadSync(center: V3(Float(tx), a0.y, Float(tz)), radius: 4)
            let foot = w.topY(tx, tz) + 1
            for z in (tz - 3)...(tz + 3) { for x in (tx - 3)...(tx + 3) { for y in foot..<(foot + 80) {
                w.setBlock(x, y, z, Blocks.id("stone_bricks")); tower.append(IVec3(x, y, z))
            } } }
            let topT = Float(foot + 80)
            st.phase = 1; st.phaseT = 0
            var through = 0, passed: Float = 0
            let pos0 = g.player.pos
            defer { g.player.pos = pos0 }
            for _ in 0..<(60 * 30) {
                g.player.pos = d.pos + V3(0, 10, 0)              // (a ship past his active distance sleeps: P376)
                w.ships.update(1.0 / 60, game: g)
                if d.worldMax.x > Float(tx - 3) && d.worldMin.x < Float(tx + 4) && d.worldMax.z > Float(tz - 3) && d.worldMin.z < Float(tz + 4)
                    && d.worldMin.y < topT { through += 1 }
                passed = max(passed, Float(tz) - d.pos.z)
                if st.phase != 1 { break }
            }
            check(through == 0 && passed > 20,
                  String(format: "dropflight: flying in at a tower 80 blocks tall across its way it goes over it (%d ticks with the hull in it; %.0f blocks past it)", through, passed))
        }
        // P504 (Nov 1 07:55:57, "Ship also needs a place to refill ammunition that you craft"): a Shell Crate, crafted
        // from two iron, two gunpowder and a copper ingot, used aboard her puts a quarter of a full load in her magazine.
        do {
            guard let st = w.ships.capState[s.id] else { check(false, "shellcrate: the dropship has its state"); return }
            let full = ShipShells.full(w.ships, s)
            st.rounds = 0
            let surv0 = g.survival, sel = g.selected, slot0 = g.inventory.main[sel]
            defer { g.survival = surv0; g.inventory.main[sel] = slot0 }
            g.survival = true
            g.inventory.main[sel] = ItemStack(Items.id(ShipShells.key), 5)
            _ = g.loadShells(s)
            let one = st.rounds
            for _ in 0..<4 { _ = g.loadShells(s) }
            let left = g.inventory.main[sel].count
            let crafted = Recipes.match(["iron_ingot", "iron_ingot", "gunpowder", "gunpowder", "copper_ingot", "", "", "", ""].map { $0.isEmpty ? ItemID(0) : Items.id($0) }, 3, 3)
            check(one == full / 4 && st.rounds == full && left == 1 && crafted.map { Items.key($0.result.item) } == ShipShells.key,
                  "shellcrate: a crate aboard her empty magazine loads \(one) of \(full) rounds; four fill it and a fifth stays in the pack (\(left) left); it is crafted (\(crafted != nil))")
        }
    }
}
