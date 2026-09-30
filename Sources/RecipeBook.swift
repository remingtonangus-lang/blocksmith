import Foundation

// Recipe book for the 2x2 and 3x3 crafting screens: a panel left of the menu listing what can be
// crafted from the inventory right now (or everything, toggled); choosing one moves its ingredients
// into the grid. Recipe buttons are ordinary menu slots, so the controller cursor reaches them.
final class RecipeBook {
    static let cols = 4, rows = 5, perPage = cols * rows
    static let base = 500                      // button ids: 500+ recipe, 490 toggle open, 491/492 page, 493 filter
    var open = false
    var craftableOnly = true
    var page = 0
    var list: [Int] = []                       // indices into Recipes.all
    let size: Int                              // crafting grid size (2 or 3)
    init(size: Int) { self.size = size }

    var pages: Int { max(1, (list.count + RecipeBook.perPage - 1) / RecipeBook.perPage) }

    // Ingredient requirement per recipe: list of ingredient strings.
    static func needs(_ r: Recipe) -> [String] { r.shapeless.isEmpty ? r.cells.compactMap { $0 } : r.shapeless }

    // Can the player's items cover every ingredient (greedy, one item per cell)?
    static func craftable(_ r: Recipe, _ pool: [ItemID: Int]) -> Bool {
        var left = pool
        for ing in needs(r) {
            guard let k = left.first(where: { $0.value > 0 && Recipes.matches(ing, $0.key) })?.key else { return false }
            left[k]! -= 1
        }
        return true
    }

    func refresh(_ g: Game, grid: ItemContainer) {
        var pool: [ItemID: Int] = [:]
        for s in g.inventory.main.slots + grid.slots where !s.isEmpty { pool[s.item, default: 0] += s.count }
        var seen = Set<ItemID>()
        list = Recipes.all.indices.filter { i in
            let r = Recipes.all[i]
            let fits = r.shapeless.isEmpty ? (r.w <= size && r.h <= size) : r.shapeless.count <= size * size
            guard fits, !seen.contains(r.result.item) else { return false }
            let ok = !craftableOnly || RecipeBook.craftable(r, pool)
            if ok { seen.insert(r.result.item) }
            return ok
        }
        page = min(page, pages - 1)
    }

    // Moves the ingredients for recipe i from the inventory into the grid (grid contents go back first).
    func fill(_ i: Int, _ g: Game, grid: ItemContainer) {
        for k in 0..<grid.count where !grid[k].isEmpty {
            let rest = g.inventory.add(grid[k]); if !rest.isEmpty { g.dropItem(rest) }
            grid[k] = .empty
        }
        let r = Recipes.all[i]
        var cells: [(Int, String)] = []
        if r.shapeless.isEmpty {
            for y in 0..<r.h { for x in 0..<r.w { if let ing = r.cells[x + y * r.w] { cells.append((x + y * size, ing)) } } }
        } else {
            for (k, ing) in r.shapeless.enumerated() { cells.append((k, ing)) }
        }
        let inv = g.inventory.main
        for (slot, ing) in cells {
            guard let j = (0..<inv.count).first(where: { !inv[$0].isEmpty && Recipes.matches(ing, inv[$0].item) }) else { continue }
            var s = inv[j]
            grid[slot] = s.with(count: 1)
            s.count -= 1
            inv[j] = s.count > 0 ? s : .empty
        }
    }

    // Slots for the panel (positions relative to the menu, left of it).
    func slots() -> [MenuSlot] {
        var out: [MenuSlot] = []
        let toggle = MenuSlot(-22, 4, nil, 0, .button(490)); toggle.w = 18; toggle.h = 18
        out.append(toggle)
        guard open else { return out }
        for k in 0..<RecipeBook.perPage {
            let b = MenuSlot(-118 + (k % RecipeBook.cols) * 22, 28 + (k / RecipeBook.cols) * 22, nil, 0, .button(RecipeBook.base + k))
            b.w = 20; b.h = 20
            out.append(b)
        }
        for (id, x) in [(491, -118), (493, -86), (492, -52)] {
            let b = MenuSlot(x, 142, nil, 0, .button(id)); b.w = id == 493 ? 30 : 26; b.h = 14
            out.append(b)
        }
        return out
    }
}

protocol HasRecipeBook: Menu {
    var book: RecipeBook { get }
    var craftGrid: ItemContainer { get }
}

extension HasRecipeBook {
    func rebuildBook() {
        slots.removeAll { if case .button(let i) = $0.kind { return i >= 490 && i < 600 } else { return false } }
        slots += book.slots()
    }
}

extension Menu {
    // Shared button handling for menus with a recipe book. Returns true if the id was a book button.
    func recipeBookButton(_ id: Int, _ book: RecipeBook, grid: ItemContainer, rebuild: () -> Void) -> Bool {
        switch id {
        case 490: book.open.toggle(); if book.open { book.refresh(game, grid: grid) }; rebuild()
        case 491: book.page = max(0, book.page - 1)
        case 492: book.page = min(book.pages - 1, book.page + 1)
        case 493: book.craftableOnly.toggle(); book.page = 0; book.refresh(game, grid: grid)
        case RecipeBook.base..<(RecipeBook.base + RecipeBook.perPage):
            let k = book.page * RecipeBook.perPage + id - RecipeBook.base
            guard k < book.list.count else { return true }
            let r = Recipes.all[book.list[k]]
            if RecipeBook.craftable(r, poolFor(grid)) { book.fill(book.list[k], game, grid: grid) }
            changed()
            book.refresh(game, grid: grid)
        default: return false
        }
        game.sfx(.click, 0.4)
        return true
    }
    func poolFor(_ grid: ItemContainer) -> [ItemID: Int] {
        var pool: [ItemID: Int] = [:]
        for s in game.inventory.main.slots + grid.slots where !s.isEmpty { pool[s.item, default: 0] += s.count }
        return pool
    }
}
