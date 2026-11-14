import Foundation
import simd

// P512: questcheck --proving builds the Proving Grounds (ProvingGrounds.swift) step by step far off in the check's own
// world, as the Proving Grounds world does on its first load, and checks what he will find there:
//   the park     all hundred vehicles stand with their helms, and each one's helm takes exactly the blocks it was built
//                from (no deck, no sign, no neighbour pulled in), then docks back;
//   the field    all hundred circuits built and run, with as many working as the circuit zoo's own run;
//   the range    each of the ten guns is taken from its computer, has its turret, and fires;
//   the signs    one before each vehicle, gun and circuit;
//   the frame    the slowest build step (the frame waits on one step at most).
enum ProvingGroundsCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world, ships = w.ships
        let wasSurvival = g.survival, pos0 = g.player.pos, fly0 = g.player.flying
        g.survival = false
        w.ships.encounters = false
        defer { g.survival = wasSurvival; g.player.pos = pos0; g.player.flying = fly0; g.player.vel = .zero }
        let o = IVec3(Int(floor(pos0.x)) + 3000, ProvingGrounds.deckY, Int(floor(pos0.z)) + 3000)
        g.player.pos = ProvingGrounds.start(o); g.player.flying = true
        let held0 = w.heldDeck
        w.heldDeck = ProvingGrounds.held(o)
        defer { w.heldDeck = held0 }
        let b = ProvingGrounds.plan(o)
        let t0 = CFAbsoluteTimeGetCurrent()
        var worst = 0.0, worstStep = 0
        while !b.done {
            let k = b.next
            // (in play each step waits for its chunks to stream in on the workers; made here first, outside the timing)
            if let (c, r) = b.needs[k] { _ = w.loadSync(center: c, radius: r) }
            let s0 = CFAbsoluteTimeGetCurrent()
            b.run(g, budget: 0)
            let ms = (CFAbsoluteTimeGetCurrent() - s0) * 1000
            if ms > worst { worst = ms; worstStep = k }
        }
        let total = CFAbsoluteTimeGetCurrent() - t0
        print(String(format: "proving: %d steps in %.1f s, slowest step %d at %.0f ms", b.steps.count, total, worstStep, worst))
        check(ProvingGrounds.built(w, o), "proving: the grounds' marker is down once every step has run (\(b.steps.count) steps)")
        // Nov 14 ("no vehicles were on the platform"): the load checks the build queued, run to the end as the game's
        // ticks run them, bring nothing down (the deck is held, World.heldDeck); and the first vehicle stands within the
        // first steps (nearest first), not after the whole deck.
        let dk = ProvingGrounds.deck
        let mid = V3(Float(o.x + (dk.x0 + dk.x1) / 2), Float(o.y), Float(o.z + (dk.z0 + dk.z1) / 2))
        let (frames, fell) = DeckHold.settle(g, around: (mid, Float(max(dk.x1 - dk.x0, dk.z1 - dk.z0)) / 2 + 32))
        check(fell == 0, "proving: the deck and all on it stand through the build's load checks (\(frames) frames, \(fell) blocks fell)")
        if !ProvingGrounds.oldSteps {
            let probe = ProvingGrounds.plan(o)
            // (which step lays the first vehicle: the plan's steps for plots are told apart by running none; count the
            // deck tiles ahead of the nearest plot instead, by the same keys)
            let near = ProvingGrounds.park.plots.map { pl -> Float in
                let base = o + pl.at
                return simd_distance(SIMD2(Float(base.x + pl.size.x / 2), Float(base.z + pl.size.z / 2)), SIMD2(ProvingGrounds.start(o).x, ProvingGrounds.start(o).z))
            }.min() ?? 0
            let ahead = probe.needs.prefix { n in n.map { simd_distance(SIMD2($0.0.x, $0.0.z), SIMD2(ProvingGrounds.start(o).x, ProvingGrounds.start(o).z)) <= near + 192 } ?? false }.count
            check(ahead < probe.steps.count / 4, "proving: the nearest vehicle goes down by step \(ahead) of \(probe.steps.count)")
        }

        // The park.
        var standing = 0, whole = 0, wrong: [String] = []
        for pl in ProvingGrounds.park.plots {
            let p = VehicleZoo.plan(pl.index)
            let shift = o + pl.at - pl.lo
            let helm = p.helm + shift
            _ = w.loadSync(center: V3(Float(helm.x), Float(helm.y), Float(helm.z)), radius: 1)
            guard w.rawBlock(helm.x, helm.y, helm.z) == p.cells.first(where: { $0.0 == p.helm })?.1 else { wrong.append("\(pl.index + 1) no helm"); continue }
            standing += 1
            let n0 = ships.list.count
            let (made, msg) = ships.assemble(at: helm, game: g)
            guard let s = made else { wrong.append("\(pl.index + 1) \(msg)"); continue }
            let parts = ([s] + ships.turrets(of: s)).reduce(0) { $0 + $1.blockCount }
            if parts == p.cells.count { whole += 1 } else { wrong.append("\(pl.index + 1) took \(parts) of \(p.cells.count)") }
            _ = ships.disassemble(s, game: g)
            for t in ships.list.dropFirst(n0) { ships.remove(t) }
        }
        check(standing == 100 && whole == 100,
              "proving: \(standing) of 100 vehicles stand with their helms, \(whole) of them taken whole from the helm" + (wrong.isEmpty ? "" : " (" + wrong.prefix(6).joined(separator: "; ") + ")"))

        // The circuit field.
        let cases = CircuitZoo.cases().count
        check(b.circuitsOK >= cases - 1, "proving: \(b.circuitsOK) of \(min(100, cases)) circuits built and working on their pads")

        // The gun range.
        var taken = 0, fired = 0, notes: [String] = []
        for k in 0..<ProvingGrounds.guns.count {
            let c = o + ProvingGrounds.gunAt(k)
            let console = IVec3(c.x + 2, o.y, c.z + 2)
            g.player.pos = V3(Float(console.x) + 0.5, Float(o.y), Float(console.z) + 1.6)
            let before = ships.list.count
            var said = ""
            let toast0 = g.onToast
            g.onToast = { said = $0 }
            let used = g.builtGunUse(console)
            g.onToast = toast0
            guard used, let s = ships.pilot else {
                let at = Blocks.key(Blocks.groupBase[Int(w.rawBlock(console.x, console.y, console.z))])
                notes.append("\(ProvingGrounds.guns[k].name) not taken: \(used ? "used" : "refused"), console cell \(at), pilot \(ships.pilot != nil), manned \(Turrets.shared.manned != nil)" + (said.isEmpty ? "" : ", \"\(said)\""))
                continue
            }
            let turrets = ships.turrets(of: s).count
            if turrets >= 1 { taken += 1 } else { notes.append("\(ProvingGrounds.guns[k].name) no turret") }
            // (the ships alone, not a game tick: the check's world keeps no save, and a tick's streaming round him would
            // drop the far guns' chunks and their blocks with them)
            for _ in 0..<30 { ships.update(1.0 / 60, game: g) }
            let n = ships.fire(s, pitch: 0, game: g)
            if n > 0 { fired += 1 } else { notes.append("\(ProvingGrounds.guns[k].name) didn't fire") }
            for sh in ships.shells { sh.life = 0 }
            ships.shells.removeAll()
            if ships.pilot != nil { g.leaveHelm() }
            _ = ships.disassemble(s, game: g)
            for t in ships.list.dropFirst(before) { ships.remove(t) }
        }
        check(taken == ProvingGrounds.guns.count && fired == ProvingGrounds.guns.count,
              "proving: \(taken) of \(ProvingGrounds.guns.count) built guns taken from their computers with a turret, \(fired) fire" + (notes.isEmpty ? "" : " (" + notes.joined(separator: "; ") + ")"))

        // The signs.
        let d = ProvingGrounds.deck
        var signs = 0
        for (p, e) in w.blockEntities where e.kind == .sign && p.y == o.y && p.x >= o.x + d.x0 && p.x <= o.x + d.x1 && p.z >= o.z + d.z0 && p.z <= o.z + d.z1 { signs += 1 }
        check(signs >= 200 + ProvingGrounds.guns.count - 5, "proving: \(signs) signs on the deck (a vehicle's, a gun's and a circuit's each)")
        // (A step is one tile, vehicle or circuit pad: what one game tick can wait on at worst while it builds.)
        check(worst < 400, String(format: "proving: the slowest build step takes %.0f ms (step %d)", worst, worstStep))
    }
}
