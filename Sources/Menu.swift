import Foundation

// Container screens (inventory, crafting table, furnace, chest, creative) with the reference game's
// click rules: left = take/place/swap stack, right = take half / place one, shift = quick-move.
// Layout is in GUI pixels (a 176x166 panel like the original), scaled by the HUD scale.
// Works with the mouse or a controller cursor that jumps between slots.

enum SlotKind { case normal, result, palette, armor(ArmorSlot), fuel, output, button(Int) }

final class MenuSlot {
    let x: Int, y: Int                    // GUI px, top-left of the 16x16 item area
    let container: ItemContainer?
    let index: Int
    let kind: SlotKind
    var paletteItem: ItemID = 0
    var w = 16, h = 16                    // hit area (buttons are larger)
    var filter: ((ItemStack) -> Bool)?    // only these items may be placed here
    var limit: Int?                       // max stack size in this slot
    var hidden = false                    // not drawn, clicked or reached by the pad cursor
    init(_ x: Int, _ y: Int, _ c: ItemContainer?, _ i: Int, _ k: SlotKind = .normal) {
        self.x = x; self.y = y; container = c; index = i; kind = k
    }
    var stack: ItemStack {
        get {
            if case .palette = kind { return paletteItem == 0 ? .empty : ItemStack(paletteItem, 1) }
            return container?[index] ?? .empty
        }
        set { container?[index] = newValue }
    }
    func accepts(_ s: ItemStack) -> Bool {
        switch kind {
        case .result, .output, .palette, .button: return false
        case .armor(let a): return s.def.armorSlot == a || (a == .head && ["carved_pumpkin", "skeleton_skull", "wither_skeleton_skull", "zombie_head", "creeper_head", "piglin_head", "dragon_head", "player_head"].contains(Items.key(s.item)))
        default: return filter?(s) ?? true
        }
    }
    var isButton: Bool { if case .button = kind { return true } else { return false } }
    var isPlayerInv: Bool = false
    var isHotbar: Bool = false
}

class Menu {
    var title: String
    var width = 176
    var height = 166
    var slots: [MenuSlot] = []
    unowned let game: Game
    var showInventoryLabel = true
    var inventoryLabelY = 73
    private weak var lastSlotClicked: MenuSlot?
    var mouseClick = false              // set by MenuInput around a mouse click: only mice double-click
    private var lastSlotClickAt: Double = 0
    var lastClickButton = 0, lastClickShift = false    // how the last button was pressed (recipe tiles: 1 / max / stack)

    init(_ title: String, game: Game) {
        self.title = title
        self.game = game
    }

    // Player inventory rows at the standard position (main at y 84, hotbar at y 142).
    func addPlayerInventory(y: Int = 84, x: Int = 8) {
        let inv = game.inventory.main
        for r in 0..<3 { for c in 0..<9 {
            let s = MenuSlot(x + c * 18, y + r * 18, inv, 9 + r * 9 + c)
            s.isPlayerInv = true
            slots.append(s)
        } }
        for c in 0..<9 {
            let s = MenuSlot(x + c * 18, y + 58, inv, c)
            s.isPlayerInv = true
            s.isHotbar = true
            slots.append(s)
        }
    }

    func changed() {}
    func tick() {}
    func onClose() {}
    func buttonPressed(_ i: Int) {}
    // B / Esc: return true to stay open (e.g. go back a page).
    func backPressed() -> Bool { false }
    var capturesText: Bool { false }
    func typed(_ s: String) {}

    // Result slot: take the crafted item.
    func takeResult(_ slot: MenuSlot) -> ItemStack? { nil }
    func tookOutput(_ slot: MenuSlot) {}          // an .output slot was (partly) emptied by the player

