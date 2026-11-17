import Foundation

// P403 7b (Remington, Oct 23 08:55: "dynamic eye-buffer resolution: drops resolution only when a frame would miss,
// recovers when it can", with an on/off in Options): the share of each eye's swapchain image the world is drawn
// into (SceneRenderer.viewScale; the compositor scales the drawn rectangle up to the eye). The swapchain stays at its
// full size, so stepping costs nothing. Fed the GPU time of each drawn frame against its budget (13.9 ms at 72 Hz,
// 27.8 ms with Space Warp):
// - a smoothed GPU time over 95 % of the budget drops the scale: by 5 %, or straight to the scale its pixels say
//   fits (at most 15 % at once) when the frame is far over, so a 26 ms frame is back inside 72 Hz in about half a
//   second instead of two (to 60 % at the least);
// - a drop that didn't make the GPU faster (a frame bound by its triangles rather than its pixels) is taken back and
//   no further drop is tried for a while, so the picture is never softened for nothing. P498: one probe that says
//   pixels counts for the next 30 s (walking makes the GPU time swing more than a 5 % step saves, and a swing must
//   not undo a good drop); it takes two failed probes in a row to hold off for 10 s (one holds for 3 s);
// - with room again (the time the next step up would cost still under 85 % of the budget) it climbs back a step.
// Ledger 177 (his Nov 15 evening captures, all GPU-bound at 53 to 60 fps): "eye resolution 100% (10% fewer pixels gave
// -11% less gpu: triangle-bound)" with 32,555 quads on screen and a 14.6 ms GPU frame; "-67%" at 201,591 quads; "2%"
// at 46,930 quads and 85 %. A frame of 32,000 quads is not held up by its triangles: the probe's answer was the
// scene changing under it (he was moving; the GPU's clock also steps down when its load falls), and each wrong
// answer put the resolution back and held it there for 3 to 10 s while the frame missed. Two rules:
// - a probe during which the GPU time ROSE says nothing (fewer pixels cannot cost more): the cut stays and the next
//   drop is judged afresh;
// - a drop is only ever taken back when the frame draws `heavyQuads` or more (his heaviest forest view, 321,000
//   quads, measured mostly pixels with the overdraw tool; under that the triangles cannot be the bound).
// BS_OLDDYNRES=1 = the probe alone decides, as before.
struct DynamicResolution {
    static let oldProbe = Env.all["BS_OLDDYNRES"] == "1"
    static let heavyQuads = 250_000
    // (Store review, Nov 2, VRC.Quest.Performance.1: the frame must hold the display's rate. His Oct 30 captures were
    // pixel-bound at up to 26 ms, which 70 % of the eye (49 % of the pixels) brought only to the budget's edge; 60 %
    // gives the frame room. Only the heaviest views reach it, for as long as they are heavy.)
    static let minScale: Float = Env.all["BS_EYEMIN"].flatMap { Float($0) } ?? 0.6, step: Float = 0.05, maxStep: Float = 0.15
    private(set) var scale: Float = 1
    private(set) var drops = 0, takenBack = 0           // for the perf line
    private(set) var unjudged = 0                       // (ledger 177: probes that gave no answer)
    // The last probe's answer (P403 step 2, 'triangles or pixels'): the GPU time after a pixel cut over the time
    // before it, scaled to a 10 % cut; ~0.9 says the frame pays for pixels, ~1.0 says it pays for triangles. 0 until a
    // probe has run.
    private(set) var lastProbe = 0.0
    private var ema = 0.0, settle = 0, hold = 0, pixelsFor = 0, failed = 0
    private var before = 0.0, cut = 0.0, prev: Float = 1, judging = false

    mutating func observe(gpuMs: Double, budgetMs: Double, enabled: Bool, fps: Double = 72, quads: Int = .max) -> Float {
        guard enabled, budgetMs > 0 else { scale = 1; judging = false; return scale }
        ema = ema == 0 ? gpuMs : ema * 0.85 + gpuMs * 0.15
        if hold > 0 { hold -= 1 }
        if pixelsFor > 0 { pixelsFor -= 1 }
        if settle > 0 { settle -= 1; return scale }           // the GPU time lags the change by a few frames
        if judging {
            judging = false
            let gain = before > 0 ? 1 - ema / before : 0      // share of the GPU time the cut saved
            lastProbe = 1 - gain * 0.1 / max(cut, 0.01)
            let trusted = DynamicResolution.oldProbe || (quads >= DynamicResolution.heavyQuads && gain > -0.03)
            if !trusted && gain < cut * 0.25 {
                // (ledger 177: not a frame triangles can hold up, or the time rose: no answer, the cut stays)
                unjudged += 1
            } else if gain < cut * 0.25 {                     // under a quarter of what the pixels cut: not pixels
                scale = prev
                takenBack += 1
                failed += 1
                hold = Int((failed >= 2 ? 10 : 3) * fps)
                settle = 16
                return scale
            } else {
                failed = 0
                pixelsFor = Int(30 * fps)
            }
        }
        if ema > budgetMs * 0.95 && scale > DynamicResolution.minScale + 1e-3 && hold == 0 {
            // The scale whose pixels fit 88 % of the budget, were the whole frame pixels.
            let fit = scale * Float((budgetMs * 0.88 / ema).squareRoot())
            let drop = min(DynamicResolution.maxStep, max(DynamicResolution.step, scale - fit))
            let next = max(DynamicResolution.minScale, scale - drop)
            before = ema
            prev = scale
            cut = 1 - Double((next * next) / (scale * scale))
            scale = next
            drops += 1
            judging = pixelsFor == 0
            settle = 16
        } else if scale < 1 {
            let up = min(1, scale + DynamicResolution.step)
            if ema * Double((up * up) / (scale * scale)) < budgetMs * 0.85 {
                scale = up
                settle = 16
            }
        }
        return scale
    }
}
