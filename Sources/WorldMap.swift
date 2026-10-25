import Foundation
import simd

// World map (M / hold View) and minimap (Options > Interface > Minimap): biome colours with height shading,
// sampled from the terrain generator on a background thread and cached at 4-block resolution, plus markers for
// the player, spawn, and the Steelhold military bases and villages you have discovered (been within 96 blocks
// of). Discoveries are saved per world in mapmarks.json.
final class MapCache {
    static let shared = MapCache()
    static let cellBlocks = 4
    private var cells: [Int64: UInt32] = [:]
    private var queue: [Int64] = []
    private var pending = Set<Int64>()
    private let lock = NSLock()
    private let worker = DispatchQueue(label: "blocksmith.worldmap", qos: .utility)
    private var working = false
    private weak var gen: TerrainGenerator?
    private var genID: ObjectIdentifier?
    private var epoch = 0                     // bumped by use(): a batch sampled with the old generator is dropped
    private(set) var version = 0              // bumped whenever sampled cells arrive or the cache restarts (minimap redraw)

    struct Mark: Codable, Hashable { var kind: String; var x: Int; var z: Int; var name: String? = nil }   // name: a town's
    private(set) var marks: [Mark] = []
    private var marksWorld = ""
    func replaceMarks(_ m: [Mark]) { marks = m }       // (checks set marks aside and put them back)
    private var scanTimer: Double = 0

    var cellCount: Int { lock.lock(); defer { lock.unlock() }; return cells.count }     // smoke memory line