    // Shift-click destination slots for a stack coming from `from`.
    func quickMoveTargets(from: MenuSlot) -> [MenuSlot] {
        if from.isPlayerInv {
            let container = slots.filter { !$0.isPlayerInv && $0.accepts(from.stack) }
            if !container.isEmpty { return container }
            return from.isHotbar ? slots.filter { $0.isPlayerInv && !$0.isHotbar } : slots.filter { $0.isHotbar }
        }
        let hot: [MenuSlot] = Array(slots.filter { $0.isHotbar }.reversed())
        let main: [MenuSlot] = Array(slots.filter { $0.isPlayerInv && !$0.isHotbar }.reversed())
        return hot + main
    }

    func moveInto(_ s0: ItemStack, _ targets: [MenuSlot]) -> ItemStack {
        var s = s0
        for t in targets where !s.isEmpty && t.stack.stacks(with: s) && t.stack.count < min(t.limit ?? 99, t.stack.maxStack) {
            var st = t.stack
            let n = min(s.count, min(t.limit ?? 99, st.maxStack) - st.count)
            st.count += n
            s.count -= n
            t.stack = st
        }
        for t in targets where !s.isEmpty && t.stack.isEmpty && t.accepts(s) {
            let n = min(s.count, min(t.limit ?? 99, s.maxStack))
            t.stack = s.with(count: n)
            s.count -= n
        }
        return s.isEmpty ? .empty : s
    }

