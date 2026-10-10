import Foundation
import simd

// Boreal Station alarm. A hostile noise inside a station's fence or bunker (gunshots, blasts: the same noise bus the
// Capital citadels hear, Game.baseNoise), or a garrison soldier who sees the player inside, sets the alarm off: a
// klaxon blares every few seconds from the hall, the blockhouse and the yard (whichever is nearest the player, so it
// carries underground), and every soldier of the station turns on the source. It runs while there is noise or a
// fight and stops 45 s after the last of it. In memory only: a reload finds the station quiet again.
final class BorealAlarmState {
    struct Site { var cx: Int, cz: Int, S: Int; var on = false; var quiet: Float = 0; var blare: Float = 0; var src = V3(0, 0, 0) }
    var sites: [String: Site] = [:]
    var log: [String] = []                       // harness: what happened, in order
    static let blareEvery: Float = 4
    static let standDown: Float = 45
}

extension BorealStation {
    static func insideSite(_ s: BorealAlarmState.Site, _ p: V3) -> Bool {
        abs(p.x - Float(s.cx)) < Float(yard + 2) && abs(p.z - Float(s.cz)) < Float(yard + 2)
            && p.y > Float(s.S - depth - 3) && p.y < Float(s.S + 30)
    }
}

extension Game {
    var borealAlarm: BorealAlarmState { bases.boreal }

    // Called once a second from basesTick, with that second's noises (before they are cleared).
    func borealAlarmTick(_ b: BaseWatch, _ dt: Float) {
        let st = b.boreal
        guard let sc = world.gen.structures else { return }
        for i in 0..<max(1, coop.seatCount) {
            let pp = coop.seatPlayer(i, self).pos
            guard let s = sc.nearest(BorealStation.kind, x: Int(pp.x), z: Int(pp.z), maxRegions: 1) else { continue }
            let cx = (s.min.x + s.max.x) / 2, cz = (s.min.z + s.max.z) / 2
            let key = "boreal:\(cx),\(cz)"
            if st.sites[key] == nil, world.isLoaded(cx, cz), let lv = BorealStation.levels(world, s) {
                st.sites[key] = BorealAlarmState.Site(cx: cx, cz: cz, S: lv.S)
            }
        }
        for key in Array(st.sites.keys) {
            guard var site = st.sites[key], world.isLoaded(site.cx, site.cz) else { continue }
            var trigger: V3? = nil
            for n in b.noises where n.hostile && BorealStation.insideSite(site, n.pos) { trigger = n.pos }
            // A soldier of the station who can see a player inside it.
            let players = (0..<max(1, coop.seatCount)).map { coop.seatPlayer($0, self).pos }
            if survival, trigger == nil, let p = players.first(where: { BorealStation.insideSite(site, $0) }) {
                if mobs.mobs.contains(where: { $0.kind.steelhold && $0.kind != .deckGun && $0.health > 0 && $0.aggro
                                               && ($0.brain?.sees ?? false) && BorealStation.insideSite(site, $0.pos) }) { trigger = p }
            }
            if let t = trigger {
                site.quiet = 0
                site.src = t
                if !site.on {
                    site.on = true
                    site.blare = 0
                    st.log.append("\(key) alarm on at \(Int(t.x)),\(Int(t.y)),\(Int(t.z))")
                    if players.contains(where: { simd_length($0 - V3(Float(site.cx), Float(site.S), Float(site.cz))) < 120 }) {
                        onToast?("The station alarm is sounding!")
                    }
                }
            } else if site.on {
                site.quiet += dt
                let fighting = mobs.mobs.contains { $0.kind.steelhold && $0.health > 0 && $0.aggro && ($0.brain?.sees ?? false)
                                                    && BorealStation.insideSite(site, $0.pos) }
                if site.quiet > BorealAlarmState.standDown && !fighting {
                    site.on = false
                    st.log.append("\(key) alarm off")
                }
            }
            if site.on {
                // The garrison turns on the source.
                for m in mobs.mobs where m.kind.steelhold && m.kind != .deckGun && m.health > 0 && BorealStation.insideSite(site, m.pos) {
                    let br = m.soldierBrain
                    br.ready = true
                    if !m.aggro { m.aggro = true; br.react = max(br.react, 0.5) }
                    if !br.sees { br.lastSeen = site.src; br.seenAgo = min(br.seenAgo, 2) }
                    m.lockTime = max(m.lockTime, 20)
                }
                // The klaxon from the speaker nearest the player: hall, blockhouse or yard.
                site.blare -= dt
                if site.blare <= 0 {
                    site.blare = BorealAlarmState.blareEvery
                    let F = site.S - BorealStation.depth
                    let speakers = [V3(Float(site.cx) + 0.5, Float(F + 7), Float(site.cz) + 0.5),
                                    V3(Float(site.cx) + 0.5, Float(site.S + 4), Float(site.cz + 18) + 0.5),
                                    V3(Float(site.cx) + 0.5, Float(site.S + 4), Float(site.cz) + 0.5)]
                    let p = player.pos
                    if let sp = speakers.min(by: { simd_length($0 - p) < simd_length($1 - p) }), simd_length(sp - p) < 96 {
                        sfx(.gun(10), 1.2, at: sp)
                    }
                }
            }
            st.sites[key] = site
        }
    }
}
