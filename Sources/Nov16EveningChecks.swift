import Foundation
import simd

// Fable's share of the Nov 16 evening playtest (docs/playtests/2026-11-16/voice-notes.md, build 26ceac53): the checks
// for ledger rows 241 on (the vehicle park's, ledger 240, is its own run: questcheck --parkdrive; the locomotive cab's
// panel is quest/scenes/train-cab-hud.scene; the garage door's times are in GarageDoorCheck).
enum Nov16EveningChecks {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        pauseMenu(g, check)
        SoldierGunCheck.run(g, check)
        fogClock(g, check)
    }

    // Ledger 252 (Fable's review of the store stills, Nov 17: the minimap black in four of eight): MapFog's reveal and
    // save timers kept the last Game's clock, and a new Game's starts at 0 (a world switched to in the same session), so
    // nothing round him was revealed until the new clock passed the old one. BS_OLDFOGCLOCK=1: as before.
    static func fogClock(_ g: Game, _ check: (Bool, String) -> Void) {
        let fog = MapFog.shared
        let snap = fog.snapshot, surv0 = g.survival, clock0 = g.clock, pos0 = g.player.pos
        defer { fog.snapshot = snap; g.survival = surv0; g.clock = clock0; g.player.pos = pos0; fog.tick(g) }
        g.survival = true
        g.clock = 900; fog.tick(g)                                  // a quarter hour played: the timers at 900
        g.clock = 2; g.player.pos = pos0 + V3(6000, 0, 6000)         // another world opened: its clock starts again
        fog.tick(g)
        let x = Int(floor(g.player.pos.x)), z = Int(floor(g.player.pos.z))
        check(fog.seen(x, z) && fog.seen(x + 64, z - 64),
              "ledger 252: a new game's clock (2 s after 900 in the last): the minimap's fog round him lifted (\(fog.seen(x, z))), 64 off too (\(fog.seen(x + 64, z - 64)))")
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
