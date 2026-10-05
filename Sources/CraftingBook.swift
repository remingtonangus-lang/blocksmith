import Foundation

// The crafting book (Remington, 2026-10-04: he plays with a controller on a TV). Opening a crafting table shows
// every recipe as a grid of tiles, 40 to a page, under category tabs ("Craftable" first). Pick a tile and craft
// straight from it into the inventory: A / click crafts one (held: repeats, faster and faster), Y / shift-click a
// stack, X / right-click as many as the inventory allows, or a chosen amount from the detail panel. Craftable recipes
// are bright, the rest dimmed (or hidden with the filter); the detail panel shows the selected recipe's ingredients and
// what you have of each. LB / RB switch categories, LT / RT (or the mouse wheel) flip pages. The manual 3x3 grid is
// one button away (and comes back here with its book button).

enum CraftCategory: Int, CaseIterable {
    case craftable, building, decoration, utility, sparkstone, tools, combat, food, transport, misc
    var name: String {
        ["Craftable Now", "Building Blocks", "Decoration", "Utility & Storage", "Sparkstone", "Tools", "Combat", "Food",
         "Transport", "Materials & Misc"][rawValue]
    }
    var icon: String {
        ["crafting_table", "bricks", "white_banner", "chest", "redstone", "iron_pickaxe", "iron_sword", "bread", "minecart", "stick"][rawValue]
    }

    static let decorWords = ["banner", "_bed", "sign", "painting", "item_frame", "flower_pot", "candle", "lantern", "torch", "decorated_pot",
                             "carpet", "glazed", "stained_glass", "head", "skull", "armor_stand", "end_rod", "chain", "pane", "shelf"]
    static let transportWords = ["boat", "raft", "minecart", "rail", "saddle", "on_a_stick", "elytra", "lead", "ship_", "propeller", "balloon",
                                 "airfoil", "harness"]
    static let combatWords = ["sword", "bow", "arrow", "shield", "trident", "mace", "spear", "gun_", "_rounds", "shells", "rocket_ammo",
                              "arc_cell", "helmet", "chestplate", "leggings", "boots", "horse_armor", "wolf_armor", "tnt", "firework"]

    // Category of a crafted item (for the tabs; "craftable" is computed live).
    static func of(_ id: ItemID) -> CraftCategory {
        let k = Items.key(id)
        func has(_ words: [String]) -> Bool { words.contains { k.contains($0) } }
        if has(transportWords) { return .transport }
        if has(combatWords) || Items.def(id).armorSlot != nil { return .combat }
        switch CreativeMenu.category(id) {
        case .building, .natural: return has(decorWords) ? .decoration : .building
        case .functional: return has(decorWords) ? .decoration : .utility
        case .sparkstone: return .sparkstone
        case .tools: return .tools
        case .food: return .food
        default: return .misc
        }
    }
}

// Crafting straight from the inventory (no grid): shared by the crafting book and the inventory's recipe panel.
enum CraftBook {
    static var flashItem: ItemID = 0           // the last crafted result and when (its tile flashes)
    static var flashAt: Double = -10
    static func needs(_ r: Recipe) -> [String] { RecipeBook.needs(r) }

    static func pool(_ g: Game) -> [ItemID: Int] {
        var p: [ItemID: Int] = [:]
        for s in g.inventory.main.slots where !s.isEmpty { p[s.item, default: 0] += s.count }
        return p
    }

    // How many times recipe r can be crafted from the pool (greedy, as the grid would be filled).
    static func maxCrafts(_ r: Recipe, _ pool: [ItemID: Int], cap: Int = 1024) -> Int {
        var left = pool
        let need = needs(r)
        if need.isEmpty { return 0 }
        var n = 0
        while n < cap {
            for ing in need {
                guard let k = left.first(where: { $0.value > 0 && Recipes.matches(ing, $0.key) })?.key else { return n }
                left[k]! -= 1
            }
            n += 1
        }
        return n
    }

    // Room for `s` in the main inventory (partial stacks of the same item and empty slots).
    static func room(_ g: Game, for s: ItemStack) -> Int {
        var n = 0
        for t in g.inventory.main.slots {
            if t.isEmpty { n += s.maxStack } else if t.stacks(with: s) { n += max(0, t.maxStack - t.count) }
        }
        return n
    }

