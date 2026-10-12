import Foundation
import simd

// The Deep stage of the scripted playthrough (backlog G4; `--playthrough --only deep`): the story under the surface the
// way a player does it. An Ember Charge through the Wardstone floor, down into the hell band, the nearest Brimstone
// Keep and its Castellan (the Ember Gate wakes), Sunderite from the strongroom walls through flux and a blast furnace
// to a pickaxe and a Sunder Charge, the charge through the Sealrock, the fall into the Ash Vault, the Marshal, the last
// battle's three waves, the Chancellor in his bunker, and the lift home. Fights are real swings through Game.tick;
// where a player would grind on (a whole wave of tanks, a 70-block shaft), the script fights for a while and finishes
// the rest in bulk, logged as such, so CI still sees every story step happen.
extension Playthrough {
    func theDeep() {
        section("deep: through the floor")
        game.ashVictory = false; game.ashStage = 0; game.ashWave = 0
        kitForDeep()
        if game.dim.dim != .overworld { game.changeDimension(to: .overworld, at: game.spawnPoint) }
        let sp = game.spawnPoint
        let sx = Int(floor(sp.x)) + 12, sz = Int(floor(sp.z)) + 12
        _ = world.loadSync(center: V3(Float(sx), Float(HellGate.floorTop + 4), Float(sz)), radius: 2)
        // The shaft down to the floor (a player digs it a block at a time; the floor is what this stage is about).
        let top = world.topY(sx, sz)
        for y in HellGate.floorTop...(top + 2) { for dz in -1...1 { for dx in -1...1 { world.setBlock(sx + dx, y, sz + dz, AIR) } } }
        info("bulk: dug a shaft \(top - HellGate.floorTop) blocks down to the Wardstone floor")
        let floorCell = IVec3(sx, HellGate.floorTop - 1, sz)
        check(world.block(floorCell.x, floorCell.y, floorCell.z) == WARDSTONE, "deep: the bottom of the surface is Wardstone (\(key(floorCell)))")
        // A Duskium pickaxe gets nowhere on it.
        _ = hold("netherite_pickaxe")
        let dug = mine(floorCell, maxSeconds: 4)
        check(!dug, "deep: a Duskium pickaxe can't break the Wardstone")
        // An Ember Charge (command-room loot) pressed onto it, through the use click; stand on it and fall through.
        give("ember_charge", 1, bulk: "a base's command chest")
        _ = hold("ember_charge")
        let stand = V3(Float(sx) + 0.5, Float(HellGate.floorTop), Float(sz) + 0.5)
        game.player.flying = false
        game.player.pos = stand; game.player.vel = .zero
        aim(at: center(floorCell))
        game.input.rightClicked = true
        frame()
        let set = !game.hell.charges.isEmpty
        let down = tick(Double(HellGate.chargeFuse) + 6) { self.game.dim.dim == .deep }
        check(set && down && game.deepEntry != nil && game.advancements.contains("adventure/deep"),
              "deep: an Ember Charge blows the floor and the player drops into the Deep (charge set \(set), Bottom of the World)")
        if game.dim.dim != .deep { game.crossSeam(down: true) }

        section("deep: the hell band")
        // Dig down through the upper crust with the pickaxe until the fire sky opens below.
        _ = hold("netherite_pickaxe")
        var blocksDug = 0
        for _ in 0..<24 where !DeepGen.inHell(game.player.pos.y) {
            let f = game.player.pos
            let below = IVec3(Int(floor(f.x)), Int(floor(f.y - 0.05)) - 0, Int(floor(f.z)))
            let cell = IVec3(below.x, below.y - (clear(below) ? 1 : 0), below.z)
            if clear(cell) { game.player.flying = false; _ = tick(1.5); continue }
            if !carvable(cell) { break }
            if mine(cell, maxSeconds: 8) { blocksDug += 1 }
            game.player.flying = false
            game.player.pos = V3(Float(cell.x) + 0.5, Float(cell.y) + 0.01, Float(cell.z) + 0.5)
            _ = tick(0.5)
        }
        info("dug \(blocksDug) blocks of crust")
        if !DeepGen.inHell(game.player.pos.y) {
            info("bulk: the crust went on; dropped into the hell band below")
            game.player.pos.y = Float(DeepGen.crustTop - 2)
        }
        _ = tick(1.1)
        check(game.advancements.contains("adventure/deep_hell"), "deep: in the hell band (Under the Fire Sky)")
        guard let keep = game.nearestKeep() else { check(false, "deep: the compass finds a Brimstone Keep"); return }
        let c = DeepGates.centre(keep)
        let kd = Int(simd_length(V2(Float(c.ox) - game.player.pos.x, Float(c.oz) - game.player.pos.z)))
        check(kd < 1600, "deep: the compass points to a Brimstone Keep \(kd) blocks off")
        info("bulk: rode \(kd) blocks across the hell band to the keep")

        section("deep: the Castellan")
        let yard = DeepGates.front(keep)
        game.player.flying = false
        game.player.pos = yard; game.player.vel = .zero
        _ = world.loadSync(center: yard, radius: 4)
        _ = tick(2)
        let strong = V3(Float(c.ox) + 0.5, Float(c.f - 9), Float(c.oz) + 0.5)
        _ = world.loadSync(center: strong, radius: 3)
        _ = tick(1)
        guard let warden = game.mobs.mobs.first(where: { $0.warden && $0.health > 0 }) else {
            check(false, "deep: the keep's Castellan waits in the strongroom"); return
        }
        // The courtyard garrison is fought off on the way in (each a fight like any other: bulk).
        let guards = game.mobs.mobs.filter { $0 !== warden && $0.kind.hostile && simd_length($0.pos - strong) < 20 }
        game.mobs.mobs.removeAll { m in guards.contains { $0 === m } }
        info("bulk: fought through \(guards.count) of the keep's guards to the strongroom")
        _ = hold("netherite_sword")
        let wt = simSeconds
        var swings = 0
        while warden.health > 0 && game.mobs.mobs.contains(where: { $0 === warden }) && swings < 260 {
            swing(at: warden)
            swings += 1
        }
        let fought = warden.health <= 0 || !game.mobs.mobs.contains { $0 === warden }
        check(fought, String(format: "deep: the Castellan falls to the sword (%d swings, %.0f s)", swings, simSeconds - wt))
        if !fought { warden.killedByPlayer = true; warden.hit(from: warden.pos + V3(1, 0, 0), damage: warden.health + 900); _ = tick(0.5) }
        collect(near: warden.pos, 10)
        let veil = Blocks.id(DeepGates.veilKey)
        let woke = DeepGates.veil(keep).contains { world.block($0.x, $0.y, $0.z) == veil }
        check(game.advancements.contains("adventure/keep_warden") && woke && count("gate_shard") >= 1,
              "deep: Castellan's Fall: the Ember Gate wakes (\(woke)) and the Gate Shard is picked up (\(count("gate_shard")))")

        section("deep: Sunderite")
        let sc = IVec3(c.ox, c.f - 9, c.oz)
        var mined = 0
        _ = hold("netherite_pickaxe")
        for _ in 0..<4 {
            guard let ore = findBlock(near: sc, radius: 7, yRange: (c.f - 13)...(c.f - 1), { $0 == "sunderite_ore" }) else { break }
            if mine(ore, maxSeconds: 20) { mined += 1; collect(near: center(ore), 6) }
        }
        let raw = count("raw_sunderite")
        check(mined >= 2 && raw >= 2, "deep: Sunderite Ore mined from the strongroom walls (\(mined) ore, \(raw) Raw Sunderite)")
        if raw < 8 { give("raw_sunderite", 8 - raw, bulk: "the rest of the strongroom's ore and its chest") }
        if count("blaze_powder") < 4 {
            if count("blaze_rod") < 2 { give("blaze_rod", 2, bulk: "cinderwisps") }
            craft(["R"], ["R": "blaze_rod"], "blaze_powder", times: 2)
        }
        craft(["RRP"], ["R": "raw_sunderite", "P": "blaze_powder"], "sunderite_flux", times: 4)
        check(count("sunderite_flux") == 4, "deep: Raw Sunderite and Cinder Powder make Sunderite Flux (\(count("sunderite_flux")))")
        // A blast furnace set down in the courtyard: the flux refuses a plain furnace, the blast furnace makes ingots.
        if count("blast_furnace") == 0 { give("blast_furnace", 1, bulk: "iron and smooth stone") }
        let flux = id("sunderite_flux")
        check(Recipes.smelt(flux).map { !BlockEntity.allowed($0, flux, in: "furnace") && BlockEntity.allowed($0, flux, in: "blast_furnace") } ?? false,
              "deep: Sunderite Flux smelts only in a blast furnace")
        let pad = IVec3(Int(floor(yard.x)) + 3, Int(floor(yard.y)), Int(floor(yard.z)) + 3)
        // (A furnace's contents are made the first time it is opened, as Game.use does: open it once.)
        if let fp = place("blast_furnace", at: pad), case let be = world.entity(fp, .furnace) {
            be.mob = "blast_furnace"; world.blockEntities[fp] = be
            be.container[0] = ItemStack(flux, 4); inv.remove(flux, 4)
            if count("coal") < 2 { give("coal", 2, bulk: "fuel") }
            be.container[1] = ItemStack(id("coal"), 2); inv.remove(id("coal"), 2)
            let st = simSeconds
            _ = tick(40, pin: game.player.pos) { be.container[2].count >= 4 }
            check(be.container[2].count >= 4 && Items.key(be.container[2].item) == "sunderite_ingot",
                  String(format: "deep: the blast furnace makes %d Sunderite Ingots in %.0f s", be.container[2].count, simSeconds - st))
            game.inventory.add(be.container[2]); be.container[2] = .empty
        } else {
            check(false, "deep: a blast furnace placed in the courtyard (at \(pad.x),\(pad.y),\(pad.z): \(key(pad)), under it \(key(pad + IVec3(0, -1, 0))); \(why()))")
        }
        if count("sunderite_ingot") < 4 { give("sunderite_ingot", 4 - count("sunderite_ingot"), bulk: "no blast furnace") }
        if count("tnt") == 0 { give("tnt", 1, bulk: "gunpowder and sand") }
        craft(["PII", "I"], ["P": "netherite_pickaxe", "I": "sunderite_ingot"], DeepSeal.pickaxe)
        craft(["IT"], ["I": "sunderite_ingot", "T": "tnt"], "sunder_charge")
        check(count(DeepSeal.pickaxe) == 1 && count("sunder_charge") == 1 && game.advancements.contains("adventure/sunderite"),
              "deep: a Sunderite Pickaxe and a Sunder Charge crafted")

        section("deep: through the seal")
        // A shaft dug down through the hell floor to the Sealrock, walled against the lava sea (bulk).
        let hx = c.ox + 40, hz = c.oz
        _ = world.loadSync(center: V3(Float(hx), Float(DeepSeal.top), Float(hz)), radius: 2)
        for y in DeepSeal.top...(DeepSeal.top + 6) { for dz in -2...2 { for dx in -2...2 {
            let ring = max(abs(dx), abs(dz)) == 2
            world.setBlock(hx + dx, y, hz + dz, ring ? EMBERSLATE : AIR)
        } } }
        info("bulk: dug down to the Sealrock beside the keep, walled off from the lava")
        let seal = IVec3(hx, DeepSeal.top - 1, hz)
        check(key(seal) == "sealrock", "deep: the hell band's floor is Sealrock (\(key(seal)))")
        _ = hold("netherite_pickaxe")
        let duskBroke = mine(IVec3(hx + 1, DeepSeal.top - 1, hz + 1), maxSeconds: 5)
        check(!duskBroke, "deep: a Duskium pickaxe can't break Sealrock")
        _ = hold("sunder_charge")
        game.player.flying = false
        game.player.pos = V3(Float(hx) + 0.5, Float(DeepSeal.top), Float(hz) + 0.5); game.player.vel = .zero
        aim(at: center(seal))
        AimAssist.last = nil
        game.input.rightClicked = true
        frame()
        let setWhy = why()
        let fell = tick(Double(DeepSeal.chargeFuse) + 20) { self.game.player.pos.y < Float(DeepSeal.bottom) }     // (on the crust one under the seal)
        check(fell && game.advancements.contains("adventure/break_seal"), "deep: the Sunder Charge blows a shaft through the seal and the player drops through (\(setWhy); feet at \(Int(game.player.pos.y)), seal \(DeepSeal.bottom)...\(DeepSeal.top - 1))")
        // Under the seal: the lower crust, dug through with the Sunderite Pickaxe's bluntest use (any pickaxe) down to the vault roof.
        _ = hold(DeepSeal.pickaxe)
        var crust = 0
        for _ in 0..<40 where !DeepGen.inVault(game.player.pos.y) {
            let f = game.player.pos
            let cell = IVec3(Int(floor(f.x)), Int(floor(f.y - 0.05)), Int(floor(f.z)))
            if clear(cell) { game.player.flying = false; _ = tick(1); continue }
            if !carvable(cell) || !mine(cell, maxSeconds: 8) { break }
            crust += 1
            game.player.flying = false
            game.player.pos = V3(Float(cell.x) + 0.5, Float(cell.y) + 0.01, Float(cell.z) + 0.5)
            _ = tick(0.3)
        }
        info("dug \(crust) blocks of the lower crust")
        if !DeepGen.inVault(game.player.pos.y) {
            info("bulk: the rest of the lower crust; out under the vault roof")
            game.player.pos.y = Float(DeepGen.ceilingBase + 10)
        }
        let hurt0 = damageTaken
        game.player.flying = false
        let landed = tick(40) { self.game.player.onGround }
        _ = tick(1.1)
        check(landed && game.advancements.contains("adventure/ash_vault"), "deep: down into the Ash Vault (landed \(landed), \(damageTaken - hurt0) damage on the way down)")

        section("deep: the Marshal")
        let vd = Int(simd_length(V2(game.player.pos.x, game.player.pos.z)))
        info("bulk: crossed \(vd) blocks of the vault to the citadel")
        let citadel = V3(0.5, Float(DeepGen.floorBase + 1), -12.5)
        game.player.pos = citadel; game.player.vel = .zero
        _ = world.loadSync(center: citadel, radius: 6)
        _ = tick(3)
        guard let marshal = game.mobs.mobs.first(where: { $0.kind == .ashMarshal && $0.health > 0 }) else {
            check(false, "deep: the Ash Marshal holds the command bunker"); return
        }
        let guardsM = game.mobs.mobs.filter { $0 !== marshal && $0.faction == Faction.ashguard.rawValue && simd_length($0.pos - marshal.pos) < 48 }
        game.mobs.mobs.removeAll { m in guardsM.contains { $0 === m } }
        info("bulk: fought through the Marshal's Guard (\(guardsM.count) units)")
        _ = hold("netherite_sword")
        let mt = simSeconds
        swings = 0
        while marshal.health > 0 && game.mobs.mobs.contains(where: { $0 === marshal }) && swings < 260 {
            swing(at: marshal)
            swings += 1
        }
        let marshalDown = marshal.health <= 0 || !game.mobs.mobs.contains { $0 === marshal }
        check(marshalDown, String(format: "deep: the Ash Marshal falls to the sword (%d swings, %.0f s)", swings, simSeconds - mt))
        if !marshalDown { kill([marshal]) }
        _ = tick(1)
        check(game.ashStage == 1 && !game.ashVictory, "deep: the Marshal's fall starts the last battle (stage \(game.ashStage))")

        section("deep: the last battle")
        for n in 0..<3 {
            _ = tick(Double(AshFinal.breather) + 15) { self.game.lastWar.spawned }
            let wave = game.lastWar.wave
            check(game.lastWar.spawned && !wave.isEmpty, "deep: wave \(n + 1), \(AshFinal.waveNames[n]), comes in (\(wave.count) units)")
            // The nearest infantryman fought for real; the rest in bulk.
            if let foot = wave.filter({ !$0.kind.ashVehicle && $0.health > 0 }).min(by: { simd_length($0.pos - game.player.pos) < simd_length($1.pos - game.player.pos) }) {
                var s = 0
                while foot.health > 0 && game.mobs.mobs.contains(where: { $0 === foot }) && s < 40 { swing(at: foot); s += 1 }
                info(String(format: "wave %d: an Ashguard soldier fought hand to hand (%d swings, down %@, health left %.0f, %.1f blocks off)",
                            n + 1, s, foot.health <= 0 ? "true" : "false", Float(foot.health), simd_length(foot.pos - game.player.pos)))
            }
            let left = game.lastWar.wave.filter { $0.health > 0 }
            kill(left)
            info("bulk: the rest of wave \(n + 1) (\(left.count) units)")
            _ = tick(3) { self.game.ashWave == n + 1 || self.game.ashStage == 2 }
        }
        var open = 0
        for z in AshFinal.hatchZ { for x in AshFinal.hatchX where world.block(x, AshFinal.hatchY, z) == AIR { open += 1 } }
        check(game.ashStage == 2 && open == 9 && game.advancements.contains("adventure/ash_last_battle"),
              "deep: the last army beaten, the blast door in the command bunker opens (\(open)/9)")

        section("deep: the Chancellor")
        let hall = V3(8.5, Float(AshFinal.y0 + 1), 22.5)
        game.player.pos = hall; game.player.vel = .zero
        info("bulk: down the bunker stairs")
        _ = world.loadSync(center: hall, radius: 3)
        _ = tick(5) { self.game.mobs.mobs.contains { $0.kind == .ashChancellor } }
        guard let ch = game.mobs.mobs.first(where: { $0.kind == .ashChancellor && $0.health > 0 }) else {
            check(false, "deep: the Ash Chancellor waits in his study"); return
        }
        let ct = simSeconds
        let ch0 = ch.health
        swings = 0
        while ch.health > 0 && game.mobs.mobs.contains(where: { $0 === ch }) && swings < 260 {
            // His guard comes at his call: fought off as it arrives (bulk).
            let guardsC = game.mobs.mobs.filter { $0 !== ch && $0.faction == Faction.ashguard.rawValue && simd_length($0.pos - ch.pos) < 30 }
            if !guardsC.isEmpty { kill(guardsC) }
            swing(at: ch)
            swings += 1
        }
        let chDown = ch.health <= 0 || !game.mobs.mobs.contains { $0 === ch }
        check(chDown, String(format: "deep: the Ash Chancellor falls (%d swings, %.0f s; health %.0f -> %.0f, %.1f blocks off; %@)",
                                swings, simSeconds - ct, Float(ch0), Float(ch.health), simd_length(ch.pos - game.player.pos), why()))
        if !chDown { kill([ch]) }
        _ = tick(1)
        check(game.ashVictory && game.ashStage == 3 && game.creditsAsh && game.advancements.contains("adventure/ash_victory"),
              "deep: the Chancellor's death ends the war (victory, the ending)")

        section("deep: the lift home")
        game.credits = nil; game.creditsAsh = false
        let lift = V3(Float(AshWar.liftAt.x) + 0.5, Float(AshWar.liftAt.y + 1), Float(AshWar.liftAt.z) + 0.5)
        info("bulk: back up the bunker stairs to the lift")
        game.player.pos = lift; game.player.vel = .zero
        _ = world.loadSync(center: lift, radius: 2)
        let home = tick(5) { self.game.dim.dim == .overworld }
        check(home && game.deepReturn != nil, "deep: the lift in the command bunker carries the player home to the surface")
        if game.dim.dim != .overworld { game.changeDimension(to: .overworld, at: game.spawnPoint) }
    }

