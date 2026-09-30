import Foundation
import simd

// The Ashen Grove: a pale, silent variant of the dark forest (reference game's late addition), with
// Ashbark trees draped in hanging ashen moss, moss carpets, nightblooms that open after dark, and
// Barkwraith hearts hidden in some trunks. At night an active heart (Ashbark logs above and below)
// calls up one Barkwraith: it only moves while nobody is looking at it, can't be hurt while its
// heart stands, and crumbles when the heart is broken or the sun rises. Hearts drop sap clumps.
extension BlockRegistry {
    func registerAshenGrove() {
        var moss = BlockDef("pale_moss_block", "Ashen Moss Block")
        moss.tex = ["pale_moss_block"]; moss.hardness = 0.1; moss.tool = .hoe; moss.sound = .plant
        add(moss)
        var carpet = BlockDef("pale_moss_carpet", "Ashen Moss Carpet")
        carpet.tex = ["pale_moss_block"]; carpet.render = .model; carpet.opaque = false; carpet.boxes = [Box(0, 0, 0, 16, 1, 16)]
        carpet.hardness = 0.1; carpet.tool = .hoe; carpet.sound = .plant; carpet.skyStop = false; carpet.replaceable = false
        add(carpet)
        var hang = BlockDef("pale_hanging_moss", "Hanging Ashen Moss")
        hang.tex = ["pale_hanging_moss"]; hang.render = .cross; hang.layer = .cutout; hang.opaque = false; hang.collide = false
        hang.hardness = 0; hang.sound = .plant; hang.replaceable = true; hang.skyStop = false
        add(hang)
        for active in [false, true] {
            var h = BlockDef(active ? "creaking_heart[active]" : "creaking_heart", "Barkwraith Heart")
            let side = active ? "creaking_heart_active" : "creaking_heart"
            h.tex = [side, side, "creaking_heart_top", "creaking_heart_top", side, side]
            h.group = "creaking_heart"; h.hidden = active
            h.hardness = 10; h.tool = .axe; h.sound = .wood; h.randomTicks = true
            add(h)
        }
        for open in [false, true] {
            var f = BlockDef(open ? "open_eyeblossom" : "closed_eyeblossom", open ? "Open Nightbloom" : "Closed Nightbloom")
            f.tex = [f.name]; f.render = .cross; f.layer = .cutout; f.opaque = false; f.collide = false
            f.hardness = 0; f.sound = .plant; f.skyStop = false; f.randomTicks = true
            add(f)
        }
    }
}

