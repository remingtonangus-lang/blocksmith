import Foundation
import simd

// On the Quest `Renderer` is the HUD host: the Mac Renderer's HUD/menu builder (buildHUD and helpers, extracted from
// Sources/Renderer.swift at build time into HudGenerated.swift by quest/tools/extract_hud.py) runs on a subclass of
// this base, and its pixel-space quads are drawn into the world-space panel. Gadgets.swift's scope overlay extends
// it too. The stats the F3 overlay shows are filled in by the Vulkan renderer.
class HudRendererBase {
    let game: Game
    var fps: Double = 0
    var drawnChunks = 0
    var drawCalls = 0
    var drawnQuads = 0
    var visibleSections = 0
    var gpuFrameMs: Double = 0
    static var questHideCrosshair = false       // the laser replaces it (extract_hud.py patches the crosshair)
    init(game: Game) { self.game = game }
}

extension Int {
    var mod4: Int { ((self % 4) + 4) % 4 }     // App.swift on the Mac
}
