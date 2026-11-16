import Foundation
import simd

// Fable's set from the Nov 15 evening playtest (docs/playtests/2026-11-15/voice-notes.md, build 39e0d988): the checks
// for ledger rows 190 on. The map pin's checks are in PlaytestOct12Tests.mapClickPin (beside the P73 ones) and the
// laser press's in the suite (quest/src/headless/main.swift, PullAim).
enum Nov15EveningChecks {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        attachPin(g, check)
        shipChair(g, check)
    }

    // Ledger 196 (21:14:15, "Why can't I get in this chair?"): a chair on a craft's deck seats him, holds him on it as the
    // craft moves and turns, and a step stands him up beside it on the deck.
    static func shipChair(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let pos0 = g.player.pos, yaw0 = g.player.yaw
        let s = w.ships.spawn(AshWrecks.salvagedFighter(), at: g.player.pos + V3(0, 12, 30), yaw: 0, name: "Seat Test", role: "capplane")
        defer { ChairSeat.shared.release(); w.ships.remove(s, turrets: false); g.player.pos = pos0; g.player.yaw = yaw0; g.player.vel = .zero }
        // A deck cell with air over it, and a chair on it.
        var seat: IVec3?
        let g0 = s.grid
        search: for y in stride(from: g0.sy - 1, through: 1, by: -1) { for z in 1..<(g0.sz - 1) { for x in 1..<(g0.sx - 1) {
            if Blocks.collide[Int(g0.get(x, y, z))] && g0.get(x, y + 1, z) == AIR && g0.get(x, y + 2, z) == AIR { seat = IVec3(x, y + 1, z); break search }
        } } }
        guard let c = seat, Blocks.has("oak_chair") else { check(false, "Ledger 196 ship chair: no deck cell on the test craft"); return }
        w.ships.setBlock(s, c, Blocks.id("oak_chair") + 1)              // facing south
        let sat = ChairSeat.shared.sitShip(g, s, c)
        var mi = MoveInput()
        _ = ChairSeat.shared.tick(g, mi)
        let on0 = simd_length(g.player.pos - ChairSeat.shipSeatPos(s, c, top: 10 / 16))
        // The craft moves 6 blocks and turns a quarter: he stays on the seat.
        s.pos += V3(6, 0, -2)
        s.rot = simd_quatf(angle: .pi / 2, axis: V3(0, 1, 0)) * s.rot
        _ = ChairSeat.shared.tick(g, mi)
        let on1 = simd_length(g.player.pos - ChairSeat.shipSeatPos(s, c, top: 10 / 16))
        let held = ChairSeat.shared.seatedOnShip
        mi.forward = 1
        _ = ChairSeat.shared.tick(g, mi)
        let up = !ChairSeat.shared.seatedOnShip
        let off = simd_length(g.player.pos - s.toWorld(V3(Float(c.x), Float(c.y), Float(c.z)) + 0.5))
        check(sat && on0 < 0.01 && held && on1 < 0.01 && up && off < 1.8,
              "Ledger 196 ship chair: a chair on a craft's deck seats him (\(sat)), he stays on it as the craft moves 6 and turns 90 (\(String(format: "%.3f", on1)) off), and a step stands him up beside it (\(up), \(String(format: "%.2f", off)) from it)")
    }

    // Ledger 191 (20:45:34, "the wire is not perfectly flush with material under it"): copper wire on a natural block at
    // the corner of a 3x3 stone pad in the air: the block's four top corners stay on its flat top (pinned), while the
    // pad's opposite corner block, bare, rounds away (so the check means something).
    static func attachPin(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, was = SmoothTerrain.enabled, field0 = SmoothTerrain.fromField
        SmoothTerrain.enabled = true; SmoothTerrain.fromField = false
        defer { SmoothTerrain.enabled = was; SmoothTerrain.fromField = field0 }
        let p0 = g.player.pos
        let x0 = (Int(floor(p0.x)) & ~15) + 8, z0 = (Int(floor(p0.z)) & ~15) + 8       // mid-chunk: no neighbour sections
        _ = w.loadSync(center: V3(Float(x0), p0.y, Float(z0)), radius: 1)
        let y0 = min(CH - 40, ((w.topY(x0, z0) + 24) & ~15) + 7)                           // mid-section
        let stone = Blocks.id("stone"), wire = Blocks.id("redstone_wire")
        var placed: [IVec3] = []
        for dz in -1...1 { for dx in -1...1 { w.setBlock(x0 + dx, y0, z0 + dz, stone); placed.append(IVec3(x0 + dx, y0, z0 + dz)) } }
        w.setBlock(x0 - 1, y0 + 1, z0 - 1, wire); placed.append(IVec3(x0 - 1, y0 + 1, z0 - 1))
        defer { for q in placed.reversed() { w.setBlock(q.x, q.y, q.z, AIR) } }
        var cells: [SIMD3<Int>: SIMD3<Float>] = [:]
        SmoothTerrain.vertexHook = { a, b, c, p in cells[SIMD3<Int>(a, b, c)] = p }
        if let ch = w.chunkAt(x0, z0), let nb = w.neighbourhood(ch) { _ = Mesher.buildSection(nb.0, nb.1, sy: y0 >> 4) }
        SmoothTerrain.vertexHook = nil
        // The dual cell of the corner (x, y, z) is (x - 1, y - 1, z - 1), section-local.
        func cornerY(_ x: Int, _ z: Int) -> Float? {
            cells[SIMD3<Int>(mod(x, CS) - 1, mod(y0 + 1, 16) - 1, mod(z, CS) - 1)].map { $0.y - Float(mod(y0 + 1, 16)) }
        }
        let wired = [(x0 - 1, z0 - 1), (x0, z0 - 1), (x0 - 1, z0), (x0, z0)].map { cornerY($0.0, $0.1) }
        let bare = cornerY(x0 + 2, z0 + 2)
        let flush = wired.allSatisfy { $0 != nil && abs($0!) < 1e-4 }
        let rounds = (bare ?? 0) < -0.05
        func f(_ v: Float?) -> String { v.map { String(format: "%.3f", $0) } ?? "none" }
        check(flush && rounds,
              "Ledger 191 wire flush: copper wire on a natural block at a pad's corner keeps its four top corners on the block's top (\(wired.map(f).joined(separator: ", ")) blocks off); the bare far corner rounds (\(f(bare)))")
    }
}
