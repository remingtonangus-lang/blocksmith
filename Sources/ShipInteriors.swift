import Foundation
import simd

// Ship interiors (Remington, 2026-10-05: frigates are far-future warships with hallways and rooms, like the citadel,
// not hollow shells). HullBuilder.interiorDeck lays out one deck inside a hull: a corridor down the centreline, rooms
// on both sides behind partition walls, a doorway into each from the corridor, ceiling lights, and furniture and loot
// by room kind. HullBuilder.ladderWell joins one deck to the next. Only empty cells inside the hull are built, so
// the skin, guns, tubes and whatever the caller placed first stay as they are.

enum ShipRoom: CaseIterable {
    case quarters, mess, armory, medbay, brig, storage, briefing, engineering
}

struct InteriorStyle {
    var floor: BlockID
    var wall: BlockID
    var trim: BlockID          // door frames, the corridor's floor stripe
    var light: BlockID
    var bed: String            // bed colour ("white", "gray"...)
    var armoryLoot: String
    var supplyLoot: String

    static func pick(_ n: String, _ fallback: BlockID) -> BlockID { Blocks.has(n) ? Blocks.id(n) : fallback }
}

extension HullBuilder {
    // One deck: floor at y, rooms `h` high above it (walls y+1 ... y+h), over x -hw...hw and z0...z1 where `inside`
    // says the hull is. The corridor is x -c...c; rooms are `roomLen` long along z, kinds taken from `rooms` in turn.
    func interiorDeck(y: Int, h: Int, hw: Int, z0: Int, z1: Int, c: Int = 1, roomLen: Int = 9, rooms: [ShipRoom],
                      style st: InteriorStyle, seed: UInt64, inside: (Int, Int, Int) -> Bool) {
        guard hw >= c + 4, z1 > z0 + 4, h >= 3 else { return }
        func free(_ x: Int, _ yy: Int, _ z: Int) -> Bool { inside(x, yy, z) && get(x, yy, z) == AIR }
        // Floor wherever there is headroom above it in the hull.
        for z in z0...z1 { for x in -hw...hw where free(x, y, z) && inside(x, y + 2, z) { set(x, y, z, st.floor) } }
        // A trim stripe down the corridor floor.
        for z in z0...z1 where get(0, y, z) == st.floor { set(0, y, z, st.trim) }
        // Corridor walls.
        for z in z0...z1 { for sx in [-1, 1] { for yy in (y + 1)...(y + h) where free(sx * (c + 1), yy, z) { set(sx * (c + 1), yy, z, st.wall) } } }
        var rng = SRng(seed | 1)
        var k = 0
        for sx in [-1, 1] {
            var za = z0
            while za + 4 <= z1 {
                let zb = min(z1, za + roomLen)
                // Partition walls at both ends of the room (shared with the next).
                for zz in [za, zb] { for x in (c + 2)...hw { for yy in (y + 1)...(y + h) where free(sx * x, yy, zz) { set(sx * x, yy, zz, st.wall) } } }
                // The room's outer reach at its middle (the hull narrows toward the ends of a deck).
                let zm = (za + zb) / 2
                var xo = c + 2
                while xo < hw && inside(sx * (xo + 1), y + 1, zm) { xo += 1 }
                if xo - (c + 2) >= 2 && zb - za >= 4 {
                    let kind = rooms[k % rooms.count]
                    k += 1
                    // Doorway from the corridor, framed in trim.
                    let dz = zm
                    for yy in (y + 1)...(y + 2) { set(sx * (c + 1), yy, dz, AIR) }
                    if get(sx * (c + 1), y + 3, dz) == st.wall { set(sx * (c + 1), y + 3, dz, st.trim) }
                    roomCells.append((grid(sx * (c + 2), y + 1, dz), kind))
                    furnish(kind, sx: sx, xi: c + 2, xo: xo, y: y, h: h, za: za + 1, zb: zb - 1, door: dz, style: st, rng: &rng, inside: inside)
                }
                za = zb
            }
        }
        // Corridor lights in the ceiling row.
        for z in stride(from: z0 + 2, through: z1, by: 5) where free(0, y + h, z) { set(0, y + h, z, st.light) }
    }

