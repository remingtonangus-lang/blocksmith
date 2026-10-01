import Foundation
import Metal
import simd

// Free-moving block structures ("ships"): boats, airships, aircraft and land vehicles.
//
// A ship owns its own block grid (ShipGrid, cell (x, y, z) spans [x, x+1] etc. in ship space) and a
// rigid-body pose: `pos` is the world position of the centre of mass, `rot` the orientation, so
//   world = pos + rot * (local - com)
// Physics (ShipPhysics.swift) runs at fixed 60 Hz substeps: gravity, buoyancy from the displaced
// volume (solid blocks plus the enclosed dry air of the hull), anisotropic water drag, air drag,
// propellers, lift balloons, airfoils, wheels with suspension, and impulse contacts against terrain
// and other ships. Rendering (ShipRender.swift) reuses the chunk mesher on the ship grid and draws
// it with a per-ship transform. The player moves in the ship's own frame while aboard
// (World.frame, ShipPlay.swift), so walking, building and climbing on a moving ship use the exact
// block shapes; mobs and dropped items collide with ship blocks in world space and are carried.
//
// A helm block assembles the structure connected to it (natural terrain excluded) into a ship and,
// sneak-used, puts it back into the world snapped to the block grid.

typealias Quat = simd_quatf

@inline(__always) func ivSub(_ a: IVec3, _ b: IVec3) -> IVec3 { IVec3(a.x - b.x, a.y - b.y, a.z - b.z) }

// Dense block grid in ship space.
final class ShipGrid {
    private(set) var sx: Int, sy: Int, sz: Int
    private(set) var blocks: [BlockID]

    init(sx: Int, sy: Int, sz: Int, blocks: [BlockID]? = nil) {
        self.sx = sx; self.sy = sy; self.sz = sz
        self.blocks = blocks ?? [BlockID](repeating: AIR, count: sx * sy * sz)
    }

    @inline(__always) func inside(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        x >= 0 && y >= 0 && z >= 0 && x < sx && y < sy && z < sz
    }
    @inline(__always) func index(_ x: Int, _ y: Int, _ z: Int) -> Int { x + z * sx + y * sx * sz }
    @inline(__always) func get(_ x: Int, _ y: Int, _ z: Int) -> BlockID { inside(x, y, z) ? blocks[index(x, y, z)] : AIR }
    func set(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) { if inside(x, y, z) { blocks[index(x, y, z)] = b } }

    // Grows the grid so cell c fits (one spare cell of margin); returns the shift applied to old coordinates.
    func grow(toInclude c: IVec3) -> IVec3 {
        let lo = IVec3(min(0, c.x - 1), min(0, c.y - 1), min(0, c.z - 1))
        let hi = IVec3(max(sx, c.x + 2), max(sy, c.y + 2), max(sz, c.z + 2))
        let shift = IVec3(-lo.x, -lo.y, -lo.z)
        let nx = hi.x - lo.x, ny = hi.y - lo.y, nz = hi.z - lo.z
        if nx == sx && ny == sy && nz == sz { return IVec3(0, 0, 0) }
        var nb = [BlockID](repeating: AIR, count: nx * ny * nz)
        for y in 0..<sy { for z in 0..<sz { for x in 0..<sx {
            let b = blocks[index(x, y, z)]
            if b != AIR { nb[(x + shift.x) + (z + shift.z) * nx + (y + shift.y) * nx * nz] = b }
        } } }
        sx = nx; sy = ny; sz = nz
        blocks = nb
        return shift
    }
}

// Per-block-state properties the ship code needs, as flat tables.
enum ShipParts {
    enum Kind: UInt8 { case none, helm, propeller, engine, balloon, wing, wheel, ring, cannon }
    static let kinds: [Kind] = {
        var t = [Kind](repeating: .none, count: Blocks.count)
        let names: [(String, Kind)] = [("ship_helm", .helm), ("ship_propeller", .propeller), ("ship_engine", .engine),
                                       ("ship_balloon", .balloon), ("ship_wing", .wing), ("ship_wheel", .wheel),
                                       ("ship_turret_ring", .ring), ("ship_cannon", .cannon)]
        for i in 0..<Blocks.count {
            let k = Blocks.key(Blocks.groupBase[i])
            for (n, kind) in names where n == k { t[i] = kind }
        }
        return t
    }()
    static let wool: [Bool] = (0..<Blocks.count).map { Blocks.key(Blocks.groupBase[$0]).hasSuffix("_wool") }
    // Unit direction of facing index 0...3 (north, south, west, east).
    static let facingDir: [V3] = [V3(0, 0, -1), V3(0, 0, 1), V3(-1, 0, 0), V3(1, 0, 0)]
    @inline(__always) static func facing(_ b: BlockID) -> Int { Int(b - Blocks.groupBase[Int(b)]) & 3 }

    // Mass in tonnes per block (water = 1 per full block).
    static let mass: [Float] = {
        var t = [Float](repeating: 0, count: Blocks.count)
        for i in 0..<Blocks.count {
            let b = BlockID(i)
            if b == AIR || Blocks.isLiquid(b) { continue }
            let key = Blocks.key(Blocks.groupBase[i])
            let snd = Blocks.def(b).sound
            var d: Float = 2.3                                  // stone and anything heavier-sounding
            if snd == .wood { d = 0.55 } else if snd == .plant { d = 0.2 } else if snd == .glass { d = 0.9 }
            else if snd == .sand || snd == .dirt { d = 1.6 } else if snd == .snow { d = 0.5 }
            if key.hasSuffix("_wool") || key.hasSuffix("_carpet") { d = 0.12 }
            if ["iron_block", "gold_block", "copper_block", "anvil", "netherite_block", "iron_bars"].contains(key) { d = 7 }
            switch kinds[i] {
            case .balloon: d = 0.04
            case .engine: d = 3
            case .propeller: d = 0.8
            case .wing: d = 0.25
            case .wheel: d = 0.6
            case .helm: d = 0.4
            case .ring: d = 2
            case .cannon: d = 2.5
            case .none: break
            }
            // Partial blocks weigh their volume.
            if !Blocks.collide[i] { d = min(d, 0.05) }
            else if !Blocks.fullCollide[i] {
                var v: Float = 0
                for bx in Blocks.boxes[i] {
                    v += Float(Int(bx.x1) - Int(bx.x0)) * Float(Int(bx.y1) - Int(bx.y0)) * Float(Int(bx.z1) - Int(bx.z0)) / 4096
                }
                d *= max(0.1, min(1, v > 0 ? v : 0.5))
            }
            t[i] = d
        }
        return t
    }()