    // Main click handler. button 0 = left, 1 = right.
    func click(_ slot: MenuSlot, button: Int, shift: Bool) {
        var carried = game.carried
        defer { game.carried = carried; changed() }
        // Double left click with a stack on the cursor gathers the same item from the screen's slots, up to a full
        // stack (reference; every click was single).
        let now = CFAbsoluteTimeGetCurrent()
        let double = mouseClick && button == 0 && !shift && lastSlotClicked === slot && now - lastSlotClickAt < 0.3
        lastSlotClicked = slot; lastSlotClickAt = now
        if double && !carried.isEmpty && carried.maxStack > 1, slot.container != nil {
            if case .normal = slot.kind {
                for pass in 0..<2 {                                         // part stacks first, then full ones
                    for o in slots where o.container != nil && !o.isButton && carried.count < carried.maxStack {
                        guard case .normal = o.kind, !o.stack.isEmpty, o.stack.stacks(with: carried) else { continue }
                        if pass == 0 && o.stack.count >= o.stack.maxStack { continue }
                        var st = o.stack
                        let n = min(st.count, carried.maxStack - carried.count)
                        carried.count += n
                        st.count -= n
                        o.stack = st.count > 0 ? st : .empty
                    }
                }
                lastSlotClicked = nil
                return
            }
        }
        switch slot.kind {
        case .button(let i):
            lastClickButton = button; lastClickShift = shift
            buttonPressed(i)
            return
        case .armor:
            // Curse of Binding: can't take it off (except in creative).
            if !slot.stack.isEmpty && Enchant.level(.bindingCurse, slot.stack) > 0 && game.survival { return }
        case .palette:
            let it = slot.paletteItem
            if it == 0 { if !carried.isEmpty { carried = .empty }; return }
            let full = ItemStack(it, Items.def(it).maxStack)
            if shift { _ = game.inventory.add(full); return }
            if !carried.isEmpty && carried.item == it && button == 0 { carried.count = min(carried.maxStack, carried.count + 1); return }
            if !carried.isEmpty { carried = .empty; return }
            carried = button == 0 ? full : ItemStack(it, 1)
            return
        case .result:
            if shift {
                // Craft as many as possible straight into the inventory.
                // Stops when the next result wouldn't fit (reference; the overflow was thrown on the ground).
                for _ in 0..<64 {
                    let next = slot.stack
                    guard !next.isEmpty, CraftBook.room(game, for: next) >= next.count, let r = takeResult(slot) else { break }
                    let rest = game.inventory.add(r)
                    if !rest.isEmpty { game.dropItem(rest); break }
                }
                return
            }
            let preview = slot.stack
            if preview.isEmpty { return }
            if carried.isEmpty || (carried.stacks(with: preview) && carried.count + preview.count <= carried.maxStack) {
                if let r = takeResult(slot) {
                    if carried.isEmpty { carried = r } else { carried.count += r.count }
                }
            }
            return
        case .output:
            if shift {
                let before = slot.stack.count
                let rest = moveInto(slot.stack, quickMoveTargets(from: slot))
                slot.stack = rest
                if rest.count < before { tookOutput(slot) }
                return
            }
            let s = slot.stack
            if s.isEmpty { return }
            if carried.isEmpty && button == 1 && s.count > 1 {                      // right click: half, rounded up
                let n = (s.count + 1) / 2
                carried = s.with(count: n)
                slot.stack = s.with(count: s.count - n)
                tookOutput(slot)
            } else if carried.isEmpty { carried = s; slot.stack = .empty; tookOutput(slot) }
            else if carried.stacks(with: s) {
                let n = min(s.count, carried.maxStack - carried.count)
                carried.count += n
                var ns = s; ns.count -= n; slot.stack = ns
                if n > 0 { tookOutput(slot) }
            }
            return
        default:
            break
        }
        if button == 1 && !shift && bundleClick(slot, carried: &carried) { return }
        if shift {
            if slot.stack.isEmpty { return }
            // P204: a soldier's armour set, quick-moved from the pack, is put on whole.
            if slot.isPlayerInv, TroopClass.ofSet(Items.key(slot.stack.item)) != nil {
                let set = slot.stack
                slot.stack = .empty
                _ = game.wearTroopSet(set, fromHeld: false)
                return
            }
            slot.stack = moveInto(slot.stack, quickMoveTargets(from: slot))
            return
        }
        var s = slot.stack
        if button == 0 {
            if carried.isEmpty {
                carried = s
                slot.stack = .empty
            } else if s.isEmpty {
                if slot.accepts(carried) {
                    let n = min(carried.count, slotLimit(slot, carried))
                    slot.stack = carried.with(count: n)
                    carried.count -= n
                    if carried.count <= 0 { carried = .empty }
                }
            } else if s.stacks(with: carried) {
                let n = max(0, min(carried.count, slotLimit(slot, s) - s.count))
                s.count += n
                slot.stack = s
                carried.count -= n
                if carried.count <= 0 { carried = .empty }
            } else if slot.accepts(carried) && carried.count <= slotLimit(slot, carried) {
                // Only a stack the slot can hold swaps in (64 books swapped into the enchanting slot became one book).
                slot.stack = carried
                carried = s
            }
        } else {
            if carried.isEmpty {
                if s.isEmpty { return }
                let half = (s.count + 1) / 2
                carried = s.with(count: half)
                s.count -= half
                slot.stack = s
            } else if slot.accepts(carried) {
                if s.isEmpty {
                    slot.stack = carried.with(count: 1)
                    carried.count -= 1
                } else if s.stacks(with: carried) {
                    if s.count < slotLimit(slot, s) {
                        s.count += 1
                        slot.stack = s
                        carried.count -= 1
                    }
                } else if carried.count <= slotLimit(slot, carried) {
                    // A different item swaps on a right click too (reference; it did nothing).
                    slot.stack = carried
                    carried = s
                }
                if carried.count <= 0 { carried = .empty }
            }
        }
    }

    func slotLimit(_ slot: MenuSlot, _ s: ItemStack) -> Int {
        if case .armor = slot.kind { return 1 }
        if let l = slot.limit { return min(l, s.maxStack) }
        return s.maxStack
    }

    // MARK: Geometry

