import Foundation

// Bundles (and the 16 dyed ones): hold up to 64 "weight" of mixed items (a stack of 16-stackables
// counts 4 each, unstackables 64, a nested bundle 4 + its contents). Right-click in menus to
// put items in / take the last one out; using a bundle in hand empties it onto the ground.
enum Bundles {
    static func isBundle(_ s: ItemStack) -> Bool { let k = Items.key(s.item); return k == "bundle" || k.hasSuffix("_bundle") }
    static func weight(_ s: ItemStack) -> Int {
        if isBundle(s) { return 4 + (s.contents ?? []).reduce(0) { $0 + weight($1) } }
        return s.count * (64 / max(1, s.maxStack))
    }
    static func fill(_ b: ItemStack) -> Int { (b.contents ?? []).reduce(0) { $0 + weight($1) } }

    // Moves as much of `s` into bundle `b` as fits. Returns (new bundle, rest of s).
    static func insert(_ b: ItemStack, _ s: ItemStack) -> (ItemStack, ItemStack) {
        guard !s.isEmpty, !Items.key(s.item).hasSuffix("shulker_box") else { return (b, s) }   // no shell boxes in bundles
        let per = isBundle(s) ? weight(s) : 64 / max(1, s.maxStack)
        let room = 64 - fill(b)
        let n = min(s.count, room / max(1, per))
        guard n > 0 else { return (b, s) }
        var nb = b
        var list = nb.contents ?? []
        if let i = list.firstIndex(where: { $0.stacks(with: s) }) {
            let add = min(n, list[i].maxStack - list[i].count)
            list[i].count += add
            if add < n { list.insert(s.with(count: n - add), at: 0) }
        } else {
            list.insert(s.with(count: n), at: 0)
        }
        nb.contents = list
        var rest = s
        rest.count -= n
        return (nb, rest.count > 0 ? rest : .empty)
    }

    // Takes the most recently added stack out.
    static func takeOut(_ b: ItemStack) -> (ItemStack, ItemStack)? {
        guard var list = b.contents, !list.isEmpty else { return nil }
        let first = list.removeFirst()
        var nb = b
        nb.contents = list.isEmpty ? nil : list
        return (nb, first)
    }
}

extension Menu {
    // Right-click bundle interactions. Returns true when handled.
    func bundleClick(_ slot: MenuSlot, carried: inout ItemStack) -> Bool {
        let s = slot.stack
        if Bundles.isBundle(carried) {
            if s.isEmpty {
                guard case let (nb, out)? = Bundles.takeOut(carried), slot.accepts(out), out.count <= slotLimit(slot, out) else { return false }
                carried = nb; slot.stack = out
            } else {
                let (nb, rest) = Bundles.insert(carried, s)
                guard nb != carried else { return false }
                carried = nb; slot.stack = rest
            }
            game.sfx(.bundleInsert, 0.6)
            return true
        }
        if Bundles.isBundle(s) && slot.container != nil {
            if carried.isEmpty {
                guard case let (nb, out)? = Bundles.takeOut(s) else { return false }
                slot.stack = nb; carried = out
            } else {
                let (nb, rest) = Bundles.insert(s, carried)
                guard nb != s else { return false }
                slot.stack = nb; carried = rest
            }
            game.sfx(.bundleRemove, 0.6)
            return true
        }
        return false
    }
}

extension Game {
    func useBundle() -> Bool {
        var h = held
        guard Bundles.isBundle(h), let list = h.contents, !list.isEmpty else { return false }
        for s in list { drops.spawn(s, at: player.eye + player.look * 0.5) }
        h.contents = nil
        inventory.held = h
        sfx(.bundleRemove, 0.7)
        return true
    }
}
