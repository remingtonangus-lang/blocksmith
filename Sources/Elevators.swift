import Foundation
import simd

// FAILURES.md entry 2, rebuilt (Nov 2). Oct 31 16:20:47 in a citadel side tower: "there should be an elevator"; Nov 1
// 20:17-20:19 at two of them (-310 74 -1818, 625 79 2072): "is this supposed to be an elevator?... I want it to be an
// actual elevator", "Should be replacing the wires if there's actually gonna be functional elevators". The P503 Lift
// Pads were a jump that teleported him to the next pad: no car, no shaft, no doors, no buttons.
//
// An elevator is a car in a shaft. The car (floor, three walls, a lit ceiling and a floor panel, two wide and three deep)
// stands at one landing as blocks; called, it comes away as one body (a kinematic Ship, as the garage door does) and
// rides up or down the shaft at a lift's pace, carrying him and whoever stands in it, and is written back at the landing
// it stops at. Each landing has a pair of sliding doors that open only where the car stands, so the open shaft is never
// a step away, and a call button beside them. In the car, the panel lists the floors; pick one and it goes.
// Shafts are found from their blocks (no record kept): the doors give the shaft's side and width, the landings are the
// heights its doors stand at, the car is where its floor is.
enum Elevators {
    static let shipName = "Lift Car"
    static let floorKey = "lift_car_floor", wallKey = "lift_car_wall", ceilKey = "lift_car_ceiling", panelKey = "lift_car_panel"
    static let doorKey = "lift_door", callKey = "lift_call"
    static let W = 2, D = 3                                  // the car: two wide (the doors), three deep (two in a small tower)
    static let vmax: Float = 3.5, accel: Float = 2.4         // blocks a second, and a second squared
    static let doorStep: Float = 0.16                        // seconds a door stage takes (three stages)
    static var rides = 0, calls = 0, retrofits = 0           // (checks)

    static func has() -> Bool { Blocks.has(floorKey) }
    static func key(_ b: BlockID) -> String { Blocks.key(Blocks.groupBase[Int(b)]) }
    static func isCar(_ b: BlockID) -> Bool { let k = key(b); return k == floorKey || k == wallKey || k == ceilKey || k == panelKey }
    static func isDoor(_ b: BlockID) -> Bool { has() && Blocks.groupBase[Int(b)] == Blocks.id(doorKey) }
    static func usable(_ k: String) -> Bool { k == panelKey || k == callKey || k == doorKey }

    // MARK: Blocks