    func origin(_ L: HudLayout) -> V2 {
        V2(floor((L.W - Float(width) * L.s) / 2), floor((L.H - Float(height) * L.s) / 2))
    }
    func slotAt(_ p: V2, _ L: HudLayout) -> MenuSlot? {
        let o = origin(L)
        for s in slots where !s.hidden {
            let x = o.x + Float(s.x - 1) * L.s, y = o.y + Float(s.y - 1) * L.s
            if p.x >= x && p.x < x + Float(s.w + 2) * L.s && p.y >= y && p.y < y + Float(s.h + 2) * L.s { return s }
        }
        return nil
    }
    func inside(_ p: V2, _ L: HudLayout) -> Bool {
        let o = origin(L)
        return p.x >= o.x && p.y >= o.y && p.x < o.x + Float(width) * L.s && p.y < o.y + Float(height) * L.s
    }
    // Q2c-console-63: the headset's Drop box in the margin right of the window (nil when there is no room for it): the
    // only place a pull off the window throws the carried stack out.
    func dropBox(_ L: HudLayout) -> (x: Float, y: Float, w: Float, h: Float)? {
        let o = origin(L), s = L.s
        let x = o.x + Float(width) * s + 8 * s
        let w = min(56 * s, L.W - x - 4 * s), h = 44 * s
        guard w >= 36 * s else { return nil }
        return (x, o.y + (Float(height) * s - h) / 2, w, h)
    }
    func inDropBox(_ p: V2, _ L: HudLayout) -> Bool {
        guard let d = dropBox(L) else { return false }
        return p.x >= d.x && p.x < d.x + d.w && p.y >= d.y && p.y < d.y + d.h
    }

    // Controller navigation: nearest slot in a direction.
    func neighbour(of cur: Int, dx: Int, dy: Int) -> Int {
        guard cur < slots.count else { return 0 }
        let a = slots[cur]
        var best = cur
        var bestScore = Int.max
        for (i, s) in slots.enumerated() where i != cur && !s.hidden {
            let ddx = s.x - a.x, ddy = s.y - a.y
            let along = dx != 0 ? ddx * dx : ddy * dy
            if along <= 0 { continue }
            let across = dx != 0 ? abs(ddy) : abs(ddx)
            let score = along + across * 3
            if score < bestScore { bestScore = score; best = i }
        }
        return best
    }
}

// MARK: Concrete screens

final class CraftingGrid {
    let size: Int
    let grid: ItemContainer
    let result = ItemContainer(1)
    var recipe: Recipe?
    init(_ size: Int) { self.size = size; grid = ItemContainer(size * size) }

    var special: (ItemStack, keep: Set<Int>)?
    func update() {
        special = Fireworks.craft(grid.slots)
        recipe = special == nil ? Recipes.match(grid.slots.map { $0.item }, size, size) : nil
        result[0] = special?.0 ?? recipe?.result ?? .empty
    }
    func take() -> ItemStack? {
        update()
        if let sp = special {
            for i in 0..<grid.count where !grid[i].isEmpty && !sp.keep.contains(i) {
                var s = grid[i]; s.count -= 1; grid[i] = s
            }
            update()
            return sp.0
        }
        guard let r = recipe else { return nil }
        let result = Recipes.keepContents(r.result, Array(grid.slots))
        for i in 0..<grid.count where !grid[i].isEmpty {
            var s = grid[i]
            let key = Items.key(s.item)
            s.count -= 1
            // Buckets give their bucket back.
            if s.count <= 0 && (key == "water_bucket" || key == "lava_bucket" || key == "milk_bucket") { s = ItemStack(Items.id("bucket"), 1) }
            grid[i] = s
        }
        update()
        return result
    }
}

