import Foundation
import simd

// Every sound is synthesized (noise bursts, filters, damped sines, formant voices) — no asset files.
// This file: the sound roster (Snd), volume categories, the lazily rendered SoundBank and the offline
// checks used by the `--sounds` harness. DSP lives in SoundSynth.swift / SoundMobs.swift, playback
// in SoundEngine.swift, music in Music.swift.

enum SoundMat: Int, CaseIterable {
    case stone, dirt, sand, wood, plant, glass, snow, gravel, metal, wool, slime, mud, bone, amethyst, soul, sculk, netherrack, deepslate
    var name: String { String(describing: self) }
}

enum MobSound: Int, CaseIterable {
    case ambient, hurt, death
    var name: String { String(describing: self) }
}

// Volume sliders. Every sound belongs to one category; master scales everything.
enum SoundCategory: Int, CaseIterable {
    case master, music, blocks, hostile, friendly, players, ambient, weather, ui
    var label: String {
        switch self {
        case .master: return "Master"
        case .music: return "Music"
        case .blocks: return "Blocks"
        case .hostile: return "Hostile Mobs"
        case .friendly: return "Friendly Mobs"
        case .players: return "Players"
        case .ambient: return "Ambient"
        case .weather: return "Weather"
        case .ui: return "Interface"
        }
    }
    var key: String { "audio_" + String(describing: self) }
}

