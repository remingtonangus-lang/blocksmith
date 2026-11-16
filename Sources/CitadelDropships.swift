import Foundation
import simd

// Ledger 206 (Nov 15 21:09:53, by a citadel under his crawler's guns: "Drop ships keep spawning from out of nowhere.
// That shouldn't happen. There should be a fixed amount of drop ships... And they should reside on base prior"): a
// citadel called a dropship in from 170-400 blocks out, built in the air past the fog, twice a lockdown; and every heavy
// noise far out (each crawler shell) called one more, with no count at all. Now a citadel has two dropships, standing
// on two concrete pads outside its walls from the time he comes within 260 blocks. A lockdown or a far blast launches
// the next one off its pad (it flies the same flight from there); a pad's dropship that is shot up, or flown off by
// him, is spent as well. Two in all, for the citadel's life: none is ever built in the air. BS_OLDDROPSHIPS=1: as before.
enum CitadelDrops {
    static let old = Env.all["BS_OLDDROPSHIPS"] == "1"
    static let fleet = 2
    static let near: Float = 260, far: Float = 520
    static let halfX = 7, halfZ = 11                    // the pad round a dropship (13 x 20 at yaw 0 or a half turn)
    static var parkedBuilt = 0, launched = 0, padsLaid = 0      // (checks)
    static var padKey: String { Blocks.has("gray_concrete") ? "gray_concrete" : "smooth_stone" }

    // Two flat dry spots outside the walls, clear of the gate road and the motor pool (south), the flattest first.
    static func findPads(_ w: World, _ r: BaseRecord) -> [[Float]] {
        var cand: [(Float, Int, Int, Int)] = []          // (score, x, z, top)
        let c = r.centre
        for rad in [74, 86, 98, 110] {
            for k in 0..<24 {
                let a = Float(k) * .pi / 12
                let x = Int(c.x + sinf(a) * Float(rad)), z = Int(c.z - cosf(a) * Float(rad))
                if abs(x - r.cx) < 18 && z > r.cz + 30 { continue }                // the gate road and the motor pool
                guard w.isLoaded(x - halfX - 1, z - halfZ - 1), w.isLoaded(x + halfX + 1, z + halfZ + 1) else { continue }
                var lo = Int.max, hi = Int.min, bad = false
                for dz in stride(from: -halfZ, through: halfZ, by: 2) { for dx in stride(from: -halfX, through: halfX, by: 2) where !bad {
                    let gy = BuildersGrounds.groundY(w, x + dx, z + dz)
                    lo = min(lo, gy); hi = max(hi, gy)
                    if Blocks.isLiquid(w.block(x + dx, gy + 1, z + dz)) { bad = true }
                    for y in (gy + 1)...(gy + 12) {
                        let b = w.block(x + dx, y, z + dz)
                        if b != AIR && !Blocks.isPlant(b) && Blocks.key(Blocks.groupBase[Int(b)]) != "snow" { bad = true; break }    // trees, buildings
                    }
                } }
                if bad || hi - lo > 3 { continue }
                cand.append((Float(hi - lo) + Float(rad) / 100, x, z, hi))
            }
        }
        cand.sort { $0.0 < $1.0 }
        var out: [[Float]] = []
        for (_, x, z, top) in cand where out.count < fleet {
            if out.contains(where: { abs(Int($0[0]) - x) < 2 * halfX + 4 && abs(Int($0[2]) - z) < 2 * halfZ + 4 }) { continue }
            let yaw: Float = Float(z) > c.z ? 0 : .pi            // nose toward the citadel (its forward is -z)
            out.append([Float(x) + 0.5, Float(top + 2), Float(z) + 0.5, yaw])
        }
        return out
    }

    // The pad: concrete from the ground up to one over the highest ground cell under it, what grows on it cleared.
    static func lay(_ w: World, _ pad: [Float]) {
        let x0 = Int(floorf(pad[0])), z0 = Int(floorf(pad[2])), top = Int(pad[1]) - 1
        let k = Blocks.id(padKey)
        for dz in -(halfZ + 1)...(halfZ + 1) { for dx in -(halfX + 1)...(halfX + 1) {
            let x = x0 + dx, z = z0 + dz
            let gy = BuildersGrounds.groundY(w, x, z)
            if gy < top { for y in (gy + 1)...top { _ = w.setBlockAsync(x, y, z, k) } }
            for y in (top + 1)...(top + 12) where w.block(x, y, z) != AIR { _ = w.setBlockAsync(x, y, z, AIR) }
        } }
        padsLaid += 1
    }
}

