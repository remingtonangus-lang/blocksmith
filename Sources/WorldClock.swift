import Foundation
import simd

// Process-wide Game.clock timers and cross-world caches reset when switching worlds or reloading the same world.
// Every new Game starts its `clock` at 0.0; without a reset, static/singleton timers left at the previous world's
// clock freeze subsystems (TownLaw, MapCache, Waymarks, TroopLines, Townsfolk, RecordedAudio, VehicleAudio, Hunting,
// raids, subs, weather/war events) or keep short windows permanently active (VRReload.insertedAt blocking left-grip
// hotbar stepping, MarketCalls looping continuously, RecordedNov15.coaxLast blaring tank MG, SaveBadge sticking
// "Save failed", Wallet/Honour showing stale deltas, Disguise staying blown, Director suppressing events, CampSmoke
// and LandmarkRender drawing the old world's towns/citadels/spires/campfires).
// Bloom of ledger 252 (MapFog). BS_OLDWORLDCLOCK=1 restores the old behaviour for before/after checks.
enum WorldClock {
    static let old = Env.all["BS_OLDWORLDCLOCK"] == "1"
    private static var activeGame: ObjectIdentifier?
    private static var activeClock: Double = 0

    // Called at the end of Game.init so every fresh Game starts with clean session timers before any tick or test setup.
    static func begin(_ g: Game) {
        guard !old else { return }
        activeGame = ObjectIdentifier(g)
        activeClock = g.clock
        resetAll()
    }

    // Called at tick / HUD / render / subsystem entry points so switching between existing Game instances or rewinding
    // Game.clock heals immediately (two comparisons on the hot path).
    @inline(__always) static func sync(_ g: Game) {
        guard !old else { return }
        let id = ObjectIdentifier(g)
        if activeGame != id || g.clock + 0.001 < activeClock {
            activeGame = id
            resetAll()
        }
        activeClock = g.clock
    }

    static func resetAll() {
        TownLaw.resetSessionTimers()
        Townsfolk.townLastLine = -100
        TroopVoice.lastLine = -100
        TroopVoice.lastIdle = -100
        MapCache.shared.resetTimers()
        MapInput.viewDown = -1
        MapInput.opened = false
        Waymarks.cache = (-1e9, nil)
        Waymarks.marksAt = -1e9
        Waymarks.arrivedAt = nil
        WaymarkEase.rel = nil; WaymarkEase.y = nil; WaymarkEase.clock = 0
        VRReload.takenAt = 0
        VRReload.insertedAt = -100
        MarketCalls.reset()
        RecordedNov15.resetSession()
        VehicleAudio.hornAt = [:]
        VehicleAudio.flybyAt = [:]
        VehicleAudio.sirenAt = -100
        Wallet.resetSession()
        Honour.changedAt = -100
        Honour.delta = 0
        Honour.lastToast = -100
        Honour.lastWhy = ""
        Honour.outlawSpotted = nil
        SaveBadge.savedAt = -100
        SaveBadge.failedAt = -100
        SaveBadge.storageFullAt = -100
        NowPlaying.at = -100
        HeldReadout.cache = ("", IVec3(0, 0, 0), -9, nil)
        ClockFace.cache = (-1, "")
        ContextPrompts.resetClock()
        Disguise.blownAt = [:]
        Director.lastSecond = -1
        Director.arrivedAt = -1
        Director.diedAt = -1000
        DirectorPlanner.shared.reset()
        BountyHunters.lastPosse = -1e9
        EnemySub.nextCheck = 0
        EnemySub.nextSpawn = 90
        FactionRaids.next = 0
        FactionRaids.lastAssault = -1e9
        FactionRep.nextHunters = 0
        FrontBattle.next = 90
        WarFront.nextGun = 0
        Seasons.nextShow = 0
        Trophies.lastScan = -100
        Goals.lastCheck = -100
        Goals.shownAt = -100
        AirDefence.lastToast = -100
        BaseSecurity.lastSpot = -100
        AircraftCrash.cooldown = [:]
        BlockWear.tankBlasts = [:]
        BlockWear.marks = [:]
        BlockWear.frameAt = -1
        BlockWear.brokeThisFrame = 0
        NavalBurst.lastAt = -10
        Parachute.openedAt = -100
        Prisoners.freedAt = 0
        Submarine.lastShot = -100
        Submarine.lastPing = [:]
        Trains.roofAt = -1e9
        TrainArrivals.shellAt = [:]
        Tracking.windToldAt = -1e9
        GunActions.dryAt = -10
        Holsters.enteredAt = -100
        Holsters.lastZone = .none
        Narrator.shared.resetClock()
        Feedback.heartTimer = 0
        Feedback.heartClock = 0
        Feedback.lastClock = 0
        CraftBook.flashAt = -10
        FarTicks.resetClock()
        Deeds.lastClock = 0
        Witnesses.lastClock = 0
        PadActions.yDownAt = -1
        PadActions.dropPressedAt = -1
        Renderer.campAt = -10
        Renderer.campList = []
        Renderer.townAt = -10
        Renderer.townList = []
        Renderer.townBoxes = []
        Renderer.citadelAt = -10
        Renderer.citadelList = []
        Renderer.citadelSites = []
        Renderer.spireAt = -10
        Renderer.spireList = []
    }
}