enum Snd: Hashable {
    // Blocks by material: break, place, footstep, mining tick, landing thud.
    case breakBlock(SoundMat), place(SoundMat), step(SoundMat), hit(SoundMat), fall(SoundMat)
    // Player
    case splash, swim, land, hurt, hurtFall, hurtDrown, hurtFire, playerDeath, eat, burp, drink, pickup, dig
    case attack, attackSweep, attackCrit, attackKnockback, attackWeak, shieldBlock, shieldBreak, armorEquip(Int), itemBreak
    case bucketFill, bucketEmpty, bucketFillLava, bucketEmptyLava, fishCast, fishSplash, fishReel, xp, levelUp, totem, gasp
    case throwItem, pearlThrow, potionThrow, potionSplash, snowballHit, eggCrack, bowDraw, bow, arrowHit, crossbowLoad, crossbowShoot
    case tridentThrow, tridentHit, tridentReturn, riptide, windCharge, shearsSnip, ignite, spyglass, goatHorn
    // Interface
    case click, open, uiHover, uiBack, toast
    // Doors, containers and mechanisms
    case doorOpen, doorClose, ironDoorOpen, ironDoorClose, trapdoorOpen, trapdoorClose, ironTrapdoorOpen, ironTrapdoorClose, gateOpen, gateClose
    case chestOpen, chestClose, enderChestOpen, enderChestClose, barrelOpen, barrelClose, shulkerOpen, shulkerClose
    case pistonExtend, pistonContract, lever, buttonWood, buttonStone, plateOn, plateOff, dispense, dispenseFail, tripwire, fizz
    case anvil, anvilLand, anvilBreak, enchant, brew, grindstone, smithing, pageTurn, composterFill, composterReady
    case itemFrameAdd, itemFrameRemove, itemFrameRotate, paintingPlace, paintingBreak, honeySlide, amethystChime
    case waxOn, waxOff, scrape, bulbOn, bulbOff, crafterCraft, crafterFail, vaultOpen, vaultEject, vaultReject, spawnerSpawn
    case potBreak, potInsert, bundleInsert, bundleRemove, bedEnter, candleOut, lanternHang, respawnAnchorCharge, respawnAnchorSet
    case sculkClick, sculkShriek, sculkBloom, sculkSpread, bell, bellResonate, tntFuse, explode, glassBreak, iceCrack
    case portalTravel, portalTrigger, endPortalOpen, endPortalFrame, beaconActivate, beaconPower, beaconDeactivate
    case fireExtinguish, lavaPop, boatPaddle, railClick
    // Loops (seamless, 2-6 s): fire, furnaces, lava, water, portals, beacons, minecarts, gliding, breathing under water, weather, biome ambience.
    case fireLoop, furnaceLoop, campfireLoop, lavaLoop, waterLoop, portalLoop, beaconLoop, minecartLoop, elytraLoop, underwaterLoop, rain, rainRoof
    case respawnAnchorLoop, spawnerLoop, netherWastesLoop, soulValleyLoop, crimsonLoop, warpedLoop, basaltLoop, endLoop, deepDarkLoop, lushLoop, dripstoneLoop
    case cricketsLoop, oceanLoop, swampLoop, windLoop, jungleLoop, fireflyLoop, hiveLoop
    // One-shot ambience stings
    case birdCall, owlHoot, dryGrassRustle, heartCreak, caveAmbience, caveDrip, caveWind, netherMood, underwaterMood, thunder, lightning, windGust
    // Every mob: ambient call, hurt, death.
    case mob(MobKind, MobSound)
    case babyMob(MobKind, MobSound)   // young animals and villagers: the same voice, higher and lighter
    // Mob specials, bosses and villagers
    case creeperHiss, fireball, evokerCast, fangs, raidHorn, mobVoidwalker, teleport
    case dragonGrowl, dragonFlap, dragonShoot, dragonDeath, crystalBreak, witherSpawn, witherShoot, witherDeath
    case wardenHeartbeat, wardenRoar, wardenSonicCharge, wardenSonicBoom, wardenEmerge, wardenDig, wardenSniff
    case elderCurse, guardianLaser, villagerYes, villagerNo, villagerTrade, villagerWork(Int), villagerCelebrate, zombieBreakDoor, zombieInfect, zombieCure
    case phantomSwoop, beeSting, beePollinate, allayItem, foxSniff, catPurr, wolfPant, parrotMimic, dolphinJump, turtleEggCrack, frogTongue, goatRam, breezeShoot
    case fireworkLaunch, fireworkBlast, fireworkBlastLarge, fireworkTwinkle
    // Legacy names (kept so every call site still compiles; they render through the mob families).
    case mobCow, mobSheep, mobChicken, mobPig, mobZombie, mobSkeleton, mobSpider, mobSlime, mobWailer, mobCinderwisp, mobBoarling, mobUndeadBoarling
    case mobVillager, mobGolem, mobBlight, mobVex, mobRavager, mobWolf, mobCat, mobHorse, mobLlama, mobBee, mobWarden
    case note(Int, Int)            // note block: instrument, pitch 0...24 (made on demand)
    // Firearms and the Steelhold garrison (WeaponAudio.swift). gun(k): 0 rifle, 1 chatter gun, 2 shotgun, 3 farsight,
    // 4 rocket, 5 arc lance, 6 reload, 7 dry fire, 8 ricochet, 9 deck gun, 10 alarm, 11 radio call, 12 turret whine.
    case gun(Int), gunReload(Int), gunDistant(Int), bulletImpact(SoundMat), bulletWhizz, bulletFlesh, grenadeBounce
    case soldier(Int, Bark), soldierStep(Int)
    case rocketFlightLoop, shellFlightLoop          // projectiles in flight (heard as they pass)
    case explodeSmall, explodeLarge, debrisRain       // grenades / big blasts, and the debris pattering down after
    // Ships, airships and land vehicles (VehicleAudio.swift): idle/full layers are cross-faded by throttle.
    case engineIdleLoop, engineFullLoop, propSlowLoop, propFastLoop, airshipWindLoop, wheelRollLoop, hullWaterLoop
    case wingRushLoop, frigateDroneLoop, carriageTreadLoop
    case hullCreak, shipCollide, shipCollideHard, shipSplash, helmTake, engineStart
    case shipCannon, turretTraverseLoop
    // Terrain and weather (TerrainAudio.swift): moving water, wind by landform, rain on leaves, snow, far thunder.
    case riverLoop, waterfallLoop, mountainWindLoop, tundraWindLoop, rainLeavesLoop, snowWindLoop, swampInsectsLoop
    case thunderFar, iceCreak, rockfall