    static func key(_ cx: Int, _ cz: Int) -> Int64 { (Int64(cx) << 32) | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: cz))) }

    // Switches to a generator (new world or dimension): the cache restarts.
    func use(_ g: TerrainGenerator) {
        let id = ObjectIdentifier(g)
        guard id != genID else { return }
        lock.lock()
        cells.removeAll(); queue.removeAll(); pending.removeAll()
        version &+= 1
        epoch &+= 1
        gen = g                               // under the lock: drain() reads it on the worker
        genID = id
        lock.unlock()
    }

    // Colour of the 4-block cell containing (x, z), or nil while it is being sampled (it is queued).
    func color(_ x: Int, _ z: Int) -> UInt32? {
        let cx = floorDiv(x, MapCache.cellBlocks), cz = floorDiv(z, MapCache.cellBlocks)
        let k = MapCache.key(cx, cz)
        lock.lock()
        if let c = cells[k] { lock.unlock(); return c }
        if !pending.contains(k) {
            pending.insert(k)
            queue.append(k)
            if queue.count > 40000 { let drop = queue.prefix(queue.count - 40000); for d in drop { pending.remove(d) }; queue.removeFirst(queue.count - 40000) }
        }
        let start = !working
        if start { working = true }
        lock.unlock()
        if start { worker.async { [weak self] in self?.drain() } }
        return nil
    }

    // Many lookups under one lock (the minimap asked per cell: a lock, a hash and an unlock each, a few thousand a
    // frame: flight profile). Misses are queued as in color(_:_:).
    func batch(_ body: ((Int, Int) -> UInt32?) -> Void) {
        var missing = false
        lock.lock()
        body { x, z in
            let k = MapCache.key(floorDiv(x, MapCache.cellBlocks), floorDiv(z, MapCache.cellBlocks))
            if let c = self.cells[k] { return c }
            if !self.pending.contains(k) { self.pending.insert(k); self.queue.append(k) }
            missing = true
            return nil
        }
        if queue.count > 40000 { let drop = queue.prefix(queue.count - 40000); for d in drop { pending.remove(d) }; queue.removeFirst(queue.count - 40000) }
        let start = missing && !working
        if start { working = true }
        lock.unlock()
        if start { worker.async { [weak self] in self?.drain() } }
    }

    // Samples queued cells, newest requests first (what is on screen now).
    private func drain() {
        while true {
            lock.lock()
            guard let g = gen, !queue.isEmpty else { working = false; lock.unlock(); return }
            let e = epoch
            let batch = Array(queue.suffix(256))
            queue.removeLast(batch.count)
            lock.unlock()
            var out: [(Int64, UInt32)] = []
            out.reserveCapacity(batch.count)
            for k in batch {
                let cx = Int(Int32(truncatingIfNeeded: k >> 32)), cz = Int(Int32(truncatingIfNeeded: k & 0xFFFF_FFFF))
                let c = g.column(cx * MapCache.cellBlocks + 2, cz * MapCache.cellBlocks + 2)
                // P337 step 5: railway lines show on the map as a dark track line.
                if let wg = g as? WorldGen, MapCache.onRail(wg, k, cx * MapCache.cellBlocks, cz * MapCache.cellBlocks) { out.append((k, 0x4A3B2E)); continue }
                out.append((k, MapCache.shade(c.biome, height: c.height)))
            }
            lock.lock()
            // A portal or world switch while this batch was sampled: its colours belong to the old world.
            if e != epoch { lock.unlock(); continue }
            for (k, c) in out { cells[k] = c; pending.remove(k) }
            if cells.count > 400_000 { cells.removeAll() }
            version &+= 1
            lock.unlock()
        }
    }

    // P337 step 5: the map cells each railway line crosses (by line id), built once per line.
    private static var railCells: [Int64: Set<Int64>] = [:]
    private static let railLock = NSLock()
    private static var railGen: ObjectIdentifier?
    static func onRail(_ gen: WorldGen, _ k: Int64, _ x: Int, _ z: Int) -> Bool {
        let n = cellBlocks
        for l in Railways.near(gen, x0: x, z0: z, x1: x + n - 1, z1: z + n - 1, pad: 0) {
            railLock.lock()
            if railCells.count > 512 || railGen != ObjectIdentifier(gen) { railCells.removeAll(); railGen = ObjectIdentifier(gen) }
            var set = railCells[l.id]
            if set == nil {
                var s = Set<Int64>()
                for c in l.cells { s.insert(key(floorDiv(c.x, n), floorDiv(c.z, n))) }
                railCells[l.id] = s; set = s
            }
            railLock.unlock()
            if set!.contains(k) { return true }
        }
        return false
    }

    // Biome base colour, lighter on high ground and darker in deep water.
    static func shade(_ b: Biome, height h: Int) -> UInt32 {
        var base: UInt32
        if b.isOcean { base = b.isDeepOcean ? 0x2A4E9A : 0x3A66C0 }
        else if b.isRiver { base = 0x4479D0 }
        else if b.isBeach { base = b == .stonyShore ? 0x8C8C88 : 0xDCCB8E }
        else if b == .desert { base = 0xE0D29A }
        else if b.isBadlands { base = 0xC0673A }
        else if b == .mushroomFields { base = 0x45C873 }        // P280: Saltpalm Isles
        else if b == .cherryGrove { base = 0xE4B2CF }
        else if b == .stonyPeaks || b == .windsweptGravellyHills { base = 0x9A9A96 }
        else if b.isPeak || b.info.temp < 0.15 || b == .iceSpikes { base = 0xEEF2F6 }
        else { base = b.info.grass }
        if b.isOcean || b.isRiver { return base }
        let k = max(0.7, min(1.25, 0.9 + Float(h - SEA) / 160))
        let r = min(255, Float((base >> 16) & 255) * k), gg = min(255, Float((base >> 8) & 255) * k), bb = min(255, Float(base & 255) * k)
        return (UInt32(r) << 16) | (UInt32(gg) << 8) | UInt32(bb)
    }

    // MARK: Discoveries

    private func marksURL(_ g: Game) -> URL? { g.save?.dir.appendingPathComponent("mapmarks.json") }

    private func loadMarks(_ g: Game) {
        let w = g.save?.dir.lastPathComponent ?? ""
        guard w != marksWorld else { return }
        marksWorld = w
        marks = []
        if let u = marksURL(g), let d = try? Data(contentsOf: u), let m = try? JSONDecoder().decode([Mark].self, from: d) { marks = m }
    }

    func marked(kind: String, x: Int, z: Int) -> Bool { marks.contains { $0.kind == kind && abs($0.x - x) < 24 && abs($0.z - z) < 24 } }

    // `silent`: the mark goes on the map without the toast (P328: the Wardstone's pointer, a mark that is not news).
    func discover(_ g: Game, kind: String, x: Int, z: Int, name given: String? = nil, silent: Bool = false) {
        guard !marks.contains(where: { $0.kind == kind && abs($0.x - x) < 24 && abs($0.z - z) < 24 }) else { return }
        // A town goes on the map under its name (the gap pass: "a name on a sign and the map").
        let name = kind == "village" ? Townsfolk.town(g, at: V3(Float(x), 64, Float(z))) : given
        marks.append(Mark(kind: kind, x: x, z: z, name: name))
        saveMarks(g)
        if !silent { g.onToast?("\(name ?? MapCache.style(kind).name) marked on the map") }
    }

    private func saveMarks(_ g: Game) {
        if let u = marksURL(g), let d = try? JSONEncoder().encode(marks) { try? d.write(to: u, options: .atomic) }
    }

    // Your own waypoints (up to 32): placing one within `near` blocks of another removes that one instead.
    // Returns true when a pin was added.
    @discardableResult
    func togglePin(_ g: Game, x: Int, z: Int, near: Int) -> Bool {
        loadMarks(g)
        if let i = marks.firstIndex(where: { $0.kind == "pin" && abs($0.x - x) <= near && abs($0.z - z) <= near }) {
            marks.remove(at: i)
            saveMarks(g)
            return false
        }
        if marks.filter({ $0.kind == "pin" }).count >= 32, let i = marks.firstIndex(where: { $0.kind == "pin" }) { marks.remove(at: i) }
        marks.append(Mark(kind: "pin", x: x, z: z))
        saveMarks(g)
        return true
    }

    // Q2c-console-20: a waypoint named after a place's marker, on the marker (no second one there).
    func pinPlace(_ g: Game, x: Int, z: Int, name: String) {
        loadMarks(g)
        guard !marks.contains(where: { $0.kind == "pin" && $0.x == x && $0.z == z }) else { return }
        if marks.filter({ $0.kind == "pin" }).count >= 32, let i = marks.firstIndex(where: { $0.kind == "pin" }) { marks.remove(at: i) }
        marks.append(Mark(kind: "pin", x: x, z: z, name: name))
        saveMarks(g)
    }

    // P242: a named pin (a base the radar station found); one already within 16 blocks is kept as it is.
    func pinNamed(_ g: Game, x: Int, z: Int, name: String) {
        loadMarks(g)
        guard !marks.contains(where: { abs($0.x - x) <= 16 && abs($0.z - z) <= 16 }) else { return }
        marks.append(Mark(kind: "pin", x: x, z: z, name: name))
        saveMarks(g)
    }

    // P205: the last death's chests as a named pin (the one before it is replaced).
    // Q2c-console-4: his things are back: the pin goes.
    func unpinDeath(_ g: Game) {
        loadMarks(g)
        marks.removeAll { $0.kind == "pin" && $0.name == "Your things" }
        saveMarks(g)
    }

    func pinDeath(_ g: Game, x: Int, z: Int) {
        loadMarks(g)
        marks.removeAll { $0.kind == "pin" && $0.name == "Your things" }
        marks.append(Mark(kind: "pin", x: x, z: z, name: "Your things"))
        saveMarks(g)
    }

    // D51 (Waymarks.swift): marks the game keeps current (contracts, bounties, your horse, ships, vehicles), one kind at a
    // time; written out only when they change.
    func setMarks(_ g: Game, kind: String, _ list: [Mark]) {
        loadMarks(g)
        guard marks.filter({ $0.kind == kind }) != list else { return }
        marks.removeAll { $0.kind == kind }
        marks += list
        saveMarks(g)
    }
    // D51: a note stamped on the map (up to 48), and the notes within `near` blocks taken off again.
    func addNote(_ g: Game, x: Int, z: Int, name: String) {
        loadMarks(g)
        marks.removeAll { $0.kind == "note" && abs($0.x - x) <= 4 && abs($0.z - z) <= 4 }
        if marks.filter({ $0.kind == "note" }).count >= 48, let i = marks.firstIndex(where: { $0.kind == "note" }) { marks.remove(at: i) }
        marks.append(Mark(kind: "note", x: x, z: z, name: name))
        saveMarks(g)
    }
    @discardableResult
    func removeNotes(_ g: Game, x: Int, z: Int, near: Int) -> Int {
        loadMarks(g)
        let n = marks.count
        marks.removeAll { ($0.kind == "note" || $0.kind == "pin") && abs($0.x - x) <= near && abs($0.z - z) <= near }
        if marks.count != n { saveMarks(g) }
        return n - marks.count
    }

    // Y6: the spine's next objective (Spine.track / Spine.lead), one marker replaced as the goal moves on; nil clears it.
    func setObjective(_ g: Game, x: Int?, z: Int?, name: String?) {
        loadMarks(g)
        let old = marks.first { $0.kind == "objective" }
        if let x, let z {
            if let o = old, o.x == x, o.z == z, o.name == name { return }
            marks.removeAll { $0.kind == "objective" }
            marks.append(Mark(kind: "objective", x: x, z: z, name: name))
        } else {
            guard old != nil else { return }
            marks.removeAll { $0.kind == "objective" }
        }
        saveMarks(g)
    }

    // Nearest waypoint to a point (for the HUD distance line).
    func nearestPin(_ x: Float, _ z: Float) -> Mark? {
        var best: Mark?
        var bestD: Float = .greatestFiniteMagnitude
        for m in marks where m.kind == "pin" {
            let dx: Float = Float(m.x) - x, dz: Float = Float(m.z) - z
            let d: Float = dx * dx + dz * dz
            if d < bestD { bestD = d; best = m }
        }
        return best
    }

    // Marker letter, colour and name per discovery kind.
    static func style(_ kind: String) -> (letter: String, color: V4, name: String) {
        switch kind {
        case "military_base": return ("B", V4(0.85, 0.2, 0.15, 1), "Capital citadel (the enemy)")
        case "capital_city": return ("C", V4(0.92, 0.94, 0.97, 1), "Capital city")
        case "boreal_station": return ("N", V4(0.45, 0.72, 1, 1), "Boreal Station")
        case "greywall_base": return ("G", V4(0.55, 0.62, 0.72, 1), "Greywall base")
        case "great_ruin": return ("A", V4(0.8, 0.75, 0.6, 1), "Ancient Spire")                 // P456 orders
        case "pillager_outpost": return ("M", V4(0.7, 0.3, 0.25, 1), "Marauder Watchtower")
        case "objective": return ("!", V4(1, 0.85, 0.2, 1), "Next objective")           // Y6 (Spine.swift)
        case "sky_isle": return ("K", V4(0.6, 0.85, 1.0, 1), "Sky isle")
        case "village": return ("V", V4(0.95, 0.8, 0.3, 1), "Village")
        case "vessel_frigate", "vessel_capfrigate": return ("F", V4(0.55, 0.62, 0.4, 1), "Meridian frigate patrol")
        case "vessel_warfrigate", "vessel_battle": return ("S", V4(0.35, 0.5, 0.95, 1), "Stormwarden frigate patrol")
        case "vessel_crawler": return ("I", V4(0.75, 0.45, 0.25, 1), "Ironback crawler patrol")
        case "vessel_carriage": return ("C", V4(0.95, 0.5, 0.15, 1), "Siege Carriage patrol")
        case "pin": return ("+", V4(0.2, 0.8, 0.85, 1), "Waypoint")
        case "legend": return ("L", V4(0.95, 0.5, 0.2, 1), "Legendary animal's den")
        case "border_post": return ("P", V4(0.75, 0.2, 0.2, 1), "Border post")
        case "station": return ("R", V4(0.85, 0.55, 0.3, 1), "Railway station")
        case "property": return ("H", V4(0.35, 0.85, 0.95, 1), "Your property")             // D28
        case "naval_port": return ("D", V4(0.3, 0.55, 0.85, 1), "Meridian dockyard")       // D39
        case "contract": return ("$", V4(0.95, 0.75, 0.25, 1), "Contract")                 // D51 (Waymarks.swift)
        case "bounty": return ("X", V4(0.9, 0.25, 0.2, 1), "Bounty")
        case "director": return ("E", V4(0.85, 0.5, 1, 1), "Event")                         // P266 (Director.swift)
        case "my_horse": return ("Y", V4(0.85, 0.65, 0.4, 1), "Your horse")
        case "horse_grave": return ("#", V4(0.72, 0.7, 0.66, 1), "Where your horse fell")     // P259
        case "my_ship": return ("^", V4(0.4, 0.75, 1, 1), "Your ship")
        case "my_vehicle": return ("=", V4(0.7, 0.75, 0.5, 1), "Your vehicle")
        case "note": return ("*", V4(0.95, 0.95, 0.85, 1), "Note")
        case "ghost_town": return ("G", V4(0.7, 0.62, 0.5, 1), "Ghost town")                // D48 (FrontierSites.swift)
        case "homestead": return ("h", V4(0.75, 0.85, 0.4, 1), "Homestead")
        case "stilt_hamlet": return ("s", V4(0.45, 0.7, 0.55, 1), "Stilt hamlet")
        case "pueblo": return ("p", V4(0.9, 0.55, 0.35, 1), "Pueblo")
        case "camp_freed": return ("O", V4(0.4, 0.9, 0.45, 1), "Freed camp (fast travel)")
        default: return ("?", V4(0.7, 0.7, 0.7, 1), kind)
        }
    }

    // Once a second: bases and villages within 96 blocks count as discovered (overworld only).
    func tick(_ g: Game) {
        loadMarks(g)
        use(g.world.gen)
        guard g.clock - scanTimer > 1, g.dim.dim == .overworld, let sc = g.world.gen.structures else { return }
        scanTimer = g.clock
        // Towns marked before they had names on the map: one a second gets its name.
        if let i = marks.firstIndex(where: { $0.kind == "village" && $0.name == nil }) {
            marks[i].name = Townsfolk.town(g, at: V3(Float(marks[i].x), 64, Float(marks[i].z)))
            saveMarks(g)
        }
        // Round every player (split screen: player 2 passing a citadel or village alone discovered nothing).
        for i in 0..<max(1, g.coop.seatCount) { scan(g, sc, g.coop.seatPlayer(i, g).pos); SkyIsle.discover(g, sc, at: g.coop.seatPlayer(i, g).pos) }
    }

    private func scan(_ g: Game, _ sc: StructureCache, _ at: V3) {
        let px = Int(floor(at.x)), pz = Int(floor(at.z))
        for t in sc.types where t.name == "military_base" || t.name == "village" || t.name == "capital_city" || t.name == "boreal_station" || t.name == Greywall.kind {
            for s in sc.startsNear(cx: floorDiv(px, CS), cz: floorDiv(pz, CS), t) {
                let cx = (s.min.x + s.max.x) / 2, cz = (s.min.z + s.max.z) / 2
                let dx = cx - px, dz = cz - pz
                let r = t.name == "capital_city" ? 150 : 96
                if dx * dx + dz * dz < r * r {
                    discover(g, kind: t.name, x: cx, z: cz, name: t.name == Greywall.kind ? Greywall.Tier.of(s).name : nil)
                }
            }
        }
        // Vessel patrols (ShipVessels): their home point counts once you come within 200 blocks of it.
        let rx = floorDiv(px, Vessels.region), rz = floorDiv(pz, Vessels.region)
        for dz in -1...1 { for dx in -1...1 {
            guard let e = Vessels.encounter(seed: g.world.seed, rx: rx + dx, rz: rz + dz, gen: g.world.gen) else { continue }
            if !Vessels.out(e.0, fleetSails: g.fleetSails) { continue }  // the Stormwarden warships sail once a Greywall Fortress falls (Y3)
            let ex = e.1.x - px, ez = e.1.z - pz
            if ex * ex + ez * ez < 200 * 200 { discover(g, kind: "vessel_" + e.0, x: e.1.x, z: e.1.z) }
        } }
    }

    // Harness: forget discoveries (temp world tests).
    func resetMarks() { marks = []; marksWorld = "" }

    // Harness: sample a square of cells around (x, z) right now (snapshots can't wait for the worker).
    func prefill(_ g: TerrainGenerator, x: Int, z: Int, radius: Int, step: Int) {
        use(g)
        var out: [(Int64, UInt32)] = []
        var bz = z - radius
        while bz <= z + radius {
            var bx = x - radius
            while bx <= x + radius {
                let cx = floorDiv(bx, MapCache.cellBlocks), cz = floorDiv(bz, MapCache.cellBlocks)
                let c = g.column(cx * MapCache.cellBlocks + 2, cz * MapCache.cellBlocks + 2)
                out.append((MapCache.key(cx, cz), MapCache.shade(c.biome, height: c.height)))
                bx += step
            }
            bz += step
        }
        lock.lock()
        for (k, c) in out { cells[k] = c }
        lock.unlock()
    }
}

