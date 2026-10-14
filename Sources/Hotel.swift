import Foundation
import simd

// D19 hotel rooms over the saloon. The barkeep lets rooms and draws baths:
//   a room for the night   $3: you sleep upstairs. Full health, the night passes (from dusk on: you wake at sunrise),
//                          your respawn point is set here, and the game is saved.
//   a hot bath             $1: the blood and the road wash off (townsfolk stop remarking on it), poison and hunger
//                          pangs go, and you come out warm (regeneration, 10 s).
enum Hotel {
    static var nights = 0, baths = 0                  // (tests)

    static func room(_ g: Game, _ m: Mob) -> String {
        g.health = g.maxHealth
        g.spawnPoint = g.player.pos
        g.anchorSpawn = nil
        let f = g.dayFraction
        var slept = false
        if Game.canSleep(f) || f > 0.45 {
            // To the next sunrise.
            let day = (g.time / DAY_LENGTH).rounded(.down)
            g.time = (day + 1) * DAY_LENGTH
            slept = true
        }
        g.saveNow(background: true)
        nights += 1
        g.sfx(.doorOpen, 0.5)
        return slept ? "You sleep well upstairs and wake at sunrise. Game saved." : "You rest a spell in a room upstairs. Game saved."
    }

    static func bath(_ g: Game) -> String {
        Deeds.blood = 0
        Deeds.person = 0
        g.effects.remove(.poison)
        g.effects.remove(.hunger)
        g.effects.remove(.nausea)
        g.applyEffect(.regeneration, amp: 0, seconds: 10)
        baths += 1
        g.sfx(.splash, 0.6)
        return "A hot bath. You come out clean and warm."
    }
}
