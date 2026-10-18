import Foundation
import simd

// Controller and keyboard layouts for piloting ships, airships, aircraft and land vehicles (Ships.swift),
// and for manning Steelhold deck guns. Keyboard keeps W/S throttle, A/D steer, Space/Ctrl climb, Shift leave.
// Controller, by vehicle:
//   boat / land vehicle   RT throttle, LT reverse, LS steer
//   airship              RT forward, LT reverse, LS left/right turn, LS up/down climb
//   vtol                 a dropship (P334): LS forward/back and strafe, RS left/right turn, RS up/down climb (RB / LB
//                        too), RT the gun; keyboard W/S, A/D turn, Space/Ctrl climb
//   aircraft             RT throttle, LT brake, LS left/right bank and turn, LS up/down pitch (pull back to climb,
//                        Options > Controller > Flight Stick)
//   warship              a commandeered frigate (P325): LS throttle and turn, RB / LB pitch the bow up and down (on
//                        Quest the right stick's up/down, so the grips stay free), RT the guns
//   any                  A climb, B leave the helm
enum VehicleControls {
    enum Kind { case boat, land, airship, aircraft, helicopter, warship, vtol }
    // Quest: the right stick's up/down while at a warship's helm (QuestControls sets it each frame; nil elsewhere).
    static var vrPitch: Float?

    static func kind(_ s: Ship) -> Kind {
        if !s.rotors.isEmpty { return .helicopter }
        if s.kinematic && s.role == "dropship" { return .vtol }                          // a commandeered drop craft (P334)
        if s.kinematic && s.isFlyingCapital { return .warship }                          // ...and a frigate (P325)
        if !s.wings.isEmpty && s.balloons == 0 { return .aircraft }
        if s.balloons > 0 { return .airship }
        if !s.wheels.isEmpty && s.submerged <= 0.01 { return .land }
        return .boat
    }
    static func name(_ k: Kind) -> String {
        switch k {
        case .boat: return "Boat"
        case .land: return "Land Vehicle"
        case .airship: return "Airship"
        case .aircraft: return "Aircraft"
        case .helicopter: return "Helicopter"
        case .warship: return "Warship"
        case .vtol: return "VTOL"
        }
    }

    // Cannons on the vessel or its turrets: then RT fires them (ShipPlay) and the left stick is the throttle.
    static func armed(_ g: Game, _ s: Ship) -> Bool {
        !s.cannons.isEmpty || g.world.ships.turrets(of: s).contains { !$0.cannons.isEmpty }
    }

    // Throttle, steer and climb (each -1...1) for this frame, and a VTOL's strafe.
    static func read(_ g: Game, _ s: Ship, _ mi: MoveInput) -> (throttle: Float, steer: Float, climb: Float, strafe: Float) {
        var throttle = mi.forward, steer = mi.strafe, climb: Float = 0
        if mi.jump { climb += 1 }
        if g.input.control { climb -= 1 }
        func c(_ v: Float) -> Float { max(-1, min(1, v)) }
        if kind(s) == .vtol {
            // P334 (c): the left stick flies (forward/back, strafe), the right stick turns and climbs.
            var strafe: Float = 0
            if let p = g.seatPad {
                let ls = stick(p.lx, p.ly, dead: g.deadZone), rs = stick(p.rx, p.ry, dead: g.deadZone)
                steer = mi.strafe - ls.x + rs.x                  // (the keys' A/D still turn)
                strafe = ls.x
                climb += rs.y
                if p.rb { climb += 1 }
                if p.lb { climb -= 1 }
            }
            return (c(throttle), c(steer), c(climb), c(strafe))
        }
        if let p = g.seatPad {
            if kind(s) == .warship, let v = vrPitch {
                climb += abs(v) > 0.2 ? v : 0            // Quest: the right stick pitches the bow
            } else {
                if p.rb { climb += 1 }                   // RB / LB climb and descend on every vehicle (pitch, a warship)
                if p.lb { climb -= 1 }
            }
            let ls = stick(p.lx, p.ly, dead: g.deadZone)
            let keysForward = mi.forward - ls.y          // what the keys alone asked for
            let trig = p.rt - p.lt
            if armed(g, s) { return (max(-1, min(1, throttle)), max(-1, min(1, steer)), max(-1, min(1, climb)), 0) }
            switch kind(s) {
            case .boat, .land:
                throttle = keysForward + trig + ls.y * 0.5
            case .airship, .warship:
                throttle = keysForward + trig
                climb += ls.y
            case .aircraft:
                throttle = keysForward + trig
                climb += Settings.shared.flightInverted ? -ls.y : ls.y
            case .helicopter, .vtol:
                break                                    // collective / cyclic / pedals: FlightModel.playerInput
            }
        }
        return (c(throttle), c(steer), c(climb), 0)
    }

