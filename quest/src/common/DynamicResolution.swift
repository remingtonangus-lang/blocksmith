import Foundation

// P403 7b (Remington, Oct 23 08:55: "dynamic eye-buffer resolution: drops resolution only when a frame would miss,
// recovers when it can", with an on/off in Options): the share of each eye's swapchain image the world is drawn
// into (SceneRenderer.viewScale; the compositor scales the drawn rectangle up to the eye). The swapchain stays at its
// full size, so stepping costs nothing. Fed the GPU time of each drawn frame against its budget (13.9 ms at 72 Hz,
// 27.8 ms with Space Warp):
// - a smoothed GPU time over 95 % of the budget drops the scale one step (5 %, to 70 % at the least);
// - a drop that didn't make the GPU faster (a frame bound by its triangles rather than its pixels) is taken back and
//   no further drop is tried for 10 s, so the picture is never softened for nothing;
// - with room again (the time the next step up would cost still under 85 % of the budget) it climbs back a step.
struct DynamicResolution {
    static let minScale: Float = 0.7, step: Float = 0.05
    private(set) var scale: Float = 1
    private(set) var drops = 0, takenBack = 0           // for the perf line
    // The last probe's answer (P403 step 2, 'triangles or pixels'): the GPU time after a 10 % pixel cut over the time
    // before it; ~0.9 says the frame pays for pixels, ~1.0 says it pays for triangles. 0 until a probe has run.
    private(set) var lastProbe = 0.0
    private var ema = 0.0, settle = 0, hold = 0
    private var before = 0.0, judging = false

    mutating func observe(gpuMs: Double, budgetMs: Double, enabled: Bool, fps: Double = 72) -> Float {
        guard enabled, budgetMs > 0 else { scale = 1; judging = false; return scale }
        ema = ema == 0 ? gpuMs : ema * 0.85 + gpuMs * 0.15
        if hold > 0 { hold -= 1 }
        if settle > 0 { settle -= 1; return scale }           // the GPU time lags the change by a few frames
        if judging {
            judging = false
            lastProbe = before > 0 ? ema / before : 0
            if ema > before * 0.975 {                         // under 2.5 % faster for ~10 % fewer pixels: not pixels
                scale = min(1, scale + DynamicResolution.step)
                takenBack += 1
                hold = Int(10 * fps)
                settle = 16
                return scale
            }
        }
        if ema > budgetMs * 0.95 && scale > DynamicResolution.minScale + 1e-3 && hold == 0 {
            before = ema
            scale = max(DynamicResolution.minScale, scale - DynamicResolution.step)
            drops += 1
            judging = true
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
