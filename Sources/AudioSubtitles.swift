import Foundation
import simd

// Subtitles (Options → Audio → Subtitles): a short caption for each sound you hear, with an arrow toward
// where it came from, listed bottom-right above the hotbar and fading after a few seconds.

final class SubtitleState {
    struct Line { var text: String; var time: Double; var pos: V3? }
    var lines: [Line] = []
}

extension AudioSettings {
    static var forceSubtitles = false        // harness only (not saved)
    // One subtitles option shared by Options → Audio and Options → Accessibility (Settings.subtitles).
    // Storage lives in Settings.subtitles (never forward back from there: that recursed forever).
    static var subtitles: Bool {
        get { forceSubtitles || Settings.shared.subtitles }
        set { Settings.shared.subtitles = newValue }
    }
}

extension MobVoice.Family {
    var verb: String {
        switch self {
        case .silent: return "clatters"
        case .grunt: return "grunts"
        case .moo: return "moos"
        case .bleat: return "bleats"
        case .cluck: return "clucks"
        case .groan: return "groans"
        case .rattle: return "rattles"
        case .hiss: return "hisses"
        case .warble: return "warbles"
        case .squish: return "squishes"
        case .wail: return "wails"
        case .crackle: return "crackles"
        case .hum: return "mumbles"
        case .growl: return "growls"
        case .bark: return "barks"
        case .meow: return "meows"
        case .neigh: return "neighs"
        case .buzz: return "buzzes"
        case .chirp: return "chirps"
        case .roar: return "roars"
        case .bubble: return "gurgles"
        case .click: return "clicks"
        case .rumble: return "rumbles"
        case .creak: return "creaks"
        case .trill: return "trills"
        case .snort: return "snorts"
        case .wind: return "whirls"
        case .squeak: return "squeaks"
        case .soldier: return "talks"
        case .snow: return "crunches"
        }
    }
}