    static let faces = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)]
    static func faceIndex(_ d: IVec3) -> Int { faces.firstIndex(of: d) ?? 0 }
    static func faceBox(_ f: Int, _ t: Int = 2) -> Box {
        switch f {
        case 0: return Box(16 - t, 0, 0, 16, 16, 16)
        case 1: return Box(0, 0, 0, t, 16, 16)
        case 2: return Box(0, 0, 16 - t, 16, 16, 16)
        default: return Box(0, 0, 0, 16, 16, t)
        }
    }
    // A car wall cell with panels on the faces in `mask` (bit f: faces[f]).
    static func wall(_ mask: Int) -> BlockID { Blocks.id(wallKey) + BlockID(max(1, min(15, mask)) - 1) }
    static func panel(_ face: IVec3) -> BlockID { Blocks.id(panelKey) + BlockID(faceIndex(face)) }
    // A landing door leaf: across u (+x or +z), sliding toward -u (side 0) or +u (side 1), stage 0 shut ... 2 open.
    static func door(alongZ: Bool, side: Int, stage: Int) -> BlockID { Blocks.id(doorKey) + BlockID((alongZ ? 6 : 0) + side * 3 + stage) }
    static func doorStage(_ b: BlockID) -> Int { (Int(b) - Int(Blocks.id(doorKey))) % 3 }
    static func doorSide(_ b: BlockID) -> Int { ((Int(b) - Int(Blocks.id(doorKey))) % 6) / 3 }
    static func doorAlongZ(_ b: BlockID) -> Bool { Int(b) - Int(Blocks.id(doorKey)) >= 6 }
    static func call(_ toWall: IVec3) -> BlockID { Blocks.id(callKey) + BlockID(faceIndex(toWall)) }

    static func register(_ r: BlockRegistry) {
        guard !r.has(floorKey) else { return }
        var f = BlockDef(floorKey, "Lift Car Floor")
        f.tex = ["lift_car_floor"]; f.hardness = 5; f.resistance = 20; f.tool = .pickaxe; f.sound = .metal
        r.add(f)
        var c = BlockDef(ceilKey, "Lift Car Ceiling")
        c.tex = ["lift_car_ceiling"]; c.hardness = 3; c.tool = .pickaxe; c.sound = .metal; c.emit = 12
        r.add(c)
        for mask in 1...15 {
            var d = BlockDef(mask == 1 ? wallKey : "\(wallKey)[\(mask)]", "Lift Car Wall")
            d.tex = ["lift_car_wall"]; d.render = .model; d.layer = .cutout; d.opaque = false; d.skyStop = false
            d.boxes = (0..<4).filter { mask & (1 << $0) != 0 }.map { faceBox($0) }
            d.hardness = 4; d.tool = .pickaxe; d.sound = .metal; d.group = wallKey; d.hidden = mask != 1
            r.add(d)
        }
        let wallT = Array(repeating: Tex.id("lift_car_wall"), count: 6), panT = Array(repeating: Tex.id("lift_car_panel"), count: 6)
        for (i, _) in faces.enumerated() {
            var d = BlockDef(i == 0 ? panelKey : "\(panelKey)[\(i)]", "Lift Car Panel")
            d.tex = ["lift_car_wall"]; d.render = .model; d.layer = .cutout; d.opaque = false; d.skyStop = false
            var w = faceBox(i); w.tex = wallT
            var p: Box
            switch i {
            case 0: p = Box(13, 4, 5, 14, 13, 11)
            case 1: p = Box(2, 4, 5, 3, 13, 11)
            case 2: p = Box(5, 4, 13, 11, 13, 14)
            default: p = Box(5, 4, 2, 11, 13, 3)
            }
            p.tex = panT
            d.boxes = [w, p]; d.hardness = 4; d.tool = .pickaxe; d.sound = .metal; d.group = panelKey; d.hidden = i != 0; d.emit = 3
            r.add(d)
        }
        for k in 0..<12 {
            let alongZ = k >= 6, side = (k % 6) / 3, stage = k % 3
            var d = BlockDef(k == 0 ? doorKey : "\(doorKey)[\(k)]", "Lift Door")
            d.tex = ["lift_door"]; d.render = .model; d.layer = .cutout; d.opaque = false; d.skyStop = false
            let a0 = stage == 0 ? 0 : (side == 0 ? 0 : (stage == 1 ? 8 : 14)), a1 = stage == 0 ? 16 : (side == 0 ? (stage == 1 ? 8 : 2) : 16)
            d.boxes = [alongZ ? Box(7, 0, a0, 9, 16, a1) : Box(a0, 0, 7, a1, 16, 9)]
            d.hardness = 6; d.resistance = 30; d.tool = .pickaxe; d.requiresTool = true; d.sound = .metal; d.group = doorKey; d.hidden = k != 0
            r.add(d)
        }
        for (i, _) in faces.enumerated() {
            var d = BlockDef(i == 0 ? callKey : "\(callKey)[\(i)]", "Lift Call Button")
            d.tex = ["lift_call"]; d.render = .model; d.layer = .cutout; d.opaque = false; d.skyStop = false; d.collide = false
            d.boxes = [BlockRegistry.attached(1, [2, 3, 0, 1][i], w: 6, h: 9, d: 2)]
            d.hardness = 2; d.tool = .pickaxe; d.sound = .metal; d.group = callKey; d.hidden = i != 0; d.emit = 5
            r.add(d)
        }
    }

    // MARK: The shaft

    struct Shaft {
        var a: IVec3                  // the car's front-left cell (x, z; y unused)
        var u: IVec3                  // across the doors (+x or +z), leaf 0 to leaf 1
        var n: IVec3                  // from the doors into the shaft
        var landings: [Int]           // each landing's floor height (the car's floor there), lowest first
        var car: Int?                 // the landing the car stands at
        var d = D                     // the car's depth
        func foot(_ i: Int, _ j: Int, _ y: Int) -> IVec3 { IVec3(a.x + u.x * i + n.x * j, y, a.z + u.z * i + n.z * j) }
        func doorCell(_ i: Int, _ y: Int) -> IVec3 { foot(i, -1, y) }
        var key: Int64 { Int64(a.x) << 32 ^ Int64(a.z) & 0xFFFF_FFFF ^ Int64(faceIndex(n)) << 60 }
    }

    // The shaft a door, call button, car block or panel at p belongs to.
    static func shaft(_ w: World, near p: IVec3) -> Shaft? {
        guard has() else { return nil }
        // A door leaf: this one, or the nearest one to a button or a car block.
        var leaf: IVec3?
        if isDoor(w.block(p.x, p.y, p.z)) { leaf = p }
        else {
            var bd = Int.max
            for y in (p.y - 4)...(p.y + 4) { for z in (p.z - 4)...(p.z + 4) { for x in (p.x - 4)...(p.x + 4) where isDoor(w.block(x, y, z)) {
                let d = abs(x - p.x) + abs(y - p.y) * 2 + abs(z - p.z)
                if d < bd { bd = d; leaf = IVec3(x, y, z) }
            } } }
        }
        guard var c = leaf else { return nil }
        while isDoor(w.block(c.x, c.y - 1, c.z)) { c.y -= 1 }
        let b = w.block(c.x, c.y, c.z)
        let alongZ = doorAlongZ(b)
        let u = alongZ ? IVec3(0, 0, 1) : IVec3(1, 0, 0)
        let leaf0 = doorSide(b) == 0 ? c : IVec3(c.x - u.x, c.y, c.z - u.z)
        let F0 = c.y - 1
        // The shaft's side: the car's floor or the open shaft behind the doors at the landing's floor.
        let sides = alongZ ? [IVec3(1, 0, 0), IVec3(-1, 0, 0)] : [IVec3(0, 0, 1), IVec3(0, 0, -1)]
        func open(_ n: IVec3) -> Int {
            var k = 0
            for i in 0..<W {
                let q = IVec3(leaf0.x + u.x * i + n.x, F0, leaf0.z + u.z * i + n.z)
                let qb = w.block(q.x, q.y, q.z)
                if key(qb) == floorKey { k += 2 } else if qb == AIR { k += 1 }
            }
            return k
        }
        let n = open(sides[0]) >= open(sides[1]) ? sides[0] : sides[1]
        let a = IVec3(leaf0.x + n.x, 0, leaf0.z + n.z)
        var s = Shaft(a: a, u: u, n: n, landings: [], car: nil)
        // Its depth: open (or the car's own) from the doors back to the shaft's wall, at head height.
        s.d = 0
        while s.d < 4 {
            let q = s.foot(0, s.d, F0 + 2)
            let qb = w.block(q.x, q.y, q.z)
            guard qb == AIR || isCar(qb) else { break }
            s.d += 1
        }
        guard s.d >= 1 else { return nil }
        for y in thru(max(1, F0 - 96), min(CH - 6, F0 + 96)) {
            let dc = s.doorCell(0, y + 1)
            if isDoor(w.block(dc.x, dc.y, dc.z)) && !isDoor(w.block(dc.x, dc.y - 1, dc.z)) {
                s.landings.append(y)
                let fc = s.foot(0, 0, y)
                if key(w.block(fc.x, fc.y, fc.z)) == floorKey { s.car = y }
            }
        }
        return s.landings.isEmpty ? nil : s
    }

    // What a landing is called on the car's panel.
    static func name(_ w: World, _ s: Shaft, _ F: Int) -> String {
        guard let i = s.landings.firstIndex(of: F) else { return "Floor" }
        if i == 0 { return "Ground floor" }
        let c = s.foot(0, 1, F + 1)
        if i == s.landings.count - 1 && w.lightAt(c.x, F + 6, c.z).sky >= 14 { return "Roof" }
        return "Floor \(i + 1)"
    }

    // MARK: Running

    final class Run {
        var shaft: Shaft
        var queue: [Int] = []
        var phase = 0                 // 0 idle, 1 doors shutting, 2 held (body hidden), 3 riding, 4 written back, 5 doors opening
        var to = 0, from = 0
        var timer: Float = 0
        var travelled: Float = 0, speed: Float = 0
        @WeakLink var ship: Ship? = nil
        var pos0 = V3(0, 0, 0)
        var cells: [(IVec3, BlockID)] = []   // the car's blocks, relative to its front-left floor cell
        var wait: [(Chunk, Int, Int)] = []
        init(_ s: Shaft) { shaft = s }
    }
    static var runs: [Int64: Run] = [:]

    static func run(_ w: World, near p: IVec3) -> Run? {
        guard let s = shaft(w, near: p) else { return nil }
        if let r = runs[s.key] {
            if r.phase == 0 { r.shaft.landings = s.landings; if let c = s.car { r.shaft.car = c } }
            return r
        }
        let r = Run(s)
        runs[s.key] = r
        return r
    }

    // The car sent to (or called to) landing F.
    static func request(_ g: Game, _ r: Run, _ F: Int) {
        guard r.shaft.landings.contains(F) else { return }
        if r.phase == 0 && r.shaft.car == F {
            // Here already: the doors open (if they were shut).
            r.phase = 5; r.timer = 0
            return
        }
        if !r.queue.contains(F) && !(r.phase >= 1 && r.phase <= 4 && r.to == F) { r.queue.append(F) }
    }

    // His use of a call button, the car's panel, or a landing door.
    @discardableResult
    static func use(_ g: Game, _ p: IVec3) -> Bool {
        let b = g.world.block(p.x, p.y, p.z), k = key(b)
        guard usable(k), let r = run(g.world, near: p) else { return false }
        let at = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)
        if k == panelKey {
            g.sfx(.buttonStone, 0.5, at: at)
            g.openMenu(LiftMenu(game: g, run: r))
            return true
        }
        // A call button or a landing's door: the car comes to this landing.
        let F = r.shaft.landings.min { abs($0 + 1 - p.y) < abs($1 + 1 - p.y) } ?? r.shaft.landings[0]
        g.sfx(.buttonStone, 0.6, at: at)
        calls += 1
        request(g, r, F)
        return true
    }

    static func setDoors(_ w: World, _ s: Shaft, _ F: Int, stage: Int) {
        let alongZ = s.u.z != 0
        for i in 0..<W { for y in (F + 1)...(F + 3) {
            let c = s.doorCell(i, y)
            guard isDoor(w.block(c.x, c.y, c.z)) else { continue }
            w.setBlock(c.x, c.y, c.z, door(alongZ: alongZ, side: i, stage: stage))
        } }
    }
    static func doorsAt(_ w: World, _ s: Shaft, _ F: Int) -> Int {
        let c = s.doorCell(0, F + 1)
        let b = w.block(c.x, c.y, c.z)
        return isDoor(b) ? doorStage(b) : 0
    }

    static func sections(_ w: World, _ cells: [IVec3]) -> [(Chunk, Int, Int)] { GarageDoors.sections(w, cells) }

    // Every frame (Game.advance, after the ships moved).
    static func tick(_ g: Game, _ dt: Float) {
        let w = g.world
        retrofitTick(g, dt)
        // A car body with no run (a save taken mid-ride): it is written back where it is, at the nearest landing height.
        for s in w.ships.list where s.name == shipName && !runs.values.contains(where: { $0.ship === s }) {
            for y in 0..<s.grid.sy { for z in 0..<s.grid.sz { for x in 0..<s.grid.sx {
                let b = s.grid.get(x, y, z)
                guard b != AIR else { continue }
                let q = s.toWorld(V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5))
                let c = IVec3(Int(floor(q.x)), Int(q.y.rounded(.down)), Int(floor(q.z)))
                if w.block(c.x, c.y, c.z) == AIR { w.setBlock(c.x, c.y, c.z, b) }
            } } }
            w.ships.remove(s)
        }
        guard !runs.isEmpty else { return }
        for (k, r) in runs {
            r.timer += dt
            switch r.phase {
            case 0:
                guard !r.queue.isEmpty else {
                    // Idle and far from him: forgotten (found again from the blocks when next used).
                    let c = r.shaft.foot(0, 0, r.shaft.car ?? 0)
                    if simd_length(V2(g.player.pos.x - Float(c.x), g.player.pos.z - Float(c.z))) > 96 { runs[k] = nil }
                    continue
                }
                let F = r.queue.removeFirst()
                guard let car = r.shaft.car else { r.queue.removeAll(); continue }
                if F == car { r.phase = 5; r.timer = 0; continue }
                r.to = F; r.from = car
                r.phase = 1; r.timer = 0
            case 1:
                // The doors where the car stands slide shut, a stage at a time.
                guard r.timer >= doorStep else { continue }
                r.timer = 0
                let st = doorsAt(w, r.shaft, r.from)
                if st > 0 {
                    setDoors(w, r.shaft, r.from, stage: st - 1)
                    if st == 2 { g.sfx(.pistonContract, 0.45, at: center(r.shaft, r.from)) }
                    continue
                }
                lift(g, r)
            case 2:
                guard let s = r.ship else { r.phase = 0; continue }
                let built = !s.mesh.busy && !s.mesh.sections.isEmpty
                if !(GarageDoors.drawn(w, r.wait) && built) && r.timer < 1.5 { s.vel = .zero; continue }
                s.hidden = false
                r.phase = 3; r.timer = 0; r.travelled = 0; r.speed = 0
                g.sfx(.pistonExtend, 0.5, at: s.pos)
            case 3:
                guard let s = r.ship else { r.phase = 0; continue }
                let dist = Float(abs(r.to - r.from)), dir: Float = r.to > r.from ? 1 : -1
                let left = max(0, dist - r.travelled)
                r.speed = min(vmax, r.speed + accel * dt, (2 * accel * left).squareRoot() + 0.05)
                r.travelled = min(dist, r.travelled + r.speed * dt)
                let want = r.pos0 + V3(0, dir * r.travelled, 0)
                if r.travelled >= dist - 0.001 {
                    s.pos = want; s.vel = .zero; s.angVel = .zero; s.updateBounds()
                    // Written back at the landing it stopped at.
                    let base = r.shaft.foot(0, 0, r.to)
                    var put: [IVec3] = []
                    for (o, b) in r.cells {
                        let c = IVec3(base.x + o.x, base.y + o.y, base.z + o.z)
                        w.setBlock(c.x, c.y, c.z, b); put.append(c)
                    }
                    r.wait = sections(w, put)
                    r.shaft.car = r.to
                    r.phase = 4; r.timer = 0
                    rides += 1
                    g.sfx(.ironDoorClose, 0.5, at: want)
                    continue
                }
                let h = max(dt, 1.0 / 120)
                s.vel = (want - s.pos) / h
                s.angVel = .zero
            case 4:
                guard let s = r.ship else { r.phase = 5; r.timer = 0; continue }
                s.vel = .zero
                if GarageDoors.drawn(w, r.wait) || r.timer > 1.5 { w.ships.remove(s); r.ship = nil; r.phase = 5; r.timer = 0 }
            case 5:
                // The doors at the car's landing slide open.
                guard r.timer >= doorStep, let F = r.shaft.car else { continue }
                r.timer = 0
                let st = doorsAt(w, r.shaft, F)
                if st < 2 {
                    if st == 0 { g.sfx(.bell, 0.12, at: center(r.shaft, F)); g.sfx(.pistonExtend, 0.4, at: center(r.shaft, F)) }
                    setDoors(w, r.shaft, F, stage: st + 1)
                    continue
                }
                r.phase = 0
            default: r.phase = 0
            }
        }
    }

    static func center(_ s: Shaft, _ F: Int) -> V3 {
        let c = s.foot(0, 0, F + 2)
        return V3(Float(c.x) + 0.5 + Float(s.u.x) * 0.5 + Float(s.n.x), Float(c.y), Float(c.z) + 0.5 + Float(s.u.z) * 0.5 + Float(s.n.z))
    }

    // The car comes away from the landing as one body (hidden until the world has redrawn without it).
    static func lift(_ g: Game, _ r: Run) {
        let w = g.world
        let s = r.shaft
        let base = s.foot(0, 0, r.from)
        var cells: [(IVec3, BlockID)] = []
        for j in 0..<s.d { for i in 0..<W { for y in 0...4 {
            let c = s.foot(i, j, r.from + y)
            let b = w.block(c.x, c.y, c.z)
            if isCar(b) { cells.append((IVec3(c.x - base.x, c.y - base.y, c.z - base.z), b)) }
        } } }
        guard !cells.isEmpty else { r.phase = 0; r.shaft.car = nil; return }
        r.cells = cells
        let bp = Blueprint()
        var lo = IVec3(Int.max, Int.max, Int.max)
        for (o, b) in cells { bp.cells[o] = b; lo = IVec3(min(lo.x, o.x), min(lo.y, o.y), min(lo.z, o.z)) }
        let sh = w.ships.spawn(bp, at: V3(Float(base.x), Float(base.y), Float(base.z)), yaw: 0, name: shipName, role: "")
        sh.role = nil
        r.pos0 = V3(Float(base.x + lo.x), Float(base.y + lo.y), Float(base.z + lo.z)) + sh.com
        sh.pos = r.pos0; sh.prevPos = r.pos0
        sh.kinematic = true; sh.hidden = true
        sh.vel = .zero; sh.angVel = .zero
        sh.updateBounds()
        w.restoring = true
        for (o, _) in cells { w.setBlock(base.x + o.x, base.y + o.y, base.z + o.z, AIR) }
        w.restoring = false
        r.wait = sections(w, cells.map { IVec3(base.x + $0.0.x, base.y + $0.0.y, base.z + $0.0.z) })
        r.ship = sh
        r.shaft.car = nil
        r.phase = 2; r.timer = 0
    }

    // MARK: Building one

    // A shaft with its car at the lowest landing, doors and a call button at every landing, walls round it between
    // them and over the top; `foot0` the car's front-left cell, `u` across the doors, `n` into the shaft. `get`/`set`
    // read and write the world or a structure's chunk. Walls go only where the cell is open (a tower's own walls,
    // floors and lights stay), except the floors and ceilings inside the shaft, which are cut.
    // (`cell(x, y, z, nil)` reads, `cell(x, y, z, b)` writes: one closure, as two capturing the same structure writer
    // would overlap.)
    static func build(foot0: IVec3, u: IVec3, n: IVec3, landings: [Int], depth D: Int = Elevators.D, wall wallB: BlockID,
                      cell: (Int, Int, Int, BlockID?) -> BlockID) {
        func get(_ x: Int, _ y: Int, _ z: Int) -> BlockID { cell(x, y, z, nil) }
        func set(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) { _ = cell(x, y, z, b) }
        guard has(), let lo = landings.min(), let hi = landings.max() else { return }
        let s = Shaft(a: foot0, u: u, n: n, landings: landings.sorted(), car: lo, d: D)
        let alongZ = u.z != 0
        for y in lo...(hi + 5) {
            for j in -1...D { for i in -1...W {
                let c = s.foot(i, j, y)
                let inside = i >= 0 && i < W && j >= 0 && j < D
                if inside { set(c.x, c.y, c.z, AIR); continue }
                let atDoor = j == -1 && i >= 0 && i < W && landings.contains { y >= $0 + 1 && y <= $0 + 3 }
                if atDoor { set(c.x, c.y, c.z, door(alongZ: alongZ, side: i, stage: 0)); continue }
                if y == hi + 5 || !Blocks.collide[Int(get(c.x, c.y, c.z))] { set(c.x, c.y, c.z, wallB) }
            } }
            // (the shaft's roof)
            if y == hi + 5 { for j in 0..<D { for i in 0..<W { let c = s.foot(i, j, y); set(c.x, c.y, c.z, wallB) } } }
        }
        // The pit's floor under the lowest landing.
        for j in 0..<D { for i in 0..<W { let c = s.foot(i, j, lo - 1); if !Blocks.collide[Int(get(c.x, c.y, c.z))] { set(c.x, c.y, c.z, wallB) } } }
        // A call button beside the doors at each landing, on the wall past leaf 1.
        for F in landings {
            let c = s.foot(W, -2, F + 2)
            set(c.x, c.y, c.z, call(n))
        }
        // The car.
        let ux = u, nx = n
        for j in 0..<D { for i in 0..<W {
            set(s.foot(i, j, lo).x, lo, s.foot(i, j, lo).z, Blocks.id(floorKey))
            set(s.foot(i, j, lo + 4).x, lo + 4, s.foot(i, j, lo + 4).z, Blocks.id(ceilKey))
            var mask = 0
            if i == 0 { mask |= 1 << faceIndex(IVec3(-ux.x, 0, -ux.z)) }
            if i == W - 1 { mask |= 1 << faceIndex(ux) }
            if j == D - 1 { mask |= 1 << faceIndex(nx) }
            for y in (lo + 1)...(lo + 3) {
                let c = s.foot(i, j, y)
                if i == W - 1 && j == (D >= 3 ? 1 : 0) && y == lo + 2 { set(c.x, c.y, c.z, panel(ux)); continue }
                if mask != 0 { set(c.x, c.y, c.z, wall(mask)) }
            }
        } }
        // The lowest landing's doors stand open on the car.
        for i in 0..<W { for y in (lo + 1)...(lo + 3) { let c = s.doorCell(i, y); set(c.x, c.y, c.z, door(alongZ: alongZ, side: i, stage: 2)) } }
    }

    // MARK: His World's towers

    // The P503 Lift Pads in his saved citadels: a column of pads (two or more, one over another) near him is taken out and
    // a shaft and car built where they stood: the car two wide and three deep from the pads' column back to the
    // tower's wall nearest them, its doors toward the tower's middle.
    static var retrofitClock: Float = 0
    static func retrofitTick(_ g: Game, _ dt: Float) {
        retrofitClock -= dt
        guard retrofitClock <= 0, has(), let pad = Lift.pad else { return }
        retrofitClock = 2
        let w = g.world
        let p = g.player.pos
        let px = Int(floor(p.x)), py = Int(floor(p.y)), pz = Int(floor(p.z))
        for dz in -8...8 { for dx in -8...8 { for dy in -6...2 {
            let x = px + dx, y = py + dy, z = pz + dz
            guard w.block(x, y, z) == pad else { continue }
            if retrofit(w, IVec3(x, y, z), avoid: p) { retrofits += 1; return }
        } } }
    }

    @discardableResult
    static func retrofit(_ w: World, _ p: IVec3, avoid: V3? = nil) -> Bool {
        guard let pad = Lift.pad else { return false }
        var ys: [Int] = []
        for y in thru(max(1, p.y - 64), min(CH - 8, p.y + 64)) where w.block(p.x, y, p.z) == pad { ys.append(y) }
        guard ys.count >= 2 else { return false }
        // The tower's nearest wall (two to five cells off at a middle landing's head height): the shaft's back.
        let mid = ys[ys.count / 2] + 2
        var best: (IVec3, Int)?
        for d in faces {
            var k = 1
            while k <= 6 && !Blocks.collide[Int(w.block(p.x + d.x * k, mid, p.z + d.z * k))] { k += 1 }
            if k >= 3 && k <= 5 && (best == nil || k < best!.1) { best = (d, k) }
        }
        guard let (n, depth) = best else { return false }
        // Across: the side with more room.
        let us = n.x != 0 ? [IVec3(0, 0, 1), IVec3(0, 0, -1)] : [IVec3(1, 0, 0), IVec3(-1, 0, 0)]
        func room(_ u: IVec3) -> Int {
            var k = 0
            while k < 5 && !Blocks.collide[Int(w.block(p.x + u.x * k, mid, p.z + u.z * k))] { k += 1 }
            return k
        }
        let u0 = room(us[0]) >= room(us[1]) ? us[0] : us[1]
        // Leaf 0 sits at -u: with u0 negative the pads' column is the car's second cell across.
        let u = u0.x + u0.z > 0 ? u0 : IVec3(-u0.x, 0, -u0.z)
        let foot0 = u0.x + u0.z > 0 ? IVec3(p.x, 0, p.z) : IVec3(p.x - u.x, 0, p.z - u.z)
        // The car fills the pads' column back to the wall (three deep), so the front row is the pads' row.
        var shift = max(0, D - depth)
        var front = IVec3(foot0.x - n.x * shift, 0, foot0.z - n.z * shift)
        var uu = u, nn = n, dd = D, lifts = ys, citadel = false
        // A citadel side tower (its pads three in from the west wall, the ladder up the north of its middle): the lift
        // goes where a new tower's does, south of the middle and clear of its doorways (CapitalBase.build).
        let centre = IVec3(p.x + 3, 0, p.z)
        if n == IVec3(-1, 0, 0) && depth == 3 && Blocks.has("ladder") && Blocks.groupBase[Int(w.block(centre.x, mid, centre.z - 4))] == Blocks.id("ladder") {
            front = IVec3(p.x, 0, p.z + 2); uu = IVec3(1, 0, 0); nn = IVec3(0, 0, 1); dd = 2; shift = 0; citadel = true
            // (its roof garden's pad: the ladder goes on up there, as in a new tower)
            if ys.count >= 3 && ys[ys.count - 1] - ys[ys.count - 2] == 7 { lifts = Array(ys.dropLast()) }
        }
        // (never with him over the shaft: an upper floor's cut would drop him down it)
        if let a = avoid {
            let s = Shaft(a: front, u: uu, n: nn, landings: lifts, car: nil)
            for j in -1...dd { for i in -1...W {
                let c = s.foot(i, j, 0)
                if Int(floor(a.x)) == c.x && Int(floor(a.z)) == c.z { return false }
            } }
        }
        let wallB = Blocks.has("capital_stone_trim") ? Blocks.id("capital_stone_trim") : Blocks.id("stone_bricks")
        for y in ys { w.setBlock(p.x, y, p.z, Blocks.has("capital_stone") ? Blocks.id("capital_stone") : STONE) }
        _ = shift
        build(foot0: front, u: uu, n: nn, landings: lifts, depth: dd, wall: wallB) { x, y, z, b in
            if let b { w.setBlock(x, y, z, b); return b }
            return w.block(x, y, z)
        }
        // (and its empty storeys become the rooms a new tower has, TowerRooms.swift)
        if citadel {
            for (i, F) in lifts.enumerated() where i < TowerRooms.Kind.allCases.count {
                TowerRooms.furnish(TowerRooms.Kind.allCases[i], F + 1, onlyIfEmpty: true) { x, y, z, b in
                    let cx = centre.x + x, cz = centre.z + z
                    // (never in his own cells)
                    var his = false
                    if let a = avoid, Int(floor(a.x)) == cx, Int(floor(a.z)) == cz {
                        let fy: Float = Float(y)
                        his = fy > a.y - 1.5 && fy < a.y + 2
                    }
                    if let b, !his {
                        w.setBlock(cx, y, cz, b); return b
                    }
                    return w.block(cx, y, cz)
                }
            }
        }
        return true
    }
}

