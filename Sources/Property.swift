import Foundation
import simd

// D28: buy a homestead or a town house. Every notice board's land office sells two deeds:
//   town house deed  ($80)  use it inside a town building nobody lives in: that building is yours. Its blocks and
//                           containers stop being town property (TownLaw.isTownOwned), so you can rebuild it and keep
//                           your things in its chests; your spawn moves there and it goes on the map ("H").
//   homestead deed   ($150) use it out in open country, 120 blocks or more from any town: you stake a homestead. A
//                           log cabin goes up where you stand (bed, a chest of seeds and tools, a lantern, a door and a
//                           hitching fence), your spawn moves there and it goes on the map ("H").
// Owned ground is kept in TownLaw.state.property (boxes: min x, y, z, max x, y, z).
enum Property {
    static let townKey = "town_house_deed", homeKey = "homestead_deed"
    static let townPrice = 8000, homePrice = 15000
    static let wildFromTown = 120
    static var bought = 0                            // (harness)

    static func owns(_ p: IVec3) -> Bool {
        for b in TownLaw.state.property ?? [] where b.count == 6 {
            if p.x >= b[0] && p.y >= b[1] && p.z >= b[2] && p.x <= b[3] && p.y <= b[4] && p.z <= b[5] { return true }
        }
        return false
    }

    static func claim(_ a: IVec3, _ b: IVec3) {
        var o = TownLaw.state.property ?? []
        o.append([a.x, a.y, a.z, b.x, b.y, b.z])
        TownLaw.state.property = o
        bought += 1
    }

    // Use with a deed in hand.
    static func use(_ g: Game, _ key: String) -> Bool {
        guard g.dim.dim == .overworld else { g.onToast?("A deed is only good on the surface of this world"); return true }
        let p = IVec3(Int(floor(g.player.pos.x)), Int(floor(g.player.pos.y)), Int(floor(g.player.pos.z)))
        return key == townKey ? townHouse(g, p) : homestead(g, p)
    }

    static func townHouse(_ g: Game, _ p: IVec3) -> Bool {
        guard let sc = g.world.gen.structures, let s = sc.nearest("village", x: p.x, z: p.z, maxRegions: 1),
              abs(s.anchor.x - p.x) < 200 && abs(s.anchor.z - p.z) < 200 else {
            g.onToast?("Nothing here for sale"); return true
        }
        if owns(p) { g.onToast?("This place is already yours"); return true }
        // The smallest building piece around you, under a roof.
        let around = s.pieces.filter { pc in
            p.x >= pc.min.x && p.x <= pc.max.x && p.z >= pc.min.z && p.z <= pc.max.z && p.y >= pc.min.y && p.y <= pc.max.y
                && pc.max.y - pc.min.y >= 8
        }
        guard let pc = around.min(by: { ($0.max.x - $0.min.x) * ($0.max.z - $0.min.z) < ($1.max.x - $1.min.x) * ($1.max.z - $1.min.z) }),
              roofed(g, p) else {
            g.onToast?("Nothing here for sale"); return true
        }
        let inside = { (q: V3) in Float(pc.min.x) <= q.x && q.x <= Float(pc.max.x + 1) && Float(pc.min.z) <= q.z && q.z <= Float(pc.max.z + 1) }
        if g.mobs.mobs.contains(where: { TownLaw.isTownsperson($0) && $0.villager?.role != "prisoner" && (inside($0.home ?? $0.pos) || ($0.villager?.bed).map { $0.count == 3 && inside(V3(Float($0[0]), 0, Float($0[2]))) } == true) }) {
            g.onToast?("Somebody lives here")
            return true
        }
        if TownLaw.isHostile(Townsfolk.town(g, at: g.player.pos)) {
            g.onToast?("This town won't sell to you"); return true
        }
        claim(pc.min, pc.max)
        if g.survival { g.consumeHeld() }
        g.spawnPoint = g.player.pos
        MapCache.shared.discover(g, kind: "property", x: p.x, z: p.z, name: "Your house in \(Townsfolk.town(g, at: g.player.pos))")
        g.sfx(.levelUp, 0.7)
        g.onToast?("The house is yours")
        return true
    }

    static func roofed(_ g: Game, _ p: IVec3) -> Bool {
        for dy in 2...8 where g.world.opaqueAt(p.x, p.y + dy, p.z) { return true }
        return false
    }