    // Blocks never pulled into a ship by the helm: terrain, fluids, plants.
    static let natural: [Bool] = {
        let keys: Set<String> = ["stone", "grass_block", "dirt", "coarse_dirt", "podzol", "mycelium", "rooted_dirt", "mud", "sand", "red_sand",
                                 "gravel", "clay", "bedrock", "deepslate", "tuff", "granite", "diorite", "andesite", "calcite", "netherrack",
                                 "end_stone", "snowy_grass_block", "snow", "ice", "moss_block", "dripstone_block", "soul_sand", "soul_soil",
                                 "crimson_nylium", "warped_nylium", "farmland", "dirt_path", "terracotta", "pointed_dripstone", "magma_block",
                                 "powder_snow", "pale_moss_block", "suspicious_sand", "suspicious_gravel", "sculk", "fire", "soul_fire",
                                 "nether_portal", "end_portal", "end_gateway", "end_portal_frame", "obsidian", "crying_obsidian", "spawner"]
        var t = [Bool](repeating: false, count: Blocks.count)
        for i in 0..<Blocks.count {
            let k = Blocks.key(Blocks.groupBase[i])
            if i == Int(AIR) || Blocks.isLiquid(BlockID(i)) || Blocks.isPlant(BlockID(i)) || keys.contains(k) || k.hasSuffix("_ore")
                || k.hasSuffix("_leaves") || k.contains("kelp") || k.contains("seagrass") || k.contains("coral") || Blocks.hardness[i] < 0 {
                t[i] = true
            }
        }
        return t
    }()

    // Turns a block state by quarter turns about +Y (one turn: north -> west -> south -> east -> north),
    // for the families with facing states (4 facings, stairs, pillars, wall torches).
    static func rotate(_ b: BlockID, _ turns: Int) -> BlockID {
        let t = ((turns % 4) + 4) % 4
        if t == 0 || b == AIR { return b }
        func turn(_ f: Int) -> Int {
            var f = f
            for _ in 0..<t { f = [2, 3, 1, 0][f] }      // N->W, S->E, W->S, E->N
            return f
        }
        let base = Blocks.groupBase[Int(b)]
        let k = Blocks.key(base)
        let off = Int(b - base)
        let shape = Blocks.shape[Int(base)]
        if shape == "stairs" { return base + BlockID((off & 4) + turn(off & 3)) }
        if shape == "torch" {
            if off >= 1 && off <= 4 { return base + BlockID(1 + turn(off - 1)) }
            return b
        }
        if Blocks.has(k + "[south]") && Blocks.has(k + "[east]") && shape.isEmpty && off < 4 { return base + BlockID(turn(off)) }
        if t % 2 == 1 && Blocks.has(k + "[x]") && Blocks.has(k + "[z]") {
            let name = Blocks.key(b)
            if name.hasSuffix("[x]") { return Blocks.id(k + "[z]") }
            if name.hasSuffix("[z]") { return Blocks.id(k + "[x]") }
        }
        return b
    }
}

// Buoyancy sample: a group of displacing cells (solid blocks + enclosed dry air) in ship space.
struct ShipBucket {
    var centre: V3          // ship space
    var volume: Float       // blocks
    var height: Float       // vertical extent (for the submerged fraction)
}

final class Ship {
    let id: Int
    var grid: ShipGrid
    var blockEntities: [IVec3: BlockEntity] = [:]     // ship space
    var name = "Ship"

    // Pose and motion.
    var pos = V3(0, 0, 0)            // world position of the centre of mass
    var rot = Quat(angle: 0, axis: V3(0, 1, 0))
    var vel = V3(0, 0, 0)
    var angVel = V3(0, 0, 0)         // world space, rad/s
    var prevPos = V3(0, 0, 0), prevRot = Quat(angle: 0, axis: V3(0, 1, 0))
    var sleeping = 0                 // substeps at rest (physics thins out)
    var terrainClear: Float = 0      // height of the hull above everything under its footprint (broadphase)
    var terrainCheck = 0             // substeps until that is measured again

    // Mass properties (rebuilt when blocks change).
    var com = V3(0, 0, 0)            // ship space
    var mass: Float = 1
    var invInertia = matrix_identity_float3x3   // ship space, about the centre of mass
    var inertiaDiag = V3(1, 1, 1)
    var blockCount = 0
    var fwd = V3(0, 0, -1)           // ship-space forward (from the helm)
    var helm: IVec3?
    var props: [(V3, V3)] = []       // propeller centre, thrust direction (ship space)
    var wheels: [V3] = []
    var wheelBase = 0                // wheel cells in the lowest wheel row (they carry the load)
    var wings: [V3] = []
    var sails = 0                    // wool blocks (catch the wind while someone steers)
    var cannons: [(V3, V3)] = []     // cannon centre, muzzle direction (ship space)
    var balloons = 0
    var engines = 0
    var hull: [V3] = []              // centres of exposed solid cells (contacts)
    var buckets: [ShipBucket] = []
    var colMin: [Int16] = []         // per column (x + z*sx): lowest solid cell, Int16.max if none
    var dryMask: [Bool] = []         // per cell: enclosed air that keeps water out
    var localMin = V3(0, 0, 0), localMax = V3(1, 1, 1)   // bounds of the blocks (ship space)
    var gridOrigin = IVec3(0, 0, 0)  // world cell of ship cell (0, 0, 0) when it was assembled
    var area = V3(1, 1, 1)           // projected area across ship-space x, y, z (air drag)

    // World-space bounds of the blocks (refreshed every physics step).
    var worldMin = V3(0, 0, 0), worldMax = V3(0, 0, 0)

