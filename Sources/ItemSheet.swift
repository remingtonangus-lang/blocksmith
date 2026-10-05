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
