import Foundation
import simd

// Combat and vehicle HUD (the gun ammo counter and hit marker live with the guns in Renderer/Ballistics):
// damage-direction indicators, an armour wear bar, vehicle gauges (speed, altitude, throttle, integrity,
// heading) and the weapon wheel.
final class CombatHUD {
    static var shared = CombatHUD()      // var: split-screen seats swap it (Coop.swift)
    struct Hit { var dir: V3; var time: Double; var strength: Float }
    private(set) var hits: [Hit] = []
    private var peak: [Int: Int] = [:]               // ship id -> most blocks seen (integrity baseline)

    // From Game.hurtPlayer: remember where it came from.
    func hurt(_ g: Game, from src: V3, amount: Int) {
        var d = src - g.player.pos
        d.y = 0
        guard simd_length(d) > 0.3 else { return }
        hits.append(Hit(dir: simd_normalize(d), time: g.clock, strength: min(1, 0.4 + Float(amount) * 0.1)))
        if hits.count > 6 { hits.removeFirst() }
    }

    func integrity(_ s: Ship) -> Float {
        let p = max(s.initialBlocks, peak[s.id] ?? 0, s.blockCount)
        peak[s.id] = p
        return p > 0 ? Float(s.blockCount) / Float(p) : 1
    }

    func lines(_ g: Game, _ L: HudLayout) -> [HudLine] {
        var out: [HudLine] = []
        let s = L.s
        let cx = floor(L.W / 2), cy = floor(L.H / 2)
        // Damage direction: red marks around the crosshair pointing at the source, fading over 1.6 s.
        hits.removeAll { g.clock - $0.time > 1.6 || g.clock < $0.time }
        if !hits.isEmpty {
            let fwd = V3(-sinf(g.player.yaw), 0, -cosf(g.player.yaw)), right = V3(cosf(g.player.yaw), 0, -sinf(g.player.yaw))
            let R = 46 * s
            for h in hits {
                let a = atan2f(simd_dot(h.dir, right), simd_dot(h.dir, fwd))     // 0 = ahead, clockwise
                let fade = Float(1 - (g.clock - h.time) / 1.6)
                let col = V4(0.95, 0.12, 0.08, fade * (0.5 + 0.5 * h.strength))
                for k in -2...2 {
                    let b = a + Float(k) * 0.07
                    let rr = R - (k == 0 ? 2 * s : 0)
                    let px = cx + sinf(b) * rr, py = cy - cosf(b) * rr
                    let sz = (k == 0 ? 5 : 3) * s
                    out.append(HudLine(text: "", x: px - sz / 2, y: py - sz / 2, scale: s, bg: col, box: V2(sz, sz)))
                }
            }
        }
        // Armour wear: one bar per worn piece, left of the hotbar (survival). P123 (Oct 12 PM: "I don't understand what
        // those four bars to my left are"): each bar has its piece's icon beside it and the column is headed "Armour".
        if g.survival {
            var row = 0
            let pieces = (0..<4).compactMap { i -> ItemStack? in
                let st = g.inventory.armor[i]
                return !st.isEmpty && st.def.durability > 0 && Items.key(st.item) != "jetpack" ? st : nil
            }
            let y0 = L.hotbarY0 - 3 * s
            if !pieces.isEmpty {
                out.append(HudLine(text: "Armour", x: L.hotbarX0 - 40 * s, y: y0 - 10 * s, scale: s, color: V4(0.85, 0.88, 0.92, 0.9)))
            }
            for st in pieces {
                let f = max(0, 1 - Float(st.damage) / Float(st.def.durability))
                let x = L.hotbarX0 - 30 * s, y = y0 + Float(row) * 7 * s
                out.append(HudLine(text: "", x: x - 10 * s, y: y - 1.5 * s, scale: s, box: V2(6 * s, 6 * s), item: st))
                out.append(HudLine(text: "", x: x, y: y, scale: s, bg: V4(0, 0, 0, 0.55), box: V2(22 * s, 3 * s)))
                let c = f < 0.2 ? Settings.shared.badColor : (Settings.shared.colorblind ? V4(0.6, 0.8, 1, 1) : V4(0.75, 0.85, 0.95, 1))
                out.append(HudLine(text: "", x: x + s * 0.5, y: y + s * 0.5, scale: s, bg: c, box: V2(21 * s * f, 2 * s)))
                row += 1
            }
        }
        out += Jetpack.gauge(g, L)
        out += g.radarLines(L)
        // Vehicle gauges while piloting (or riding aboard).
        if let ship = g.world.ships.pilot ?? g.world.ships.aboard, g.menu == nil {
            // A Meridian frigate's panel has one more row: the Tidebreaker's gauge.
            let gun = g.world.ships.mainGunStatus(ship.root)
            let kind = VehicleControls.kind(ship)
            // P325 (e): a commandeered warship's drive (the engines left) and the bow's pitch on a row of their own.
            let war = kind == .warship ? g.world.ships.capState[ship.root.id] : nil
            let extra: Float = (gun == nil ? 0 : 11) + (war == nil ? 0 : 11)
            let x = L.insetX + 6 * s, y0 = L.H - L.insetY - (64 + extra) * s
            let w = 104 * s
            out.append(HudLine(text: "", x: x - 3 * s, y: y0 - 4 * s, scale: s, bg: V4(0, 0, 0, 0.5), box: V2(w + 6 * s, (58 + extra) * s)))
            if let st = war {
                let dy = y0 + 54 * s
                let d = Capital.drive(ship.root, st)
                let out0 = d <= 0
                let tag = out0 ? "Engines out" : String(format: "Pitch %+d", Int((st.helmPitch * 180 / .pi).rounded()))
                let tw = Float(Font.width(tag)) * s
                let dc = out0 ? Settings.shared.badColor : (d < 0.6 ? V4(0.95, 0.75, 0.2, 1) : V4(0.55, 0.85, 1, 1))
                out.append(HudLine(text: "Drive", x: x, y: dy, scale: s, color: out0 ? dc : V4(0.85, 0.85, 0.85, 1)))
                out.append(HudLine(text: tag, x: x + w - tw, y: dy, scale: s, color: out0 ? dc : V4(0.8, 0.9, 1, 1)))
                let bw = max(0, w - tw - 30 * s)
                out.append(HudLine(text: "", x: x + 26 * s, y: dy + s, scale: s, bg: V4(0.2, 0.2, 0.22, 0.9), box: V2(bw, 5 * s)))
                out.append(HudLine(text: "", x: x + 26 * s, y: dy + s, scale: s, bg: dc, box: V2(bw * d, 5 * s)))
            }
            if let (state, fill, ready) = gun {
                let gy = y0 + (war == nil ? 54 : 65) * s
                let c = ready ? V4(0.55, 0.85, 1, 1) : V4(0.95, 0.75, 0.2, 1)
                out.append(HudLine(text: MainGun.name, x: x, y: gy, scale: s, color: V4(0.85, 0.85, 0.85, 1)))
                let sw = Float(Font.width(state)) * s
                out.append(HudLine(text: state, x: x + w - sw, y: gy, scale: s, color: c))
                let bx = x + Float(Font.width(MainGun.name)) * s + 4 * s, bw = max(0, w - sw - 4 * s - (bx - x))
                out.append(HudLine(text: "", x: bx, y: gy + s, scale: s, bg: V4(0.2, 0.2, 0.22, 0.9), box: V2(bw, 5 * s)))
                out.append(HudLine(text: "", x: bx, y: gy + s, scale: s, bg: c, box: V2(bw * fill, 5 * s)))
            }
            let speed = simd_length(ship.vel) * 3.6
            out.append(HudLine(text: "\(ship.name) - \(VehicleControls.name(kind))", x: x, y: y0, scale: s, color: V4(1, 0.9, 0.6, 1)))
            out.append(HudLine(text: String(format: "%3.0f km/h", speed), x: x, y: y0 + 11 * s, scale: s))
            let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
            var hd = Double(-ship.yaw * 180 / .pi).truncatingRemainder(dividingBy: 360)
            if hd < 0 { hd += 360 }
            let heading = dirs[Int((hd + 22.5) / 45) % 8]
            out.append(HudLine(text: heading, x: x + w - Float(Font.width(heading)) * s, y: y0 + 11 * s, scale: s, color: V4(0.7, 0.9, 1, 1)))
            if kind == .airship || kind == .aircraft || kind == .helicopter || kind == .warship || kind == .vtol {
                let alt = Int(ship.pos.y) - SEA
                out.append(HudLine(text: "Alt \(alt)", x: x + 56 * s, y: y0 + 11 * s, scale: s, color: V4(0.8, 0.95, 0.8, 1)))
            }
            // Throttle: centre line, bar to the right for forward, left for reverse.
            let ty = y0 + 23 * s, mid = x + w / 2
            out.append(HudLine(text: "", x: x, y: ty, scale: s, bg: V4(0.2, 0.2, 0.22, 0.9), box: V2(w, 5 * s)))
            let t = max(-1, min(1, ship.throttle))
            out.append(HudLine(text: "", x: t >= 0 ? mid : mid + w / 2 * t, y: ty, scale: s, bg: V4(0.95, 0.75, 0.2, 1), box: V2(abs(t) * w / 2, 5 * s)))
            out.append(HudLine(text: "", x: mid - s / 2, y: ty - s, scale: s, bg: V4(1, 1, 1, 0.9), box: V2(s, 7 * s)))
            // Integrity: share of the vehicle's blocks still attached.
            let integ = integrity(ship)
            let iy = y0 + 33 * s
            out.append(HudLine(text: "Hull", x: x, y: iy, scale: s, color: V4(0.85, 0.85, 0.85, 1)))
            out.append(HudLine(text: "", x: x + 26 * s, y: iy + s, scale: s, bg: V4(0.2, 0.2, 0.22, 0.9), box: V2(w - 26 * s, 5 * s)))
            let ic = integ < 0.35 ? Settings.shared.badColor : (integ < 0.7 ? V4(0.95, 0.75, 0.2, 1) : Settings.shared.goodColor)
            out.append(HudLine(text: "", x: x + 26 * s, y: iy + s, scale: s, bg: ic, box: V2((w - 26 * s) * integ, 5 * s)))
            if kind == .airship {
                out.append(HudLine(text: String(format: "Lift %d%%", Int(ship.liftLevel * 100)), x: x, y: y0 + 43 * s, scale: s, color: V4(0.8, 0.9, 1, 1)))
            } else if VehicleDepot.usesFuel(ship.root) {
                // Q2: the land vehicle's tank (D44), on the panel where it can be seen in play.
                let f = VehicleDepot.level(ship.root)
                let fc = f <= VehicleDepot.fumes ? Settings.shared.badColor : (f < VehicleDepot.low ? V4(0.95, 0.75, 0.2, 1) : V4(0.85, 0.85, 0.85, 1))
                out.append(HudLine(text: "Fuel", x: x, y: y0 + 43 * s, scale: s, color: V4(0.85, 0.85, 0.85, 1)))
                out.append(HudLine(text: "", x: x + 26 * s, y: y0 + 44 * s, scale: s, bg: V4(0.2, 0.2, 0.22, 0.9), box: V2(30 * s, 5 * s)))
                out.append(HudLine(text: "", x: x + 26 * s, y: y0 + 44 * s, scale: s, bg: fc, box: V2(30 * s * max(0, min(1, f)), 5 * s)))
            }
            if VehicleControls.armed(g, ship) {
                let loading = ship.reload > 0 || g.world.ships.turrets(of: ship).contains { $0.reload > 0 }
                let t = loading ? "Guns loading" : "Guns ready"
                out.append(HudLine(text: t, x: x + w - Float(Font.width(t)) * s, y: y0 + 43 * s, scale: s,
                                   color: loading ? V4(0.95, 0.75, 0.2, 1) : Settings.shared.goodColor))
            }
        }
        // P379 step 2: the locomotive's cab: speed, the regulator (forward right, reverse left) and the brake.
        if let tr = Trains.cab(g), g.menu == nil {
            let x = L.insetX + 6 * s, y0 = L.H - L.insetY - 52 * s, w = 104 * s
            out.append(HudLine(text: "", x: x - 3 * s, y: y0 - 4 * s, scale: s, bg: V4(0, 0, 0, 0.5), box: V2(w + 6 * s, 46 * s)))
            out.append(HudLine(text: tr.track.name, x: x, y: y0, scale: s, color: V4(1, 0.9, 0.6, 1)))
            out.append(HudLine(text: String(format: "%3.0f km/h", tr.blocksPerSec * 3.6), x: x, y: y0 + 11 * s, scale: s))
            let reg = tr.throttle < 0 ? "Reverse" : "Regulator"
            out.append(HudLine(text: reg, x: x, y: y0 + 22 * s, scale: s, color: V4(0.85, 0.85, 0.85, 1)))
            let bx = x + 44 * s, bw = w - 44 * s, mid = bx + bw / 3
            out.append(HudLine(text: "", x: bx, y: y0 + 23 * s, scale: s, bg: V4(0.2, 0.2, 0.22, 0.9), box: V2(bw, 5 * s)))
            let t = max(-1, min(2, tr.throttle))
            out.append(HudLine(text: "", x: t >= 0 ? mid : mid + bw / 3 * t, y: y0 + 23 * s, scale: s, bg: V4(0.95, 0.75, 0.2, 1), box: V2(abs(t) * bw / 3, 5 * s)))
            out.append(HudLine(text: "", x: mid - s / 2, y: y0 + 22 * s, scale: s, bg: V4(1, 1, 1, 0.9), box: V2(s, 7 * s)))
            out.append(HudLine(text: "Brake", x: x, y: y0 + 33 * s, scale: s, color: V4(0.85, 0.85, 0.85, 1)))
            out.append(HudLine(text: "", x: bx, y: y0 + 34 * s, scale: s, bg: V4(0.2, 0.2, 0.22, 0.9), box: V2(bw, 5 * s)))
            out.append(HudLine(text: "", x: bx, y: y0 + 34 * s, scale: s, bg: Settings.shared.badColor, box: V2(bw * tr.cabBrake, 5 * s)))
        }
        // Q2: the tank sight (D42) under the crosshair while a wheeled vehicle's gun is laid on it.
        if let ship = g.world.ships.pilot, !ship.wheels.isEmpty, let p = TankSight.aim, g.menu == nil, VehicleControls.armed(g, ship) {
            let t = String(format: "%.0f m  %@", simd_length(p - g.player.eye), TankSight.laid ? "LAID" : "traversing")
            out.append(HudLine(text: t, x: cx - Float(Font.width(t)) * s / 2, y: cy + 22 * s, scale: s,
                               color: TankSight.laid ? Settings.shared.goodColor : V4(0.95, 0.75, 0.2, 1)))
        }
        // Q2: a co-op gun seat (D52): which gun, and its reload under the crosshair.
        if let tid = Partner.gunner[Partner.seat(g)], let t = g.world.ships.list.first(where: { $0.id == tid }), g.menu == nil {
            let w = 40 * s, x = cx - w / 2, y = cy + 14 * s
            let f = t.reloadTime > 0 ? max(0, 1 - t.reload / t.reloadTime) : 1
            out.append(HudLine(text: "", x: x, y: y, scale: s, bg: V4(0, 0, 0, 0.55), box: V2(w, 4 * s)))
            out.append(HudLine(text: "", x: x, y: y, scale: s, bg: f >= 1 ? Settings.shared.goodColor : V4(0.95, 0.75, 0.2, 1), box: V2(w * f, 4 * s)))
            let label = f >= 1 ? "Gun seat: ready" : "Gun seat: loading"
            out.append(HudLine(text: label, x: cx - Float(Font.width(label)) * s / 2, y: y + 6 * s, scale: s, color: V4(0.9, 0.9, 0.9, 0.9)))
        }
        // Manned deck gun: reload bar under the crosshair.
        if Turrets.shared.active {
            let r = max(0, Turrets.shared.reload)
            let w = 40 * s, x = cx - w / 2, y = cy + 14 * s
            out.append(HudLine(text: "", x: x, y: y, scale: s, bg: V4(0, 0, 0, 0.55), box: V2(w, 4 * s)))
            out.append(HudLine(text: "", x: x, y: y, scale: s, bg: r <= 0 ? Settings.shared.goodColor : V4(0.95, 0.75, 0.2, 1), box: V2(w * max(0, 1 - r / (HeavyTurret.reload * 0.6)), 4 * s)))
        }
        out += WeaponWheel.shared.lines(g, L)
        return out
    }
}

