import Foundation

// P403 7b (Remington, Oct 23 08:55: "dynamic eye-buffer resolution: drops resolution only when a frame would miss,
// recovers when it can", with an on/off in Options): the share of each eye's swapchain image the world is drawn
// into (SceneRenderer.viewScale; the compositor scales the drawn rectangle up to the eye). The swapchain stays at its
// full size, so stepping costs nothing. Fed the GPU time of each drawn frame against its budget (13.9 ms at 72 Hz,
// 27.8 ms with Space Warp):
// - a smoothed GPU time over 95 % of the budget drops the scale: by 5 %, or straight to the scale its pixels say
//   fits (at most 15 % at once) when the frame is far over, so a 26 ms frame is back inside 72 Hz in about half a
//   second instead of two (to 70 % at the least);
// - a drop that didn't make the GPU faster (a frame bound by its triangles rather than its pixels) is taken back and
//   no further drop is tried for a while, so the picture is never softened for nothing. P498: one probe that says
//   pixels counts for the next 30 s (walking makes the GPU time swing more than a 5 % step saves, and a swing must
//   not undo a good drop); it takes two failed probes in a row to hold off for 10 s (one holds for 3 s);
// - with room again (the time the next step up would cost still under 85 % of the budget) it climbs back a step.
struct DynamicResolution {
    static let minScale: Float = 0.7, step: Float = 0.05, maxStep: Float = 0.15
    private(set) var scale: Float = 1
    private(set) var drops = 0, takenBack = 0           // for the perf line
    // The last probe's answer (P403 step 2, 'triangles or pixels'): the GPU time after a pixel cut over the time
    // before it, scaled to a 10 % cut; ~0.9 says the frame pays for pixels, ~1.0 says it pays for triangles. 0 until a
    // probe has run.
    private(set) var lastProbe = 0.0
    private var ema = 0.0, settle = 0, hold = 0, pixelsFor = 0, failed = 0
    private var before = 0.0, cut = 0.0, prev: Float = 1, judging = false

    mutating func observe(gpuMs: Double, budgetMs: Double, enabled: Bool, fps: Double = 72) -> Float {
        guard enabled, budgetMs > 0 else { scale = 1; judging = false; return scale }
        ema = ema == 0 ? gpuMs : ema * 0.85 + gpuMs * 0.15
        if hold > 0 { hold -= 1 }
        if pixelsFor > 0 { pixelsFor -= 1 }
        if settle > 0 { settle -= 1; return scale }           // the GPU time lags the change by a few frames
        if judging {
            judging = false
            let gain = before > 0 ? 1 - ema / before : 0      // share of the GPU time the cut saved
            lastProbe = 1 - gain * 0.1 / max(cut, 0.01)
            if gain < cut * 0.25 {                            // under a quarter of what the pixels cut: not pixels
                scale = prev
                takenBack += 1
                failed += 1
                hold = Int((failed >= 2 ? 10 : 3) * fps)
                settle = 16
                return scale
            }
            failed = 0
            pixelsFor = Int(30 * fps)
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