extension TextureGen {
    static func ashenPainters(_ p: inout [String: Painter]) {
        p["pale_moss_block"] = { x, y in
            // Soft grey-green: gentle blotches, very little per-pixel grain.
            let k = 0.9 + (blot(x, y, 1702, 4) - 0.5) * 0.16 + (blot(x, y, 1703, 8) - 0.5) * 0.1 + (r(x, y, 1701) - 0.5) * 0.05
            return hex(0x98A48E, k)
        }
        // Ashbark leaves: soft clumps with gaps (less contrast than per-pixel noise, which read as gravel).
        p["pale_oak_leaves"] = { x, y in
            let clump = blot(x, y, 1720, 4)
            if clump < 0.32 || r(x, y, 1721) < 0.12 { return clear }
            return hex(0xA2AE98, 0.78 + 0.28 * clump + 0.08 * r(x, y, 1722))
        }
        p["pale_hanging_moss"] = { x, y in
            let strand = (x * 7 + 3) % 5 == 0 || (x * 3 + 1) % 7 == 0
            let len = 6 + Int(r(x, 0, 1703) * 10)
            return strand && y < len ? hex(0xA4AC9A, 0.8 + 0.3 * r(x, y, 1704)) : clear
        }
        let barkC: UInt32 = 0x5E5652
        p["creaking_heart"] = { x, y in
            let core = x >= 5 && x <= 10 && y >= 3 && y <= 12
            if core { return hex(0x4A3A30, 0.8 + 0.25 * r(x, y, 1705)) }
            let stripe = (x + Int(r(0, y / 5, 1706) * 2)) % 4 == 0
            return hex(barkC, stripe ? 0.72 : 0.9 + 0.14 * r(x, y, 1707))
        }
        p["creaking_heart_active"] = { x, y in
            let core = x >= 5 && x <= 10 && y >= 3 && y <= 12
            if core {
                let vein = (x + y) % 3 == 0 || r(x, y, 1708) < 0.25
                return vein ? hex(0xFF9A2A, 0.9 + 0.2 * r(x, y, 1709)) : hex(0x4A3A30, 0.85)
            }
            let stripe = (x + Int(r(0, y / 5, 1706) * 2)) % 4 == 0
            return hex(barkC, stripe ? 0.72 : 0.9 + 0.14 * r(x, y, 1707))
        }
        p["creaking_heart_top"] = { x, y in
            let dx = Float(x) - 7.5, dy = Float(y) - 7.5
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(barkC, 0.85) }
            let d = (dx * dx + dy * dy).squareRoot()
            if d < 3 { return hex(0x4A3A30) }
            return hex(0xE4DAD3, Int(d * 1.15) % 2 == 0 ? 1 : 0.86)
        }
        func bloom(_ open: Bool) -> Painter {
            { x, y in
                // Stem and leaves, then a bud: closed = grey petals folded, open = orange eye in pale petals.
                if x == 7 && y >= 7 { return hex(0x5A6A4A, 0.9 + 0.2 * r(x, y, 1710)) }
                if y >= 11 && y <= 12 && (x == 5 || x == 6 || x == 8 || x == 9) { return hex(0x6A7A5A) }
                if open {
                    let dx = x - 7, dy = y - 4
                    let d2 = dx * dx + dy * dy
                    if d2 <= 1 { return hex(0xFF8C1A) }
                    if d2 <= 9 { return hex(0xD8D2C8, 0.9 + 0.15 * r(x, y, 1711)) }
                    return clear
                }
                if x >= 6 && x <= 8 && y >= 2 && y <= 6 { return hex(0x8A8490, 0.85 + 0.2 * r(x, y, 1712)) }
                return clear
            }
        }
        p["open_eyeblossom"] = bloom(true)
        p["closed_eyeblossom"] = bloom(false)
    }
}

extension Game {
    // Hearts near the player (rescanned every 10 s), nightbloom-style night check, Barkwraith spawning.
    var ashenNight: Bool { let f = dayFraction; return f > 0.54 && f < 0.96 }

    func ashenTick(_ dt: Float) {
        guard dim.dim == .overworld else { return }
        heartTimer -= dt
        guard heartTimer <= 0 else { return }
        heartTimer = 2
        heartScanAge += 2
        if heartScanAge >= 10 {
            heartScanAge = 0
            hearts = scanHearts()
        }
        let base = Blocks.id("creaking_heart"), active = base + 1
        for h in hearts {
            let b = world.block(h.x, h.y, h.z)
            guard Blocks.groupBase[Int(b)] == base else { continue }
            let natural = Blocks.key(world.block(h.x, h.y + 1, h.z)).hasPrefix("pale_oak_log") && Blocks.key(world.block(h.x, h.y - 1, h.z)).hasPrefix("pale_oak_log")
            let want = ashenNight && natural && difficulty > 0
            if want != (b == active) { world.setBlock(h.x, h.y, h.z, want ? active : base) }
            guard want else { continue }
            let hv = V3(Float(h.x) + 0.5, Float(h.y), Float(h.z) + 0.5)
            if mobs.mobs.contains(where: { $0.kind == .creaking && $0.home.map { simd_length($0 - hv) < 0.5 } ?? false }) { continue }
            guard simd_length(player.pos - hv) < 40 else { continue }
            // One Barkwraith per heart, on open ground within 8 blocks.
            for _ in 0..<6 {
                let x = h.x + Int.random(in: -8...8), z = h.z + Int.random(in: -8...8)
                let top = world.topY(x, z)
                guard top > 0, abs(top - h.y) < 12 else { continue }
                var y = top + 1
                while y > h.y - 12 && !(world.block(x, y, z) == AIR && world.block(x, y + 1, z) == AIR && world.block(x, y + 2, z) == AIR && Blocks.collide[Int(world.block(x, y - 1, z))]) { y -= 1 }
                guard y > h.y - 12 else { continue }
                let m = Mob(.creaking, at: V3(Float(x) + 0.5, Float(y), Float(z) + 0.5))
                m.home = hv
                mobs.mobs.append(m)
                particles.dust(Blocks.id("pale_oak_log"), at: m.pos + V3(0, 1.2, 0), count: 20, spread: 0.6)
                break
            }
        }
    }