    // Prompt line while piloting.
    static func prompts(_ g: Game, _ s: Ship) -> [String] {
        if !Prompt.pad {
            func n(_ a: KeyBinds.Action) -> String { KeyBinds.name(KeyBinds.key(a)) }
            if kind(s) == .helicopter {
                return [Glyphs.key(n(.forward) + n(.left) + n(.back) + n(.right)) + " Cyclic", Glyphs.key(n(.jump)) + Glyphs.key("Ctrl") + " Collective",
                        "Mouse Turn", Glyphs.key("Shift") + " Leave"]
            }
            let up = kind(s) == .warship ? " Pitch" : " Climb"
            var k = [Glyphs.key(n(.forward) + "/" + n(.back)) + " Throttle", Glyphs.key(n(.left) + "/" + n(.right)) + " Steer",
                     Glyphs.key(n(.jump)) + Glyphs.key("Ctrl") + up, Glyphs.key("Shift") + " Leave"]
            if armed(g, s) { k.insert(Glyph.mouseL.s + " Fire", at: 2) }
            return k
        }
        let rt = PadMap.glyph(.rt).s, lt = PadMap.glyph(.lt).s, ls = Glyph.ls.s, b = PadMap.glyph(.b).s
        let climb = PadMap.glyph(.rb).s + PadMap.glyph(.lb).s
        if kind(s) == .vtol { return [ls + " Fly / Strafe", Glyph.rs.s + " Turn / Climb", rt + " Fire", b + " Leave"] }
        if armed(g, s) { return [ls + " Throttle / Steer", rt + " Fire", climb + (kind(s) == .warship ? " Pitch" : " Climb"), b + " Leave"] }
        switch kind(s) {
        case .boat, .land: return [rt + " Throttle", lt + " Reverse", ls + " Steer", b + " Leave"]
        case .airship: return [rt + " Forward", ls + " Turn / Climb", lt + " Reverse", b + " Leave"]
        case .warship: return [rt + " Forward", ls + " Turn / Pitch", lt + " Reverse", b + " Leave"]
        case .aircraft: return [rt + " Throttle", ls + " Bank / Pitch", lt + " Brake", b + " Leave"]
        case .helicopter: return [rt + lt + " Collective", ls + " Cyclic", Glyph.rs.s + " Turn", b + " Leave"]
        case .vtol: return [ls + " Fly / Strafe", Glyph.rs.s + " Turn / Climb", b + " Leave"]
        }
    }
}

// MARK: Manned deck guns

// Use a Steelhold deck gun (LT / right-click) to take its controls: the right stick / mouse turns and elevates
// the barrels, RT / left-click fires the twin shells (3 s reload), B / Shift steps off. The gun's own crew AI
// sleeps while you man it.
final class Turrets {
    static var shared = Turrets()      // var: split-screen seats swap it (Coop.swift)
    weak var manned: Mob?
    var reload: Float = 0
    var lastFired: Double = -10
    // P101 (Oct 12 12:15, "two barrels, so two shots per load"): each pull fires one barrel, left then right, a short
    // beat apart; the full reload comes after the second.
    var loaded = 2                                   // barrels loaded (2 after a reload)
    static let beat: Float = 0.45                    // between the two barrels
    weak var lastManned: Mob?
    // P372: taken by its handles on the headset: the hand aims it (`handAim`, a world direction), letting go leaves.
    var byGrip = false
    var handAim: V3?

    static let roofY: Float = 5.5                    // the heavy turret's gunhouse roof above its origin (HeavyTurret model)
    static func canMan(_ m: Mob) -> Bool { m.kind == .deckGun && m.health > 0 }

    // Rumble / harness helper: true while the player is on a gun.
    var active: Bool { manned != nil }

    func mount(_ g: Game, _ m: Mob) {
        let same = m === lastManned                  // back on the same gun: its reload and loaded barrel carry on
        manned = m
        lastManned = m
        m.aggro = false
        m.persistent = true
        if !same { reload = 0.5; loaded = 2 }
        g.player.yaw = m.yaw
        g.player.pitch = m.soldierBrain.pitch
        g.player.flying = false
        g.sfx(.place(.stone), 0.8, at: m.pos)
        g.onToast?("Manning the deck gun")
    }

    func leave(_ g: Game) {
        guard let m = manned else { return }
        manned = nil
        byGrip = false; handAim = nil
        let fwd = V3(-sinf(m.yaw), 0, -cosf(m.yaw))
        g.player.pos = Turrets.exitSpot(g.world, m, fwd: fwd)
        g.player.vel = .zero
        g.player.airPeak = g.player.pos.y
    }

