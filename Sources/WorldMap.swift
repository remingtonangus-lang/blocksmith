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

    struct Mark: Codable, Hashable { var kind: String; var x: Int; var z: Int }
    private(set) var marks: [Mark] = []
    private var marksWorld = ""
    private var scanTimer: Double = 0

    static func key(_ cx: Int, _ cz: Int) -> Int64 { (Int64(cx) << 32) | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: cz))) }

    // Switches to a generator (new world or dimension): the cache restarts.
    func use(_ g: TerrainGenerator) {
        let id = ObjectIdentifier(g)
        guard id != genID else { return }
        lock.lock()
        cells.removeAll(); queue.removeAll(); pending.removeAll()
        lock.unlock()
        gen = g
        genID = id
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

    // Samples queued cells, newest requests first (what is on screen now).
    private func drain() {
        while true {
            lock.lock()
            guard let g = gen, !queue.isEmpty else { working = false; lock.unlock(); return }
            let batch = Array(queue.suffix(256))
            queue.removeLast(batch.count)
            lock.unlock()
            var out: [(Int64, UInt32)] = []
            out.reserveCapacity(batch.count)
            for k in batch {
                let cx = Int(Int32(truncatingIfNeeded: k >> 32)), cz = Int(Int32(truncatingIfNeeded: k & 0xFFFF_FFFF))
                let c = g.column(cx * MapCache.cellBlocks + 2, cz * MapCache.cellBlocks + 2)
                out.append((k, MapCache.shade(c.biome, height: c.height)))
            }
            lock.lock()
            for (k, c) in out { cells[k] = c; pending.remove(k) }
            if cells.count > 400_000 { cells.removeAll() }
            lock.unlock()
        }
    }

    // Biome base colour, lighter on high ground and darker in deep water.
    static func shade(_ b: Biome, height h: Int) -> UInt32 {
        var base: UInt32
        if b.isOcean { base = b.isDeepOcean ? 0x2A4E9A : 0x3A66C0 }
        else if b.isRiver { base = 0x4479D0 }
        else if b.isBeach { base = b == .stonyShore ? 0x8C8C88 : 0xDCCB8E }
        else if b == .desert { base = 0xE0D29A }
        else if b.isBadlands { base = 0xC0673A }
        else if b == .mushroomFields { base = 0x9C7FA2 }
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

    func discover(_ g: Game, kind: String, x: Int, z: Int) {
        guard !marks.contains(where: { $0.kind == kind && abs($0.x - x) < 24 && abs($0.z - z) < 24 }) else { return }
        marks.append(Mark(kind: kind, x: x, z: z))
        saveMarks(g)
        g.onToast?("\(MapCache.style(kind).name) marked on the map")
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
        case "military_base": return ("B", V4(0.85, 0.2, 0.15, 1), "Capital citadel")
        case "village": return ("V", V4(0.95, 0.8, 0.3, 1), "Village")
        case "vessel_frigate": return ("F", V4(0.6, 0.35, 0.9, 1), "Skyward Frigate patrol")
        case "vessel_carriage": return ("C", V4(0.95, 0.5, 0.15, 1), "Siege Carriage patrol")
        case "pin": return ("+", V4(0.2, 0.8, 0.85, 1), "Waypoint")
        default: return ("?", V4(0.7, 0.7, 0.7, 1), kind)
        }
    }

    // Once a second: bases and villages within 96 blocks count as discovered (overworld only).
    func tick(_ g: Game) {
        loadMarks(g)
        use(g.world.gen)
        guard g.clock - scanTimer > 1, g.dim.dim == .overworld, let sc = g.world.gen.structures else { return }
        scanTimer = g.clock
        let px = Int(floor(g.player.pos.x)), pz = Int(floor(g.player.pos.z))
        for t in sc.types where t.name == "military_base" || t.name == "village" {
            for s in sc.startsNear(cx: floorDiv(px, CS), cz: floorDiv(pz, CS), t) {
                let cx = (s.min.x + s.max.x) / 2, cz = (s.min.z + s.max.z) / 2
                let dx = cx - px, dz = cz - pz
                if dx * dx + dz * dz < 96 * 96 { discover(g, kind: t.name, x: cx, z: cz) }
            }
        }
        // Vessel patrols (ShipVessels): their home point counts once you come within 200 blocks of it.
        let rx = floorDiv(px, Vessels.region), rz = floorDiv(pz, Vessels.region)
        for dz in -1...1 { for dx in -1...1 {
            guard let e = Vessels.encounter(seed: g.world.seed, rx: rx + dx, rz: rz + dz, gen: g.world.gen) else { continue }
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
        let cache = MapCache.shared
        let unknown: UInt32 = 0x1E2024
        for r in 0..<rows {
            var runStart = 0
            var runColor: UInt32 = 0xFFFFFFFF
            let bz = Int(floor(wz + (Float(r) - Float(rows) / 2) * Float(bpc)))
            for c in 0...cols {
                var col: UInt32 = 0xFFFFFFFE
                if c < cols {
                    let bx = Int(floor(wx + (Float(c) - Float(cols) / 2) * Float(bpc)))
                    col = cache.color(bx, bz) ?? unknown
                }
                if col != runColor {
                    if c > 0 && runColor != 0xFFFFFFFF {
                        out.append(HudLine(text: "", x: x0 + Float(runStart) * px, y: y0 + Float(r) * px, scale: s, bg: color(runColor), box: V2(Float(c - runStart) * px, px)))
                    }
                    runStart = c
                    runColor = col
                }
            }
        }
    }

    // Screen position of a world point on that map, or nil when off it.
    static func project(_ x: Float, _ z: Float, x0: Float, y0: Float, cols: Int, rows: Int, px: Float, wx: Float, wz: Float, bpc: Int) -> V2? {
        let cx = (x - wx) / Float(bpc) + Float(cols) / 2, cz = (z - wz) / Float(bpc) + Float(rows) / 2
        guard cx >= 0 && cz >= 0 && cx < Float(cols) && cz < Float(rows) else { return nil }
        return V2(x0 + cx * px, y0 + cz * px)
    }

    static func markers(_ out: inout [HudLine], _ g: Game, x0: Float, y0: Float, cols: Int, rows: Int, px: Float, wx: Float, wz: Float, bpc: Int, s: Float) {
        func at(_ x: Float, _ z: Float) -> V2? { project(x, z, x0: x0, y0: y0, cols: cols, rows: rows, px: px, wx: wx, wz: wz, bpc: bpc) }
        if g.dim.dim == .overworld {
            if let p = at(g.spawnPoint.x, g.spawnPoint.z) {
                out.append(HudLine(text: "", x: p.x - 2 * s, y: p.y - 2 * s, scale: s, bg: V4(1, 1, 1, 0.9), box: V2(4 * s, 4 * s)))
            }
            for m in MapCache.shared.marks {
                guard let p = at(Float(m.x), Float(m.z)) else { continue }
                let st = MapCache.style(m.kind)
                out.append(HudLine(text: "", x: p.x - 4 * s, y: p.y - 4 * s, scale: s, bg: V4(0, 0, 0, 0.8), box: V2(8 * s, 8 * s)))
                out.append(HudLine(text: "", x: p.x - 3 * s, y: p.y - 3 * s, scale: s, bg: st.color, box: V2(6 * s, 6 * s)))
                out.append(HudLine(text: st.letter, x: p.x - 2 * s, y: p.y - 3 * s, scale: s * 0.85, color: V4(1, 1, 1, 1)))
            }
        }
        // Vehicles loaded nearby: hostile vessels as red diamonds, the rest (yours) blue; the one you steer is the player dot.
        for sh in g.world.ships.list where sh !== g.world.ships.pilot {
            guard let p = at(sh.pos.x, sh.pos.z) else { continue }
            let col = sh.isVessel ? V4(0.95, 0.25, 0.2, 1) : V4(0.35, 0.6, 1, 1)
            out.append(HudLine(text: "", x: p.x - 3 * s, y: p.y - 3 * s, scale: s, bg: V4(0, 0, 0, 0.85), box: V2(6 * s, 6 * s)))
            out.append(HudLine(text: "", x: p.x - 2 * s, y: p.y - 2 * s, scale: s, bg: col, box: V2(4 * s, 4 * s)))
        }
        // The player: a dot with a facing tick.
        if let p = at(g.player.pos.x, g.player.pos.z) {
            let f = V2(-sinf(g.player.yaw), -cosf(g.player.yaw))
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
        MapDraw.terrain(&out, x0: x0, y0: y0, cols: cols, rows: rows, px: px, wx: g.player.pos.x, wz: g.player.pos.z, bpc: bpc, s: s)
        MapDraw.markers(&out, g, x0: x0, y0: y0, cols: cols, rows: rows, px: px, wx: g.player.pos.x, wz: g.player.pos.z, bpc: bpc, s: s)
        out.append(HudLine(text: "N", x: x0 + size / 2 - 2 * s, y: y0 + s, scale: s, color: V4(1, 1, 1, 0.9)))
        let coords = "\(Int(floor(g.player.pos.x))) \(Int(floor(g.player.pos.z)))"
        out.append(HudLine(text: coords, x: x0 + size - Float(Font.width(coords)) * s, y: y0 + size + 4 * s, scale: s, color: V4(0.9, 0.9, 0.9, 0.9),
                           bg: Settings.shared.textBackground > 0 ? V4(0, 0, 0, Settings.shared.textBackground) : nil))
        // Nearest waypoint: distance and compass direction under the coordinates.
        if g.dim.dim == .overworld, let pin = MapCache.shared.nearestPin(g.player.pos.x, g.player.pos.z) {
            let dx: Float = Float(pin.x) + 0.5 - g.player.pos.x, dz: Float = Float(pin.z) + 0.5 - g.player.pos.z
            let dist = Int((dx * dx + dz * dz).squareRoot())
            let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
            let ang: Float = atan2f(dx, -dz)                               // 0 = north (-z), clockwise
            let i = Int(((ang / (2 * .pi) * 8) + 8.5).rounded(.down)) % 8
            let t = dist < 3 ? "+ here" : "+ \(dist) \(dirs[i])"
            out.append(HudLine(text: t, x: x0 + size - Float(Font.width(t)) * s, y: y0 + size + 13 * s, scale: s, color: V4(0.4, 0.9, 0.95, 0.95),
                               bg: Settings.shared.textBackground > 0 ? V4(0, 0, 0, Settings.shared.textBackground) : nil))
        }
        return out
    }
}

// MARK: World map screen

// Opens with M (rebindable) or by holding View. Pan: left stick / D-pad / arrow keys / mouse drag; zoom: LT/RT,
// LB/RB or the mouse wheel; A or Space recentres on you; B / M / Esc closes. The game keeps running.
final class MapMenu: Menu, CustomDrawnMenu {
    var cx: Float, cz: Float
    static let zooms = [2, 4, 8, 16, 32, 64]
    var zoom = 2                   // index into zooms (blocks per cell)
    var dragFrom: V2?

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
        let p = PadManager.shared.lastMapped ?? PadSnapshot()
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
        if dz != 0 { zoom = max(0, min(MapMenu.zooms.count - 1, zoom + (dz > 0 ? 1 : -1))); g.sfx(.click, 0.3) }
        if (p.a && !q.a) || g.input.tapped(Key.space) { cx = g.player.pos.x; cz = g.player.pos.z }
        // Waypoint at the centre cross: X on the pad, Enter or right-click (again on a waypoint removes it).
        if (p.x && !q.x) || g.input.tapped(Key.enter) || g.input.rightClicked {
            let added = MapCache.shared.togglePin(g, x: Int(floor(cx)), z: Int(floor(cz)), near: max(3, bpc * 3))
            g.sfx(added ? .click : .uiBack, 0.4)
        }
        if g.input.leftDown {
            let m = V2(g.input.mouseX, g.input.mouseY)
            if let f = dragFrom {
                let L = HudLayout(g.screen.x, g.screen.y).fitted(self)
                let d = (m - f) / (2 * L.s) * Float(bpc)
                cx -= d.x; cz -= d.y
            }
            dragFrom = m
        } else { dragFrom = nil }
        if g.input.tapped(KeyBinds.key(.map)) { g.closeMenu() }
        MapMenu.prevPad = p
    }
    static var prevPad = PadSnapshot()

    func drawLines(_ L: HudLayout, _ o: V2) -> [HudLine] {
        let g = game
        let s = L.s
        var out: [HudLine] = []
        let px = 2 * s
        let x0 = o.x + 8 * s, y0 = o.y + 18 * s
        let cols = 152, rows = 82
        MapDraw.terrain(&out, x0: x0, y0: y0, cols: cols, rows: rows, px: px, wx: cx, wz: cz, bpc: bpc, s: s)
        MapDraw.markers(&out, g, x0: x0, y0: y0, cols: cols, rows: rows, px: px, wx: cx, wz: cz, bpc: bpc, s: s)
        // Centre cross and what is under it.
        let mx = x0 + Float(cols) * px / 2, my = y0 + Float(rows) * px / 2
        out.append(HudLine(text: "", x: mx - 4 * s, y: my - s / 2, scale: s, bg: V4(1, 1, 1, 0.8), box: V2(8 * s, s)))
        out.append(HudLine(text: "", x: mx - s / 2, y: my - 4 * s, scale: s, bg: V4(1, 1, 1, 0.8), box: V2(s, 8 * s)))
        let bx = Int(floor(cx)), bz = Int(floor(cz))
        let biome = g.world.gen.column(bx, bz).biome.displayName
        let info = "\(biome)   \(bx), \(bz)   1 cell = \(bpc) blocks"
        out.append(HudLine(text: info, x: o.x + 8 * s, y: o.y + Float(height - 13) * s, scale: s, color: V4(0.2, 0.2, 0.22, 1)))
        let marks = MapCache.shared.marks
        let bases = marks.filter { $0.kind == "military_base" }.count
        let vill = marks.filter { $0.kind == "village" }.count
        let vessels = marks.filter { $0.kind.hasPrefix("vessel_") }.count
        let key = "B bases \(bases)   V villages \(vill)" + (vessels > 0 ? "   F/C patrols \(vessels)" : "")
        out.append(HudLine(text: key, x: o.x + Float(width - 8) * s - Float(Font.width(key)) * s, y: o.y + 6 * s, scale: s, color: V4(0.25, 0.25, 0.28, 1)))
        return out
    }

    var legend: String {
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
