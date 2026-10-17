import Foundation
import simd

// P318 (Oct 15 19:10, rewritten 19:39: NO TEXT). The Ash Vault's goals are what a soldier would do, found by looking:
//   the blast door  a console stands against the command bunker's east wall beside the hatch, a copper lamp on it.
//                   The lamp is dark while the war goes on (using the console then gives a dead clunk and a spark);
//                   once the last army is broken it lights, and using it grinds the blast door open (saved:
//                   Game.ashHatchOpen). Vaults saved before it get the console placed when the bunker is near.
//   the guns        a mortar has a breech handle at its foot: pulling it (use) spikes the tube: a clang, smoke, the
//                   tube left split. A crew with no whole tube beside it fights with its rifles.
//   the fuel        a fuel drum has a brass bung on top: put a flame to it (flint and steel, a fire charge or a
//                   torch in hand) and it goes up in a burst of fire.
// Each still counts toward the Vault's lasting edges (VaultObjectives), with no text: the old tally pop-ups, the
// HUD line and the Greywall bases' objective lists are gone.
enum AshSabotage {
    static let consoleAt = IVec3(11, AshFinal.hatchY + 1, 3)
    static let lampAt = IVec3(11, AshFinal.hatchY + 2, 3)
    static let igniters: Set<String> = ["flint_and_steel", "fire_charge", "torch", "soul_torch"]
}

