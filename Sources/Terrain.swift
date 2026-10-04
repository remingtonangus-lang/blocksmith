import Foundation
import os

// Realistic surface model (heights in displayed y, sea surface at 62). Everything is a pure function of
// world position and seed, evaluated on fixed global grids, so chunks agree exactly and seeds are stable.
//
//  1. Macro fields (16-block grid, bilinear): continentalness from domain-warped fbm (continents thousands
//     of blocks wide, shelves, deep basins, rare open-ocean islands); mountain belts along the zero lines of a
//     warped low-frequency noise (long ranges with a crest, foothills on both sides); a ruggedness field for
//     hill country; climate: sea-level temperature from latitude-like bands along z plus noise; rainfall from
//     noise, a three-cell latitude pattern (wet tropics, dry subtropics, wet mid-latitudes, dry poles),
//     continental interiors drier, prevailing winds by latitude giving wet windward slopes and rain shadows.
//  2. Detail (4-block grid, the density lattice): hills, mountain massifs, mesa terraces in hot dry country,
//     then an erosion filter: stripes aligned with the slope at four scales, each fed the previous one's
//     gradient, so ridges and gullies branch downhill instead of looking like noise.
//  3. Rivers and lakes: a jittered 128-block node graph over the smooth elevation; each land node drains to
//     its steepest lower neighbour, rain-weighted upstream counts give river size, nodes without a lower
//     neighbour hold lakes filled to their rim's spill level. Valleys are cut toward the river level
//     (V-shaped in mountains, flat floodplains in lowlands), channels and levees keep the water in, and the
//     water surface steps down toward lakes and the sea.
//  4. Biomes come from the local climate with altitude lapse (snowlines, treelines), so neighbours are always
//     climate neighbours; small coherent climate jitter interleaves borders into ecotones.
let SEA_D: Float = Float(SEA - YOFF)

@inline(__always) func gridKey(_ a: Int, _ b: Int) -> Int64 { (Int64(a) << 32) ^ Int64(UInt32(truncatingIfNeeded: b)) }

// Thread-safe direct-mapped memo for pure functions of a 2D integer key (eviction just recomputes).
final class GridCache<T> {
    private var keys: [Int64]
    private var vals: [T]
    private let shift: UInt64
    private let lock: UnsafeMutablePointer<os_unfair_lock>

    init(bits: Int, empty: T) {
        keys = [Int64](repeating: Int64.min, count: 1 << bits)
        vals = [T](repeating: empty, count: 1 << bits)
        shift = UInt64(64 - bits)
        lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }
    deinit { lock.deallocate() }

    @inline(__always) func get(_ a: Int, _ b: Int, _ make: () -> T) -> T {
        let k = gridKey(a, b)
        let slot = Int(truncatingIfNeeded: (UInt64(bitPattern: k) &* 0x9E3779B97F4A7C15) >> shift)
        os_unfair_lock_lock(lock)
        if keys[slot] == k {
            let v = vals[slot]
            os_unfair_lock_unlock(lock)
            return v
        }
        os_unfair_lock_unlock(lock)
        let v = make()
        os_unfair_lock_lock(lock)
        keys[slot] = k
        vals[slot] = v
        os_unfair_lock_unlock(lock)
        return v
    }
}

final class Terrain {
    // Smooth large-scale fields.
    struct Macro {
        var e: Float = 0      // smooth base elevation (displayed y)
        var c: Float = 0      // continentalness (< 0 sea)
        var u: Float = 0      // mountain uplift 0...1
        var r: Float = 0      // ruggedness (hill country) 0...1
        var ts: Float = 0     // sea-level temperature (-1 polar ... +1 tropical)
        var w: Float = 0      // rainfall (-1 arid ... +1 very wet)
        var isl: Float = 0    // remote ocean island
    }
    // One 4-block lattice column.
    struct Node {
        var h: Float = 0      // final surface height
        var wl: Float = 62    // water surface (sea level unless a river or lake is here)
        var rv: Float = 99    // distance to the nearest channel / lake in channel half-widths (< 1 inside)
        var ts: Float = 0, w: Float = 0, c: Float = 0, u: Float = 0, r: Float = 0
        var slope: Float = 0  // smooth slope (rise per block) before erosion and rivers
        var v: Float = 0      // variant noise (picks between sibling biomes)
        var jt: Float = 0, jw: Float = 0   // ecotone jitter for temperature and rainfall
        var dry: Float = 0    // 1 on a dry lake bed (salt flat)
        var isl: Float = 0
        var delta: Float = 0  // river delta flats near a mouth
        var vol: Float = 0    // inside a volcano's cone (0 outside, 1 on the cone proper; Landmarks.swift)
        var lava: Float = 0   // crater lava lake surface (display height), 0 when none
        var flow: Float = 0   // 1 on a lava channel down a volcano's flank
    }

    let seed: UInt64
    let s32: UInt32
    let warpA: Noise, warpB: Noise, contN: Noise, beltN: Noise, actN: Noise, rugN: Noise
    let tempN: Noise, humN: Noise, latN: Noise, hillN: Noise, massN: Noise, mesaN: Noise
    let varN: Noise, mw1: Noise, mw2: Noise, detN: Noise, jitN: Noise, islN: Noise

    static let latPeriod: Float = 9000      // blocks along z for one hot -> cold -> hot cycle
    static let rs = 128                     // river node spacing
    static let accMin: Float = 3            // rain-weighted upstream nodes before a river shows

