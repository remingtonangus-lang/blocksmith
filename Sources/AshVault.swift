import Foundation
import simd

// The Ash Vault's towns, rail lines and airfield (the gap pass, docs/status/the-deep-expansion.md "Gap pass" D2):
//   Towns     four garrison towns where the axis roads cross the 390 ring: a gate with the town's sign, barracks, a
//             mess hall, a radio room with its mast, family quarters, a depot, a signal tower, a mortar pit and a
//             station at the end of the line.
//   Rail      a line on an embankment (or through a cutting) beside each axis road from a halt outside the citadel's
//             gates to each town, and one more to the airfield; powered rails every 20 blocks keep a cart rolling;
//             halts with a platform, roof, lamps, a sign naming the line and a cart waiting.
//   Airfield  a runway with edge lamps, two hangars with bombers built of blocks, a third bomber on the apron, a
//             control tower, fuel tanks, anti-aircraft pits, a barracks and a mortar pit.
// Ground a save had generated before (structure-guard-vault.txt) keeps what it had: a town or the airfield touching it
// is left out whole, and a line stops at its edge.
extension AshWar {
    static let townNames = ["Cinderhold", "Slagford", "Emberwatch", "Last Lamp"]
    static let townSites: [AshSite] = [AshSite(kind: "town", x: 0, z: -390, r: 36, face: 0),
                                       AshSite(kind: "town", x: 390, z: 0, r: 36, face: 90),
                                       AshSite(kind: "town", x: 0, z: 390, r: 36, face: 180),
                                       AshSite(kind: "town", x: -390, z: 0, r: 36, face: 270)]
    static let airfield = AshSite(kind: "airfield", x: -340, z: -340, r: 60, face: 0)
    static let airfieldName = "Airfield One"
    static func townName(_ s: AshSite) -> String {
        townNames[townSites.firstIndex { $0.x == s.x && $0.z == s.z } ?? 0]
    }

    // MARK: Rail

    // A straight run of track: along x at z = fixed, or along z at x = fixed, from a to b (inclusive).
    struct RailRun { let alongX: Bool; let fixed: Int; let a: Int; let b: Int }
    static let railRuns: [RailRun] = [
        RailRun(alongX: false, fixed: 6, a: -410, b: -50),       // north, to Cinderhold
        RailRun(alongX: true, fixed: -6, a: 50, b: 410),         // east, to Slagford
        RailRun(alongX: false, fixed: -6, a: 50, b: 410),        // south, to Emberwatch
        RailRun(alongX: true, fixed: 6, a: -410, b: -50),        // west, to Last Lamp
        RailRun(alongX: true, fixed: -6, a: -334, b: -50),       // west, then north to the airfield
        RailRun(alongX: false, fixed: -334, a: -300, b: -7),
    ]
    static let railCorner = IVec3(-334, 0, -6)                    // the airfield line's curve (north-east)
    // A halt: `len` cells of run `run` from `from` in direction `dir`, the platform on `side` of the track.
    struct Halt { let run: Int; let from: Int; let dir: Int; let side: Int; let name: String; let to: String }
    static let halts: [Halt] = [
        Halt(run: 0, from: -50, dir: -1, side: 1, name: "Citadel Halt", to: townNames[0]),
        Halt(run: 0, from: -396, dir: -1, side: 1, name: townNames[0], to: "the Citadel"),
        Halt(run: 1, from: 50, dir: 1, side: -1, name: "Citadel Halt", to: townNames[1]),
        Halt(run: 1, from: 396, dir: 1, side: -1, name: townNames[1], to: "the Citadel"),
        Halt(run: 2, from: 50, dir: 1, side: -1, name: "Citadel Halt", to: townNames[2]),
        Halt(run: 2, from: 396, dir: 1, side: -1, name: townNames[2], to: "the Citadel"),
        Halt(run: 3, from: -50, dir: -1, side: 1, name: "Citadel Halt", to: townNames[3]),
        Halt(run: 3, from: -396, dir: -1, side: 1, name: townNames[3], to: "the Citadel"),
        Halt(run: 4, from: -50, dir: -1, side: -1, name: "Citadel Halt", to: airfieldName),
        Halt(run: 5, from: -286, dir: -1, side: -1, name: airfieldName, to: "the Citadel"),
    ]
    static let haltLength = 14

