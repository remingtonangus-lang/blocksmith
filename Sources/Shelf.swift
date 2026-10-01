import Foundation
import simd

// Chiseled bookshelves (6 book slots picked by where the front is clicked) and decorated pots
// (hold one stack; items go in one at a time).
extension BlockRegistry {
    func registerShelf() {
        var d = BlockDef("chiseled_bookshelf", "Chiseled Bookshelf")
        d.tex = ["chiseled_bookshelf_side", "chiseled_bookshelf_side", "chiseled_bookshelf_top", "chiseled_bookshelf_top",
                 "chiseled_bookshelf_side", "chiseled_bookshelf_side"]
        d.hardness = 1.5; d.tool = .axe; d.sound = .wood
        _ = addFacing(d, front: "chiseled_bookshelf_empty")
    }
}

extension TextureGen {
    static func shelfPainters(_ p: inout [String: Painter]) {
        p["chiseled_bookshelf_side"] = { x, y in hex(0xA2824E, (y == 0 || y == 15 || x == 0 || x == 15) ? 0.7 : 0.9 + 0.1 * r(x, y, 1400)) }
        p["chiseled_bookshelf_top"] = { x, y in hex(0xA2824E, (x == 0 || y == 0 || x == 15 || y == 15) ? 0.7 : 0.95 + 0.05 * r(x, y, 1401)) }
        p["chiseled_bookshelf_empty"] = { x, y in
            let frame = x == 0 || x == 15 || y == 0 || y == 15 || y == 7 || y == 8 || x == 5 || x == 10
            return frame ? hex(0xA2824E, 0.85 + 0.1 * r(x, y, 1402)) : hex(0x2A1E12, 0.9 + 0.1 * r(x, y, 1403))
        }
    }
}

enum Shelf {
    static let bookKeys: Set<String> = ["book", "written_book", "writable_book", "enchanted_book", "knowledge_book"]
    static func color(_ k: String, _ i: Int) -> V3 {
        switch k {
        case "enchanted_book": return V3(0.55, 0.25, 0.65)
        case "written_book", "writable_book": return V3(0.35, 0.22, 0.12)
        default: return [V3(0.55, 0.2, 0.18), V3(0.2, 0.35, 0.55), V3(0.25, 0.45, 0.25), V3(0.6, 0.5, 0.25)][i % 4]
        }
    }
}

extension Game {
    func useShelf(_ p: IVec3) {
        guard let t = target, t.hit == p else { return }
        let b = world.block(p.x, p.y, p.z)
        let f = Int(b - Blocks.groupBase[Int(b)])
        let front = [IVec3(0, 0, -1), IVec3(0, 0, 1), IVec3(-1, 0, 0), IVec3(1, 0, 0)][f]
        guard t.normal == front else { return }
        let be = world.blockEntities[p] ?? BlockEntity(.shelf)
        world.blockEntities[p] = be
        let hp = hitPoint(t) - V3(Float(p.x), Float(p.y), Float(p.z))
        let u: Float = [1 - hp.x, hp.x, hp.z, 1 - hp.z][f]
        let slot = (hp.y >= 0.5 ? 0 : 3) + max(0, min(2, Int(u * 3)))
        be.level = slot + 1
        let c = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)
        if be.container[slot].isEmpty {
            guard Shelf.bookKeys.contains(Items.key(held.item)) else { return }
            be.container[slot] = held.with(count: 1)
            if survival { consumeHeld() }
            sfx(.itemFrameAdd, 0.6, at: c)
        } else {
            let s = be.container[slot]
            be.container[slot] = .empty
            let rest = inventory.add(s)
            if !rest.isEmpty { dropItem(rest) }
            sfx(.itemFrameRemove, 0.6, at: c)
        }
        swing = 1
        world.redstone.wakeAround(p)
    }

    // Decorated pots take one item per click, up to a stack of one kind.
    func usePot(_ p: IVec3) {
        let be = world.blockEntities[p] ?? BlockEntity(.pot)
        world.blockEntities[p] = be
        let h = held
        let c = V3(Float(p.x) + 0.5, Float(p.y) + 0.8, Float(p.z) + 0.5)
        guard !h.isEmpty else { return }
        let cur = be.container[0]
        if cur.isEmpty || (cur.stacks(with: h) && cur.count < cur.maxStack) {
            be.container[0] = cur.isEmpty ? h.with(count: 1) : cur.with(count: cur.count + 1)
            if survival { consumeHeld() }
            sfx(.potInsert, 0.7, at: c)
            particles.smoke(at: c, dark: false)
        } else {
            sfx(.hit(.stone), 0.5, at: c)         // full / different item: the pot just wobbles
        }
        swing = 1
    }

    func writeShelves(_ wr: inout EntityWriter, eye: V3) {
        let tex = Int(Tex.id("smoke"))
        for (p, be) in world.blockEntities where be.kind == .shelf {
            let c = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5) - eye
            guard simd_length(c) < 32 else { continue }
            let b = world.block(p.x, p.y, p.z)
            let f = Int(b - Blocks.groupBase[Int(b)])
            let n = [V3(0, 0, -1), V3(0, 0, 1), V3(-1, 0, 0), V3(1, 0, 0)][min(3, f)]
            let left = [V3(1, 0, 0), V3(-1, 0, 0), V3(0, 0, -1), V3(0, 0, 1)][min(3, f)]
            let l = world.lightAt(p.x + Int(n.x), p.y, p.z + Int(n.z))
            let light = max(0.2, max(Float(l.sky) / 15 * daylight, Float(l.block) / 15))
            for i in 0..<6 where !be.container[i].isEmpty {
                let col = Float(i % 3), top = i < 3
                let center = c + n * 0.44 + left * (0.5 - (col + 0.5) / 3) + V3(0, top ? 0.25 : -0.25, 0)
                let k = Items.key(be.container[i].item)
                wr.orientedBox(center - left * 0.0, left * 0.13, V3(0, 0.19, 0), n * 0.05, layer: tex, color: V4(Shelf.color(k, i) * light, 1))
            }
        }
    }
}
