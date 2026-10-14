import Foundation
import simd

// D47: vault side objectives, the armoured train robbery, and boss bars on the HUD (the Quest panel draws the same
// HUD as the Mac: Renderer.buildHUD).
//   the Vault    three things to wreck in the Ash Vault before (or during) the last war, each with a lasting edge:
//                  spike the guns      break 6 Ashguard mortars: their crews fight with rifles, no more shells
//                  burn the fuel       break 10 fuel drums: the Ashguard's tanks, half-tracks and trucks crawl (60%)
//                  cut the signals     break 12 red signal lamps: the army's sightings go stale in 3 s, not 8, so
//                                      its guns lose you sooner
//                progress shows in toasts and the journal; kept with the world (TownLaw.state.vaultObj).
//   bullion      one day in three a line's train runs as a bullion train: an armoured locomotive, a guard car with
//                a gun turret and the bullion car. It won't stop at gunpoint; block the line to halt it, silence the
//                guard car (heavy rounds, explosives) and crack the bullion car for three times the takings. A big
//                crime: double the bounty and two posses.
//   boss bars    the bullion train's guard car, a gang leader (D26) and a legendary animal near you get a bar.
enum VaultObjectives {
    struct Objective { let key: String; let block: String; let need: Int; let name: String; let done: String }
    static let all: [Objective] = [
        Objective(key: "guns", block: "ash_mortar", need: 6, name: "Spike the guns",
                  done: "The Vault's mortars are spiked: their crews fight with rifles now"),
        Objective(key: "fuel", block: "ash_drum", need: 10, name: "Burn the fuel",
                  done: "The Ashguard's fuel is burned: their tanks and trucks crawl"),
        Objective(key: "signals", block: "ash_lamp", need: 12, name: "Cut the signals",
                  done: "The signal lamps are out: the Ashguard's guns lose you sooner"),
    ]

    static func count(_ k: String) -> Int { TownLaw.state.vaultObj?[k] ?? 0 }
    static func done(_ k: String) -> Bool {
        guard let o = all.first(where: { $0.key == k }) else { return false }
        return count(k) >= o.need
    }
    static var fuelFactor: Float { done("fuel") ? 0.6 : 1 }
    static var spotWindow: Double { done("signals") ? 3 : 8 }

    // Game.breakBlock, in the Deep.
    static func broke(_ g: Game, _ p: IVec3, _ b: BlockID) {
        guard g.dim.dim == .deep, DeepGen.inVault(Float(p.y)) else { return }
        let k = Blocks.key(Blocks.groupBase[Int(b)])
        guard let o = all.first(where: { $0.block == k }) else { return }
        let n = count(o.key)
        guard n < o.need else { return }
        var m = TownLaw.state.vaultObj ?? [:]
        m[o.key] = n + 1
        TownLaw.state.vaultObj = m
        if n + 1 >= o.need {
            g.sfx(.levelUp, 0.8)
            g.onToast?(o.done)
            g.logMessage("The Vault: " + o.done + ".")
        } else if n == 0 || (n + 1) % 3 == 0 {
            g.onToast?("\(o.name): \(n + 1) of \(o.need)")
        }
    }

    // MARK: The bullion train

    static func bullionDay(_ id: Int64, _ day: Int) -> Bool {
        hashf(Int(truncatingIfNeeded: id), day, 0xB011, 0x5EED) < 1.0 / 3.0
    }
}

extension Game {
    // Renderer.buildHUD: the D47 bars (name, fraction, colour).
    func huntedBars() -> [(String, Float, V4)] {
        var out: [(String, Float, V4)] = []
        let p = player.pos
        for tr in Trains.trains.values where tr.bullion && tr.cars.count > 1 {
            let gc = tr.cars[1]
            if gc.health > 0 && simd_length(gc.pos - p) < 64 { out.append(("Bullion Train Guard Car", Float(gc.health) / 160, V4(0.85, 0.7, 0.2, 1))) }
        }
        for m in mobs.mobs where m.health > 0 && simd_length(m.pos - p) < 48 {
            if let gg = GangLeaders.isLeader(m) {
                out.append((gg.leader, Float(m.health) / Float(m.spec.health * 2), V4(0.75, 0.3, 0.2, 1)))
            } else if m.legend >= 0 && m.legend < Hunting.legends.count && !m.carcass {
                let l = Hunting.legends[Int(m.legend)]
                out.append((l.name.capitalizedFirst, Float(m.health) / Float(l.health), V4(0.5, 0.75, 0.35, 1)))
            }
            if out.count >= 3 { break }
        }
        return out
    }
}
