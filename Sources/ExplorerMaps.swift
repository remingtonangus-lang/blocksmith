import Foundation
import simd

// Explorer maps (reference cartographer trades): a map that leads to the nearest structure of a kind.
// Using one turns it into a filled map centred near the structure, 2 blocks per pixel, with the
// coastline sketched in from the terrain generator and the destination marked. The Dreadnought and Brigand
// Roost maps (G20: the sites that replaced the Sea Temple and Forest Manor) and the Capital map (master cartographers).
enum ExplorerMaps {
    struct Kind { let item: String; let name: String; let structure: String; let color: UInt32 }
    static let kinds: [Kind] = [
        Kind(item: "sea_temple_explorer_map", name: "Dreadnought Explorer Map", structure: "monument", color: 0x3AA8A0),
        Kind(item: "manor_explorer_map", name: "Brigand Roost Explorer Map", structure: "mansion", color: 0x6A4A2A),
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
              let s = sc.nearest(k.structure, x: Int(floor(player.pos.x)), z: Int(floor(player.pos.z)), maxRegions: k.structure == "buried_treasure" ? 40 : 10) else {      // (treasure: rare beach chests, look 2.5 km out)
            onToast?("The map shows nothing nearby")
            return true
        }
        let tx = (s.min.x + s.max.x) / 2, tz = (s.min.z + s.max.z) / 2
        // P365 (c): a drawn map that shows the way: centred between here and the destination, zoomed out until both
        // are on it, the land painted (water by depth, sand, grass, forest, rock, snow, shaded on the north slopes) and
        // a dashed red trail from where it was opened to the mark. Locked, so holding it never paints over the drawing.
        let px0 = Int(floor(player.pos.x)), pz0 = Int(floor(player.pos.z))
        let span = max(abs(tx - px0), abs(tz - pz0))
        var scale = 0
        while scale < 4 && (128 << scale) < span + 48 { scale += 1 }
        let per = 1 << scale
        let cx = (tx + px0) / 2, cz = (tz + pz0) / 2
        let m = MapData(cx: cx, cz: cz, scale: scale, dim: "overworld")
        m.locked = true
        var hPrev = [Int](repeating: SEA, count: 128)
        for z in 0..<128 { for x in 0..<128 {
            let wx = cx + (x - 64) * per, wz = cz + (z - 64) * per
            let c = world.gen.column(wx, wz)
            let b = c.biome
            var rgb: SIMD3<Float>
            if c.height < SEA || b.isOcean || b.isRiver {
                let deep = min(1, Float(max(0, SEA - c.height)) / 24)
                rgb = SIMD3(0.44, 0.58, 0.80) * (1 - deep * 0.35)
            } else if b.isBeach || b == .desert {
                rgb = SIMD3(0.86, 0.79, 0.58)
            } else {
                switch b {
                case .badlands, .erodedBadlands, .woodedBadlands: rgb = SIMD3(0.78, 0.50, 0.32)
                case .forest, .birchForest, .darkForest, .oldGrowthBirchForest, .taiga, .oldGrowthPineTaiga, .oldGrowthSpruceTaiga,
                     .jungle, .bambooJungle, .sparseJungle, .paleGarden:
                    rgb = SIMD3(0.40, 0.56, 0.30)
                case .snowyPlains, .iceSpikes, .snowyTaiga, .snowySlopes, .frozenPeaks, .jaggedPeaks, .grove: rgb = SIMD3(0.92, 0.93, 0.95)
                case .stonyPeaks, .windsweptHills, .windsweptGravellyHills: rgb = SIMD3(0.60, 0.59, 0.56)
                case .swamp, .mangroveSwamp: rgb = SIMD3(0.42, 0.48, 0.32)
                default: rgb = SIMD3(0.62, 0.72, 0.42)
                }
                // Relief: lit where the ground rises to the south, shaded where it falls (the north slopes).
                let dh = Float(c.height - hPrev[x])
                rgb *= max(0.78, min(1.15, 1 + dh * 0.05 / Float(per)))
            }
            hPrev[x] = c.height
            let r = UInt32(min(255, rgb.x * 255)), g = UInt32(min(255, rgb.y * 255)), bl = UInt32(min(255, rgb.z * 255))
            m.colors[x + z * 128] = 0xFF000000 | r << 16 | g << 8 | bl
        } }
        // The trail: red dashes from the opening spot to the mark.
        let ax = Float(px0 - cx) / Float(per) + 64, az = Float(pz0 - cz) / Float(per) + 64
        let bx = Float(tx - cx) / Float(per) + 64, bz = Float(tz - cz) / Float(per) + 64
        let steps = Int(max(abs(bx - ax), abs(bz - az)))
        if steps > 8 {
            for i in 0...steps where (i / 4) % 2 == 0 && i < steps - 5 {
                let f = Float(i) / Float(steps)
                let x = Int(ax + (bx - ax) * f), z = Int(az + (bz - az) * f)
                if x >= 0 && x < 127 && z >= 0 && z < 127 {
                    for (ox, oz) in [(0, 0), (1, 0), (0, 1), (1, 1)] { m.colors[x + ox + (z + oz) * 128] = 0xFFB02818 }
                }
            }
        }
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
