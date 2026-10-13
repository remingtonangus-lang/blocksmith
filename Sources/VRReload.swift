import Foundation
import simd

// VR manual reload (Oct 11 evening playtest P56: "grab a magazine from the hip and put it in the gun"). With a gun in the
// aiming hand, the off hand reaching down by the hip and squeezing its grip takes a magazine (when the pack has rounds and
// the gun isn't full); bringing that hand to the gun hand slots it in and the gun is loaded at once. Letting go of the
// grip first drops it (nothing is lost: the rounds stay in the pack). The timed reload (X, or the trigger on an empty gun)
// still works, for seated play and comfort. The Quest controls feed hand positions in world space each frame.
enum VRReload {
    enum Event { case none, grabbed, inserted, dropped, refused }
    static let wellReach: Float = 0.16          // m between the hands that counts as the magazine at the well

    // Low beside the body: 0.4-1.2 m under the head and within 0.5 m of it sideways, and not out in front of the body
    // (P109, Oct 12 PM: "still can't grip left when I'm holding a gun": a hand held at the waist in front, the usual
    // pose for pressing a grip, counted as the hip, so with a gun not full every left grip took a magazine and the
    // hotbar never stepped). `forward`: the way the body faces (level).
    static let frontLimit: Float = 0.12
    static func atHip(head: V3, hand: V3, forward: V3? = nil) -> Bool {
        let d = hand - head
        guard d.y < -0.4 && d.y > -1.2 && simd_length(V2(d.x, d.z)) < 0.5 else { return false }
        if let f = forward { return simd_dot(V2(d.x, d.z), simd_normalize(V2(f.x, f.z))) < frontLimit }
        return true
    }

    static var grabs = 0, inserts = 0           // tests

    static func tick(_ g: Game, offHand: V3, gunHand: V3, head: V3, grip: Bool, gripWas: Bool) -> Event {
        let a = g.arms
        guard let gi = g.heldGun, g.alive else { a.magInHand = false; return .none }
        if a.magInHand {
            if !grip { a.magInHand = false; return .dropped }
            if simd_length(offHand - gunHand) < wellReach {
                a.magInHand = false
                a.reload = 0
                g.loadMagazine(gi)
                inserts += 1
                return .inserted
            }
            return .none
        }
        let fwd = V3(-sinf(g.player.yaw), 0, -cosf(g.player.yaw))
        guard grip && !gripWas && atHip(head: head, hand: offHand, forward: fwd) else { return .none }
        let gs = Guns.all[gi]
        // A full gun: the grip is the hotbar's (no toast; P74).
        if g.held.tag >= Guns.magSize(g.held) { return .none }
        if g.ammoCount(gs.ammo) <= 0 { g.onToast?("No \(Items.def(Items.id(gs.ammo)).display) to reload"); return .refused }
        a.magInHand = true
        a.reload = 0
        g.sfx(.gunReload(gs.sound), 0.5)
        grabs += 1
        return .grabbed
    }
}
