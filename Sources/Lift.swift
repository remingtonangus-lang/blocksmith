import Foundation
import simd

// P503 (Oct 31 16:20:47, at the top of a citadel's side tower, after its 37-block ladder: "Also, there should be an
// elevator"): a lift. Lift Pads stand one over another up a building, a pad set into each floor; standing on one, a jump
// rides up to the next pad above in the same column and a crouch rides down to the next below (up to 64 blocks), with
// room to stand on the pad it reaches. The ride takes him there at once, with the lift's hum and clunk. The citadels'
// side towers have a pad on every floor and the roof garden (on ground no save had before, CapitalBase.build).
enum Lift {
    static let reach = 64
    static var rides = 0                                   // (checks)
    static var sneakWas = false                            // (a crouch rides once per press)
    static var pad: BlockID? { Blocks.has("lift_pad") ? Blocks.id("lift_pad") : nil }

    // The next pad up (dir 1) or down (-1) from the pad at p, with two free cells over it.
    static func next(_ w: World, from p: IVec3, dir: Int) -> IVec3? {
        guard let pad else { return nil }
        var y = p.y + dir
        for _ in 0..<reach {
            guard y >= 1 && y < CH - 3 else { return nil }
            if w.block(p.x, y, p.z) == pad && !Blocks.collide[Int(w.block(p.x, y + 1, p.z))] && !Blocks.collide[Int(w.block(p.x, y + 2, p.z))] {
                return IVec3(p.x, y, p.z)
            }
            y += dir
        }
        return nil
    }
}

extension Game {
    // A jump (up) or a crouch (down) on a Lift Pad: true when it carried him.
    @discardableResult
    func liftRide(up: Bool) -> Bool {
        guard player.onGround, !player.flying, riding == nil, world.ships.pilot == nil, let pad = Lift.pad else { return false }
        let f = IVec3(Int(floor(player.pos.x)), Int(floor(player.pos.y - 0.1)), Int(floor(player.pos.z)))
        guard world.block(f.x, f.y, f.z) == pad, let to = Lift.next(world, from: f, dir: up ? 1 : -1) else { return false }
        let from = player.pos
        player.pos = V3(Float(to.x) + 0.5, Float(to.y + 1), Float(to.z) + 0.5)
        player.vel = .zero
        player.airPeak = player.pos.y                       // (no fall counted for the ride down)
        Lift.rides += 1
        sfx(.pistonExtend, 0.5, at: from)
        sfx(.ironDoorClose, 0.6, at: player.pos)
        return true
    }
}

extension BlockRegistry {
    func registerLift() {
        guard !has("lift_pad") else { return }
        var d = BlockDef("lift_pad", "Lift Pad")
        d.tex = ["lift_pad_side", "lift_pad_side", "lift_pad", "lift_pad_side", "lift_pad_side", "lift_pad_side"]
        d.hardness = 4; d.resistance = 30; d.tool = .pickaxe; d.requiresTool = true; d.sound = .stone; d.emit = 4
        add(d)
    }
}

extension TextureGen {
    static func liftPainters(_ p: inout [String: Painter]) {
        // The pad's top: a steel plate with hazard bands round its rim and a lit chevron pair (up and down) in its middle.
        p["lift_pad"] = { x, y in
            if x == 0 || x == 15 || y == 0 || y == 15 { return hex(0x2E3238) }
            if x <= 2 || x >= 13 || y <= 2 || y >= 13 { return (x + y) % 4 < 2 ? hex(0xD8A820) : hex(0x23262B) }
            let cx = abs(Float(x) - 7.5)
            if (y == 4 || y == 5) && cx < Float(y) - 2.5 { return hex(0x7CE0FF) }        // up
            if (y == 10 || y == 11) && cx < 13.5 - Float(y) { return hex(0x7CE0FF) }     // down
            return hex(0x6A737C, 0.94 + 0.06 * r(x, y, 5031))
        }
        p["lift_pad_side"] = { x, y in
            if y >= 13 { return (x + y) % 4 < 2 ? hex(0xD8A820) : hex(0x23262B) }
            if x == 0 || x == 15 || y == 0 { return hex(0x30353C) }
            return hex(0x5E666F, 0.95 + 0.05 * r(x, y, 5032))
        }
    }
}

