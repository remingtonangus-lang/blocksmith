import Foundation
import simd

// H10 (Oct 13 evening): "horse bonding raises stamina and health, with RDR2-style cores in the UI".
// Objectives:
//  - Each bond level raises the horse's top health (30, 33, 36, 40) as well as its stamina (HorseFeel.staminaMax).
//  - Two cores sit under the bars, 0-100: a health core and a stamina core. They drain slowly with riding and time
//    (a full core lasts about 45 min of riding) and set how fast the outer bars refill: an empty core refills at a
//    quarter speed, and the health bar refills by itself only while its core holds.
//  - Food and care fill the cores: treats (by kind), hay most of all, brushing tops up both, a night at a stable fills
//    them. Feeding a horse at full health is never wasted any more: it goes into its cores.
//  - The HUD draws both cores as small filled squares beside the bond level, with the horse's health beside its stamina.
//  - Saved with the horse (MobSave "hc", "sc").
enum HorseCores {
    static let maxHealth: [Int] = [30, 33, 36, 40]
    static let drainRide: Float = 100 / 2700              // per s ridden: a full core lasts 45 min in the saddle
    static let drainIdle: Float = 100 / 14400             // per s left alone: 4 h
    static let gallopExtra: Float = 1.6                   // the stamina core goes faster at a gallop
    // Core points a treat gives: (health core, stamina core).
    static let food: [String: (Float, Float)] = [
        "sugar": (0, 10), "wheat": (8, 8), "apple": (12, 12), "carrot": (10, 14), "golden_carrot": (45, 45),
        "golden_apple": (80, 80), "enchanted_golden_apple": (100, 100), "hay_block": (40, 40)]
    static let brush: (Float, Float) = (15, 15)
    static func regenScale(_ core: Float) -> Float { 0.25 + 0.75 * simd_clamp(core / 100, 0, 1) }
}

extension Mob {
    // Top health of a tamed horse by bond level (others keep their kind's).
    var horseMaxHealth: Int { gaited && tamed ? HorseCores.maxHealth[bondLevel - 1] : max(spec.health, 30) }

    // Once a tick for a tamed, gaited horse (ridden: gaitStep; left alone: waitWhereLeft).
    func coreTick(_ dt: Float, ridden: Bool, galloping: Bool) {
        guard gaited, tamed else { return }
        let h = hs
        let d = ridden ? HorseCores.drainRide : HorseCores.drainIdle
        h.healthCore = max(0, h.healthCore - d * dt)
        h.staminaCore = max(0, h.staminaCore - d * dt * (galloping ? HorseCores.gallopExtra : 1))
        // Health refills by itself while its core holds: a heart (2) every 6 s full, every 24 s near empty.
        if health > 0 && health < horseMaxHealth && h.healthCore > 1 {
            h.healAccum += dt * HorseCores.regenScale(h.healthCore) / 3
            if h.healAccum >= 1 { h.healAccum -= 1; health = min(horseMaxHealth, health + 1) }
        }
    }

    // Fill the cores (food, brush, stable). True when anything changed.
    @discardableResult
    func feedCores(_ hp: Float, _ st: Float) -> Bool {
        let h = hs
        guard h.healthCore < 99.5 || h.staminaCore < 99.5 else { return false }
        h.healthCore = min(100, h.healthCore + hp)
        h.staminaCore = min(100, h.staminaCore + st)
        return true
    }
}