    static func cell(_ r: RailRun, _ t: Int) -> (x: Int, z: Int) { r.alongX ? (t, r.fixed) : (r.fixed, t) }

    // The rail shape at a column (Rails.swift shapes), nil off the lines.
    static func railShape(_ x: Int, _ z: Int) -> Int? {
        if x == railCorner.x && z == railCorner.z { return 9 }
        for r in railRuns {
            if r.alongX { if z == r.fixed && x >= r.a && x <= r.b { return 1 } }
            else if x == r.fixed && z >= r.a && z <= r.b { return 0 }
        }
        return nil
    }

    static func railDistance(_ x: Int, _ z: Int) -> Float {
        var best = Float.greatestFiniteMagnitude
        for r in railRuns {
            let (along, across) = r.alongX ? (x, z) : (z, x)
            let da = max(0, max(r.a - along, along - r.b))
            best = min(best, sqrtf(Float(da * da + (across - r.fixed) * (across - r.fixed))))
        }
        return best
    }

    // Inside a site's footprint (the rail only lays its track there; the site's own plan keeps the way clear).
    static func inSite(_ x: Int, _ z: Int) -> Bool {
        sites.contains { abs(x - $0.x) <= $0.r && abs(z - $0.z) <= $0.r }
    }

    static func railStarts(guardSet: DeepGuard) -> [StructureStart] {
        railRuns.indices.map { i in
            let r = railRuns[i]
            var pieces: [Piece] = []
            var a = r.a
            while a <= r.b {
                let b = min(r.b, a + 31)
                let (p, q) = (cell(r, a), cell(r, b))
                let seg = (a, b)
                pieces.append(Piece(min: IVec3(min(p.x, q.x) - 5, ground - 14, min(p.z, q.z) - 5),
                                    max: IVec3(max(p.x, q.x) + 5, ground + 8, max(p.z, q.z) + 5)) { w in
                    AshWar.layRail(&w, i, seg.0, seg.1, guardSet)
                })
                a = b + 1
            }
            let mid = cell(r, (r.a + r.b) / 2)
            return StructureStart(kind: "ash_rail", pieces: pieces, anchor: IVec3(mid.x, ground + 1, mid.z))
        }
    }

