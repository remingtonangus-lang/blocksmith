import Foundation

// Harness item sheets (--itemsheet KIND[:SCALE[:PAGE]]): every item's icon in a grid, drawn through the HUD's own
// icon path, for before/after comparisons and the blind critic. KIND: tools (tools, weapons, armour), items (every
// non-block item), blocks (block items), enchanted (tools and armour with the glint). SCALE: pixels per icon pixel
// (2 = desktop hotbar, 4 = TV). PAGE: which screenful.
enum ItemSheet {
    struct Request { var kind: String; var scale: Float; var page: Int }
    static var request: Request?

    static func items(_ kind: String) -> [ItemStack] {
        var out: [ItemStack] = []
        for i in 1..<Items.count {
            let id = ItemID(i)
            let d = Items.def(id)
            let toolish = d.tool != .none || d.armorSlot != nil || d.attack > 1 || d.durability > 0
            switch kind {
            case "blocks": if d.block != nil && d.sprite == nil { out.append(ItemStack(id, 1)) }
            case "tools", "enchanted":
                if toolish && d.sprite != nil {
                    var st = ItemStack(id, 1)
                    if kind == "enchanted" { st.ench = 1 }
                    out.append(st)
                }
            default: if d.sprite != nil || d.texKey != nil { out.append(ItemStack(id, 1)) }
            }
        }
        return out
    }

    static func parse(_ arg: String) -> Request {
        let p = arg.split(separator: ":").map(String.init)
        return Request(kind: p.first ?? "items", scale: p.count > 1 ? Float(p[1]) ?? 2 : 2, page: p.count > 2 ? Int(p[2]) ?? 0 : 0)
    }
}

// --itemcheck: every vector-designed item icon (ItemHD) rendered at the layer size and checked: it covers a sane share
// of the icon (3-85 %), stays off the icon's border (clipped designs), and overlay pairs split into a non-empty base and
// tint. Prints the counts (vector / pixel-art fallback) and the generation cost (startup time).
extension ItemSheet {
    static func check(size n: Int = 128) -> Int {
        var names: [String] = []
        for i in 1..<Items.count {
            let d = Items.def(ItemID(i))
            if let k = d.texKey { names.append(k) } else if d.sprite != nil { names.append("item_" + d.name) }
            if let o = d.overlay { names.append(o) }
        }
        names = Array(Set(names)).sorted()
        var vector = 0, fallback = 0, fails = 0
        let t0 = Date()
        for name in names {
            let item = String(name.dropFirst(5))
            var px: [V4]? = nil
            if let (k, m) = ItemHD.design(item) { px = ItemHD.vector(k, m, n) }
            else if ItemHD.gunKeys.contains(item) { px = ItemHD.render(ItemHD.gunCanvas(item, n)) }
            else if let (shell, layout) = ItemHD.eggShells[item] { px = ItemHD.render(ItemHD.eggCanvas(shell, layout: layout, n)) }
            else if let (key, ov) = ItemHD.pairKeys[name] { px = ItemHD.render(ItemHD.pairCanvas(key, n), split: ov ? 2 : 1) }
            else if let sp = ItemHD.spriteByItem[item] {
                let cv = ItemHD.Canvas(n)
                if ItemHD.family(cv, item, sp) { px = ItemHD.render(cv) }
            }
            guard let img = px else { fallback += 1; continue }
            vector += 1
            var cov = 0, border = 0
            for y in 0..<n { for x in 0..<n where img[y * n + x].w >= 0.5 {
                cov += 1
                if x == 0 || y == 0 || x == n - 1 || y == n - 1 { border += 1 }
            } }
            let share = Float(cov) / Float(n * n)
            if share < 0.03 || share > 0.85 || border > n / 2 {
                fails += 1
                print(String(format: "itemcheck FAIL %@: coverage %.1f%%, %ld border pixels", name, share * 100, border))
            }
        }
        let ms = Date().timeIntervalSince(t0) * 1000
        print(String(format: "itemcheck: %ld layers, %ld vector, %ld pixel-art fallback, %ld fail; vector generation %.0f ms total (%.2f ms each, one core)",
                     names.count, vector, fallback, fails, ms, ms / Double(max(1, vector))))
        // 3D models (ItemModels.swift): build cost (background queue in play) and size. The first-person buffer holds
        // Renderer.heldVertCap vertices: a model and its overlay at 6 per quad must fit.
        let (models, mean, worst, avgQ, mostQ, bytes) = ItemModels.measure()
        print(String(format: "itemcheck: %ld item models, build %.2f ms mean, %.2f worst; %.0f quads mean, %ld most; %.1f MB if every model is kept",
                     models, mean, worst, avgQ, mostQ, Double(bytes) / 1_048_576))
        if mostQ * 12 > Renderer.heldVertCap {
            fails += 1
            print("itemcheck FAIL: a model of \(mostQ) quads overflows the held-item buffer (\(Renderer.heldVertCap) vertices)")
        }
        return fails
    }
}