    // Furniture for one room: x from sx*xi (by the corridor wall) to sx*xo (the hull), z za...zb, floor at y.
    private func furnish(_ kind: ShipRoom, sx: Int, xi: Int, xo: Int, y: Int, h: Int, za: Int, zb: Int, door: Int,
                         style st: InteriorStyle, rng: inout SRng, inside: (Int, Int, Int) -> Bool) {
        func free(_ x: Int, _ z: Int, _ dy: Int = 1) -> Bool { inside(sx * x, y + dy, z) && get(sx * x, y + dy, z) == AIR && get(sx * x, y, z) != AIR }
        func put(_ x: Int, _ z: Int, _ b: BlockID, _ dy: Int = 1) { if free(x, z, dy) { set(sx * x, y + dy, z, b) } }
        // Keep the way in clear: nothing on the cell inside the doorway or the one beyond it.
        func clearOfDoor(_ x: Int, _ z: Int) -> Bool { !(abs(z - door) <= 1 && x <= xi + 1) }
        let chest = Blocks.id("chest")
        func locker(_ x: Int, _ z: Int, _ loot: String) {
            guard clearOfDoor(x, z), free(x, z) else { return }
            set(sx * x, y + 1, z, chest)
            chests.append((grid(sx * x, y + 1, z), loot))
        }
        // A light in the middle of the ceiling.
        let lx = (xi + xo) / 2, lz = (za + zb) / 2
        if inside(sx * lx, y + h, lz) && get(sx * lx, y + h, lz) == AIR { set(sx * lx, y + h, lz, st.light) }
        switch kind {
        case .quarters, .medbay:
            // Bunks along the hull side, heads toward +z; a locker at the end.
            let foot = Blocks.has("\(st.bed)_bed") ? Blocks.id("\(st.bed)_bed") : AIR
            let head = Blocks.has("\(st.bed)_bed_head") ? Blocks.id("\(st.bed)_bed_head") : AIR
            var z = za
            while z + 1 <= zb && foot != AIR {
                if clearOfDoor(xo, z) && free(xo, z) && free(xo, z + 1) {
                    set(sx * xo, y + 1, z, foot)
                    set(sx * xo, y + 1, z + 1, head)
                }
                z += 3
            }
            if kind == .medbay {
                put(xo, zb, StyleBlocks.cauldron)
                put(xi, zb, StyleBlocks.brewing)
            } else {
                locker(xi, zb, st.supplyLoot)
            }
        case .mess:
            // A long table down the middle with seats either side.
            let tx = (xi + xo) / 2
            for z in (za + 1)...max(za + 1, zb - 1) where clearOfDoor(tx, z) {
                put(tx, z, StyleBlocks.table)
            }
            put(xo, za, StyleBlocks.furnace)
            put(xo, zb, StyleBlocks.barrel)
        case .armory:
            // Weapon racks (bars) along the hull side, ammunition chests at the ends.
            for z in za...zb where clearOfDoor(xo, z) { put(xo, z, StyleBlocks.bars) }
            locker(xi, za, st.armoryLoot)
            locker(xi, zb, st.armoryLoot)
        case .brig:
            // A cell behind bars at the hull side.
            let cx = max(xi + 1, xo - 1)
            for z in za...zb where clearOfDoor(cx, z) { put(cx, z, StyleBlocks.bars); put(cx, z, StyleBlocks.bars, 2) }
            put(xo, (za + zb) / 2, StyleBlocks.barrel)
        case .storage:
            for z in za...zb where clearOfDoor(xo, z) {
                put(xo, z, rng.range(0, 2) == 0 ? StyleBlocks.barrel : StyleBlocks.crate)
            }
            locker(xi, zb, st.supplyLoot)
        case .briefing:
            // A map table with consoles round it.
            let tx = (xi + xo) / 2, tz = (za + zb) / 2
            put(tx, tz, StyleBlocks.table)
            put(tx, tz - 1, StyleBlocks.table)
            put(xo, tz, StyleBlocks.console)
        case .engineering:
            for z in stride(from: za, through: zb, by: 2) where clearOfDoor(xo, z) { put(xo, z, StyleBlocks.console) }
            put(xi, zb, StyleBlocks.crate)
        }
    }

