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
                for _ in 0..<64 {
                    guard let r = takeResult(slot) else { break }
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
                let rest = moveInto(slot.stack, quickMoveTargets(from: slot))
                slot.stack = rest
                return
            }
            let s = slot.stack
            if s.isEmpty { return }
            if carried.isEmpty { carried = s; slot.stack = .empty }
            else if carried.stacks(with: s) {
                let n = min(s.count, carried.maxStack - carried.count)
                carried.count += n
                var ns = s; ns.count -= n; slot.stack = ns
            }
            return
        default:
            break
        }
        if button == 1 && !shift && bundleClick(slot, carried: &carried) { return }
        if shift {
            if slot.stack.isEmpty { return }
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
            } else if slot.accepts(carried) {
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
                } else if s.stacks(with: carried) && s.count < slotLimit(slot, s) {
                    s.count += 1
                    slot.stack = s
                    carried.count -= 1
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
        for s in slots {
            let x = o.x + Float(s.x - 1) * L.s, y = o.y + Float(s.y - 1) * L.s
            if p.x >= x && p.x < x + Float(s.w + 2) * L.s && p.y >= y && p.y < y + Float(s.h + 2) * L.s { return s }
        }
        return nil
    }
    func inside(_ p: V2, _ L: HudLayout) -> Bool {
        let o = origin(L)
        return p.x >= o.x && p.y >= o.y && p.x < o.x + Float(width) * L.s && p.y < o.y + Float(height) * L.s
    }

    // Controller navigation: nearest slot in a direction.
    func neighbour(of cur: Int, dx: Int, dy: Int) -> Int {
        guard cur < slots.count else { return 0 }
        let a = slots[cur]
        var best = cur
        var bestScore = Int.max
        for (i, s) in slots.enumerated() where i != cur {
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
        for i in 0..<grid.count where !grid[i].isEmpty {
            var s = grid[i]
            let key = Items.key(s.item)
            s.count -= 1
            // Buckets give their bucket back.
            if s.count <= 0 && (key == "water_bucket" || key == "lava_bucket" || key == "milk_bucket") { s = ItemStack(Items.id("bucket"), 1) }
            grid[i] = s
        }
        update()
        return r.result
    }
}

final class InventoryMenu: Menu, HasRecipeBook {
    let craft = CraftingGrid(2)
    let book = RecipeBook(size: 2)
    var craftGrid: ItemContainer { craft.grid }
    override func buttonPressed(_ i: Int) { _ = recipeBookButton(i, book, grid: craft.grid) { rebuildBook() } }
    init(game: Game) {
        super.init("", game: game)
        for i in 0..<4 { slots.append(MenuSlot(8, 8 + i * 18, game.inventory.armor, i, .armor(ArmorSlot(rawValue: i)!))) }
        slots.append(MenuSlot(77, 62, game.inventory.offhand, 0))
        for r in 0..<2 { for c in 0..<2 { slots.append(MenuSlot(98 + c * 18, 18 + r * 18, craft.grid, c + r * 2)) } }
        slots.append(MenuSlot(154, 28, craft.result, 0, .result))
        addPlayerInventory()
        showInventoryLabel = false
        // The recipe panel is open from the start; its tiles craft straight into the inventory.
        book.open = true
        book.refresh(game, grid: craft.grid)
        slots += book.slots()
    }
    override func changed() { craft.update() }
    override func takeResult(_ slot: MenuSlot) -> ItemStack? { craft.take() }
    override func quickMoveTargets(from: MenuSlot) -> [MenuSlot] {
        if from.isPlayerInv, let a = from.stack.def.armorSlot {
            let t = slots.filter { if case .armor(let s) = $0.kind { return s == a && $0.stack.isEmpty } else { return false } }
            if !t.isEmpty { return t }
        }
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
        slots.append(MenuSlot(56, 53, be.container, 1, .fuel))
        slots.append(MenuSlot(116, 35, be.container, 2, .output))
        addPlayerInventory()
    }
    override func quickMoveTargets(from: MenuSlot) -> [MenuSlot] {
        if from.isPlayerInv {
            let s = from.stack
            if Recipes.smelt(s.item) != nil { return [slots[0]] }
            if Recipes.fuel(s.item) > 0 { return [slots[1]] }
            return from.isHotbar ? slots.filter { $0.isPlayerInv && !$0.isHotbar } : slots.filter { $0.isHotbar }
        }
        return super.quickMoveTargets(from: from)
    }
}

final class ChestMenu: Menu {
    convenience init(game: Game, entity: BlockEntity) { self.init(game: game, container: entity.container, title: "Chest") }
    init(game: Game, container: ItemContainer, title: String) {
        super.init(title, game: game)
        let rows = container.count / 9
        height = 114 + rows * 18
        inventoryLabelY = height - 94
        for r in 0..<rows { for c in 0..<9 { slots.append(MenuSlot(8 + c * 18, 18 + r * 18, container, c + r * 9)) } }
        addPlayerInventory(y: height - 82)
    }
    var closed: (() -> Void)?
    override func onClose() { closed?() }
}

// Two chests side by side facing the same way: one 54-slot screen.
final class DoubleChestMenu: Menu {
    init(game: Game, a: ItemContainer, b: ItemContainer) {
        super.init("Large Chest", game: game)
        height = 222
        inventoryLabelY = 128
        for (k, c) in [a, b].enumerated() {
            for r in 0..<3 { for col in 0..<9 { slots.append(MenuSlot(8 + col * 18, 18 + (r + k * 3) * 18, c, col + r * 9)) } }
        }
        addPlayerInventory(y: 140)
    }
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
