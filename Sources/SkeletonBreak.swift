import Foundation
import simd

// P247 (Oct 13 22:00: "skeletons fall apart where the sword hits them"): a blade blow on a skeleton breaks off the bone
// it struck. The contact point (the Quest blade's, or where the aim met the body) is taken into the model's frame: an
// arm comes off at the shoulder (with no arms it can't draw its bow and comes in clawing), a leg at the hip (it hobbles;
// with both gone it drags itself), a hard blow to the skull knocks the head off and ends it, and a blow to the ribs
// chips bone off. Every break throws real pieces (DebrisField.bits, bone material) and may leave a bone to pick up.
extension Game {
    static let breaksBones: Set<MobKind> = [.skeleton, .stray, .parched]
    static let boneBlock: BlockID = Blocks.has("bone_block") ? Blocks.id("bone_block") : STONE

    func skeletonBlow(_ m: Mob, at hit: V3?, power: Float, blade: Bool) {
        guard Game.breaksBones.contains(m.kind), blade || power >= 1 else { return }
        let at = hit ?? m.pos + V3(0, m.height * 0.6, 0)
        let d = at - m.pos
        let right = V3(cosf(m.yaw), 0, -sinf(m.yaw))
        let px: Float = 16 / max(0.1, m.scale)
        let lx = simd_dot(d, right) * px, ly = d.y * px
        let crawl: Float = m.lostBones & 12 == 12 ? 11 : 0               // (a legless one lies lower)
        let y = ly + crawl
        let seed = hash3(Int(at.x * 64), Int(at.y * 64), Int(at.z * 64), UInt32(truncatingIfNeeded: Int(clock * 60)))
        let dir = simd_length(at - player.eye) > 1e-3 ? simd_normalize(at - player.eye) : player.look
        func world(_ x: Float, _ yy: Float) -> V3 { m.pos + right * (x / px) + V3(0, (yy - crawl) / px, 0) }
        if y >= 24.5 {
            guard power >= 0.9 || m.health * 2 <= m.spec.health else { chip(at, dir, seed); return }
            fling(world(0, 28.5), size: SIMD3(0.42, 0.36, 0.42), dir, seed, pieces: 4)
            m.health = 0                                                    // the skull is off: it falls in a heap
            for (bx, by) in [(-2, 16), (2, 6), (-2, 6)] as [(Float, Float)] { fling(world(bx, by), size: SIMD3(0.12, 0.3, 0.12), dir * 0.3, seed &+ UInt32(by), pieces: 2) }
            sfx(.attackCrit, 1.2, at: at)
            return
        }
        let bit: UInt8
        if y >= 12.5 && abs(lx) >= 3.4 { bit = lx < 0 ? 1 : 2 }
        else if y < 12 { bit = lx < 0 ? 4 : 8 }
        else { chip(at, dir, seed); return }
        guard m.lostBones & bit == 0, power >= 0.55 else { chip(at, dir, seed); return }
        m.lostBones |= bit
        let arm = bit <= 2
        let side: Float = bit == 1 || bit == 4 ? -1 : 1
        fling(arm ? world(side * 5, 16) : world(side * 2, 6), size: arm ? SIMD3(0.14, 0.42, 0.14) : SIMD3(0.14, 0.5, 0.14), dir, seed, pieces: 3)
        if Items.has("bone") && Rand.int(in: 0..<2) == 0 { drops.spawn(ItemStack(Items.id("bone"), 1), at: at) }
        if arm { m.aimHold = 0 }                                          // the bow drops with the arm
        sfx(.attackCrit, 0.9, at: at)
    }

    private func fling(_ c: V3, size: SIMD3<Float>, _ dir: V3, _ seed: UInt32, pieces: Int) {
        let bone = Game.boneBlock
        debris.bits(bone, at: c, size: size, direction: dir, count: pieces, speed: 2.5, seed: seed)
        particles.dust(bone, at: c, count: 4, spread: 0.15)
        sfx(.hit(soundMat(bone)), 1.1, at: c)
    }

    private func chip(_ at: V3, _ dir: V3, _ seed: UInt32) {
        let bone = Game.boneBlock
        debris.bits(bone, at: at, size: SIMD3(0.1, 0.1, 0.1), direction: dir, count: 2, speed: 1.8, seed: seed)
        particles.dust(bone, at: at, count: 3, spread: 0.1)
    }
}
