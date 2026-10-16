import Foundation
import simd

// Maps: using an empty map makes a filled map aligned to the reference 128-block grid (scale 0, one
// block per pixel; the cartography table zooms out to 1:16). Holding it fills in terrain colours (with
// the reference north-slope shading) within 64 pixels of the player; it is drawn on screen while held.
final class MapData: Codable {
    var cx: Int, cz: Int          // centre (blocks)
    var scale: Int                // 0...4 → 1, 2, 4, 8, 16 blocks per pixel
    var dim: String
    var colors: [UInt32]          // 128 x 128 RGBA (0 = unexplored)
    var locked = false
    var marker: [Int]? = nil     // explorer maps: destination x, z and colour
    init(cx: Int, cz: Int, scale: Int, dim: String) {
        self.cx = cx; self.cz = cz; self.scale = scale; self.dim = dim
        colors = [UInt32](repeating: 0, count: 128 * 128)
    }
}

enum MapColors {
    // Base colour for a map pixel from the top block (reference map-colour families).
    static func base(_ b: BlockID) -> UInt32 {
        let k = Blocks.key(Blocks.groupBase[Int(b)])
        if Blocks.fluidKind[Int(b)] == 1 || k.contains("kelp") || k.contains("seagrass") { return 0x4040FF }
        if Blocks.fluidKind[Int(b)] == 2 { return 0xFF0000 }
        if k.hasSuffix("grass_block") || k == "moss_block" || k == "short_grass" || k == "tall_grass" { return 0x7FB238 }
        if k.hasSuffix("_leaves") || k == "vine" || k == "bamboo" || k.hasSuffix("sapling") { return 0x007C00 }
        if k.contains("snow") || k == "powder_snow" || k.contains("white") { return 0xFFFFFF }
        if k.contains("ice") { return 0xA0A0FF }
        if k.contains("sand") && !k.contains("red") { return 0xF7E9A3 }
        if k.contains("red_sand") || k.contains("terracotta") { return 0xD87F33 }
        if k.contains("dirt") || k == "farmland" || k == "podzol" || k == "mud" || k == "coarse_dirt" { return 0x976D4D }
        if k.hasSuffix("_log") || k.hasSuffix("_planks") || k.hasSuffix("_wood") { return 0x8F7748 }
        if k.contains("netherrack") || k.contains("nether_") || k.contains("crimson") { return 0x700200 }
        if k.contains("warped") { return 0x167E86 }
        if k.contains("end_stone") { return 0xF7E9A3 }
        if k.contains("clay") { return 0xA4A8B8 }
        if k.contains("gravel") || k.contains("stone") || k.contains("deepslate") || k.contains("andesite") || k.contains("cobble") || k.contains("ore") { return 0x707070 }
        if k.contains("mycelium") { return 0x7F3FB2 }
        if k.contains("flower") || k == "poppy" || k == "dandelion" { return 0x007C00 }
        if k.contains("pumpkin") || k.contains("orange") { return 0xD87F33 }
        if k.contains("wool") || k.contains("concrete") { return 0xC8C8C8 }
        return 0x8A8A8A
    }
}

extension Game {
    // Right-click with an empty map: create a filled map here.
    func useEmptyMap() -> Bool {
        guard Items.key(held.item) == "map", Items.has("filled_map") else { return false }
        let scale = 0
        let size = 128 << scale
        let cx = Int(floor((player.pos.x + 64) / Float(size))) * size, cz = Int(floor((player.pos.z + 64) / Float(size))) * size
        let id = (maps.keys.max() ?? -1) + 1
        maps[id] = MapData(cx: cx, cz: cz, scale: scale, dim: dim.dim.folder ?? "overworld")
        var s = ItemStack(Items.id("filled_map"), 1)
        s.tag = id
        giveOrReplaceHeld(s)
        sfx(.pageTurn, 0.7)
        return true
    }

