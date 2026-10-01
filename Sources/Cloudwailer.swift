import Foundation
import simd

// Cloudwailer (the reference happy ghast): a big, gentle flying mob. Snowballs tempt it and heal it
// (1 each); it heals faster in water or rain. A harness (16 colours: 3 leather + 2 glass + 1 wool)
// lets a player ride it: look to steer, forward to fly, jump to rise. Wailerlings (babies, a quarter
// size) grow up in 20 minutes. It has 20 health and takes no fall damage.
enum Cloudwailer {
    static var harnessColor: [ItemID: Int] = [:]

    static func register(_ reg: ItemRegistry) {
        for (i, c) in BlockRegistry.colors.enumerated() {
            let n = "\(c.0)_harness"
            guard !reg.has(n) else { continue }
            var d = ItemDef(n, "\(c.1) Harness")
            d.maxStack = 1
            d.texKey = "item_harness"
            d.overlay = "item_harness_band"
            d.overlayColor = BlockRegistry.colorHex[c.0] ?? 0xFFFFFF
            harnessColor[reg.add(d)] = i
        }
    }

    static func recipes() -> [Recipe?] {
        BlockRegistry.colors.map { c in
            Recipes.shaped(["LLL", "GWG"], ["L": "leather", "G": "glass", "W": "\(c.0)_wool"], "\(c.0)_harness")
        }
    }

    static let shape: [String] = [
        "................",
        "................",
        "................",
        "..111111111111..",
        "..1bbbbbbbbbb1..",
        "..1b11bbbb11b1..",
        "..1bbbbbbbbbb1..",
        "..1bbbbbbbbbb1..",
        "..1111111111111.",
        "...............1",
        "..g..........g..",
        ".ggg........ggg.",
        ".ggg........ggg.",
        "..g..........g..",
        "................",
        "................",
    ]

    static func painters(_ p: inout [String: TextureGen.Painter]) {
        let rows = shape.map { Array($0) }
        p["item_harness"] = { x, y in
            guard y < rows.count, x < rows[y].count else { return TextureGen.clear }
            switch rows[y][x] {
            case "1": return V4(0.35, 0.22, 0.12, 1)
            case "g": return V4(0.75, 0.85, 0.95, 1)
            default: return TextureGen.clear
            }
        }
        p["item_harness_band"] = { x, y in
            guard y < rows.count, x < rows[y].count, rows[y][x] == "b" else { return TextureGen.clear }
            return V4(1, 1, 1, 1)
        }
    }
}

extension Mob {
    // Free-flying behaviour (called from animalAI; returns the walk speed, always 0: it moves by velocity).
    func cloudwailerAI(_ dt: Float, _ g: Game) -> Float {
        let player = g.player.pos
        let dist = simd_length(player - pos)
        // Heals 1 health every 20 s, every 5 s when wet.
        fireTick += dt
        let wet = g.isRainingAt(pos) || Blocks.fluidKind[Int(g.world.block(Int(floor(pos.x)), Int(floor(pos.y)), Int(floor(pos.z))))] == 1
        if fireTick >= (wet ? 5 : 20) { fireTick = 0; health = min(spec.health, health + 1) }
        var goal: V3
        if Items.key(g.held.item) == "snowball" && dist < 16 && g.alive {
            // Tempted: hover a few blocks from the player at eye height.
            let away = dist > 0.1 ? (pos - player) / dist : V3(1, 0, 0)
            goal = player + away * (4 + halfW) + V3(0, 1, 0)
            face(player)
        } else if saddled, let h = home, simd_length(h - pos) > 3 {
            goal = h                                               // harnessed ones stay where they were left
        } else {
            if aiTimer <= 0 || flyTarget == nil {
                aiTimer = Float.random(in: 4...9)
                var t = pos + V3(Float.random(in: -12...12), Float.random(in: -3...3), Float.random(in: -12...12))
                // Keep to 4-12 blocks above the ground.
                let ground = Float(g.world.topY(Int(floor(t.x)), Int(floor(t.z))) + 1)
                t.y = max(ground + 4, min(ground + 12, t.y))
                flyTarget = t
            }
            goal = flyTarget ?? pos
            face(goal)
        }
        let d = goal - pos
        let l = simd_length(d)
        let sp: Float = baby ? 2 : 1.5
        let want: V3 = l > 0.5 ? d * (min(sp, l) / l) : V3.zero
        let k: Float = min(1, dt * 1.5)
        vel += (want - vel) * k
        walkPhase += dt
        return 0
    }

