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
        // Wooden shelves: a back board and a ledge; three items stand on the ledge (Game.useDisplayShelf).
        for w in BlockRegistry.doorWoods where has("\(w)_planks") {
            let n = "\(w)_shelf"
            let backs = [Box(0, 0, 12, 16, 16, 16), Box(0, 0, 0, 16, 16, 4), Box(12, 0, 0, 16, 16, 16), Box(0, 0, 0, 4, 16, 16)]
            let ledges = [Box(0, 0, 4, 16, 2, 12), Box(0, 0, 4, 16, 2, 12), Box(4, 0, 0, 12, 2, 16), Box(4, 0, 0, 12, 2, 16)]
            let tops = [Box(0, 14, 8, 16, 16, 12), Box(0, 14, 4, 16, 16, 8), Box(8, 14, 0, 12, 16, 16), Box(4, 14, 0, 8, 16, 16)]
            for (k, dir) in ["north", "south", "west", "east"].enumerated() {
                var s = BlockDef(k == 0 ? n : "\(n)[\(dir)]", "\(BlockRegistry.woodName(w)) Shelf")
                s.tex = ["\(w)_planks"]; s.render = .model; s.opaque = false; s.boxes = [backs[k], ledges[k], tops[k]]
                s.hardness = 2; s.tool = .axe; s.sound = .wood; s.group = n; s.hidden = k != 0; s.skyStop = false
                add(s)
            }
        }
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

    // Wooden shelf: the front holds three stacks, picked by where it's clicked; using an item swaps it with that
    // slot (an empty hand takes the slot's stack).
    func useDisplayShelf(_ p: IVec3) {
        guard let t = target, t.hit == p else { return }
        let b = world.block(p.x, p.y, p.z)
        let f = min(3, Int(b - Blocks.groupBase[Int(b)]))
        // Powered: the shelf (with up to two more of the same facing beside it, left to right) swaps everything it holds
        // with the hotbar, three slots per shelf from the first hotbar slot.
        if world.redstone.received(p) > 0 {
            let leftV = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, -1), IVec3(0, 0, 1)][f]
            func sameShelf(_ q: IVec3) -> Bool { world.block(q.x, q.y, q.z) == b }
            var first = p
            var n = 1
            while n < 3 && sameShelf(first + leftV) { first = first + leftV; n += 1 }
            var row: [IVec3] = []
            var q = first
            while row.count < 3 && sameShelf(q) { row.append(q); q = q - leftV }
            var k = 0
            for sp in row {
                let sbe = world.blockEntities[sp] ?? BlockEntity(.display)
                world.blockEntities[sp] = sbe
                for slot in 0..<3 {
                    let tmp = sbe.container[slot]
                    sbe.container[slot] = inventory.main[k]
                    inventory.main[k] = tmp
                    k += 1
                }
            }
            sfx(.itemFrameAdd, 0.7, at: V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5))
            swing = 1
            return
        }
        let be = world.blockEntities[p] ?? BlockEntity(.display)
        world.blockEntities[p] = be
        let hp = hitPoint(t) - V3(Float(p.x), Float(p.y), Float(p.z))
        let u: Float = [1 - hp.x, hp.x, hp.z, 1 - hp.z][f]
        let slot = max(0, min(2, Int(u * 3)))
        let c = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)
        let cur = be.container[slot], h = held
        if cur.isEmpty && h.isEmpty { return }
        be.container[slot] = h
        inventory.held = cur
        sfx(h.isEmpty ? .itemFrameRemove : .itemFrameAdd, 0.6, at: c)
        swing = 1
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
        // Wooden shelves: three items standing on the ledge, facing out.
        for (p, be) in world.blockEntities where be.kind == .display {
            let c = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5) - eye
            guard simd_length(c) < 40 else { continue }
            let b = world.block(p.x, p.y, p.z)
            let f = min(3, Int(b - Blocks.groupBase[Int(b)]))
            let n = [V3(0, 0, -1), V3(0, 0, 1), V3(-1, 0, 0), V3(1, 0, 0)][f]
            let left = [V3(1, 0, 0), V3(-1, 0, 0), V3(0, 0, -1), V3(0, 0, 1)][f]
            let l = world.lightAt(p.x + Int(n.x), p.y, p.z + Int(n.z))
            let light = max(0.2, max(Float(l.sky) / 15 * daylight, Float(l.block) / 15))
            for i in 0..<3 where !be.container[i].isEmpty {
                let item = be.container[i]
                let along: Float = 0.5 - (Float(i) + 0.5) / 3
                let center: V3 = c + n * 0.05 + left * along + V3(0, -0.12, 0)
                if let layer = Items.texLayer(item.item) {
                    wr.sprite(center: center, half: 0.17, right: left * -1, up: V3(0, 1, 0), layer: layer, light: light)
                } else if let bl = item.def.block {
                    wr.cube(center: center + V3(0, -0.1, 0), half: 0.12, yaw: 0, block: bl, light: light)
                }
            }
        }
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