// MARK: Weapon wheel

// Hold RB (controller) or Tab (keyboard, rebindable) with guns in the inventory: a wheel of up to eight guns
// opens; point the right stick / move the mouse at one and let go to equip it. A quick tap of RB still steps
// the hotbar; a quick tap of Tab switches to the next gun. The game keeps running behind the wheel.
final class WeaponWheel {
    static var shared = WeaponWheel()      // var: split-screen seats swap it (Coop.swift)
    private(set) var open = false
    private var holding = false
    private var viaPad = false
    private var holdTime: Float = 0
    private var cursor = V2(0, 0)
    private(set) var choice = -1
    private(set) var entries: [Int] = []              // inventory main indices holding guns

    static func guns(_ g: Game) -> [Int] { Array((0..<36).filter { Guns.index(g.inventory.main[$0].item) != nil }.prefix(8)) }

    // True when RB belongs to the wheel (the player has a gun somewhere), so the hotbar waits for the release.
    func ownsRB(_ g: Game) -> Bool { holding && viaPad }

    // P208 (Oct 13 18:43, "the weapon wheel does not work"): on the headset the right stick had to be held pressed in
    // while it was tilted, which Touch sticks don't do (the click lets go as the stick tips). There a click opens the
    // wheel, the stick points at a gun, and letting the stick spring back (or clicking again) takes it; B closes it.
    static var clickToOpen = false
    private var flicked = false

