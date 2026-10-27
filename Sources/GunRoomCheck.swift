import Foundation
import simd

// P471 part 4 (Oct 26 19:53-19:56) checks, `questcheck --gunroom`: "this should be a computer room right here. There
// should be a guy in here, and you should have to get in the chair and operate the computer in order to control the
// gun"; in the Boreal blockhouse: "There's still too many gates and shit in here". A gunned Greywall tower's foot and the
// Boreal blockhouse (new ground) are gun rooms: a computer, a chair and the operator seated in it, who works the gun
// over the room. He gets up to fight a player close by; with him gone, the player sits in the chair to work the gun and
// is back in it when he leaves the gun. The blockhouse keeps one railed way down. A station's reinforcements are its
// garrison's side (Capital squads came down into a Greywall garrison: "How is everyone in here dead?").
enum GunRoomCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        built(check)
        live(g, check)
    }

    // The rooms as generated, new ground against old.
    static func built(_ check: (Bool, String) -> Void) {
        func greywall(_ p471: Bool) -> (chairs: Int, operators: Int, towers: Int) {
            let S = 100, t = Greywall.Tier.fortress, e = t.half + Greywall.margin
            var chairs = 0, ops = 0
            for cz in floorDiv(-e, CS)...floorDiv(e, CS) { for cx in floorDiv(-e, CS)...floorDiv(e, CS) {
                var buf = [BlockID](repeating: AIR, count: CS * CS * CH)
                for z in 0..<CS { for x in 0..<CS { for y in 0...S { buf[Chunk.index(x, y, z)] = STONE } } }
                buf.withUnsafeMutableBufferPointer { b in
                    var w = StructWriter(bx: cx * CS, bz: cz * CS, blocks: b.baseAddress!)
                    Greywall.build(&w, 0, S, 0, t, 4242, bank: true, p471: p471)
                    ops += w.mobs.filter { $0.0.contains(":operator") }.count
                }
                chairs += buf.filter { ChairSeat.seatTop(Blocks.key(Blocks.groupBase[Int($0)])) != nil }.count
            } }
            return (chairs, ops, t.towers.count)
        }
        let gn = greywall(true), go = greywall(false)
        check(gn.chairs == gn.towers && gn.operators == gn.towers && go.chairs == 0 && go.operators == 0,
              "gunroom: a Greywall fortress on new ground has a chair and an operator in each of its \(gn.towers) gunned towers (\(gn.chairs) chairs, \(gn.operators) operators); on old ground none (\(go.chairs), \(go.operators))")

        func boreal(_ p471: Bool) -> (bars: Int, chairs: Int, consoles: Int, operators: Int) {
            let S = 200
            let bars = Blocks.has("station_railing") ? Blocks.groupBase[Int(Blocks.id("station_railing"))] : BlockID.max
            let console = Blocks.has("command_console") ? Blocks.id("command_console") : BlockID.max
            var n = (0, 0, 0, 0)
            for cz in -3...2 { for cx in -3...2 {
                var buf = [BlockID](repeating: STONE, count: CS * CS * CH)
                for i in (CS * CS * S)..<(CS * CS * CH) { buf[i] = AIR }
                buf.withUnsafeMutableBufferPointer { b in
                    var w = StructWriter(bx: cx * CS, bz: cz * CS, blocks: b.baseAddress!)
                    BorealStation.build(&w, 0, S, 0, 77, p471: p471)
                    n.3 += w.mobs.filter { $0.0.contains(":operator") }.count
                }
                // The blockhouse (x -8...7, z 14...23), its first two rows above the floor.
                for z in 14...23 { for x in -8...7 where floorDiv(x, CS) == cx && floorDiv(z, CS) == cz {
                    for y in (S + 1)...(S + 2) {
                        let b = buf[Chunk.index(x - cx * CS, y, z - cz * CS)]
                        if Blocks.groupBase[Int(b)] == bars { n.0 += 1 }
                        if ChairSeat.seatTop(Blocks.key(Blocks.groupBase[Int(b)])) != nil { n.1 += 1 }
                        if b == console { n.2 += 1 }
                    }
                } }
            } }
            return n
        }
        let bn = boreal(true), bo = boreal(false)
        check(bn.bars * 2 < bo.bars && bn.chairs == 1 && bn.consoles >= 3 && bn.operators == 1 && bo.chairs == 0 && bo.operators == 0,
              "gunroom: the Boreal blockhouse on new ground: \(bn.bars) railing blocks (\(bo.bars) on old ground), \(bn.chairs) chair at \(bn.consoles) consoles, \(bn.operators) operator (old ground \(bo.chairs), \(bo.operators))")
    }

    // A gun room in play: a console, its chair, a gun on the roof six above, the operator.
    static func live(_ g: Game, _ check: (Bool, String) -> Void) {
        let a = PlaytestOct12Tests.arena(g, dx: -90, dz: 90, r: 12)
        let w = g.world
        let keep = g.mobs.mobs
        var placed: [(IVec3, BlockID)] = []
        func set(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) { placed.append((IVec3(x, y, z), w.block(x, y, z))); w.setBlock(x, y, z, b) }
        defer {
            if Turrets.shared.manned != nil { Turrets.shared.leave(g) }
            ChairSeat.shared.release()
            for (p, b) in placed.reversed() { w.setBlock(p.x, p.y, p.z, b) }
            a.restore(); g.mobs.mobs = keep; g.drops.items.removeAll()
        }
        let y1 = a.py + 1
        set(a.fx, y1, a.fz - 1, Blocks.id("command_console"))
        set(a.fx, y1, a.fz, Blocks.id("oak_chair"))
        for z in (a.fz - 3)...(a.fz + 3) { for x in (a.fx - 3)...(a.fx + 3) { set(x, a.py + 6, z, STONE) } }
        g.survival = true; g.player.flying = false; g.paused = false; g.menu = nil
        func hold() { g.health = 20; g.alive = true }
        hold()
        let seat = V3(Float(a.fx) + 0.5, Float(y1), Float(a.fz) + 0.5)
        guard let gun = Mob.structureMob("deck_gun", at: seat + V3(0, 6, 0)), let op = Mob.structureMob("soldier_trooper:operator^0", at: seat) else {
            check(false, "gunroom: makes a gun and an operator"); return
        }
        g.mobs.mobs = [gun, op]
        // 1. The player far off: the operator sits at the computer and the gun counts as crewed.
        g.player.pos = seat + V3(0, 60, 40); g.player.flying = true
        for _ in 0..<(3 * 72) { g.tick(1.0 / 72); hold() }
        let b = op.soldierBrain
        let sat = b.station == .seated && simd_length(V2(op.pos.x - seat.x, op.pos.z - seat.z)) < 0.2 && abs(op.pos.y - seat.y) < 0.3
        let crewed = gun.deckGunCrewed(g)
        check(sat && crewed && op.customName == "Gun Operator",
              "gunroom: the operator sits in the chair at the computer (\(b.station), \(String(format: "%.2f", simd_length(V2(op.pos.x - seat.x, op.pos.z - seat.z)))) off the seat) and the gun over him is crewed (\(crewed))")
        // 2. The player uses the computer with the operator in his chair: refused.
        var toasts: [String] = []
        let t0 = g.onToast
        g.onToast = { toasts.append($0) }
        defer { g.onToast = t0 }
        g.player.flying = false
        g.player.pos = seat + V3(1, 0, 2)
        let refused = g.stationGunUse(IVec3(a.fx, y1, a.fz - 1)) && Turrets.shared.manned == nil
        check(refused && toasts.last?.contains("operator") == true, "gunroom: with the operator in the chair the computer is refused (\"\(toasts.last ?? "-")\")")
        // 3. In the room with him: he gets up and fights.
        var up = false, fought = false
        for _ in 0..<(3 * 72) {
            g.tick(1.0 / 72); hold()
            if b.offPost > 0 && b.station == StationPose.none { up = true }
            if op.aggro && up { fought = true }
        }
        check(up && fought, "gunroom: with the player 2 blocks off the operator gets up (\(up)) and fights (\(fought))")
        // 4. Gone (killed): the player takes the chair and works the gun, and is back in the chair when he leaves it.
        op.health = 0; op.killedByPlayer = true
        g.mobDied(op)
        g.mobs.mobs.removeAll { $0 === op }
        let used = g.stationGunUse(IVec3(a.fx, y1, a.fz - 1))
        let manned = Turrets.shared.manned === gun
        let remote = Turrets.shared.remoteSeat == IVec3(a.fx, y1, a.fz)
        Turrets.shared.leave(g)
        let back = ChairSeat.shared.at == IVec3(a.fx, y1, a.fz)
        check(used && manned && remote && back,
              "gunroom: with the operator dead the computer works the gun (\(manned)) from the chair (\(remote)), and leaving the gun sits him back in it (\(back))")
        ChairSeat.shared.release()
        // 5. A save keeps the operator at his post.
        guard let op2 = Mob.structureMob("soldier_trooper:operator^0", at: seat) else { return }
        var d: [String: Float] = [:]
        op2.saveExtra(&d)
        let re = Mob(.soldierTrooper, at: seat)
        re.loadExtra(d)
        check(re.brain?.orderStation == .seated && re.brain?.gunPost != nil,
              "gunroom: the operator keeps his post through a save (station \(re.brain.map { "\($0.orderStation)" } ?? "-"))")
        // 6. A Boreal Station Greywall holds: the reinforcements coming down the stair are Greywall's (they were Capital
        // troops, who shot the garrison dead).
        let sop = StationOp(key: "gunroom", cx: a.fx, cz: a.fz, S: a.py + BorealStation.depth)
        var squads: [String] = []
        for grey in [true, false] {
            guard let g1 = Mob.structureMob("soldier_trooper" + (grey ? "@grey" : ""), at: seat),
                  let g2 = Mob.structureMob("soldier_recruit" + (grey ? "@grey" : ""), at: seat + V3(2, 0, 0)) else { return }
            g.mobs.mobs = [g1, g2]
            g.stationReinforce(sop, toward: g.player.pos)
            let new = g.mobs.mobs.dropFirst(2)
            squads.append(new.count == 3 && new.allSatisfy { $0.faction == g1.faction } ? "\(new.count) of its side" : new.map { "\($0.faction)" }.joined(separator: ","))
        }
        check(squads.allSatisfy { $0.hasSuffix("of its side") },
              "gunroom: a station's reinforcements are its garrison's side (Greywall-held: \(squads[0]); Capital: \(squads[1]))")
    }
}