#if os(macOS)
import Metal

// Headless proof (--worldclocktest): plays World A up to clock = 900 s so every process-wide timer and cross-world
// cache sits at 900 s (with stale World A data), then switches to World B (new seed) and also reloads World A (same
// seed, new Game) at clock = 2 s. With BS_OLDWORLDCLOCK=1 every check fails; without it all pass.
enum WorldClockTest {
    static func run(device: MTLDevice) -> Int32 {
        var fails = 0, passed = 0
        func check(_ ok: Bool, _ what: String) {
            if ok { passed += 1 } else { fails += 1 }
            print("worldclock: \(ok ? "PASS" : "FAIL") \(what)")
        }

        // World A: simulate a 15-minute session (clock = 900 s) touching every affected subsystem.
        let wA = World(seed: 12345, device: device, save: nil)
        let gA = Game(world: wA, save: nil, persistent: false)
        gA.clock = 900
        WorldClock.sync(gA)

        // Seed stale timers and cross-world caches at clock = 900.
        TownLaw.worldSeed = wA.seed
        TownLaw.lastTick = 900
        TownLaw.lastAmbient = 900
        Townsfolk.townLastLine = 900
        TroopVoice.lastLine = 900
        TroopVoice.lastIdle = 900
        MapCache.shared.tick(gA)                                     // sets scanTimer = 900
        Waymarks.marksAt = 900
        Waymarks.cache = (900, Waymarks.Target(kind: "note", key: "stale", name: "Old World Target", pos: V3(999, 70, 999)))
        VRReload.insertedAt = 900
        VRReload.takenAt = 900
        _ = MarketCalls.heard(900)                                   // sets until = 908.4, next ~ 1000
        RecordedNov15.coaxLast = 900
        RecordedNov15.coaxFrom = 899
        RecordedNov15.treesAt = 900
        RecordedNov15.radarAt = 900
        RecordedNov15.collapseAt = 900
        RecordedNov15.volcanoesAt = 900
        VehicleAudio.sirenAt = 900
        VehicleAudio.flybyAt[1] = 900
        VehicleAudio.hornAt[1] = 1000
        Wallet.shown = 50000
        Wallet.changedAt = 900
        Honour.changedAt = 900
        Honour.lastToast = 900
        SaveBadge.savedAt = 890
        SaveBadge.failedAt = 900
        Disguise.blownAt[0] = 900
        Director.diedAt = 900
        BountyHunters.lastPosse = 900
        EnemySub.nextCheck = 920
        EnemySub.nextSpawn = 1200
        FactionRaids.next = 1200
        FactionRaids.lastAssault = 900
        FactionRep.nextHunters = 1200
        FrontBattle.next = 1080
        WarFront.nextGun = 905
        Seasons.nextShow = 905
        Trophies.lastScan = 900
        Goals.lastCheck = 900
        Goals.shownAt = 900
        AirDefence.lastToast = 900
        BaseSecurity.lastSpot = 900
        NavalBurst.lastAt = 900
        Parachute.openedAt = 900
        Submarine.lastShot = 900
        Submarine.lastPing[1] = 900
        Trains.roofAt = 900
        Tracking.windToldAt = 900
        GunActions.dryAt = 900
        Holsters.enteredAt = 900
        FarTicks.roll(clock: 900)
        Renderer.campAt = 900; Renderer.campList = [V3(777, 70, 777)]
        Renderer.townAt = 900; Renderer.townList = [V4(777, 70, 777, 36)]
        Renderer.citadelAt = 900; Renderer.citadelList = [V3(777, 70, 777)]
        Renderer.spireAt = 900; Renderer.spireList = [V4(777, 70, 777, 80)]

        // Scenario 1: Reloading the SAME world (same seed 12345) at clock = 2.0 s.
        let wSame = World(seed: 12345, device: device, save: nil)
        let gSame = Game(world: wSame, save: nil, persistent: false)
        gSame.clock = 2.0
        TownLaw.tick(gSame)
        check(TownLaw.lastTick == 2.0, "same-seed reload: TownLaw ticks immediately (lastTick \(TownLaw.lastTick))")
        check(TownLaw.ambientOK(gSame), "same-seed reload: TownLaw.ambientOK is not frozen by old townLastLine")
        check(gSame.clock - TownLaw.lastAmbient > 30, "same-seed reload: TownLaw.lastAmbient reset (\(TownLaw.lastAmbient))")

        // Scenario 2: Switching to World B (different seed 99999) at clock = 2.0 s.
        let wB = World(seed: 99999, device: device, save: nil)
        let gB = Game(world: wB, save: nil, persistent: false)
        gB.clock = 2.0
        gB.survival = true
        gB.alive = true

        // 1. VRReload left grip on a full gun must NOT be blocked by World A's insertedAt (ledger 194 regression).
        let rifle = Items.id(Guns.all[0].key)
        var fullGun = ItemStack(rifle, 1)
        fullGun.tag = Guns.magSize(fullGun)
        gB.inventory.main[gB.selected] = fullGun
        let vrEv = VRReload.tick(gB, offHand: V3(0.4, 1.0, 0), gunHand: V3(0.2, 1.3, -0.4), head: V3(0, 1.6, 0), grip: true, gripWas: false)
        check(vrEv == .none, "VRReload: full gun left grip returns .none, not stuck .full (got \(vrEv))")

        // 2. MarketCalls must NOT stay stuck true for 900 s (ledger 330 regression).
        let mcStart = MarketCalls.heard(2.0)      // first pass at t=2 -> until=10.4
        let mcAfter = MarketCalls.heard(15.0)     // after pass ends -> must be false (resting)
        check(mcStart && !mcAfter, "MarketCalls: plays once then rests (at 2s \(mcStart), at 15s \(mcAfter))")

        // 3. RecordedNov15 tank coax MG loop must NOT blare in World B.
        let coaxActive = gB.clock - RecordedNov15.coaxLast < 0.2
        check(!coaxActive && gB.clock - RecordedNov15.treesAt > 1.2 && gB.clock - RecordedNov15.radarAt > 1.5,
              "RecordedNov15: coax not stuck (\(coaxActive)), trees/radar timers unfrozen")

        // 4. Waymarks must NOT return World A's stale target or freeze marksAt.
        let wm = Waymarks.current(gB)
        check(wm?.key != "stale" && gB.clock - Waymarks.marksAt >= 5,
              "Waymarks: stale target cleared (\(wm?.key ?? "nil")), marksAt unfrozen (\(Waymarks.marksAt))")

        // 5. TroopVoice & Townsfolk must NOT be muted.
        check(gB.clock - TroopVoice.lastLine >= 3.5 && gB.clock - TroopVoice.lastIdle > 22 && gB.clock - Townsfolk.townLastLine > 2,
              "Voices: TroopVoice and Townsfolk unfrozen")

        // 6. SaveBadge must NOT show stuck "Save failed" in World B.
        let hudOn = HudExtras.enabled
        HudExtras.enabled = true
        let L = HudLayout(1280, 800)
        let badge = SaveBadge.lines(gB, L, below: false)
        let wallet = Wallet.lines(gB, L)
        HudExtras.enabled = hudOn
        check(badge.isEmpty, "SaveBadge: no stale Save failed badge in new world (lines \(badge.count))")
        check(wallet.isEmpty, "Wallet: no stale balance delta in new world (lines \(wallet.count))")

        // 7. Disguise & Director must NOT carry blown disguise or recent-death suppression from World A.
        let disguising = Disguise.blownAt.isEmpty
        let dirDiedOk = gB.clock - Director.diedAt >= 60
        check(disguising && dirDiedOk, "Disguise/Director: blownAt empty (\(disguising)), diedAt cleared (\(dirDiedOk))")

        // 8. MapCache scanTimer must NOT be stuck at 900 s.
        MapCache.shared.tick(gB)
        check(MapCache.shared.scanTimerValue == gB.clock, "MapCache: scanTimer updated to 2.0 (got \(MapCache.shared.scanTimerValue))")

        // 9. World-event schedulers (EnemySub, FactionRaids, FactionRep, FrontBattle, WarFront, Seasons, BountyHunters, Trophies, Goals).
        check(gB.clock >= EnemySub.nextCheck && EnemySub.nextSpawn <= 90 && FactionRaids.next == 0 && FactionRep.nextHunters == 0
              && FrontBattle.next <= 90 && gB.clock >= WarFront.nextGun && gB.clock >= Seasons.nextShow
              && gB.clock - BountyHunters.lastPosse > 100 && gB.clock - Trophies.lastScan >= 5 && gB.clock - Goals.lastCheck >= 0.5,
              "Schedulers: subs, raids, hunters, fronts, seasons, trophies, goals unfrozen")

        // 10. Cross-world horizon/smoke caches (CampSmoke, LandmarkRender) must NOT keep World A's coordinates.
        check(Renderer.campList.isEmpty && Renderer.townList.isEmpty && Renderer.citadelList.isEmpty && Renderer.spireList.isEmpty
              && gB.clock - Renderer.campAt >= 2 && gB.clock - Renderer.citadelAt >= 2,
              "Horizon caches: camp/town/citadel/spire caches cleared")

        // 11. VehicleAudio, Submarine, NavalBurst, Parachute, FarTicks, AirDefence, BaseSecurity.
        FarTicks.counting = 3
        FarTicks.roll(clock: 2.0)
        check(VehicleAudio.hornAt.isEmpty && VehicleAudio.flybyAt.isEmpty && gB.clock - VehicleAudio.sirenAt > 9
              && gB.clock - Submarine.lastShot >= 4 && Submarine.lastPing.isEmpty
              && gB.clock - NavalBurst.lastAt >= 0.25 && gB.clock - Parachute.openedAt >= 0.5
              && FarTicks.lastSecond == 3
              && gB.clock - AirDefence.lastToast > 8 && gB.clock - BaseSecurity.lastSpot > 20,
              "Audio/combat/FarTicks: all unfrozen")

        // 12. VoiceEvents must NOT leak old-world events as "--898s ..." after switching worlds.
        let ve = VoiceEvents()
        gA.toastText = "Old World Toast"
        ve.observe(gA)
        ve.observe(gB)
        let recent = ve.recent(gB)
        check(!recent.contains(where: { $0.contains("--") || $0.contains("Old World Toast") }),
              "VoiceEvents: no negative-time old-world events after world switch (\(recent))")

        print("worldclocktest: \(passed) passed, \(fails) FAILED (BS_OLDWORLDCLOCK=\(WorldClock.old ? 1 : 0))")
        return fails == 0 ? 0 : 1
    }
}
#endif
