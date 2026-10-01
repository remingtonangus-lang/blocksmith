import Foundation
import simd

// Fireworks: stars (gunpowder + dyes + optional shape / trail / twinkle, fade colours added later),
// rockets (paper + 1-3 gunpowder + up to 7 stars) launched from the ground, a dispenser or a
// crossbow, exploding into coloured sparks that hurt nearby mobs (reference numbers).
enum Fireworks {
    // Star tag: shape (0 small ball, 1 large ball, 2 star, 3 hisser, 4 burst) | trail << 3 | twinkle << 4.
    // Star pat: colour indices; fade colours are stored + 16.
    static let shapeItems: [String: Int] = ["fire_charge": 1, "gold_nugget": 2, "feather": 4]
    static func shape(of key: String) -> Int? {
        if let s = shapeItems[key] { return s }
        if key.hasSuffix("_head") || key.hasSuffix("_skull") { return 3 }
        return nil
    }
    static let shapeNames = ["Small Ball", "Large Ball", "Star-shaped", "Hisser-shaped", "Burst"]

    // Special crafting (dynamic ingredients). Returns the result and grid slots that are not consumed.
    static func craft(_ g: [ItemStack]) -> (ItemStack, keep: Set<Int>)? {
        let items = g.enumerated().filter { !$0.element.isEmpty }
        guard !items.isEmpty else { return nil }
        let keys = items.map { Items.key($0.element.item) }
        func count(_ k: String) -> Int { keys.filter { $0 == k }.count }
        let dyes = items.compactMap { Banners.colorIndex(ofDye: Items.key($0.element.item)) }
        // Firework star.
        if count("gunpowder") == 1 && !dyes.isEmpty && count("firework_star") == 0 && count("paper") == 0 {
            var shape = 0, shapes = 0, trail = 0, twinkle = 0, other = 0
            for k in keys {
                if k == "gunpowder" || k.hasSuffix("_dye") { continue }
                if let s = Fireworks.shape(of: k) { shape = s; shapes += 1 }
                else if k == "diamond" { trail += 1 }
                else if k == "glowstone_dust" { twinkle += 1 }
                else { other += 1 }
            }
            guard shapes <= 1, trail <= 1, twinkle <= 1, other == 0 else { return nil }
            var s = ItemStack(Items.id("firework_star"), 1)
            s.tag = shape | (trail << 3) | (twinkle << 4) | (1 << 8)
            s.pat = dyes
            return (s, [])
        }
        // Fade colours onto an existing star.
        if count("firework_star") == 1 && !dyes.isEmpty && keys.count == dyes.count + 1 {
            guard let star = items.first(where: { Items.key($0.element.item) == "firework_star" })?.element else { return nil }
            var s = star.with(count: 1)
            s.pat = (star.pat ?? []).filter { $0 < 16 } + dyes.map { $0 + 16 }
            return (s, [])
        }
        // Rocket.
        let gp = count("gunpowder")
        if count("paper") == 1 && gp >= 1 && gp <= 3 && keys.count == 1 + gp + count("firework_star") && count("firework_star") <= 7 {
            var s = ItemStack(Items.id("firework_rocket"), 3)
            s.tag = gp
            let stars = items.filter { Items.key($0.element.item) == "firework_star" }.map { $0.element.with(count: 1) }
            if !stars.isEmpty { s.contents = stars }
            return (s, [])
        }
        // Banner copy: a patterned banner + a blank one of the same colour.
        let banners = items.filter { Blocks.shape[Int($0.element.def.block ?? 0)] == "banner" }
        if banners.count == 2 && keys.count == 2 && banners[0].element.item == banners[1].element.item {
            let (a, b) = (banners[0], banners[1])
            if a.element.pat != nil && b.element.pat == nil { var r = a.element.with(count: 1); r.count = 1; return (r, [a.offset]) }
            if b.element.pat != nil && a.element.pat == nil { var r = b.element.with(count: 1); r.count = 1; return (r, [b.offset]) }
        }
        // Shield decoration.
        if keys.count == 2 && count("shield") == 1 && banners.count == 1 {
            let sh = items.first { Items.key($0.element.item) == "shield" }!.element
            guard sh.pat == nil else { return nil }
            var r = sh.with(count: 1)
            r.pat = banners[0].element.pat ?? []
            r.tag = Banners.baseColor(banners[0].element.def.block ?? 0) + 1
            return (r, [])
        }
        // Book copy: a written book (original or first copy) + books and quills.
        if count("written_book") == 1 && count("writable_book") >= 1 && keys.count == 1 + count("writable_book") {
            let (i, b) = items.first { Items.key($0.element.item) == "written_book" }!
            guard b.tag < 2 else { return nil }
            var r = b.with(count: count("writable_book"))
            r.tag = b.tag + 1
            return (r, [i])
        }
        // Leather armour (and horse armour) dyeing: the reference colour-averaging formula.
        if dyes.count >= 1 && keys.count == dyes.count + 1,
           case let (li, armor)? = items.first(where: { let k = Items.key($0.element.item); return k.hasPrefix("leather_") && Items.def($0.element.item).maxStack == 1 }) {
            var sum = [0, 0, 0], maxSum = 0, n = 0
            var cols: [UInt32] = dyes.map { BlockRegistry.colorHex[Banners.colors[$0]] ?? 0xFFFFFF }
            if let c = armor.pat?.first { cols.append(UInt32(c)) }
            for c in cols {
                let r = Int((c >> 16) & 255), g = Int((c >> 8) & 255), b = Int(c & 255)
                sum[0] += r; sum[1] += g; sum[2] += b; maxSum += max(r, max(g, b)); n += 1
            }
            var avg = sum.map { $0 / n }
            let maxAvg = Float(maxSum) / Float(n), top = Float(max(avg[0], max(avg[1], avg[2])))
            if top > 0 { avg = avg.map { Int(Float($0) * maxAvg / top) } }
            var r = armor.with(count: 1)
            r.pat = [(avg[0] << 16) | (avg[1] << 8) | avg[2]]
            _ = li
            return (r, [])
        }
        // Map copy.
        if count("filled_map") == 1 && count("map") >= 1 && keys.count == 1 + count("map") {
            let m = items.first { Items.key($0.element.item) == "filled_map" }!.element
            return (m.with(count: count("map") + 1), [])
        }
        return nil
    }

