import Foundation
import simd

// VR manual reload (Oct 11 evening playtest P56: "grab a magazine from the hip and put it in the gun"). With a gun in the
// aiming hand, the off hand reaching down by the hip and squeezing its grip takes a magazine (when the pack has rounds and
// the gun isn't full); bringing that hand to the gun slots it in and the gun is loaded at once (P161: forgiving, below). The timed reload (X, or the trigger on an empty gun)
// still works, for seated play and comfort. The Quest controls feed hand positions in world space each frame.
enum VRReload {
    enum Event { case none, grabbed, inserted, dropped, refused }
    // P161 (Oct 13: "loading a magazine is too hard"): forgiving now. The magazine stays in the hand once taken (no need
    // to keep squeezing) for up to `holdFor` seconds; it seats anywhere within `wellReach` of the gun, from the gun hand
    // along the barrel to `barrelReach` ahead of it; a fresh grip press away from the gun puts it back (and steps the
    // hotbar, P162). The hip zone is deeper and wider.
    static let wellReach: Float = 0.26          // m from the gun (was 0.16 from the gun hand only)
    static let barrelReach: Float = 0.4
    static let holdFor: Double = 6
    static let wellSnap: Float = 0.3            // R7: m from the drawn magazine well
    static var takenAt: Double = 0

    // Low beside the body: 0.4-1.2 m under the head and within 0.5 m of it sideways, and not out in front of the body
    // (P109, Oct 12 PM: "still can't grip left when I'm holding a gun": a hand held at the waist in front, the usual
    // pose for pressing a grip, counted as the hip, so with a gun not full every left grip took a magazine and the
    // hotbar never stepped). `forward`: the way the body faces (level).
    static let frontLimit: Float = 0.12
    static func atHip(head: V3, hand: V3, forward: V3? = nil) -> Bool {
        let d = hand - head
        guard d.y < -0.3 && d.y > -1.3 && simd_length(V2(d.x, d.z)) < 0.6 else { return false }
        if let f = forward { return simd_dot(V2(d.x, d.z), simd_normalize(V2(f.x, f.z))) < frontLimit }
        return true
    }

    static var grabs = 0, inserts = 0           // tests

    // Distance from the hand to the gun: the segment from the gun hand along the barrel.
    static func toGun(_ hand: V3, gunHand: V3, forward: V3?) -> Float {
        guard let f = forward else { return simd_length(hand - gunHand) }
        let t = max(0, min(barrelReach, simd_dot(hand - gunHand, f)))
        return simd_length(hand - (gunHand + f * t))
    }

    static func tick(_ g: Game, offHand: V3, gunHand: V3, head: V3, grip: Bool, gripWas: Bool, gunForward: V3? = nil, resting: Bool = false, well: V3? = nil) -> Event {
        let a = g.arms
        guard let gi = g.heldGun, g.alive else { a.magInHand = false; return .none }
        if a.magInHand {
            // R7 (Oct 13: "loading a magazine from the hip is too hard"): the drawn gun is 3.2x, so its magazine well hangs
            // well away from the hand and the barrel segment; a magazine brought to the well as drawn seats too (within
            // `wellSnap` of it), with a heavy click in both hands and the gun's latch sound.
            let near = toGun(offHand, gunHand: gunHand, forward: gunForward) < wellReach || well.map { simd_length(offHand - $0) < wellSnap } == true
            if (grip && !gripWas && !near) || g.clock - takenAt > holdFor { a.magInHand = false; return .dropped }
            if near {
                a.magInHand = false
                a.reload = 0
                g.loadMagazine(gi, shells: GunActions.shellByShell(gi) ? 1 : nil)     // D7: shell by shell
                inserts += 1
                return .inserted
            }
            return .none
        }
        let fwd = V3(-sinf(g.player.yaw), 0, -cosf(g.player.yaw))
        // R1: a hand resting at the side (the relaxed arm) is not a reach for the pouch; its grip is the hotbar's.
        guard grip && !gripWas && !resting && atHip(head: head, hand: offHand, forward: fwd) else { return .none }
        let gs = Guns.all[gi]
        // A full gun: the grip is the hotbar's (no toast; P74).
        if g.held.tag >= Guns.magSize(g.held) && !DualWield.offEmptyOrLow(g) { return .none }
        if g.ammoCount(gs.ammo) <= 0 { g.onToast?("No \(Items.def(Items.id(gs.ammo)).display) to reload: " + Guns.ammoSource(gs.ammo)); return .refused }
        // D8: both hands full (two revolvers): a speedloader for each gun, at once.
        if DualWield.active(g) != nil {
            g.loadMagazine(gi)
            DualWield.reloadOff(g)
            inserts += 1
            return .inserted
        }
        a.magInHand = true
        takenAt = g.clock
        a.reload = 0
        g.sfx(.gunReload(gs.sound), 0.5)
        grabs += 1
        return .grabbed
    }
}