    static func layRail(_ w: inout StructWriter, _ ri: Int, _ a: Int, _ b: Int, _ guardSet: DeepGuard) {
        let r = railRuns[ri]
        let k = AshKit()
        let y0 = ground
        let rail = Blocks.id("rail"), powered = Blocks.id("powered_rail"), battery = Blocks.id("redstone_block")
        let gravel = Blocks.id("gravel")
        for t in a...b {
            let (cx, cz) = cell(r, t)
            for d in -3...3 {
                let x = r.alongX ? cx : cx + d, z = r.alongX ? cz + d : cz
                guard w.inside(x, y0, z), guardSet.clear(floorDiv(x, CS), floorDiv(z, CS), 0) else { continue }
                if inSite(x, z) {
                    guard d == 0 else { continue }
                    if !Blocks.collide[Int(w.get(x, y0, z))] { w.set(x, y0, z, k.floor) }
                    w.set(x, y0 + 2, z, AIR)
                } else {
                    // A cutting through rock and an embankment over dips: a gravel bed with basalt shoulders.
                    if abs(d) <= 2 { w.fill(x, y0 + 1, z, x, y0 + 6, z, AIR) }
                    if abs(d) <= 2 {
                        // (P504: a three-wide gravel bed, so the line is drawn as main-line track, ShapeRails.mainline)
                        w.set(x, y0, z, abs(d) <= 1 ? gravel : k.basalt)
                        var y = y0 - 1
                        while y > y0 - 14 && !Blocks.collide[Int(w.get(x, y, z))] { w.set(x, y, z, k.basalt); y -= 1 }
                    }
                }
                guard d == 0 else { continue }
                let shape = railShape(x, z) ?? (r.alongX ? 1 : 0)
                if t % 20 == 0 && shape < 6 {
                    w.set(x, y0, z, battery)
                    w.set(x, y0 + 1, z, powered + BlockID(shape + 6))
                } else {
                    w.set(x, y0 + 1, z, rail + BlockID(shape))
                }
            }
        }
        // Buffer stops at the line ends (not where the airfield line turns the corner): a carriage rolls up and stops.
        for (e, open) in [(r.a, ri == 4), (r.b, ri == 5)] where !open && e >= a && e <= b {
            let (x, z) = cell(r, e)
            guard w.inside(x, y0, z) else { continue }
            w.set(x, y0, z, k.concrete); w.set(x, y0 + 1, z, k.concrete); w.set(x, y0 + 2, z, k.lamp)
        }
        // Halts on this stretch.
        for h in halts where h.run == ri {
            let first = h.from, last = h.from + h.dir * (haltLength - 1)
            let lo = min(first, last), hi = max(first, last)
            guard hi >= a && lo <= b else { continue }
            for t in max(lo, a)...min(hi, b) {
                let (cx, cz) = cell(r, t)
                guard guardSet.clear(floorDiv(cx, CS), floorDiv(cz, CS), 0) else { continue }
                func at(_ off: Int) -> (Int, Int) { r.alongX ? (cx, cz + off * h.side) : (cx + off * h.side, cz) }
                for off in 2...4 { let (x, z) = at(off); w.set(x, y0, z, k.floor); w.set(x, y0 + 1, z, k.floor) }
                for off in 0...4 { let (x, z) = at(off); w.set(x, y0 + 5, z, k.plating); for y in (y0 + 2)...(y0 + 4) where off >= 2 { w.set(x, y, z, AIR) } }
                let mid = h.from + h.dir * (haltLength / 2)
                if t == first || t == last || t == mid {
                    let (x, z) = at(4)
                    w.fill(x, y0 + 2, z, x, y0 + 4, z, k.plating)
                    let (lx, lz) = at(2)
                    w.set(lx, y0 + 5, lz, k.lamp)
                }
                if t == mid {
                    let (x, z) = at(0)
                    w.mob(r.alongX ? "minecart^90" : "minecart", V3(Float(x) + 0.5, Float(y0 + 1), Float(z) + 0.5))   // (P504: along the track)
                }
                if t == first + h.dir {
                    // The halt's board, facing up the line toward anyone arriving.
                    let (x, z) = at(3)
                    let fdx = r.alongX ? -h.dir : 0, fdz = r.alongX ? 0 : -h.dir
                    sign(&w, x, y0 + 2, z, facing: (fdx, fdz), ["Ashguard Rail", h.name, "Line to", h.to])
                }
            }
        }
    }

    // A standing sign with its lines, facing (dx, dz).
    static func sign(_ w: inout StructWriter, _ x: Int, _ y: Int, _ z: Int, facing: (Int, Int), _ lines: [String]) {
        guard w.inside(x, y, z) else { return }
        let base = Blocks.has("dark_oak_sign") ? Blocks.id("dark_oak_sign") : Blocks.id("oak_sign")
        let f = facing.1 < 0 ? 0 : (facing.1 > 0 ? 1 : (facing.0 < 0 ? 2 : 3))
        w.set(x, y, z, base + BlockID(f))
        let be = BlockEntity(.sign)
        be.lines = lines.map { ShopMenu.fit($0, 88) }
        w.entities.append((IVec3(x, y, z), be))
    }

    // MARK: Towns

    // The town's radio room (the chatter, AshArmy.swift) in world coordinates.
    static func radioRoom(_ s: AshSite) -> V3 {
        let f = Frame(s)
        let m = townMirror(s, f)
        return V3(Float(f.x(-23 * m, 12)) + 0.5, Float(ground + 1), Float(f.z(-23 * m, 12)) + 0.5)
    }
    // The plan is drawn with the rail on its +u side; towns whose line runs up the other side are mirrored.
    static func townMirror(_ s: AshSite, _ f: Frame) -> Int {
        railShape(f.x(6, 0), f.z(6, 0)) != nil ? 1 : -1
    }