    var category: SoundCategory {
        switch self {
        case .mob(let k, _), .babyMob(let k, _): return k.hostile ? .hostile : .friendly
        case .mobCow, .mobSheep, .mobChicken, .mobPig, .mobVillager, .mobGolem, .mobWolf, .mobCat, .mobHorse, .mobLlama, .mobBee,
             .villagerYes, .villagerNo, .villagerTrade, .villagerWork, .villagerCelebrate, .beePollinate, .allayItem, .foxSniff, .catPurr, .wolfPant,
             .parrotMimic, .dolphinJump, .turtleEggCrack, .frogTongue, .goatRam, .zombieCure:
            return .friendly
        case .mobZombie, .mobSkeleton, .mobSpider, .mobSlime, .mobWailer, .mobCinderwisp, .mobBoarling, .mobUndeadBoarling, .mobBlight, .mobVex, .mobRavager,
             .mobWarden, .creeperHiss, .fireball, .evokerCast, .fangs, .raidHorn, .mobVoidwalker, .teleport, .dragonGrowl, .dragonFlap, .dragonShoot,
             .dragonDeath, .crystalBreak, .witherSpawn, .witherShoot, .witherDeath, .wardenHeartbeat, .wardenRoar, .wardenSonicCharge, .wardenSonicBoom,
             .wardenEmerge, .wardenDig, .wardenSniff, .elderCurse, .guardianLaser, .zombieBreakDoor, .zombieInfect, .phantomSwoop, .beeSting, .breezeShoot:
            return .hostile
        case .step, .splash, .swim, .land, .hurt, .hurtFall, .hurtDrown, .hurtFire, .playerDeath, .eat, .burp, .drink, .pickup, .dig, .attack, .attackSweep,
             .attackCrit, .attackKnockback, .attackWeak, .shieldBlock, .shieldBreak, .armorEquip, .itemBreak, .bucketFill, .bucketEmpty, .bucketFillLava,
             .bucketEmptyLava, .fishCast, .fishSplash, .fishReel, .xp, .levelUp, .totem, .gasp, .throwItem, .pearlThrow, .potionThrow, .potionSplash,
             .snowballHit, .eggCrack, .bowDraw, .bow, .arrowHit, .crossbowLoad, .crossbowShoot, .tridentThrow, .tridentHit, .tridentReturn, .riptide,
             .windCharge, .shearsSnip, .ignite, .spyglass, .goatHorn, .elytraLoop, .underwaterLoop, .boatPaddle, .minecartLoop:
            return .players
        case .click, .open, .uiHover, .uiBack, .toast: return .ui
        case .rain, .rainRoof, .thunder, .lightning, .windGust: return .weather
        case .fireLoop, .furnaceLoop, .campfireLoop, .lavaLoop, .waterLoop, .portalLoop, .beaconLoop, .respawnAnchorLoop, .spawnerLoop,
             .netherWastesLoop, .soulValleyLoop, .crimsonLoop, .warpedLoop, .basaltLoop, .endLoop, .deepDarkLoop, .lushLoop, .dripstoneLoop,
             .caveAmbience, .caveDrip, .caveWind, .netherMood, .underwaterMood, .lavaPop,
             .cricketsLoop, .oceanLoop, .swampLoop, .windLoop, .jungleLoop, .birdCall, .owlHoot, .fireflyLoop, .dryGrassRustle, .heartCreak, .hiveLoop:
            return .ambient
        case .note: return .blocks
        case .gun, .gunReload, .gunDistant, .bulletImpact, .bulletWhizz, .bulletFlesh, .grenadeBounce: return .players
        case .soldier, .soldierStep: return .hostile
        case .rocketFlightLoop, .shellFlightLoop: return .players
        case .explodeSmall, .explodeLarge, .debrisRain: return .blocks
        case .engineIdleLoop, .engineFullLoop, .propSlowLoop, .propFastLoop, .airshipWindLoop, .wheelRollLoop, .hullWaterLoop,
             .wingRushLoop, .frigateDroneLoop, .carriageTreadLoop,
             .hullCreak, .shipCollide, .shipCollideHard, .shipSplash, .helmTake, .engineStart, .shipCannon, .turretTraverseLoop: return .blocks
        case .riverLoop, .waterfallLoop, .mountainWindLoop, .tundraWindLoop, .swampInsectsLoop, .iceCreak, .rockfall: return .ambient
        case .rainLeavesLoop, .snowWindLoop, .thunderFar: return .weather
        default: return .blocks
        }
    }