// Draws a top-down map into HudLines: `cells` x `rows` cells of `px` screen pixels each, centred on (wx, wz)
// at `bpc` blocks per cell, with markers. Rows are merged into runs of equal colour.
enum MapDraw {
    static func color(_ c: UInt32, _ a: Float = 1) -> V4 { V4(Float((c >> 16) & 255) / 255, Float((c >> 8) & 255) / 255, Float(c & 255) / 255, a) }

    static func terrain(_ out: inout [HudLine], x0: Float, y0: Float, cols: Int, rows: Int, px: Float, wx: Float, wz: Float, bpc: Int, s: Float) {
        let unknown: UInt32 = 0x1E2024
        let fog = MapFog.shared
        let halfRows: Float = Float(rows) / 2, halfCols: Float = Float(cols) / 2, step: Float = Float(bpc)
        // A named function, not a trailing closure: the release type checker timed out on the closure body.
        func draw(_ lookup: (Int, Int) -> UInt32?) {
            for r in 0..<rows {
                var runStart = 0
                var runColor: UInt32 = 0xFFFFFFFF
                let fz: Float = wz + (Float(r) - halfRows) * step
                let bz = Int(floor(fz))
                let y: Float = y0 + Float(r) * px
                for c in 0...cols {
                    var col: UInt32 = 0xFFFFFFFE
                    if c < cols {
                        let fx: Float = wx + (Float(c) - halfCols) * step
                        let bx = Int(floor(fx))
                        col = fog.fogged(bx, bz) ? MapFog.dark : (lookup(bx, bz) ?? unknown)     // A5: unexplored ground stays dark
                    }
                    if col == runColor { continue }
                    if c > 0 && runColor != 0xFFFFFFFF {
                        let x: Float = x0 + Float(runStart) * px
                        let w: Float = Float(c - runStart) * px
                        out.append(HudLine(text: "", x: x, y: y, scale: s, bg: color(runColor), box: V2(w, px)))
                    }
                    runStart = c
                    runColor = col
                }
            }
        }
        MapCache.shared.batch(draw)
    }

