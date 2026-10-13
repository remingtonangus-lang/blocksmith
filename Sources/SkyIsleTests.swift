import Foundation
import Metal
import simd

// Sky isle and Grapple Line checks (backlog C7; `questcheck --skyisle-only`, and part of every questcheck run):
//   placement  over seven regions square on six seeds: a share of regions holds an isle, none within 800 blocks of
//              spawn, every turf top in its band (displayed 236-262), and the ground under each far below its keel
//   build      a real isle's chunk, generated through the world's own path: turf on top, rock under it, a shrine chest,
//              open air under the keel; the shrine's loot fills
//   grapple    crafted from iron and string; cast at a block 15 ahead it reels the player there through Game.tick
//              (no fall damage); cast at a skiff it hooks the deck; cast at the empty sky it says so
enum SkyIsleTests {
    static func run(device: MTLDevice, game g: Game, check: (Bool, String) -> Void) {
        placement(device, check)
        grapple(g, check)
    }

    static func placement(_ device: MTLDevice, _ check: (Bool, String) -> Void) {
        let seeds: [UInt64] = [12345, 777, 424242, 1, 98765, 31337]
        var regions = 0, isles = 0, near = 0, offBand = 0, grounded = 0
        var first: (World, StructureStart, SkyIsle.Shape, Int, Int)?
        let R = 3
        for seed in seeds {
            let world = World(seed: seed, device: device, save: nil)
            guard let wg = world.gen as? WorldGen, let sc = wg.structures, let type = sc.types.first(where: { $0.name == SkyIsle.kind }) else {
                check(false, "skyisle \(seed): no structure type"); continue
            }
            let o = Game.spawnOrigin(seed: seed)
            let orx = floorDiv(floorDiv(o.0, CS), SkyIsle.spacing), orz = floorDiv(floorDiv(o.1, CS), SkyIsle.spacing)
            for rz in (orz - R)...(orz + R) { for rx in (orx - R)...(orx + R) {
                regions += 1
                guard let s = sc.start(type, regionX: rx, regionZ: rz) else { continue }
                isles += 1
                let cx = floorDiv(s.anchor.x, CS), cz = floorDiv(s.anchor.z, CS)
                let seedFor = regionSeed(sc, type, cx, cz)
                let sh = SkyIsle.shape(seedFor, cx, cz)
                if simd_length(V2(Float(sh.x - o.0), Float(sh.z - o.1))) < SkyIsle.minSpawn { near += 1 }
                if sh.top < SkyIsle.lowTop || sh.top > SkyIsle.highTop { offBand += 1 }
                if wg.column(sh.x, sh.z).height > sh.top - sh.depth - 20 { grounded += 1 }
                if first == nil { first = (world, s, sh, cx, cz) }
            } }
        }
        let share = Float(isles) / Float(max(1, regions))
        check(share > 0.15 && share < 0.5 && near == 0 && offBand == 0 && grounded == 0,
              String(format: "skyisle placement: %d isles in %d regions (%.0f%%), %d within 800 of spawn, %d off the height band, %d near the ground",
                     isles, regions, share * 100, near, offBand, grounded))

        // A real isle's chunk: the one holding its shrine chest (one up from the floor, 3 behind the anchor), generated
        // through the world's own path.
        guard let (world, s, _, _, _) = first, let wg = world.gen as? WorldGen else { check(false, "skyisle build: no isle to build"); return }
        // T11: a frigate based 300 blocks off finds the isle for its patrol circle, its turf top as cruise ground.
        let found = SkyIsle.near(wg, x: Float(s.anchor.x + 300), z: Float(s.anchor.z), range: 700)
        let mine = found.first { simd_length($0.c - V2(Float(s.anchor.x) + 0.5, Float(s.anchor.z - 3) + 0.5)) < 1 }
        check(mine.map { abs($0.top - Float(s.anchor.y + 1)) < 0.5 && $0.r > 10 } ?? false,
              "skyisle patrol: a frigate based 300 blocks off finds the isle to circle (\(found.count) found, top \(mine.map { Int($0.top) } ?? -1), radius \(mine.map { Int($0.r) } ?? -1))")
        let ch = IVec3(s.anchor.x, s.anchor.y + 1, s.anchor.z - 3)
        let cx = floorDiv(ch.x, CS), cz = floorDiv(ch.z, CS)
        var blocks = wg.generate(cx: cx, cz: cz)
        _ = wg.structures?.place(into: &blocks, cx: cx, cz: cz)       // structures go on after the terrain, as World does
        func at(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
            let lx = x - cx * CS, lz = z - cz * CS
            guard lx >= 0, lx < CS, lz >= 0, lz < CS, y >= 0, y < CH else { return AIR }
            return blocks[Chunk.index(lx, y, lz)]
        }
        let chest = Blocks.groupBase[Int(Blocks.id("chest"))]
        let hasChest = Blocks.groupBase[Int(at(ch.x, ch.y, ch.z))] == chest
        // Every column of the chunk: the isle's blocks (40 down from the floor and up) are turf over rock with open
        // air under the keel, far above the ground.
        var turf = 0, rock = 0, openBelow = true
        let lowY = s.anchor.y - 40
        for lz in 0..<CS { for lx in 0..<CS {
            let x = cx * CS + lx, z = cz * CS + lz
            var top = -1, bottom = -1
            for y in lowY..<min(CH, s.anchor.y + 12) where at(x, y, z) != AIR { if bottom < 0 { bottom = y }; top = y }
            guard top >= 0 else { continue }
            let k = Blocks.key(at(x, top, z))
            if k == "grass_block" || k.hasSuffix("stone_bricks") || k.contains("oak") || k == "lantern" || k.contains("chest") { turf += 1 }
            let r = Blocks.key(at(x, bottom, z))
            if r.contains("stone") || r == "andesite" || r == "cobblestone" || r == "dirt" { rock += 1 }
            for y in max(0, bottom - 8)..<bottom where at(x, y, z) != AIR { openBelow = false }
        } }
        check(hasChest && turf > 20 && rock > 20 && openBelow,
              "skyisle build: the isle at \(s.anchor.x),\(s.anchor.y - YOFF),\(s.anchor.z) has its shrine chest (\(hasChest)), turf on \(turf) columns of its chunk, rock under \(rock), open air under its keel (\(openBelow))")
        let box = ItemContainer(27)
        var rng = SRng(7)
        Loot.fill(box, table: SkyIsle.kind, rng: &rng)
        let n = box.slots.filter { !$0.isEmpty }.count
        check(n >= 3, "skyisle build: the shrine chest fills with sky loot (\(box.slots.filter { !$0.isEmpty }.map { Items.key($0.item) }.joined(separator: ", ")))")
    }

