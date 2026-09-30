import Foundation
import simd

// Beacons: a pyramid of iron/gold/emerald/diamond/duskium blocks (1-4 layers) under a beacon with a
// clear view of the sky powers it. Paying an ingot, emerald, diamond or duskium ingot picks the
// powers: speed/haste (1+), resistance/jump boost (2+), strength (3+), and at 4 layers regeneration
// or level II of the primary. Every 4 s players within 10 + 10*layers blocks get (9 + 2*layers) s.
enum Beacons {
    static let bases: Set<String> = ["iron_block", "gold_block", "emerald_block", "diamond_block", "netherite_block"]
    static let payments: Set<String> = ["iron_ingot", "gold_ingot", "emerald", "diamond", "netherite_ingot"]
    static let tiers: [[Effect]] = [[.speed, .haste], [.resistance, .jumpBoost], [.strength]]

    static func levels(_ w: World, _ p: IVec3) -> Int {
        var lvl = 0
        for l in 1...4 {
            let y = p.y - l
            guard y >= 0 else { break }
            for dz in -l...l { for dx in -l...l {
                if !bases.contains(Blocks.key(w.block(p.x + dx, y, p.z + dz))) { return lvl }
            } }
            lvl = l
        }
        return lvl
    }

    // Beam needs every block above to let light through.
    static func skyClear(_ w: World, _ p: IVec3) -> Bool {
        var y = p.y + 1
        while y < CH {
            let b = w.block(p.x, y, p.z)
            if b != AIR && Blocks.opaque[Int(b)] && Blocks.key(b) != "bedrock" { return false }
            y += 1
        }
        return true
    }
}

extension Game {
    // Every 80 ticks: recompute levels and apply the chosen powers.
    func beaconTick() {
        for (p, be) in world.blockEntities where be.kind == .beacon {
            let lvl = Beacons.levels(world, p)
            be.level = Beacons.skyClear(world, p) ? lvl : 0
            guard be.level > 0, let prim = Effect.named(be.mob) else { continue }
            let range = Float(10 + 10 * be.level)
            let c = V3(Float(p.x) + 0.5, Float(p.y), Float(p.z) + 0.5)
            guard abs(player.pos.x - c.x) <= range, abs(player.pos.z - c.z) <= range, player.pos.y >= c.y - range else { continue }
            let secs = Float(9 + 2 * be.level)
            let sec = Effect.named(be.secondary)
            let amp = be.level >= 4 && sec == prim ? 1 : 0
            applyEffect(prim, amp: amp, seconds: secs, ambient: true)
            if be.level >= 4, let s = sec, s != prim { applyEffect(s, amp: 0, seconds: secs, ambient: true) }
        }
    }

    // Beams: vertical light columns for powered beacons.
    func writeBeams(_ wr: inout EntityWriter, eye: V3) {
        let layer = Int(Tex.id("smoke"))
        let t = Float(clock)
        for (p, be) in world.blockEntities where be.kind == .beacon && be.level > 0 {
            let base = V3(Float(p.x) + 0.5, Float(p.y) + 1, Float(p.z) + 0.5) - eye
            let top = V3(base.x, Float(CH) - eye.y, base.z)
            if simd_length(V2(base.x, base.z)) > Float(world.renderDistance * CS) { continue }
            for k in 0..<2 {
                let a = t * 0.6 + Float(k) * .pi / 2
                let r = V3(cosf(a), 0, sinf(a)) * (k == 0 ? 0.18 : 0.3)
                let col = k == 0 ? V4(1.6, 1.8, 1.9, 1) : V4(0.7, 0.85, 1.0, 0.45)
                wr.quad([base - r, base + r, top + r, top - r], [V2(0.4, 0.4), V2(0.6, 0.4), V2(0.6, 0.6), V2(0.4, 0.6)], layer, col)
                let r2 = V3(-r.z, 0, r.x)
                wr.quad([base - r2, base + r2, top + r2, top - r2], [V2(0.4, 0.4), V2(0.6, 0.4), V2(0.6, 0.6), V2(0.4, 0.6)], layer, col)
            }
        }
    }
}

final class BeaconMenu: Menu {
    let pos: IVec3
    let be: BlockEntity
    let pay = ItemContainer(1)
    var primary: Effect?
    var secondary: Effect?

    // Buttons: 0-4 primary powers, 5 regeneration, 6 primary II, 7 confirm.
    static let primaryButtons: [(Effect, Int)] = [(.speed, 1), (.haste, 1), (.resistance, 2), (.jumpBoost, 2), (.strength, 3)]

    init(game: Game, at p: IVec3, entity: BlockEntity) {
        pos = p
        be = entity
        primary = Effect.named(entity.mob)
        secondary = Effect.named(entity.secondary)
        super.init("Beacon", game: game)
        width = 230
        height = 219
        for (i, _) in BeaconMenu.primaryButtons.enumerated() {
            let row = [0, 0, 1, 1, 2][i], col = [0, 1, 0, 1, 0][i]
            let b = MenuSlot(53 + col * 25, 22 + row * 25, nil, 0, .button(i))
            b.w = 20; b.h = 20
            slots.append(b)
        }
        for (i, x) in [(5, 164), (6, 189)] {
            let b = MenuSlot(x, 47, nil, 0, .button(i))
            b.w = 20; b.h = 20
            slots.append(b)
        }
        let ok = MenuSlot(164, 107, nil, 0, .button(7))
        ok.w = 20; ok.h = 20
        slots.append(ok)
        let paySlot = MenuSlot(136, 110, pay, 0)
        paySlot.filter = { Beacons.payments.contains(Items.key($0.item)) }
        paySlot.limit = 1
        slots.append(paySlot)
        addPlayerInventory(y: 137, x: 36)
        showInventoryLabel = false
        be.level = Beacons.levels(game.world, p)
    }

    func available(_ i: Int) -> Bool {
        if i < 5 { return be.level >= BeaconMenu.primaryButtons[i].1 }
        return be.level >= 4 && primary != nil
    }

    override func buttonPressed(_ i: Int) {
        guard i == 7 || available(i) else { return }
        switch i {
        case 0..<5: primary = BeaconMenu.primaryButtons[i].0
        case 5: secondary = .regeneration
        case 6: secondary = primary
        default:
            guard !pay[0].isEmpty, let p = primary else { return }
            pay[0] = .empty
            be.mob = p.key
            be.secondary = secondary?.key ?? ""
            game.sfx(.enchant, 0.8)
            game.closeMenu()
        }
    }

    override func onClose() {
        if !pay[0].isEmpty {
            let rest = game.inventory.add(pay[0]); if !rest.isEmpty { game.dropItem(rest) }
            pay[0] = .empty
        }
    }
}