// The car's floor panel: the landings, top first; the one it stands at marked.
final class LiftMenu: ListMenu {
    let run: Elevators.Run
    init(game g: Game, run r: Elevators.Run) {
        run = r
        super.init("Lift", game: g)
        subtitle = "Choose a floor"
        corner = ""
    }
    var floors: [Int] { run.shaft.landings.reversed() }
    override var rows: [Row] {
        floors.map { F in
            Row(name: Elevators.name(game.world, run.shaft, F), detail: F == run.shaft.car ? "Here" : "", value: "", enabled: F != run.shaft.car, good: true)
        }
    }
    override func pressed(_ i: Int) {
        let f = floors
        guard i < f.count else { return }
        Elevators.request(game, run, f[i])
        game.closeMenu()
    }
}

extension BlockRegistry {
    func registerElevators() { Elevators.register(self) }
}

extension TextureGen {
    static func elevatorPainters(_ p: inout [String: Painter]) {
        typealias T = TextureGen
        // Diamond-tread steel.
        p["lift_car_floor"] = { x, y in
            if (x + y) % 6 == 0 && (x / 3 + y / 3) % 2 == 0 { return T.hex(0xA9B1B8) }
            return T.hex(0x5D646B, 0.93 + 0.07 * T.r(x, y, 6101))
        }
        // Lit panels in a steel grid.
        p["lift_car_ceiling"] = { x, y in
            if x % 8 == 0 || y % 8 == 0 { return T.hex(0x4A5056) }
            return T.hex(0xF4F1E2, 0.96 + 0.04 * T.r(x, y, 6102))
        }
        // Brushed steel over a dark wood rail.
        p["lift_car_wall"] = { x, y in
            if y == 9 || y == 10 { return T.hex(0x5A3A22, 0.9 + 0.1 * T.r(x, 0, 6103)) }
            return T.hex(0x9DA5AC, 0.94 + 0.06 * T.r(x / 3, y, 6104))
        }
        // The floor buttons: two columns of lit rounds on a black plate.
        p["lift_car_panel"] = { x, y in
            let bx = (x - 3) % 6, by = (y - 1) % 3
            if x >= 3 && x <= 12 && y >= 1 && y <= 14 && bx < 3 && by < 2 { return T.hex(0xF0C060) }
            return T.hex(0x1C1F23, 0.95 + 0.05 * T.r(x, y, 6105))
        }
        // A door leaf: brushed steel, a dark seam down its leading edge.
        p["lift_door"] = { x, y in
            if x == 15 { return T.hex(0x2A2E33) }
            return T.hex(0xB4BBC1, 0.93 + 0.07 * T.r(x / 2, y, 6106))
        }
        // The call box: steel plate, an up and a down arrow lit amber.
        p["lift_call"] = { x, y in
            let cx = abs(Float(x) - 7.5)
            if (y == 4 || y == 5) && cx < Float(y) - 2.5 { return T.hex(0xFFB040) }
            if (y == 10 || y == 11) && cx < 13.5 - Float(y) { return T.hex(0xFFB040) }
            return T.hex(0x7C848B, 0.95 + 0.05 * T.r(x, y, 6107))
        }
    }
}