    // Fill in a few rows of the held map each frame.
    func mapTick() {
        guard Items.key(held.item) == "filled_map", let m = maps[held.tag], !m.locked, m.dim == (dim.dim.folder ?? "overworld") else { return }
        let per = 1 << m.scale
        let px = Int(floor(player.pos.x)), pz = Int(floor(player.pos.z))
        let ppx = (px - m.cx) / per + 64, ppz = (pz - m.cz) / per + 64
        mapRow = (mapRow + 1) % 128
        let z = mapRow
        guard abs(z - ppz) < 64 else { return }
        // Held far east or west of its area (an explorer map just bought), the range inverted: -Ounchecked ran the loop
        // up from the lower bound, writing past the colour array and hanging every frame.
        let lo = max(0, ppx - 64), hi = min(128, ppx + 64)
        guard lo < hi else { return }
        for x in lo..<hi {
            let dx = x - ppx, dz = z - ppz
            if dx * dx + dz * dz > 64 * 64 { continue }
            let wx = m.cx + (x - 64) * per, wz = m.cz + (z - 64) * per
            guard world.isLoaded(wx, wz) else { continue }
            let y = world.topY(wx, wz)
            var b = world.block(wx, y, wz)
            var yy = y
            // Look through thin plants to the ground beneath.
            while yy > 0 && !Blocks.opaque[Int(b)] && !Blocks.isLiquid(b) && Blocks.render[Int(b)] == RenderType.cross.rawValue { yy -= 1; b = world.block(wx, yy, wz) }
            var col = MapColors.base(b)
            // North-slope shading (brighter uphill, darker downhill); depth shading for water.
            let north = world.topY(wx, wz - per)
            var k: Float = yy > north ? 1.0 : (yy < north ? 0.71 : 0.86)
            if Blocks.fluidKind[Int(b)] == 1 {
                var depth = 0
                while depth < 10 && Blocks.isLiquid(world.block(wx, yy - depth - 1, wz)) { depth += 1 }
                k = depth > 6 ? 0.71 : (depth > 2 ? 0.86 : 1)
            }
            let r = UInt32(Float((col >> 16) & 255) * k), g = UInt32(Float((col >> 8) & 255) * k), bl = UInt32(Float(col & 255) * k)
            col = (r << 16) | (g << 8) | bl | 0xFF000000
            m.colors[x + z * 128] = col
        }
    }
}

// Cartography table: zoom out (map + paper), copy (map + empty map), lock (map + glass pane).
final class CartographyMenu: Menu {
    let box = ItemContainer(2)
    let out = ItemContainer(1)
    init(game: Game) {
        super.init("Cartography Table", game: game)
        slots.append(MenuSlot(15, 15, box, 0))
        slots.append(MenuSlot(15, 52, box, 1))
        slots.append(MenuSlot(145, 39, out, 0, .result))
        addPlayerInventory()
    }
    func compute() -> ItemStack? {
        let a = box[0], b = box[1]
        guard Items.key(a.item) == "filled_map", !b.isEmpty, let m = game.maps[a.tag] else { return nil }
        switch Items.key(b.item) {
        case "paper" where m.scale < 4 && !m.locked:
            var s = a; s.tag = -1; return s          // zoomed copy made on take
        case "map": var s = a; s.count = 2; return s
        case "glass_pane" where !m.locked: var s = a; s.tag = -2; return s
        default: return nil
        }
    }
    override func changed() {
        if var r = compute() { if r.tag < 0 { r.tag = box[0].tag }; out[0] = r } else { out[0] = .empty }
    }
    override func takeResult(_ slot: MenuSlot) -> ItemStack? {
        guard let r = compute(), let m = game.maps[box[0].tag] else { return nil }
        var result = r
        if r.tag == -1 {
            // Zoom out: a new map at the next scale covering the old one.
            let scale = m.scale + 1, size = 128 << scale
            let nm = MapData(cx: Int(floor(Float(m.cx + 64) / Float(size))) * size, cz: Int(floor(Float(m.cz + 64) / Float(size))) * size, scale: scale, dim: m.dim)
            let id = (game.maps.keys.max() ?? -1) + 1
            game.maps[id] = nm
            result.tag = id
        } else if r.tag == -2 {
            m.locked = true
            result.tag = box[0].tag
        }
        for i in 0..<2 { var s = box[i]; s.count -= 1; box[i] = s.count > 0 ? s : .empty }
        changed()
        return result
    }
    override func onClose() {
        for i in 0..<2 where !box[i].isEmpty { let rest = game.inventory.add(box[i]); if !rest.isEmpty { game.dropItem(rest) }; box[i] = .empty }
    }
}
