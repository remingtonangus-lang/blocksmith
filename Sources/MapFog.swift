import Foundation
import simd

// Fog of war on the map and minimap (backlog A5): only ground a player has been near shows its colours; the rest is
// dark, with the discovered sites (bases, towns, vessels: MapCache marks, which radar and the map tables add from afar)
// still marked on it. Explored ground is kept per world and dimension in 32-block tiles (mapfog.json beside
// mapmarks.json), revealed 96 blocks round every player once a second. Creative play shows the whole map.
final class MapFog {
    static let shared = MapFog()
    static let tile = 32
    static let reveal = 96
    static let dark: UInt32 = 0x0C0D10

    private var tiles: [String: Set<Int64>] = [:]       // dimension -> explored tiles
    private var cur: Set<Int64> = []                    // tiles[dim], kept apart so the map's per-cell test hashes no String
    private var lastURL: URL?                           // the loaded world's file (saved before another world loads)
    private var dim = "overworld"
    private var world = ""
    private var dirty = false
    private var saveTimer: Double = 0
    private var timer: Double = -10
    private(set) var version = 0                        // bumped when tiles are revealed (minimap redraw)
    var active = true                                   // false in creative (the whole map shows)

    var exploredCount: Int { cur.count }

    @inline(__always) static func key(_ x: Int, _ z: Int) -> Int64 {
        MapCache.key(floorDiv(x, tile), floorDiv(z, tile))
    }

    // True when the cell at (x, z) is still under the fog (the map draws it dark).
    @inline(__always) func fogged(_ x: Int, _ z: Int) -> Bool {
        active && !cur.contains(MapFog.key(x, z))
    }

    func seen(_ x: Int, _ z: Int) -> Bool { cur.contains(MapFog.key(x, z)) }

    private func url(_ g: Game) -> URL? { g.save?.dir.appendingPathComponent("mapfog.json") }

    private func load(_ g: Game) {
        let w = g.save?.dir.lastPathComponent ?? ""
        guard w != world else { return }
        if dirty, let u = lastURL, let d = try? JSONEncoder().encode(tiles.mapValues { $0.sorted() }) { try? d.write(to: u, options: .atomic) }
        dirty = false
        world = w
        lastURL = url(g)
        tiles = [:]
        if let u = url(g), let d = try? Data(contentsOf: u), let t = try? JSONDecoder().decode([String: [Int64]].self, from: d) {
            for (k, v) in t { tiles[k] = Set(v) }
        }
        cur = tiles[dim] ?? []
        version &+= 1
    }

    func save(_ g: Game) {
        guard dirty, let u = url(g) else { return }
        dirty = false
        let out = tiles.mapValues { $0.sorted() }
        if let d = try? JSONEncoder().encode(out) { try? d.write(to: u, options: .atomic) }
    }

    // Every frame from the HUD (MapCache.tick's caller): reveal round every player once a second, save every 10 s.
    func tick(_ g: Game) {
        load(g)
        active = g.survival
        let d = g.dim.dim.rawValue                       // (the case name: the keys saved before)
        if d != dim { dim = d; cur = tiles[d] ?? []; version &+= 1 }
        guard g.clock - timer >= 1 else { return }
        timer = g.clock
        for i in 0..<max(1, g.coop.seatCount) { reveal(around: g.coop.seatPlayer(i, g).pos) }
        if g.clock - saveTimer >= 10 { saveTimer = g.clock; save(g) }
    }

    // Marks the tiles within `reveal` blocks of a point explored.
    func reveal(around p: V3) {
        let px = Int(floor(p.x)), pz = Int(floor(p.z))
        let r = MapFog.reveal / MapFog.tile + 1
        let tx = floorDiv(px, MapFog.tile), tz = floorDiv(pz, MapFog.tile)
        var set = tiles[dim] ?? []
        var added = false
        for dz in -r...r { for dx in -r...r {
            // the tile's nearest point within reach
            let x0 = (tx + dx) * MapFog.tile, z0 = (tz + dz) * MapFog.tile
            let nx = max(x0, min(x0 + MapFog.tile - 1, px)) - px, nz = max(z0, min(z0 + MapFog.tile - 1, pz)) - pz
            guard nx * nx + nz * nz <= MapFog.reveal * MapFog.reveal else { continue }
            if set.insert(MapCache.key(tx + dx, tz + dz)).inserted { added = true }
        } }
        if added { tiles[dim] = set; cur = set; dirty = true; version &+= 1 }
    }

    // Harness: forget everything (temp world tests), or swap the explored tiles out and back.
    func reset() { tiles = [:]; world = ""; version &+= 1 }
    var snapshot: [String: Set<Int64>] { get { tiles } set { tiles = newValue; version &+= 1 } }
}