// P503's checks (questcheck --lift, and the full suite): a jump on a pad rides to the next pad up, past one with no room
// over it, a crouch back down, and nothing above the top pad; a citadel built on new ground has its four gun rooms (a
// console, a chair and an operator under each barbette's and side tower's gun) and a Lift Pad in every floor of its side
// towers; on ground saved before, none of them.
enum LiftCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let a = PlaytestOct12Tests.arena(g, dx: -70, dz: 70, r: 3)
        let w = g.world
        var placed: [(IVec3, BlockID)] = []
        func set(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) { placed.append((IVec3(x, y, z), w.block(x, y, z))); w.setBlock(x, y, z, b) }
        let fly0 = g.player.flying, pos0 = g.player.pos
        defer { for (p, b) in placed.reversed() { w.setBlock(p.x, p.y, p.z, b) }; a.restore(); g.player.flying = fly0; g.player.pos = pos0 }
        guard let pad = Lift.pad else { check(false, "lift: no Lift Pad block"); return }
        for k in 0...3 { set(a.fx, a.py + 6 * k, a.fz, pad) }
        set(a.fx, a.py + 7, a.fz, STONE)                        // (the second pad has no room over it)
        g.player.flying = false
        func ride(_ up: Bool) -> Int {
            g.player.onGround = true; g.player.vel = .zero
            _ = g.liftRide(up: up)
            return Int(floor(g.player.pos.y)) - a.py - 1
        }
        g.player.pos = V3(Float(a.fx) + 0.5, Float(a.py + 1), Float(a.fz) + 0.5)
        let up1 = ride(true), up2 = ride(true), top = ride(true), down = ride(false)
        g.player.pos = V3(Float(a.fx) + 2.5, Float(a.py + 1), Float(a.fz) + 0.5)
        let off = ride(true)
        check(up1 == 12 && up2 == 18 && top == 18 && down == 12 && off == 0,
              "lift: a jump on a pad rides up past a pad with no room over it (\(up1) up, 12 wanted), on to the top (\(up2), 18), no further (\(top)); a crouch rides down (\(down), 12); off a pad nothing (\(off))")
        // The citadel, on new ground and on ground saved before P503.
        func citadel(_ rooms: Bool) -> (mobs: [String: Int], built: [String: Int], seated: Int) {
            var mobs: [String: Int] = [:], built: [String: Int] = [:]
            var consoles: [IVec3] = [], chairs = Set<IVec3>()
            for cz in -4...3 { for cx in -4...3 {
                var blocks = [BlockID](repeating: AIR, count: CS * CS * CH)
                for y in 0..<99 { for zz in 0..<CS { for xx in 0..<CS { blocks[Chunk.index(xx, y, zz)] = STONE } } }
                blocks.withUnsafeMutableBufferPointer { buf in
                    var sw = StructWriter(bx: cx * CS, bz: cz * CS, blocks: buf.baseAddress!)
                    CapitalBase.build(&sw, 0, 100, 0, 12345, gunRooms: rooms)
                    for (k, _) in sw.mobs { mobs[k, default: 0] += 1 }
                }
                for (i, b) in blocks.enumerated() where b != AIR && b != STONE {
                    let k = Blocks.key(Blocks.groupBase[Int(b)])
                    built[k, default: 0] += 1
                    let q = IVec3(cx * CS + i % CS, i / (CS * CS), cz * CS + (i / CS) % CS)
                    if k == "command_console" { consoles.append(q) } else if k == "oak_chair" { chairs.insert(q) }
                }
            } }
            // (consoles with a chair beside them: a citadel's command desks have them too)
            let seated = consoles.filter { c in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)].contains { chairs.contains(c + $0) } }.count
            return (mobs, built, seated)
        }
        let new = citadel(true), old = citadel(false)
        let ops = new.mobs.filter { $0.key.hasPrefix("soldier_trooper:operator") }.values.reduce(0, +)
        let consoles = (new.built["command_console"] ?? 0) - (old.built["command_console"] ?? 0)
        let chairs = new.seated - old.seated
        let oldOps = old.mobs.filter { $0.key.hasPrefix("soldier_trooper:operator") }.count
        check(ops == 4 && consoles == 4 && chairs == 4 && new.built["lift_pad"] == 14 && oldOps == 0 && old.built["lift_pad"] == nil,
              "lift: a citadel on new ground has 4 gun rooms (\(consoles) consoles, \(chairs) chairs, \(ops) operators) and \(new.built["lift_pad"] ?? 0) Lift Pads (14); on old ground \(oldOps) operators and \(old.built["lift_pad"] ?? 0) pads")
    }
}