    // The seed a structure start of `type` at chunk (cx, cz) was made with (as StructureCache.start makes it).
    static func regionSeed(_ sc: StructureCache, _ t: StructureType, _ cx: Int, _ cz: Int) -> UInt64 {
        sc.seed &+ t.salt &+ UInt64(bitPattern: Int64(cx &* 31 &+ cz))
    }

    static func grapple(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let craft = Recipes.match([0, 0, Items.id("iron_ingot"), 0, Items.id("string"), 0, Items.id("string"), 0, 0], 3, 3)?.result
        check(craft.map { Items.key($0.item) } == GrappleLine.key, "grapple: iron and two string make a Grapple Line")

        let pos0 = g.player.pos, yaw0 = g.player.yaw, pitch0 = g.player.pitch, held0 = g.inventory.main[g.inventory.selected]
        let toast0 = g.onToast, surv0 = g.survival, menu0 = g.menu, health0 = g.health, fly0 = g.player.flying
        var said = ""
        g.onToast = { said = $0 }
        var placed: [IVec3] = []
        defer {
            for q in placed { w.setBlock(q.x, q.y, q.z, AIR) }
            g.player.pos = pos0; g.player.yaw = yaw0; g.player.pitch = pitch0; g.inventory.main[g.inventory.selected] = held0
            g.onToast = toast0; g.survival = surv0; g.menu = menu0; g.grapple = nil; g.health = health0
            g.player.flying = fly0; g.player.vel = .zero
        }
        g.survival = true; g.menu = nil
        g.inventory.main[g.inventory.selected] = ItemStack(Items.id(GrappleLine.key), 1)

        // A block 15 ahead and 10 up, on a platform high over the ground: reel there.
        let fx = Int(floor(pos0.x)), fz = Int(floor(pos0.z))
        let py = min(CH - 40, w.topY(fx, fz) + 30)
        for z in (fz - 1)...(fz + 1) { for x in (fx - 1)...(fx + 1) { w.setBlock(x, py - 1, z, STONE); placed.append(IVec3(x, py - 1, z)) } }
        let target = IVec3(fx, py + 10, fz - 15)
        w.setBlock(target.x, target.y, target.z, STONE); placed.append(target)
        g.player.pos = V3(Float(fx) + 0.5, Float(py), Float(fz) + 0.5); g.player.vel = .zero; g.player.flying = false
        let eye = g.player.eye, aim = V3(Float(target.x) + 0.5, Float(target.y) + 0.5, Float(target.z) + 1.0) - eye
        g.player.yaw = atan2f(-aim.x, -aim.z); g.player.pitch = atan2f(aim.y, simd_length(V2(aim.x, aim.z)))
        let cast = g.grappleUse() && g.grapple != nil
        var t: Float = 0
        while t < 3 && g.grapple != nil { g.health = 20; g.tick(0.05); t += 0.05 }
        let d = simd_length(g.player.pos - (V3(Float(target.x) + 0.5, Float(target.y) + 0.5, Float(target.z) + 1.5)))
        check(cast && g.grapple == nil && d < 2.5 && g.health >= 20,
              String(format: "grapple: cast at a block 15 ahead and 10 up (%@), it reels the player there in %.1f s (%.1f off), no fall damage", cast ? "hooked" : "missed", t, d))

        // The empty sky: nothing to hook.
        g.player.pitch = .pi / 2 - 0.01
        said = ""
        let none = g.grappleUse() && g.grapple == nil && said.contains("Nothing")

        // A skiff: the hook takes its deck.
        g.player.pos = V3(Float(fx) + 0.5, Float(py), Float(fz) + 0.5); g.player.vel = .zero
        let s = w.ships.spawn(SkySkiff.blueprint(), at: V3(Float(fx) + 0.5, Float(py) + 4, Float(fz) - 12.5), yaw: 0, name: SkySkiff.name, role: "")
        defer { w.ships.remove(s) }
        var onShip = false
        do {
            let c = s.pos - g.player.eye
            g.player.yaw = atan2f(-c.x, -c.z); g.player.pitch = atan2f(c.y, simd_length(V2(c.x, c.z)))
            onShip = g.grappleUse() && g.grapple?.ship === s
            g.grapple = nil
        }
        check(none && onShip, "grapple: at the empty sky it says so (\(none), '\(said)'); cast at a skiff it hooks the deck (\(onShip))")
    }
}