// The compass (A5): held in either hand on the surface, a strip across the top of the view shows the heading and the
// discovered sites in front, each by its map letter, and names the nearest one with its distance and direction.
enum CompassHUD {
    static let span: Float = .pi * 2 / 3                  // 120 degrees across the strip
    static let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]

    static func holding(_ g: Game) -> Bool {
        let c = Items.has("compass") ? Items.id("compass") : ItemID.max
        let m = g.inventory.main[g.inventory.selected], o = g.inventory.offhand[0]
        return (!m.isEmpty && m.item == c) || (!o.isEmpty && o.item == c)
    }

    // Bearing of a world direction, 0 = north (-z), clockwise, 0..2pi.
    static func bearing(_ dx: Float, _ dz: Float) -> Float {
        let a = atan2f(dx, -dz)
        return a < 0 ? a + 2 * .pi : a
    }
    static func compassPoint(_ a: Float) -> String { dirs[Int((a / (2 * .pi) * 8 + 0.5).rounded(.down)) % 8] }

    // The sites on the strip: (offset -1...1 across it, letter, colour), and the nearest discovered site.
    static func marks(_ g: Game) -> (on: [(Float, String, V4)], nearest: (String, Int, String)?) {
        let p = g.player.pos
        let heading = bearing(-sinf(g.player.yaw), -cosf(g.player.yaw))
        var on: [(Float, String, V4)] = []
        var best: (String, Int, String)?
        var bestD = Float.infinity
        for m in MapCache.shared.marks where m.kind != "pin" {
            let dx = Float(m.x) + 0.5 - p.x, dz = Float(m.z) + 0.5 - p.z
            let d = (dx * dx + dz * dz).squareRoot()
            let b = bearing(dx, dz)
            var rel = b - heading
            while rel > .pi { rel -= 2 * .pi }
            while rel < -.pi { rel += 2 * .pi }
            let st = MapCache.style(m.kind)
            if abs(rel) <= span / 2 && d < 3000 { on.append((rel / (span / 2), st.letter, st.color)) }
            if d < bestD { bestD = d; best = (m.name ?? st.name, Int(d), compassPoint(b)) }
        }
        return (on, best)
    }

    static func lines(_ g: Game, _ L: HudLayout) -> [HudLine] {
        guard HudExtras.enabled, g.menu == nil, g.alive, !g.hideHUD, g.dim.dim == .overworld, holding(g) else { return [] }
        let s = L.s
        let w: Float = 160 * s, h: Float = 12 * s
        let x0 = L.W / 2 - w / 2, y0 = L.insetY + 4 * s
        var out = [HudLine(text: "", x: x0, y: y0, scale: s, bg: V4(0, 0, 0, 0.6), box: V2(w, h))]
        let heading = bearing(-sinf(g.player.yaw), -cosf(g.player.yaw))
        // Cardinal and half-cardinal points in view.
        for (i, n) in dirs.enumerated() {
            var rel = Float(i) * .pi / 4 - heading
            while rel > .pi { rel -= 2 * .pi }
            while rel < -.pi { rel += 2 * .pi }
            guard abs(rel) <= span / 2 else { continue }
            let x = x0 + w / 2 + rel / (span / 2) * (w / 2 - 6 * s)
            out.append(HudLine(text: n, x: x - Float(Font.width(n)) * s / 2, y: y0 + 2 * s, scale: s,
                               color: n == "N" ? V4(1, 0.35, 0.3, 1) : V4(0.9, 0.9, 0.9, n.count == 1 ? 1 : 0.6)))
        }
        let (on, nearest) = marks(g)
        for (o, letter, c) in on {
            let x = x0 + w / 2 + o * (w / 2 - 6 * s)
            out.append(HudLine(text: letter, x: x - Float(Font.width(letter)) * s / 2, y: y0 + h + s, scale: s, color: c, bg: V4(0, 0, 0, 0.5)))
        }
        out.append(HudLine(text: "", x: x0 + w / 2 - 0.5 * s, y: y0, scale: s, bg: V4(1, 1, 1, 0.8), box: V2(s, h)))     // the lubber line
        if let n = nearest {
            let t = "\(n.0) \(n.1) \(n.2)"
            out.append(HudLine(text: t, x: L.W / 2 - Float(Font.width(t)) * s / 2, y: y0 + h + 11 * s, scale: s, color: V4(0.95, 0.9, 0.7, 0.95),
                               bg: V4(0, 0, 0, max(0.4, Settings.shared.textBackground))))
        }
        return out
    }
}