    // Crafts recipe r up to `times` times from the inventory into the inventory; stops when the ingredients run out
    // or the result no longer fits (nothing is dropped). Returns the number of crafts made.
    @discardableResult
    static func craft(_ r: Recipe, times: Int, game g: Game) -> Int {
        let inv = g.inventory.main
        var made = 0
        while made < times {
            guard room(g, for: r.result) >= r.result.count else { break }
            // Find one item per ingredient (distinct units), then take them.
            var take: [Int: Int] = [:]
            var ok = true
            for ing in needs(r) {
                guard let j = (0..<inv.count).first(where: { !inv[$0].isEmpty && Recipes.matches(ing, inv[$0].item) && inv[$0].count > (take[$0] ?? 0) })
                else { ok = false; break }
                take[j, default: 0] += 1
            }
            guard ok else { break }
            var returns: [ItemStack] = []
            for (j, n) in take {
                var s = inv[j]
                let key = Items.key(s.item)
                s.count -= n
                // Buckets give their bucket back, bottles their bottle.
                if key == "water_bucket" || key == "lava_bucket" || key == "milk_bucket" { returns.append(ItemStack(Items.id("bucket"), n)) }
                if key == "honey_bottle", Items.has("glass_bottle") { returns.append(ItemStack(Items.id("glass_bottle"), n)) }
                inv[j] = s.count > 0 ? s : .empty
            }
            let rest = g.inventory.add(r.result)
            if !rest.isEmpty { g.dropItem(rest) }
            for b in returns { let left = g.inventory.add(b); if !left.isEmpty { g.dropItem(left) } }
            made += 1
        }
        if made > 0 {
            // Feedback on three channels: the pickup sound, a flash on the tile, a light tap on the controller.
            g.sfx(.pickup, 0.6)
            flashItem = r.result.item
            flashAt = g.clock
            PadManager.shared.rumble(min(0.35, 0.12 + 0.02 * Float(made)), 0.05)
        }
        return made
    }

    // Crafts enough for one full stack of the result (at least one craft).
    static func stackTimes(_ r: Recipe) -> Int { max(1, (r.result.maxStack + r.result.count - 1) / max(1, r.result.count)) }
}

final class CraftingBookMenu: Menu, CustomDrawnMenu {
    static let cols = 8, rows = 5, perPage = cols * rows
    static let tabBase = 600, tileBase = 700
    static let prevPage = 690, nextPage = 691, filterBtn = 692
    static let craft1 = 800, craftStack = 801, craftMax = 802, amountDown = 803, amountUp = 804, craftAmount = 805, gridBtn = 806
    static let amounts = [1, 2, 3, 4, 5, 8, 10, 16, 20, 32, 64]
    static var lastTab: CraftCategory = .craftable
    static var showAll = true

    let size: Int
    var tab: CraftCategory = CraftingBookMenu.lastTab
    var page = 0
    var list: [Int] = []                       // indices into Recipes.all for this tab
    var selected: Int?                         // recipe index shown in the detail panel
    var amount = 8
    var pool: [ItemID: Int] = [:]
    var holdA: Double = 0, repeatT: Double = 0  // A held on a tile: repeat crafting
    var lastCraftMessage = ""

    // Every recipe that fits this grid, one per result item, grouped by category (cached per grid size).
    static var byCategory: [Int: [CraftCategory: [Int]]] = [:]
    static func catalogue(_ size: Int) -> [CraftCategory: [Int]] {
        if let c = byCategory[size] { return c }
        var out: [CraftCategory: [Int]] = [:]
        var seen = Set<ItemID>()
        for (i, r) in Recipes.all.enumerated() {
            let fits = r.shapeless.isEmpty ? (r.w <= size && r.h <= size) : r.shapeless.count <= size * size
            guard fits, !seen.contains(r.result.item) else { continue }
            seen.insert(r.result.item)
            out[CraftCategory.of(r.result.item), default: []].append(i)
        }
        byCategory[size] = out
        return out
    }