    // Per frame before look/hotbar handling; returns true while the wheel is open (it takes the look input).
    func tick(_ g: Game, _ p: PadSnapshot, _ q: PadSnapshot, _ dt: Float) -> Bool {
        let key = KeyBinds.key(.weapons)
        if g.world.ships.pilot != nil || Turrets.shared.active { holding = false; open = false; return false }
        if WeaponWheel.clickToOpen { return tickClick(g, p, q) }
        if !holding {
            let has = !WeaponWheel.guns(g).isEmpty
            if has && p.rb && !q.rb { holding = true; viaPad = true; holdTime = 0 }
            else if g.input.tapped(key) {
                if has { holding = true; viaPad = false; holdTime = 0 } else { g.onToast?("No guns") }
            }
        }
        guard holding else { return false }
        let down = viaPad ? p.rb : g.input.down(key)
        holdTime += dt
        if down {
            if !open && holdTime >= 0.22 {
                open = true
                entries = WeaponWheel.guns(g)
                cursor = .zero
                choice = entries.firstIndex(of: g.selected) ?? -1
                g.sfx(.click, 0.5)
            }
            if open {
                var v = V2(p.rx, p.ry)
                if !viaPad {
                    cursor += V2(g.input.mouseDX, -g.input.mouseDY) * 0.02
                    if simd_length(cursor) > 1 { cursor = simd_normalize(cursor) }
                    v = cursor
                }
                if simd_length(v) > (viaPad ? 0.5 : 0.3) && !entries.isEmpty {
                    let n = Float(entries.count)
                    var a = atan2f(v.x, v.y)
                    if a < 0 { a += 2 * .pi }
                    let i = Int((a / (2 * .pi / n)).rounded()) % entries.count
                    if i != choice { choice = i; g.sfx(.click, 0.3); PadManager.shared.rumble(0.12, 0.03, sharpness: 0.9) }
                }
            }
            return open
        }
        holding = false
        if open {
            open = false
            if choice >= 0 && choice < entries.count { equip(g, entries[choice]) }
            return false
        }
        // Quick tap.
        if viaPad { g.select(g.selected + 1) } else { nextGun(g) }
        return false
    }