    // Screen position of a world point on that map, or nil when off it.
    static func project(_ x: Float, _ z: Float, x0: Float, y0: Float, cols: Int, rows: Int, px: Float, wx: Float, wz: Float, bpc: Int) -> V2? {
        let cx = (x - wx) / Float(bpc) + Float(cols) / 2, cz = (z - wz) / Float(bpc) + Float(rows) / 2
        guard cx >= 0 && cz >= 0 && cx < Float(cols) && cz < Float(rows) else { return nil }
        return V2(x0 + cx * px, y0 + cz * px)
    }

    // A world point off the map pulled onto its border along the line from the centre (the home marker's edge arrow).
    static func projectEdge(_ x: Float, _ z: Float, x0: Float, y0: Float, cols: Int, rows: Int, px: Float, wx: Float, wz: Float, bpc: Int) -> V2? {
        let dx = (x - wx) / Float(bpc), dz = (z - wz) / Float(bpc)
        let hx = Float(cols) / 2 - 1, hz = Float(rows) / 2 - 1
        let k = max(abs(dx) / hx, abs(dz) / hz)
        guard k > 1 else { return nil }
        return V2(x0 + (Float(cols) / 2 + dx / k) * px, y0 + (Float(rows) / 2 + dz / k) * px)
    }

    // P463 (Oct 25 16:57: "the arrow for where I'm pointing on the radar should correspond to where my headset's pointed
    // and looking at, not what my right joystick is"): the headset's yaw (QuestApp); the body's yaw elsewhere.
    static var facingYaw: (() -> Float?)?
    static func markers(_ out: inout [HudLine], _ g: Game, x0: Float, y0: Float, cols: Int, rows: Int, px: Float, wx: Float, wz: Float, bpc: Int, s: Float, labels: Bool = false) {
        func at(_ x: Float, _ z: Float) -> V2? { project(x, z, x0: x0, y0: y0, cols: cols, rows: rows, px: px, wx: wx, wz: wz, bpc: bpc) }
        if g.dim.dim == .overworld {
            // Home (P131): a house marker on the bed (or the world spawn); off the minimap it sits on the edge toward
            // home, so the way back always shows.
            let hp = g.spawnPoint
            let edge = labels ? nil : projectEdge(hp.x, hp.z, x0: x0, y0: y0, cols: cols, rows: rows, px: px, wx: wx, wz: wz, bpc: bpc)
            if let p = at(hp.x, hp.z) ?? edge {
                out.append(HudLine(text: "", x: p.x - 4 * s, y: p.y - 4 * s, scale: s, bg: V4(0, 0, 0, 0.85), box: V2(8 * s, 8 * s)))
                out.append(HudLine(text: "", x: p.x - 3 * s, y: p.y - 3 * s, scale: s, bg: HomeFinder.colour, box: V2(6 * s, 6 * s)))
                out.append(HudLine(text: "H", x: p.x - 2 * s, y: p.y - 3 * s, scale: s * 0.85, color: V4(0.1, 0.05, 0, 1)))
                if labels {
                    let n = HomeFinder.name(g)
                    out.append(HudLine(text: n, x: p.x + 6 * s, y: p.y - 3 * s, scale: s * 0.85, color: HomeFinder.colour, bg: V4(0, 0, 0, 0.6)))
                }
            }
            for m in MapCache.shared.marks {
                guard let p = at(Float(m.x), Float(m.z)) else { continue }
                let st = MapCache.style(m.kind)
                out.append(HudLine(text: "", x: p.x - 4 * s, y: p.y - 4 * s, scale: s, bg: V4(0, 0, 0, 0.8), box: V2(8 * s, 8 * s)))
                out.append(HudLine(text: "", x: p.x - 3 * s, y: p.y - 3 * s, scale: s, bg: st.color, box: V2(6 * s, 6 * s)))
                out.append(HudLine(text: st.letter, x: p.x - 2 * s, y: p.y - 3 * s, scale: s * 0.85, color: V4(1, 1, 1, 1)))
                // The big map names its towns beside their markers (kept inside the map).
                if labels, let n = m.name {
                    let w = Float(Font.width(n)) * s * 0.85
                    let right = x0 + Float(cols) * px
                    let lx = p.x + 6 * s + w < right ? p.x + 6 * s : p.x - 6 * s - w
                    out.append(HudLine(text: n, x: lx, y: p.y - 3 * s, scale: s * 0.85, color: V4(1, 0.93, 0.7, 1), bg: V4(0, 0, 0, 0.6)))
                }
            }
        }
        // Vehicles loaded nearby: hostile vessels as red diamonds, the rest (yours) blue; the one you steer is the player dot.
        for sh in g.world.ships.list where sh !== g.world.ships.pilot {
            guard let p = at(sh.pos.x, sh.pos.z) else { continue }
            let col = sh.isVessel ? V4(0.95, 0.25, 0.2, 1) : V4(0.35, 0.6, 1, 1)
            out.append(HudLine(text: "", x: p.x - 3 * s, y: p.y - 3 * s, scale: s, bg: V4(0, 0, 0, 0.85), box: V2(6 * s, 6 * s)))
            out.append(HudLine(text: "", x: p.x - 2 * s, y: p.y - 2 * s, scale: s, bg: col, box: V2(4 * s, 4 * s)))
        }
        // P88: bounty hunters after you, as red crosses (on the big map and the minimap).
        for m in g.mobs.mobs where BountyHunters.isHunter(m) {
            guard let p = at(m.pos.x, m.pos.z) else { continue }
            out.append(HudLine(text: "", x: p.x - 3 * s, y: p.y - 3 * s, scale: s, bg: V4(0, 0, 0, 0.85), box: V2(6 * s, 6 * s)))
            out.append(HudLine(text: "", x: p.x - 3 * s, y: p.y - s / 2, scale: s, bg: V4(1, 0.2, 0.15, 1), box: V2(6 * s, s)))
            out.append(HudLine(text: "", x: p.x - s / 2, y: p.y - 3 * s, scale: s, bg: V4(1, 0.2, 0.15, 1), box: V2(s, 6 * s)))
        }
        // O8: the bounty hunters' party on your trail, as a red ring (on the edge of the minimap toward them when off it).
        if let tp = BountyHunters.party, g.dim.dim == .overworld,
           let p = at(tp.x, tp.y) ?? (labels ? nil : projectEdge(tp.x, tp.y, x0: x0, y0: y0, cols: cols, rows: rows, px: px, wx: wx, wz: wz, bpc: bpc)) {
            let red = V4(1, 0.2, 0.15, 1)
            out.append(HudLine(text: "", x: p.x - 5 * s, y: p.y - 5 * s, scale: s, bg: V4(0, 0, 0, 0.85), box: V2(10 * s, 10 * s)))
            out.append(HudLine(text: "", x: p.x - 4 * s, y: p.y - 4 * s, scale: s, bg: red, box: V2(8 * s, 8 * s)))
            out.append(HudLine(text: "", x: p.x - 2 * s, y: p.y - 2 * s, scale: s, bg: V4(0, 0, 0, 0.85), box: V2(4 * s, 4 * s)))
            if labels { out.append(HudLine(text: "Bounty hunters", x: p.x + 7 * s, y: p.y - 3 * s, scale: s * 0.85, color: red, bg: V4(0, 0, 0, 0.6))) }
        }
        // P98: the war bands hunting you (the Reckoning), as orange squares.
        for h in Reckoning.hunts where h.left > 0 {
            guard let p = at(h.pos.x, h.pos.y) else { continue }
            out.append(HudLine(text: "", x: p.x - 4 * s, y: p.y - 4 * s, scale: s, bg: V4(0, 0, 0, 0.85), box: V2(8 * s, 8 * s)))
            out.append(HudLine(text: "", x: p.x - 3 * s, y: p.y - 3 * s, scale: s, bg: V4(1, 0.55, 0.1, 1), box: V2(6 * s, 6 * s)))
        }
        // The player: a dot with a facing tick.
        if let p = at(g.player.pos.x, g.player.pos.z) {
            let yaw = MapDraw.facingYaw?() ?? g.player.yaw
            let f = V2(-sinf(yaw), -cosf(yaw))
            // Bigger, with a longer outlined facing tick (a 6 px square read as just another mark: blind UI critic, map).
            for k in 1...5 {
                let q = p + f * Float(k + 3) * s
                out.append(HudLine(text: "", x: q.x - 2 * s, y: q.y - 2 * s, scale: s, bg: V4(0, 0, 0, 0.85), box: V2(4 * s, 4 * s)))
            }
            for k in 1...5 {
                let q = p + f * Float(k + 3) * s
                out.append(HudLine(text: "", x: q.x - s, y: q.y - s, scale: s, bg: V4(1, 0.9, 0.3, 1), box: V2(2 * s, 2 * s)))
            }
            out.append(HudLine(text: "", x: p.x - 5 * s, y: p.y - 5 * s, scale: s, bg: V4(0, 0, 0, 0.9), box: V2(10 * s, 10 * s)))
            out.append(HudLine(text: "", x: p.x - 4 * s, y: p.y - 4 * s, scale: s, bg: V4(1, 1, 1, 1), box: V2(8 * s, 8 * s)))
        }
    }
}