final class InventoryMenu: Menu, HasRecipeBook {
    let craft = CraftingGrid(2)
    let book = RecipeBook(size: 2)
    var craftGrid: ItemContainer { craft.grid }
    static let searchBtn = 480          // outside the recipe book's 490..<600 range (it rebuilds those)
    static let sortBtn = 481            // Q2c-console-21
    var sortedAt: Double = -10
    var query = ""                     // search: matching slots light up, the rest dim (Renderer)
    var searching = false
    override var capturesText: Bool { searching }
    override func typed(_ s: String) { searching = ItemSearch.type(s, into: &query) }
    func matches(_ st: ItemStack) -> Bool { !st.isEmpty && ItemSearch.matches(st.item, query) }
    override func buttonPressed(_ i: Int) {
        if i == InventoryMenu.sortBtn {
            InventoryMenu.sortPack(game.inventory.main)
            sortedAt = game.clock
            game.sfx(.pageTurn, 0.5)
            return
        }
        if i == InventoryMenu.searchBtn {
            searching.toggle()
            if !searching { query = "" }
            game.sfx(.click, 0.4)
            return
        }
        // The book button opens the 2x2 crafting book (CraftingBook.swift), the same screen as a table's.
        if i == 490 { game.switchMenu(to: CraftingBookMenu(game: game, size: 2)); return }
        _ = recipeBookButton(i, book, grid: craft.grid) { rebuildBook() }
    }
    init(game: Game) {
        super.init("", game: game)
        for i in 0..<4 { slots.append(MenuSlot(8, 8 + i * 18, game.inventory.armor, i, .armor(ArmorSlot(rawValue: i)!))) }
        slots.append(MenuSlot(77, 62, game.inventory.offhand, 0))
        // No 2x2 grid (recipe-book crafting only): the Craft button opens the crafting book.
        let sb = MenuSlot(97, 62, nil, 0, .button(InventoryMenu.searchBtn)); sb.w = 46; sb.h = 14
        slots.append(sb)
        let so = MenuSlot(145, 62, nil, 0, .button(InventoryMenu.sortBtn)); so.w = 24; so.h = 14       // Q2c-console-21
        slots.append(so)
        addPlayerInventory()
        showInventoryLabel = false
        // Only the book button: crafting by recipe is the crafting book's job (LB/RB or the button open it).
        book.open = false
        slots += book.slots()
    }
    override func changed() { craft.update() }
    override func takeResult(_ slot: MenuSlot) -> ItemStack? { craft.take() }

    // Q2c-console-21: the pack (not the hotbar) sorted, identical stacks merged up to their stack size.
    static func category(_ s: ItemStack) -> Int {
        let d = s.def, k = Items.key(s.item)
        if Guns.index(s.item) != nil || d.tool != .none || k.hasSuffix("_sword") || ["bow", "crossbow", "trident", "shield", "mace"].contains(k) { return 0 }
        if d.armorSlot != nil { return 1 }
        if d.food != nil { return 2 }
        if Guns.ammo.contains(where: { $0.0 == k }) || k == "arrow" || k.hasSuffix("_arrow") { return 3 }
        if d.block != nil { return 4 }
        return 5
    }
    static func sortPack(_ c: ItemContainer) {
        var merged: [ItemStack] = []
        for i in 9..<c.count where !c[i].isEmpty {
            var left = c[i]
            for j in merged.indices where left.count > 0 {
                var a = merged[j], b = left
                a.count = 1; b.count = 1
                guard a == b else { continue }
                let move = min(max(0, merged[j].def.maxStack - merged[j].count), left.count)
                merged[j].count += move; left.count -= move
            }
            if left.count > 0 { merged.append(left) }
        }
        merged.sort {
            let ca = category($0), cb = category($1)
            if ca != cb { return ca < cb }
            let na = $0.displayName, nb = $1.displayName
            return na != nb ? na < nb : $0.count > $1.count
        }
        for i in 9..<c.count { c[i] = i - 9 < merged.count ? merged[i - 9] : .empty }
    }
    override func quickMoveTargets(from: MenuSlot) -> [MenuSlot] {
        if from.isPlayerInv, let a = from.stack.def.armorSlot {
            let t = slots.filter { if case .armor(let s) = $0.kind { return s == a && $0.stack.isEmpty } else { return false } }
            if !t.isEmpty { return t }
        }
        // A shield goes to an empty off hand (reference).
        if from.isPlayerInv, Items.key(from.stack.item) == "shield", slots.count > 4, slots[4].stack.isEmpty { return [slots[4]] }
        if from.isPlayerInv {
            return from.isHotbar ? slots.filter { $0.isPlayerInv && !$0.isHotbar } : slots.filter { $0.isHotbar }
        }
        return super.quickMoveTargets(from: from)
    }
    override func onClose() { returnGrid(craft.grid) }
    func returnGrid(_ g: ItemContainer) {
        for i in 0..<g.count where !g[i].isEmpty {
            let rest = game.inventory.add(g[i])
            if !rest.isEmpty { game.dropItem(rest) }
            g[i] = .empty
        }
    }
}

