import Foundation
import simd

// VR manual reload (Oct 11 evening playtest P56: "grab a magazine from the hip and put it in the gun"). With a gun in the
// aiming hand, the off hand reaching down by the hip and squeezing its grip takes a magazine (when the pack has rounds and
// the gun isn't full); bringing that hand to the gun slots it in and the gun is loaded at once (P161: forgiving, below). The timed reload (X, or the trigger on an empty gun)
// still works, for seated play and comfort. The Quest controls feed hand positions in world space each frame.
enum VRReload {
    enum Event { case none, grabbed, inserted, dropped, refused, kept, full }
    // P161 (Oct 13: "loading a magazine is too hard"): forgiving now. The magazine stays in the hand once taken (no need
    // to keep squeezing) for up to `holdFor` seconds; it seats anywhere within `wellReach` of the gun, from the gun hand
    // along the barrel to `barrelReach` ahead of it; a fresh grip press away from the gun puts it back (and steps the
    // hotbar, P162). The hip zone is deeper and wider.
    // P286 (Oct 14 19:49, Oct 15 19:08: "still too hard", "not consistent enough"): wider again, and kept longer.
    static let wellReach: Float = 0.38          // m from the gun (was 0.16 from the gun hand only; P257: 0.26 -> 0.32; P286: 0.38)
    static let barrelReach: Float = 0.45
    static let holdFor: Double = 10
    static let wellSnap: Float = 0.5            // R7: m from the drawn magazine well (P257: 0.3 -> 0.42; P286: 0.5)
    // P286: a fresh squeeze while carrying a magazine only puts it back when the hand is this far from the gun (a
    // re-squeeze on the way to the well kept dropping it: the commonest miss).
    static let putBackFrom: Float = 0.7
    // P286 (b): the comfort option "Reload: Button" (Quest options): no hip pouch (the left grip is always the
    // hotbar's), and X reloads in 60% of the gun's time.
    static var buttonMode = false
    static let buttonScale: Float = 0.6
    // P286 (c): a shotgun's pouch handful: shells seated per trip to the gun (the timed reload still feeds one by one).
    static let handful = 4
    static let fresh: Double = 2                // P257: seconds after the hand reaches the hip that its grip takes a magazine
    static var takenAt: Double = 0

    // Low beside the body: 0.4-1.2 m under the head and within 0.5 m of it sideways, and not out in front of the body
    // (P109, Oct 12 PM: "still can't grip left when I'm holding a gun": a hand held at the waist in front, the usual
    // pose for pressing a grip, counted as the hip, so with a gun not full every left grip took a magazine and the
    // hotbar never stepped). `forward`: the way the body faces (level).
    // P257 (Oct 14 12:04, a repeat of R7: "taking a magazine from the hip is still too hard"): a bigger zone, 0.2-1.4 m
    // under the head (seated and lying back too), within 0.75 m sideways and up to 0.22 m in front of the body.
    // P286: 0.15-1.5 m under the head, within 0.85 m sideways, up to 0.28 m in front.
    static let frontLimit: Float = 0.28
    static func atHip(head: V3, hand: V3, forward: V3? = nil) -> Bool {
        let d = hand - head
        guard d.y < -0.15 && d.y > -1.5 && simd_length(V2(d.x, d.z)) < 0.85 else { return false }
        if let f = forward { return simd_dot(V2(d.x, d.z), simd_normalize(V2(f.x, f.z))) < frontLimit }
        return true
    }

    static var grabs = 0, inserts = 0           // tests

    // P257 (e): there is a magazine to take: a gun in hand, not full, rounds for it in the pack (or a second gun to load).
    static func canTake(_ g: Game) -> Bool {
        guard let gi = g.heldGun, !g.arms.magInHand else { return false }
        if g.held.tag >= Guns.magSize(g.held) && !DualWield.offEmptyOrLow(g) { return false }
        return g.ammoCount(Guns.all[gi].ammo) > 0
    }

    // Distance from the hand to the gun: the segment from the gun hand along the barrel.
    static func toGun(_ hand: V3, gunHand: V3, forward: V3?) -> Float {
        guard let f = forward else { return simd_length(hand - gunHand) }
        let t = max(0, min(barrelReach, simd_dot(hand - gunHand, f)))
        return simd_length(hand - (gunHand + f * t))
    }

    // `entered`: the hand reached the hip zone this frame (P286: a grip already squeezed on the way down takes one too).
    static func tick(_ g: Game, offHand: V3, gunHand: V3, head: V3, grip: Bool, gripWas: Bool, gunForward: V3? = nil, resting: Bool = false,
                     well: V3? = nil, entered: Bool = false) -> Event {
        let a = g.arms
        guard let gi = g.heldGun, g.alive else { a.magInHand = false; return .none }
        if a.magInHand {
            // R7 (Oct 13: "loading a magazine from the hip is too hard"): the drawn gun is 3.2x, so its magazine well hangs
            // well away from the hand and the barrel segment; a magazine brought to the well as drawn seats too (within
            // `wellSnap` of it), with a heavy click in both hands and the gun's latch sound.
            let dGun = toGun(offHand, gunHand: gunHand, forward: gunForward)
            let near = dGun < wellReach || well.map { simd_length(offHand - $0) < wellSnap } == true
            if g.clock - takenAt > holdFor { a.magInHand = false; return .dropped }
            if grip && !gripWas && !near {
                if dGun > putBackFrom { a.magInHand = false; return .dropped }
                return .kept                                // (a re-squeeze on the way: still in hand, no hotbar step)
            }
            if near {
                a.magInHand = false
                a.reload = 0
                g.loadMagazine(gi, shells: GunActions.shellByShell(gi) ? handful : nil)     // D7 / P286 (c): a handful of shells
                inserts += 1
                return .inserted
            }
            return .none
        }
        let fwd = V3(-sinf(g.player.yaw), 0, -cosf(g.player.yaw))
        // R1: a hand resting at the side (the relaxed arm) is not a reach for the pouch; its grip is the hotbar's.
        guard !buttonMode, grip && (!gripWas || entered) && !resting && atHip(head: head, hand: offHand, forward: fwd) else { return .none }
        let gs = Guns.all[gi]
        // A full gun: nothing to take (no toast; P74). P465 (Oct 25 19:41-19:42, "Reloading sucks... I am not trying to
        // move across the toolbar": a squeeze at the hip for the Faustrohr's next warhead stepped the hotbar off the
        // launcher): a reach for the pouch never steps the hotbar; the grip in front of the waist (P109) still does.
        if g.held.tag >= Guns.magSize(g.held) && !DualWield.offEmptyOrLow(g) { return .full }
        if g.ammoCount(gs.ammo) <= 0 { g.onToast?("No \(Items.def(Items.id(gs.ammo)).display)"); return .refused }   // P300 (b)
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