    init(game: Game, size: Int = 3) {
        self.size = size
        super.init(size == 3 ? "Crafting" : "Crafting (2x2)", game: game)
        width = 344
        height = 262
        showInventoryLabel = false
        for t in CraftCategory.allCases {
            let b = MenuSlot(8 + t.rawValue * 23, 16, nil, 0, .button(CraftingBookMenu.tabBase + t.rawValue)); b.w = 21; b.h = 20
            slots.append(b)
        }
        for k in 0..<CraftingBookMenu.perPage {
            let b = MenuSlot(8 + (k % CraftingBookMenu.cols) * 22, 52 + (k / CraftingBookMenu.cols) * 22, nil, 0, .button(CraftingBookMenu.tileBase + k))
            b.w = 20; b.h = 20
            slots.append(b)
        }
        for (id, x, w) in [(CraftingBookMenu.prevPage, 8, 22), (CraftingBookMenu.filterBtn, 64, 64), (CraftingBookMenu.nextPage, 162, 22)] {
            let b = MenuSlot(x, 164, nil, 0, .button(id)); b.w = w; b.h = 12
            slots.append(b)
        }
        for (i, id) in [CraftingBookMenu.craft1, CraftingBookMenu.craftStack, CraftingBookMenu.craftMax].enumerated() {
            let b = MenuSlot(196, 150 + i * 19, nil, 0, .button(id)); b.w = 140; b.h = 16
            slots.append(b)
        }
        for (id, x, w) in [(CraftingBookMenu.amountDown, 196, 18), (CraftingBookMenu.craftAmount, 218, 96), (CraftingBookMenu.amountUp, 318, 18)] {
            let b = MenuSlot(x, 207, nil, 0, .button(id)); b.w = w; b.h = 16
            slots.append(b)
        }
        // The manual grid (a table's 3x3, or the inventory with its 2x2 grid and armour).
        let gb = MenuSlot(196, 228, nil, 0, .button(CraftingBookMenu.gridBtn)); gb.w = 140; gb.h = 16
        slots.append(gb)
        addPlayerInventory(y: 186, x: 8)
        refresh()
    }

    var pages: Int { max(1, (list.count + CraftingBookMenu.perPage - 1) / CraftingBookMenu.perPage) }

    func refresh() {
        pool = CraftBook.pool(game)
        let cat = CraftingBookMenu.catalogue(size)
        if tab == .craftable {
            list = CraftCategory.allCases.dropFirst().flatMap { cat[$0] ?? [] }.filter { RecipeBook.craftable(Recipes.all[$0], pool) }
        } else {
            let all = cat[tab] ?? []
            list = CraftingBookMenu.showAll ? all : all.filter { RecipeBook.craftable(Recipes.all[$0], pool) }
        }
        page = min(page, pages - 1)
    }

    override func changed() { refresh() }

    func recipe(at k: Int) -> Int? {
        let i = page * CraftingBookMenu.perPage + k
        return i < list.count ? list[i] : nil
    }

    func switchTab(_ d: Int) {
        let n = CraftCategory.allCases.count
        tab = CraftCategory(rawValue: (tab.rawValue + d + n) % n) ?? .craftable
        CraftingBookMenu.lastTab = tab
        page = 0
        refresh()
        game.sfx(.click, 0.4)
    }

    func flip(_ d: Int) {
        let np = max(0, min(pages - 1, page + d))
        if np != page { page = np; game.sfx(.uiHover, 0.5) }
    }

    // Crafts the recipe of tile k (or the selected recipe): 1, a stack, the maximum, or `times`.
    func craftTile(_ i: Int, times: Int) {
        let r = Recipes.all[i]
        selected = i
        let made = CraftBook.craft(r, times: times, game: game)
        if made == 0 {
            let can = CraftBook.maxCrafts(r, CraftBook.pool(game)) > 0
            lastCraftMessage = can ? "No room in the inventory" : "Missing ingredients"
            game.sfx(.click, 0.25)
        } else {
            lastCraftMessage = "Crafted \(made * r.result.count) \(r.result.def.display)"
        }
        refresh()
    }

    override func click(_ slot: MenuSlot, button: Int, shift: Bool) {
        guard case .button(let id) = slot.kind else { super.click(slot, button: button, shift: shift); return }
        switch id {
        case CraftingBookMenu.tileBase..<(CraftingBookMenu.tileBase + CraftingBookMenu.perPage):
            guard let i = recipe(at: id - CraftingBookMenu.tileBase) else { return }
            let r = Recipes.all[i]
            // Click: one. Shift-click / Y: a stack. Right-click / X: as many as possible.
            craftTile(i, times: shift ? CraftBook.stackTimes(r) : (button == 1 ? 9999 : 1))
        default:
            buttonPressed(id)
        }
    }

