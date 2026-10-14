import Foundation
import simd

// D6 holsters on the body (VR). Handguns ride on the body, not only in the hotbar: the first handgun in the hotbar
// sits in the hip holster on the gun-hand side, the second in a cross-draw holster at the chest. The gun hand reaching
// to a holster and gripping draws that gun at once (a quick draw: half the usual raise, a hammer click); gripping
// there again with the gun out holsters it and the hand goes back to what it held before. Those grips don't step the
// hotbar.
enum Holsters {
    enum Zone { case none, hip, chest }
    static var before: Int?                          // the hotbar slot held before the draw
    static var draws = 0, holsters = 0               // (tests)

    // Where a hand is on the body: `head` and its level `yaw`.
    static func zone(head: V3, yaw: Float, hand: V3) -> Zone {
        let fwd = V3(-sinf(yaw), 0, -cosf(yaw)), right = V3(cosf(yaw), 0, -sinf(yaw))
        let d = hand - head
        let chest = V3(0, -0.5, 0) + fwd * 0.14 - right * 0.06
        if simd_length(d - chest) < 0.12 { return .chest }
        let side = simd_dot(d, right), ahead = simd_dot(d, fwd)
        if d.y < -0.55 && d.y > -1.2 && side > 0.1 && side < 0.45 && ahead < 0.18 && ahead > -0.25 { return .hip }
        return .none
    }

    // Hotbar slots of the holstered guns: the first handgun (hip) and the second (chest).
    static func slots(_ g: Game) -> (hip: Int?, chest: Int?) {
        var found: [Int] = []
        for i in 0..<9 {
            let s = g.inventory.main.slots[i]
            if !s.isEmpty, let gi = Guns.index(s.item), Guns.isHandgun(gi) { found.append(i) }
            if found.count == 2 { break }
        }
        return (found.first, found.count > 1 ? found[1] : nil)
    }

    // A grip press with the gun hand in `z`. True when the holster took it (draw or holster).
    @discardableResult
    static func grip(_ g: Game, _ z: Zone) -> Bool {
        guard z != .none, g.alive else { return false }
        let (hip, chest) = slots(g)
        guard let slot = z == .hip ? hip : chest else { return false }
        if g.selected == slot {
            // Holster it: back to what the hand held before (or the first slot without a handgun).
            let back = before.flatMap { $0 != slot ? $0 : nil }
                ?? (0..<9).first { i in i != hip && i != chest } ?? slot
            g.select(back)
            before = nil
            g.sfx(.gunReload(Guns.all[Guns.revolver].sound), 0.25)
            holsters += 1
            return true
        }
        before = g.selected
        g.select(slot)
        g.equipAnim = 0.5                            // a quick draw
        if let gi = g.heldGun { g.sfx(.gunReload(Guns.all[gi].sound), 0.35) }
        draws += 1
        return true
    }
}