    // A ladder from the floor at y0 up through the floor at y1 at (x, z), against a wall at x + back (back = -1 or 1):
    // the upper floor is opened over it and the backing wall is built where the hull is empty.
    func ladderWell(x: Int, z: Int, y0: Int, y1: Int, back: Int) {
        let ladder = Blocks.id("ladder")
        let face: BlockID = back < 0 ? 3 : 2
        for y in (y0 + 1)...y1 {
            if get(x + back, y, z) == AIR { set(x + back, y, z, StyleBlocks.ladderBack) }
            set(x, y, z, ladder + face)
        }
    }
}

// Blocks the interiors use, with fallbacks (resolved once).
enum StyleBlocks {
    static func pick(_ n: String, _ fallback: BlockID) -> BlockID { Blocks.has(n) ? Blocks.id(n) : fallback }
    static let table = pick("smooth_stone_slab", pick("stone_slab", STONE))
    static let furnace = pick("furnace", STONE)
    static let barrel = pick("barrel", PLANKS)
    static let crate = pick("ammo_crate", pick("barrel", PLANKS))
    static let bars = pick("iron_bars", STONE)
    static let console = pick("command_console", STONE)
    static let cauldron = pick("cauldron", STONE)
    static let brewing = pick("brewing_stand", STONE)
    static let ladderBack = pick("warship_panel", STONE)
}