extension Game {
    // Each second at a citadel (CapitalBases): its pads found and laid once he comes near, a dropship standing on every
    // pad not spent, put away when he goes far (the hulls aren't saved; built again when he comes back).
    func baseDropPads(_ r: inout BaseRecord, _ b: BaseWatch) {
        guard !CitadelDrops.old, r.cleared != true, r.broken != true else { return }
        let dist = simd_length(V2(player.pos.x - r.centre.x, player.pos.z - r.centre.z))
        if r.dropPads == nil || r.dropPads?.isEmpty == true && dist < CitadelDrops.near && Int(clock) % 30 == 0 {
            guard dist < CitadelDrops.near else { return }
            let pads = CitadelDrops.findPads(world, r)
            r.dropPads = pads
            r.dropSpent = Array(repeating: false, count: pads.count)
            for p in pads { CitadelDrops.lay(world, p) }
            b.note("\(r.key) dropship pads: \(pads.map { "\(Int($0[0])),\(Int($0[2]))" }.joined(separator: " "))")
        }
        guard let pads = r.dropPads, !pads.isEmpty else { return }
        var spent = r.dropSpent ?? Array(repeating: false, count: pads.count)
        if spent.count < pads.count { spent += Array(repeating: false, count: pads.count - spent.count) }
        var ids = b.dropIds[r.key] ?? [:]
        for (i, pd) in pads.enumerated() where !spent[i] && i < CitadelDrops.fleet {
            if let id = ids[i] {
                guard let s = world.ships.list.first(where: { $0.id == id }) else {
                    // gone from the world with him near: shot to pieces
                    if dist < CitadelDrops.near { spent[i] = true; ids[i] = nil; b.note("\(r.key) dropship \(i) on its pad lost") }
                    else { ids[i] = nil }
                    continue
                }
                if s.wrecked || s.captured || world.ships.pilot === s {
                    spent[i] = true; ids[i] = nil
                    b.note("\(r.key) dropship \(i) on its pad \(s.captured || world.ships.pilot === s ? "taken" : "wrecked")")
                    continue
                }
                if dist > CitadelDrops.far { world.ships.remove(s); ids[i] = nil }
                continue
            }
            let pad = V3(pd[0], pd[1], pd[2])
            guard dist < CitadelDrops.near, world.isLoaded(Int(pad.x), Int(pad.z)) else { continue }
            let s = world.ships.parkDropship(faction: .steelhold, pad: pad, yaw: pd[3])
            ids[i] = s.id
            CitadelDrops.parkedBuilt += 1
            b.note("\(r.key) dropship \(i) parked on its pad")
        }
        r.dropSpent = spent
        b.dropIds[r.key] = ids
    }

    // The citadel sends the next dropship standing on its pad (a lockdown's reinforcements, a far blast); false with
    // none there (two in all).
    func baseLaunchDrop(_ r: inout BaseRecord, _ b: BaseWatch, to p: V3) -> Bool {
        guard r.dropships < CitadelDrops.fleet, let pads = r.dropPads else { return false }
        var spent = r.dropSpent ?? Array(repeating: false, count: pads.count)
        var ids = b.dropIds[r.key] ?? [:]
        for i in pads.indices where i < spent.count && !spent[i] {
            guard let id = ids[i], let s = world.ships.list.first(where: { $0.id == id }) else { continue }
            guard world.ships.launchParked(s, to: p, game: self) else { continue }
            spent[i] = true; ids[i] = nil
            r.dropSpent = spent
            b.dropIds[r.key] = ids
            r.dropships += 1
            CitadelDrops.launched += 1
            if simd_length(player.pos - s.pos) < 200 { onToast?("A Capital Dropship lifts off its pad") }
            return true
        }
        return false
    }
}