    static func homestead(_ g: Game, _ p: IVec3) -> Bool {
        if let sc = g.world.gen.structures, let s = sc.nearest("village", x: p.x, z: p.z, maxRegions: 2),
           abs(s.anchor.x - p.x) < wildFromTown && abs(s.anchor.z - p.z) < wildFromTown {
            g.onToast?("Too close to town"); return true
        }
        // A 7 x 7 footprint, ground within two blocks of level, dry.
        let y0 = g.world.topY(p.x, p.z) + 1
        for dx in -3...3 { for dz in -3...3 {
            let t = g.world.topY(p.x + dx, p.z + dz) + 1
            if abs(t - y0) > 2 || Blocks.isLiquid(g.world.builtBlock(p.x + dx, t - 1, p.z + dz)) {
                g.onToast?("Too rough for a cabin"); return true
            }
        } }
        build(g, p.x, y0, p.z)
        claim(IVec3(p.x - 12, y0 - 8, p.z - 12), IVec3(p.x + 12, y0 + 24, p.z + 12))
        if g.survival { g.consumeHeld() }
        g.spawnPoint = V3(Float(p.x) + 0.5, Float(y0), Float(p.z) + 0.5)
        g.player.pos = g.spawnPoint
        MapCache.shared.discover(g, kind: "property", x: p.x, z: p.z, name: "Your homestead")
        g.sfx(.levelUp, 0.8)
        g.onToast?("You've staked your homestead")
        return true
    }

    static func b(_ n: String, _ f: String) -> BlockID { Blocks.has(n) ? Blocks.id(n) : Blocks.id(f) }

    // The cabin: log corners, plank walls and floor, a slab roof, a door on the north side.
    static func build(_ g: Game, _ cx: Int, _ y: Int, _ cz: Int) {
        let w = g.world
        let log = b("spruce_log", "oak_log"), plank = b("spruce_planks", "oak_planks"), slab = b("spruce_slab", "oak_slab")
        let floor = b("spruce_planks", "oak_planks"), stone = b("cobblestone", "stone"), fence = b("spruce_fence", "oak_fence")
        for dx in -3...3 { for dz in -3...3 {
            let x = cx + dx, z = cz + dz
            // Ground under it filled, the space above cleared.
            var fy = y - 1
            while fy > y - 5 && !w.opaqueAt(x, fy, z) { w.setBlock(x, fy, z, stone); fy -= 1 }
            w.setBlock(x, y - 1, z, abs(dx) == 3 || abs(dz) == 3 ? stone : floor)
            for dy in 0...5 { w.setBlock(x, y + dy, z, AIR) }
            let edge = abs(dx) == 3 || abs(dz) == 3, corner = abs(dx) == 3 && abs(dz) == 3
            if edge { for dy in 0...2 { w.setBlock(x, y + dy, z, corner ? log : plank) } }
            w.setBlock(x, y + 3, z, slab)
        } }
        // Windows east and west.
        if Blocks.has("glass_pane") { w.setBlock(cx + 3, y + 1, cz, Blocks.id("glass_pane")); w.setBlock(cx - 3, y + 1, cz, Blocks.id("glass_pane")) }
        // The door, north.
        let door = b("spruce_door", "oak_door")
        w.setBlock(cx, y, cz - 3, door); w.setBlock(cx, y + 1, cz - 3, door + 8)
        // Bed, chest, lantern, a crafting table.
        if Blocks.has("red_bed") && Blocks.has("red_bed_head") {
            w.setBlock(cx - 2, y, cz + 1, Blocks.id("red_bed")); w.setBlock(cx - 2, y, cz + 2, Blocks.id("red_bed_head"))
        }
        if Blocks.has("crafting_table") { w.setBlock(cx + 2, y, cz + 2, Blocks.id("crafting_table")) }
        if Blocks.has("lantern") { w.setBlock(cx, y + 2, cz, Blocks.id("lantern")) }
        if Blocks.has("chest") {
            let at = IVec3(cx + 2, y, cz - 1)
            w.setBlock(at.x, at.y, at.z, Blocks.id("chest"))
            let be = BlockEntity(.chest)
            var i = 0
            for (k, n) in [("wheat_seeds", 16), ("carrot", 4), ("potato", 4), ("iron_hoe", 1), ("iron_axe", 1), ("bread", 6), ("torch", 16), ("bucket", 1)]
            where Items.has(k) && i < be.items.count { be.items[i] = ItemStack(Items.id(k), n); i += 1 }
            w.blockEntities[at] = be
        }
        // A hitching rail out front.
        for dx in -2...2 where dx != 0 { w.setBlock(cx + dx, w.topY(cx + dx, cz - 6) + 1, cz - 6, fence) }
    }
}

extension ItemRegistry {
    func registerDeeds() {
        for (k, name, col) in [(Property.townKey, "Town House Deed", 0xE8D8A8), (Property.homeKey, "Homestead Deed", 0xD8C890)] where !has(k) {
            var d = ItemDef(k, name)
            d.sprite = Sprite(mask: "paper", base: UInt32(col), extras: [:])
            d.maxStack = 1
            add(d)
        }
    }
}