    // How far away a sound can be heard (blocks); most sounds carry 16 blocks at full volume.
    var range: Float {
        switch self {
        case .explode, .fireworkBlastLarge, .lightning, .wardenSonicBoom, .crystalBreak, .endPortalOpen: return 64
        case .gun(let k): return k == 9 ? 128 : (k == 10 ? 96 : (k <= 5 || k == WeaponAudio.sidearmSlot ? 48 : 16))
        case .gunDistant: return 220
        case .explodeLarge: return 128
        case .explodeSmall: return 48
        case .shipCollideHard: return 48
        case .shipCannon: return 96
        case .shipCollide, .engineStart, .engineIdleLoop, .propSlowLoop, .wheelRollLoop, .turretTraverseLoop, .airshipWindLoop: return 32
        case .engineFullLoop, .propFastLoop, .wingRushLoop, .rocketFlightLoop, .shellFlightLoop: return 48
        case .frigateDroneLoop: return 160
        case .carriageTreadLoop: return 96
        case .waterfallLoop: return 32
        case .raidHorn, .goatHorn, .bellResonate: return 96
        case .dragonGrowl, .dragonDeath, .witherSpawn, .witherDeath, .dragonFlap: return 128
        case .thunder: return 160
        case .thunderFar: return 400
        case .rockfall: return 48
        case .bell, .fireworkBlast, .fireworkLaunch, .wardenRoar, .wardenEmerge, .sculkShriek, .mob(.ghast, _), .mobWailer, .beaconActivate: return 32
        default: return 16
        }
    }

    // Seamless loops are rendered with their tail cross-faded into their head.
    var isLoop: Bool {
        switch self {
        case .fireLoop, .furnaceLoop, .campfireLoop, .lavaLoop, .waterLoop, .portalLoop, .beaconLoop, .minecartLoop, .elytraLoop, .underwaterLoop, .rain, .rainRoof,
             .respawnAnchorLoop, .spawnerLoop, .netherWastesLoop, .soulValleyLoop, .crimsonLoop, .warpedLoop, .basaltLoop, .endLoop, .deepDarkLoop, .lushLoop, .dripstoneLoop,
             .cricketsLoop, .oceanLoop, .swampLoop, .windLoop, .jungleLoop, .fireflyLoop, .hiveLoop,
             .engineIdleLoop, .engineFullLoop, .propSlowLoop, .propFastLoop, .airshipWindLoop, .wheelRollLoop, .hullWaterLoop,
             .wingRushLoop, .frigateDroneLoop, .carriageTreadLoop,
             .riverLoop, .waterfallLoop, .mountainWindLoop, .tundraWindLoop, .rainLeavesLoop, .snowWindLoop, .swampInsectsLoop,
             .rocketFlightLoop, .shellFlightLoop, .turretTraverseLoop:
            return true
        default: return false
        }
    }

    // File / log name: "step_stone", "mob_cow_hurt", "villager_work_3".
    var name: String {
        switch self {
        case .breakBlock(let m): return "break_\(m.name)"
        case .place(let m): return "place_\(m.name)"
        case .step(let m): return "step_\(m.name)"
        case .hit(let m): return "hit_\(m.name)"
        case .fall(let m): return "fall_\(m.name)"
        case .armorEquip(let t): return "armor_equip_\(t)"
        case .villagerWork(let p): return "villager_work_\(p)"
        case .mob(let k, let s): return "mob_\(k.key)_\(s.name)"
        case .babyMob(let k, let s): return "baby_\(k.key)_\(s.name)"
        case .note(let i, let p): return "note_\(i)_\(p)"
        case .gun(let k): return "gun_\(k)"
        case .gunReload(let k): return "gun_reload_\(k)"
        case .gunDistant(let k): return "gun_distant_\(k)"
        case .bulletImpact(let m): return "bullet_impact_\(m.name)"
        case .soldier(let r, let b): return "soldier_\(r)_\(b.name)"
        case .soldierStep(let r): return "soldier_step_\(r)"
        default: return String(describing: self)
        }
    }

    // Expected clip length (seconds) for the offline check.
    var expectedSeconds: ClosedRange<Float> {
        switch self {
        case .step, .hit: return 0.02...0.7
        case .gun(let k): return k == 9 ? 1.0...6 : (k == 7 ? 0.03...0.4 : 0.1...3)
        case .gunReload: return 0.4...2.5
        case .gunDistant: return 0.5...6
        case .thunderFar: return 2...9
        case .explodeLarge: return 1.5...8
        case .bulletImpact, .bulletFlesh, .grenadeBounce, .soldierStep: return 0.03...1.2
        case .bulletWhizz: return 0.1...0.6
        case .soldier: return 0.15...3
        case .breakBlock, .place, .fall: return 0.08...1.3
        case .click, .uiHover, .uiBack, .lever, .buttonWood, .buttonStone, .plateOn, .plateOff, .tripwire, .railClick: return 0.02...0.5
        case .mob(_, .death), .babyMob(_, .death), .playerDeath, .dragonDeath, .witherDeath: return 0.15...8
        case .mob(_, .hurt), .babyMob(_, .hurt): return 0.04...2.5
        case .mob(_, .ambient), .babyMob(_, .ambient): return 0.05...5
        case .witherSpawn, .wardenEmerge, .wardenSonicCharge, .raidHorn, .goatHorn, .endPortalOpen, .beaconActivate, .thunder, .explode, .bellResonate, .caveAmbience,
             .netherMood, .underwaterMood, .caveWind, .totem, .elderCurse, .tntFuse, .fireworkTwinkle, .enchant, .villagerCelebrate, .levelUp, .fireworkBlastLarge, .lightning:
            return 0.5...12
        case _ where isLoop: return 1.5...8
        default: return 0.03...4
        }
    }

}


