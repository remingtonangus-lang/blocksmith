import Foundation
import simd

// On the Quest `Renderer` is the HUD host: the Mac Renderer's HUD/menu builder (buildHUD and helpers, extracted
// from Sources/Renderer.swift at build time into HudGenerated.swift) runs as an extension of this class and its
// pixel-space quads are drawn into the world-space panel. Gadgets.swift's scope overlay extends it too.
final class Renderer {
    let game: Game
    init(game: Game) { self.game = game }
}
