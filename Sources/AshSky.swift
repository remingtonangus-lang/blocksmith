import Foundation
import simd

// The Ash Vault's own sky (the Deep expansion, docs/status/the-deep-expansion.md). While the eye is down in the vault,
// the renderers leave out every terrain section from y 144 up (the roof, 154-182, and the tops of the pillars), so
// overhead is open sky: a smoky ember haze, darker toward the zenith, with the Cinder Sun (a dull molten disc and its
// glow) hanging in it. The haze is also the fog, so the floor and the pillars fade into it, and the vault gets more
// ambient light than the hell band or the crusts. Climb (or fly) above y 128 and the real roof is drawn again.
enum AshSky {
    static let cutSection = 9                                   // sections from here up (y >= 144) are sky
    static let eyeBelow: Float = 128
    // P323 (b, Oct 15 18:50: "less murky sky-ness"; it read as hell's own red murk): a paler ash haze, the ember glow
    // kept low in it, and the fog starting further out.
    static let haze = V3(0.40, 0.25, 0.18)
    static let zenith = V3(0.17, 0.10, 0.08)
    static let sunDir = simd_normalize(V3(0.32, 0.86, -0.4))
    static let sunTint = V4(1.0, 0.46, 0.24, 1)
    static let glow: Float = 0.55                               // the sky shader's warm halo around the sun
    static let ambient: Float = 0.56                            // the Deep's own is 0.42
    static let fogStart: Float = 32
    static let fogEnd: Float = 130
}

extension Game {
    // The camera is down in the Ash Vault, under its sky.
    var inVaultSky: Bool { dim.dim == .deep && player.pos.y < AshSky.eyeBelow && player.pos.y > Float(DeepGen.coreTop) }
    // P323 (b): anywhere in the vault's open cavern, up to its roof (the sky itself only from y 128 down): its haze,
    // fog and light, not the hell band's. Dropping in through the roof (a shaft through the seal) used to show the hell
    // band's dark red murk over a floor 135 blocks down: "a void", "a Nether under the Nether".
    var inVaultHaze: Bool {
        guard dim.dim == .deep, player.pos.y > Float(DeepGen.coreTop), player.pos.y < Float(DeepSeal.bottom) else { return false }
        if inVaultSky { return true }
        guard let dg = world.gen as? DeepGen else { return false }
        return Int(floor(player.eye.y)) < dg.ceilingY(Int(floor(player.pos.x)), Int(floor(player.pos.z)))
    }
    // Ambient light the renderers use (the dimension's own, brighter under the vault's sky).
    var dimAmbient: Float { inVaultHaze ? AshSky.ambient : dim.dim.ambient }
}
