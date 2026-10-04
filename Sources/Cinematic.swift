import Foundation
import simd

// Photo / cinematic camera (Future ideas #5). Photo mode (F6, or Pause > Photo Mode) detaches a free camera from the
// player and hides the HUD; the world keeps running. Fly it with WASD / left stick (Space / A up, Shift / LB down,
// sprint / L3 for speed), look with the mouse / right stick. Keyframes make a camera path that plays back smoothly
// (Catmull-Rom through every key, yaw unwrapped): K / X adds one, P / Y plays or stops, Backspace / D-pad left clears.
// Depth of field (Fancy graphics): F / RB toggles it, it focuses on what the centre of the view hits (autofocus) unless
// focus is set by hand with [ and ] / D-pad down and up; - and = / LT and RT change the aperture. B / Esc / F6 leaves.
final class Cinematic {
    struct Key { var pos: V3; var yaw: Float; var pitch: Float; var fov: Float }

    var active = false
    var pos = V3(0, 0, 0), yaw: Float = 0, pitch: Float = 0
    var fov: Float = 70
    var keys: [Key] = []
    var playing = false
    var t: Float = 0                  // path position: key index + fraction
    var secondsPerKey: Float = 3
    var dof = false
    var autoFocus = true
    var focus: Float = 12             // blocks
    var aperture: Float = 0.5         // 0...1: blur strength
    var hudWas = false
    var followPlayer = false          // harness: the camera is wherever the snapshot put the player
    var message = ""
    var messageTime: Float = 0

    // MARK: Path

    // Catmull-Rom through p1..p2 (p0 and p3 are the neighbours; ends repeat).
    static func cr(_ p0: Float, _ p1: Float, _ p2: Float, _ p3: Float, _ u: Float) -> Float {
        let u2 = u * u, u3 = u2 * u
        let a: Float = 2 * p1
        let b: Float = (p2 - p0) * u
        let c: Float = (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2
        let d: Float = (3 * p1 - p0 - 3 * p2 + p3) * u3
        return 0.5 * (a + b + c + d)
    }
    static func cr3(_ p0: V3, _ p1: V3, _ p2: V3, _ p3: V3, _ u: Float) -> V3 {
        V3(cr(p0.x, p1.x, p2.x, p3.x, u), cr(p0.y, p1.y, p2.y, p3.y, u), cr(p0.z, p1.z, p2.z, p3.z, u))
    }

    // The camera on the path at t (0 ... keys.count - 1). Yaw is unwrapped key to key so it never spins the long way.
    func sample(_ t: Float) -> Key? {
        guard !keys.isEmpty else { return nil }
        if keys.count == 1 { return keys[0] }
        var ks = keys
        for i in 1..<ks.count {
            var d = ks[i].yaw - ks[i - 1].yaw
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
            ks[i].yaw = ks[i - 1].yaw + d
        }
        let tt = max(0, min(Float(ks.count - 1), t))
        let i = min(ks.count - 2, Int(floorf(tt)))
        let u = tt - Float(i)
        let k0 = ks[max(0, i - 1)], k1 = ks[i], k2 = ks[i + 1], k3 = ks[min(ks.count - 1, i + 2)]
        return Key(pos: Cinematic.cr3(k0.pos, k1.pos, k2.pos, k3.pos, u),
                   yaw: Cinematic.cr(k0.yaw, k1.yaw, k2.yaw, k3.yaw, u),
                   pitch: max(-1.55, min(1.55, Cinematic.cr(k0.pitch, k1.pitch, k2.pitch, k3.pitch, u))),
                   fov: Cinematic.cr(k0.fov, k1.fov, k2.fov, k3.fov, u))
    }

    func say(_ s: String) { message = s; messageTime = 2.5 }

    // Harness self-test (--cinetest): the path passes through every key, moves smoothly between them and takes the
    // short way round in yaw.
    static func selfTest() -> Int {
        var fails = 0
        func check(_ ok: Bool, _ what: String) { print("\(ok ? "PASS" : "FAIL") cinematic: \(what)"); if !ok { fails += 1 } }
        let c = Cinematic()
        c.keys = [Key(pos: V3(0, 100, 0), yaw: 3.0, pitch: 0, fov: 70), Key(pos: V3(20, 110, 5), yaw: -3.0, pitch: 0.2, fov: 60),
                  Key(pos: V3(40, 105, 30), yaw: -2.5, pitch: -0.1, fov: 70), Key(pos: V3(30, 100, 60), yaw: -1.0, pitch: 0, fov: 80)]
        var through = true
        for (i, k) in c.keys.enumerated() { if let s = c.sample(Float(i)), simd_length(s.pos - k.pos) > 0.01 { through = false } }
        check(through, "the path passes through every keyframe")
        var maxStep: Float = 0, prev = c.sample(0)!.pos
        var t: Float = 0.01
        while t <= 3 { let p = c.sample(t)!.pos; maxStep = max(maxStep, simd_length(p - prev)); prev = p; t += 0.01 }
        check(maxStep < 1.2, String(format: "the path is smooth (largest step %.2f blocks per 1/100 key)", maxStep))
        let mid = c.sample(0.5)!.yaw
        check(abs(mid) > 3.0 && abs(mid) < 3.4, String(format: "yaw from 3.0 to -3.0 goes the short way round (mid %.2f)", mid))
        print("cinetest: \(fails == 0 ? "PASS" : "\(fails) FAILED")")
        return fails
    }
}

extension Game {
    func togglePhotoMode() {
        let c = cine
        if coop.active && !c.active { onToast?("Photo mode is for one player (end split screen first)"); return }
        if c.active {
            c.active = false
            c.playing = false
            hideHUD = c.hudWas
            onToast?("Photo mode off")
            return
        }
        c.active = true
        c.hudWas = hideHUD
        hideHUD = true
        c.pos = player.eye
        c.yaw = player.yaw; c.pitch = player.pitch
        c.fov = fovSetting
        c.say("Photo mode: K key, P play, F depth of field, F6 leave")
        onToast?(c.message)
    }

