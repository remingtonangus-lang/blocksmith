import Foundation
import simd

// Fable's share of the Nov 16 evening playtest (docs/playtests/2026-11-16/voice-notes.md, build 26ceac53): the checks
// for ledger rows 241 on (the vehicle park's, ledger 240, is its own run: questcheck --parkdrive; the locomotive cab's
// panel is quest/scenes/train-cab-hud.scene; the garage door's times are in GarageDoorCheck).
enum Nov16EveningChecks {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        pauseMenu(g, check)
        SoldierGunCheck.run(g, check)
    }

    // Ledger 242 (21:15:34-21:15:59): the pause page has no Track a Target or Statistics rows, and its buttons are 30
    // tall (were 22) on a page 500 wide (was 440). BS_OLDPAUSEMENU=1: as before.
    static func pauseMenu(_ g: Game, _ check: (Bool, String) -> Void) {
        if g.menu != nil { g.closeMenu() }
        let pm = PauseMenu(game: g)
        g.openMenu(pm)
        defer { g.closeMenu() }
        let ids = pm.rows.map { $0.1 }
        let st = pm.style
        check(!ids.contains("track") && !ids.contains("stats") && st.btnH >= 30 && st.width >= 500,
              "ledger 242: the pause page has no Track a Target or Statistics (rows: \(ids.joined(separator: ","))), its buttons \(Int(st.btnH)) tall on a page \(Int(st.width)) wide")
    }
}
