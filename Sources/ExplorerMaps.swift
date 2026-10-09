import Foundation
import simd

// Explorer maps (reference cartographer trades): a map that leads to the nearest structure of a kind.
// Using one turns it into a filled map centred near the structure, 2 blocks per pixel, with the
// coastline sketched in from the terrain generator and the destination marked. Sea Temple and Forest
// Manor maps follow the reference; the Steelhold map is Blocksmith's own (master cartographers).
enum ExplorerMaps {
    struct Kind { let item: String; let name: String; let structure: String; let color: UInt32 }
    static let kinds: [Kind] = [
        Kind(item: "sea_temple_explorer_map", name: "Sea Temple Explorer Map", structure: "monument", color: 0x3AA8A0),
        Kind(item: "manor_explorer_map", name: "Forest Manor Explorer Map", structure: "mansion", color: 0x6A4A2A),
        Kind(item: "steelhold_explorer_map", name: "Capital Explorer Map", structure: "military_base", color: 0xE0B020),
        // Sold in town (general store, saloon: Shops.swift): leads to the nearest buried treasure.
        Kind(item: "treasure_map", name: "Treasure Map", structure: "buried_treasure", color: 0xC03020),
    ]

    static func register(_ reg: ItemRegistry) {
        for k in kinds where !reg.has(k.item) {
            var d = ItemDef(k.item, k.name)
            d.texKey = "item_map"
            d.overlay = "item_explorer_mark"
            d.overlayColor = k.color
            d.maxStack = 1
            reg.add(d)
        }
    }

    static func painters(_ p: inout [String: TextureGen.Painter]) {
        // A small cross in the lower right of the map icon, tinted per map.
        p["item_explorer_mark"] = { x, y in
            let cx = 11, cy = 11
            let d1 = x - cx, d2 = y - cy
            return (abs(d1) <= 2 && abs(d2) <= 2 && (d1 == d2 || d1 == -d2)) ? V4(1, 1, 1, 1) : TextureGen.clear
        }
    }
}

extension Game {
    // Right-click with an explorer map: locate the structure and turn the map into a filled one.
    func useExplorerMap() -> Bool {
        guard let k = ExplorerMaps.kinds.first(where: { $0.item == Items.key(held.item) }), Items.has("filled_map") else { return false }
        guard dim.dim == .overworld, let sc = world.gen.structures,
              let s = sc.nearest(k.structure, x: Int(floor(player.pos.x)), z: Int(floor(player.pos.z)), maxRegions: 10) else {
            onToast?("The map shows nothing nearby")
            return true
        }
        let tx = (s.min.x + s.max.x) / 2, tz = (s.min.z + s.max.z) / 2
        // Reference: scale 1 (2 blocks per pixel), aligned to the map grid.
        let scale = 1, size = 128 << scale
        let cx = Int(floor(Float(tx + size / 2) / Float(size))) * size, cz = Int(floor(Float(tz + size / 2) / Float(size))) * size
        let m = MapData(cx: cx, cz: cz, scale: scale, dim: "overworld")
        // Sketch land and water from the generator so the way there is readable.
        let per = 1 << scale
        for z in 0..<128 { for x in 0..<128 {
            let wx = cx + (x - 64) * per, wz = cz + (z - 64) * per
            let c = world.gen.column(wx, wz)
            let water = c.height < SEA || c.biome.isOcean || c.biome.isRiver
            m.colors[x + z * 128] = (water ? 0x6F8FC8 : 0xD8C49A) | 0xFF000000
        } }
        m.marker = [tx, tz, Int(k.color)]
        let id = (maps.keys.max() ?? -1) + 1
        maps[id] = m
        var st = ItemStack(Items.id("filled_map"), 1)
        st.tag = id
        st.label = k.name
        giveOrReplaceHeld(st)
        sfx(.place(.plant), 0.5)
        return true
    }
}