    // Control (set by the pilot each frame, ShipPlay.swift).
    var throttle: Float = 0          // -1...1
    var telegraphPause: Float = 0    // piloting: throttle resting at stop after passing through it
    var steer: Float = 0             // -1 (left) ... 1 (right)
    var climb: Float = 0             // -1...1
    var liftLevel: Float = 0         // 0...1 share of balloon lift in use (kept while nobody steers: airships hover)
    var piloted = false
    var hoverY: Float?               // altitude held by an unpiloted airship
    var autopilot: V3?               // throttle, steer, climb when no player steers (harness, crews)

    // Turrets: a ship mounted on another on a vertical-axis bearing (a Turret Ring), placed by its parent.
    weak var parent: Ship?
    var children: [Ship] = []        // turrets riding on this ship (refreshed every frame by the manager)
    var parentId: Int?
    var mountLocal = V3(0, 0, 0)     // bearing point in the parent's space
    var pivot = V3(0, 0, 0)          // the same point in this ship's space
    var turretYaw: Float = 0         // relative to the parent
    var aimYaw: Float?               // wanted turretYaw
    var aimAt: V3?                   // world point to track (crews); sets aimYaw
    var reload: Float = 0            // seconds until the cannons can fire again

    // Vessels (ShipVessels.swift): crewed encounter ships.
    var role: String?                // "frigate", "carriage"
    var home: V3?
    var crewStations: [V3] = []
    var captured = false             // the player has steered it: crews stop giving orders
    var fireTimer: Float = 0
    var initialBlocks = 0            // block count when it appeared (hull bar)
    var soundTimer: Float = 0

    // Diagnostics (harness).
    var submerged: Float = 0         // submerged volume last step
    var contacts = 0
    var grounded = false

    // Rendering (ShipRender.swift).
    let mesh = ShipMesh()

    init(id: Int, grid: ShipGrid) {
        self.id = id
        self.grid = grid
    }

    // MARK: Transforms

    @inline(__always) func toWorld(_ l: V3) -> V3 { pos + rot.act(l - com) }
    @inline(__always) func toLocal(_ w: V3) -> V3 { rot.inverse.act(w - pos) + com }
    @inline(__always) func dirToWorld(_ d: V3) -> V3 { rot.act(d) }
    @inline(__always) func dirToLocal(_ d: V3) -> V3 { rot.inverse.act(d) }
    // Same, with the pose of the previous frame (carrying riders).
    @inline(__always) func prevToLocal(_ w: V3) -> V3 { prevRot.inverse.act(w - prevPos) + com }

    // Heading (player yaw convention: forward = (-sin yaw, 0, -cos yaw)) of the ship's -Z axis.
    var yaw: Float {
        let f = rot.act(V3(0, 0, -1))
        return atan2f(-f.x, -f.z)
    }
    var prevYaw: Float {
        let f = prevRot.act(V3(0, 0, -1))
        return atan2f(-f.x, -f.z)
    }
    func velocity(at w: V3) -> V3 { vel + simd_cross(angVel, w - pos) }

    // World-space inverse inertia.
    var invInertiaWorld: simd_float3x3 {
        let r = simd_float3x3(rot)
        return r * invInertia * r.transpose
    }

    // MARK: Derived data

    @inline(__always) func dry(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        grid.inside(x, y, z) && dryMask[grid.index(x, y, z)]
    }

    // Recomputes mass, centre of mass, inertia, parts, hull cells, buoyancy buckets and the dry mask.
    // Keeps the world position of the ship-space origin fixed (pos follows the moving centre of mass).
    func rebuild() {
        let g = grid
        let sx = g.sx, sy = g.sy, sz = g.sz
        let massT = ShipParts.mass, kinds = ShipParts.kinds, collide = Blocks.collide
        var m: Float = 0
        var c = V3(0, 0, 0)
        var n = 0
        props.removeAll(); wheels.removeAll(); wings.removeAll(); cannons.removeAll(); balloons = 0; engines = 0; sails = 0
        let woolT = ShipParts.wool
        var lo = V3(Float(sx), Float(sy), Float(sz)), hi = V3(0, 0, 0)
        helm = nil
        for y in 0..<sy { for z in 0..<sz { for x in 0..<sx {
            let b = g.blocks[g.index(x, y, z)]
            if b == AIR { continue }
            n += 1
            let p = V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)
            let bm = massT[Int(b)]
            m += bm
            c += p * bm
            lo = simd_min(lo, p - 0.5); hi = simd_max(hi, p + 0.5)
            if woolT[Int(b)] { sails += 1 }
            switch kinds[Int(b)] {
            case .helm:
                if helm == nil { helm = IVec3(x, y, z); fwd = -ShipParts.facingDir[ShipParts.facing(b)] }
            case .propeller: props.append((p, -ShipParts.facingDir[ShipParts.facing(b)]))
            case .engine: engines += 1
            case .balloon: balloons += 1
            case .wing: wings.append(p)
            case .wheel: wheels.append(p)
            case .cannon: cannons.append((p, -ShipParts.facingDir[ShipParts.facing(b)]))
            case .ring, .none: break
            }
        } } }
        blockCount = n
        let lowest = wheels.map { $0.y }.min() ?? 0
        wheelBase = wheels.filter { $0.y < lowest + 0.5 }.count
        localMin = n > 0 ? lo : V3(0, 0, 0)
        localMax = n > 0 ? hi : V3(1, 1, 1)
        let oldCom = com
        mass = max(m, 0.05)
        let newCom = m > 0 ? c / m : V3(Float(sx), Float(sy), Float(sz)) * 0.5
        // Keep the structure where it is: the world point of the old origin must not move.
        pos += rot.act(newCom - oldCom)
        prevPos += prevRot.act(newCom - oldCom)
        com = newCom