// MARK: Minimap

enum Minimap {
    // "X 5218  Y -16  Z -6037": Y is the block height the F3 screen shows (sea level 62 on the surface).
    static func coordsLine(_ g: Game) -> String {
        let p = g.player.pos
        let y = Int(floor(p.y - Float(YOFF + g.dim.dim.yShift)))
        return "X \(Int(floor(p.x)))  Y \(y)  Z \(Int(floor(p.z)))"
    }
    // The terrain rows only change when the player crosses a block or new cells arrive: rebuilt then, reused otherwise
    // (rebuilding read 1024 cells through the cache lock every frame: ~11% of the frame's CPU encode in the profile).
    // One entry per split-screen seat.
    private struct TerrainKey: Equatable { var bx: Int, bz: Int, version: Int, fog: Int, x0: Float, y0: Float, px: Float }
    private static var terrainKeys: [TerrainKey?] = [nil, nil]
    private static var terrainRows: [[HudLine]] = [[], []]

    // How far under the map's top the lines below it end (the wallet and honour go under them): the coordinates, the
    // country line and the waypoint line.
    static func below(_ g: Game) -> Float {
        let pin = g.dim.dim == .overworld && MapCache.shared.nearestPin(g.player.pos.x, g.player.pos.z) != nil
        let n = (pin ? 1 : 0) + (Countries.hudLine(g) != nil ? 1 : 0) + (HomeFinder.line(g) != nil ? 1 : 0)
        return 30 + Float(max(0, n - 1)) * 13           // (P191: 13 apart, as below)
    }