    override func buttonPressed(_ id: Int) {
        switch id {
        case CraftingBookMenu.tabBase..<(CraftingBookMenu.tabBase + CraftCategory.allCases.count):
            tab = CraftCategory(rawValue: id - CraftingBookMenu.tabBase) ?? .craftable
            CraftingBookMenu.lastTab = tab
            page = 0; refresh(); game.sfx(.click, 0.4)
        case CraftingBookMenu.prevPage: flip(-1)
        case CraftingBookMenu.nextPage: flip(1)
        case CraftingBookMenu.filterBtn:
            CraftingBookMenu.showAll.toggle(); page = 0; refresh(); game.sfx(.click, 0.4)
        case CraftingBookMenu.craft1, CraftingBookMenu.craftStack, CraftingBookMenu.craftMax, CraftingBookMenu.craftAmount:
            guard let i = selected else { return }
            let r = Recipes.all[i]
            let t = id == CraftingBookMenu.craft1 ? 1 : (id == CraftingBookMenu.craftStack ? CraftBook.stackTimes(r) : (id == CraftingBookMenu.craftMax ? 9999 : amount))
            craftTile(i, times: t)
        case CraftingBookMenu.amountDown, CraftingBookMenu.amountUp:
            let a = CraftingBookMenu.amounts
            let k = a.firstIndex(where: { $0 >= amount }) ?? 0
            amount = a[max(0, min(a.count - 1, k + (id == CraftingBookMenu.amountUp ? 1 : -1)))]
            game.sfx(.click, 0.3)
        case CraftingBookMenu.gridBtn:
            game.switchMenu(to: size == 3 ? CraftingTableMenu(game: game) : InventoryMenu(game: game))
        default: break
        }
    }

    // Per frame: the hovered tile becomes the selected recipe.
    override func tick() {
        if let h = game.menuHover, case .button(let id) = h.kind, id >= CraftingBookMenu.tileBase, id < CraftingBookMenu.tileBase + CraftingBookMenu.perPage,
           let i = recipe(at: id - CraftingBookMenu.tileBase) {
            selected = i
        }
    }

    // Pad: A held on a tile keeps crafting (after 0.4 s, then faster and faster).
    func padHold(_ aHeld: Bool, _ dt: Double) {
        guard aHeld, let h = game.menuHover, case .button(let id) = h.kind, id >= CraftingBookMenu.tileBase,
              id < CraftingBookMenu.tileBase + CraftingBookMenu.perPage, let i = recipe(at: id - CraftingBookMenu.tileBase) else {
            holdA = 0; repeatT = 0; return
        }
        holdA += dt
        guard holdA > 0.4 else { return }
        repeatT -= dt
        if repeatT <= 0 {
            craftTile(i, times: 1)
            repeatT = max(0.03, 0.12 - (holdA - 0.4) * 0.05)
        }
    }

    // MARK: Drawing (HudLines inside the panel)

    var legend: String {
        if let h = game.menuHover, case .button(let id) = h.kind, id >= CraftingBookMenu.tileBase, id < CraftingBookMenu.tileBase + CraftingBookMenu.perPage {
            return Prompt.line([(.select, "Craft 1 (hold: more)"), (.quick, "Stack"), (.alt, "Max"), (.tabs, "Category"), (.back, "Close")])
        }
        return Prompt.line([(.select, "Select"), (.tabs, "Category"), (.back, "Close")])
    }