    // Ridden (from updateRidden): the rider steers with the view; forward flies, jump rises.
    func rideCloudwailer(_ dt: Float, _ g: Game) {
        let w = g.world
        let inp = g.rideInput
        yaw = g.player.yaw
        var target = g.player.look * (4.5 * max(0, inp.forward))
        target += V3(-sinf(yaw + .pi / 2), 0, -cosf(yaw + .pi / 2)) * (-2 * inp.strafe)
        if inp.jump { target.y += 3 }
        vel += (target - vel) * min(1, dt * 2.5)
        let hit = w.moveBody(&pos, halfW: halfW, height: height, vel * dt, step: 0, onGround: false)
        if hit.x { vel.x = 0 }
        if hit.y { vel.y = 0 }
        if hit.z { vel.z = 0 }
        home = pos
        walkPhase += dt
        g.player.pos = pos + V3(0, height, 0)
        g.player.vel = .zero
        g.player.airPeak = g.player.pos.y
    }

    // Ridden nautilus: swims where the rider looks, jump dashes (every 2 s); the rider keeps breathing.
    func rideNautilus(_ dt: Float, _ g: Game) {
        let w = g.world
        let inp = g.rideInput
        yaw = g.player.yaw
        let wet = Blocks.fluidKind[Int(w.block(Int(floor(pos.x)), Int(floor(pos.y + 0.4)), Int(floor(pos.z))))] == 1
        attackCooldown -= dt
        if wet {
            let target = g.player.look * (5.5 * max(0, inp.forward))
            if inp.jump && attackCooldown <= 0 { attackCooldown = 2; vel += g.player.look * 10 }
            vel += (target - vel) * min(1, dt * 2)
            g.applyEffect(.waterBreathing, amp: 0, seconds: 2)
        } else {
            vel.y -= 28 * dt
            vel.x *= expf(-4 * dt); vel.z *= expf(-4 * dt)
        }
        let hit = w.moveBody(&pos, halfW: halfW, height: height, vel * dt, step: 0.5, onGround: onGround)
        if hit.x { vel.x = 0 }
        if hit.y { onGround = vel.y < 0; vel.y = 0 } else { onGround = false }
        if hit.z { vel.z = 0 }
        walkPhase += dt * 4
        g.player.pos = pos + V3(0, height * 0.6, 0)
        g.player.vel = .zero
        g.player.airPeak = g.player.pos.y
    }
}

// Model: a soft white cube with a calm face, short tentacles, and harness + goggles when saddled.
func cloudwailerParts(_ m: Mob) -> [Part] {
    let white = V3(0.95, 0.95, 0.97), dark = V3(0.25, 0.25, 0.3)
    var p: [Part] = [box(-32, 0, -32, 64, 64, 64, white, 4)]
    // Closed happy eyes and a small mouth on the front (-Z).
    p.append(box(-20, 38, -32.4, 12, 3, 0.4, dark)); p.append(box(8, 38, -32.4, 12, 3, 0.4, dark))
    p.append(box(-4, 26, -32.4, 8, 3, 0.4, dark))
    for i in 0..<9 {
        let x = Float(i % 3) * 20 - 20, z = Float(i / 3) * 20 - 20
        let len: Float = 10 + Float((i * 7) % 5) * 2
        p.append(Part(mn: V3(x - 2, -len, z - 2), mx: V3(x + 2, 0, z + 2), pivot: V3(x, 0, z),
                      rotX: sinf(m.walkPhase * 2 + Float(i)) * 0.25, color: white * 0.92, pattern: 4))
    }
    if m.saddled {
        let c = TextureGen.hex(BlockRegistry.colorHex[BlockRegistry.colors[m.collar % 16].0] ?? 0xFFFFFF).rgb3
        p.append(box(-33, 60, -33, 66, 5, 66, c))                         // harness on top
        p.append(box(-33, 42, -33.6, 66, 6, 0.6, V3(0.35, 0.22, 0.12)))   // goggle strap
        p.append(box(-22, 41, -34.2, 14, 8, 0.6, V3(0.7, 0.85, 0.95)))
        p.append(box(8, 41, -34.2, 14, 8, 0.6, V3(0.7, 0.85, 0.95)))
    }
    return p
}