extension Game {
    // Game.interact, before the console's radio: the hatch console, a mortar's breech, a drum's bung.
    func ashBaseUse(_ p: IVec3) -> Bool {
        guard dim.dim == .deep else { return false }
        let id = world.block(p.x, p.y, p.z)
        let k = Blocks.key(Blocks.groupBase[Int(id)])
        let at = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)
        if (p == AshSabotage.consoleAt && k == "command_console") || (p == AshSabotage.lampAt && k == "redstone_lamp") {
            ashHatchUse(at)
            return true
        }
        if k == "ash_mortar" && DeepGen.inVault(Float(p.y)) {
            world.setBlock(p.x, p.y, p.z, Blocks.id("ash_mortar_spiked"))
            sfx(.lever, 0.9, at: at)
            sfx(.bulletImpact(.metal), 1.1, at: at)
            sfx(.gun(8), 0.6, at: at)
            for _ in 0..<6 { particles.smoke(at: at + V3(Rand.float(in: -0.2...0.2), 0.6, Rand.float(in: -0.2...0.2))) }
            VaultObjectives.broke(self, p, id)
            return true
        }
        if k == "ash_drum" && DeepGen.inVault(Float(p.y)) && AshSabotage.igniters.contains(Items.key(held.item)) {
            sfx(.fizz, 0.8, at: at)
            world.setBlock(p.x, p.y, p.z, AIR)
            VaultObjectives.broke(self, p, id)
            if Items.key(held.item) == "fire_charge" { consumeHeld() } else if Items.key(held.item) == "flint_and_steel" { damageHeld(1) }
            Explosion.explode(at: at, power: 2.2, game: self, fire: true)
            return true
        }
        return false
    }

    func ashHatchUse(_ at: V3) {
        guard ashStage >= 2 else {
            // Locked: the lever throws and drops back, a dead clunk, a spark off the panel, and the panel's refusal
            // buzzer (P348 c).
            sfx(.dispenseFail, 0.9, at: at)
            sfx(.gun(10), 0.5, at: at)
            sfx(.lever, 0.5, at: at)
            particles.add(Particle(pos: at + V3(0, 0.4, 0), vel: V3(0, 1.5, 0), life: 0.15, maxLife: 0.15, layer: Int(Tex.id("smoke")),
                                   uv0: V2(0, 0), uvSize: 1, size: 0.06, gravity: 6, color: V3(2.2, 1.6, 0.6), collide: false, glow: true))
            return
        }
        sfx(.lever, 1.0, at: at)
        guard !ashHatchOpen else { return }
        ashHatchOpen = true
        let door = V3(8.5, Float(AshFinal.hatchY) + 0.5, 3.5)
        sfx(.pistonExtend, 1.0, at: door)
        sfx(.gun(14), 1.2, at: door)
        sfx(.ashSiren, 1.0, at: door)                    // P348 (c): the alarm wails as the door grinds open
        addShake(0.35)
        ashHatchTick()
    }

    // Once a second in the Deep (lastWarTick): the console and its lamp stand by the hatch (placed in vaults saved
    // before them), the lamp lit once the door can open, and an opened door stays open.
    func ashHatchTick() {
        let c = AshSabotage.consoleAt, l = AshSabotage.lampAt
        guard world.isLoaded(c.x, c.z), world.isLoaded(AshFinal.hatchX.lowerBound, AshFinal.hatchZ.lowerBound),
              world.isLoaded(AshFinal.hatchX.upperBound, AshFinal.hatchZ.upperBound),
              simd_length_squared(player.pos - V3(Float(c.x), Float(c.y), Float(c.z))) < 96 * 96 else { return }
        let console = Blocks.id("command_console")
        if world.block(c.x, c.y, c.z) == AIR { world.setBlock(c.x, c.y, c.z, console) }
        let lit = ashStage >= 2
        let lamp = Blocks.id(lit ? "redstone_lamp[lit]" : "redstone_lamp")
        let now = world.block(l.x, l.y, l.z)
        if now != lamp && (now == AIR || Blocks.key(Blocks.groupBase[Int(now)]) == "redstone_lamp") {
            if lit && now != AIR { sfx(.lever, 0.7, at: V3(Float(l.x) + 0.5, Float(l.y) + 0.5, Float(l.z) + 0.5)) }
            world.setBlock(l.x, l.y, l.z, lamp)
        }
        // P348 (c): read by looking: while the war goes on the panel spits a red spark now and then (dead, locked);
        // once the door can open, amber light pulses over the console and the hatch's corners until it is used.
        let top = V3(Float(c.x) + 0.5, Float(c.y) + 1.2, Float(c.z) + 0.5)
        if !lit {
            if Rand.float(in: 0..<1) < 0.5 {
                particles.add(Particle(pos: top, vel: V3(Rand.float(in: -0.6...0.6), 1.2, Rand.float(in: -0.6...0.6)), life: 0.25, maxLife: 0.25,
                                       layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1, size: 0.07, gravity: 6,
                                       color: V3(2.4, 0.3, 0.2), collide: false, glow: true))
            }
        } else if !ashHatchOpen {
            let corners = [top, V3(7.0, Float(AshFinal.hatchY) + 1.1, 2.0), V3(10.0, Float(AshFinal.hatchY) + 1.1, 2.0),
                           V3(7.0, Float(AshFinal.hatchY) + 1.1, 5.0), V3(10.0, Float(AshFinal.hatchY) + 1.1, 5.0)]
            for q in corners {
                particles.add(Particle(pos: q, vel: V3(0, 0.25, 0), life: 0.9, maxLife: 0.9, layer: Int(Tex.id("smoke")), uv0: V2(0, 0),
                                       uvSize: 1, size: 0.16, gravity: 0, color: V3(2.6, 1.5, 0.35), collide: false, glow: true))
            }
            sfx(.click, 0.25, at: top)
        }
        guard ashHatchOpen else { return }
        for z in AshFinal.hatchZ { for x in AshFinal.hatchX where world.block(x, AshFinal.hatchY, z) == AshFinal.door {
            world.setBlock(x, AshFinal.hatchY, z, AIR)
        } }
    }

    // A mortar crew needs a whole tube within 3 blocks to fire (a spiked or broken one leaves it its rifles).
    func ashTubeNear(_ p: V3) -> Bool {
        let tube = Blocks.id("ash_mortar")
        let x0 = Int(floorf(p.x)), y0 = Int(floorf(p.y)), z0 = Int(floorf(p.z))
        for dy in -1...1 { for dz in -3...3 { for dx in -3...3 where world.block(x0 + dx, y0 + dy, z0 + dz) == tube { return true } } }
        return false
    }
}