    private func tickClick(_ g: Game, _ p: PadSnapshot, _ q: PadSnapshot) -> Bool {
        let click = p.rb && !q.rb
        if !open {
            guard click else { return false }
            entries = WeaponWheel.guns(g)
            guard !entries.isEmpty else { g.onToast?("No guns to pick from"); return false }
            open = true; holding = true; viaPad = true; flicked = false
            choice = entries.firstIndex(of: g.selected) ?? -1
            g.sfx(.click, 0.5)
            return true
        }
        if p.b && !q.b { open = false; holding = false; return false }
        let v = V2(p.rx, p.ry)
        if simd_length(v) > 0.55 {
            let n = Float(entries.count)
            var a = atan2f(v.x, v.y)
            if a < 0 { a += 2 * .pi }
            let i = Int((a / (2 * .pi / n)).rounded()) % entries.count
            if i != choice { choice = i; g.sfx(.click, 0.3); PadManager.shared.rumble(0.12, 0.03, sharpness: 0.9) }
            flicked = true
            return true
        }
        if (flicked && simd_length(v) < 0.25) || click {
            open = false; holding = false
            if choice >= 0 && choice < entries.count { equip(g, entries[choice]) }
            return false
        }
        return true
    }

    // Harness (--padview combat): the wheel open with entry `pick` highlighted.
    func showForSnapshot(_ g: Game, pick: Int) {
        entries = WeaponWheel.guns(g)
        holding = true; viaPad = true; open = !entries.isEmpty
        choice = entries.isEmpty ? -1 : pick % entries.count
    }