    func drawLines(_ L: HudLayout, _ o: V2) -> [HudLine] {
        let s = L.s
        var out: [HudLine] = []
        func box(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: V4) {
            out.append(HudLine(text: "", x: o.x + Float(x) * s, y: o.y + Float(y) * s, scale: s, bg: c, box: V2(Float(w) * s, Float(h) * s)))
        }
        func label(_ t: String, _ x: Int, _ y: Int, _ c: V4 = V4(1, 1, 1, 1), maxW: Int = 400) {
            var t = t
            while Float(Font.width(t)) > Float(maxW) && t.count > 2 { t = String(t.dropLast(2)) + "." }
            out.append(HudLine(text: t, x: o.x + Float(x) * s, y: o.y + Float(y) * s, scale: s, color: c))
        }
        func icon(_ st: ItemStack, _ x: Int, _ y: Int, _ size: Int = 16) {
            out.append(HudLine(text: "", x: o.x + Float(x) * s, y: o.y + Float(y) * s, scale: s, box: V2(Float(size) * s, Float(size) * s), item: st))
        }
        let ink = V4(0.18, 0.18, 0.2, 1)
        let focus = V4(0.2, 0.32, 0.68, 1)
        let cb = Settings.shared.colorblind
        let good = cb ? V4(0.35, 0.5, 0.75, 1) : V4(0.42, 0.62, 0.4, 1)
        let hover = game.menuHover
        // Tabs.
        for sl in slots {
            guard case .button(let id) = sl.kind, id >= CraftingBookMenu.tabBase, id < CraftingBookMenu.tabBase + CraftCategory.allCases.count,
                  let t = CraftCategory(rawValue: id - CraftingBookMenu.tabBase) else { continue }
            let on = t == tab, hot = hover === sl
            box(sl.x, sl.y, sl.w, sl.h, on ? V4(0.95, 0.95, 0.95, 1) : (hot ? V4(0.6, 0.66, 0.8, 1) : V4(0.5, 0.5, 0.52, 1)))
            if on { box(sl.x, sl.y + sl.h - 2, sl.w, 2, focus) }
            if Items.has(t.icon) { icon(ItemStack(Items.id(t.icon), 1), sl.x + 2, sl.y + 2) }
        }
        label("\(tab.name)  -  page \(page + 1)/\(pages)", 8, 40, ink, maxW: 180)
        // Recipe tiles: craftable bright with a green rim, the rest dimmed.
        for k in 0..<CraftingBookMenu.perPage {
            let sl = slots[CraftCategory.allCases.count + k]
            guard let i = recipe(at: k) else { box(sl.x, sl.y, sl.w, sl.h, V4(0.66, 0.66, 0.68, 1)); continue }
            let r = Recipes.all[i]
            let ok = RecipeBook.craftable(r, pool)
            let hot = hover === sl
            box(sl.x - 1, sl.y - 1, sl.w + 2, sl.h + 2, hot ? focus : (ok ? good : V4(0.42, 0.42, 0.44, 1)))
            box(sl.x, sl.y, sl.w, sl.h, ok ? V4(0.86, 0.9, 0.86, 1) : V4(0.6, 0.6, 0.62, 1))
            icon(r.result, sl.x + 2, sl.y + 2)
            if !ok { box(sl.x, sl.y, sl.w, sl.h, V4(0.35, 0.35, 0.38, 0.55)) }
            let since = Float(game.clock - CraftBook.flashAt)
            if r.result.item == CraftBook.flashItem && since < 0.3 { box(sl.x, sl.y, sl.w, sl.h, V4(1, 1, 0.82, 0.65 * (1 - since / 0.3))) }
        }
        if list.isEmpty {
            label(tab == .craftable ? "Nothing craftable yet: gather materials" : "No recipes here", 14, 100, ink, maxW: 170)
        }
        // Page and filter buttons.
        for sl in slots {
            guard case .button(let id) = sl.kind, [CraftingBookMenu.prevPage, CraftingBookMenu.nextPage, CraftingBookMenu.filterBtn].contains(id) else { continue }
            box(sl.x, sl.y, sl.w, sl.h, hover === sl ? focus : V4(0.36, 0.36, 0.4, 1))
            let t = id == CraftingBookMenu.prevPage ? "<" : (id == CraftingBookMenu.nextPage ? ">" : (CraftingBookMenu.showAll ? "Show: All" : "Show: Can"))
            label(t, sl.x + (sl.w - Font.width(t)) / 2, sl.y + 3)
        }
        // Detail panel.
        box(192, 36, 146, 140, V4(0.7, 0.7, 0.72, 1))
        if let i = selected {
            let r = Recipes.all[i]
            let have = CraftBook.maxCrafts(r, pool)
            box(196, 40, 36, 36, V4(0.55, 0.55, 0.58, 1))
            icon(r.result, 198, 42, 32)
            label(r.result.def.display, 236, 42, ink, maxW: 100)
            label("Makes \(r.result.count)", 236, 54, V4(0.3, 0.3, 0.34, 1), maxW: 100)
            label(have > 0 ? "Can craft \(have)" : "Missing items", 236, 66, have > 0 ? (cb ? V4(0.15, 0.3, 0.6, 1) : V4(0.1, 0.42, 0.12, 1)) : V4(0.6, 0.12, 0.1, 1), maxW: 100)
            // Ingredient grid (3x3 or 2x2) with each cell's item; red where you have none.
            let g = max(r.w, 1), cells: [String?] = r.shapeless.isEmpty ? r.cells : r.shapeless.map { Optional($0) }
            let cw = r.shapeless.isEmpty ? g : min(3, r.shapeless.count)
            for (c, ing) in cells.enumerated() {
                let cx = 198 + (c % max(1, cw)) * 19, cy = 84 + (c / max(1, cw)) * 19
                box(cx, cy, 18, 18, V4(0.45, 0.45, 0.48, 1))
                guard let ing = ing else { continue }
                let opts = ing.hasPrefix("#") ? Array(Recipes.tagSets[String(ing.dropFirst())] ?? []) : (Items.has(ing) ? [Items.id(ing)] : [])
                let owned = opts.first { (pool[$0] ?? 0) > 0 }
                let shown = owned ?? opts.sorted().first
                if owned == nil { box(cx, cy, 18, 18, V4(0.7, 0.2, 0.2, 0.6)) }
                if let it = shown { icon(ItemStack(it, 1), cx + 1, cy + 1) }
            }
            // What you have of each distinct ingredient.
            var rowsDone = Set<String>()
            var ly = 86
            // Count and name on two lines when there is room (one line cut names short: "84/3 Oak Plan.", TV shot).
            let twoLines = Set(CraftBook.needs(r)).count <= 3
            for ing in CraftBook.needs(r) where !rowsDone.contains(ing) && ly < 140 {
                rowsDone.insert(ing)
                let need = CraftBook.needs(r).filter { $0 == ing }.count
                let opts = ing.hasPrefix("#") ? Array(Recipes.tagSets[String(ing.dropFirst())] ?? []) : (Items.has(ing) ? [Items.id(ing)] : [])
                let got = opts.reduce(0) { $0 + (pool[$1] ?? 0) }
                let nm = ing.hasPrefix("#") ? "Any " + String(ing.dropFirst()).replacingOccurrences(of: "_", with: " ") : (opts.first.map { Items.def($0).display } ?? ing)
                let col = got >= need ? ink : V4(0.6, 0.12, 0.1, 1)
                if twoLines {
                    label("\(got) / \(need)", 258, ly, col, maxW: 78)
                    label(nm, 258, ly + 9, col, maxW: 78)
                    ly += 20
                } else {
                    label("\(got)/\(need) \(nm)", 258, ly, col, maxW: 78)
                    ly += 11
                }
            }
        } else {
            label("Choose a recipe", 200, 60, ink, maxW: 130)
        }
        // Craft buttons.
        for sl in slots {
            guard case .button(let id) = sl.kind, id >= CraftingBookMenu.craft1, id <= CraftingBookMenu.gridBtn else { continue }
            let hot = hover === sl
            box(sl.x, sl.y, sl.w, sl.h, hot ? focus : V4(0.36, 0.36, 0.4, 1))
            var t = ""
            switch id {
            case CraftingBookMenu.craft1: t = "Craft 1"
            case CraftingBookMenu.craftStack: t = "Craft a stack"
            case CraftingBookMenu.craftMax: t = "Craft max"
            case CraftingBookMenu.amountDown: t = "-"
            case CraftingBookMenu.amountUp: t = "+"
            case CraftingBookMenu.craftAmount: t = "Craft \(amount)x"
            default: t = size == 3 ? "Manual grid" : "Inventory & 2x2 grid"
            }
            label(t, sl.x + (sl.w - Font.width(t)) / 2, sl.y + 4)
        }
        if !lastCraftMessage.isEmpty { label(lastCraftMessage, 196, 248, ink, maxW: 144) }
        label("Inventory", 8, 177, ink)
        return out
    }
}

extension Game {
    // Replaces the open screen (the old one tidies up first: grid items back to the inventory).
    func switchMenu(to m: Menu) {
        menu?.onClose()
        openMenu(m)
    }
}