    func scanHearts() -> [IVec3] {
        let base = Blocks.id("creaking_heart")
        var out: [IVec3] = []
        let pcx = floorDiv(Int(floor(player.pos.x)), CS), pcz = floorDiv(Int(floor(player.pos.z)), CS)
        for cz in (pcz - 2)...(pcz + 2) { for cx in (pcx - 2)...(pcx + 2) {
            guard let c = world.chunks[ChunkKey(x: cx, z: cz)] else { continue }
            for lz in 0..<CS { for lx in 0..<CS {
                let top = Int(c.height[lx + lz * CS])
                guard top > 20 else { continue }
                for y in max(1, top - 24)...top where Blocks.groupBase[Int(c.blocks[Chunk.index(lx, y, lz)])] == base {
                    out.append(IVec3(cx * CS + lx, y, cz * CS + lz))
                }
            } }
        } }
        return out
    }

    // Nightblooms open at dusk and close at dawn (random ticks).
    func nightbloomTick(_ p: IVec3, _ key: String) {
        let night = ashenNight
        if key == "closed_eyeblossom" && night { world.setBlock(p.x, p.y, p.z, Blocks.id("open_eyeblossom")) }
        if key == "open_eyeblossom" && !night { world.setBlock(p.x, p.y, p.z, Blocks.id("closed_eyeblossom")) }
    }
}

extension Mob {
    // Barkwraith: frozen while watched, bound to its heart.
    func barkwraithAI(_ dt: Float, _ g: Game, dist: Float, canTarget: Bool) -> Float {
        guard let h = home else { health = -2000; return 0 }
        let hb = g.world.block(Int(floor(h.x)), Int(floor(h.y)), Int(floor(h.z)))
        if Blocks.key(Blocks.groupBase[Int(hb)]) != "creaking_heart" || !g.ashenNight {
            g.particles.dust(Blocks.id("pale_oak_log"), at: pos + V3(0, 1.3, 0), count: 30, spread: 0.7)
            health = -2000
            return 0
        }
        let center = pos + V3(0, height * 0.6, 0)
        let toMe = center - g.player.eye
        let d = simd_length(toMe)
        let watched = g.alive && d < 48 && simd_dot(g.player.look, toMe / max(0.01, d)) > 0.85 && g.world.canSee(g.player.eye, center)
        if watched { vel.x = 0; vel.z = 0; walkAmount = 0; return 0 }
        if canTarget && dist < 24 {
            face(g.player.pos)
            if dist < halfW + 1.4 && attackCooldown <= 0 {
                attackCooldown = 1.5
                g.hurtPlayer(spec.attack, from: pos, cause: "was slain by a Barkwraith", attacker: self)
            }
            return spec.speed
        }
        if simd_length(V2(h.x - pos.x, h.z - pos.z)) > 24 { face(h); return spec.speed * 0.6 }
        wander(); return moving ? spec.speed * 0.4 : 0
    }
}

func barkwraithParts(_ m: Mob, swing: Float) -> [Part] {
    let bark = V3(0.37, 0.34, 0.32), pale = V3(0.78, 0.76, 0.72), glow = V3(1, 0.6, 0.15)
    return [
        Part(mn: V3(-4, 0, -1.5), mx: V3(-1, 18, 1.5), pivot: V3(-2.5, 18, 0), rotX: swing, color: bark, pattern: 4),
        Part(mn: V3(1, 0, -1.5), mx: V3(4, 18, 1.5), pivot: V3(2.5, 18, 0), rotX: -swing, color: bark, pattern: 4),
        box(-5, 18, -2.5, 10, 16, 5, bark, 4), box(-2, 22, -2.8, 4, 6, 0.4, pale),
        Part(mn: V3(-8, 12, -1.5), mx: V3(-5, 34, 1.5), pivot: V3(-6.5, 33, 0), rotX: -swing * 0.8, color: bark, pattern: 4),
        Part(mn: V3(5, 12, -1.5), mx: V3(8, 34, 1.5), pivot: V3(6.5, 33, 0), rotX: swing * 0.8, color: bark, pattern: 4),
        box(-4, 34, -4, 8, 9, 8, bark, 4), box(-6, 40, -1, 3, 4, 2, pale), box(3, 40, -1, 3, 4, 2, pale),
        box(-3, 38, -4.2, 2, 1.5, 0.3, glow), box(1, 38, -4.2, 2, 1.5, 0.3, glow),
    ]
}
