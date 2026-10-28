import Foundation
import simd

// The player's own body, drawn only in the third-person camera views (F5). Original look:
// rust tunic, charcoal trousers, brown boots; worn armour as shells over them (playerArmorParts).
func writePlayerModel(_ g: Game, eye: V3, daylight: Float, into out: UnsafeMutablePointer<MobVert>, capacity: Int) -> Int {
    if BoatLooks.drawsRider(g) { return 0 }        // H9: seated in a boat, the boat's model draws the body (BoatLooks.swift)
    let p = g.player
    let prone = p.prone
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
func playerParts(_ g: Game, pitch: Float, walk: Float, hit: Float, posed: Bool = true) -> [Part] {
    let skin = V3(0.85, 0.66, 0.5), hair = V3(0.3, 0.2, 0.12)
    // Player 2 (split screen) wears a blue tunic.
    let chest: V3 = g.coop.current == 1 ? V3(0.16, 0.34, 0.62) : V3(0.62, 0.26, 0.16)
    let legs = V3(0.22, 0.22, 0.26), feet = V3(0.35, 0.22, 0.12)
    let armor = playerArmorOverride ?? g.inventory.armor.slots
    // P481 (store look-alike review, Oct 28): a person's figure, not the reference game's block man (an 8-pixel cube
    // head with a painted face on a 4-wide-limbed box body). Limbs slimmer than the torso with gaps between them, a
    // waist narrower than the chest, hands below the sleeves, and a modelled head on a neck, built like the townsfolk's
    // (TownsfolkModel): nose, ears, eyes with iris and lids, brows, lips, jaw, hair. The joints stay where they were
    // (hips at 12, shoulders at +-6/22, the neck at 24), so the walk, the seat poses and the worn pieces still fit.
    let boot = V3(0.3, 0.19, 0.1), belt = V3(0.16, 0.11, 0.08)
    var parts: [Part] = []
    parts.reserveCapacity(56)
    func b(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pat: Float = Pat.cloth) {
        parts.append(Part(mn: V3(x0, y0, z0), mx: V3(x1, y1, z1), color: c, pattern: pat))
    }
    // Legs from the hips: trousers, boots with a toe and a darker sole.
    for right in [false, true] {
        let sx: Float = right ? 1 : -1, rot = right ? -walk : walk
        func leg(_ a: Float, _ y0: Float, _ z0: Float, _ c: Float, _ y1: Float, _ z1: Float, _ col: V3, _ pat: Float) {
            let x0 = right ? a : -c, x1 = right ? c : -a
            parts.append(Part(mn: V3(x0, y0, z0), mx: V3(x1, y1, z1), pivot: V3(sx * 2, 12, 0), rotX: rot, color: col, pattern: pat))
        }
        leg(0.35, 3, -1.8, 3.65, 12, 1.8, legs, Pat.cloth)
        leg(0.25, 0.6, -2.2, 3.75, 4, 1.95, feet, Pat.leather)
        leg(0.3, 0.6, -3.0, 3.7, 2.2, -2.2, feet * 0.92, Pat.leather)                  // the toe
        leg(0.2, 0, -3.05, 3.8, 0.6, 2.0, boot * 0.6, Pat.leather)                     // the sole
    }
    // Torso: the waist narrower than the chest, the shoulders rounded off; a belt and buckle, a collar opening.
    b(-3.9, 12, -2.0, 3.9, 16.5, 2.0, chest)
    b(-4.3, 16.5, -2.3, 4.3, 23.2, 2.3, chest)
    b(-3.9, 23.2, -2.0, 3.9, 24.0, 2.0, chest * 0.96)
    b(-4.0, 12.0, -2.15, 4.0, 13.3, 2.15, belt, Pat.leather)
    b(-0.8, 12.1, -2.27, 0.8, 13.2, -2.15, V3(0.72, 0.62, 0.38), Pat.metal)
    b(-1.0, 21.4, -2.36, 1.0, 23.2, -2.3, skin * 0.97, Pat.skin)                        // the open collar
    b(-1.9, 22.6, -2.42, -1.0, 23.4, -2.3, chest * 0.86); b(1.0, 22.6, -2.42, 1.9, 23.4, -2.3, chest * 0.86)
    // Arms from the shoulders: sleeves with a cuff, the hand narrower and flatter, the thumb forward.
    for right in [false, true] {
        let sx: Float = right ? 1 : -1, rot = right ? walk + hit : -walk
        func arm(_ a: Float, _ y0: Float, _ z0: Float, _ c: Float, _ y1: Float, _ z1: Float, _ col: V3, _ pat: Float) {
            let x0 = right ? a : -c, x1 = right ? c : -a
            parts.append(Part(mn: V3(x0, y0, z0), mx: V3(x1, y1, z1), pivot: V3(sx * 6, 22, 0), rotX: rot, color: col, pattern: pat))
        }
        arm(4.45, 14.6, -1.45, 7.35, 23.8, 1.45, chest, Pat.cloth)
        arm(4.4, 14.4, -1.5, 7.4, 15.1, 1.5, chest * 0.88, Pat.cloth)                   // the cuff
        arm(4.75, 11.6, -1.1, 7.05, 14.4, 1.2, skin, Pat.skin)
        arm(4.6, 12.7, -1.55, 5.4, 14.1, -1.0, skin * 0.96, Pat.skin)                  // the thumb
    }
    // Head, on the neck: built in the townsfolk's head frame (23.5 to 30.5) and drawn at their proportions.
    let neck = V3(0, 24, 0)
    func h(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: V3, _ pat: Float = Pat.skin) {
        let h0 = V3(0, 23.5, 0), hs = V3(0.8, 0.8, 0.82), lift = V3(0, 1.1, 0)
        parts.append(Part(mn: h0 + (V3(x0, y0, z0) - h0) * hs + lift, mx: h0 + (V3(x1, y1, z1) - h0) * hs + lift,
                          pivot: neck, rotX: pitch, color: c, pattern: pat))
    }
    h(-3.2, 23.5, -3.2, 3.2, 30.5, 3.2, skin)
    h(-0.6, 25.9, -3.85, 0.6, 27.6, -3.2, skin * 0.92)                                      // nose
    h(-0.85, 25.7, -4.0, 0.85, 26.4, -3.5, skin * 0.9)                                      // its tip
    h(-3.55, 25.8, -0.6, -3.2, 28.2, 0.9, skin * 0.94); h(3.2, 25.8, -0.6, 3.55, 28.2, 0.9, skin * 0.94)   // ears
    h(-1.5, 23.5, -3.45, 1.5, 24.4, -3.2, skin * 0.97)                                      // chin
    h(-2.2, 27, -3.3, -0.9, 28, -3.2, V3(0.95, 0.95, 0.93)); h(0.9, 27, -3.3, 2.2, 28, -3.2, V3(0.95, 0.95, 0.93))   // eyes
    let iris = V3(0.25, 0.4, 0.55)
    h(-1.7, 27, -3.36, -1.0, 27.9, -3.28, iris, Pat.enamel); h(1.0, 27, -3.36, 1.7, 27.9, -3.28, iris, Pat.enamel)
    h(-1.5, 27.2, -3.4, -1.2, 27.7, -3.36, V3(0.04, 0.03, 0.03), Pat.enamel); h(1.2, 27.2, -3.4, 1.5, 27.7, -3.36, V3(0.04, 0.03, 0.03), Pat.enamel)
    h(-2.25, 27.85, -3.34, -0.85, 28.1, -3.2, skin * 0.78); h(0.85, 27.85, -3.34, 2.25, 28.1, -3.2, skin * 0.78)   // lids
    h(-2.4, 28.4, -3.32, -0.8, 28.9, -3.2, hair * 0.8, Pat.cloth); h(0.8, 28.4, -3.32, 2.4, 28.9, -3.2, hair * 0.8, Pat.cloth)   // brows
    let lip = skin * V3(0.82, 0.58, 0.55)
    h(-1.2, 25.0, -3.3, 1.2, 25.3, -3.2, lip * 0.85); h(-0.95, 24.7, -3.32, 0.95, 25.0, -3.2, lip)
    let cheek = skin * V3(1.03, 0.93, 0.92)
    h(-2.8, 25.3, -3.25, -1.6, 26.4, -3.2, cheek); h(1.6, 25.3, -3.25, 2.8, 26.4, -3.2, cheek)
    // Short hair: one cap over the crown, the back and the ears' tops (it rounds off in the inventory's figure; flat
    // slabs the head's width stood out of its rounded corners there), sideburns, a swept front.
    h(-3.55, 27.0, -2.4, 3.55, 31.5, 3.6, hair, Pat.cloth)
    h(-3.42, 25.2, -1.3, -3.2, 27.0, 0.6, hair * 0.9, Pat.cloth); h(3.2, 25.2, -1.3, 3.42, 27.0, 0.6, hair * 0.9, Pat.cloth)
    h(-2.9, 29.3, -3.45, 2.2, 30.9, -2.35, hair, Pat.cloth)
    parts.append(Part(mn: V3(-1.2, 23.2, -1.0), mx: V3(1.2, 24.9, 1.3), pivot: neck, rotX: pitch * 0.4, color: skin, pattern: Pat.skin))   // neck
    playerClothesParts = parts.count
    parts += playerArmorParts(armor, pitch: pitch, walk: walk, hit: hit)
    if Items.key(armor[1].item) == "jetpack" && !armor[1].isEmpty {
        // Jetpack on the back: two steel tanks with copper nozzles.
        for x: Float in [-3.6, 0.4] {
            parts.append(Part(mn: V3(x, 13, 2), mx: V3(x + 3.2, 23, 5), pivot: .zero, rotX: 0, color: V3(0.48, 0.52, 0.57), pattern: 8))
            parts.append(Part(mn: V3(x + 0.6, 11, 2.6), mx: V3(x + 2.6, 13, 4.4), pivot: .zero, rotX: 0, color: V3(0.78, 0.45, 0.23)))
        }
    }
    // P282 (c): the hand shows what the game holds (Game.held: nothing at the helm or a deck gun), not the slot.
    let inHand = g.held
    if !inHand.isEmpty {
        let c: V3 = inHand.def.block != nil ? V3(0.55, 0.45, 0.35) : V3(0.7, 0.7, 0.72)
        parts.append(Part(mn: V3(5, 9, -5), mx: V3(7, 13, -1), pivot: V3(6, 22, 0), rotX: walk + hit, color: c))
    }
    if posed { seatArms(g, &parts, pitch: pitch, hit: hit) }

    return parts
}

// P282 (c) (Oct 14 19:36, "from third person it looks as if I'm holding the gun"): the arms (sleeves, armour shells and
// the held item ride the same shoulder pivots) do what the hands do in the seat. At the controls both reach forward and
// down to the helm, wheel or deck-gun handles; mounted, the left hand holds the reins low ahead, and a gun in the right
// points along the look. The rowboat poses its own arms on the paddles (BoatLooks.seated).
func seatArms(_ g: Game, _ parts: inout [Part], pitch: Float, hit: Float) {
    let mounted = g.mountedOneHand && !BoatLooks.drawsRider(g)
    guard g.handsOnControls || mounted else { return }
    var left: Float = 0.95, right: Float = 0.95
    if mounted {
        left = 0.6
        right = g.heldGun != nil ? HandsPose.aim(pitch) : 0.25 + hit          // a blade still swings
    }
    for i in parts.indices where parts[i].pivot.y == 22 && abs(parts[i].pivot.x) == 6 {
        parts[i].rotX = parts[i].pivot.x > 0 ? right : left
        parts[i].rotZ = parts[i].pivot.x > 0 ? -0.12 : 0.12
    }
}

enum HandsPose {
    // A shoulder rotation pointing the arm along the view: level is a quarter turn up from hanging, the look's pitch on top.
    static func aim(_ pitch: Float) -> Float { .pi / 2 + max(-0.8, min(0.8, pitch)) }
}

// How many of playerParts' boxes are the body and clothes (the rest, worn pieces and the held item, lie over them: the
// inventory figure draws them after, P473).
var playerClothesParts = 0

// P276 (a): another player's worn pieces while their body is drawn (a split-screen seat); nil: this player's own.
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
    // P481: the pieces are laid out round the old block figure's sizes (an 8-wide head, 4-wide limbs) and drawn fitted
    // to the person's figure (playerParts): the head's pieces to its smaller head, the arms' and legs' to slimmer limbs.
    func fitHead(_ v: V3) -> V3 { V3(v.x * 0.68, 24.6 + (v.y - 24) * 0.75, v.z * 0.72) }
    func head(_ mn: V3, _ mx: V3, _ c: V3, _ pat: Float) -> Part { Part(mn: fitHead(mn), mx: fitHead(mx), pivot: neck, rotX: pitch, color: c, pattern: pat) }
    func arm(_ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float, _ r: Float, _ c: V3, _ pat: Float, right: Bool) -> Part {
        let sx: Float = right ? 1 : -1
        func fx(_ x: Float) -> Float { sx * 5.9 + (x - sx * 6) * 0.75 }
        return Part(mn: V3(fx(x0), y0, -r * 0.75), mx: V3(fx(x1), y1, r * 0.75), pivot: V3(sx * 6, 22, 0), rotX: right ? walk + hit : -walk, color: c, pattern: pat)
    }
    func leg(_ right: Bool, _ y0: Float, _ y1: Float, _ r: Float, _ c: V3, _ pat: Float, front: Float = 0) -> Part {
        let x0: Float = right ? 0 : -4 - (r - 2), x1: Float = right ? 4 + (r - 2) : 0
        let sx: Float = right ? 2 : -2
        func fx(_ x: Float) -> Float { sx + (x - sx) * 0.8 }
        return Part(mn: V3(fx(x0), y0, (-r - front) * 0.9), mx: V3(fx(x1), y1, r * 0.9), pivot: V3(sx, 12, 0), rotX: right ? -walk : walk, color: c, pattern: pat)
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
