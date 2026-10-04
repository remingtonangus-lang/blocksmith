import Foundation

// Pixel layout of the HUD (origin top-left, drawable pixels). Shared by the renderer (drawing)
// and Game (mouse hit-testing), so both always agree.
struct HudLayout {
    let W: Float
    let H: Float
    let s: Float      // integer HUD scale
    let slot: Float   // slot size in pixels
    static let cols = 9
    static var userScale: Int = UserDefaults.standard.integer(forKey: "guiScale") { didSet { UserDefaults.standard.set(userScale, forKey: "guiScale") } }
    static var couch: Bool = UserDefaults.standard.bool(forKey: "couchMode") { didSet { UserDefaults.standard.set(couch, forKey: "couchMode") } }
    // Split screen (Coop.swift): the whole frame's height, so each half-height view keeps the TV's full overscan margin.
    static var splitFullH: Float = 0

    // TV overscan margins (Settings.safeArea percent of each edge), in pixels.
    let insetX: Float
    let insetY: Float

    init(_ W: Float, _ H: Float) {
        self.W = W
        self.H = H
        let safe = Float(max(0, min(10, Settings.shared.safeArea))) / 100
        insetX = floor(W * safe)
        insetY = floor((HudLayout.splitFullH > 0 ? HudLayout.splitFullH : H) * safe)
        // Auto scale fits the classic 400x300 layout; couch mode (TV) targets ~280x210 for big text.
        let uw = W - 2 * insetX, uh = H - 2 * insetY
        let auto = max(1, min(floor(uw / (HudLayout.couch ? 280 : 400)), floor(uh / (HudLayout.couch ? 210 : 300))))
        let maxFit = max(1, min(floor(W / 240), floor(H / 180)))
        s = HudLayout.userScale > 0 ? min(Float(HudLayout.userScale), maxFit) : auto
        slot = 20 * s
    }

    // Same screen at an explicit scale.
    init(_ W: Float, _ H: Float, scale: Float) {
        self.W = W
        self.H = H
        let safe = Float(max(0, min(10, Settings.shared.safeArea))) / 100
        insetX = floor(W * safe)
        insetY = floor((HudLayout.splitFullH > 0 ? HudLayout.splitFullH : H) * safe)
        s = max(1, scale)
        slot = 20 * s
    }

    // Largest scale (up to this one) at which a menu panel plus its title/legend fits inside the safe area.
    func fitted(_ m: Menu) -> HudLayout {
        let extraW: Float = (m as? HasRecipeBook)?.book.open == true ? 250 : 8
        let extraH: Float = m is PauseMenu && (m as? PauseMenu)?.page == .title ? 90 : 34
        let fw = floor((W - 2 * insetX) / (Float(m.width) + extraW))
        let fh = floor((H - 2 * insetY) / (Float(m.height) + extraH))
        let fit = max(1, min(s, fw, fh))
        return fit == s ? self : HudLayout(W, H, scale: fit)
    }

    var hotbarX0: Float { floor((W - slot * 9) / 2) }
    var hotbarY0: Float { H - slot - 4 * s - insetY }

    func hotbarSlot(_ i: Int) -> V2 { V2(hotbarX0 + Float(i) * slot, hotbarY0) }

    func hotbarIndex(at p: V2) -> Int? {
        let i = Int(floor((p.x - hotbarX0) / slot))
        guard i >= 0 && i < 9 && p.y >= hotbarY0 && p.y < hotbarY0 + slot else { return nil }
        return i
    }

    // Creative inventory grid, centred in the space above the hotbar.
    func gridRows(_ n: Int) -> Int { (n + HudLayout.cols - 1) / HudLayout.cols }

    func gridOrigin(_ n: Int) -> V2 {
        let gw = slot * Float(HudLayout.cols), gh = slot * Float(gridRows(n))
        let y = max(12 * s, floor((hotbarY0 - 10 * s - gh) / 2))
        return V2(floor((W - gw) / 2), y)
    }

    func gridSlot(_ i: Int, _ n: Int) -> V2 {
        let o = gridOrigin(n)
        return o + V2(Float(i % HudLayout.cols) * slot, Float(i / HudLayout.cols) * slot)
    }

    func gridIndex(at p: V2, _ n: Int) -> Int? {
        let o = gridOrigin(n)
        let c = Int(floor((p.x - o.x) / slot)), r = Int(floor((p.y - o.y) / slot))
        guard c >= 0 && c < HudLayout.cols && r >= 0 else { return nil }
        let i = r * HudLayout.cols + c
        return i < n ? i : nil
    }
}