extension Snd {
    // nil = no subtitle (the player's own footsteps, UI clicks, constant beds handled by loop captions).
    func caption(positional: Bool) -> String? {
        switch self {
        case .mob(let k, let s), .babyMob(let k, let s):
            let n = k.spec.name
            switch s {
            case .ambient: return "\(n) \(MobVoice.profile(k).family.verb)"
            case .hurt: return "\(n) hurts"
            case .death: return "\(n) dies"
            }
        case .step: return positional ? "Footsteps" : nil
        case .hit: return nil
        case .voice(let i): return TownVoice.caption(i)
        case .breakBlock: return "Block broken"
        case .place: return "Block placed"
        case .fall: return "Something fell"
        case .splash: return "Splash"
        case .swim: return "Swimming"
        case .land: return nil
        case .hurt, .hurtFall, .hurtDrown, .hurtFire: return "Player hurts"
        case .playerDeath: return "Player dies"
        case .eat: return "Eating"
        case .burp: return "Burp"
        case .drink: return "Drinking"
        case .pickup: return "Item picked up"
        case .dig: return nil
        case .attack, .attackSweep, .attackCrit, .attackKnockback, .attackWeak: return "Attack"
        case .shieldBlock: return "Shield blocks"
        case .shieldBreak: return "Shield breaks"
        case .armorEquip: return "Gear equipped"
        case .itemBreak: return "Item breaks"
        case .bucketFill, .bucketFillLava: return "Bucket fills"
        case .bucketEmpty, .bucketEmptyLava: return "Bucket empties"
        case .fishCast: return "Line cast"
        case .fishSplash: return "Bobber splashes"
        case .fishReel: return "Line reeled"
        case .xp: return "Experience gained"
        case .levelUp: return "Level up"
        case .totem: return "Totem activates"
        case .gasp: return "Gasping"
        case .throwItem, .pearlThrow, .potionThrow: return "Item thrown"
        case .potionSplash: return "Bottle smashes"
        case .snowballHit: return "Snowball hits"
        case .eggCrack: return "Egg cracks"
        case .bowDraw: return "Bow pulled"
        case .bow: return "Arrow fired"
        case .arrowHit: return "Arrow hits"
        case .crossbowLoad: return "Crossbow loads"
        case .crossbowShoot: return "Crossbow fires"
        case .tridentThrow: return "Trident thrown"
        case .tridentHit: return "Trident hits"
        case .tridentReturn: return "Trident returns"
        case .riptide: return "Trident surges"
        case .windCharge: return "Wind bursts"
        case .shearsSnip: return "Shears snip"
        case .ignite: return "Fire lit"
        case .spyglass: return nil
        case .goatHorn: return "Horn blares"
        case .click, .open, .uiHover, .uiBack, .toast: return nil
        case .doorOpen, .ironDoorOpen: return "Door opens"
        case .doorClose, .ironDoorClose: return "Door closes"
        case .trapdoorOpen, .ironTrapdoorOpen: return "Trapdoor opens"
        case .trapdoorClose, .ironTrapdoorClose: return "Trapdoor closes"
        case .gateOpen: return "Gate opens"
        case .gateClose: return "Gate closes"
        case .chestOpen, .enderChestOpen, .barrelOpen, .shulkerOpen: return "Container opens"
        case .chestClose, .enderChestClose, .barrelClose, .shulkerClose: return "Container closes"
        case .pistonExtend: return "Piston moves"
        case .pistonContract: return "Piston retracts"
        case .lever: return "Lever clicks"
        case .buttonWood, .buttonStone: return "Button clicks"
        case .plateOn, .plateOff: return "Pressure plate clicks"
        case .dispense: return "Dispensed item"
        case .dispenseFail: return "Dispenser fails"
        case .tripwire: return "Tripwire clicks"
        case .fizz: return "Fizz"
        case .anvil: return "Anvil used"
        case .anvilLand: return "Anvil lands"
        case .anvilBreak: return "Anvil destroyed"
        case .enchant: return "Enchanting"
        case .brew: return "Brewing"
        case .grindstone: return "Grindstone used"
        case .smithing: return "Smithing table used"
        case .pageTurn: return "Page rustles"
        case .composterFill: return "Composter fills"
        case .composterReady: return "Composter ready"
        case .itemFrameAdd: return "Item framed"
        case .itemFrameRemove: return "Frame emptied"
        case .itemFrameRotate: return "Item clicks"
        case .paintingPlace: return "Painting placed"
        case .paintingBreak: return "Painting breaks"
        case .honeySlide: return "Sliding"
        case .amethystChime: return "Crystal chimes"
        case .waxOn: return "Wax on"
        case .waxOff: return "Wax off"
        case .scrape: return "Scraping"
        case .bulbOn, .bulbOff: return "Bulb clicks"
        case .crafterCraft: return "Crafter crafts"
        case .crafterFail: return "Crafter fails"
        case .vaultOpen: return "Vault opens"
        case .vaultEject: return "Vault ejects item"
        case .vaultReject: return "Vault rejects"
        case .spawnerSpawn: return "Spawner flares"
        case .potBreak: return "Pot shatters"
        case .potInsert: return "Pot filled"
        case .bundleInsert, .bundleRemove: return nil
        case .bedEnter: return "Bed creaks"
        case .candleOut: return "Candle snuffed"
        case .lanternHang: return "Lantern placed"
        case .respawnAnchorCharge: return "Anchor charges"
        case .respawnAnchorSet: return "Spawn point set"
        case .sculkClick: return "Murk sensor clicks"
        case .sculkShriek: return "Shrieker shrieks"
        case .sculkBloom: return "Murk blooms"
        case .sculkSpread: return "Murk spreads"
        case .bell, .bellResonate: return "Bell rings"
        case .tntFuse: return "Fuse hisses"
        case .explode: return "Explosion"
        case .glassBreak: return "Glass breaks"
        case .iceCrack: return "Ice cracks"
        case .portalTravel: return "Portal whooshes"
        case .portalTrigger: return "Portal hums"
        case .endPortalOpen: return "Gate opens"
        case .endPortalFrame: return "Eye placed"
        case .beaconActivate: return "Beacon activates"
        case .beaconPower: return "Beacon power selected"
        case .beaconDeactivate: return "Beacon fades"
        case .fireExtinguish: return "Fire extinguished"
        case .lavaPop: return "Lava pops"
        case .boatPaddle: return "Paddling"
        case .railClick: return "Rail clicks"
        case .fireLoop, .campfireLoop: return "Fire crackles"
        case .furnaceLoop: return "Furnace crackles"
        case .lavaLoop: return "Lava bubbles"
        case .waterLoop: return "Water flows"
        case .portalLoop: return "Portal whooshes"
        case .beaconLoop: return "Beacon hums"
        case .stationHumLoop: return "Machinery hums"
        case .minecartLoop: return "Minecart rolls"
        case .elytraLoop: return "Wind rushes"
        case .underwaterLoop: return nil
        case .rain, .rainRoof: return "Rain falls"
        case .respawnAnchorLoop: return "Anchor hums"
        case .spawnerLoop: return "Spawner crackles"
        case .netherWastesLoop, .soulValleyLoop, .crimsonLoop, .warpedLoop, .basaltLoop, .endLoop, .deepDarkLoop, .lushLoop, .dripstoneLoop: return nil
        case .cricketsLoop: return "Crickets chirp"
        case .oceanLoop: return "Waves crash"
        case .swampLoop: return "Frogs croak"
        case .windLoop: return "Wind blows"
        case .jungleLoop: return "Insects buzz"
        case .birdCall: return "Bird sings"
        case .fireflyLoop: return "Fireflies twinkle"
        case .hiveLoop: return "Hive buzzes"
        case .dryGrassRustle: return "Dry grass rustles"
        case .heartCreak: return "Heart creaks"
        case .owlHoot: return "Owl hoots"
        case .caveAmbience, .caveWind: return "Cave noises"
        case .caveDrip: return "Water drips"
        case .netherMood: return "Eerie noise"
        case .underwaterMood: return "Deep moan"
        case .thunder: return "Thunder roars"
        case .lightning: return "Lightning strikes"
        case .windGust: return "Wind gusts"
        case .creeperHiss: return "Hisser hisses"
        case .fireball: return "Fireball"
        case .evokerCast: return "Conjurer casts"
        case .fangs: return "Fangs snap"
        case .raidHorn: return "Raid horn blows"
        case .mobVoidwalker: return "Voidwalker screams"
        case .teleport: return "Something teleports"
        case .dragonGrowl: return "Hollow Wyrm growls"
        case .dragonFlap: return "Wings flap"
        case .dragonShoot: return "Hollow Wyrm breathes"
        case .dragonDeath: return "Hollow Wyrm dies"
        case .crystalBreak: return "Crystal shatters"
        case .witherSpawn: return "The Blight awakens"
        case .witherShoot: return "The Blight shoots"
        case .witherDeath: return "The Blight dies"
        case .wardenHeartbeat: return "Heart beats"
        case .wardenRoar: return "Deep Stalker roars"
        case .wardenSonicCharge: return "Deep Stalker charges"
        case .wardenSonicBoom: return "Sonic boom"
        case .wardenEmerge: return "Deep Stalker emerges"
        case .wardenDig: return "Deep Stalker digs"
        case .wardenSniff: return "Deep Stalker sniffs"
        case .elderCurse: return "Curse inflicted"
        case .guardianLaser: return "Beam charges"
        case .villagerYes: return "Townsperson agrees"
        case .villagerNo: return "Townsperson disagrees"
        case .villagerTrade: return "Townsperson trades"
        case .villagerWork: return "Townsperson works"
        case .villagerCelebrate: return "Townsfolk cheer"
        case .zombieBreakDoor: return "Door bashed"
        case .zombieInfect: return "Townsperson infected"
        case .zombieCure: return "Zombie townsperson snuffles"
        case .phantomSwoop: return "Nightwing swoops"
        case .beeSting: return "Bee stings"
        case .beePollinate: return "Bee buzzes"
        case .allayItem: return "Helper chimes"
        case .foxSniff: return "Fox sniffs"
        case .catPurr: return "Cat purrs"
        case .wolfPant: return "Wolf pants"
        case .parrotMimic: return "Parrot talks"
        case .dolphinJump: return "Dolphin jumps"
        case .turtleEggCrack: return "Egg cracks"
        case .frogTongue: return "Frog eats"
        case .goatRam: return "Goat rams"
        case .breezeShoot: return "Gustling shoots"
        case .fireworkLaunch: return "Firework launches"
        case .fireworkBlast, .fireworkBlastLarge: return "Firework blasts"
        case .fireworkTwinkle: return "Firework twinkles"
        case .mobCow, .mobSheep, .mobChicken, .mobPig, .mobZombie, .mobSkeleton, .mobSpider, .mobSlime, .mobWailer, .mobCinderwisp, .mobBoarling,
             .mobUndeadBoarling, .mobVillager, .mobGolem, .mobBlight, .mobVex, .mobRavager, .mobWolf, .mobCat, .mobHorse, .mobLlama, .mobBee, .mobWarden:
            return "Creature calls"
        case .note: return "Note block plays"
        case .gun(let k):
            switch k {
            case 0...5, 13: return "Gunfire"
            case 6: return "Reloading"
            case 7: return "Gun clicks empty"
            case 8: return "Ricochet"
            case 9: return "Heavy gun fires"
            case 10: return "Alarm blares"
            case 11: return "Radio chatter"
            case 14: return "Gun loaded"
            case 15: return "Gun empty"
            default: return "Turret turns"
            }
        case .gunReload: return "Reloading"
        case .riverLoop: return "Stream babbles"
        case .waterfallLoop: return "Waterfall roars"
        case .mountainWindLoop: return "Wind howls"
        case .tundraWindLoop, .snowWindLoop: return "Icy wind"
        case .rainLeavesLoop: return "Rain on leaves"
        case .swampInsectsLoop: return "Insects drone"
        case .thunderFar: return "Distant thunder"
        case .iceCreak: return "Ice creaks"
        case .rockfall: return "Rocks tumble"
        case .engineIdleLoop, .engineFullLoop: return "Engine runs"
        case .propSlowLoop, .propFastLoop: return "Propeller whirs"
        case .airshipWindLoop: return "Wind in the rigging"
        case .wingRushLoop: return "Air rushes past"
        case .frigateDroneLoop: return "Warship engines drone"
        case .carriageTreadLoop: return "Heavy treads clank"
        case .wheelRollLoop: return "Wheels rumble"
        case .hullWaterLoop: return "Water laps the hull"
        case .hullCreak: return "Hull creaks"
        case .shipCollide, .shipCollideHard: return "Hull crashes"
        case .shipSplash: return "Hull splashes"
        case .helmTake: return "Helm taken"
        case .engineStart: return "Engine starts"
        case .shipCannon: return "Cannon fires"
        case .mainGunCharge: return "Main gun charging"
        case .mainGunFire: return "Main gun fires"
        case .mainGunRumble: return "Ground rumbles"
        case .turretTraverseLoop: return "Turret turns"
        case .gunDistant: return "Distant gunfire"
        case .bulletImpact: return "Bullet hits"
        case .bulletWhizz: return "Bullet whizzes"
        case .rocketFlightLoop: return "Rocket roars past"
        case .explodeSmall, .explodeLarge: return "Explosion"
        case .debrisRain: return "Debris falls"
        case .shellFlightLoop: return "Shell whistles"
        case .bulletFlesh: return "Bullet hits flesh"
        case .grenadeBounce: return "Grenade bounces"
        case .soldier(_, let b):
            switch b {
            case .alert: return "Soldier shouts"
            case .attack: return "Soldier orders"
            case .reload: return "Soldier reloads"
            case .grenade: return "Grenade warning"
            case .hurt: return "Soldier hurts"
            case .death: return "Soldier dies"
            case .idle: return "Soldier chatters"
            case .retreat: return "Soldier falls back"
            }
        case .soldierStep: return positional ? "Boots" : nil
        }
    }
}

