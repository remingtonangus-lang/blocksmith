import Foundation
import simd

// D3: hitching posts in towns.
// Objectives:
//  - Use a fence post while riding your horse (or with it standing within 12 blocks and an empty hand) and you
//    hitch it there: you step down, the rein is tied to the post (drawn like a lead, but no lead is spent or dropped)
//    and it stands at the rail, short-tethered, never wandering off or bolting.
//  - A hitched horse rests: both cores refill (H10), faster with water within 3 blocks (a trough), and its stamina
//    comes back full. Use the post again with an empty hand, or call your horse, to untie it.
//  - Towns have hitching rails with troughs in front of the saloon, store, stable and jail (town generation); any
//    fence post anywhere works the same way.
extension Game {
    func hitchAt(_ p: IVec3) -> Bool {
        let anchor = V3(Float(p.x) + 0.5, Float(p.y), Float(p.z) + 0.5)
        // Untie: a hitched horse of yours at this post, empty hand, not riding.
        if riding == nil && held.isEmpty,
           let h = mobs.mobs.first(where: { $0.hitched && $0.knot == p && $0.yours }) {
            unhitch(h)
            onToast?("You untie \(h.customName ?? "your horse")")
            return true
        }
        var horse: Mob?
        if let r = riding, r.gaited, r.tamed, simd_length(r.pos - anchor) < 5 { horse = r }
        else if riding == nil && held.isEmpty {
            horse = mobs.mobs.first { $0.bond == horseBond && horseBond != 0 && $0.health > 0 && $0.downed <= 0 && simd_length($0.pos - anchor) < 12 }
        }
        guard let h = horse, !h.hitched else { return false }
        if riding === h { dismount() }
        h.leashed = true; h.knot = p; h.hitched = true
        h.stayAt = anchor
        h.vel = .zero
        sfx(.place(.wood), 0.6, at: anchor)
        onToast?("\(h.customName ?? "Your horse") is hitched")
        Hitching.hitches += 1
        return true
    }

    func unhitch(_ h: Mob) {
        h.hitched = false; h.leashed = false; h.knot = nil
    }
}

extension Mob {
    // Once a tick while hitched (from leashTick): short tether, rest and water.
    func hitchedTick(_ dt: Float, _ g: Game) {
        guard let k = knot else { hitched = false; return }
        let anchor = V3(Float(k.x) + 0.5, Float(k.y), Float(k.z) + 0.5)
        let d = anchor - pos
        let len = simd_length(V2(d.x, d.z))
        if len > 2.5 {
            let pull = d * ((len - 2.5) / max(len, 0.01))
            vel.x += pull.x * dt * 8; vel.z += pull.z * dt * 8
        }
        if len > 12 { pos = anchor + V3(1, 0, 0) }                      // (pushed far off: back at the rail)
        panic = 0
        guard gaited, tamed else { return }
        Hitching.waterCheck -= dt
        if Hitching.waterCheck <= 0 {
            Hitching.waterCheck = 2
            hitchWater = Hitching.waterNear(g, k)
        }
        let rate: Float = hitchWater ? 1.2 : 0.4                         // core points a second
        feedCores(rate * dt, rate * dt)
        stamina += 6 * dt
    }
}

enum Hitching {
    static var hitches = 0
    static var waterCheck: Float = 0
    static func waterNear(_ g: Game, _ k: IVec3) -> Bool {
        for dy in -1...1 { for dz in -3...3 { for dx in -3...3 {
            let b = g.world.block(k.x + dx, k.y + dy, k.z + dz)
            if b == WATER || Blocks.key(b).hasPrefix("water_cauldron") { return true }
        } } }
        return false
    }
}