    static func tooltip(_ s: ItemStack) -> [String] {
        let k = Items.key(s.item)
        var out: [String] = []
        if Bundles.isBundle(s) {
            for c in (s.contents ?? []).prefix(6) { out.append("\(c.displayName) x\(c.count)") }
            if (s.contents ?? []).count > 6 { out.append("and \((s.contents ?? []).count - 6) more...") }
            out.append("\(Bundles.fill(s))/64")
        }
        if k.hasPrefix("music_disc_") { out.append(MusicDiscs.title(String(k.dropFirst(11)))) }
        if k == "goat_horn" { out.append(GoatHorns.names[max(0, min(7, s.tag))]) }
        if k == "written_book" {
            out.append("by Player")
            out.append(Books.generations[min(3, s.tag)])
        }
        if k == "firework_rocket" {
            out.append("Flight Duration: \(max(1, s.tag))")
            for st in s.contents ?? [] { out += tooltip(st).map { "  " + $0 } }
        } else if k == "firework_star" && s.tag != 0 {
            out.append(shapeNames[min(4, s.tag & 7)])
            let cols = (s.pat ?? []).filter { $0 < 16 }.map { BlockRegistry.colors[$0].1 }
            if !cols.isEmpty { out.append(cols.joined(separator: ", ")) }
            let fade = (s.pat ?? []).filter { $0 >= 16 }.map { BlockRegistry.colors[$0 - 16].1 }
            if !fade.isEmpty { out.append("Fade to " + fade.joined(separator: ", ")) }
            if s.tag & 8 != 0 { out.append("Trail") }
            if s.tag & 16 != 0 { out.append("Twinkle") }
        }
        return out
    }
}