    static func buildTown(_ w: inout StructWriter, _ s: AshSite, _ f: Frame, _ rng: inout SRng) {
        let k = AshKit()
        let y0 = ground
        let m = townMirror(s, f)
        let name = townName(s)
        func put(_ u: Int, _ y: Int, _ v: Int, _ b: BlockID) { w.set(f.x(u * m, v), y, f.z(u * m, v), b) }
        func box(_ u0: Int, _ ya: Int, _ v0: Int, _ u1: Int, _ yb: Int, _ v1: Int, _ b: BlockID) {
            let xa = f.x(u0 * m, v0), xb = f.x(u1 * m, v1), za = f.z(u0 * m, v0), zb = f.z(u1 * m, v1)
            w.fill(min(xa, xb), ya, min(za, zb), max(xa, xb), yb, max(za, zb), b)
        }
        func unit(_ n: String, _ u: Float, _ v: Float, y: Int = y0 + 1) {
            let um = u * Float(m)
            let x = Float(s.x) + um * Float(-f.fz) + v * Float(f.fx) + 0.5, z = Float(s.z) + um * Float(f.fx) + v * Float(f.fz) + 0.5
            w.mob(n + "^\(f.heading)", V3(x, Float(y), z))
        }
        func soldier(_ rank: String, _ u: Float, _ v: Float, y: Int = y0 + 1) { unit("soldier_\(rank)@ash", u, v, y: y) }
        func chest(_ u: Int, _ v: Int, _ loot: String) { w.chest(f.x(u * m, v), y0 + 1, f.z(u * m, v), loot: loot, seed: rng.next(), facing: 0) }
        // Facing toward the street (-u, +u) or down the street toward the citadel (-v), in world terms.
        func dir(_ du: Int, _ dv: Int) -> (Int, Int) { (du * m * (-f.fz) + dv * f.fx, du * m * f.fx + dv * f.fz) }
        func signAt(_ u: Int, _ y: Int, _ v: Int, _ face: (Int, Int), _ lines: [String]) { sign(&w, f.x(u * m, v), y, f.z(u * m, v), facing: face, lines) }
        // A building between u0 < u1, v0 < v1 with its door in the wall facing the street (doorSide -1: the u0 wall).
        func hall(_ u0: Int, _ v0: Int, _ u1: Int, _ v1: Int, h: Int, wall: BlockID, roof: BlockID, doorSide: Int) {
            box(u0, y0 + 1, v0, u1, y0 + h, v1, wall)
            box(u0 + 1, y0 + 1, v0 + 1, u1 - 1, y0 + h - 1, v1 - 1, AIR)
            box(u0, y0 + h, v0, u1, y0 + h, v1, roof)
            box(u0 + 1, y0, v0 + 1, u1 - 1, y0, v1 - 1, k.floor)
            let du = doorSide > 0 ? u1 : u0, mid = (v0 + v1) / 2
            box(du, y0 + 1, mid - 1, du, y0 + 3, mid + 1, AIR)
            put(du + doorSide, y0 + 3, mid - 2, k.lamp); put(du + doorSide, y0 + 3, mid + 2, k.lamp)
            for v in stride(from: v0 + 3, to: v1 - 1, by: 4) where abs(v - mid) > 2 { put(u0, y0 + 3, v, k.bars); put(u1, y0 + 3, v, k.bars) }
            put((u0 + u1) / 2, y0 + h - 1, mid, k.lamp)
        }
        func lampPost(_ u: Int, _ v: Int) { box(u, y0 + 1, v, u, y0 + 3, v, k.plating); put(u, y0 + 4, v, k.lamp) }

        // The gate on the road in from the citadel, with the town's sign.
        for u in [-4, 4] { box(u, y0 + 1, -34, u, y0 + 6, -34, k.plating); put(u, y0 + 7, -34, k.lamp) }
        box(-4, y0 + 7, -34, 4, y0 + 7, -34, k.concrete)
        put(0, y0 + 7, -34, k.mark)
        signAt(-5, y0 + 1, -35, dir(0, -1), [name.uppercased(), "Ashguard garrison", "Mess, depot, rail", "Year 11 below"])
        for v in stride(from: -28, through: 30, by: 10) { lampPost(-4, v) }
        // West of the street: barracks, the mess hall, the radio room and its mast, a mortar pit.
        hall(-30, -30, -8, -16, h: 6, wall: k.plating, roof: k.concrete, doorSide: 1)
        chest(-28, -28, "ash_supply")
        soldier("recruit", -14, -22); soldier("trooper", -24, -20)
        hall(-30, -12, -8, 2, h: 6, wall: k.concrete, roof: k.plating, doorSide: 1)
        for v in stride(from: -9, through: -1, by: 4) { box(-24, y0 + 1, v, -14, y0 + 1, v, k.basalt) }
        put(-28, y0 + 1, -5, k.fire)
        signAt(-7, y0 + 1, -9, dir(1, 0), ["MESS HALL", "Rations halved", "by order of", "the Marshal"])
        hall(-30, 6, -16, 18, h: 6, wall: k.concrete, roof: k.plating, doorSide: 1)
        box(-28, y0 + 1, 7, -24, y0 + 1, 7, k.console)
        chest(-18, 8, "ash_command")
        box(-23, y0 + 7, 12, -23, y0 + 20, 12, k.chain == AIR ? k.bars : k.chain)
        put(-23, y0 + 21, 12, k.lamp)
        signAt(-15, y0 + 1, 15, dir(1, 0), ["RADIO ROOM", "Listening for", "the surface.", "Nothing yet."])
        soldier("officer", -22, 14)
        for du in -3...3 { for dv in -3...3 where max(abs(du), abs(dv)) == 3 && !(dv == -3 && abs(du) <= 1) {
            box(-22 + du, y0 + 1, 28 + dv, -22 + du, y0 + 2, 28 + dv, k.bags)
        } }
        put(-22, y0 + 1, 28, k.mortar)
        soldier("trooper:mortar", -21, 26); soldier("recruit:mortar", -23, 26)
        // East of the rail: the depot, family quarters, the signal tower.
        hall(14, -30, 32, -14, h: 7, wall: k.plating, roof: k.concrete, doorSide: -1)
        for a in 0..<4 { box(18 + a * 3, y0 + 1, -26, 18 + a * 3, y0 + 1 + rng.int(3), -24, k.crate) }
        chest(30, -28, "ash_supply")
        unit("ash_truck", 22, -9)
        for (u0, v0) in [(14, -6), (24, -6), (14, 6), (24, 6)] {
            hall(u0, v0, u0 + 7, v0 + 8, h: 4, wall: k.concrete, roof: k.blackWool, doorSide: -1)
        }
        signAt(13, y0 + 1, -3, dir(-1, 0), ["Quarters", "No lamps after", "the second bell", ""])
        box(25, y0 + 1, 23, 27, y0 + 16, 25, k.concrete)
        box(23, y0 + 17, 21, 29, y0 + 17, 27, k.plating)
        for du in -3...3 { for dv in -3...3 where max(abs(du), abs(dv)) == 3 { put(26 + du, y0 + 18, 24 + dv, k.bars) } }
        put(26, y0 + 19, 24, k.lamp)
        soldier("marksman", 26, 24, y: y0 + 18)
        // The street's watch.
        soldier("officer", 0, -20); soldier("trooper", -3, -6); soldier("trooper:mg", 3, 10); soldier("recruit:medic", -2, 2)
        soldier("recruit", -2, -32); soldier("recruit", 2, -32)            // the gate guard, just inside
    }