// Renders and caches clips. Rendering is deterministic (seeded per sound and variant), so the
// headless harness and the running game produce identical audio.
final class SoundBank {
    static let rate: Double = 44100
    private var clips: [Snd: [[Float]]] = [:]
    private var evicted = Set<Snd>()          // held as PCM by the engine: a late prewarm must not cache it again
    private let lock = NSLock()

    // Everything with a fixed identity (note blocks are open-ended and made on demand).
    static var allSounds: [Snd] {
        var s: [Snd] = []
        for m in SoundMat.allCases { s += [.breakBlock(m), .place(m), .step(m), .hit(m), .fall(m)] }
        s += [.splash, .swim, .land, .hurt, .hurtFall, .hurtDrown, .hurtFire, .playerDeath, .eat, .burp, .drink, .pickup, .dig,
              .attack, .attackSweep, .attackCrit, .attackKnockback, .attackWeak, .shieldBlock, .shieldBreak, .itemBreak,
              .bucketFill, .bucketEmpty, .bucketFillLava, .bucketEmptyLava, .fishCast, .fishSplash, .fishReel, .xp, .levelUp, .totem, .gasp,
              .throwItem, .pearlThrow, .potionThrow, .potionSplash, .snowballHit, .eggCrack, .bowDraw, .bow, .arrowHit, .crossbowLoad, .crossbowShoot,
              .tridentThrow, .tridentHit, .tridentReturn, .riptide, .windCharge, .shearsSnip, .ignite, .spyglass, .goatHorn,
              .click, .open, .uiHover, .uiBack, .toast,
              .doorOpen, .doorClose, .ironDoorOpen, .ironDoorClose, .trapdoorOpen, .trapdoorClose, .ironTrapdoorOpen, .ironTrapdoorClose, .gateOpen, .gateClose,
              .chestOpen, .chestClose, .enderChestOpen, .enderChestClose, .barrelOpen, .barrelClose, .shulkerOpen, .shulkerClose,
              .pistonExtend, .pistonContract, .lever, .buttonWood, .buttonStone, .plateOn, .plateOff, .dispense, .dispenseFail, .tripwire, .fizz,
              .anvil, .anvilLand, .anvilBreak, .enchant, .brew, .grindstone, .smithing, .pageTurn, .composterFill, .composterReady,
              .itemFrameAdd, .itemFrameRemove, .itemFrameRotate, .paintingPlace, .paintingBreak, .honeySlide, .amethystChime,
              .waxOn, .waxOff, .scrape, .bulbOn, .bulbOff, .crafterCraft, .crafterFail, .vaultOpen, .vaultEject, .vaultReject, .spawnerSpawn,
              .potBreak, .potInsert, .bundleInsert, .bundleRemove, .bedEnter, .candleOut, .lanternHang, .respawnAnchorCharge, .respawnAnchorSet,
              .sculkClick, .sculkShriek, .sculkBloom, .sculkSpread, .bell, .bellResonate, .tntFuse, .explode, .glassBreak, .iceCrack,
              .portalTravel, .portalTrigger, .endPortalOpen, .endPortalFrame, .beaconActivate, .beaconPower, .beaconDeactivate,
              .fireExtinguish, .lavaPop, .boatPaddle, .railClick,
              .fireLoop, .furnaceLoop, .campfireLoop, .lavaLoop, .waterLoop, .portalLoop, .beaconLoop, .minecartLoop, .elytraLoop, .underwaterLoop, .rain, .rainRoof,
              .respawnAnchorLoop, .spawnerLoop, .netherWastesLoop, .soulValleyLoop, .crimsonLoop, .warpedLoop, .basaltLoop, .endLoop, .deepDarkLoop, .lushLoop, .dripstoneLoop,
              .cricketsLoop, .oceanLoop, .swampLoop, .windLoop, .jungleLoop, .birdCall, .owlHoot, .fireflyLoop, .dryGrassRustle, .heartCreak, .hiveLoop,
              .caveAmbience, .caveDrip, .caveWind, .netherMood, .underwaterMood, .thunder, .lightning, .windGust,
              .creeperHiss, .fireball, .evokerCast, .fangs, .raidHorn, .mobVoidwalker, .teleport,
              .dragonGrowl, .dragonFlap, .dragonShoot, .dragonDeath, .crystalBreak, .witherSpawn, .witherShoot, .witherDeath,
              .wardenHeartbeat, .wardenRoar, .wardenSonicCharge, .wardenSonicBoom, .wardenEmerge, .wardenDig, .wardenSniff,
              .elderCurse, .guardianLaser, .villagerYes, .villagerNo, .villagerTrade, .villagerCelebrate, .zombieBreakDoor, .zombieInfect, .zombieCure,
              .phantomSwoop, .beeSting, .beePollinate, .allayItem, .foxSniff, .catPurr, .wolfPant, .parrotMimic, .dolphinJump, .turtleEggCrack, .frogTongue, .goatRam, .breezeShoot,
              .fireworkLaunch, .fireworkBlast, .fireworkBlastLarge, .fireworkTwinkle]
        for t in 0..<6 { s.append(.armorEquip(t)) }
        for p in 0..<13 { s.append(.villagerWork(p)) }
        for k in MobKind.allCases where MobVoice.profile(k).family != .silent {
            for m in MobSound.allCases { s.append(.mob(k, m)) }
        }
        for k in [MobKind.cow, .pig, .sheep, .chicken, .villager, .wolf, .cat, .horse, .fox, .goat] { s.append(.babyMob(k, .ambient)) }
        for k in 0...13 { s.append(.gun(k)) }
        for k in [0, 1, 2, 3, 4, 5, WeaponAudio.sidearmSlot] { s.append(.gunReload(k)); s.append(.gunDistant(k)) }
        s.append(.gunDistant(WeaponAudio.heavySlot))
        for m in SoundMat.allCases { s.append(.bulletImpact(m)) }
        s += [.bulletWhizz, .bulletFlesh, .grenadeBounce, .rocketFlightLoop, .shellFlightLoop, .explodeSmall, .explodeLarge, .debrisRain]
        s += [.engineIdleLoop, .engineFullLoop, .propSlowLoop, .propFastLoop, .airshipWindLoop, .wheelRollLoop, .hullWaterLoop,
              .hullCreak, .shipCollide, .shipCollideHard, .shipSplash, .helmTake, .engineStart, .shipCannon, .turretTraverseLoop,
              .wingRushLoop, .frigateDroneLoop, .carriageTreadLoop]
        s += [.riverLoop, .waterfallLoop, .mountainWindLoop, .tundraWindLoop, .rainLeavesLoop, .snowWindLoop, .swampInsectsLoop,
              .thunderFar, .iceCreak, .rockfall]
        for r in 0...3 { for b in Bark.allCases { s.append(.soldier(r, b)) }; s.append(.soldierStep(r)) }
        return s
    }