final class Rocket {
    var pos: V3
    var vel: V3
    var age: Float = 0
    let life: Float
    let stars: [ItemStack]
    var dead = false
    let shotBy: Bool           // fired from a crossbow: flies straight
    init(at p: V3, dir: V3, flight: Int, stars: [ItemStack], crossbow: Bool = false) {
        pos = p
        shotBy = crossbow
        vel = crossbow ? dir * 16 : V3(Float.random(in: -0.1...0.1), 1, Float.random(in: -0.1...0.1)) * 4
        // Reference lifetime: 10 x (flight + 1) + rand(6) + rand(7) ticks.
        let ticks: Int = 10 * (max(1, flight) + 1) + Int.random(in: 0...5) + Int.random(in: 0...6)
        life = Float(ticks) / 20
        self.stars = stars
    }
}

extension Game {
    // Right-click the ground with a rocket (not gliding): launch it.
    func launchRocket(_ t: (hit: IVec3, normal: IVec3)) -> Bool {
        guard Items.key(held.item) == "firework_rocket", !player.gliding else { return false }
        let at = V3(Float(t.hit.x) + 0.5, Float(t.hit.y) + 0.5, Float(t.hit.z) + 0.5) + V3(Float(t.normal.x), Float(t.normal.y), Float(t.normal.z)) * 0.6
        rockets.append(Rocket(at: at, dir: V3(0, 1, 0), flight: held.tag, stars: held.contents ?? []))
        if survival { consumeHeld() }
        sfx(.fireworkLaunch, 1, at: at)
        swing = 1
        return true
    }

    func rocketTick(_ dt: Float) {
        guard !rockets.isEmpty else { return }
        for r in rockets {
            r.age += dt
            if !r.shotBy { r.vel.x *= 1.15; r.vel.z *= 1.15; r.vel.y += 0.04 * 400 * dt; r.vel = simd_length(r.vel) > 30 ? simd_normalize(r.vel) * 30 : r.vel }
            r.pos += r.vel * dt
            particles.smoke(at: r.pos - r.vel * 0.02, dark: false)
            let b = world.block(Int(floor(r.pos.x)), Int(floor(r.pos.y)), Int(floor(r.pos.z)))
            let hitMob = r.shotBy ? mobs.mobs.first { m in m.health > 0 && abs(m.pos.x - r.pos.x) < m.halfW && abs(m.pos.z - r.pos.z) < m.halfW && r.pos.y > m.pos.y && r.pos.y < m.pos.y + m.height } : nil
            if r.age >= r.life || (Blocks.collide[Int(b)] && r.shotBy) || hitMob != nil { explode(r) }
        }
        rockets.removeAll { $0.dead }
    }

    func explode(_ r: Rocket) {
        r.dead = true
        guard !r.stars.isEmpty else { sfx(.fireworkBlast, 0.4, at: r.pos); return }
        addFlash(at: r.pos, color: V3(3, 2.6, 2.2), radius: 14, life: 0.6)
        // Damage: 5 + 2 per extra star within 5 blocks (reference), less with distance.
        let dmg = Float(5 + 2 * (r.stars.count - 1))
        for m in mobs.mobs where m.health > 0 {
            let d = simd_length(m.pos + V3(0, m.height / 2, 0) - r.pos)
            if d < 5 { m.hit(from: r.pos, damage: max(1, Int(dmg * sqrtf((5 - d) / 5))), knockback: 0.3) }
        }
        let pd = simd_length(player.pos + V3(0, 0.9, 0) - r.pos)
        if pd < 5 && survival { hurtPlayer(max(1, Int(dmg * sqrtf((5 - pd) / 5))), from: r.pos, cause: "went off with a bang", type: .explosion) }
        let large = r.stars.contains { $0.tag & 7 == 1 }
        sfx(large ? .fireworkBlastLarge : .fireworkBlast, 1.5, at: r.pos)
        if r.stars.contains(where: { $0.tag & 16 != 0 }) { sfx(.fireworkTwinkle, 1.2, at: r.pos) }
        for st in r.stars { particles.firework(at: r.pos, star: st) }
    }