    static func lines(_ g: Game, _ L: HudLayout) -> [HudLine] {
        guard Settings.shared.minimap, HudExtras.enabled, g.menu == nil, g.alive, !g.hideHUD else { return [] }
        let s = L.s
        let cols = 32, rows = 32
        let px = 2 * s
        let size = Float(cols) * px
        let x0 = L.W - L.insetX - size - 6 * s
        let y0 = L.insetY + 6 * s + (g.effects.any ? 54 * s : 0)          // below the effect icons
        var out: [HudLine] = [HudLine(text: "", x: x0 - 2 * s, y: y0 - 2 * s, scale: s, bg: V4(0, 0, 0, 0.75), box: V2(size + 4 * s, size + 4 * s))]
        let bpc = 4
        // Every sample is floor(wx) + a whole number of blocks, so the rows depend only on the block the player is in.
        let seat = min(1, g.coop.current)
        let key = TerrainKey(bx: Int(floor(g.player.pos.x)), bz: Int(floor(g.player.pos.z)), version: MapCache.shared.version, fog: MapFog.shared.version, x0: x0, y0: y0, px: px)
        if terrainKeys[seat] != key {
            terrainRows[seat].removeAll(keepingCapacity: true)
            MapDraw.terrain(&terrainRows[seat], x0: x0, y0: y0, cols: cols, rows: rows, px: px, wx: g.player.pos.x, wz: g.player.pos.z, bpc: bpc, s: s)
            terrainKeys[seat] = key
        }
        out.append(contentsOf: terrainRows[seat])
        MapDraw.markers(&out, g, x0: x0, y0: y0, cols: cols, rows: rows, px: px, wx: g.player.pos.x, wz: g.player.pos.z, bpc: bpc, s: s)
        out.append(HudLine(text: "N", x: x0 + size / 2 - 2 * s, y: y0 + s, scale: s, color: V4(1, 1, 1, 0.9)))
        // X, height and Z (Oct 11 Quest playtest P11: "I should be able to see how far up and down I am").
        let coords = Minimap.coordsLine(g)
        out.append(HudLine(text: coords, x: x0 + size - Float(Font.width(coords)) * s, y: y0 + size + 4 * s, scale: s, color: V4(0.9, 0.9, 0.9, 0.9),
                           bg: Settings.shared.textBackground > 0 ? V4(0, 0, 0, Settings.shared.textBackground) : nil))
        // The country you're in, in its flag colour, under the coordinates (Countries.swift).
        // P191 (Oct 13: "the home and distance indicator overlaps the location indicator"): each line's background is
        // 13 tall, so the lines are 13 apart (they were 9: every box covered the foot of the line above).
        var under: Float = 17
        if let (t, c) = Countries.hudLine(g) {
            out.append(HudLine(text: t, x: x0 + size - Float(Font.width(t)) * s, y: y0 + size + under * s, scale: s, color: c,
                               bg: V4(0, 0, 0, max(0.45, Settings.shared.textBackground))))
            under += 13
        }
        // Nearest waypoint: distance and compass direction under the coordinates.
        if g.dim.dim == .overworld, let pin = MapCache.shared.nearestPin(g.player.pos.x, g.player.pos.z) {
            let dx: Float = Float(pin.x) + 0.5 - g.player.pos.x, dz: Float = Float(pin.z) + 0.5 - g.player.pos.z
            let dist = Int((dx * dx + dz * dz).squareRoot())
            let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
            let ang: Float = atan2f(dx, -dz)                               // 0 = north (-z), clockwise
            let i = Int(((ang / (2 * .pi) * 8) + 8.5).rounded(.down)) % 8
            let t = dist < 3 ? "+ here" : "+ \(dist) \(dirs[i])"
            out.append(HudLine(text: t, x: x0 + size - Float(Font.width(t)) * s, y: y0 + size + under * s, scale: s, color: V4(0.4, 0.9, 0.95, 0.95),
                               bg: Settings.shared.textBackground > 0 ? V4(0, 0, 0, Settings.shared.textBackground) : nil))
            under += 13
        }
        // Home (P131): the way back to your bed (or the world spawn), with a compass in hand or once far from it.
        if let t = HomeFinder.line(g) {
            out.append(HudLine(text: t, x: x0 + size - Float(Font.width(t)) * s, y: y0 + size + under * s, scale: s, color: HomeFinder.colour,
                               bg: V4(0, 0, 0, max(0.45, Settings.shared.textBackground))))
        }
        return out
    }
}

// MARK: World map screen

// Opens with M (rebindable) or by holding View. Pan: left stick / D-pad / arrow keys / mouse drag; zoom: LT/RT,
// LB/RB or the mouse wheel; A or Space recentres on you; B / M / Esc closes. The game keeps running.
final class MapMenu: Menu, CustomDrawnMenu {
    var cx: Float, cz: Float
    // P273 (Oct 14 19:31, "can't zoom in on the world map"): on the headset only zoom-out reached the map (the left
    // trigger and grip; the right trigger is the laser's click). Now the right stick and a two-hand pinch zoom both
    // ways about the spot the laser points at, from a few chunks (1 block a cell: 152 x 82 blocks) out to the whole
    // explored world (256 a cell: 39 x 21 thousand), and the level is remembered (Settings.mapZoom).
    static let zooms = [1, 2, 4, 8, 16, 32, 64, 128, 256]
    var zoom = max(0, min(MapMenu.zooms.count - 1, Settings.shared.mapZoom))   // index into zooms (blocks per cell)
    var zoomRepeat: Float = 0
    var pinch0: Float?
    var dragFrom: V2?
    var pressWorld: (Int, Int)?
    var pressAt: V2?, dragged: Float = 0    // a left press: where, and how far it has dragged since (a tap places a pin)

    init(game: Game) {
        cx = game.player.pos.x
        cz = game.player.pos.z
        super.init("World Map", game: game)
        showInventoryLabel = false
        width = 320; height = 214
    }

    var bpc: Int { MapMenu.zooms[zoom] }