    // Rendered in the background when a fight or a vehicle is near, so the first shot or engine doesn't hitch.
    static var combatSounds: [Snd] {
        var s: [Snd] = []
        for k in 0...13 { s.append(.gun(k)) }
        for k in [0, 1, 2, 3, 4, 5, WeaponAudio.sidearmSlot] { s.append(.gunReload(k)); s.append(.gunDistant(k)) }
        s.append(.gunDistant(WeaponAudio.heavySlot))
        for m in [SoundMat.stone, .dirt, .sand, .wood, .plant, .glass, .gravel, .metal, .deepslate] { s.append(.bulletImpact(m)) }
        s += [.bulletWhizz, .bulletFlesh, .grenadeBounce, .rocketFlightLoop, .shellFlightLoop, .explodeSmall, .explodeLarge, .debrisRain]
        for r in 0...3 { for b in Bark.allCases { s.append(.soldier(r, b)) }; s.append(.soldierStep(r)) }
        return s
    }
    static var vehicleSounds: [Snd] {
        [.engineStart, .engineIdleLoop, .engineFullLoop, .propSlowLoop, .propFastLoop, .airshipWindLoop, .wheelRollLoop, .hullWaterLoop,
         .wingRushLoop, .frigateDroneLoop, .carriageTreadLoop, .hullCreak, .shipCollide, .shipCollideHard, .shipSplash, .helmTake,
         .shipCannon, .turretTraverseLoop, .shellFlightLoop, .explodeLarge]
    }

