import Foundation
import simd

// P342 (b) (Oct 16 19:45-19:48: "replace the glowstone ceiling look with a sky of its own, the way the world below has
// one"): hell's own sky, drawn the way the Ash Vault's is (AshSky.swift). While the eye is down in the hell band (the
// Emberdeep, or the Deep's hell band) the renderers leave out every terrain section from the band's upper reaches up,
// so overhead is open sky instead of a rock roof hung with amber crystals: a smouldering red-brown murk (the land's own
// haze at the horizon, HellAtmosphere's colour), darkening to a near-black ember glow overhead, and a huge dull Ember Moon
// low in it. The lumenstone spikes that hung from the roof are gone (HellLands.swift). Climb above the cut and the real
// roof is drawn again.
enum HellSky {
    // Sections from here up are sky while the eye is below `eyeBelow` (the Deep's band: y 320; the Emberdeep: y 160).
    static func cutSection(_ d: Dim) -> Int { d == .deep ? 20 : 10 }
    static func eyeBelow(_ d: Dim) -> Float { d == .deep ? 306 : 148 }
    static let sunDir = simd_normalize(V3(-0.5, 0.3, 0.62))
    static let sunTint = V4(1.0, 0.34, 0.12, 1)
    static let sunSize: Float = 20
    static let glow: Float = 0.4                                // the sky shader's halo round the Ember Moon
    // Overhead: the horizon's haze darkened to a smoky ember black.
    static func zenith(_ haze: V3) -> V3 { haze * 0.35 + V3(0.03, 0.006, 0.004) }
}

extension Game {
    // The camera is down in a hell band, under hell's sky.
    var inHellSky: Bool {
        switch dim.dim {
        case .nether: return player.pos.y < HellSky.eyeBelow(.nether)
        case .deep: return DeepGen.inHell(player.pos.y) && player.pos.y < HellSky.eyeBelow(.deep)
        default: return false
        }
    }
    // Sections from here up are left to an own sky (the Ash Vault's or hell's); NSEC: none.
    var skyCutSection: Int { inVaultSky ? AshSky.cutSection : (inHellSky ? HellSky.cutSection(dim.dim) : NSEC) }
    // The body hung in an own sky: the vault's Cinder Sun or hell's Ember Moon (direction, tint, half size).
    var ownSkyBody: (dir: V3, tint: V4, size: Float)? {
        if inVaultSky { return (AshSky.sunDir, AshSky.sunTint, 12) }
        if inHellSky { return (HellSky.sunDir, HellSky.sunTint, HellSky.sunSize) }
        return nil
    }
}
