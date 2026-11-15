import Foundation

// Nov 14 playtest (21:07:33, at a line's locomotive, -11959 80 -869: "Should be able to see myself driving the train";
// as Nov 1's "I should be able to see myself when I'm driving the sidecar"): his body under the view (P466's, the
// inventory figure's own without head and arms, the tracked hands being the arms) stood on the footplate while he
// drives a locomotive from its cab, whatever VR Comfort's Show My Body says (that stays off for walking, P473: "I
// don't wanna see myself. Gets in the way"). BS_OLDCABBODY=1: no body in the cab.
extension Game {
    static let oldCabBody = Env.all["BS_OLDCABBODY"] == "1"
    // At a big locomotive's regulator (riding the engine is driving it).
    var drivingCab: Bool {
        guard !Game.oldCabBody, let r = riding else { return false }
        return Trains.isEngine(r) && Trains.isBig(r)
    }
    // Whether his body is drawn under the view (QuestControls.appendBody); `showBody`: VR Comfort's Show My Body.
    func bodyUnderView(showBody: Bool) -> Bool {
        guard alive, sleeping == 0, !player.prone else { return false }
        if drivingCab { return true }
        return showBody && riding == nil && world.ships.pilot == nil && Turrets.shared.manned == nil && !handsOnControls
    }
}

// Nov 14 playtest ("Bullets should be doing micro damage to the hulls"): a small-arms round that strikes a hull (a
// vehicle's, a vessel's, a capital ship's) stopped there and did nothing. It now chips the hull a counted, tiny amount:
// a hundredth of a block a point of damage (a rifle round 0.05, a magazine about a block's worth), never a hole, and
// small arms alone take at most a tenth of the hull (a pistol can't sink a ship). The chip is read by the hull bar and
// the shares a hull founders, gives up or limps at (Ship.hullBlocks), and by a capital ship's integrity. Shells,
// rockets and blasts are as they were. BS_OLDCHIP=1: rounds do nothing to hulls.
extension ShipManager {
    static let oldChip = Env.all["BS_OLDCHIP"] == "1"
    static let chipPerDamage: Float = 0.01, chipCap: Float = 0.1
    static var chipHits = 0                                   // (checks)
    func chip(_ part: Ship, _ damage: Float) {
        guard !ShipManager.oldChip, damage > 0 else { return }
        let s = part.root
        let whole = Float(max(s.initialBlocks, s.blockCount))
        s.chip = min(whole * ShipManager.chipCap, s.chip + damage * ShipManager.chipPerDamage)
        ShipManager.chipHits += 1
    }
}

// Nov 14 playtest (20:56:43, driving the Ironback Crawler: "the HUD kind of gets in the way sometimes"; the 30 s before
// it put up eight lines of travel news over the view: "Ardesh - Tamargard border post marked on the map", "Fort Red
// Station marked on the map", "You found the Fort & Ash Rail Road: 2 stations, marked on your map", "Entering
// Savenonia"...). At a helm or a regulator (Game.drivingHUD) that news goes to the journal only; what is about the
// drive, the fight or him (hits, the hull, orders, intel) still shows. BS_OLDDRIVETOASTS=1: all of it shows.
extension Game {
    static let oldDriveToasts = Env.all["BS_OLDDRIVETOASTS"] == "1"
    static func travelNews(_ s: String) -> Bool {
        s.hasSuffix(" marked on the map") || s.hasSuffix("marked on your map") || s.hasPrefix("Entering ") || s.hasPrefix("Leaving ")
    }
    func quietWhileDriving(_ s: String) -> Bool {
        !Game.oldDriveToasts && drivingHUD && Game.travelNews(s)
    }
}