    // Sounds worth having ready before the first frame (rendered first by the prewarm thread).
    static var commonSounds: [Snd] {
        var s: [Snd] = []
        for m in [SoundMat.stone, .dirt, .wood, .plant, .sand, .gravel, .snow] { s += [.step(m), .hit(m), .breakBlock(m), .place(m)] }
        s += [.click, .open, .uiBack, .pickup, .splash, .land, .hurt, .eat, .attack, .attackSweep, .doorOpen, .doorClose, .chestOpen, .chestClose, .xp, .levelUp, .bow,
              .fireLoop, .waterLoop, .lavaLoop, .rain, .underwaterLoop, .caveAmbience, .birdCall, .caveDrip, .netherMood, .thunder, .explode]
        for k in [MobKind.cow, .sheep, .chicken, .pig, .zombie, .skeleton, .creeper, .spider, .enderman, .villager] {
            for m in MobSound.allCases { s.append(.mob(k, m)) }
        }
        return s
    }

    // Short, common sounds get 3 takes; mobs 2; long ambience and one-offs 1.
    static func variants(for s: Snd) -> Int {
        switch s {
        case .step, .hit, .breakBlock, .place, .fall, .attack, .attackSweep, .eat, .lavaPop, .caveDrip, .villagerWork: return 3
        case .birdCall: return 6
        case .gun(let k): return k <= 5 || k == 8 || k == WeaponAudio.sidearmSlot ? 3 : 2
        case .bulletImpact, .bulletWhizz, .bulletFlesh, .soldierStep: return 3
        case .soldier(_, let b): return b == .idle ? 4 : 3
        case .mob(_, .ambient), .mob(_, .hurt), .babyMob: return 2
        case .note: return 1
        case _ where s.isLoop: return 1
        case _ where s.expectedSeconds.upperBound >= 5: return 1
        default: return 2
        }
    }