final class CraftingTableMenu: Menu, HasRecipeBook {
    let craft = CraftingGrid(3)
    let book = RecipeBook(size: 3)
    var craftGrid: ItemContainer { craft.grid }
    override func buttonPressed(_ i: Int) {
        // The book button goes back to the crafting book (CraftingBook.swift).
        if i == 490 { game.switchMenu(to: CraftingBookMenu(game: game)); return }
        _ = recipeBookButton(i, book, grid: craft.grid) { rebuildBook() }
    }
    init(game: Game) {
        super.init("Crafting", game: game)
        for r in 0..<3 { for c in 0..<3 { slots.append(MenuSlot(30 + c * 18, 17 + r * 18, craft.grid, c + r * 3)) } }
        slots.append(MenuSlot(124, 35, craft.result, 0, .result))
        addPlayerInventory()
        slots += book.slots()
    }
    override func changed() { craft.update() }
    override func takeResult(_ slot: MenuSlot) -> ItemStack? { craft.take() }
    override func quickMoveTargets(from: MenuSlot) -> [MenuSlot] {
        if from.isPlayerInv { return from.isHotbar ? slots.filter { $0.isPlayerInv && !$0.isHotbar } : slots.filter { $0.isHotbar } }
        return super.quickMoveTargets(from: from)
    }
    override func onClose() {
        for i in 0..<craft.grid.count where !craft.grid[i].isEmpty {
            let rest = game.inventory.add(craft.grid[i])
            if !rest.isEmpty { game.dropItem(rest) }
            craft.grid[i] = .empty
        }
    }
}

