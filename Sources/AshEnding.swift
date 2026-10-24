import Foundation
import simd

// P438 (Remington, Oct 24 16:02-16:03, in the Ash Vault after the Marshal fell: "Now what? What ends the game? I need
// to be able to test that"). The game ends in the Chancellor's Bunker under the command bunker (AshFinal.swift): the
// Marshal's fall sends the last army in three waves; once it is broken the console beside the blast door lights and
// opens it; the Chancellor waits in his study at the foot of the stairs, and his death rolls the ending and opens the
// lift home. He could not tell any of that from play, and could not get back to a step to try it again.
//   in play   when the last army breaks, the Chancellor's own voice over the loudspeakers says where he is (the bunker,
//             behind the blast door), and says it again every two minutes while the door stays shut and the player is
//             in the vault. A soldier's line, not a hint box.
//   to test   /ending [army|bunker|chancellor|credits] (the command console, which he already uses) puts the war at
//             that step and the player where it happens: army, the Marshal dead and the first wave coming, at the
//             command bunker; bunker, the army broken, standing on the blast door beside the lit console; chancellor,
//             the door open, at the foot of the stairs in the guard hall; credits, the ending rolls.
extension Game {
    func endingCommand(_ a: [String]) -> [String] {
        let step = a.count > 1 ? a[1].lowercased() : "bunker"
        guard ["army", "bunker", "chancellor", "credits"].contains(step) else {
            return ["Usage: /ending army|bunker|chancellor|credits"]
        }
        if step == "credits" { creditsAsh = true; credits = 0; return ["The ending rolls"] }
        ashVictory = false
        ashWave = 0
        lastWar.wave.removeAll()
        lastWar.spawned = false
        lastWar.inBunker = 0
        lastWar.chancellorCall = 30
        // (a Chancellor left from an earlier try goes: the bunker brings its own when the player walks in)
        mobs.mobs.removeAll { $0.kind == .ashChancellor }
        let at: V3
        switch step {
        case "army":
            ashStage = 0
            ashHatchOpen = false
            at = V3(9.5, Float(AshFinal.hatchY + 1), 3.5)
        case "bunker":
            ashStage = 2
            ashHatchOpen = false
            at = V3(9.5, Float(AshFinal.hatchY + 1), 3.5)
        default:
            ashStage = 2
            ashHatchOpen = true
            at = V3(8.5, Float(AshFinal.y0 + 1), 21.5)
        }
        if dim.dim != .deep { changeDimension(to: .deep, at: at, syncRadius: 3) }
        player.pos = at
        player.vel = .zero
        player.airPeak = at.y
        if step == "bunker" || step == "chancellor" {
            // The blast door shut again for the bunker step (an earlier try left it open).
            if step == "bunker" { for z in AshFinal.hatchZ { for x in AshFinal.hatchX { world.setBlock(x, AshFinal.hatchY, z, AshFinal.door) } } }
            ashHatchTick()
        }
        if step == "army" { startLastBattle() }
        return ["The war's end, at: \(step)"]
    }

    // Once a second from lastWarTick while the army is broken and the blast door is shut.
    func chancellorCallSecond(_ s: Float) {
        guard ashStage == 2, !ashHatchOpen, !ashVictory, DeepGen.inVault(player.pos.y) else { return }
        lastWar.chancellorCall -= s
        guard lastWar.chancellorCall <= 0 else { return }
        lastWar.chancellorCall = 120
        let lines = [
            "The Chancellor, over the loudspeakers: \"Seal the bunker! Nobody opens the blast door in the command post!\"",
            "The Chancellor, over the loudspeakers: \"Let them come down to my bunker. I am waiting.\"",
            "The Chancellor, over the loudspeakers: \"Guard the console by the blast door! Shoot anyone who touches it!\"",
        ]
        lastWar.chancellorLine = (lastWar.chancellorLine + 1) % lines.count
        onToast?(lines[lastWar.chancellorLine])
        sfx(.ashSiren, 0.5, at: player.pos)
    }
}