    func writeRockets(_ wr: inout EntityWriter, eye: V3) {
        let smoke = Int(Tex.id("smoke"))
        for r in rockets {
            let c = r.pos - eye
            wr.texturedBox(c - V3(0.05, 0.2, 0.05), c + V3(0.05, 0.2, 0.05), layer: smoke, color: V4(0.8, 0.2, 0.2, 1))
        }
    }
}

extension ParticleManager {
    func firework(at c: V3, star s: ItemStack) {
        let spark = Int(Tex.id("smoke"))
        let cols = (s.pat ?? [15]).filter { $0 < 16 }
        let fades = (s.pat ?? []).filter { $0 >= 16 }.map { $0 - 16 }
        let shape = s.tag & 7
        let trail = s.tag & 8 != 0, twinkle = s.tag & 16 != 0
        var dirs: [V3] = []
        switch shape {
        case 1:                                      // large ball
            for _ in 0..<160 { dirs.append(simd_normalize(V3(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1))) * 1.9) }
        case 2:                                      // star: five points
            for i in 0..<5 {
                let a0 = Float(i) * 2 * .pi / 5 - .pi / 2, a1 = a0 + .pi / 5
                for k in 0..<12 {
                    let t = Float(k) / 12
                    let r: Float = 1 - 0.55 * t
                    dirs.append(V3(cosf(a0 + (a1 - a0) * t) * r, sinf(a0 + (a1 - a0) * t) * r, 0))
                    dirs.append(V3(cosf(a1 + (a1 - a0) * t) * (0.45 + 0.55 * t), sinf(a1 + (a1 - a0) * t) * (0.45 + 0.55 * t), 0))
                }
            }
        case 3:                                      // hisser face
            let face = ["#..#", "#..#", ".##.", "####", "#..#"]
            for (y, row) in face.enumerated() { for (x, ch) in row.enumerated() where ch == "#" {
                for _ in 0..<3 { dirs.append(V3((Float(x) - 1.5) * 0.35 + Float.random(in: -0.05...0.05), (2 - Float(y)) * 0.35, 0)) }
            } }
        case 4:                                      // burst: upward fountain
            for _ in 0..<70 { dirs.append(V3(Float.random(in: -0.4...0.4), Float.random(in: 0.2...1.2), Float.random(in: -0.4...0.4))) }
        default:
            for _ in 0..<70 { dirs.append(simd_normalize(V3(Float.random(in: -1...1), Float.random(in: -1...1), Float.random(in: -1...1)))) }
        }
        for d in dirs {
            let col = Banners.tint(cols.randomElement() ?? 15) * 1.3
            let life = Float.random(in: 1.2...1.8) * (trail ? 1.3 : 1)
            // Fade colours: a second, longer-lived shell of sparks in the fade colour.
            let fadeCol: V3? = fades.isEmpty ? nil : Banners.tint(fades.randomElement()!) * 1.3
            add(Particle(pos: c, vel: d * 7 + V3(0, 0.5, 0), life: life, maxLife: life, layer: spark, uv0: V2(0, 0), uvSize: 1,
                         size: twinkle ? Float.random(in: 0.05...0.14) : 0.1, gravity: 1.2, color: col, collide: false, glow: true))
            if let fc = fadeCol {
                add(Particle(pos: c, vel: d * 6, life: life * 1.4, maxLife: life * 1.4, layer: spark, uv0: V2(0, 0), uvSize: 1,
                             size: 0.08, gravity: 1.0, color: fc, collide: false, glow: true))
            }
            if trail {
                add(Particle(pos: c, vel: d * 5, life: life * 0.8, maxLife: life, layer: spark, uv0: V2(0, 0), uvSize: 1, size: 0.07, gravity: 2.5,
                             color: col, collide: false, glow: true))
            }
        }
    }
}