final class FurnaceMenu: Menu {
    let be: BlockEntity
    init(game: Game, entity: BlockEntity) {
        be = entity
        super.init("Furnace", game: game)
        slots.append(MenuSlot(56, 17, be.container, 0))
        let fuel = MenuSlot(56, 53, be.container, 1, .fuel)
        fuel.filter = { Recipes.fuel($0.item) > 0 || Items.key($0.item) == "bucket" }      // fuels only (anything went in)
        slots.append(fuel)
        slots.append(MenuSlot(116, 35, be.container, 2, .output))
        // Q2c-console-40: room for the status lines between the slots and the pack.
        height = 186
        inventoryLabelY = 93
        addPlayerInventory(y: 104)
    }
    var note = "", noteAt: Double = -10          // a refusal shown on the status line for a few seconds
    override func click(_ slot: MenuSlot, button: Int, shift: Bool) {
        if case .fuel = slot.kind, !game.carried.isEmpty, !slot.accepts(game.carried) {
            note = "\(game.carried.def.display) isn't fuel"; noteAt = game.clock
            game.sfx(.click, 0.25)
            return
        }
        super.click(slot, button: button, shift: shift)
    }
    // Q2c-console-40: what it is doing, or why it is stuck: up to two lines, each amber when he must act.
    var status: [(String, Bool)] {
        if !note.isEmpty && game.clock - noteAt < 3 { return [(note, true)] }
        let c = be.container, input = c[0], fuel = c[1], out = c[2]
        let kind = be.mob, fast = kind == "smoker" || kind == "blast_furnace"
        let cook = kind == "smoker" ? "cook" : "smelt"
        if input.isEmpty {
            if be.burn > 0 { return [("Burning its fuel: nothing to \(cook)", false)] }
            return [(kind == "smoker" ? "Put food to cook in the top slot, fuel below" : "Put something to smelt in the top slot, fuel below", false)]
        }
        guard let r = Recipes.smelt(input.item) else { return [("\(input.def.display) can't be \(cook)ed", true)] }
        guard BlockEntity.allowed(r, input.item, in: kind) else {
            let kinds = [("", "Furnace"), ("blast_furnace", "Blast Furnace"), ("smoker", "Smoker")].filter { BlockEntity.allowed(r, input.item, in: $0.0) }
            return [("\(input.def.display) needs a " + kinds.map { $0.1 }.joined(separator: " or "), true)]
        }
        if !out.isEmpty && (out.item != r || out.count >= out.maxStack) { return [("Take out the \(out.def.display) to keep going", true)] }
        let fuelTicks = fuel.isEmpty ? 0 : Recipes.fuel(fuel.item) * fuel.count
        if be.burn == 0 && fuelTicks == 0 { return [("Add fuel below: coal, charcoal, logs or planks", true)] }
        var lines: [(String, Bool)] = [("\(kind == "smoker" ? "Cooking" : "Smelting") \(input.def.display): \(input.count) left", false)]
        // One item takes 200 units of cooking and of fuel (a smoker or blast furnace spends both twice as fast).
        let fuelled = (be.burn + fuelTicks + be.cook) / 200
        if fuelled < input.count {
            lines.append(("Fuel for \(max(1, fuelled)) more: add more to finish", true))
        } else {
            let secs = Int((Double(input.count) * 200 - Double(be.cook)) / (fast ? 40 : 20))
            lines.append((secs < 60 ? "About \(max(1, secs)) s" : "About \((secs + 30) / 60) min", false))
        }
        return lines
    }
    override func quickMoveTargets(from: MenuSlot) -> [MenuSlot] {
        if from.isPlayerInv {
            let s = from.stack
            // Only what this furnace can cook goes to the input (a smoker took logs and cobblestone it never cooks).
            if let r = Recipes.smelt(s.item), BlockEntity.allowed(r, s.item, in: be.mob) { return [slots[0]] }
            if Recipes.fuel(s.item) > 0 { return [slots[1]] }
            return from.isHotbar ? slots.filter { $0.isPlayerInv && !$0.isHotbar } : slots.filter { $0.isHotbar }
        }
        return super.quickMoveTargets(from: from)
    }
    // The experience stored by smelting is paid out when the player takes from the output (reference; furnaces gave none).
    override func tookOutput(_ slot: MenuSlot) {
        guard be.xp > 0 else { return }
        let whole = floorf(be.xp)
        let n = Int(whole) + (Rand.float(in: 0..<1) < be.xp - whole ? 1 : 0)
        be.xp = 0
        if n > 0 { game.addXP(n) }
    }
}

