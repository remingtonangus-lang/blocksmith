import Foundation
import simd

// P370 (b, Oct 18 07:59: "why are the people sitting down? we should have chairs... add actual chairs"): chairs, benches
// and stools in every wood. They are crafted and placed like any block (a chair and a bench turn their front toward
// whoever places them), and using one sits on it: the player drops onto the seat facing out, and sneaking, jumping or
// walking off stands him up in front of it. Towns furnish their tables, desks, parlours and the saloon with them in
// place of the stairs and slabs that stood in for seats.
extension BlockRegistry {
    // Turn a box drawn for facing 0 (front toward -Z, back toward +Z) to facing k (0 north, 1 south, 2 west, 3 east).
    static func turnBox(_ bx: Box, _ k: Int) -> Box {
        func turn(_ x: Int, _ z: Int) -> (Int, Int) {
            switch k { case 1: return (16 - x, 16 - z); case 2: return (z, 16 - x); case 3: return (16 - z, x); default: return (x, z) }
        }
        let a = turn(Int(bx.x0), Int(bx.z0)), c = turn(Int(bx.x1), Int(bx.z1))
        return Box(min(a.0, c.0), Int(bx.y0), min(a.1, c.1), max(a.0, c.0), Int(bx.y1), max(a.1, c.1), tex: bx.tex)
    }

    func registerSeats() {
        let dirs = ["north", "south", "west", "east"]
        for w in BlockRegistry.doorWoods where has("\(w)_planks") {
            let wood = BlockRegistry.woodName(w)
            func def(_ name: String, _ disp: String, _ boxes: [Box], group: String, hidden: Bool) -> BlockDef {
                var s = BlockDef(name, disp)
                s.tex = ["\(w)_planks"]; s.render = .model; s.opaque = false; s.boxes = boxes
                s.hardness = 2; s.tool = .axe; s.sound = .wood; s.group = group; s.hidden = hidden; s.skyStop = false
                return s
            }
            // Chair: four legs, a seat at 9/16, a slatted back.
            let chair = [Box(3, 0, 3, 5, 8, 5), Box(11, 0, 3, 13, 8, 5), Box(3, 0, 11, 5, 8, 13), Box(11, 0, 11, 13, 8, 13),
                         Box(2, 8, 2, 14, 10, 14), Box(3, 10, 11, 5, 16, 13), Box(11, 10, 11, 13, 16, 13),
                         Box(3, 14, 11, 13, 16, 13), Box(5, 11, 12, 11, 13, 13)]
            // Bench: a long plank seat at 8/16 on two trestles, open front and back.
            let bench = [Box(0, 6, 3, 16, 8, 13), Box(1, 0, 4, 3, 6, 12), Box(13, 0, 4, 15, 6, 12), Box(3, 2, 7, 13, 3, 9)]
            for (k, dir) in dirs.enumerated() {
                let cn = "\(w)_chair", bn = "\(w)_bench"
                add(def(k == 0 ? cn : "\(cn)[\(dir)]", "\(wood) Chair", chair.map { BlockRegistry.turnBox($0, k) }, group: cn, hidden: k != 0))
                add(def(k == 0 ? bn : "\(bn)[\(dir)]", "\(wood) Bench", bench.map { BlockRegistry.turnBox($0, k) }, group: bn, hidden: k != 0))
            }
            // Stool: three splayed legs and a round-ish top at 10/16.
            let stool = [Box(4, 8, 4, 12, 10, 12), Box(3, 8, 5, 13, 10, 11), Box(5, 8, 3, 11, 10, 13),
                         Box(4, 0, 4, 6, 8, 6), Box(10, 0, 4, 12, 8, 6), Box(7, 0, 10, 9, 8, 12), Box(5, 3, 5, 11, 4, 11)]
            add(def("\(w)_stool", "\(wood) Stool", stool, group: "\(w)_stool", hidden: false))
        }
    }
}

// The player on a seat.
final class ChairSeat {
    static let shared = ChairSeat()
    private(set) var at: IVec3?
    private var ready = false                  // the use press that sat him down has been let go
    static var sat = 0                         // (checks)

    // How high the seat's top is (blocks), for a chair, bench or stool key; nil for anything else.
    static func seatTop(_ key: String) -> Float? {
        if key.hasSuffix("_chair") { return 10 / 16 }
        if key.hasSuffix("_bench") { return 8 / 16 }
        if key.hasSuffix("_stool") { return 10 / 16 }
        return nil
    }
    static func key(_ w: World, _ p: IVec3) -> String { Blocks.key(Blocks.groupBase[Int(w.materialAt(p.x, p.y, p.z))]) }

    // The way a seat's sitter faces (yaw), from its facing state (0 north ... 3 east; a stool: as he came).
    static func facingYaw(_ w: World, _ p: IVec3, else yaw: Float) -> Float {
        let b = w.block(p.x, p.y, p.z)
        let k = key(w, p)
        guard !k.hasSuffix("_stool") else { return yaw }
        // Front toward -Z (north) means facing -Z: yaw 0 looks -Z (Player.look = (-sin yaw, ., -cos yaw)).
        return [0, Float.pi, Float.pi / 2, -Float.pi / 2][Int(b - Blocks.groupBase[Int(b)]) & 3]
    }

    func sit(_ g: Game, _ p: IVec3) {
        guard g.riding == nil, ChairSeat.seatTop(ChairSeat.key(g.world, p)) != nil else { return }
        // Nothing solid over the seat (a chair under a slab is still a chair; a block on it is not).
        guard !g.world.solidAt(p.x, p.y + 1, p.z) else { return }
        at = p
        ready = false
        g.player.yaw = ChairSeat.facingYaw(g.world, p, else: g.player.yaw)
        g.player.vel = .zero
        g.sfx(.place(.wood), 0.5, at: V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5))
        ChairSeat.sat += 1
    }

    // Once a frame (Game.tick, before movement): true while seated (movement is skipped).
    func tick(_ g: Game, _ mi: MoveInput) -> Bool {
        guard let p = at else { return false }
        let w = g.world
        guard g.alive, g.riding == nil, let top = ChairSeat.seatTop(ChairSeat.key(w, p)) else { at = nil; return false }
        let still = !mi.jump && !mi.sneak && abs(mi.forward) < 0.5 && abs(mi.strafe) < 0.5
        if !still && ready { stand(g); return false }
        if still { ready = true }
        // Hips on the seat: the feet point sits below the seat top so the eyes are at a seated height.
        g.player.pos = V3(Float(p.x) + 0.5, Float(p.y) + top - 0.55, Float(p.z) + 0.5)
        g.player.vel = .zero
        g.player.onGround = true
        g.player.airPeak = g.player.pos.y
        return true
    }

    // Up and a step out in front of the seat (onto it when the front is blocked).
    func stand(_ g: Game) {
        guard let p = at else { return }
        at = nil
        let w = g.world
        let yaw = ChairSeat.facingYaw(w, p, else: g.player.yaw)
        let f = IVec3(p.x + Int((-sinf(yaw)).rounded()), p.y, p.z + Int((-cosf(yaw)).rounded()))
        let open = !w.solidAt(f.x, f.y, f.z) && !w.solidAt(f.x, f.y + 1, f.z)
        g.player.pos = open ? V3(Float(f.x) + 0.5, Float(f.y), Float(f.z) + 0.5) : V3(Float(p.x) + 0.5, Float(p.y) + 1, Float(p.z) + 0.5)
        g.player.vel = .zero
        g.player.airPeak = g.player.pos.y
    }
}