// `Blocksmith --interiorcheck`: every room of the capital ships' interiors can be walked to from where you board
// (the hangar floor) with the player's moves: walking, a one-block jump, drops of up to three, ladders. Also the helm
// and every chest. Reads the hull builders' grids directly (no world, no Metal).
enum InteriorCheck {
    struct Walk {
        let sx: Int, sy: Int, sz: Int
        let blocks: [BlockID]
        func at(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
            guard x >= 0 && x < sx && y >= 0 && y < sy && z >= 0 && z < sz else { return AIR }
            return blocks[x + z * sx + y * sx * sz]
        }
        func passable(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            let b = at(x, y, z)
            return !Blocks.collide[Int(b)] || Player.climbable(b)
        }
        func climb(_ x: Int, _ y: Int, _ z: Int) -> Bool { Player.climbable(at(x, y, z)) }
        // Feet at (x, y, z): two cells to stand in, and something to stand on (or a ladder to hold).
        func standable(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            guard passable(x, y, z) && passable(x, y + 1, z) else { return false }
            let below = at(x, y - 1, z)
            return (Blocks.collide[Int(below)] && !Player.climbable(below)) || climb(x, y, z) || climb(x, y - 1, z)
        }
        func reach(from s: IVec3) -> Set<IVec3> {
            var seen = Set<IVec3>([s])
            var q = [s]
            var i = 0
            let dirs = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)]
            func visit(_ c: IVec3) { if !seen.contains(c) { seen.insert(c); q.append(c) } }
            while i < q.count {
                let c = q[i]; i += 1
                for d in dirs {
                    let n = c + d
                    if standable(n.x, n.y, n.z) { visit(n); continue }
                    // A one-block step or jump (headroom over the start).
                    if passable(c.x, c.y + 2, c.z) && standable(n.x, n.y + 1, n.z) { visit(IVec3(n.x, n.y + 1, n.z)); continue }
                    // Drops of up to three.
                    var dy = 1
                    while dy <= 3 && passable(n.x, n.y - dy + 1, n.z) && passable(n.x, n.y - dy + 2, n.z) {
                        if standable(n.x, n.y - dy, n.z) { visit(IVec3(n.x, n.y - dy, n.z)); break }
                        dy += 1
                    }
                }
                // Ladders: up while holding one, down onto anything standable.
                if climb(c.x, c.y, c.z) || climb(c.x, c.y + 1, c.z) {
                    if standable(c.x, c.y + 1, c.z) { visit(IVec3(c.x, c.y + 1, c.z)) }
                }
                if standable(c.x, c.y - 1, c.z) && (climb(c.x, c.y - 1, c.z) || climb(c.x, c.y, c.z)) { visit(IVec3(c.x, c.y - 1, c.z)) }
            }
            return seen
        }
    }

    static func run() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        var fails = 0
        func check(_ ok: Bool, _ what: String) {
            print((ok ? "PASS " : "FAIL ") + what)
            if !ok { fails += 1 }
        }
        for (name, make, from, minRooms) in [("warfrigate", { Capital.frigate() }, (0, 27, 250), 60),
                                             ("capfrigate", { Capital.capitalFrigate() }, (0, 5, 85), 16)] as [(String, () -> HullBuilder, (Int, Int, Int), Int)] {
            let t0 = CFAbsoluteTimeGetCurrent()
            let hb = make()
            let w = Walk(sx: hb.sx, sy: hb.sy, sz: hb.sz, blocks: hb.blocks)
            let start = hb.grid(from.0, from.1, from.2)
            let seen = w.reach(from: start)
            let blocks = hb.blocks.reduce(0) { $0 + ($1 == AIR ? 0 : 1) }
            print(String(format: "interior %@: %ld blocks built in %.0f ms, %ld rooms, %ld chests, %ld walkable cells from the hangar", name, blocks,
                         (CFAbsoluteTimeGetCurrent() - t0) * 1000, hb.roomCells.count, hb.chests.count, seen.count))
            check(w.standable(start.x, start.y, start.z), "\(name): the hangar floor is standable at the boarding point")
            var missed: [String] = []
            for (c, kind) in hb.roomCells where !seen.contains(c) { missed.append("\(kind) at \(c.x - hb.ox),\(c.y),\(c.z)") }
            check(hb.roomCells.count >= minRooms, "\(name): decks of rooms (\(hb.roomCells.count))")
            check(missed.isEmpty, "\(name): every room reachable from the hangar (\(hb.roomCells.count - missed.count) of \(hb.roomCells.count))\(missed.isEmpty ? "" : "; first missed: " + missed.prefix(4).joined(separator: "; "))")
            // A chest is reachable when a walkable cell is beside it (at its level or the one below).
            var lost: [String] = []
            for (c, _) in hb.chests {
                let near = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)].contains { d in
                    seen.contains(c + d) || seen.contains(c + d + IVec3(0, -1, 0))
                }
                if !near { lost.append("\(c.x - hb.ox),\(c.y),\(c.z)") }
            }
            check(lost.isEmpty, "\(name): every chest reachable (\(hb.chests.count - lost.count) of \(hb.chests.count))\(lost.isEmpty ? "" : "; first: " + lost.prefix(4).joined(separator: "; "))")
            // The helm: standing beside it on the bridge.
            if let h = (0..<hb.blocks.count).first(where: { Blocks.key(Blocks.groupBase[Int(hb.blocks[$0])]) == "ship_helm" }) {
                let y = h / (hb.sx * hb.sz), rem = h - y * hb.sx * hb.sz, z = rem / hb.sx, x = rem - z * hb.sx
                let ok = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)].contains { seen.contains(IVec3(x, y, z) + $0) }
                check(ok, "\(name): the bridge helm reachable (\(x - hb.ox),\(y),\(z))")
            } else { check(false, "\(name): has a helm") }
            // Crew posts stand in the open.
            var buried: [String] = []
            for p in hb.crew {
                let c = IVec3(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)))
                if !w.passable(c.x, c.y, c.z) || !w.passable(c.x, c.y + 1, c.z) { buried.append("\(c.x - hb.ox),\(c.y),\(c.z)") }
            }
            check(buried.isEmpty, "\(name): no crew post inside a block (\(buried.count))\(buried.isEmpty ? "" : ": " + buried.prefix(4).joined(separator: "; "))")
        }
        print("interiorcheck: \(fails == 0 ? "PASS" : "\(fails) FAILED")")
        return fails == 0 ? 0 : 3
    }
}
