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
    static var splitFullW: Float = 0

    // TV overscan margins (Settings.safeArea percent of each edge), in pixels.
    let insetX: Float
    let insetY: Float

    init(_ W: Float, _ H: Float) {
        self.W = W
        self.H = H
        let safe = Float(max(0, min(10, Settings.shared.safeArea))) / 100
        insetX = floor((HudLayout.splitFullW > 0 ? HudLayout.splitFullW : W) * safe)
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
        insetX = floor((HudLayout.splitFullW > 0 ? HudLayout.splitFullW : W) * safe)
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

    var safeRect: HudRect {
        HudRect(x: insetX, y: insetY, w: max(0, W - 2 * insetX), h: max(0, H - 2 * insetY))
    }

    var hotbarRect: HudRect {
        HudRect(x: hotbarX0, y: hotbarY0, w: slot * Float(HudLayout.cols), h: slot)
    }

    // Bottom-center HUD region: hotbar + hearts/hunger/XP/held-label (or driving panel + status bars).
    func bottomHudRect(driveTop: Float? = nil) -> HudRect {
        let pad = 4 * s
        let x0 = max(insetX, hotbarX0 - pad)
        let x1 = min(W - insetX, hotbarX0 + slot * Float(HudLayout.cols) + pad)
        let top = driveTop.map { $0 - 26 * s } ?? (hotbarY0 - 42 * s)
        let y0 = max(insetY, top)
        let y1 = H - insetY
        return HudRect(x: x0, y: y0, w: max(0, x1 - x0), h: max(0, y1 - y0))
    }

    var crosshairRect: HudRect {
        HudRect(x: floor(W / 2) - 14 * s, y: floor(H / 2) - 14 * s, w: 28 * s, h: 28 * s)
    }

    func menuRect(_ m: Menu) -> HudRect {
        let ml = fitted(m)
        let mw = Float(m.width) * ml.s, mh = Float(m.height) * ml.s
        let pad = 4 * ml.s
        return HudRect(x: floor((W - mw) / 2) - pad, y: floor((H - mh) / 2) - 16 * ml.s, w: mw + pad * 2, h: mh + 24 * ml.s)
    }
}

// Axis-aligned rectangle in HUD pixel space (origin top-left), shared for non-overlapping HUD placement.
struct HudRect {
    var x: Float
    var y: Float
    var w: Float
    var h: Float

    var maxX: Float { x + w }
    var maxY: Float { y + h }
    var midX: Float { x + w * 0.5 }
    var midY: Float { y + h * 0.5 }
    var isEmpty: Bool { w <= 0 || h <= 0 }

    func expanded(by pad: Float) -> HudRect {
        HudRect(x: x - pad, y: y - pad, w: w + pad * 2, h: h + pad * 2)
    }

    func intersects(_ other: HudRect) -> Bool {
        !isEmpty && !other.isEmpty && x < other.maxX && maxX > other.x && y < other.maxY && maxY > other.y
    }

    func contains(_ other: HudRect, tolerance: Float = 0) -> Bool {
        other.x >= x - tolerance && other.y >= y - tolerance && other.maxX <= maxX + tolerance && other.maxY <= maxY + tolerance
    }

    func union(_ other: HudRect) -> HudRect {
        if isEmpty { return other }
        if other.isEmpty { return self }
        let x0 = min(x, other.x), y0 = min(y, other.y)
        let x1 = max(maxX, other.maxX), y1 = max(maxY, other.maxY)
        return HudRect(x: x0, y: y0, w: x1 - x0, h: y1 - y0)
    }
}