    override func tick() {
        let g = game
        let p = g.seatPad ?? PadSnapshot()
        let dt: Float = 1.0 / 60
        let ls = stick(p.lx, p.ly, dead: g.deadZone)
        var pan = V2(ls.x, -ls.y)
        if p.left || g.input.down(Key.arrowLeft) { pan.x -= 1 }
        if p.right || g.input.down(Key.arrowRight) { pan.x += 1 }
        if p.up || g.input.down(Key.arrowUp) { pan.y -= 1 }
        if p.down || g.input.down(Key.arrowDown) { pan.y += 1 }
        let speed = Float(bpc) * 60 * dt
        cx += pan.x * speed
        cz += pan.y * speed
        let q = MapMenu.prevPad
        var dz = 0
        if (p.rt > 0.5 && q.rt <= 0.5) || (p.rb && !q.rb) { dz -= 1 }
        if (p.lt > 0.5 && q.lt <= 0.5) || (p.lb && !q.lb) { dz += 1 }
        dz -= g.input.scrollSteps
        if g.vrHead != nil {
            // (the left trigger and grip are not zoom on the headset: a pinch starts with a grip)
            dz = 0
            zoomRepeat -= dt
            if abs(p.ry) > 0.6 { if zoomRepeat <= 0 { dz += p.ry > 0 ? -1 : 1; zoomRepeat = 0.28 } } else if abs(p.ry) < 0.3 { zoomRepeat = 0 }
            if let d = g.vrPinch {
                if let d0 = pinch0 {
                    if d > d0 * 1.3 { dz -= 1; pinch0 = d } else if d < d0 / 1.3 { dz += 1; pinch0 = d }
                } else { pinch0 = d }
            } else { pinch0 = nil }
        }
        if dz != 0 {
            let nz = max(0, min(MapMenu.zooms.count - 1, zoom + (dz > 0 ? 1 : -1)))
            if nz != zoom {
                // About the pointed spot: the ground under the laser or the mouse stays under it.
                let L0 = HudLayout(g.screen.x, g.screen.y).fitted(self)
                let m = V2(g.input.mouseX, g.input.mouseY)
                let o = origin(L0), px = 2 * L0.s
                let c = (m.x - (o.x + 8 * L0.s)) / px, r = (m.y - (o.y + 18 * L0.s)) / px
                if c >= 0 && c < Float(MapMenu.cols) && r >= 0 && r < Float(MapMenu.rows) {
                    let wx = cx + (c - Float(MapMenu.cols) / 2) * Float(bpc), wz = cz + (r - Float(MapMenu.rows) / 2) * Float(bpc)
                    let k = Float(MapMenu.zooms[nz]) / Float(bpc)
                    cx = wx - (wx - cx) * k; cz = wz - (wz - cz) * k
                }
                zoom = nz
                Settings.shared.mapZoom = nz
                g.sfx(.click, 0.3)
            }
        }
        if (p.a && !q.a) || g.input.tapped(Key.space) { cx = g.player.pos.x; cz = g.player.pos.z }
        // Waypoint at the centre cross: X on the pad or Enter; a click on the map (a right-click, or a left tap that
        // doesn't drag: the headset's laser and trigger) puts it where you point (P73: on the headset the centre cross
        // was the only way and he never found it). Again on a waypoint removes it.
        func pin(_ x: Int, _ z: Int) {
            if MapMenu.follow(g, x: x, z: z, near: Float(max(4, bpc * 3))) { return }      // Q2c-console-20
            let added = MapCache.shared.togglePin(g, x: x, z: z, near: max(3, bpc * 3))
            g.sfx(added ? .click : .uiBack, 0.4)
        }
        let L = HudLayout(g.screen.x, g.screen.y).fitted(self)
        let mouse = V2(g.input.mouseX, g.input.mouseY)
        if (p.x && !q.x) || g.input.tapped(Key.enter) { pin(Int(floor(cx)), Int(floor(cz))) }
        if g.input.rightClicked {
            if let w = world(at: mouse, L) { pin(w.0, w.1) } else { pin(Int(floor(cx)), Int(floor(cz))) }
        }
        // R4 (Oct 13, after P73/P195): a press only pans once the pointer has really left where it went down (a headset
        // laser shakes 10-30 px as the trigger is pulled, which panned the map under the pin and could pass the tap
        // limit); a press that never started panning puts the pin where it went down, however long it was held.
        let tapTol: Float = (g.vrHead != nil ? 18 : 4) * L.s
        if g.input.leftDown {
            if let at = pressAt {
                dragged = max(dragged, simd_length(mouse - at))
                if dragged >= tapTol, let f = dragFrom {
                    let d = (mouse - f) / (2 * L.s) * Float(bpc)
                    cx -= d.x; cz -= d.y
                }
            } else { pressAt = mouse; dragged = 0; pressWorld = world(at: mouse, L) }
            dragFrom = mouse
        } else {
            if pressAt != nil, dragged < tapTol, let w = pressWorld { pin(w.0, w.1) }
            dragFrom = nil; pressAt = nil; pressWorld = nil
        }
        if g.input.tapped(KeyBinds.key(.map)) { g.closeMenu() }
        MapMenu.prevPad = p
    }
    static var prevPad = PadSnapshot()
    static let cols = 152, rows = 82

    // Q2c-console-20: a tap on a marker follows it: a followable one (contract, bounty, horse, ship, vehicle, Director
    // event, the fallen horse, the story's objective) is tracked; a place (town, base, landmark) gets a named waypoint
    // that is tracked. Pins and notes keep their own tap (remove). False: nothing to follow there.
    static func follow(_ g: Game, x: Int, z: Int, near: Float) -> Bool {
        guard g.dim.dim == .overworld else { return false }
        let at = V2(Float(x) + 0.5, Float(z) + 0.5)
        func dist(_ p: V2) -> Float { simd_length(p - at) }
        if MapCache.shared.marks.contains(where: { ($0.kind == "pin" || $0.kind == "note") && dist(V2(Float($0.x), Float($0.z))) <= near }) { return false }
        if let t = Waymarks.candidates(g).filter({ $0.kind != "pin" && $0.kind != "note" })
            .min(by: { dist(V2($0.pos.x, $0.pos.z)) < dist(V2($1.pos.x, $1.pos.z)) }), dist(V2(t.pos.x, t.pos.z)) <= near {
            Waymarks.track(g, t)
            g.sfx(.xp, 0.4)
            return true
        }
        let moving: Set<String> = ["contract", "bounty", "my_horse", "my_ship", "my_vehicle", "director", "horse_grave", "objective"]
        guard let m = MapCache.shared.marks.filter({ !moving.contains($0.kind) && $0.kind != "pin" && $0.kind != "note" })
            .min(by: { dist(V2(Float($0.x), Float($0.z))) < dist(V2(Float($1.x), Float($1.z))) }), dist(V2(Float(m.x), Float(m.z))) <= near else { return false }
        let name = m.name ?? MapCache.style(m.kind).name
        MapCache.shared.pinPlace(g, x: m.x, z: m.z, name: name)
        Waymarks.track(g, Waymarks.Target(kind: "pin", key: "\(m.x),\(m.z)", name: "Waypoint: " + name,
                                          pos: V3(Float(m.x) + 0.5, g.player.pos.y, Float(m.z) + 0.5)))
        g.sfx(.xp, 0.4)
        return true
    }

    // The world column under a point on the screen, if it is over the map (drawLines' grid).
    func world(at m: V2, _ L: HudLayout) -> (Int, Int)? {
        let o = origin(L), s = L.s, px = 2 * s
        let x0 = o.x + 8 * s, y0 = o.y + 18 * s
        let c = (m.x - x0) / px, r = (m.y - y0) / px
        guard c >= 0 && c < Float(MapMenu.cols) && r >= 0 && r < Float(MapMenu.rows) else { return nil }
        let wx: Float = cx + (c - Float(MapMenu.cols) / 2) * Float(bpc)
        let wz: Float = cz + (r - Float(MapMenu.rows) / 2) * Float(bpc)
        return (Int(floor(wx)), Int(floor(wz)))
    }

