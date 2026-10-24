import Foundation

// Text size in the headset (Q2, scorecard "Accessibility: subtitle size in VR not measured"; `questcheck
// --vrtext-only`, and part of every questcheck run): the angle a capital letter (the pixel font's 7 rows) spans at the
// default HUD scale on the HUD panel (subtitles, toasts, goals) and at each main menu's fitted scale on the menu panel,
// from the panels' size and distance (QuestControls). Floors: 1.0 degree for the HUD's lines read at a glance, 0.7
// for menus read on purpose (about where low-resolution headset text stops being legible).
enum VRTextCheck {
    static func degrees(px: Float, panelWidthM: Float, distM: Float) -> Float {
        let m = px * panelWidthM / Float(QuestControls.panelW)
        return 2 * atanf(m / 2 / distM) * 180 / .pi
    }
    static func run(game g: Game, check: (Bool, String) -> Void) {
        let couch0 = HudLayout.couch, scale0 = HudLayout.userScale, menu0 = g.menu, surv0 = g.survival
        defer { HudLayout.couch = couch0; HudLayout.userScale = scale0; if g.menu != nil { g.closeMenu() }; g.menu = menu0; g.survival = surv0 }
        // The headset's defaults: couch mode on (QuestSettings.platformDefaults), GUI scale auto.
        HudLayout.couch = true; HudLayout.userScale = 0
        let W = Float(QuestControls.panelW), H = Float(QuestControls.panelH)
        let L = HudLayout(W, H)
        let hud = degrees(px: 7 * L.s, panelWidthM: QuestControls.hudWidthM, distM: QuestControls.hudDistM)
        var rows: [String] = [String(format: "HUD %.2f deg (scale %.0f)", hud, L.s)]
        var low: [String] = []
        if hud < 1.0 { low.append(rows[0]) }
        if g.menu != nil { g.closeMenu() }
        let menus: [(String, () -> Void)] = [
            ("inventory", { g.survival = true; g.openInventory() }),
            ("creative", { g.survival = false; g.openInventory() }),
            ("pause", { g.openMenu(PauseMenu(game: g)) }),
            ("title", { let pm = PauseMenu(game: g); pm.page = .title; pm.build(); g.openMenu(pm) }),     // (P410)
        ]
        for (name, open) in menus {
            open()
            guard let m = g.menu else { low.append("\(name): didn't open"); continue }
            let F = L.fitted(m)
            let d = degrees(px: 7 * F.s, panelWidthM: QuestControls.menuWidthM, distM: QuestControls.menuDistM)
            let r = name + String(format: " %.2f deg (scale %.0f)", d, F.s)
            rows.append(r)
            if d < 0.7 { low.append(r) }
            g.closeMenu()
        }
        print("vr text: capital letter height " + rows.joined(separator: ", "))
        check(low.isEmpty, "vr text: HUD text spans at least 1.0 degree and menu text 0.7 at the headset's defaults (\(rows.joined(separator: ", ")))" + (low.isEmpty ? "" : "; too small: " + low.joined(separator: ", ")))
    }
}