    func equip(_ g: Game, _ idx: Int) {
        guard idx >= 0, idx < 36 else { return }
        if idx < 9 { g.select(idx); return }
        let a = g.inventory.main[idx]
        g.inventory.main[idx] = g.inventory.main[g.selected]
        g.inventory.main[g.selected] = a
        g.equipAnim = 1
        g.onToast?(a.def.display)
    }

    func nextGun(_ g: Game) {
        let list = WeaponWheel.guns(g)
        guard !list.isEmpty else { return }
        let next = list.first { $0 > g.selected && $0 < 9 } ?? list.first { $0 >= 9 } ?? list[0]
        equip(g, next == g.selected ? list[0] : next)
    }

    func lines(_ g: Game, _ L: HudLayout) -> [HudLine] {
        guard open, !entries.isEmpty else { return [] }
        let s = L.s
        let cx = floor(L.W / 2), cy = floor(L.H / 2)
        let R = 54 * s, cell = 24 * s
        var out: [HudLine] = [HudLine(text: "", x: cx - R - cell, y: cy - R - cell, scale: s, bg: V4(0, 0, 0, 0.35), box: V2(2 * (R + cell), 2 * (R + cell)))]
        for (i, idx) in entries.enumerated() {
            let a = Float(i) * 2 * .pi / Float(entries.count)
            let px = cx + sinf(a) * R - cell / 2, py = cy - cosf(a) * R - cell / 2
            let sel = i == choice
            out.append(HudLine(text: "", x: px - s, y: py - s, scale: s, bg: sel ? V4(1, 0.85, 0.3, 1) : V4(0.1, 0.1, 0.12, 0.9), box: V2(cell + 2 * s, cell + 2 * s)))
            out.append(HudLine(text: "", x: px, y: py, scale: s, bg: sel ? V4(0.45, 0.42, 0.3, 0.95) : V4(0.3, 0.3, 0.33, 0.9), box: V2(cell, cell)))
            var l = HudLine(text: "", x: px + 3 * s, y: py + 3 * s, scale: s)
            l.item = g.inventory.main[idx]
            l.box = V2(cell - 6 * s, cell - 6 * s)
            out.append(l)
        }
        if choice >= 0 && choice < entries.count {
            let st = g.inventory.main[entries[choice]]
            let name = st.def.display
            out.append(HudLine(text: name, x: cx - Float(Font.width(name)) * s / 2, y: cy - 10 * s, scale: s, color: V4(1, 0.9, 0.5, 1)))
            if let gi = Guns.index(st.item) {
                let gs = Guns.all[gi]
                let ammo = "\(st.tag)/\(Guns.magSize(st))  +\(g.survival ? g.ammoCount(gs.ammo) : 99)"
                out.append(HudLine(text: ammo, x: cx - Float(Font.width(ammo)) * s / 2, y: cy + 2 * s, scale: s))
            }
        }
        return out
    }
}