// Q2c-console-22: Take and Store buttons at a chest screen's top right. Take moves everything that fits into the pack
// and hotbar; Store puts away every pack stack (not the hotbar) of an item the chest already holds. The town's theft
// check reads the chest's contents as it always has, so a button counts the same as moving the items by hand.
extension Menu {
    static let takeBtn = 470, storeBtn = 471
    func addChestButtons() {
        let st = MenuSlot(110, 3, nil, 0, .button(Menu.storeBtn)); st.w = 30; st.h = 11; slots.append(st)
        let t = MenuSlot(142, 3, nil, 0, .button(Menu.takeBtn)); t.w = 28; t.h = 11; slots.append(t)
    }
    func chestButton(_ i: Int, _ parts: [ItemContainer]) {
        let g = game
        if i == Menu.takeBtn {
            var moved = 0, stuck = false
            for p in parts { for k in 0..<p.count where !p[k].isEmpty {
                let before = p[k].count
                let rest = g.inventory.add(p[k])
                if rest.count != before { moved += 1 }
                if !rest.isEmpty { stuck = true }
                p[k] = rest
            } }
            g.sfx(.pickup, 0.6)
            g.onToast?(moved == 0 ? (stuck ? "Your pack is full" : "The chest is empty") : "Took \(moved) stack\(moved == 1 ? "" : "s")" + (stuck ? ": your pack is full" : ""))
        } else if i == Menu.storeBtn {
            let have = Set(parts.flatMap { $0.slots.filter { !$0.isEmpty }.map { $0.item } })
            let main = g.inventory.main
            var moved = 0
            for k in 9..<main.count where !main[k].isEmpty && have.contains(main[k].item) {
                var rest = main[k]
                for p in parts where !rest.isEmpty { rest = p.add(rest) }
                if rest.count != main[k].count { moved += 1 }
                main[k] = rest
            }
            g.sfx(.click, 0.6)
            g.onToast?(moved == 0 ? "Nothing in your pack matches this chest" : "Stored \(moved) stack\(moved == 1 ? "" : "s")")
        }
    }
}

final class ChestMenu: Menu {
    let box: ItemContainer
    convenience init(game: Game, entity: BlockEntity) { self.init(game: game, container: entity.container, title: "Chest") }
    init(game: Game, container: ItemContainer, title: String) {
        box = container
        super.init(title, game: game)
        let rows = container.count / 9
        height = 114 + rows * 18
        inventoryLabelY = height - 94
        for r in 0..<rows { for c in 0..<9 { slots.append(MenuSlot(8 + c * 18, 18 + r * 18, container, c + r * 9)) } }
        addPlayerInventory(y: height - 82)
        addChestButtons()                           // Q2c-console-22
    }
    override func buttonPressed(_ i: Int) { chestButton(i, [box]) }
    var closed: (() -> Void)?
    override func onClose() { closed?() }
}

// Two chests side by side facing the same way: one 54-slot screen.
final class DoubleChestMenu: Menu {
    let halves: [ItemContainer]
    override func buttonPressed(_ i: Int) { chestButton(i, halves) }      // Q2c-console-22
    init(game: Game, a: ItemContainer, b: ItemContainer) {
        halves = [a, b]
        super.init("Large Chest", game: game)
        height = 222
        inventoryLabelY = 128
        for (k, c) in [a, b].enumerated() {
            for r in 0..<3 { for col in 0..<9 { slots.append(MenuSlot(8 + col * 18, 18 + (r + k * 3) * 18, c, col + r * 9)) } }
        }
        addPlayerInventory(y: 140)
        addChestButtons()                           // Q2c-console-22
    }
    var closed: (() -> Void)?                      // P264: a trapped double chest lets its circuit go
    override func onClose() { closed?() }
}

final class ShellBoxMenu: Menu {
    init(game: Game, entity: BlockEntity) {
        super.init("Shell Box", game: game)
        for r in 0..<3 { for c in 0..<9 {
            let sl = MenuSlot(8 + c * 18, 18 + r * 18, entity.container, c + r * 9)
            sl.filter = { !Items.key($0.item).hasSuffix("shulker_box") }       // no boxes inside boxes
            slots.append(sl)
        } }
        addPlayerInventory()
    }
}

final class DispenserMenu: Menu {
    init(game: Game, entity: BlockEntity, title: String) {
        super.init(title, game: game)
        for r in 0..<3 { for c in 0..<3 { slots.append(MenuSlot(62 + c * 18, 17 + r * 18, entity.container, c + r * 3)) } }
        addPlayerInventory()
    }
}

final class HopperMenu: Menu {
    init(game: Game, entity: BlockEntity) {
        super.init("Hopper", game: game)
        height = 133
        inventoryLabelY = 40
        for c in 0..<5 { slots.append(MenuSlot(44 + c * 18, 20, entity.container, c)) }
        addPlayerInventory(y: 51)
    }
}