    private let macroCache: GridCache<Macro>
    private let nodeCache: GridCache<Node>
    private let rbaseCache: GridCache<RBase>
    private let rdownCache: GridCache<Int8>
    private let raccCache: GridCache<Float>
    private let lakeCache: GridCache<Lake>
    private let riverCells: GridCache<RiverSet>
    let volcanoCache = GridCache<Volcano>(bits: 8, empty: Volcano.none)

    init(seed: UInt64) {
        self.seed = seed
        s32 = UInt32(truncatingIfNeeded: seed ^ (seed >> 32)) ^ 0x7E44A1
        func n(_ k: UInt64) -> Noise { Noise(seed: seed &+ 100 &+ k) }
        warpA = n(1); warpB = n(2); contN = n(3); beltN = n(4); actN = n(5); rugN = n(6)
        tempN = n(7); humN = n(8); latN = n(9); hillN = n(10); massN = n(11); mesaN = n(12)
        varN = n(13); mw1 = n(14); mw2 = n(15); detN = n(16); jitN = n(17); islN = n(18)
        macroCache = GridCache(bits: 14, empty: Macro())
        nodeCache = GridCache(bits: 16, empty: Node())
        rbaseCache = GridCache(bits: 15, empty: RBase())
        rdownCache = GridCache(bits: 15, empty: -2)
        raccCache = GridCache(bits: 15, empty: 0)
        lakeCache = GridCache(bits: 12, empty: Lake())
        riverCells = GridCache(bits: 13, empty: RiverSet())
    }

