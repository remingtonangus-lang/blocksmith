import Foundation
import simd

// Controller and keyboard layouts for piloting ships, airships, aircraft and land vehicles (Ships.swift),
// and for manning Steelhold deck guns. Keyboard keeps W/S throttle, A/D steer, Space/Ctrl climb, Shift leave.
// Controller, by vehicle:
//   boat / land vehicle   RT throttle, LT reverse, LS steer
//   airship              RT forward, LT reverse, LS left/right turn, LS up/down climb
//   aircraft             RT throttle, LT brake, LS left/right bank and turn, LS up/down pitch (pull back to climb,
//                        Options > Controller > Flight Stick)
//   any                  A climb, B leave the helm
enum VehicleControls {
    enum Kind { case boat, land, airship, aircraft }

    static func kind(_ s: Ship) -> Kind {
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
        }
    }

    // Cannons on the vessel or its turrets: then RT fires them (ShipPlay) and the left stick is the throttle.
    static func armed(_ g: Game, _ s: Ship) -> Bool {
        !s.cannons.isEmpty || g.world.ships.turrets(of: s).contains { !$0.cannons.isEmpty }
    }

    // Throttle, steer and climb (each -1...1) for this frame.
    static func read(_ g: Game, _ s: Ship, _ mi: MoveInput) -> (throttle: Float, steer: Float, climb: Float) {
        var throttle = mi.forward, steer = mi.strafe, climb: Float = 0
        if mi.jump { climb += 1 }
        if g.input.control { climb -= 1 }
        if let p = PadManager.shared.lastMapped {
            if p.rb { climb += 1 }                       // RB / LB climb and descend on every vehicle
            if p.lb { climb -= 1 }
            let ls = stick(p.lx, p.ly, dead: g.deadZone)
            let keysForward = mi.forward - ls.y          // what the keys alone asked for
            let trig = p.rt - p.lt
            if armed(g, s) { return (max(-1, min(1, throttle)), max(-1, min(1, steer)), max(-1, min(1, climb))) }
            switch kind(s) {
            case .boat, .land:
                throttle = keysForward + trig + ls.y * 0.5
            case .airship:
                throttle = keysForward + trig
                climb += ls.y
            case .aircraft:
                throttle = keysForward + trig
                climb += Settings.shared.flightInverted ? -ls.y : ls.y
            }
        }
        func c(_ v: Float) -> Float { max(-1, min(1, v)) }
        return (c(throttle), c(steer), c(climb))
    }

    // Prompt line while piloting.
    static func prompts(_ g: Game, _ s: Ship) -> [String] {
        if !Prompt.pad {
            func n(_ a: KeyBinds.Action) -> String { KeyBinds.name(KeyBinds.key(a)) }
            var k = [Glyphs.key(n(.forward) + "/" + n(.back)) + " Throttle", Glyphs.key(n(.left) + "/" + n(.right)) + " Steer",
                     Glyphs.key(n(.jump)) + Glyphs.key("Ctrl") + " Climb", Glyphs.key("Shift") + " Leave"]
            if armed(g, s) { k.insert(Glyph.mouseL.s + " Fire", at: 2) }
            return k
        }
        let rt = PadMap.glyph(.rt).s, lt = PadMap.glyph(.lt).s, ls = Glyph.ls.s, b = PadMap.glyph(.b).s
        let climb = PadMap.glyph(.rb).s + PadMap.glyph(.lb).s
        if armed(g, s) { return [ls + " Throttle / Steer", rt + " Fire", climb + " Climb", b + " Leave"] }
        switch kind(s) {
        case .boat, .land: return [rt + " Throttle", lt + " Reverse", ls + " Steer", b + " Leave"]
        case .airship: return [rt + " Forward", ls + " Turn / Climb", lt + " Reverse", b + " Leave"]
        case .aircraft: return [rt + " Throttle", ls + " Bank / Pitch", lt + " Brake", b + " Leave"]
        }
    }
}

// MARK: Manned deck guns

// Use a Steelhold deck gun (LT / right-click) to take its controls: the right stick / mouse turns and elevates
// the barrels, RT / left-click fires the twin shells (3 s reload), B / Shift steps off. The gun's own crew AI
// sleeps while you man it.
final class Turrets {
    static let shared = Turrets()
    weak var manned: Mob?
    var reload: Float = 0
    var lastFired: Double = -10