extension Game {
    // Records a caption for a played sound (called from sfx and for active loops).
    func subtitle(_ s: Snd, at pos: V3?) {
        Subtitles.shared.add(self, s, at: pos)      // drawn by HudExtras with the controller prompts
    }

    // Lines to draw (newest last) with an arrow toward the source and an alpha that fades out.
    func subtitleLines() -> [(String, Float)] {
        guard AudioSettings.subtitles else { return [] }
        let st = subtitles
        st.lines.removeAll { clock - $0.time > 3 }
        guard !st.lines.isEmpty else { return [] }
        let eye = player.eye
        let right = V3(cosf(player.yaw), 0, -sinf(player.yaw))
        var out: [(String, Float)] = []
        for l in st.lines {
            let age = Float(clock - l.time)
            let alpha: Float = min(1, (3 - age) / 1)
            var t = l.text
            if let p = l.pos {
                let rel = p - eye
                let d = simd_length(rel)
                if d > 1.5 {
                    let side = simd_dot(rel / d, right)
                    if side > 0.35 { t = "  \(t) >" } else if side < -0.35 { t = "< \(t)  " } else { t = "  \(t)  " }
                } else { t = "  \(t)  " }
            } else { t = "  \(t)  " }
            out.append((t, alpha))
        }
        return out
    }
}