    // P194 (Oct 13: "exiting the gun deposits you outside the base, in mid-air"): the nearest standing spot behind or
    // beside the gunhouse (solid floor, two clear blocks, within 2 up or down of the gun's base), nearest first, out to
    // 11 blocks; with none (a gun on a small tower roof), back on the gunhouse roof.
    static func exitSpot(_ w: World, _ m: Mob, fwd: V3) -> V3 {
        let right = V3(-fwd.z, 0, fwd.x)
        let dirs: [V3] = [-fwd, right, -right, simd_normalize(-fwd + right), simd_normalize(-fwd - right), fwd]
        for k in 3...11 {
            for d in dirs {
                let p = m.pos + d * Float(k)
                let x = Int(floor(p.x)), z = Int(floor(p.z)), y0 = Int(floor(m.pos.y))
                for dy in [0, 1, -1, 2, -2] {
                    let y = y0 + dy
                    let under = w.block(x, y - 1, z)
                    guard Blocks.collide[Int(under)] && !Blocks.isLiquid(under) else { continue }
                    let a = w.block(x, y, z), b = w.block(x, y + 1, z)
                    if !Blocks.collide[Int(a)] && !Blocks.collide[Int(b)] && !Blocks.isLiquid(a) {
                        return V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)
                    }
                }
            }
        }
        return m.pos - fwd * 2.5 + V3(0, Turrets.roofY, 0)
    }

    // Per frame while manning (from Game.tick before movement): true = the gun has the controls this frame.
    func tick(_ g: Game, _ p: PadSnapshot, _ q: PadSnapshot, sneak: Bool, dt: Float) -> Bool {
        guard let m = manned else { return false }
        if m.health <= 0 || !g.alive || g.mobs.mobs.first(where: { $0 === m }) == nil { manned = nil; return false }
        if sneak { leave(g); return false }
        let b = m.soldierBrain
        // P372: held by its handles, the barrels follow the hand.
        if let a = handAim, simd_length(a) > 0.1 {
            let n = simd_normalize(a)
            g.player.yaw = atan2f(-n.x, -n.z); g.player.pitch = asinf(max(-1, min(1, n.y)))
        }
        // The barrels follow the view, at the gun's traverse speed.
        var dyaw = g.player.yaw - m.yaw
        while dyaw > .pi { dyaw -= 2 * .pi }
        while dyaw < -.pi { dyaw += 2 * .pi }
        let turn: Float = 1.8 * dt
        if GunParts.canTurn(m) { m.yaw += max(-turn, min(turn, dyaw)) }              // P372: a broken mount holds it
        g.player.pitch = max(-0.17, min(0.9, g.player.pitch))
        b.pitch += max(-1.2 * dt, min(1.2 * dt, g.player.pitch - b.pitch))
        // Stand on the gunhouse roof ahead of the cupola, over the breeches: the eye is above the barrels with a clear
        // view forward (behind the breech put it inside the 5.5 m armoured box, so nothing was visible: Quest round 3).
        let fwd = V3(-sinf(m.yaw), 0, -cosf(m.yaw))
        g.player.pos = m.pos - fwd * 2.5 + V3(0, Turrets.roofY, 0)
        g.player.vel = .zero
        g.player.onGround = true
        reload -= dt
        if reload <= 0 && loaded == 0 { loaded = 2 }
        let fire = g.input.leftClicked || (p.rt > 0.5 && q.rt <= 0.5)
        if fire && reload <= 0 && GunParts.canFireAny(m) { shoot(g, m) }
        else if fire { g.sfx(.click, 0.4) }
        g.target = nil
        g.mining = nil
        return true
    }

    func shoot(_ g: Game, _ m: Mob) {
        let b = m.soldierBrain
        if loaded <= 0 { loaded = 2 }
        var sx: Float = loaded == 2 ? -1 : 1           // left barrel first
        if !GunParts.canFire(m, sx) { sx = -sx }       // P372: a broken barrel is skipped
        loaded -= 1
        reload = loaded > 0 ? Turrets.beat : HeavyTurret.reload * 0.6
        lastFired = g.clock
        let pivot = m.pos + V3(0, HeavyTurret.trunnionY, 0)
        let fwd = V3(-sinf(m.yaw) * cosf(b.pitch), sinf(b.pitch), -cosf(m.yaw) * cosf(b.pitch))
        let muzzle = HeavyTurret.muzzle(m, sx)
        var s = Slug(pos: muzzle, vel: Guns.scatter(fwd, 0.004) * HeavyTurret.speed, kind: .shell, damage: 0, fromPlayer: true,
                     shooter: ObjectIdentifier(m), by: "Player", life: 12, gravity: HeavyTurret.gravity)
        HeavyTurret.arm(&s)
        s.power = HeavyTurret.mannedPower; s.breach = HeavyTurret.mannedBreach      // P70
        g.arms.spawn(s)
        HeavyTurret.flash(g, muzzle, fwd, smoke: 10)
        b.kick = 1; b.kickSide = sx
        g.sfx(.gun(9), 2, at: pivot)
        g.baseNoise(at: pivot, kind: .cannon)
        PadManager.shared.rumble(0.9, 0.3, sharpness: 0.2)
        g.player.pitch += 0.03
        shots += 1
    }
    private(set) var shots = 0                        // (tests)

    func prompts() -> [String] {
        let ready = reload <= 0
        if Prompt.pad {
            return [PadMap.glyph(.rt).s + (ready ? (loaded == 1 ? " Fire right barrel" : " Fire") : " Reloading..."), Glyph.rs.s + " Aim", PadMap.glyph(.b).s + " Leave"]
        }
        return [Glyph.mouseL.s + (ready ? (loaded == 1 ? " Fire right barrel" : " Fire") : " Reloading..."), "Mouse Aim", Glyphs.key("Shift") + " Leave"]
    }
}
