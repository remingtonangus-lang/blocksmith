import Foundation
import simd

// D36: bodies found raise the alarm, so stealth plays differently from going loud.
//   bodies     a Greywall soldier killed inside his base while it is quiet (a knife from behind, a suppressed shot)
//              leaves his body where he fell (a dark stain on the ground, five minutes). Any of his comrades who comes
//              within 10 blocks of it with a clear view sounds the alarm there: "They've found a body!". Kill out of
//              sight and away from patrol routes; or drag the fight somewhere quiet.
//   loud       once a base's alarm has sounded it is marked loud (saved: TownLaw.state.loudBases).
//   ghost      take a base that never went loud and the garrison's pay chest is yours on top ($100, honour 3).
enum Bodies {
    struct Body { let key: String; let pos: V3; let t: Double }
    static var list: [Body] = []
    static let lasts: Double = 300, sight: Float = 10
    static var found = 0, ghosts = 0                      // (harness)

    static func loud(_ key: String) -> Bool { TownLaw.state.loudBases?.contains(key) ?? false }
    static func markLoud(_ key: String) {
        guard !loud(key) else { return }
        var l = TownLaw.state.loudBases ?? []; l.append(key); TownLaw.state.loudBases = l
    }
}

extension Game {
    // soldierDied: a quiet kill inside a base leaves a body.
    func bodyLeft(_ m: Mob) {
        guard m.factionValue == .greywall else { return }
        for (key, site) in bases.greywall.sites where !site.on && !bases.greywall.taken.contains(key) && Greywall.inside(site, m.pos) {
            if Bodies.list.count >= 32 { Bodies.list.removeFirst() }
            Bodies.list.append(Bodies.Body(key: key, pos: m.pos, t: clock))
            return
        }
    }

    // Once a second, before greywallAlarmTick (BaseSecurity.tick's pace): bodies spotted, loud bases marked.
    func bodiesTick(_ b: BaseWatch) {
        let st = b.greywall
        for (key, site) in st.sites where site.on { Bodies.markLoud(key) }
        Bodies.list.removeAll { clock - $0.t > Bodies.lasts || st.taken.contains($0.key) }
        guard !Bodies.list.isEmpty else { return }
        var spotted: [Int] = []
        for (i, body) in Bodies.list.enumerated() {
            if let site = st.sites[body.key], site.on { continue }
            let see = body.pos + V3(0, 0.3, 0)
            // A stain where he fell.
            if Rand.float(in: 0..<1) < 0.3 {
                particles.add(Particle(pos: see, vel: V3(0, 0.05, 0), life: 1.2, maxLife: 1.2, layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1,
                                       size: 0.18, gravity: 0, color: V3(0.3, 0.03, 0.03), collide: false))
            }
            if mobs.mobs.contains(where: { $0.factionValue == .greywall && $0.health > 0 && $0.kind != .deckGun
                    && simd_length($0.pos - body.pos) < Bodies.sight && world.canSee($0.eye, see) }) {
                spotted.append(i)
                if b.noises.count < 48 { b.noises.append(BaseNoise(pos: body.pos, kind: .gunshot, power: 0.8, hostile: true)) }
                Bodies.found += 1
                onToast?("They've found a body! The base is on alert")
            }
        }
        for i in spotted.reversed() { Bodies.list.remove(at: i) }
    }

    // greywallTake: a base taken without its alarm ever sounding.
    func ghostTake(_ key: String) {
        guard survival, !Bodies.loud(key) else { return }
        Bodies.ghosts += 1
        money += 10000
        Honour.earn(self, 3, source: "outlaw", "a base taken unseen")
        onToast?("Taken without a single alarm. The garrison's pay chest is yours (+\(Money.format(10000)))")
    }
}