        // Inertia about the centre of mass (each block a unit cube).
        var I = simd_float3x3(0)
        for y in 0..<sy { for z in 0..<sz { for x in 0..<sx {
            let b = g.blocks[g.index(x, y, z)]
            if b == AIR { continue }
            let bm = massT[Int(b)]
            let r = V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5) - com
            let rr = simd_dot(r, r)
            let own = bm / 6
            I[0][0] += bm * (rr - r.x * r.x) + own; I[1][1] += bm * (rr - r.y * r.y) + own; I[2][2] += bm * (rr - r.z * r.z) + own
            I[0][1] -= bm * r.x * r.y; I[0][2] -= bm * r.x * r.z; I[1][2] -= bm * r.y * r.z
        } } }
        I[1][0] = I[0][1]; I[2][0] = I[0][2]; I[2][1] = I[1][2]
        // Floor the diagonal so tiny or thin ships stay well conditioned.
        let floorI = max(0.2, mass * 0.3)
        for i in 0..<3 { I[i][i] = max(I[i][i], floorI) }
        invInertia = I.inverse
        inertiaDiag = V3(I[0][0], I[1][1], I[2][2])
        sleeping = 0

        // Column bottoms and the enclosed-air (dry) mask: air above a solid cell of its column and between
        // solid cells along both its x row and its z row (a bowl, a closed hull or a walled deck).
        colMin = [Int16](repeating: Int16.max, count: sx * sz)
        for z in 0..<sz { for x in 0..<sx {
            for y in 0..<sy where collide[Int(g.blocks[g.index(x, y, z)])] { colMin[x + z * sx] = Int16(y); break }
        } }
        dryMask = [Bool](repeating: false, count: sx * sy * sz)
        var rowLo = [Int](repeating: Int.max, count: sx), rowHi = [Int](repeating: -1, count: sx)
        for y in 0..<sy {
            for x in 0..<sx { rowLo[x] = Int.max; rowHi[x] = -1 }
            for z in 0..<sz { for x in 0..<sx where collide[Int(g.blocks[g.index(x, y, z)])] {
                rowLo[x] = min(rowLo[x], z); rowHi[x] = max(rowHi[x], z)
            } }
            for z in 0..<sz {
                var xl = Int.max, xh = -1
                for x in 0..<sx where collide[Int(g.blocks[g.index(x, y, z)])] { xl = min(xl, x); xh = max(xh, x) }
                if xh < 0 { continue }
                for x in (xl + 1)..<max(xl + 1, xh) {
                    let i = g.index(x, y, z)
                    if collide[Int(g.blocks[i])] { continue }
                    if z <= rowLo[x] || z >= rowHi[x] { continue }
                    if Int(colMin[x + z * sx]) >= y { continue }
                    dryMask[i] = true
                }
            }
        }

        // Hull: solid cells with an exposed face (not wheels: they have their own contact model).
        hull.removeAll()
        func open(_ x: Int, _ y: Int, _ z: Int) -> Bool { !g.inside(x, y, z) || !collide[Int(g.blocks[g.index(x, y, z)])] }
        for y in 0..<sy { for z in 0..<sz { for x in 0..<sx {
            let b = g.blocks[g.index(x, y, z)]
            if !collide[Int(b)] || kinds[Int(b)] == .wheel { continue }
            if open(x + 1, y, z) || open(x - 1, y, z) || open(x, y + 1, z) || open(x, y - 1, z) || open(x, y, z + 1) || open(x, y, z - 1) {
                hull.append(V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5))
            }
        } } }

        // Projected areas (cells seen looking along each ship axis).
        var ayz = [Bool](repeating: false, count: sy * sz), axz = [Bool](repeating: false, count: sx * sz)
        var axy = [Bool](repeating: false, count: sx * sy)
        for y in 0..<sy { for z in 0..<sz { for x in 0..<sx where collide[Int(g.blocks[g.index(x, y, z)])] {
            ayz[y + z * sy] = true; axz[x + z * sx] = true; axy[x + y * sx] = true
        } } }
        func count(_ a: [Bool]) -> Int { a.reduce(0) { $0 + ($1 ? 1 : 0) } }
        area = V3(Float(max(1, count(ayz))), Float(max(1, count(axz))), Float(max(1, count(axy))))

        // Buoyancy buckets (bigger for big ships so sampling stays cheap).
        let cells = sx * sy * sz
        let B = cells <= 6000 ? 1 : (cells <= 60000 ? 2 : 4)
        let bx = (sx + B - 1) / B, by = (sy + B - 1) / B, bz = (sz + B - 1) / B
        var vol = [Float](repeating: 0, count: bx * by * bz)
        var cen = [V3](repeating: .zero, count: bx * by * bz)
        for y in 0..<sy { for z in 0..<sz { for x in 0..<sx {
            let i = g.index(x, y, z)
            let b = g.blocks[i]
            var v: Float = 0
            if dryMask[i] { v = 1 }
            else if collide[Int(b)] {
                v = Blocks.fullCollide[Int(b)] ? 1 : 0.5
                if kinds[Int(b)] == .balloon { v = 0 }        // balloons lift through ShipPhysics, not buoyancy
            }
            if v == 0 { continue }
            let k = x / B + (z / B) * bx + (y / B) * bx * bz
            vol[k] += v
            cen[k] += V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5) * v
        } } }
        buckets.removeAll()
        for k in 0..<vol.count where vol[k] > 0 {
            buckets.append(ShipBucket(centre: cen[k] / vol[k], volume: vol[k], height: Float(B)))
        }
        updateBounds()
    }

    func updateBounds() {
        var lo = V3(repeating: .greatestFiniteMagnitude), hi = V3(repeating: -.greatestFiniteMagnitude)
        for i in 0..<8 {
            let c = V3(i & 1 == 0 ? localMin.x : localMax.x, i & 2 == 0 ? localMin.y : localMax.y, i & 4 == 0 ? localMin.z : localMax.z)
            let w = toWorld(c)
            lo = simd_min(lo, w); hi = simd_max(hi, w)
        }
        worldMin = lo; worldMax = hi
    }

    // MARK: Frame-mode block lookup (World.block while World.frame == self)

    // The ship's block at a ship-space cell; around and inside the ship, the world block at that point
    // (water is kept out of the hull's enclosed air).
    func frameBlock(_ x: Int, _ y: Int, _ z: Int, _ w: World) -> BlockID {
        if grid.inside(x, y, z) {
            let i = grid.index(x, y, z)
            let b = grid.blocks[i]
            if b != AIR { return b }
            if dryMask[i] { return AIR }
        }
        let p = toWorld(V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5))
        // Turrets on this ship (their own grids, turned on their rings).
        for t in children where p.x > t.worldMin.x && p.x < t.worldMax.x && p.y > t.worldMin.y && p.y < t.worldMax.y
            && p.z > t.worldMin.z && p.z < t.worldMax.z {
            let l = t.toLocal(p)
            let tb = t.grid.get(Int(floor(l.x)), Int(floor(l.y)), Int(floor(l.z)))
            if tb != AIR { return tb }
        }
        let wb = w.rawBlock(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)))
        // Inside the hull's columns the world's water never reaches above the ship's floor.
        if Blocks.isLiquid(wb) && grid.inside(x, y, z) && Int(colMin[x + z * grid.sx]) < y && Blocks.fluidKind[Int(wb)] == 1 { return AIR }
        return wb
    }

    // MARK: Raycast in ship space

    // Nearest ship block along a world ray: (cell, face normal in ship space, distance).
    func raycast(_ o: V3, _ d: V3, maxDist: Float, world w: World) -> (cell: IVec3, normal: IVec3, t: Float)? {
        let lo = toLocal(o), ld = dirToLocal(d)
        // Clip the ray to the grid box.
        var t0: Float = 0, t1 = maxDist
        let gmax = V3(Float(grid.sx), Float(grid.sy), Float(grid.sz))
        for a in 0..<3 {
            if abs(ld[a]) < 1e-6 {
                if lo[a] < 0 || lo[a] > gmax[a] { return nil }
            } else {
                var ta = (0 - lo[a]) / ld[a], tb = (gmax[a] - lo[a]) / ld[a]
                if ta > tb { swap(&ta, &tb) }
                t0 = max(t0, ta); t1 = min(t1, tb)
                if t0 > t1 { return nil }
            }
        }
        var t = t0
        var best: (IVec3, IVec3, Float)?
        while t <= t1 + 0.001 {
            let p = lo + ld * t
            let c = IVec3(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)))
            let b = grid.get(c.x, c.y, c.z)
            if b != AIR && Blocks.targetable(b) {
                let o3 = V3(Float(c.x), Float(c.y), Float(c.z))
                for (mn, mx) in w.selectionBoxes(b) {
                    if let rb = World.rayBox(lo, ld, o3 + mn, o3 + mx), rb.0 <= maxDist, best == nil || rb.0 < best!.2 { best = (c, rb.1, rb.0) }
                }
                if best != nil { break }
            }
            t += 0.05
        }
        return best.map { (cell: $0.0, normal: $0.1, t: $0.2) }
    }
}

