import Foundation
import simd

// The seam between the surface and the Deep stacked under it (task 22). The surface has no bedrock floor: break through
// its lowest layer and you carry on digging at the top of the Deep (same x, z), and climb out of the Deep's top layer to
// come back up. The Ash Vault's hot updrafts slow long falls into it; below the vault floor is the molten core.
// P291: a fall through an Ember Charge's shaft carries straight on into hell (HellDrop.swift).
extension Game {
    func deepTick(_ dt: Float) {
        hellDropTick(dt)
        if dim.dim == .deep {
            sunderTick(dt); hellHints(); gatesTick(dt); ashArmyTick(dt)
            for m in mobs.mobs where m.warden { m.wardenTick(dt, self) }
        }
        guard alive, world.frame == nil, riding == nil else { return }
        let p = player.pos
        switch dim.dim {
        case .overworld where p.y < 0.5:
            // The Wardstone floor (HellGate.swift): only an Ember Charge's shaft lets you through.
            if world.block(Int(floor(p.x)), 0, Int(floor(p.z))) == WARDSTONE { break }
            crossSeam(down: true)
        case .deep where p.y >= Float(CH - 1):
            crossSeam(down: false)
        // P291 (d, Oct 15): the hell band's slow updraft drift is gone; falls there are normal speed and a landing takes
        // a tenth of the fall damage (Game.survivalTick).
        case .deep:
            // Updrafts: a long drop into the vault floats down (no fall damage), so breaking through its roof is survivable.
            // P291 (d): creative falls at the normal speed.
            if survival && DeepGen.inVault(p.y) && !player.onGround && !player.flying {
                if player.vel.y < -6 { applyEffect(.slowFalling, amp: 0, seconds: 1.5) }
                // P328 (NO TEXT): the updraft shows instead of a toast: warm air streaming up past him as he floats down.
                if effects.has(.slowFalling) && Rand.float(in: 0..<1) < 0.5 {
                    particles.smoke(at: p + V3(Rand.float(in: -1.5...1.5), Rand.float(in: -2...1), Rand.float(in: -1.5...1.5)), dark: false)
                }
            }
        default: break
        }
    }

    // Moves the player across the seam and opens a two-block pocket where they arrive (as if they had dug into it),
    // standing on solid rock. Arrival is a block or two clear of the opposite trigger, so nobody bounces back.
    func crossSeam(down: Bool) {
        let x = Int(floor(player.pos.x)), z = Int(floor(player.pos.z))
        let feet = down ? CH - 3 : 1
        let to = V3(player.pos.x, Float(feet), player.pos.z)
        // P291 (b): falling through the blasted floor keeps falling: the shaft runs on into the hell band over the
        // nearest column with solid ground at the bottom, with the fall's speed carried over. Only the nearest chunks
        // load first (no loading pause); without such ground in reach it is the pocket below as before.
        let falling = down && player.vel.y < -1 && !player.flying
        let carried = player.vel.y
        changeDimension(to: down ? .deep : .overworld, at: to, syncRadius: falling ? 2 : nil)
        if falling, let site = hellLanding(nearX: x, z: z) {
            openHellShaft(site.x, site.z, roof: site.roof)
            let at = V3(Float(site.x) + 0.5, Float(feet), Float(site.z) + 0.5)
            player.pos = at
            player.vel = V3(0, min(carried, -10), 0)
            player.airPeak = at.y
            hellDrop = HellDropState(active: true, broke: false, roof: site.roof, floor: site.floor, t: 0)
            achieve("deep_visit"); deepEntry = at
            deepVisited = true
            return
        }
        // Climbing out into the surface's Wardstone floor cuts a way up through it (the floor below stays shut).
        for y in feet...(down ? feet + 1 : max(feet + 1, HellGate.floorTop)) where world.block(x, y, z) != AIR { world.setBlock(x, y, z, AIR) }
        if !Blocks.opaque[Int(world.block(x, feet - 1, z))] { world.setBlock(x, feet - 1, z, EMBERSLATE) }
        player.pos = to
        player.vel = .zero
        player.airPeak = to.y
        if down { achieve("deep_visit"); deepEntry = to }
        if down { deepVisited = true }       // NO TEXT (P328): the arrival speaks for itself
    }
}

extension MobManager {
    // The Deep's natural spawns: the hell band spawns like the Emberdeep (tougher: depth power); the solid crusts spawn
    // nothing, and the Ash Vault belongs to the Ashguard (their garrisons come with the sites, AshWar.swift).
    func trySpawnDeep(_ game: Game) {
        guard DeepGen.inHell(game.player.pos.y) else { return }
        let n = mobs.count
        trySpawnEmberdeep(game, base: DeepGen.hellBase, height: DeepGen.hellHeight)
        for m in mobs[n...] where m.kind.hostile { m.power = MobManager.depthPower(.deep, m.pos.y) }
    }
}