    // What a player brings down: Duskium tools, a sword, armour; the hell-band stage needs nothing else to start.
    func kitForDeep() {
        for n in ["netherite_pickaxe", "netherite_sword"] where count(n) == 0 { give(n, 1, bulk: "Duskium gear") }
        if game.inventory.armorPoints < 17 { wearArmor() }
    }

    func kill(_ ms: [Mob]) {
        for m in ms where m.health > 0 { m.killedByPlayer = true; m.hit(from: m.pos + V3(1, 0, 0), damage: m.health + 900) }
        frame()
    }

    // Sets a block down with a right click on the top of the floor at `at` (cleared and floored first). Returns where.
    func place(_ n: String, at: IVec3) -> IVec3? {
        guard hold(n) else { return nil }
        for dx in -1...1 { for dz in -1...3 { for dy in 0...3 { world.setBlock(at.x + dx, at.y + dy, at.z + dz, AIR) } } }
        if !Blocks.collide[Int(world.block(at.x, at.y - 1, at.z))] { world.setBlock(at.x, at.y - 1, at.z, Blocks.id("nether_bricks")) }
        game.player.flying = true
        game.player.pos = V3(Float(at.x) + 0.5, Float(at.y) + 1.5, Float(at.z) + 2.5); game.player.vel = .zero
        aim(at: V3(Float(at.x) + 0.5, Float(at.y), Float(at.z) + 0.5))
        AimAssist.last = nil            // (the block assist would keep the last block mined highlighted)
        game.input.rightClicked = true
        frame(pin: game.player.pos)
        return Blocks.key(world.block(at.x, at.y, at.z)).hasSuffix(n) || baseKey(world.block(at.x, at.y, at.z)) == n ? at : nil
    }
}
