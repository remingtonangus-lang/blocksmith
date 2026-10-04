import Foundation
import simd

// The player's own body, drawn only in the third-person camera views (F5). Original look:
// rust tunic, charcoal trousers, brown boots; worn armour tints the matching boxes.
func writePlayerModel(_ g: Game, eye: V3, daylight: Float, into out: UnsafeMutablePointer<MobVert>, capacity: Int) -> Int {
    let p = g.player
    let walk = sinf(g.walkBob) * 0.8 * g.walkAmount
    let sw = g.swing
    let hit = playerHitAngle(sw)
    let parts = playerParts(g, pitch: p.prone ? p.pitch + .pi / 2 * 0.8 : p.pitch, walk: walk, hit: hit)

    let l = g.world.lightAt(Int(floor(p.pos.x)), Int(floor(p.pos.y + 1)), Int(floor(p.pos.z)))
    var bright = max(0.05, max(Float(l.sky) / 15 * daylight, Float(l.block) / 15))
    bright = bright + (1 - bright) * g.world.dim.ambient
    let CT = Mesher.cornerTable
    let faceShade: [Float] = [0.8, 0.8, 1.0, 0.55, 0.68, 0.68]
    let order = [0, 1, 2, 0, 2, 3]
    let cy = cosf(p.yaw), sy = sinf(p.yaw)
    let sneak: Float = p.sneaking && !p.flying ? -0.15 : 0
    let base = p.pos + V3(0, p.prone ? 0.3 : sneak, 0) - eye
    // Swimming / crawling / gliding: the whole body lies along the view, head first.
    let tilt: Float = p.prone ? -.pi / 2 : 0
    let ct = cosf(tilt), st = sinf(tilt)
    let lift: Float = p.prone ? -0.9 : 0
    var n = 0
    for part in parts {
        if n + 36 > capacity { return n }
        let rot = part.rotation
        let size = part.mx - part.mn
        for f in 0..<6 {
            for k in order {
                let ci = (f * 4 + k) * 3
                let lp = part.mn + size * V3(Float(CT[ci]), Float(CT[ci + 1]), Float(CT[ci + 2]))
                var q = part.place(lp, rot)
                q *= 0.9375 / 16
                if tilt != 0 {
                    let yy = q.y + lift
                    q = V3(q.x, yy * ct - q.z * st, yy * st + q.z * ct)
                }
                let r = V3(cy * q.x + sy * q.z, q.y, -sy * q.x + cy * q.z) + base
                out[n] = MobVert(pos: V4(r, part.pattern), color: V4(part.color, faceShade[f] * bright), local: V4(lp, 0))
                n += 1
            }
        }
    }
    return n
}

// The right arm's attack swing for swing progress `sw` (0...1): up and forward (positive rotX; it was negative
// and the third-person arm struck backwards, the same sign bug as the soldiers' arms).
func playerHitAngle(_ sw: Float) -> Float { sw > 0 ? sinf(sqrtf(sw) * .pi) * 1.3 : 0 }

// The player's boxes (model space, 1/16 block, facing -Z): worn armour tints, head pitched about the neck, a held item.
func playerParts(_ g: Game, pitch: Float, walk: Float, hit: Float) -> [Part] {
    let skin = V3(0.85, 0.66, 0.5), hair = V3(0.3, 0.2, 0.12)
    // Player 2 (split screen) wears a blue tunic.
    let tunic: V3 = g.coop.current == 1 ? V3(0.16, 0.34, 0.62) : V3(0.62, 0.26, 0.16)
    let trousers = V3(0.22, 0.22, 0.26), boots = V3(0.35, 0.22, 0.12)
    let armor = g.inventory.armor
    func tone(_ slot: Int, _ c: V3) -> V3 { armor[slot].isEmpty ? c : (ArmorLook.color(armor[slot].item) ?? c) }
    let chest = tone(1, tunic), legs = tone(2, trousers), feet = tone(3, boots)
    var parts: [Part] = [
        Part(mn: V3(-4, 0, -2), mx: V3(0, 3, 2), pivot: V3(-2, 12, 0), rotX: walk, color: feet, pattern: 4),
        Part(mn: V3(0, 0, -2), mx: V3(4, 3, 2), pivot: V3(2, 12, 0), rotX: -walk, color: feet, pattern: 4),
        Part(mn: V3(-4, 3, -2), mx: V3(-0.01, 12, 2), pivot: V3(-2, 12, 0), rotX: walk, color: legs, pattern: 4),
        Part(mn: V3(0.01, 3, -2), mx: V3(4, 12, 2), pivot: V3(2, 12, 0), rotX: -walk, color: legs, pattern: 4),
        box(-4, 12, -2, 8, 12, 4, chest, 4),
        Part(mn: V3(-8, 12, -2), mx: V3(-4, 24, 2), pivot: V3(-6, 22, 0), rotX: -walk, color: chest, pattern: 4),
        Part(mn: V3(-8, 12, -2.01), mx: V3(-4, 15, 2.01), pivot: V3(-6, 22, 0), rotX: -walk, color: skin),
        Part(mn: V3(4, 12, -2), mx: V3(8, 24, 2), pivot: V3(6, 22, 0), rotX: walk + hit, color: chest, pattern: 4),
        Part(mn: V3(4, 12, -2.01), mx: V3(8, 15, 2.01), pivot: V3(6, 22, 0), rotX: walk + hit, color: skin),
    ]
    // Head turns with the view pitch around the neck.
    let neck = V3(0, 24, 0)
    func head(_ mn: V3, _ mx: V3, _ c: V3) -> Part { Part(mn: mn, mx: mx, pivot: neck, rotX: pitch, color: c) }
    parts.append(head(V3(-4, 24, -4), V3(4, 32, 4), skin))
    parts.append(head(V3(-4.2, 29.5, -4.2), V3(4.2, 32.3, 4.2), armor[0].isEmpty ? hair : tone(0, hair)))
    parts.append(head(V3(-4.2, 24.5, 1), V3(4.2, 29.5, 4.2), armor[0].isEmpty ? hair : tone(0, hair)))
    parts.append(head(V3(-3, 27, -4.15), V3(-1, 28.5, -4.05), V3(0.95, 0.95, 0.95)))
    parts.append(head(V3(1, 27, -4.15), V3(3, 28.5, -4.05), V3(0.95, 0.95, 0.95)))
    parts.append(head(V3(-2, 27, -4.2), V3(-1, 28.5, -4.1), V3(0.2, 0.3, 0.55)))
    parts.append(head(V3(2, 27, -4.2), V3(3, 28.5, -4.1), V3(0.2, 0.3, 0.55)))
    parts.append(head(V3(-2, 25, -4.15), V3(2, 25.8, -4.05), V3(0.55, 0.35, 0.3)))
    if !g.inventory.held.isEmpty {
        let c: V3 = g.inventory.held.def.block != nil ? V3(0.55, 0.45, 0.35) : V3(0.7, 0.7, 0.72)
        parts.append(Part(mn: V3(5, 9, -5), mx: V3(7, 13, -1), pivot: V3(6, 22, 0), rotX: walk + hit, color: c))
    }

    return parts
}