    // FNV-1a of the sound name, so seeds do not depend on Swift's per-process hashing.
    static func seed(_ s: Snd, variant v: Int) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.name.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return h ^ (UInt64(v + 1) &* 0x9E3779B97F4A7C15)
    }

    // Pure: the clip for one take of a sound.
    static func render(_ s: Snd, variant v: Int) -> [Float] {
        var g = Synth(seed: seed(s, variant: v))
        let n = variants(for: s)
        let pitch: Float = n <= 1 ? 1 : 1 + (Float(v) - Float(n - 1) / 2) * 0.07
        let x = g.render(s, pitch: pitch)
        // Takes also differ by a small playback-rate change (like a pitch jitter), so even fully
        // deterministic patches (bells, chimes, level-up) vary between takes.
        guard n > 1 && v > 0 && !s.isLoop else { return x }
        let rate: Float = 1 + (v % 2 == 1 ? 0.035 : -0.035) * Float((v + 1) / 2)
        let m = Int(Float(x.count) / rate)
        guard m > 8 else { return x }
        var out = [Float](repeating: 0, count: m)
        for i in 0..<m {
            let t = Float(i) * rate
            let k = Int(t)
            let f = t - Float(k)
            let a = x[min(k, x.count - 1)], b = x[min(k + 1, x.count - 1)]
            out[i] = a + (b - a) * f
        }
        out[m - 1] = 0
        return out
    }

    func has(_ s: Snd) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return clips[s] != nil
    }

    // The cached clip, rendering it synchronously when missing (a few ms for short sounds).
    func clip(_ s: Snd, variant: Int) -> [Float] {
        lock.lock()
        if let vs = clips[s], !vs.isEmpty { lock.unlock(); return vs[variant % vs.count] }
        lock.unlock()
        var vs: [[Float]] = []
        for v in 0..<SoundBank.variants(for: s) { vs.append(SoundBank.render(s, variant: v)) }
        lock.lock(); if !evicted.contains(s) { clips[s] = vs }; lock.unlock()
        return vs[variant % vs.count]
    }

    // Renders a list in the background (common sounds first, then everything) so play() rarely renders on the main thread.
    private var pending = Set<Snd>()
    func prewarm(_ list: [Snd], qos: DispatchQoS.QoSClass = .utility) {
        lock.lock()
        let todo = list.filter { clips[$0] == nil && !pending.contains($0) && !evicted.contains($0) }
        for s in todo { pending.insert(s) }
        lock.unlock()
        guard !todo.isEmpty else { return }
        DispatchQueue.global(qos: qos).async { [weak self] in
            for s in todo {
                guard let self = self else { return }
                _ = self.clip(s, variant: 0)
                self.lock.lock(); self.pending.remove(s); self.lock.unlock()
            }
        }
    }

    // Drops a sound's float copy once the engine holds it as PCM buffers (halves resident audio memory).
    func evict(_ s: Snd) {
        lock.lock(); clips[s] = nil; evicted.insert(s); lock.unlock()
    }

    var cachedCount: Int { lock.lock(); defer { lock.unlock() }; return clips.count }
    var cachedBytes: Int {
        lock.lock(); defer { lock.unlock() }
        var n = 0
        for vs in clips.values { for v in vs { n += v.count * 4 } }
        return n
    }

    // 16-bit mono WAV (used by the headless harness to check the synth).
    static func writeWAV(_ samples: [Float], to path: String, rate: Double = SoundBank.rate) {
        var d = Data()
        d.reserveCapacity(44 + samples.count * 2)
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let n = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + n)
        d.append(contentsOf: Array("WAVEfmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(rate)); u32(UInt32(rate) * 2); u16(2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(n)
        for x in samples { u16(UInt16(bitPattern: Int16(max(-1, min(1, x)) * 32767))) }
        try? d.write(to: URL(fileURLWithPath: path))
    }

    // Offline sanity check of a rendered clip: non-silent, unclipped, finite, the right length, seamless if a loop.
    struct Check {
        var seconds: Float = 0, peak: Float = 0, rms: Float = 0, dc: Float = 0, clipped = 0, nan = 0, loopGap: Float = 0
        var problems: [String] = []
        var ok: Bool { problems.isEmpty }
    }
    static func check(_ s: Snd, _ x: [Float]) -> Check {
        var c = Check()
        c.seconds = Float(x.count) / Float(rate)
        var sum: Float = 0, sq: Float = 0
        for v in x {
            if !v.isFinite { c.nan += 1; continue }
            let a = abs(v)
            if a > c.peak { c.peak = a }
            if a >= 0.999 { c.clipped += 1 }
            sum += v; sq += v * v
        }
        if !x.isEmpty { c.rms = sqrtf(sq / Float(x.count)); c.dc = sum / Float(x.count) }
        let want = s.expectedSeconds
        if c.nan > 0 { c.problems.append("\(c.nan) non-finite samples") }
        if x.isEmpty || c.peak < 0.05 { c.problems.append(String(format: "silent (peak %.3f)", c.peak)) }
        if c.rms < 0.002 { c.problems.append(String(format: "too quiet (rms %.4f)", c.rms)) }
        if c.clipped > 0 { c.problems.append("\(c.clipped) clipped samples") }
        if abs(c.dc) > 0.05 { c.problems.append(String(format: "dc offset %.3f", c.dc)) }
        if !want.contains(c.seconds) { c.problems.append(String(format: "length %.2fs outside %.2f...%.2f", c.seconds, want.lowerBound, want.upperBound)) }
        if s.isLoop && x.count > 100 {
            // A loop's seam must not click: the wrap-around step may be no bigger than the largest step inside the clip.
            var maxStep: Float = 0
            for k in 1..<x.count { let d = abs(x[k] - x[k - 1]); if d > maxStep { maxStep = d } }
            c.loopGap = abs(x[x.count - 1] - x[0])
            if c.loopGap > max(0.05, maxStep * 1.05) { c.problems.append(String(format: "loop seam jump %.3f (largest inner step %.3f)", c.loopGap, maxStep)) }
        } else if x.count > 8 {
            // One-shots must start and end near zero (no clicks).
            if abs(x[0]) > 0.05 { c.problems.append(String(format: "starts at %.3f", x[0])) }
            if abs(x[x.count - 1]) > 0.02 { c.problems.append(String(format: "ends at %.3f", x[x.count - 1])) }
        }
        return c
    }
}
