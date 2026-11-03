import Foundation
import simd

// P508 (his Nov 1 16:26 list: "stealth everywhere"). Every enemy noticed him the moment it had a line to him inside its
// range, whichever way it faced, by day or by night, whether he crept or ran: crouching only cut the range by a fifth.
// Now an enemy that hasn't found him yet has to notice him (Mob.notice, 0 to 1, raised every sight check):
//   facing     in front of it (60 degrees either side) at full speed, off to the side at a third, never behind (the
//              creatures of the dark: 0.6 at the side, 0.3 behind)
//   distance   in plain view within 24 blocks noticed at the first look; twice as long at 48
//   light      soldiers, raiders and townsfolk see by the light where he stands (night and dark rooms hide him); the
//              creatures of the dark see nearly as well without it
//   manner     crouched 0.4, standing still 0.7, sprinting 1.4; in tall grass, crops or leaves half again
//   close by   within 3 blocks (1.5 crouched) it hears him whatever way it faces
//   noise      a shot or a blast of his within 48 blocks gives him away at once (Stealth.loud, Game.baseNoise)
// Half noticed, it turns to look. Unseen, the notice drains over three seconds. Once it has found him (or he hurts it,
// or its side is alarmed) it tracks him as before. The silent takedown (Takedowns), the bodies found (Bodies) and the
// quiet extractions (BorealOps) are the rest of it.
enum Stealth {
    static var on = true
    static var noticed = 0                           // (harness: enemies that noticed him through the gauge)
    // The last loud thing he did: where, when, how loud.
    static var loud: (pos: V3, at: Double, power: Float) = (.zero, -100, 0)

    static func heard(_ g: Game, at p: V3, power: Float) {
        guard simd_length(p - g.player.pos) < 6 else { return }
        loud = (p, g.clock, power)
    }

    // Humans see by the light (soldiers of every side, raiders, outlaws, townsfolk); the rest hardly need it.
    static func seesByLight(_ k: MobKind) -> Bool {
        k.steelhold || Soldier.rank(k) != nil || k == .pillager || k == .vindicator || k == .evoker || k == .illusioner
            || k == .villager || k == .witch
    }

    // One sight check for a body not yet after him (`seen`: in its range with a line to him). True when it has him.
    static func notices(_ g: Game, _ m: Mob, dist: Float, seen: Bool, dt: Float) -> Bool {
        guard on, m.kind.hostile || m.kind.steelhold else { return seen }
        if m.aggro || m.lockTime > 0 || m.hurt > 0 { m.notice = seen ? 1 : m.notice; return seen }
        let pl = g.player
        // Loud: a shot or a blast of his nearby.
        if g.clock - loud.at < 1.5 && simd_length(loud.pos - m.pos) < 48 * max(0.5, loud.power) && dist < 64 {
            m.notice = 1; noticed += 1; return true
        }
        guard seen else { m.notice = max(0, m.notice - dt / 3); return false }
        if dist < (pl.sneaking ? 1.5 : 3) { m.notice = 1; noticed += 1; return true }
        var to = V3(pl.eye.x - m.pos.x, 0, pl.eye.z - m.pos.z)
        to = simd_length(to) > 1e-3 ? simd_normalize(to) : V3(0, 0, -1)
        let face: Float = simd_dot(m.forward, to)
        let byLight = seesByLight(m.kind)
        // (the creatures of the dark smell and hear him too: a third as quick behind them)
        let cone: Float = face > 0.5 ? 1 : (face > -0.1 ? (byLight ? 0.35 : 0.6) : (byLight ? 0 : 0.3))
        var light: Float = 0.85
        if byLight {
            let l = g.world.lightAt(Int(floor(pl.eye.x)), Int(floor(pl.eye.y)), Int(floor(pl.eye.z)))
            let eff = max(Float(l.sky) * g.daylight, Float(l.block)) / 15
            light = 0.2 + 0.8 * eff
        }
        let hv = simd_length(V2(pl.vel.x, pl.vel.z))
        let manner: Float = pl.sneaking ? 0.4 : (pl.sprinting ? 1.4 : (hv < 0.4 ? 0.7 : 1))
        let feet = g.world.builtBlock(Int(floor(pl.pos.x)), Int(floor(pl.pos.y + 0.2)), Int(floor(pl.pos.z)))
        let head = g.world.builtBlock(Int(floor(pl.eye.x)), Int(floor(pl.eye.y)), Int(floor(pl.eye.z)))
        let cover: Float = (feet != AIR && !Blocks.collide[Int(feet)] && !Blocks.isLiquid(feet)) || Blocks.key(Blocks.groupBase[Int(head)]).hasSuffix("_leaves") ? 0.5 : 1
        let reach: Float = 48 / max(dist, 4)
        let rate: Float = cone * light * manner * cover * reach * Difficulty.row.sight
        m.notice = min(1, m.notice + rate * dt)
        if m.notice > 0.35 && cone < 1 { m.face(pl.eye) }   // something's there: it turns to look
        if m.notice >= 1 { noticed += 1; return true }
        return false
    }
}