// MARK: Manager (one per World / dimension)

final class ShipManager {
    unowned let world: World
    private(set) var list: [Ship] = []
    private var nextId = 1
    var pilot: Ship?                 // the ship the player steers
    var aboard: Ship?                // the ship whose frame the player moved in last frame
    var target: (ship: Ship, cell: IVec3, normal: IVec3)?   // ship block under the crosshair
    var mineCell: (Ship, IVec3)?
    var mineProgress: Float = 0
    var breakCooldown: Float = 0
    private var boxScratch: [(V3, V3)] = []
    var shells: [Shell] = []         // cannon shells in flight (ShipCombat.swift)
    var ghosts: [(Ship, Float)] = [] // docked ships still drawn while the world remeshes their blocks
    var wind = V3(4, 0, 2)           // world wind (b/s): sails (set each frame from the clock and weather)
    var encounters = true            // rare vessels spawn near their home regions (off in harness scenes)
    var encounterTimer: Float = 0
    var spawnedRegions = Set<String>()   // regions whose vessel has already appeared
    let meshQueue = DispatchQueue(label: "blocksmith.shipmesh", qos: .userInitiated)
    var stepMs: Double = 0           // physics time last frame (harness / debug)
    var accum: Float = 0                  // unstepped time (ShipPhysics)

    init(world: World) {
        self.world = world
        load()
    }

    var isEmpty: Bool { list.isEmpty }

    func add(_ s: Ship) { list.append(s) }
    func remove(_ s: Ship) {
        list.removeAll { $0 === s }
        if pilot === s { pilot = nil }
        if aboard === s { aboard = nil }
        if target?.ship === s { target = nil }
    }
    func newId() -> Int { defer { nextId += 1 }; return nextId }

    // MARK: World-space collision boxes (mobs, items, the player while not aboard)

    // Approximate world AABBs of ship blocks overlapping [mn, mx]: each block's box is centred on its
    // rotated centre, widened halfway toward the rotated cube's bounds so turned decks have no gaps.
    func boxes(_ mn: V3, _ mx: V3, _ out: inout [(V3, V3)]) {
        for s in list where s.worldMax.x > mn.x - 1 && s.worldMin.x < mx.x + 1 && s.worldMax.y > mn.y - 1 && s.worldMin.y < mx.y + 1
            && s.worldMax.z > mn.z - 1 && s.worldMin.z < mx.z + 1 {
            let r = simd_float3x3(s.rot)
            let ax: V3 = simd_abs(r[0]), ay: V3 = simd_abs(r[1]), az: V3 = simd_abs(r[2])
            let full: V3 = (ax + ay + az) * 0.5
            let half = V3(0.5 + (full.x - 0.5) * 0.5, full.y, 0.5 + (full.z - 0.5) * 0.5)
            // Query box in ship space.
            var lo = V3(repeating: .greatestFiniteMagnitude), hi = V3(repeating: -.greatestFiniteMagnitude)
            for i in 0..<8 {
                let c = V3(i & 1 == 0 ? mn.x : mx.x, i & 2 == 0 ? mn.y : mx.y, i & 4 == 0 ? mn.z : mx.z)
                let l = s.toLocal(c)
                lo = simd_min(lo, l); hi = simd_max(hi, l)
            }
            let g = s.grid
            let x0 = max(0, Int(floor(lo.x - 1))), x1 = min(g.sx - 1, Int(floor(hi.x + 1)))
            let y0 = max(0, Int(floor(lo.y - 1))), y1 = min(g.sy - 1, Int(floor(hi.y + 1)))
            let z0 = max(0, Int(floor(lo.z - 1))), z1 = min(g.sz - 1, Int(floor(hi.z + 1)))
            if x0 > x1 || y0 > y1 || z0 > z1 { continue }
            for y in y0...y1 { for z in z0...z1 { for x in x0...x1 {
                let b = g.blocks[g.index(x, y, z)]
                if !Blocks.collide[Int(b)] { continue }
                var bl: Float = 0, bh: Float = 1
                if Blocks.connectKind[Int(b)] != 0 {
                    // Fences and walls (their shape depends on neighbours): a full post, 1.5 high like their collision.
                    bh = Blocks.connectKind[Int(b)] == 2 ? 1 : 1.5
                } else if !Blocks.fullCollide[Int(b)] {
                    // Partial blocks (slabs, stairs...): their vertical extent.
                    bl = 1; bh = 0
                    for bx in Blocks.boxes[Int(b)] { bl = min(bl, Float(bx.y0) / 16); bh = max(bh, Float(bx.y1) / 16) }
                    if bh <= bl { continue }
                }
                let cl = V3(Float(x) + 0.5, Float(y) + (bl + bh) * 0.5, Float(z) + 0.5)
                let w = s.toWorld(cl)
                let hy = half.y * (bh - bl) + (half.y - 0.5) * (1 - (bh - bl))
                let bmn = V3(w.x - half.x, w.y - hy, w.z - half.z), bmx = V3(w.x + half.x, w.y + hy, w.z + half.z)
                if bmx.x > mn.x && bmn.x < mx.x && bmx.y > mn.y && bmn.y < mx.y && bmx.z > mn.z && bmn.z < mx.z { out.append((bmn, bmx)) }
            } } }
        }
    }