    // Photo mode input (the player stands still; the world runs on).
    func cineTick(_ p: PadSnapshot, _ q: PadSnapshot, _ dt: Float) {
        let c = cine
        defer { if c.messageTime >= 2.5 { onToast?(c.message); c.messageTime = 2.49 } }
        c.messageTime = max(0, c.messageTime - dt)
        if input.tapped(KeyBinds.key(.photo)) || input.tapped(Key.esc) || (p.b && !q.b) { togglePhotoMode(); return }
        if c.playing {
            c.t += dt / max(0.2, c.secondsPerKey)
            if let k = c.sample(c.t) { c.pos = k.pos; c.yaw = k.yaw; c.pitch = k.pitch; c.fov = k.fov }
            if c.t >= Float(c.keys.count - 1) { c.playing = false; c.say("Path finished") }
            if input.tapped(35) || (p.y && !q.y) { c.playing = false; c.say("Stopped") }      // P
        } else {
            // Look.
            if input.captured {
                c.yaw -= input.mouseDX * 0.0022 * sensitivity
                c.pitch -= input.mouseDY * 0.0022 * sensitivity * (invertY ? -1 : 1)
            }
            let look = PadLook.shared.update(rx: p.rx, ry: p.ry, dead: Settings.shared.lookDead, sensitivity: 0.6, invert: invertY, friction: 1, dt: dt)
            c.yaw += look.x; c.pitch = max(-1.55, min(1.55, c.pitch + look.y))
            // Fly (no collision).
            var f: Float = 0, s: Float = 0, u: Float = 0
            if input.down(KeyBinds.key(.forward)) { f += 1 }
            if input.down(KeyBinds.key(.back)) { f -= 1 }
            if input.down(KeyBinds.key(.right)) { s += 1 }
            if input.down(KeyBinds.key(.left)) { s -= 1 }
            if input.down(KeyBinds.key(.jump)) || p.a { u += 1 }
            if input.shift || p.lb { u -= 1 }
            let ls = stick(p.lx, p.ly, dead: deadZone)
            f += ls.y; s += ls.x
            let fast: Float = input.control || p.l3 ? 4 : 1
            let fw = V3(-sinf(c.yaw), 0, -cosf(c.yaw)), rt = V3(cosf(c.yaw), 0, -sinf(c.yaw))
            c.pos += (fw * f + rt * s + V3(0, u, 0)) * 8 * fast * dt
            // Keyframes and playback.
            if input.tapped(40) || (p.x && !q.x) {                                           // K
                c.keys.append(Cinematic.Key(pos: c.pos, yaw: c.yaw, pitch: c.pitch, fov: c.fov))
                c.say("Keyframe \(c.keys.count)")
            }
            if input.tapped(35) || (p.y && !q.y) {                                            // P
                if c.keys.count >= 2 { c.playing = true; c.t = 0; c.say("Playing \(c.keys.count) keys") } else { c.say("Add two keyframes first (K)") }
            }
            if input.tapped(51) || (p.left && !q.left) { c.keys.removeAll(); c.say("Path cleared") }   // Backspace
        }
        // Depth of field.
        if input.tapped(3) || (p.rb && !q.rb) { c.dof.toggle(); c.say(c.dof ? "Depth of field on" + (fancyGraphics ? "" : " (needs Fancy graphics)") : "Depth of field off") }
        if input.tapped(33) || (p.down && !q.down) { c.autoFocus = false; c.focus = max(1, c.focus / 1.25); c.say(String(format: "Focus %.1f", c.focus)) }   // [
        if input.tapped(30) || (p.up && !q.up) { c.autoFocus = false; c.focus = min(400, c.focus * 1.25); c.say(String(format: "Focus %.1f", c.focus)) }   // ]
        if input.tapped(27) || (p.lt > 0.5 && q.lt <= 0.5) { c.aperture = max(0.1, c.aperture - 0.1); c.say(String(format: "Aperture %.1f", c.aperture)) }  // -
        if input.tapped(24) || (p.rt > 0.5 && q.rt <= 0.5) { c.aperture = min(1, c.aperture + 0.1); c.say(String(format: "Aperture %.1f", c.aperture)) }   // =
        if input.tapped(37) || (p.r3 && !q.r3) { c.autoFocus = true; c.say("Autofocus") }   // L
        if c.dof && c.autoFocus {
            let look = V3(-sinf(c.yaw) * cosf(c.pitch), sinf(c.pitch), -cosf(c.yaw) * cosf(c.pitch))
            let hit = world.raycast(c.pos, look, maxDist: 300)
            let want: Float = hit.map { simd_length(V3(Float($0.hit.x), Float($0.hit.y), Float($0.hit.z)) + 0.5 - c.pos) } ?? 300
            c.focus += (want - c.focus) * min(1, dt * 4)
        }
    }
}