    @inline(__always) static func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = max(0, min(1, (x - e0) / (e1 - e0)))
        return t * t * (3 - 2 * t)
    }
    @inline(__always) static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

    // MARK: Macro fields

    private static let shelf: [(Float, Float)] = [(-1.2, 18), (-0.6, 24), (-0.32, 34), (-0.14, 50), (-0.04, 58), (0.0, 62.5),
                                                   (0.05, 64.5), (0.3, 70), (0.7, 86), (1.2, 104)]

    private static func curve(_ c: Float) -> Float {
        let pts = Terrain.shelf
        if c <= pts[0].0 { return pts[0].1 }
        for i in 1..<pts.count where c <= pts[i].0 {
            let a = pts[i - 1], b = pts[i]
            return a.1 + (b.1 - a.1) * (c - a.0) / (b.0 - a.0)
        }
        return pts[pts.count - 1].1
    }

    // Smooth elevation (continent shape + mountain uplift) at a point: (e, c, u, island).
    func baseE(_ x: Float, _ z: Float) -> (Float, Float, Float, Float) {
        let wx = x + 520 * warpA.fbm2(x / 1700, z / 1700, 3)
        let wz = z + 520 * warpB.fbm2(x / 1700, z / 1700, 3)
        var c = contN.fbm2(wx / 3000, wz / 3000, 6) * 2.2 + 0.1
        // Rare islands rising from the deep ocean (the remote ones become mushroom fields).
        let deepness = Terrain.smooth(-0.42, -0.58, c)
        var isl: Float = 0
        if deepness > 0 {
            isl = Terrain.smooth(0.3, 0.45, islN.fbm2(x / 380, z / 380, 3)) * deepness
            if isl > 0 { c = Terrain.lerp(c, 0.12, isl) }
        }
        // Mountain belts: crests along the zero lines of a warped low-frequency noise, active in places.
        let bx = x + 380 * warpB.fbm2(x / 900 + 31, z / 900, 2)
        let bz = z + 380 * warpA.fbm2(x / 900, z / 900 + 17, 2)
        let bn = abs(beltN.fbm2(bx / 2300, bz / 2300, 3))
        var u: Float = 0
        if bn < 0.24 {
            let b = powf(1 - bn / 0.24, 1.6)
            let act = Terrain.smooth(-0.2, 0.2, actN.fbm2(x / 2600, z / 2600, 2))
            u = b * act * Terrain.smooth(0.0, 0.22, c)
        }
        let e = Terrain.curve(c) + u * 62
        return (e, c, u, isl)
    }

    // Full macro evaluation at a point (climate included).
    func macro(_ x: Float, _ z: Float) -> Macro {
        let (e, c, u, isl) = baseE(x, z)
        var m = Macro(e: e, c: c, u: u, isl: isl)
        m.r = Terrain.smooth(-0.25, 0.45, rugN.fbm2(x / 1300, z / 1300, 3))
        let lz = z + 500 * latN.fbm2(x / 2500, z / 2500, 2)
        let sphi = sinf(2 * Float.pi * lz / Terrain.latPeriod)      // +1 tropics, -1 polar
        let lat01 = (1 - sphi) / 2                                     // 0 equator ... 1 pole
        // Warm through the subtropics, falling off faster toward the poles (like Earth's profile).
        m.ts = 0.64 - 1.08 * powf(lat01, 1.6) + 0.95 * tempN.fbm2(x / 2100, z / 2100, 3)
        var w = 1.05 * humN.fbm2(x / 1500, z / 1500, 3)
        w += 0.36 * cosf(3 * Float.pi * lat01)
        w -= 0.28 * Terrain.smooth(0.3, 1.0, c)
        // Prevailing wind: trade easterlies, mid-latitude westerlies, polar easterlies.
        let windx = -cosf(3 * Float.pi * (lat01 - 1.0 / 6.0))
        let up: Float = windx > 0 ? -1 : 1                              // direction the wind comes from
        let str = abs(windx)
        let here = max(e, 63)
        var shadow: Float = 0, rise: Float = 0
        for d: Float in [70, 170, 320, 520] {
            let (eu, cu, _, _) = baseE(x + up * d, z)
            shadow = max(shadow, eu - here)
            if d == 70 { rise = here - max(eu, 63) }
            if d <= 320 && cu < -0.05 { w += 0.05 }                    // moist air off the sea
        }
        w -= 0.6 * str * Terrain.smooth(8, 70, shadow)
        w += 0.3 * str * Terrain.smooth(4, 40, rise)
        m.w = w
        return m
    }

    private func macroNode(_ gx: Int, _ gz: Int) -> Macro {
        macroCache.get(gx, gz) { macro(Float(gx * 16), Float(gz * 16)) }
    }

    // Macro fields bilinear on the 16-block grid.
    func macroLerp(_ x: Int, _ z: Int) -> Macro {
        let gx = floorDiv(x, 16), gz = floorDiv(z, 16)
        let fx = Float(x - gx * 16) / 16, fz = Float(z - gz * 16) / 16
        let a = macroNode(gx, gz), b = macroNode(gx + 1, gz), c = macroNode(gx, gz + 1), d = macroNode(gx + 1, gz + 1)
        func l(_ p: Float, _ q: Float, _ r: Float, _ s: Float) -> Float {
            let top = p + (q - p) * fx
            let bot = r + (s - r) * fx
            return top + (bot - top) * fz
        }
        return Macro(e: l(a.e, b.e, c.e, d.e), c: l(a.c, b.c, c.c, d.c), u: l(a.u, b.u, c.u, d.u),
                     r: l(a.r, b.r, c.r, d.r), ts: l(a.ts, b.ts, c.ts, d.ts), w: l(a.w, b.w, c.w, d.w), isl: l(a.isl, b.isl, c.isl, d.isl))
    }

    // MARK: Detail

    // Hills, mountain massifs and mesa terraces on top of the smooth base (before erosion and rivers).
    func detail(_ x: Float, _ z: Float, _ m: Macro) -> Float {
        var h = m.e
        // Sea cliffs: on some coasts the land steps up within a few blocks of the shoreline.
        if m.c > -0.02 && m.c < 0.08 {
            let cliff = Terrain.smooth(0.1, 0.35, detN.fbm2(x / 600 + 50, z / 600, 2)) * Terrain.smooth(0.15, -0.1, m.ts + 0.2 * m.w)
            if cliff > 0.001 { h += cliff * 18 * Terrain.smooth(0.0, 0.012, m.c) }
        }
        let hill = hillN.fbm2(x / 320, z / 320, 4)
        h += m.r * (24 * hill + 6) + 3 * detN.fbm2(x / 110, z / 110, 2)
        if m.u > 0.001 {
            let mf = massN.fbm2(x / 800, z / 800, 4) * 2
            let s = Terrain.smooth(-0.6, 0.9, mf)
            h += m.u * (30 + 115 * powf(s, 1.4))
        }
        // Dune fields in hot deserts: long ridges across the (east-west) prevailing wind.
        let sandy = Terrain.smooth(-0.25, -0.5, m.w) * Terrain.smooth(0.35, 0.6, m.ts) * (1 - m.r) * (1 - m.u)
        if sandy > 0.001 {
            let dn = 1 - abs(detN.noise2(x / 34 + 0.4 * z / 90, z / 110 + 900))
            h += sandy * (dn * dn * 14 - 3) * Terrain.smooth(SEA_D + 1, SEA_D + 6, h)
        }
        // Table lands: flat-topped uplands behind steep escarpments (the erosion filter then dissects the edges).
        if m.c > 0.12 && m.w < 0.35 && m.u < 0.4 {
            let pn = mesaN.fbm2(x / 1100 + 500, z / 1100 - 300, 3)
            let pm = Terrain.smooth(0.2, 0.24, pn) * Terrain.smooth(0.12, 0.3, m.c) * Terrain.smooth(0.35, 0.1, m.w) * (1 - m.u * 2.5)
            if pm > 0.001 {
                let top = m.e + 26 + 20 * Terrain.smooth(0.24, 0.5, pn) + 2 * detN.fbm2(x / 90, z / 90, 2)
                h = Terrain.lerp(h, max(h, top), pm)
            }
        }
        // Mesas and buttes in hot, dry country: stepped terraces with steep risers.
        let arid = Terrain.smooth(-0.15, -0.45, m.w) * Terrain.smooth(0.35, 0.6, m.ts)
        if arid > 0.001 {
            let mm = arid * Terrain.smooth(0.0, 0.35, mesaN.fbm2(x / 700, z / 700, 3))
            if mm > 0.001 {
                let lift = 30 * Terrain.smooth(-0.1, 0.4, mesaN.fbm2(x / 260 + 40, z / 260, 2))
                let hh = h + mm * lift
                if hh > 63 {
                    let step: Float = 13
                    let t = (hh - 63) / step
                    let k = floorf(t)
                    let terr = 63 + (k + Terrain.smooth(0.6, 0.8, t - k)) * step
                    h = hh + (terr - hh) * mm
                }
            }
        }
        return h
    }

    // Erosion stripes for one octave: value in [-1, 1] and its gradient (per block).
    @inline(__always) private func gully(_ x: Float, _ z: Float, _ gx: Float, _ gz: Float, _ wavelength: Float, _ oct: Int) -> (Float, Float, Float) {
        let f = 1 / wavelength
        let px = x * f, pz = z * f
        let ix = floorf(px), iz = floorf(pz)
        let fx = px - ix, fz = pz - iz
        let gl = (gx * gx + gz * gz).squareRoot() + 1e-6
        let dx = -gz / gl, dz = gx / gl            // across the slope: the stripes run downhill
        var va: Float = 0, vx: Float = 0, vz: Float = 0, wt: Float = 0
        let cxi = Int(ix), czi = Int(iz)
        let tau = 2 * Float.pi
        for oj in -1...2 {
            for oi in -1...2 {
                let hj = hash3(cxi + oi, oct, czi + oj, s32 ^ 0x6011)
                let jx = Float(hj & 0xFFFF) / 65536
                let jz = Float(hj >> 16) / 65536
                let ppx = fx - Float(oi) - jx
                let ppz = fz - Float(oj) - jz
                let d2 = ppx * ppx + ppz * ppz
                let wgt = expf(-2 * d2)
                let ph = (ppx * dx + ppz * dz) * tau
                va += cosf(ph) * wgt
                let s = -sinf(ph) * wgt * tau * f
                vx += s * dx
                vz += s * dz
                wt += wgt
            }
        }
        return (va / wt, vx / wt, vz / wt)
    }

    // MARK: Lattice nodes

    func node(_ gx: Int, _ gz: Int) -> Node {
        nodeCache.get(gx, gz) { computeNode(gx * 4, gz * 4) }
    }

    private func computeNode(_ x: Int, _ z: Int) -> Node {
        let m = macroLerp(x, z)
        let fx = Float(x), fz = Float(z)
        let pre = detail(fx, fz, m)
        let p1 = detail(fx + 3, fz, m), p2 = detail(fx, fz + 3, m)
        let gx = (p1 - pre) / 3, gz = (p2 - pre) / 3
        let slope = (gx * gx + gz * gz).squareRoot()
        var h = pre
        let strength = Terrain.smooth(0.03, 0.4, slope) * (0.15 + 0.85 * max(m.u, m.r * 0.5)) * Terrain.smooth(SEA_D - 4, SEA_D + 10, pre)
        if strength > 0.001 {
            var ax = gx, az = gz
            var amp: Float = 36, wl: Float = 340
            for o in 0..<4 {
                let (v, vx, vz) = gully(fx, fz, ax, az, wl, o)
                h += v * amp * strength
                ax += vx * amp * strength
                az += vz * amp * strength
                amp *= 0.5; wl *= 0.5
            }
        }
        var n = Node(h: h, wl: SEA_D, rv: 99, ts: m.ts, w: m.w, c: m.c, u: m.u, r: m.r, slope: slope)
        n.isl = m.isl
        n.v = varN.fbm2(fx / 500, fz / 500, 2) * 2.2
        n.jt = 0.1 * jitN.fbm2(fx / 40, fz / 40, 2)
        n.jw = 0.12 * jitN.fbm2(fx / 40 + 71, fz / 40 - 13, 2)
        carveWater(&n, fx, fz, m)
        applyVolcanoes(&n, fx, fz)
        return n
    }

    // Column fields: bilinear between the four lattice nodes; the water level is the highest corner's (rivers
    // and lakes flag the nodes around them, so whole channels share one level).
    struct Column {
        var h: Float, wl: Float, rv: Float, ts: Float, w: Float, c: Float, u: Float, r: Float, slope: Float, v: Float, jt: Float, jw: Float, dry: Float, isl: Float, delta: Float
        var vol: Float = 0, lava: Float = 0, flow: Float = 0
    }

    static func blend(_ a: Node, _ b: Node, _ c: Node, _ d: Node, _ fx: Float, _ fz: Float) -> Column {
        func l(_ p: Float, _ q: Float, _ r: Float, _ s: Float) -> Float {
            let top = p + (q - p) * fx
            let bot = r + (s - r) * fx
            return top + (bot - top) * fz
        }
        return Column(h: l(a.h, b.h, c.h, d.h), wl: max(max(a.wl, b.wl), max(c.wl, d.wl)), rv: l(a.rv, b.rv, c.rv, d.rv),
                      ts: l(a.ts, b.ts, c.ts, d.ts), w: l(a.w, b.w, c.w, d.w), c: l(a.c, b.c, c.c, d.c), u: l(a.u, b.u, c.u, d.u),
                      r: l(a.r, b.r, c.r, d.r), slope: l(a.slope, b.slope, c.slope, d.slope), v: l(a.v, b.v, c.v, d.v),
                      jt: l(a.jt, b.jt, c.jt, d.jt), jw: l(a.jw, b.jw, c.jw, d.jw), dry: l(a.dry, b.dry, c.dry, d.dry), isl: l(a.isl, b.isl, c.isl, d.isl), delta: l(a.delta, b.delta, c.delta, d.delta),
                      vol: l(a.vol, b.vol, c.vol, d.vol), lava: max(max(a.lava, b.lava), max(c.lava, d.lava)), flow: l(a.flow, b.flow, c.flow, d.flow))
    }

    func column(_ x: Int, _ z: Int) -> Column {
        let gx = floorDiv(x, 4), gz = floorDiv(z, 4)
        return Terrain.blend(node(gx, gz), node(gx + 1, gz), node(gx, gz + 1), node(gx + 1, gz + 1),
                             Float(x - gx * 4) / 4, Float(z - gz * 4) / 4)
    }

    // MARK: Rivers and lakes

    struct RBase { var x: Float = 0, z: Float = 0, p: Float = 0, rain: Float = 0, ocean: Bool = true }
    struct Lake { var valid = false, x: Float = 0, z: Float = 0, ll: Float = 0, r2: Float = 0, r: Float = 0, dry = false }
    struct Seg { var ax: Float, az: Float, bx: Float, bz: Float, la: Float, lb: Float, hw: Float, depth: Float, mouth: Bool, dry: Bool = false }
    final class RiverSet { var segs: [Seg] = []; var lakes: [Lake] = [] }

    private static let dirs: [(Int, Int)] = [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)]

    func rbase(_ i: Int, _ j: Int) -> RBase {
        rbaseCache.get(i, j) {
            let h = hash3(i, 0x5151, j, s32 ^ 0xA11)
            let rs = Float(Terrain.rs)
            let px = Float(i) * rs + rs * (0.15 + 0.7 * Float(h & 0xFFFF) / 65536)
            let pz = Float(j) * rs + rs * (0.15 + 0.7 * Float(h >> 16) / 65536)
            let m = macro(px, pz)
            return RBase(x: px, z: pz, p: m.e, rain: max(0.12, min(1.5, 0.55 + m.w)), ocean: m.e < SEA_D - 1)
        }
    }

    // Steepest-descent neighbour (index into dirs), -1 for a sink (sea or lake basin).
    func rdown(_ i: Int, _ j: Int) -> Int {
        Int(rdownCache.get(i, j) {
            let n = rbase(i, j)
            if n.ocean { return -1 }
            var best: Int8 = -1
            var bs: Float = 0
            for (k, d) in Terrain.dirs.enumerated() {
                let m = rbase(i + d.0, j + d.1)
                let dx = m.x - n.x, dz = m.z - n.z
                let s = (n.p - m.p) / (dx * dx + dz * dz).squareRoot()
                if s > bs { bs = s; best = Int8(k) }
            }
            return best
        })
    }

    // Rain-weighted number of nodes draining through (i, j), counted within 12 nodes.
    func racc(_ i: Int, _ j: Int) -> Float {
        raccCache.get(i, j) {
            let R = 12
            var total: Float = 0
            var stack: [(Int, Int)] = [(i, j)]
            while let cur = stack.popLast() {
                let ci = cur.0, cj = cur.1
                total += rbase(ci, cj).rain
                for (k, d) in Terrain.dirs.enumerated() {
                    let mi = ci + d.0, mj = cj + d.1
                    if abs(mi - i) > R || abs(mj - j) > R { continue }
                    if rbase(mi, mj).ocean { continue }
                    // m drains into c when its own steepest direction is the opposite of d.
                    if rdown(mi, mj) == 7 - k { stack.append((mi, mj)) }
                }
            }
            return total
        }
    }

    // River surface level at a node (lakes hold their spill level).
    func rlevel(_ i: Int, _ j: Int) -> Float {
        let n = rbase(i, j)
        if n.ocean { return SEA_D }
        if rdown(i, j) < 0 { let lk = lake(i, j); if lk.valid { return lk.ll } }
        return max(SEA_D, n.p - 1)
    }

    // Lake in a basin node: filled to just below the lowest point of a ring around it.
    func lake(_ i: Int, _ j: Int) -> Lake {
        lakeCache.get(i, j) {
            let n = rbase(i, j)
            let a = racc(i, j)
            guard !n.ocean && a >= 2 else { return Lake() }
            let r2 = min(130, 22 + 11 * a.squareRoot())
            var ring: Float = 1e9
            for k in 0..<24 {
                let ang = Float(k) * 2 * Float.pi / 24
                let rx = n.x + cosf(ang) * r2, rz = n.z + sinf(ang) * r2
                ring = min(ring, detail(rx, rz, macro(rx, rz)))
            }
            // Never above the rivers that feed it: every neighbour is higher than the basin node.
            var rim: Float = 1e9
            for d in Terrain.dirs { rim = min(rim, rbase(i + d.0, j + d.1).p - 1) }
            let ll = min(rim, max(n.p - 6, min(n.p + 12, ring - 1)))
            guard ll > SEA_D + 1.5 else { return Lake() }       // a basin at sea level is just low ground
            return Lake(valid: true, x: n.x, z: n.z, ll: ll, r2: r2, r: r2 * 0.45, dry: n.rain < 0.25)
        }
    }

    // Segments and lakes that can reach river cell (ci, cj).
    private func riverSet(_ ci: Int, _ cj: Int) -> RiverSet {
        riverCells.get(ci, cj) {
            let set = RiverSet()
            for j in (cj - 3)...(cj + 3) {
                for i in (ci - 3)...(ci + 3) {
                    let n = rbase(i, j)
                    if n.ocean { continue }
                    let a = racc(i, j)
                    let d = rdown(i, j)
                    if d < 0 {
                        if abs(i - ci) <= 2 && abs(j - cj) <= 2 { let lk = lake(i, j); if lk.valid { set.lakes.append(lk) } }
                        continue
                    }
                    let di = i + Terrain.dirs[d].0, dj = j + Terrain.dirs[d].1
                    let m = rbase(di, dj)
                    if a < Terrain.accMin {
                        // Dry washes: in arid country small drainage lines cut narrow canyons without water.
                        if a >= 1.1 && n.rain < 0.4 && !m.ocean {
                            set.segs.append(Seg(ax: n.x, az: n.z, bx: m.x, bz: m.z, la: n.p - 1, lb: m.p - 1, hw: 1.5, depth: 0, mouth: false, dry: true))
                        }
                        continue
                    }
                    let hw = 1.8 + 1.5 * (a - Terrain.accMin + 1).squareRoot()
                    set.segs.append(Seg(ax: n.x, az: n.z, bx: m.x, bz: m.z, la: rlevel(i, j), lb: rlevel(di, dj),
                                        hw: hw, depth: min(7, 1.6 + hw * 0.4), mouth: m.ocean))
                }
            }
            return set
        }
    }

    // Harness: nearest lake (non-dry basin) or river mouth with a delta, as a world position (x, z).
    func nearestFeature(_ kind: String, x: Int, z: Int) -> (Int, Int)? {
        if kind == "volcano" {
            guard let v = nearestVolcano(Float(x), Float(z), cells: 8) else { return nil }
            return (Int(v.x), Int(v.z))
        }
        let ci = floorDiv(x, Terrain.rs), cj = floorDiv(z, Terrain.rs)
        // Deltas need a coast: search farther (continents are thousands of blocks wide) for any sizeable river mouth.
        let maxR = kind == "delta" ? 72 : 40
        for r in 0..<maxR {
            for j in (cj - r)...(cj + r) { for i in (ci - r)...(ci + r) where max(abs(i - ci), abs(j - cj)) == r {
                let n = rbase(i, j)
                if n.ocean { continue }
                let d = rdown(i, j)
                if kind == "lake" && d < 0 { let lk = lake(i, j); if lk.valid && !lk.dry && lk.r2 > 40 { return (Int(lk.x), Int(lk.z)) } }
                if kind == "delta" && d >= 0 && racc(i, j) > 14.5 {         // half-width > 7: the delta fan threshold
                    let m = rbase(i + Terrain.dirs[d].0, j + Terrain.dirs[d].1)
                    if m.ocean { return (Int((n.x + m.x) / 2), Int((n.z + m.z) / 2)) }
                }
            } }
        }
        return nil
    }

    // Audit for CI: river segments in a rectangle of river cells whose water surface would rise downstream.
    func riverAudit(_ i0: Int, _ j0: Int, _ i1: Int, _ j1: Int) -> (segments: Int, uphill: Int, lakes: Int) {
        var segs = 0, up = 0, lakes = 0
        for j in j0...j1 { for i in i0...i1 {
            let n = rbase(i, j)
            if n.ocean { continue }
            let d = rdown(i, j)
            if d < 0 { if lake(i, j).valid { lakes += 1 }; continue }
            if racc(i, j) < Terrain.accMin { continue }
            segs += 1
            if rlevel(i + Terrain.dirs[d].0, j + Terrain.dirs[d].1) > rlevel(i, j) + 0.01 { up += 1 }
        } }
        return (segs, up, lakes)
    }

    // Cuts valleys, channels and lake basins into a node and records its water level.
    private func carveWater(_ n: inout Node, _ x: Float, _ z: Float, _ m: Macro) {
        let e = m.e
        let set = riverSet(Int(floorf(x / Float(Terrain.rs))), Int(floorf(z / Float(Terrain.rs))))
        if set.segs.isEmpty && set.lakes.isEmpty { return }
        let raw = n.h
        var h = raw
        // Meanders: warp the query point instead of bending the segments.
        let qx = x + 26 * mw1.fbm2(x / 110, z / 110, 2) + 50 * mw1.fbm2(x / 420 + 9, z / 420, 2)
        let qz = z + 26 * mw2.fbm2(x / 110, z / 110, 2) + 50 * mw2.fbm2(x / 420, z / 420 + 9, 2)
        var rv: Float = 99, bestL = SEA_D
        var delta: Float = 0, deltaCh = false
        let fjord = Terrain.smooth(-0.05, -0.35, m.ts) * Terrain.smooth(0.1, 0.35, m.u + 0.3 * m.r) * Terrain.smooth(0.5, 0.1, m.c)
        for s in set.segs {
            let dx = s.bx - s.ax, dz = s.bz - s.az
            let l2 = dx * dx + dz * dz
            let t = max(0, min(1, ((qx - s.ax) * dx + (qz - s.az) * dz) / l2))
            let px = s.ax + dx * t, pz = s.az + dz * t
            let ex = qx - px, ez = qz - pz
            let dn = (ex * ex + ez * ez).squareRoot()
            let hw = s.mouth ? s.hw * (1 + 1.2 * t * t) : s.hw
            if dn > hw + 220 { continue }
            let lv = Terrain.lerp(s.la, s.lb, t)
            if s.dry {
                if dn < 40 {
                    let floorY = max(SEA_D + 2, min(lv, e - 1))
                    h = min(h, floorY + max(0, dn - 1.5) * 2.4)
                }
                continue
            }
            var L = max(SEA_D, min(lv, e - 1))
            // The last few blocks above the sea run at sea level: a wide lowland river stepped down one block wherever
            // its level crossed a whole number, a stack of long straight water walls across the estuary (blind critic,
            // run 364 lake shot).
            if L < SEA_D + 3 { L = SEA_D }
            var slope = 0.22 + 0.75 * Terrain.smooth(8, 90, max(0, raw - L))
            var depth = s.depth
            var hwv = hw
            // Fjords: on cold mountain coasts the lower valley is a glacial trough drowned by the sea.
            if fjord > 0.01 {
                let low = Terrain.smooth(110, SEA_D, lv)
                L -= fjord * low * 30
                slope += fjord * 1.3
                hwv += fjord * low * 16
                depth += fjord * low * 4
            }
            // Canyons: through dry country rivers cut steep walls and keep no floodplain.
            let arid = Terrain.smooth(-0.15, -0.5, m.w)
            slope += arid * 1.5
            let relief = max(0, raw - L)
            let fp = (hwv * 1.6 * (1 - Terrain.smooth(10, 50, relief)) + 2) * (1 - 0.8 * arid)
            let target = L + 1 + max(0, dn - hwv - fp) * slope
            h = min(h, target)
            if dn < hwv {
                let q = dn / hwv
                let bed = L - depth * max(0, 1 - q * q).squareRoot()
                h = min(h, bed)
            }
            // Deltas: big lowland rivers fan out into flats cut by distributary channels near the mouth.
            if s.mouth && s.hw > 7 && t > 0.35 && raw < SEA_D + 6 && fjord < 0.3 {
                let fan = Terrain.smooth(hwv + 90 * t, hwv, dn) * Terrain.smooth(0.35, 0.7, t)
                if fan > 0.01 {
                    h = min(h, Terrain.lerp(h, SEA_D + 1, fan))
                    delta = max(delta, fan)
                    let ch = abs(detN.fbm2(x / 45 + 300, z / 45, 2))
                    if ch < 0.05 * fan { h = min(h, SEA_D - 1.5); deltaCh = true }
                }
            }
            let r = dn / hwv
            if r < rv { rv = r; bestL = L }
        }
        var lakeL: Float = -1
        var dry: Float = 0
        if !set.lakes.isEmpty {
            let warp = 1 + 0.22 * detN.fbm2(x / 70, z / 70, 2)
            for lk in set.lakes {
                let ex = qx - lk.x, ez = qz - lk.z
                let dn = (ex * ex + ez * ez).squareRoot() * warp
                if dn > lk.r2 + 4 { continue }
                if dn < lk.r {
                    let q = dn / lk.r
                    h = min(h, lk.ll - (2 + 8 * (1 - q * q)))
                }
                if dn > lk.r2 - 6 && h < lk.ll + 1 { h = lk.ll + 1 }          // close gaps in the rim
                if dn < lk.r2 && h < lk.ll {
                    if lk.dry { dry = 1; h = max(h, lk.ll - 1) } else { lakeL = max(lakeL, lk.ll) }
                }
            }
        }
        // Banks and levees for the nearest channel (never built out into the sea).
        if rv >= 1 && rv < 1.8 && raw >= SEA_D - 1 { h = max(h, bestL + 1) }
        n.h = h
        n.dry = dry
        n.delta = delta
        if deltaCh && rv > 0.9 { rv = 0.9 }
        if rv < 2 { n.wl = max(bestL, SEA_D) }
        if lakeL > 0 { n.wl = max(n.wl, lakeL); if rv > 1 { rv = 0.5 } }
        n.rv = rv
    }

    // MARK: Biomes

    @inline(__always) static func lapse(_ ts: Float, _ h: Float) -> Float { ts - max(0, h - 64) * (0.95 / 175) }

    // Temperature at a column's surface (altitude lapse + ecotone jitter).
    @inline(__always) func temperature(_ c: Column, _ h: Float) -> Float { Terrain.lapse(c.ts, h) + c.jt }

    // Biome from local climate and landform. dT/dW shift the climate (tree palettes and colour blending).
    func biome(_ k: Column, _ h: Float, dT: Float = 0, dW: Float = 0) -> Biome {
        let t = Terrain.lapse(k.ts, h) + k.jt + dT
        let ts = k.ts + k.jt + dT
        let w = k.w + k.jw + dW
        let v = k.v
        // Water.
        if h < SEA_D - 0.5 && k.wl <= SEA_D + 0.01 {
            let ts = k.ts + 0.3 * k.jt + dT
            let deep = h < SEA_D - 26
            if ts < -0.45 { return deep ? .deepFrozenOcean : .frozenOcean }
            if ts < -0.12 { return deep ? .deepColdOcean : .coldOcean }
            if ts < 0.3 { return deep ? .deepOcean : .ocean }
            if ts < 0.58 { return deep ? .deepLukewarmOcean : .lukewarmOcean }
            return deep ? .deepLukewarmOcean : .warmOcean
        }
        if k.rv < 1 && h < k.wl - 0.5 { return t < -0.45 ? .frozenRiver : .river }
        // Remote islands out in the deep ocean.
        if k.isl > 0.12 && t > -0.2 { return .mushroomFields }
        // A volcano's cone: bare rock (its surface is basalt and tuff, WorldGen.surface), no trees or grass.
        if k.vol > 0.5 { return .stonyPeaks }
        let high = h - SEA_D
        // Shores.
        if k.c < 0.014 && h < SEA_D + 3 && k.u < 0.25 {
            if k.slope > 0.6 { return .stonyShore }                     // rocky coasts (was 0.9: never seen)
            if t < -0.4 { return .snowyBeach }
            if ts > 0.55 && w < -0.35 { return .desert }
            return .beach
        }
        if k.dry > 0.5 { return ts > 0.4 ? .desert : .plains }
        if k.delta > 0.4 && high < 4 && w > -0.15 { return t > 0.4 ? .mangroveSwamp : (t > -0.1 ? .swamp : .plains) }
        // Frozen: tundra, snowy forest, glaciated peaks. (Thresholds lowered a little: snow covered ~25% of land.)
        if t < -0.56 {
            if high > 75 && (k.slope > 0.55 || k.u > 0.45) {
                if k.slope > 0.9 || k.u > 0.6 { return v > 0 ? .jaggedPeaks : .frozenPeaks }
                return .snowySlopes
            }
            if high > 50 && w > -0.1 { return .grove }
            if w < -0.2 { return (w < -0.4 && v > 0.45 && t < -0.65) ? .iceSpikes : .snowyPlains }
            return .snowyTaiga
        }
        if t < -0.31 {
            if high > 80 && (k.slope > 0.7 || k.u > 0.5) { return .snowySlopes }
            if high > 45 && w > -0.05 { return .grove }
            if w < -0.3 { return .snowyPlains }
            return .snowyTaiga
        }
        // Bare rock above the treeline where it is too warm or dry for snow cover.
        if high > 100 && k.u > 0.4 && k.slope > 0.5 { return .stonyPeaks }
        // Boreal.
        if t < 0.02 {
            if high > 28 && k.r > 0.42 && k.slope > 0.25 {
                if w < -0.25 { return .windsweptGravellyHills }
                return w > 0.2 ? .windsweptForest : .windsweptHills
            }
            if high > 60 && w > -0.25 && w < 0.25 && k.slope < 0.5 { return .meadow }
            if w > 0.4 { return v > 0.1 ? .oldGrowthPineTaiga : .oldGrowthSpruceTaiga }
            if w < -0.35 { return .plains }
            return .taiga
        }
        // Temperate.
        if t < 0.32 {
            if high > 32 && k.r > 0.45 && k.slope > 0.3 { return w > 0.1 ? .windsweptForest : .windsweptHills }
            if high > 55 && w > -0.1 && w < 0.35 && k.slope < 0.5 { return v > 0.35 ? .cherryGrove : .meadow }
            if w > 0.38 && high < 6 && k.slope < 0.25 { return .swamp }
            if w < -0.3 { return v > 0.55 ? .sunflowerPlains : .plains }
            if w < 0 { return v > 0.45 ? .flowerForest : (v < -0.2 ? .plains : .forest) }
            if w < 0.35 {
                if v > 0.35 { return v > 0.62 ? .oldGrowthBirchForest : .birchForest }
                return .forest
            }
            return v > 0.45 ? .paleGarden : .darkForest
        }
        // Warm.
        if t < 0.58 {
            if w > 0.32 && high < 5 && k.slope < 0.25 { return t > 0.45 ? .mangroveSwamp : .swamp }
            // Dry threshold as in the hot band (-0.36 here turned every hill terrace of a desert edge to savanna grass
            // as the temperature lapsed with height: eyes-on biome_desert, run 372).
            if w < -0.32 { return high > 25 && w < -0.42 && t > 0.48 ? .badlands : .desert }
            if w < -0.12 {
                if high > 50 && k.slope < 0.35 { return .savannaPlateau }
                return k.r > 0.5 && k.slope > 0.35 ? .windsweptSavanna : .savanna
            }
            if w < 0.2 { return v < 0 ? .plains : .forest }
            if w < 0.38 { return .sparseJungle }
            return .jungle
        }
        // Hot.
        if w > 0.3 && high < 5 && k.slope < 0.25 { return .mangroveSwamp }
        if w < -0.32 {
            let rough = k.r + (w < -0.4 ? 0.4 : 0) + k.slope
            // Mesas: hilly dry country, and whole regions where the variety noise is high (badlands were 8 % of the hot
            // dry country in scattered patches, so no view showed a mesa landscape: blind critic, run 373 tour_mesa).
            if (high > 8 && rough > 0.3) || (high > 3 && v > 0.25) {
                if high > 38 && w > -0.5 { return .woodedBadlands }
                return v > 0.6 ? .erodedBadlands : .badlands
            }
            return .desert
        }
        if w < -0.05 {
            if high > 50 && k.slope < 0.35 { return .savannaPlateau }
            return k.r > 0.5 && k.slope > 0.35 ? .windsweptSavanna : .savanna
        }
        if w < 0.12 { return .sparseJungle }
        return v > 0.5 ? .bambooJungle : .jungle
    }

    // Climate classes for the neighbour check: 0 frozen ... 4 hot, and a moisture class 0 arid ... 2 wet.
    static func tempClass(_ b: Biome) -> Int {
        switch b {
        case .snowyPlains, .iceSpikes, .snowyTaiga, .grove, .snowySlopes, .frozenPeaks, .jaggedPeaks, .snowyBeach, .frozenRiver,
             .frozenOcean, .deepFrozenOcean: return 0
        case .taiga, .oldGrowthPineTaiga, .oldGrowthSpruceTaiga, .coldOcean, .deepColdOcean: return 1
        case .desert, .badlands, .erodedBadlands, .woodedBadlands, .jungle, .bambooJungle, .warmOcean: return 4
        case .savanna, .savannaPlateau, .windsweptSavanna, .sparseJungle, .mangroveSwamp, .lukewarmOcean, .deepLukewarmOcean: return 3
        default: return 2
        }
    }
    static func wetClass(_ b: Biome) -> Int {
        switch b {
        case .desert, .badlands, .erodedBadlands, .woodedBadlands: return 0
        case .jungle, .bambooJungle, .sparseJungle, .swamp, .mangroveSwamp, .darkForest, .paleGarden: return 2
        default: return 1
        }
    }
    // True when two biomes should never touch.
    static func implausible(_ a: Biome, _ b: Biome) -> Bool {
        if a == b { return false }
        if abs(tempClass(a) - tempClass(b)) >= 3 { return true }
        if abs(wetClass(a) - wetClass(b)) >= 2 && !a.isRiver && !b.isRiver && !a.isOcean && !b.isOcean { return true }
        let mush = a == .mushroomFields ? b : (b == .mushroomFields ? a : nil)
        if let o = mush, !o.isOcean && !o.isBeach && o != .mushroomFields { return true }
        return false
    }
}