    func overlaps(_ mn: V3, _ mx: V3) -> Bool {
        boxScratch.removeAll(keepingCapacity: true)
        boxes(mn, mx, &boxScratch)
        let eps: Float = 1e-4
        for (a, c) in boxScratch where a.x < mx.x - eps && c.x > mn.x + eps && a.y < mx.y - eps && c.y > mn.y + eps && a.z < mx.z - eps && c.z > mn.z + eps {
            return true
        }
        return false
    }

    // The ship whose frame a body at world position p belongs to (aboard or about to be).
    func frameShip(for p: V3, height: Float, current: Ship?) -> Ship? {
        func test(_ s: Ship, _ margin: Float) -> Bool {
            let l = s.toLocal(p)
            return l.x > s.localMin.x - margin && l.x < s.localMax.x + margin && l.z > s.localMin.z - margin && l.z < s.localMax.z + margin
                && l.y > s.localMin.y - 1 - height * 0.5 && l.y < s.localMax.y + 2.5
        }
        if let c = current, list.contains(where: { $0 === c }), test(c, 1.5) { return c }
        for s in list where p.x > s.worldMin.x - 2 && p.x < s.worldMax.x + 2 && p.z > s.worldMin.z - 2 && p.z < s.worldMax.z + 2
            && p.y > s.worldMin.y - 3 && p.y < s.worldMax.y + 4 {
            if test(s, 0.45) { return s }
        }
        return nil
    }

    // MARK: Assembly