    func drawLines(_ L: HudLayout, _ o: V2) -> [HudLine] {
        let g = game
        let s = L.s
        var out: [HudLine] = []
        let px = 2 * s
        let x0 = o.x + 8 * s, y0 = o.y + 18 * s
        let cols = MapMenu.cols, rows = MapMenu.rows
        MapDraw.terrain(&out, x0: x0, y0: y0, cols: cols, rows: rows, px: px, wx: cx, wz: cz, bpc: bpc, s: s)
        Countries.mapBorders(&out, g, x0: x0, y0: y0, cols: cols, rows: rows, px: px, wx: cx, wz: cz, bpc: bpc, s: s)
        WarFront.mapFronts(&out, g, x0: x0, y0: y0, cols: cols, rows: rows, px: px, wx: cx, wz: cz, bpc: bpc)
        Nation.mapProvinces(&out, g, x0: x0, y0: y0, cols: cols, rows: rows, px: px, wx: cx, wz: cz, bpc: bpc, s: s)
        // P273 (c): marks keep their size at every zoom; past 64 blocks a cell the names give way to the hover label
        // (dozens of towns' names piled over each other).
        MapDraw.markers(&out, g, x0: x0, y0: y0, cols: cols, rows: rows, px: px, wx: cx, wz: cz, bpc: bpc, s: s, labels: bpc <= 64)
        // Centre cross and what is under it.
        let mx = x0 + Float(cols) * px / 2, my = y0 + Float(rows) * px / 2
        out.append(HudLine(text: "", x: mx - 4 * s, y: my - s / 2, scale: s, bg: V4(1, 1, 1, 0.8), box: V2(8 * s, s)))
        out.append(HudLine(text: "", x: mx - s / 2, y: my - 4 * s, scale: s, bg: V4(1, 1, 1, 0.8), box: V2(s, 8 * s)))
        let bx = Int(floor(cx)), bz = Int(floor(cz))
        let biome = g.world.gen.column(bx, bz).biome.displayName
        let info = "\(biome)   \(bx), \(bz)   1 cell = \(bpc) blocks" + (g.dim.dim == .overworld ? "   \(Seasons.label)" : "")
        out.append(HudLine(text: info, x: o.x + 8 * s, y: o.y + Float(height - 13) * s, scale: s, color: V4(0.2, 0.2, 0.22, 1)))
        let marks = MapCache.shared.marks
        let bases = marks.filter { $0.kind == "military_base" }.count
        let grey = marks.filter { $0.kind == Greywall.kind }.count
        let vill = marks.filter { $0.kind == "village" }.count
        let vessels = marks.filter { $0.kind.hasPrefix("vessel_") }.count
        // Y4: which force is the enemy over everything and which is the stage to take; Y6: the next objective.
        let goal = marks.contains { $0.kind == "objective" } ? "   ! next objective" : ""
        let key = "B Capital (enemy) \(bases)   G Greywall \(grey)   V towns \(vill)" + (vessels > 0 ? "   F/C patrols \(vessels)" : "") + goal
        out.append(HudLine(text: key, x: o.x + Float(width - 8) * s - Float(Font.width(key)) * s, y: o.y + 6 * s, scale: s, color: V4(0.25, 0.25, 0.28, 1)))
        // Q2c-console-30: a card for the marker under the pointer: what it is, its name, how far.
        let mouse = V2(g.input.mouseX, g.input.mouseY)
        if g.dim.dim == .overworld, let w = world(at: mouse, L) {
            let reach = Float(bpc) * 3
            var best: (String, Float, V2)?
            func consider(_ label: String, _ x: Float, _ z: Float) {
                let d = simd_length(V2(x - Float(w.0), z - Float(w.1)))
                if d <= reach && d < (best?.1 ?? .infinity) { best = (label, d, V2(x, z)) }
            }
            consider(HomeFinder.name(g) + ": where you wake", g.spawnPoint.x, g.spawnPoint.z)
            for m in marks {
                let st = MapCache.style(m.kind)
                consider(m.name.map { st.name + ": " + $0 } ?? st.name, Float(m.x) + 0.5, Float(m.z) + 0.5)
            }
            if let b = best {
                let far = Int(simd_length(V2(b.2.x - g.player.pos.x, b.2.y - g.player.pos.z)))
                let t = b.0 + "  (\(far) blocks)"
                let tw = Float(Font.width(t)) * s
                let right = x0 + Float(cols) * px
                var lx = mouse.x + 8 * s, ly = mouse.y - 14 * s
                if lx + tw + 4 * s > right { lx = max(x0 + 2 * s, mouse.x - 8 * s - tw) }
                if ly < y0 + 2 * s { ly = mouse.y + 10 * s }
                out.append(HudLine(text: "", x: lx - 3 * s, y: ly - 2 * s, scale: s, bg: V4(0.08, 0.08, 0.1, 0.92), box: V2(tw + 6 * s, 11 * s)))
                out.append(HudLine(text: t, x: lx, y: ly, scale: s, color: V4(1, 0.95, 0.8, 1)))
            }
        }
        return out
    }

    var legend: String {
        // (On the headset: the laser and trigger, P73.)
        if game.vrHead != nil { return Prompt.line([(.move, "Pan"), (.tabs, "Zoom"), (.select, "Centre"), (.back, "Close")]) + "   Point + trigger: follow a marker or drop a waypoint" }
        if Prompt.pad {
            return Prompt.line([(.move, "Pan"), (.tabs, "Zoom"), (.select, "Centre"), (.alt, "Waypoint"), (.back, "Close")])
        }
        return "Arrows / drag Pan   " + Glyph.mouseM.s + " Zoom   " + Glyphs.key("Space") + " Centre   " + Glyph.mouseR.s + " Waypoint   " + Glyphs.key("Esc") + " Close"
    }
}

// Menus that draw their own content as HudLines (Renderer calls drawLines inside the panel).
protocol CustomDrawnMenu: AnyObject {
    func drawLines(_ L: HudLayout, _ o: V2) -> [HudLine]
    var legend: String { get }
}

// View held 0.35 s opens the map; a quick tap still cycles the camera (Game.tick).
enum MapInput {
    static var viewDown: Double = -1
    static var opened = false
    static func viewTap(_ g: Game, _ p: PadSnapshot, _ q: PadSnapshot) -> Bool {
        if p.view && !q.view { viewDown = g.clock; opened = false }
        if p.view && !opened && viewDown >= 0 && g.clock - viewDown > 0.35 {
            opened = true
            g.openMenu(MapMenu(game: g))
            return false
        }
        if !p.view && q.view {
            let tap = !opened && viewDown >= 0
            viewDown = -1
            return tap
        }
        return false
    }
}