    static func canMan(_ m: Mob) -> Bool { m.kind == .deckGun && m.health > 0 }

    // Rumble / harness helper: true while the player is on a gun.
    var active: Bool { manned != nil }

    func mount(_ g: Game, _ m: Mob) {
        manned = m
        m.aggro = false
        m.persistent = true
        reload = 0.5
        g.player.yaw = m.yaw
        g.player.pitch = m.soldierBrain.pitch
        g.player.flying = false
        g.sfx(.place(.stone), 0.8, at: m.pos)
        g.onToast?("Manning the deck gun")
    }

    func leave(_ g: Game) {
        guard let m = manned else { return }
        manned = nil
        let side = V3(cosf(m.yaw), 0, -sinf(m.yaw))
        g.player.pos = m.pos + side * 1.6
        g.player.vel = .zero
    }

    // Per frame while manning (from Game.tick before movement): true = the gun has the controls this frame.
    func tick(_ g: Game, _ p: PadSnapshot, _ q: PadSnapshot, sneak: Bool, dt: Float) -> Bool {
        guard let m = manned else { return false }
        if m.health <= 0 || !g.alive || g.mobs.mobs.first(where: { $0 === m }) == nil { manned = nil; return false }
        if sneak { leave(g); return false }
        let b = m.soldierBrain
        // The barrels follow the view, at the gun's traverse speed.
        var dyaw = g.player.yaw - m.yaw
        while dyaw > .pi { dyaw -= 2 * .pi }
        while dyaw < -.pi { dyaw += 2 * .pi }
        let turn: Float = 1.8 * dt
        m.yaw += max(-turn, min(turn, dyaw))
        g.player.pitch = max(-0.17, min(0.9, g.player.pitch))
        b.pitch += max(-1.2 * dt, min(1.2 * dt, g.player.pitch - b.pitch))
        // Stand behind the breech.
        let fwd = V3(-sinf(m.yaw), 0, -cosf(m.yaw))
        g.player.pos = m.pos - fwd * 1.3
        g.player.vel = .zero
        g.player.onGround = true
        reload -= dt
        let fire = g.input.leftClicked || (p.rt > 0.5 && q.rt <= 0.5)
        if fire && reload <= 0 { shoot(g, m) }
        else if fire { g.sfx(.click, 0.4) }
        g.target = nil
        g.mining = nil
        return true
    }

    func shoot(_ g: Game, _ m: Mob) {
        let b = m.soldierBrain
        reload = 3
        lastFired = g.clock
        let pivot = m.pos + V3(0, 1.0, 0)
        let fwd = V3(-sinf(m.yaw) * cosf(b.pitch), sinf(b.pitch), -cosf(m.yaw) * cosf(b.pitch))
        let side = V3(cosf(m.yaw), 0, -sinf(m.yaw))
        for sx: Float in [-1, 1] {
            let muzzle = pivot + fwd * 3.4 + side * (sx * 0.44)
            var s = Slug(pos: muzzle, vel: Guns.scatter(fwd, 0.008) * 55, kind: .shell, damage: 0, fromPlayer: true,
                         shooter: ObjectIdentifier(m), by: "Player", life: 6, gravity: 20)
            s.power = 1.8
            g.arms.spawn(s)
            for _ in 0..<6 { g.particles.smoke(at: muzzle + fwd * Float.random(in: 0...1), dark: false) }
        }
        g.sfx(.gun(9), 2, at: pivot)
        PadManager.shared.rumble(0.9, 0.3, sharpness: 0.2)
        g.player.pitch += 0.03
    }

    func prompts() -> [String] {
        let ready = reload <= 0
        if Prompt.pad {
            return [PadMap.glyph(.rt).s + (ready ? " Fire" : " Reloading..."), Glyph.rs.s + " Aim", PadMap.glyph(.b).s + " Leave"]
        }
        return [Glyph.mouseL.s + (ready ? " Fire" : " Reloading..."), "Mouse Aim", Glyphs.key("Shift") + " Leave"]
    }
}