    // Builds a ship from everything connected to the helm at h (natural terrain excluded). Structures standing on
    // a Turret Ring become turrets: separate ships turning on the ring.
    @discardableResult
    func assemble(at h: IVec3, game: Game?) -> (Ship?, String) {
        let w = world
        let natural = ShipParts.natural, kinds = ShipParts.kinds
        let limit = 60000
        let dirs = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 1, 0), IVec3(0, -1, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)]
        // Connected cells from start, not entering `taken`, never going up out of a turret ring.
        func collect(_ start: IVec3, _ taken: Set<IVec3>) -> [IVec3]? {
            var seen = Set<IVec3>([start])
            var queue = [start]
            var head = 0
            while head < queue.count {
                let c = queue[head]; head += 1
                if queue.count > limit { return nil }
                let ring = kinds[Int(w.rawBlock(c.x, c.y, c.z))] == .ring
                for (k, d) in dirs.enumerated() {
                    if ring && k == 2 { continue }
                    let n = c + d
                    if seen.contains(n) || taken.contains(n) || n.y < 0 || n.y >= CH { continue }
                    if natural[Int(w.rawBlock(n.x, n.y, n.z))] { continue }
                    seen.insert(n)
                    queue.append(n)
                }
            }
            return queue
        }
        let tooBig = "Too big to move (over \(limit) blocks) - is it touching a building?"
        guard let main = collect(h, []) else { return (nil, tooBig) }
        var taken = Set(main)
        var turrets: [(IVec3, [IVec3])] = []
        for c in main where kinds[Int(w.rawBlock(c.x, c.y, c.z))] == .ring {
            let top = c + IVec3(0, 1, 0)
            if taken.contains(top) || natural[Int(w.rawBlock(top.x, top.y, top.z))] { continue }
            guard let cells = collect(top, taken) else { return (nil, tooBig) }
            for t in cells { taken.insert(t) }
            turrets.append((c, cells))
        }
        let s = makeShip(main)
        var made = [s]
        for (ring, cells) in turrets {
            let t = makeShip(cells)
            t.parent = s
            t.parentId = s.id
            let bearing = V3(Float(ring.x) + 0.5, Float(ring.y) + 1, Float(ring.z) + 0.5)
            t.mountLocal = s.toLocal(bearing)
            t.pivot = t.toLocal(bearing)
            t.name = "Turret"
            made.append(t)
        }
        // Water level around the hull (to fill the hole it leaves).
        var waterTop: Int?
        for c in main {
            for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)] {
                let n = c + d
                if taken.contains(n) { continue }
                let b = w.rawBlock(n.x, n.y, n.z)
                if Blocks.fluidKind[Int(b)] == 1 && Blocks.fluidLevel[Int(b)] == 0 { waterTop = max(waterTop ?? n.y, n.y) }
            }
            if waterTop != nil && main.count > 4000 { break }
        }
        for c in taken { w.setBlockAsync(c.x, c.y, c.z, AIR) }
        // Refill the water the hull kept out (the vacated cells and the dry air inside it).
        if let top = waterTop {
            let lo = s.gridOrigin
            let g = s.grid
            for y in lo.y...min(top, lo.y + g.sy - 1) { for z in lo.z..<(lo.z + g.sz) { for x in lo.x..<(lo.x + g.sx) {
                let gx = x - lo.x, gy = y - lo.y, gz = z - lo.z
                let wasShip = taken.contains(IVec3(x, y, z))
                if (wasShip || s.dry(gx, gy, gz)) && w.rawBlock(x, y, z) == AIR { w.setBlockAsync(x, y, z, WATER) }
            } } }
        }
        for m in made {
            add(m)
            m.mesh.rebuildAll(m, device: w.device, queue: meshQueue)
        }
        let total = made.reduce(0) { $0 + $1.blockCount }
        let mass = made.reduce(Float(0)) { $0 + $1.mass }
        let extra = turrets.isEmpty ? "" : ", \(turrets.count) turret\(turrets.count == 1 ? "" : "s")"
        return (s, "Assembled \(total) blocks (\(String(format: "%.1f", mass)) t\(extra))")
    }

    // A ship from world cells (the blocks are read, not removed).
    private func makeShip(_ cells: [IVec3]) -> Ship {
        let w = world
        var lo = cells[0], hi = cells[0]
        for c in cells {
            lo = IVec3(min(lo.x, c.x), min(lo.y, c.y), min(lo.z, c.z))
            hi = IVec3(max(hi.x, c.x), max(hi.y, c.y), max(hi.z, c.z))
        }
        let grid = ShipGrid(sx: hi.x - lo.x + 1, sy: hi.y - lo.y + 1, sz: hi.z - lo.z + 1)
        for c in cells { grid.set(c.x - lo.x, c.y - lo.y, c.z - lo.z, w.rawBlock(c.x, c.y, c.z)) }
        let s = Ship(id: newId(), grid: grid)
        for c in cells { if let be = w.blockEntities.removeValue(forKey: c) { s.blockEntities[ivSub(c, lo)] = be } }
        s.rebuild()
        s.pos = V3(Float(lo.x), Float(lo.y), Float(lo.z)) + s.com
        s.prevPos = s.pos
        s.gridOrigin = lo
        s.updateBounds()
        return s
    }

    // Puts a ship back into the world, snapped to the block grid and the nearest quarter turn.
    @discardableResult
    func disassemble(_ s: Ship, game: Game?) -> String {
        for t in list where t.parent === s { _ = disassemble(t, game: game) }
        let w = world
        let turns = Int((s.yaw / (.pi / 2)).rounded())
        let snapped = Quat(angle: Float(turns) * .pi / 2, axis: V3(0, 1, 0))
        // World position of cell centres under the snapped rotation, rounded so they land on block centres.
        let g = s.grid
        let anchorLocal = V3(0.5, 0.5, 0.5)
        let a = s.pos + snapped.act(anchorLocal - s.com)
        let aCell = IVec3(Int(floor(a.x)), Int(floor(a.y)), Int(floor(a.z)))
        func cell(_ x: Int, _ y: Int, _ z: Int) -> IVec3 {
            let d = snapped.act(V3(Float(x), Float(y), Float(z)))
            return aCell + IVec3(Int(d.x.rounded()), Int(d.y.rounded()), Int(d.z.rounded()))
        }
        var dropped = 0
        for y in 0..<g.sy { for z in 0..<g.sz { for x in 0..<g.sx {
            let b = g.blocks[g.index(x, y, z)]
            let p = cell(x, y, z)
            if p.y < 0 || p.y >= CH { continue }
            let here = w.rawBlock(p.x, p.y, p.z)
            if b == AIR {
                // Keep the hull's enclosed air dry.
                if s.dry(x, y, z) && Blocks.isLiquid(here) { w.setBlockAsync(p.x, p.y, p.z, AIR) }
                continue
            }
            if !Blocks.replaceable[Int(here)] {
                if let game { game.drops.spawn(ItemStack(Items.item(forBlock: b) ?? 0, 1), at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5); dropped += 1 }
                continue
            }
            w.setBlockAsync(p.x, p.y, p.z, ShipParts.rotate(b, turns))
            if let be = s.blockEntities[IVec3(x, y, z)] { w.blockEntities[p] = be }
        } } }
        remove(s)
        // Keep drawing it, snapped into place, until the world's new meshes are in.
        s.rot = Quat(angle: Float(turns) * .pi / 2, axis: V3(0, 1, 0))
        let c0 = V3(Float(aCell.x), Float(aCell.y), Float(aCell.z)) + 0.5
        s.pos = c0 - s.rot.act(anchorLocal - s.com)
        s.updateBounds()
        ghosts.append((s, 0.6))
        return dropped > 0 ? "Docked (\(dropped) blocks didn't fit and dropped)" : "Docked"
    }

    // MARK: Editing

    // Sets a block on a ship (growing its grid when needed) and refreshes physics and mesh.
    func setBlock(_ s: Ship, _ c: IVec3, _ b: BlockID) {
        var cell = c
        if !s.grid.inside(c.x, c.y, c.z) {
            if b == AIR { return }
            let shift = s.grid.grow(toInclude: c)
            let sv = V3(Float(shift.x), Float(shift.y), Float(shift.z))
            s.com += sv
            var moved: [IVec3: BlockEntity] = [:]
            for (k, v) in s.blockEntities { moved[k + shift] = v }
            s.blockEntities = moved
            if let t = target, t.ship === s { target = (s, t.cell + shift, t.normal) }
            cell = c + shift
            s.grid.set(cell.x, cell.y, cell.z, b)
            s.rebuild()
            s.mesh.rebuildAll(s, device: world.device, queue: meshQueue)
            return
        }
        s.grid.set(cell.x, cell.y, cell.z, b)
        if b == AIR { s.blockEntities.removeValue(forKey: cell) }
        s.rebuild()
        if s.blockCount == 0 { remove(s); return }
        s.mesh.rebuildAround(s, cell, device: world.device, queue: meshQueue)
        if b == AIR { splitIfNeeded(s) }
    }

    // MARK: Save / load (ships.json in the dimension's save folder)

    private struct Saved: Codable {
        var id: Int
        var name: String
        var pos: [Float]
        var rot: [Float]
        var vel: [Float]
        var angVel: [Float]
        var size: [Int]
        var palette: [String]
        var cells: Data             // lzfse(u16 palette index per cell)
        var liftLevel: Float
        var hoverY: Float?
        var entities: [String: BlockEntity]
        var parent: Int?
        var mount: [Float]?
        var pivot: [Float]?
        var turretYaw: Float?
        var role: String?
        var home: [Float]?
        var captured: Bool?
        var initial: Int?
    }

    private var url: URL? { world.save?.dir.appendingPathComponent("ships.json") }

    func save() {
        guard let url else { return }
        if let r = world.save?.dir.appendingPathComponent("shipregions.json"), let d = try? JSONEncoder().encode(Array(spawnedRegions).sorted()) {
            try? d.write(to: r, options: .atomic)
        }
        guard let d = encode() else {
            if FileManager.default.fileExists(atPath: url.path) { try? FileManager.default.removeItem(at: url) }
            return
        }
        try? d.write(to: url, options: .atomic)
    }

    private func load() {
        if let r = world.save?.dir.appendingPathComponent("shipregions.json"), let d = try? Data(contentsOf: r),
           let a = try? JSONDecoder().decode([String].self, from: d) { spawnedRegions = Set(a) }
        guard let url, let d = try? Data(contentsOf: url) else { return }
        decode(d)
    }

    // All ships as JSON (nil when there are none).
    func encode() -> Data? {
        var out: [Saved] = []
        for s in list {
            var map: [BlockID: UInt16] = [:]
            var names: [String] = []
            var idx = [UInt16](repeating: 0, count: s.grid.blocks.count)
            for (i, b) in s.grid.blocks.enumerated() {
                if let m = map[b] { idx[i] = m; continue }
                let m = UInt16(names.count)
                map[b] = m; names.append(Blocks.key(b)); idx[i] = m
            }
            let raw = idx.withUnsafeBytes { Data($0) }
            let packed = ((try? (raw as NSData).compressed(using: .lzfse)) as Data?) ?? raw
            var ents: [String: BlockEntity] = [:]
            for (k, v) in s.blockEntities { ents["\(k.x),\(k.y),\(k.z)"] = v }
            let q = s.rot.vector
            out.append(Saved(id: s.id, name: s.name, pos: [s.pos.x, s.pos.y, s.pos.z], rot: [q.x, q.y, q.z, q.w],
                             vel: [s.vel.x, s.vel.y, s.vel.z], angVel: [s.angVel.x, s.angVel.y, s.angVel.z],
                             size: [s.grid.sx, s.grid.sy, s.grid.sz], palette: names, cells: packed,
                             liftLevel: s.liftLevel, hoverY: s.hoverY, entities: ents,
                             parent: s.parent?.id, mount: [s.mountLocal.x, s.mountLocal.y, s.mountLocal.z],
                             pivot: [s.pivot.x, s.pivot.y, s.pivot.z], turretYaw: s.turretYaw,
                             role: s.role, home: s.home.map { [$0.x, $0.y, $0.z] }, captured: s.captured, initial: s.initialBlocks))
        }
        if out.isEmpty { return nil }
        return try? JSONEncoder().encode(out)
    }

    // Adds the ships stored in `d` (see encode).
    func decode(_ d: Data) {
        guard let saved = try? JSONDecoder().decode([Saved].self, from: d) else { return }
        for sv in saved where sv.size.count == 3 && sv.pos.count == 3 && sv.rot.count == 4 {
            let n = sv.size[0] * sv.size[1] * sv.size[2]
            guard n > 0 else { continue }
            let raw = ((try? (sv.cells as NSData).decompressed(using: .lzfse)) as Data?) ?? sv.cells
            guard raw.count == n * 2 else { continue }
            let palette = sv.palette.map { Blocks.has($0) ? Blocks.id($0) : AIR }
            var blocks = [BlockID](repeating: AIR, count: n)
            raw.withUnsafeBytes { (p: UnsafeRawBufferPointer) in
                let u = p.bindMemory(to: UInt16.self)
                for i in 0..<n { let k = Int(u[i]); blocks[i] = k < palette.count ? palette[k] : AIR }
            }
            let s = Ship(id: sv.id, grid: ShipGrid(sx: sv.size[0], sy: sv.size[1], sz: sv.size[2], blocks: blocks))
            s.name = sv.name
            s.rebuild()
            s.pos = V3(sv.pos[0], sv.pos[1], sv.pos[2])
            s.rot = simd_normalize(Quat(vector: V4(sv.rot[0], sv.rot[1], sv.rot[2], sv.rot[3])))
            if sv.vel.count == 3 { s.vel = V3(sv.vel[0], sv.vel[1], sv.vel[2]) }
            if sv.angVel.count == 3 { s.angVel = V3(sv.angVel[0], sv.angVel[1], sv.angVel[2]) }
            s.prevPos = s.pos; s.prevRot = s.rot
            s.liftLevel = sv.liftLevel
            s.hoverY = sv.hoverY
            for (k, v) in sv.entities {
                let p = k.split(separator: ",").compactMap { Int($0) }
                if p.count == 3 { s.blockEntities[IVec3(p[0], p[1], p[2])] = v }
            }
            s.parentId = sv.parent
            if let m = sv.mount, m.count == 3 { s.mountLocal = V3(m[0], m[1], m[2]) }
            if let p = sv.pivot, p.count == 3 { s.pivot = V3(p[0], p[1], p[2]) }
            s.turretYaw = sv.turretYaw ?? 0
            s.role = sv.role
            if let h = sv.home, h.count == 3 { s.home = V3(h[0], h[1], h[2]) }
            s.captured = sv.captured ?? false
            s.initialBlocks = sv.initial ?? 0
            s.updateBounds()
            s.mesh.rebuildAll(s, device: world.device, queue: meshQueue)
            list.append(s)
            nextId = max(nextId, sv.id + 1)
        }
        // Re-link turrets to their ships.
        for s in list where s.parent == nil {
            if let pid = s.parentId { s.parent = list.first { $0.id == pid && $0 !== s } }
        }
    }
}