    // MARK: The airfield

    static func buildAirfield(_ w: inout StructWriter, _ s: AshSite, _ f: Frame, _ rng: inout SRng) {
        let k = AshKit()
        let y0 = ground
        let glass = GLASS
        func put(_ u: Int, _ y: Int, _ v: Int, _ b: BlockID) { w.set(f.x(u, v), y, f.z(u, v), b) }
        func box(_ u0: Int, _ ya: Int, _ v0: Int, _ u1: Int, _ yb: Int, _ v1: Int, _ b: BlockID) {
            let xa = f.x(u0, v0), xb = f.x(u1, v1), za = f.z(u0, v0), zb = f.z(u1, v1)
            w.fill(min(xa, xb), ya, min(za, zb), max(xa, xb), yb, max(za, zb), b)
        }
        func unit(_ n: String, _ u: Float, _ v: Float, y: Int = y0 + 1, heading: Int = 0) {
            let x = Float(s.x) + u * Float(-f.fz) + v * Float(f.fx) + 0.5, z = Float(s.z) + u * Float(f.fx) + v * Float(f.fz) + 0.5
            w.mob(n + "^\((heading + f.heading) % 360)", V3(x, Float(y), z))
        }
        func soldier(_ rank: String, _ u: Float, _ v: Float, y: Int = y0 + 1) { unit("soldier_\(rank)@ash", u, v, y: y) }
        func signAt(_ u: Int, _ y: Int, _ v: Int, _ du: Int, _ dv: Int, _ lines: [String]) {
            sign(&w, f.x(u, v), y, f.z(u, v), facing: (du * (-f.fz) + dv * f.fx, du * f.fx + dv * f.fz), lines)
        }
        func sandbags(_ u: Int, _ v: Int, _ r: Int) {
            for du in -r...r { for dv in -r...r where max(abs(du), abs(dv)) == r && !(du == r && abs(dv) <= 1) {
                box(u + du, y0 + 1, v + dv, u + du, y0 + 2, v + dv, k.bags)
            } }
        }
        // A bomber built of blocks, nose toward -u: a plated fuselage with a glazed nose and cockpit, wings with the
        // ember mark, four engines on gear legs, a tail fin and tailplane.
        func bomber(_ cu: Int, _ cv: Int) {
            box(cu - 7, y0 + 2, cv - 1, cu + 7, y0 + 4, cv + 1, k.plating)
            box(cu + 2, y0 + 2, cv - 1, cu + 2, y0 + 4, cv + 1, k.redWool)
            put(cu - 7, y0 + 3, cv, glass); box(cu - 6, y0 + 5, cv, cu - 4, y0 + 5, cv, glass)
            box(cu - 1, y0 + 3, cv - 10, cu + 2, y0 + 3, cv + 10, k.plating)
            for sv in [-7, 7] { box(cu, y0 + 3, cv + sv - 1, cu + 1, y0 + 3, cv + sv, k.mark) }
            for ev in [-8, -4, 4, 8] {
                box(cu - 3, y0 + 2, cv + ev, cu, y0 + 2, cv + ev, k.black)
                put(cu - 4, y0 + 2, cv + ev, k.bars)
                put(cu - 1, y0 + 1, cv + ev, k.chain == AIR ? k.bars : k.chain)
            }
            box(cu + 5, y0 + 5, cv, cu + 7, y0 + 8, cv, k.plating)
            put(cu + 7, y0 + 8, cv, k.redWool)
            box(cu + 6, y0 + 5, cv - 4, cu + 7, y0 + 5, cv + 4, k.plating)
            put(cu + 6, y0 + 1, cv, k.chain == AIR ? k.bars : k.chain)
        }
        // Runway: dark strip, a dashed centre line, lamps flush along both edges, the threshold marked at each end.
        box(-44, y0, -56, -30, y0, 56, k.floor)
        for v in -56...56 {
            if (v + 56) % 8 < 4 { put(-37, y0, v, k.basalt) }
            if v % 6 == 0 { put(-45, y0, v, k.lamp); put(-29, y0, v, k.lamp) }
        }
        for u in -44...(-30) where u % 2 == 0 { put(u, y0, -56, k.mark); put(u, y0, 56, k.mark) }
        box(-29, y0, -4, -9, y0, 4, k.floor)                                      // taxiway to the hangars
        // Hangars, open toward the runway, a bomber in each; a third on the apron.
        for cv in [-18, 18] {
            box(-8, y0 + 1, cv - 12, 20, y0 + 10, cv - 12, k.plating)
            box(-8, y0 + 1, cv + 12, 20, y0 + 10, cv + 12, k.plating)
            box(20, y0 + 1, cv - 12, 20, y0 + 10, cv + 12, k.plating)
            box(-8, y0 + 11, cv - 12, 20, y0 + 11, cv + 12, k.concrete)
            box(-7, y0, cv - 11, 19, y0, cv + 11, k.floor)
            for u in stride(from: -4, through: 16, by: 8) { put(u, y0 + 10, cv, k.lamp) }
            put(-8, y0 + 8, cv - 12, k.mark); put(-8, y0 + 8, cv + 12, k.mark)
            bomber(4, cv)
            w.chest(f.x(18, cv + 10), y0 + 1, f.z(18, cv + 10), loot: "ash_supply", seed: rng.next(), facing: 0)
            signAt(-9, y0 + 1, cv - 13, -1, 0, ["HANGAR \(cv < 0 ? 1 : 2)", "Engines run", "every shift.", "Wheels chocked."])
            soldier("trooper", -6, Float(cv + 8)); soldier("recruit", 12, Float(cv - 6))
        }
        bomber(-18, 42)
        soldier("recruit", -14, 32)
        // Control tower: a concrete shaft, a glazed cab, a lamp on the roof.
        box(30, y0 + 1, -14, 36, y0 + 11, -8, k.concrete)
        box(31, y0 + 1, -13, 35, y0 + 10, -9, AIR)
        box(30, y0 + 12, -14, 36, y0 + 14, -8, glass)
        box(31, y0 + 12, -13, 35, y0 + 14, -9, AIR)
        box(30, y0 + 15, -14, 36, y0 + 15, -8, k.plating)
        box(31, y0 + 11, -13, 35, y0 + 11, -9, k.floor)
        put(33, y0 + 16, -11, k.lamp)
        box(30, y0 + 1, -12, 30, y0 + 3, -10, AIR)
        box(33, y0 + 12, -13, 35, y0 + 12, -13, k.console)
        signAt(29, y0 + 1, -15, -1, 0, ["CONTROL", airfieldName, "No flights since", "the Sealing"])
        soldier("officer", 33, -11, y: y0 + 12)
        // Fuel, a barracks, a windsock, the anti-aircraft pits (quad guns of plate and bars), a mortar pit.
        for cv in [30, 44] {
            for du in -5...5 { for dv in -5...5 where du * du + dv * dv <= 25 {
                let edge = du * du + dv * dv > 16
                for y in (y0 + 1)...(y0 + 7) where edge || y == y0 + 7 { put(44 + du, y, cv + dv, y == y0 + 3 && edge ? k.redWool : k.plating) }
            } }
            put(44, y0 + 8, cv, k.lamp)
        }
        for a in 0..<6 { for b in 0..<3 where rng.int(5) != 0 { put(30 + a, y0 + 1, 50 + b, k.drum) } }
        unit("ash_truck:fuel", 30, 40, heading: 90)
        box(24, y0 + 1, -40, 48, y0 + 6, -26, k.plating)
        box(25, y0 + 1, -39, 47, y0 + 5, -27, AIR)
        box(24, y0 + 6, -40, 48, y0 + 6, -26, k.concrete)
        box(25, y0, -39, 47, y0, -27, k.floor)
        box(24, y0 + 1, -34, 24, y0 + 3, -32, AIR)
        w.chest(f.x(46, -38), y0 + 1, f.z(46, -38), loot: "ash_armory", seed: rng.next(), facing: 0)
        soldier("trooper", 30, -30); soldier("recruit", 40, -36)
        box(-26, y0 + 1, -50, -26, y0 + 9, -50, k.chain == AIR ? k.bars : k.chain)
        box(-25, y0 + 7, -50, -22, y0 + 9, -50, k.redWool)
        for (u, v) in [(-54, -30), (-54, 30), (50, -50), (54, 12)] {
            sandbags(u, v, 3)
            put(u, y0 + 1, v, k.plating)
            for (du, dv) in [(0, 0), (0, 1), (1, 0), (1, 1)] {
                put(u + du, y0 + 2, v + dv, k.bars); put(u + du - 1, y0 + 3, v + dv, k.bars)
            }
            soldier("marksman", Float(u + 1), Float(v - 2))
        }
        sandbags(20, 50, 3)
        put(20, y0 + 1, 50, k.mortar)
        soldier("trooper:mortar", 21, 48); soldier("recruit:mortar", 19, 48)
        soldier("officer", -12, 0); soldier("trooper:mg", -14, -6); soldier("recruit:medic", -12, 6)
        signAt(-26, y0 + 1, -58, 0, -1, [airfieldName.uppercased(), "Ashguard Air Wing", "Bombers: three", "Sorties: none"])
    }
}
