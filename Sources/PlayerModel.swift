import Foundation
import simd

// The player's own body, drawn only in the third-person camera views (F5). Original look:
// rust tunic, charcoal trousers, brown boots; worn armour as shells over them (playerArmorParts).
func writePlayerModel(_ g: Game, eye: V3, daylight: Float, into out: UnsafeMutablePointer<MobVert>, capacity: Int) -> Int {
    if BoatLooks.drawsRider(g) { return 0 }        // H9: seated in a boat, the boat's model draws the body (BoatLooks.swift)
    let p = g.player
    let prone = p.prone || Partner.isDowned(g)          // Q2: a downed co-op partner lies on the ground
    let walk = sinf(g.walkBob) * 0.8 * g.walkAmount
    let sw = g.swing
    let hit = playerHitAngle(sw)
    let parts = playerParts(g, pitch: prone ? p.pitch + .pi / 2 * 0.8 : p.pitch, walk: walk, hit: hit)

    let l = g.world.lightAt(Int(floor(p.pos.x)), Int(floor(p.pos.y + 1)), Int(floor(p.pos.z)))
    var bright = max(0.05, max(Float(l.sky) / 15 * daylight, Float(l.block) / 15))
    bright = bright + (1 - bright) * g.world.dim.ambient
    let CT = Mesher.cornerTable
    let faceShade: [Float] = [0.8, 0.8, 1.0, 0.55, 0.68, 0.68]
    let order = [0, 1, 2, 0, 2, 3]
    let cy = cosf(p.yaw), sy = sinf(p.yaw)
    let sneak: Float = p.sneaking && !p.flying ? -0.15 : 0
    let base = p.pos + V3(0, (prone ? 0.3 : sneak) + p.viewDY, 0) - eye
    // Swimming / crawling / gliding: the whole body lies along the view, head first.
    let tilt: Float = prone ? -.pi / 2 : 0
    let ct = cosf(tilt), st = sinf(tilt)
    let lift: Float = prone ? -0.9 : 0
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

// The player's boxes (model space, 1/16 block, facing -Z): clothes, head pitched about the neck, worn armour as shells
// over them (P265: playerArmorParts), a held item.
func playerParts(_ g: Game, pitch: Float, walk: Float, hit: Float) -> [Part] {
    let skin = V3(0.85, 0.66, 0.5), hair = V3(0.3, 0.2, 0.12)
    // Player 2 (split screen) wears a blue tunic.
    let chest: V3 = g.coop.current == 1 ? V3(0.16, 0.34, 0.62) : V3(0.62, 0.26, 0.16)
    let legs = V3(0.22, 0.22, 0.26), feet = V3(0.35, 0.22, 0.12)
    let armor = playerArmorOverride ?? g.inventory.armor.slots
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
    parts.append(head(V3(-4.2, 29.5, -4.2), V3(4.2, 32.3, 4.2), hair))
    parts.append(head(V3(-4.2, 24.5, 1), V3(4.2, 29.5, 4.2), hair))
    parts.append(head(V3(-3, 27, -4.15), V3(-1, 28.5, -4.05), V3(0.95, 0.95, 0.95)))
    parts.append(head(V3(1, 27, -4.15), V3(3, 28.5, -4.05), V3(0.95, 0.95, 0.95)))
    parts.append(head(V3(-2, 27, -4.2), V3(-1, 28.5, -4.1), V3(0.2, 0.3, 0.55)))
    parts.append(head(V3(2, 27, -4.2), V3(3, 28.5, -4.1), V3(0.2, 0.3, 0.55)))
    parts.append(head(V3(-2, 25, -4.15), V3(2, 25.8, -4.05), V3(0.55, 0.35, 0.3)))
    parts += playerArmorParts(armor, pitch: pitch, walk: walk, hit: hit)
    if Items.key(armor[1].item) == "jetpack" && !armor[1].isEmpty {
        // Jetpack on the back: two steel tanks with copper nozzles.
        for x: Float in [-3.6, 0.4] {
            parts.append(Part(mn: V3(x, 13, 2), mx: V3(x + 3.2, 23, 5), pivot: .zero, rotX: 0, color: V3(0.48, 0.52, 0.57), pattern: 8))
            parts.append(Part(mn: V3(x + 0.6, 11, 2.6), mx: V3(x + 2.6, 13, 4.4), pivot: .zero, rotX: 0, color: V3(0.78, 0.45, 0.23)))
        }
    }
    if !g.inventory.held.isEmpty {
        let c: V3 = g.inventory.held.def.block != nil ? V3(0.55, 0.45, 0.35) : V3(0.7, 0.7, 0.72)
        parts.append(Part(mn: V3(5, 9, -5), mx: V3(7, 13, -1), pivot: V3(6, 22, 0), rotX: walk + hit, color: c))
    }

    return parts
}

// P276 (a): another player's worn pieces while their body is drawn (NetCoop.writeRemote); nil: this player's own.
var playerArmorOverride: [ItemStack]?

// P265 (Oct 14 12:19, "the player figure in the inventory wears the armour he has equipped"): worn pieces as shells
// over the clothes (the old look only recoloured the shirt, which never read as armour). A helmet dome with a brow
// band, cheek and neck guards that leaves the face open; a breastplate with pauldrons and sleeves; leggings with a belt;
// boots with toe caps. Each piece's colour, trim and finish come from ArmorLook.style: the tiers, steel, copper, fur,
// troop-class plate, the faction kits in their colours and trims, leather dye, a legendary's gold trim, an enchanted
// piece's violet sheen, a worn-out piece dulled. The bandana is a mask over the lower face, glider wings fold on the
// back, a pumpkin or a head replaces the head. The inventory preview, third person, boats and player 2 all use it.
func playerArmorParts(_ a: [ItemStack], pitch: Float, walk: Float, hit: Float) -> [Part] {
    var p: [Part] = []
    let neck = V3(0, 24, 0)
    func head(_ mn: V3, _ mx: V3, _ c: V3, _ pat: Float) -> Part { Part(mn: mn, mx: mx, pivot: neck, rotX: pitch, color: c, pattern: pat) }
    func arm(_ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float, _ r: Float, _ c: V3, _ pat: Float, right: Bool) -> Part {
        Part(mn: V3(x0, y0, -r), mx: V3(x1, y1, r), pivot: V3(right ? 6 : -6, 22, 0), rotX: right ? walk + hit : -walk, color: c, pattern: pat)
    }
    func leg(_ right: Bool, _ y0: Float, _ y1: Float, _ r: Float, _ c: V3, _ pat: Float, front: Float = 0) -> Part {
        let x0: Float = right ? 0 : -4 - (r - 2), x1: Float = right ? 4 + (r - 2) : 0
        return Part(mn: V3(x0, y0, -r - front), mx: V3(x1, y1, r), pivot: V3(right ? 2 : -2, 12, 0), rotX: right ? -walk : walk, color: c, pattern: pat)
    }
    guard a.count >= 4 else { return p }
    // Head.
    let h = a[0]
    if !h.isEmpty {
        let k = Items.key(h.item)
        let st = ArmorLook.style(h)
        if k == "carved_pumpkin" || k.hasSuffix("_head") || k.hasSuffix("_skull") {
            p.append(head(V3(-4.5, 23.6, -4.5), V3(4.5, 32.6, 4.5), st.color, st.pattern))
            if k == "carved_pumpkin" {
                p.append(head(V3(-3, 27, -4.7), V3(-1, 28.6, -4.4), V3(0.25, 0.12, 0), 9))
                p.append(head(V3(1, 27, -4.7), V3(3, 28.6, -4.4), V3(0.25, 0.12, 0), 9))
                p.append(head(V3(-2.5, 24.8, -4.7), V3(2.5, 25.8, -4.4), V3(0.25, 0.12, 0), 9))
            }
        } else if k == "bandana" {
            // A mask over the nose and mouth, knotted at the back.
            p.append(head(V3(-4.35, 24.2, -4.4), V3(4.35, 26.8, 4.35), st.color, 6))
            p.append(head(V3(-1, 25, 4.35), V3(1, 26.6, 5.2), st.color * 0.85, 6))
        } else {
            let c = st.color, pat = st.pattern
            p.append(head(V3(-4.6, 29.4, -4.6), V3(4.6, 32.7, 4.6), c, pat))                    // the dome
            p.append(head(V3(-4.6, 24.4, 4.0), V3(4.6, 29.4, 4.6), c * 0.92, pat))              // the neck guard
            p.append(head(V3(-4.6, 25.2, -4.6), V3(-4.0, 29.4, 4.0), c * 0.92, pat))            // cheek guards
            p.append(head(V3(4.0, 25.2, -4.6), V3(4.6, 29.4, 4.0), c * 0.92, pat))
            p.append(head(V3(-4.7, 29.0, -4.75), V3(4.7, 29.8, -4.0), st.trim ?? c * 0.8, st.trimPattern))   // the brow band
            if k == "turtle_helmet" { p.append(head(V3(-3.2, 32.6, -3.2), V3(3.2, 33.2, 3.2), c * 0.8, 4)) }
        }
    }
    // Chest (glider wings and the jetpack are worn there too).
    let c = a[1]
    if !c.isEmpty {
        let k = Items.key(c.item)
        let st = ArmorLook.style(c)
        if k == "elytra" {
            for x: Float in [-4.6, 0.3] {
                p.append(Part(mn: V3(x, 9.5, 2.1), mx: V3(x + 4.3, 23.5, 2.9), pivot: .zero, color: st.color, pattern: 3))
            }
        } else if k != "jetpack" {
            let col = st.color, pat = st.pattern
            p.append(box(-4.6, 12.4, -2.6, 9.2, 12, 5.2, col, pat))                               // the breastplate
            if let t = st.trim {
                p.append(box(-0.7, 13, -2.85, 1.4, 11, 0.3, t, st.trimPattern))                  // a centre ridge
                p.append(box(-4.6, 12.1, -2.75, 9.2, 0.8, 5.5, t, st.trimPattern))               // the hem
            }
            for right in [false, true] {
                let x0: Float = right ? 3.9 : -8.7, x1: Float = right ? 8.7 : -3.9
                p.append(arm(x0, x1, 20.6, 24.8, 2.7, st.trim ?? col * 0.9, st.trim == nil ? pat : st.trimPattern, right: right))   // pauldron
                p.append(arm(right ? 3.95 : -8.5, right ? 8.5 : -3.95, 15.2, 20.6, 2.45, col * 0.95, pat, right: right))           // sleeve
            }
        }
    }
    // Legs.
    let l = a[2]
    if !l.isEmpty {
        let st = ArmorLook.style(l)
        p.append(box(-4.5, 10.8, -2.5, 9, 1.8, 5, st.trim ?? st.color * 0.75, st.trim == nil ? st.pattern : st.trimPattern))   // the belt
        p.append(leg(false, 4.2, 11.4, 2.45, st.color * 0.92, st.pattern))
        p.append(leg(true, 4.2, 11.4, 2.45, st.color * 0.92, st.pattern))
    }
    // Feet.
    let f = a[3]
    if !f.isEmpty {
        let st = ArmorLook.style(f)
        for right in [false, true] {
            p.append(leg(right, -0.1, 4.4, 2.6, st.color * 0.85, st.pattern))
            p.append(leg(right, -0.05, 1.7, 2.4, st.color * 0.75, st.pattern, front: 0.7))    // the toe cap
            if let t = st.trim { p.append(leg(right, 3.7, 4.6, 2.7, t, st.trimPattern)) }      // the cuff
        }
    }
    return p
}
