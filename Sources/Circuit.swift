import Foundation
import simd

// Sparkstone: power levels 0-15 following the reference game's rules.
//  - Sources: levers, buttons, pressure plates, sparkstone torches (inverters with 1-tick delay and
//    burnout), sparkstone blocks, observers, daylight detectors, targets, repeaters, comparators.
//  - Solid opaque blocks conduct: strongly powered by an adjacent source's strong output (levers/
//    buttons/plates into what they sit on, torches upward, repeaters/comparators/observers forward),
//    weakly powered by dust pointing into them. Weak power drives components but not dust.
//  - Dust networks are solved as a whole: each wire takes the best of its external input and its
//    neighbours' level minus one; changed wires wake the blocks around them.
//  - Consumers: lamps, pistons/sticky pistons (quasi-connectivity, 12-block push limit, slime/honey
//    groups), doors/trapdoors/gates, TNT, dispensers/droppers, note blocks, hoppers (locking), bells.
// Everything runs on the 20 Hz game tick; delays are in game ticks (1 sparkstone tick = 2).
final class Circuit {
    unowned let w: World
    weak var game: Game?
    private(set) var now = 0
    private var scheduled: [(at: Int, p: IVec3)] = []
    private var scheduledSet = Set<IVec3>()
    private var dirty: [IVec3] = []
    private var dirtySet = Set<IVec3>()
    private var settledWires = Set<IVec3>()
    var comparatorOut: [IVec3: Int] = [:]
    var trapped: [IVec3: Int] = [:]                 // trapped chests: players looking inside
    var sensor: [IVec3: (Int, Int)] = [:]           // murk sensors: (output, until tick)
    private var edge = Set<IVec3>()                  // components currently seeing power (edge detection)
    private var burn: [IVec3: [Int]] = [:]           // torch toggle times (burnout)
    var tracked = Set<IVec3>()                        // hoppers, plates, daylight detectors (periodic work)
    private var hopperCooldown: [IVec3: Int] = [:]
    private var busy = false

    init(world: World) { w = world }

    // MARK: Kinds

    enum K: UInt8 {
        case none, wire, torch, block, lamp, lever, button, plate, weightedPlate, repeater, comparator, observer, piston, stickyPiston
        case dispenser, dropper, hopper, note, daylight, target, door, trapdoor, gate, tnt, pistonHead, bell, ironDoor, ironTrapdoor
        case rail, poweredRail, detectorRail, activatorRail
        case tripHook, trappedChest, copperBulb, crafter, sculkSensor
    }

    static let kinds: [K] = {
        var t = [K](repeating: .none, count: Blocks.count)
        func set(_ group: String, _ k: K) {
            guard Blocks.has(group) else { return }
            let base = Int(Blocks.groupBase[Int(Blocks.id(group))])
            for i in base..<Blocks.count where Int(Blocks.groupBase[i]) == base { t[i] = k }
        }
        set("redstone_wire", .wire); set("redstone_torch", .torch); set("redstone_block", .block); set("redstone_lamp", .lamp)
        set("lever", .lever); set("stone_button", .button); set("polished_blackstone_button", .button)
        for w in BlockRegistry.buttonWoods { set("\(w)_button", .button); set("\(w)_pressure_plate", .plate) }
        set("stone_pressure_plate", .plate); set("polished_blackstone_pressure_plate", .plate)
        set("light_weighted_pressure_plate", .weightedPlate); set("heavy_weighted_pressure_plate", .weightedPlate)
        set("repeater", .repeater); set("comparator", .comparator); set("observer", .observer)
        set("piston", .piston); set("sticky_piston", .stickyPiston); set("piston_head", .pistonHead)
        set("dispenser", .dispenser); set("dropper", .dropper); set("hopper", .hopper); set("note_block", .note)
        set("daylight_detector", .daylight); set("target", .target); set("tnt", .tnt); set("bell", .bell)
        for w in BlockRegistry.doorWoods { set("\(w)_door", .door); set("\(w)_trapdoor", .trapdoor); set("\(w)_fence_gate", .gate) }
        set("iron_door", .ironDoor); set("iron_trapdoor", .ironTrapdoor)
        set("crafter", .crafter); set("sculk_sensor", .sculkSensor); set("calibrated_sculk_sensor", .sculkSensor)
        set("tripwire_hook", .tripHook); set("trapped_chest", .trappedChest)
        for i in 1..<Blocks.count where Int(Blocks.groupBase[i]) == i && Blocks.key(BlockID(i)).hasSuffix("copper_bulb") { set(Blocks.key(BlockID(i)), .copperBulb) }
        set("rail", .rail); set("powered_rail", .poweredRail); set("detector_rail", .detectorRail); set("activator_rail", .activatorRail)
        return t
    }()
    @inline(__always) static func kind(_ b: BlockID) -> K { kinds[Int(b)] }
    @inline(__always) func st(_ b: BlockID) -> Int { Int(b - Blocks.groupBase[Int(b)]) }
    @inline(__always) func base(_ b: BlockID) -> BlockID { Blocks.groupBase[Int(b)] }
    static let opp = [1, 0, 3, 2, 5, 4]
    static let D = BlockRegistry.dir6
    // facing (0 N, 1 S, 2 W, 3 E) -> dir6
    @inline(__always) static func d6(_ f: Int) -> Int { f + 2 }

    func block(_ p: IVec3) -> BlockID { w.block(p.x, p.y, p.z) }
    // Full opaque cubes conduct power.
    func conductor(_ b: BlockID) -> Bool { Blocks.opaque[Int(b)] && Circuit.kind(b) == .none && b != AIR }

    // MARK: Change notifications (from World)

    func blockChanged(_ p: IVec3, _ old: BlockID, _ new: BlockID) {
        mark(p)
        for d in 0..<6 { mark(p + Circuit.D[d]) }
        // Dust climbing slopes and blocks the dust points into two steps away.
        if Circuit.kind(old) == .wire || Circuit.kind(new) == .wire || conductor(old) || conductor(new) {
            for d in 2..<6 {
                let n = p + Circuit.D[d]
                mark(n + IVec3(0, 1, 0)); mark(n + IVec3(0, -1, 0))
                for e in 0..<6 { mark(n + Circuit.D[e]) }
            }
            mark(p + IVec3(0, 2, 0)); mark(p + IVec3(0, -2, 0))
        }
        // Observers watching this position.
        for d in 0..<6 {
            let n = p + Circuit.D[d]
            let b = block(n)
            if Circuit.kind(b) == .observer {
                let s = st(b)
                let face = s % 6
                if n + Circuit.D[face] == p && s < 6 { schedule(n, 2) }
            }
        }
        let k = Circuit.kind(new)
        if k == .hopper || k == .plate || k == .weightedPlate || k == .daylight || k == .detectorRail || k == .tripHook || k == .sculkSensor { tracked.insert(p) }
        else if tracked.contains(p) { tracked.remove(p) }
        settledWires.remove(p)
    }

    func mark(_ p: IVec3) {
        guard p.y >= 0 && p.y < CH else { return }
        let b = block(p)
        let k = Circuit.kind(b)
        if k == .none && !conductor(b) { return }
        if dirtySet.insert(p).inserted { dirty.append(p) }
    }

    func schedule(_ p: IVec3, _ delay: Int) {
        guard !scheduledSet.contains(p) else { return }
        scheduledSet.insert(p)
        scheduled.append((now + max(1, delay), p))
    }

    // Registers periodic components of a chunk that just arrived.
    func chunkLoaded(_ c: Chunk) {
        let bx = c.cx * CS, bz = c.cz * CS
        for i in 0..<c.blocks.count {
            let k = Circuit.kind(c.blocks[i])
            if k == .hopper || k == .daylight || k == .plate || k == .weightedPlate || k == .detectorRail || k == .tripHook || k == .sculkSensor {
                tracked.insert(IVec3(bx + (i & 15), i >> 8, bz + ((i >> 4) & 15)))
            }
        }
    }

    // MARK: Power queries

    // Strong power the component at q emits into its neighbour in direction d (q -> q + D[d]).
    func strongOut(_ q: IVec3, _ d: Int) -> Int {
        let b = block(q)
        let s = st(b)
        switch Circuit.kind(b) {
        case .lever, .button:
            guard s >= 12 else { return 0 }
            return d == attachedDir(s) ? 15 : 0
        case .plate: return s > 0 && d == 0 ? 15 : 0
        case .weightedPlate: return d == 0 ? s : 0
        case .torch:
            let lit = s == 0 || (s >= 2 && s < 6)
            return lit && d == 1 ? 15 : 0
        case .repeater: return (s & 16) != 0 && d == Circuit.d6(s & 3) ? 15 : 0
        case .comparator: return d == Circuit.d6(s & 3) ? (comparatorOut[q] ?? 0) : 0
        case .observer: return s >= 6 && d == Circuit.opp[s % 6] ? 15 : 0
        case .detectorRail: return s >= 6 && d == 0 ? 15 : 0
        case .tripHook: return s >= 4 && d == Circuit.opp[Circuit.d6(s & 3)] ? 15 : 0
        case .trappedChest: return d == 0 ? (trapped[q] ?? 0) : 0
        default: return 0
        }
    }

    // Power a source/component at q provides to an adjacent component or dust at q + D[d].
    func sourceOut(_ q: IVec3, _ d: Int) -> Int {
        let b = block(q)
        let s = st(b)
        switch Circuit.kind(b) {
        case .lever, .button: return s >= 12 ? 15 : 0
        case .plate: return s > 0 ? 15 : 0
        case .weightedPlate, .target: return s
        case .daylight: return s & 15
        case .block: return 15
        case .torch:
            let lit = s == 0 || (s >= 2 && s < 6)
            guard lit else { return 0 }
            let attached = s < 2 ? 0 : Circuit.opp[Circuit.d6((s - 2) % 4)]
            return d == attached ? 0 : 15
        case .repeater: return (s & 16) != 0 && d == Circuit.d6(s & 3) ? 15 : 0
        case .comparator: return d == Circuit.d6(s & 3) ? (comparatorOut[q] ?? 0) : 0
        case .observer: return s >= 6 && d == Circuit.opp[s % 6] ? 15 : 0
        case .wire: return (d == 0 || wirePoints(q, d)) ? s : 0
        case .detectorRail: return s >= 6 ? 15 : 0
        case .tripHook: return s >= 4 ? 15 : 0
        case .sculkSensor: return sensor[q]?.0 ?? 0
        case .trappedChest: return trapped[q] ?? 0
        default: return 0
        }
    }

    // (strong, weak) power of a conductor block.
    func blockPower(_ q: IVec3) -> (Int, Int) {
        var strong = 0, weak = 0
        for d in 0..<6 {
            let n = q + Circuit.D[d]
            let nb = block(n)
            let k = Circuit.kind(nb)
            if k == .none { continue }
            strong = max(strong, strongOut(n, Circuit.opp[d]))
            if k == .wire {
                let lv = st(nb)
                if lv > 0 && (d == 1 || wirePoints(n, Circuit.opp[d])) { weak = max(weak, lv) }
            }
        }
        return (strong, max(strong, weak))
    }

    // Power arriving at a component at p from direction d.
    func powerFrom(_ p: IVec3, _ d: Int, forWire: Bool = false) -> Int {
        let q = p + Circuit.D[d]
        let b = block(q)
        if Circuit.kind(b) != .none { return Circuit.kind(b) == .wire && forWire ? 0 : sourceOut(q, Circuit.opp[d]) }
        if conductor(b) { let bp = blockPower(q); return forWire ? bp.0 : bp.1 }
        return 0
    }

    func received(_ p: IVec3, except: Set<Int> = []) -> Int {
        var best = 0
        for d in 0..<6 where !except.contains(d) { best = max(best, powerFrom(p, d)) }
        return best
    }

    // Lever/button: direction from the switch to the block it is mounted on.
    func attachedDir(_ s: Int) -> Int {
        let attach = (s % 12) / 4, f = s % 4
        if attach == 0 { return 0 }
        if attach == 2 { return 1 }
        return Circuit.opp[Circuit.d6(f)]
    }

    // MARK: Dust

    // Does the component at n make adjacent dust (in direction d from the dust) connect?
    func connectsDust(_ n: IVec3, _ d: Int) -> Bool {
        let b = block(n)
        let s = st(b)
        switch Circuit.kind(b) {
        case .wire, .torch, .block, .lever, .button, .plate, .weightedPlate, .target, .daylight, .comparator, .detectorRail, .tripHook, .trappedChest, .sculkSensor: return true
        case .repeater: return (Circuit.d6(s & 3) / 2) == d / 2
        case .observer: return s % 6 == d        // only its output (back) side, which faces the dust
        default: return false
        }
    }

    // Horizontal directions this wire connects to (including slopes up/down).
    func wireConnections(_ q: IVec3) -> [Int] {
        var out: [Int] = []
        let aboveSolid = conductor(block(q + IVec3(0, 1, 0)))
        for d in 2..<6 {
            let n = q + Circuit.D[d]
            let nb = block(n)
            if connectsDust(n, d) { out.append(d); continue }
            if !conductor(nb) && Circuit.kind(block(n + IVec3(0, -1, 0))) == .wire { out.append(d); continue }
            if conductor(nb) && !aboveSolid && Circuit.kind(block(n + IVec3(0, 1, 0))) == .wire { out.append(d) }
        }
        return out
    }

    func wirePoints(_ q: IVec3, _ d: Int) -> Bool {
        if d == 0 { return true }
        if d == 1 { return false }
        let c = wireConnections(q)
        if c.isEmpty { return true }
        if c.contains(d) { return true }
        return c.count == 1 && Circuit.opp[c[0]] == d
    }

    // Wires directly linked to q (same level, one up, one down).
    private func wireNeighbours(_ q: IVec3) -> [IVec3] {
        var out: [IVec3] = []
        let aboveSolid = conductor(block(q + IVec3(0, 1, 0)))
        for d in 2..<6 {
            let n = q + Circuit.D[d]
            let nb = block(n)
            if Circuit.kind(nb) == .wire { out.append(n); continue }
            if !conductor(nb) {
                let dn = n + IVec3(0, -1, 0)
                if Circuit.kind(block(dn)) == .wire { out.append(dn) }
            } else if !aboveSolid {
                let up = n + IVec3(0, 1, 0)
                if Circuit.kind(block(up)) == .wire { out.append(up) }
            }
        }
        return out
    }

    private func solveWires(from start: IVec3) {
        var net: [IVec3] = [start]
        var seen: Set<IVec3> = [start]
        var i = 0
        while i < net.count && net.count < 4096 {
            for n in wireNeighbours(net[i]) where seen.insert(n).inserted { net.append(n) }
            i += 1
        }
        // External input for each wire, then relax levels downward from the strongest.
        var level: [IVec3: Int] = [:]
        var buckets = [[IVec3]](repeating: [], count: 16)
        for q in net {
            var e = 0
            for d in 0..<6 { e = max(e, powerFrom(q, d, forWire: true)) }
            level[q] = e
            if e > 0 { buckets[e].append(q) }
        }
        for lv in stride(from: 15, to: 1, by: -1) {
            var k = 0
            while k < buckets[lv].count {
                let q = buckets[lv][k]
                k += 1
                guard level[q] == lv else { continue }
                for n in wireNeighbours(q) where (level[n] ?? 0) < lv - 1 {
                    level[n] = lv - 1
                    buckets[lv - 1].append(n)
                }
            }
        }
        for q in net {
            settledWires.insert(q)
            let b = block(q)
            let lv = level[q] ?? 0
            if st(b) != lv {
                setQuiet(q, base(b) + BlockID(lv))
                // Wake everything the wire can affect: neighbours and what they touch.
                for d in 0..<6 {
                    let n = q + Circuit.D[d]
                    if Circuit.kind(block(n)) != .wire { mark(n) }
                    if conductor(block(n)) { for e in 0..<6 { let m = n + Circuit.D[e]; if Circuit.kind(block(m)) != .wire { mark(m) } } }
                }
            }
        }
    }

    // Change a block without re-notifying the sparkstone engine for that position itself.
    func setQuiet(_ p: IVec3, _ b: BlockID) {
        busy = true
        w.setBlockAsync(p.x, p.y, p.z, b)
        busy = false
        // Observers still see it.
        for d in 0..<6 {
            let n = p + Circuit.D[d]
            let nb = block(n)
            if Circuit.kind(nb) == .observer {
                let s = st(nb)
                if n + Circuit.D[s % 6] == p && s < 6 { schedule(n, 2) }
            }
        }
    }
    var isBusy: Bool { busy }

    // MARK: Tick

    func tick() {
        now += 1
        settledWires.removeAll(keepingCapacity: true)
        // Scheduled events due now.
        if !scheduled.isEmpty {
            let due = scheduled.filter { $0.at <= now }
            scheduled.removeAll { $0.at <= now }
            for e in due { scheduledSet.remove(e.p) }
            for e in due { fire(e.p) }
        }
        var n = 0
        while !dirty.isEmpty && n < 20000 {
            let p = dirty.removeFirst()
            dirtySet.remove(p)
            update(p)
            n += 1
        }
        periodic()
    }

    private func update(_ p: IVec3) {
        let b = block(p)
        let s = st(b)
        switch Circuit.kind(b) {
        case .wire:
            if !settledWires.contains(p) { solveWires(from: p) }
        case .torch:
            let attached = s < 2 ? IVec3(0, -1, 0) : Circuit.D[Circuit.opp[Circuit.d6((s - 2) % 4)]]
            let q = p + attached
            let powered = conductor(block(q)) ? blockPower(q).1 > 0 : false
            let lit = s == 0 || (s >= 2 && s < 6)
            if lit == powered { schedule(p, 2) }
        case .copperBulb:
            // Toggles on each rising edge of power.
            let powered = received(p) > 0
            if powered && !edge.contains(p) { edge.insert(p); setQuiet(p, base(b) + BlockID(1 - s)); wakeAround(p) }
            else if !powered { edge.remove(p) }
        case .lamp:
            let powered = received(p) > 0
            if powered && s == 0 { setQuiet(p, base(b) + 1); wakeAround(p) }
            else if !powered && s == 1 { schedule(p, 4) }
        case .repeater:
            let f = s & 3, locked = lockInput(p, f)
            if locked != ((s & 32) != 0) { setQuiet(p, base(b) + BlockID((s & 31) | (locked ? 32 : 0))) }
            if locked { return }
            let input = powerFrom(p, Circuit.opp[Circuit.d6(f)]) > 0
            let powered = (s & 16) != 0
            if input != powered { schedule(p, ((s >> 2) & 3) * 2 + 2) }
        case .comparator:
            if comparatorOutput(p, s) != (comparatorOut[p] ?? 0) { schedule(p, 2) }
        case .piston, .stickyPiston:
            pistonUpdate(p, b, s)
        case .door, .ironDoor, .trapdoor, .ironTrapdoor, .gate:
            let k = Circuit.kind(b)
            var powered = received(p) > 0
            if k == .door || k == .ironDoor {
                let other = p + IVec3(0, (s & 8) != 0 ? -1 : 1, 0)
                powered = powered || received(other) > 0
            }
            let was = edge.contains(p)
            if powered != was {
                if powered { edge.insert(p) } else { edge.remove(p) }
                let open = (s & 4) != 0
                if open != powered {
                    setQuiet(p, base(b) + BlockID(s ^ 4))
                    if k == .door || k == .ironDoor {
                        let o = p + IVec3(0, (s & 8) != 0 ? -1 : 1, 0)
                        let ob = block(o)
                        if base(ob) == base(b) { setQuiet(o, base(b) + BlockID(st(ob) ^ 4)); edge.insert(o) }
                    }
                    game?.sfx(.open, 0.6, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5)
                }
            }
        case .tnt:
            if received(p) > 0 { setQuiet(p, AIR); game?.tnts.prime(at: p) }
        case .dispenser, .dropper, .note, .bell, .crafter:
            let powered = received(p) > 0 || (Circuit.kind(b) != .note && received(p + IVec3(0, 1, 0), except: [0]) > 0)
            let was = edge.contains(p)
            if powered && !was {
                edge.insert(p)
                if Circuit.kind(b) == .note { playNote(p, s) }
                else if Circuit.kind(b) == .bell { game?.sfx(.levelUp, 0.8, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5) }
                else { schedule(p, 4) }
            } else if !powered && was { edge.remove(p) }
        case .hopper:
            let locked = received(p) > 0
            if locked != (s >= 5) { setQuiet(p, base(b) + BlockID(s % 5 + (locked ? 5 : 0))) }
        case .poweredRail, .activatorRail:
            // Powered directly, or through up to 8 rails of the same kind in line.
            let on = railPowered(p, b)
            if on != (s >= 6) {
                setQuiet(p, base(b) + BlockID(s % 6 + (on ? 6 : 0)))
                for d in 2..<6 { for dy in -1...1 { let n = p + Circuit.D[d] + IVec3(0, dy, 0); if base(block(n)) == base(b) { mark(n) } } }
            }
        default:
            // A conductor changed power: wake the components around it.
            if conductor(b) { for d in 0..<6 { let n = p + Circuit.D[d]; if Circuit.kind(block(n)) != .none { mark(n) } } }
        }
    }

    // A vibration (steps, block changes, landings...): murk sensors within 8 blocks fire for 30 ticks
    // with a strength that falls off with distance, then rest.
    func vibrate(at pos: V3) {
        for p in tracked where Circuit.kind(block(p)) == .sculkSensor && sensor[p] == nil {
            let d = simd_length(V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5) - pos)
            guard d <= 8 else { continue }
            sensor[p] = (max(1, 15 - Int(d * 15 / 8)), now + 30)
            game?.sfx(.click, 0.3, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5)
            wakeAround(p)
            let q = p + IVec3(0, -1, 0); mark(q); wakeAround(q)
        }
    }

    // Trapped chests emit the number of viewers (the player: 0 or 1).
    func setTrapped(_ p: IVec3, _ v: Int) {
        trapped[p] = v == 0 ? nil : v
        mark(p); wakeAround(p)
        let below = p + IVec3(0, -1, 0)
        mark(below); wakeAround(below)
    }

    func wakeAround(_ p: IVec3) {
        for d in 0..<6 {
            let n = p + Circuit.D[d]
            mark(n)
            if conductor(block(n)) { for e in 0..<6 { mark(n + Circuit.D[e]) } }
        }
    }

    // Scheduled work.
    private func fire(_ p: IVec3) {
        let b = block(p)
        let s = st(b)
        switch Circuit.kind(b) {
        case .torch:
            let attached = s < 2 ? IVec3(0, -1, 0) : Circuit.D[Circuit.opp[Circuit.d6((s - 2) % 4)]]
            let q = p + attached
            let powered = conductor(block(q)) ? blockPower(q).1 > 0 : false
            let lit = s == 0 || (s >= 2 && s < 6)
            guard lit == powered else { return }
            // Burnout: more than 8 toggles in 60 ticks leaves the torch off for a while.
            var hist = (burn[p] ?? []).filter { now - $0 < 60 }
            hist.append(now)
            burn[p] = hist
            if hist.count > 8 && !lit { schedule(p, 160); return }
            let ns: Int = s < 2 ? (lit ? 1 : 0) : (lit ? s + 4 : s - 4)
            setQuiet(p, base(b) + BlockID(ns))
            if hist.count > 8 && lit { game?.sfx(.fizz, 0.4, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5) }
            wakeAround(p); mark(p + IVec3(0, 1, 0)); wakeAround(p + IVec3(0, 1, 0))
        case .lamp:
            if received(p) == 0 && s == 1 { setQuiet(p, base(b)); wakeAround(p) }
        case .repeater:
            let f = s & 3
            if lockInput(p, f) { return }
            let input = powerFrom(p, Circuit.opp[Circuit.d6(f)]) > 0
            let powered = (s & 16) != 0
            if input != powered {
                setQuiet(p, base(b) + BlockID(s ^ 16))
                let front = p + Circuit.D[Circuit.d6(f)]
                mark(front); wakeAround(front)
                // Keep at least a one-delay pulse: re-check after turning on.
                if !powered { schedule(p, ((s >> 2) & 3) * 2 + 2) }
            }
        case .comparator:
            let out = comparatorOutput(p, s)
            comparatorOut[p] = out
            let on = out > 0
            if on != ((s & 8) != 0) { setQuiet(p, base(b) + BlockID(s ^ 8)) }
            let front = p + Circuit.D[Circuit.d6(s & 3)]
            mark(front); wakeAround(front)
        case .observer:
            if s < 6 {
                setQuiet(p, base(b) + BlockID(s + 6))
                schedule(p, 2)
            } else {
                setQuiet(p, base(b) + BlockID(s - 6))
            }
            let back = p + Circuit.D[Circuit.opp[s % 6]]
            mark(back); wakeAround(back)
        case .lever, .button:
            // Button release.
            if Circuit.kind(b) == .button && s >= 12 {
                setQuiet(p, base(b) + BlockID(s - 12))
                game?.sfx(.click, 0.5, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5)
                switchChanged(p, s - 12)
            }
        case .dispenser, .dropper:
            game?.dispense(at: p, dir: s % 6, dropper: Circuit.kind(b) == .dropper)
        case .crafter:
            game?.crafterFire(p)
        default: break
        }
    }

    // Lever/button toggled: its neighbours and the block it is on (and that block's neighbours) wake.
    func switchChanged(_ p: IVec3, _ s: Int) {
        wakeAround(p)
        let q = p + Circuit.D[attachedDir(s)]
        mark(q); wakeAround(q)
    }

    private func lockInput(_ p: IVec3, _ f: Int) -> Bool {
        let sides = f <= 1 ? [4, 5] : [2, 3]
        for d in sides {
            let n = p + Circuit.D[d]
            let nb = block(n)
            let k = Circuit.kind(nb)
            if (k == .repeater || k == .comparator) && sourceOut(n, Circuit.opp[d]) > 0 { return true }
        }
        return false
    }

    // Comparator: compare (rear if rear >= side) or subtract (rear - side). The rear reads containers,
    // directly or through one conductor block.
    func comparatorOutput(_ p: IVec3, _ s: Int) -> Int {
        let f = s & 3
        let backDir = Circuit.opp[Circuit.d6(f)]
        var rear = powerFrom(p, backDir)
        let q = p + Circuit.D[backDir]
        if let c = containerSignal(q) { rear = c }
        else if conductor(block(q)), rear < 15, let c = containerSignal(q + Circuit.D[backDir]) { rear = max(rear, c) }
        let sides = f <= 1 ? [4, 5] : [2, 3]
        var side = 0
        for d in sides {
            let n = p + Circuit.D[d]
            let k = Circuit.kind(block(n))
            if k == .wire || k == .block || k == .repeater || k == .comparator { side = max(side, powerFrom(p, d)) }
        }
        if (s & 4) != 0 { return max(0, rear - side) }
        return rear >= side ? rear : 0
    }

    func containerSignal(_ q: IVec3) -> Int? {
        guard let be = w.blockEntities[q], be.kind != .spawner else {
            let k = Blocks.key(base(block(q)))
            if k == "composter" { return 0 }
            return nil
        }
        let c = be.container
        guard c.count > 0 else { return 0 }
        var fill: Float = 0
        var any = false
        for i in 0..<c.count where !c[i].isEmpty { fill += Float(c[i].count) / Float(c[i].maxStack); any = true }
        return any ? Int(floor(1 + fill / Float(c.count) * 14)) : 0
    }

    // MARK: Periodic: plates, daylight detectors, hoppers

    private func periodic() {
        guard let g = game else { return }
        var remove: [IVec3] = []
        for p in tracked {
            let b = block(p)
            let s = st(b)
            switch Circuit.kind(b) {
            case .plate, .weightedPlate:
                let wood = !Blocks.key(base(b)).hasPrefix("stone") && !Blocks.key(base(b)).hasPrefix("polished")
                let n = g.entitiesOn(p, items: wood || Circuit.kind(b) == .weightedPlate)
                var level = 0
                if Circuit.kind(b) == .weightedPlate {
                    let heavy = Blocks.key(base(b)).hasPrefix("heavy")
                    level = n == 0 ? 0 : min(15, heavy ? (n + 9) / 10 : n)
                } else { level = n > 0 ? 1 : 0 }
                if level != s {
                    // Plates release after 20 ticks (10 for weighted) with nothing on them.
                    if level < s && now % (Circuit.kind(b) == .weightedPlate ? 10 : 20) != 0 { continue }
                    setQuiet(p, base(b) + BlockID(level))
                    g.sfx(.click, 0.4, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5)
                    wakeAround(p); let q = p + IVec3(0, -1, 0); mark(q); wakeAround(q)
                }
            case .daylight:
                guard now % 20 == 0 else { continue }
                let sky = w.lightAt(p.x, p.y + 1, p.z).sky
                let inv = s >= 16
                let level = g.dim.dim.hasSky ? Int((Float(sky) * max(0, (g.daylight - 0.12) / 0.88)).rounded()) : 0
                let out = inv ? 15 - level : level
                if out != (s & 15) { setQuiet(p, base(b) + BlockID(out + (inv ? 16 : 0))); wakeAround(p) }
            case .hopper:
                hopperCooldown[p, default: 0] -= 1
                if (hopperCooldown[p] ?? 0) <= 0 && s < 5 {
                    if g.hopperTransfer(p, out: s % 5) { hopperCooldown[p] = 8 }
                }
            case .sculkSensor:
                if let v = sensor[p], now >= v.1 { sensor[p] = nil; wakeAround(p); let q = p + IVec3(0, -1, 0); mark(q); wakeAround(q) }
            case .tripHook:
                // Armed when string runs (up to 40 blocks) to a hook facing back; pulled while anything touches the string.
                guard now % 2 == 0 else { continue }
                let dir = Circuit.D[Circuit.d6(s & 3)]
                var q = p + dir
                var cells: [IVec3] = []
                var armed = false
                for _ in 0..<41 {
                    let qb = block(q)
                    if Blocks.key(base(qb)) == "tripwire" { cells.append(q); q = q + dir; continue }
                    if Circuit.kind(qb) == .tripHook && (st(qb) & 3) == ((s & 3) ^ 1) { armed = true }
                    break
                }
                let on = armed && !cells.isEmpty && cells.contains { g.entitiesOn($0, items: true) > 0 }
                if on != (s >= 4) {
                    setQuiet(p, base(b) + BlockID((s & 3) + (on ? 4 : 0)))
                    g.sfx(.click, 0.5, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5)
                    wakeAround(p)
                    let a = p + Circuit.D[Circuit.opp[Circuit.d6(s & 3)]]
                    mark(a); wakeAround(a)
                }
            case .none: remove.append(p)
            default: break
            }
        }
        for p in remove { tracked.remove(p) }
    }

    private func railPowered(_ p: IVec3, _ b: BlockID) -> Bool {
        if received(p) > 0 || received(p + IVec3(0, -1, 0), except: [1]) > 0 { return true }
        let shape = st(b) % 6
        let axis: [IVec3] = (shape == 0 || shape >= 4) ? [IVec3(0, 0, -1), IVec3(0, 0, 1)] : [IVec3(-1, 0, 0), IVec3(1, 0, 0)]
        for a in axis {
            var q = p
            for _ in 0..<8 {
                var next: IVec3?
                for dy in [0, 1, -1] { let n = q + a + IVec3(0, dy, 0); if base(block(n)) == base(b) { next = n; break } }
                guard let n = next else { break }
                if received(n) > 0 { return true }
                q = n
            }
        }
        return false
    }

    // Detector rails: pressed while a minecart is on them (released 20 ticks after it leaves).
    func detectorCheck(_ carts: [V3]) {
        for p in tracked where Circuit.kind(block(p)) == .detectorRail {
            let b = block(p)
            let s = st(b)
            let has = carts.contains { Int(floor($0.x)) == p.x && Int(floor($0.z)) == p.z && abs($0.y - Float(p.y)) < 1.2 }
            if has && s < 6 { setQuiet(p, base(b) + BlockID(s + 6)); wakeAround(p); mark(p + IVec3(0, -1, 0)); wakeAround(p + IVec3(0, -1, 0)) }
            else if !has && s >= 6 && now % 20 == 0 { setQuiet(p, base(b) + BlockID(s - 6)); wakeAround(p); wakeAround(p + IVec3(0, -1, 0)) }
        }
    }

    // MARK: Pistons

    static func immovable(_ b: BlockID, _ w: World, _ p: IVec3) -> Bool {
        if b == BEDROCK || b == OBSIDIAN || Blocks.hardness[Int(b)] < 0 { return true }
        let k = Blocks.key(Blocks.groupBase[Int(b)])
        if ["crying_obsidian", "reinforced_deepslate", "end_portal_frame", "spawner", "chest", "furnace", "lit_furnace", "hopper",
            "dispenser", "dropper", "enchanting_table", "ender_chest", "beacon", "lectern", "barrel", "respawn_anchor", "piston_head"].contains(k) { return true }
        if w.blockEntities[p] != nil { return true }
        let kk = kind(b)
        if (kk == .piston || kk == .stickyPiston) && Int(b - Blocks.groupBase[Int(b)]) >= 6 { return true }
        return false
    }
    // Broken (and dropped) instead of pushed.
    static func fragile(_ b: BlockID) -> Bool {
        if b == AIR || Blocks.isLiquid(b) { return true }
        let r = Blocks.render[Int(b)]
        if r == RenderType.cross.rawValue || r == RenderType.wire.rawValue { return true }
        let k = kind(b)
        if [.torch, .lever, .button, .plate, .weightedPlate, .repeater, .comparator, .door, .ironDoor].contains(k) { return true }
        return Blocks.replaceable[Int(b)] || !Blocks.collide[Int(b)]
    }

    private func pistonPowered(_ p: IVec3, _ face: Int) -> Bool {
        for d in 0..<6 where d != face { if powerFrom(p, d) > 0 { return true } }
        // Quasi-connectivity: power reaching the block above counts too.
        let up = p + IVec3(0, 1, 0)
        for d in 0..<6 where d != 0 { if powerFrom(up, d) > 0 { return true } }
        return false
    }

    private func pistonUpdate(_ p: IVec3, _ b: BlockID, _ s: Int) {
        let face = s % 6, extended = s >= 6
        let sticky = Circuit.kind(b) == .stickyPiston
        let powered = pistonPowered(p, face)
        if powered && !extended {
            if move(from: p + Circuit.D[face], dir: face, push: true, piston: p) {
                setQuiet(p, base(b) + BlockID(face + 6))
                setQuiet(p + Circuit.D[face], Blocks.id("piston_head") + BlockID(face + (sticky ? 6 : 0)))
                game?.sfx(.place(.wood), 0.6, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5)
                wakeAround(p + Circuit.D[face] + Circuit.D[face])
            }
        } else if !powered && extended {
            let head = p + Circuit.D[face]
            if Circuit.kind(block(head)) == .pistonHead { setQuiet(head, AIR) }
            setQuiet(p, base(b) + BlockID(face))
            if sticky {
                let q = head + Circuit.D[face]
                let qb = block(q)
                if !Circuit.fragile(qb) && !Circuit.immovable(qb, w, q) { _ = move(from: q, dir: Circuit.opp[face], push: false, piston: p) }
            }
            game?.sfx(.place(.wood), 0.5, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5)
            wakeAround(head)
        }
    }

    // Moves the block structure starting at `start` one step in `dir` (slime/honey drag their
    // neighbours). Push fails beyond 12 blocks or on immovable blocks; fragile blocks in the way break.
    private func move(from start: IVec3, dir: Int, push: Bool, piston: IVec3) -> Bool {
        var set: [IVec3] = []
        var inSet = Set<IVec3>()
        var queue: [IVec3] = [start]
        let slime = Blocks.id("slime_block"), honey = Blocks.id("honey_block")
        var qi = 0
        while qi < queue.count {
            let q = queue[qi]; qi += 1
            if inSet.contains(q) || q == piston { continue }
            let b = block(q)
            if Circuit.fragile(b) { continue }
            if Circuit.immovable(b, w, q) { return false }
            inSet.insert(q); set.append(q)
            if set.count > 12 { return false }
            queue.append(q + Circuit.D[dir])
            if b == slime || b == honey {
                for d in 0..<6 {
                    let n = q + Circuit.D[d]
                    if n == piston { continue }
                    let nb = block(n)
                    if (b == slime && nb == honey) || (b == honey && nb == slime) { continue }
                    if !Circuit.fragile(nb) && !Circuit.immovable(nb, w, n) { queue.append(n) }
                }
            }
        }
        // Fragile blocks where the structure moves into break and drop.
        var destroy: [IVec3] = []
        for q in set {
            let t = q + Circuit.D[dir]
            if inSet.contains(t) { continue }
            if t == piston { return false }
            let tb = block(t)
            if tb != AIR && !Blocks.isLiquid(tb) { destroy.append(t) }
        }
        for q in destroy {
            game?.breakDrops(q, block(q))
            setQuiet(q, AIR)
        }
        let ids = set.map { block($0) }
        for q in set where !inSet.contains(q - Circuit.D[dir]) { setQuiet(q, AIR) }
        for (i, q) in set.enumerated() { setQuiet(q + Circuit.D[dir], ids[i]) }
        game?.entitiesPushed(set.map { $0 + Circuit.D[dir] }, dir: Circuit.D[dir])
        for q in set { wakeAround(q); wakeAround(q + Circuit.D[dir]) }
        return true
    }

    // MARK: Note blocks

    private func playNote(_ p: IVec3, _ note: Int) {
        guard block(p + IVec3(0, 1, 0)) == AIR else { return }
        let below = Blocks.key(base(block(p + IVec3(0, -1, 0))))
        let inst: Int
        if below.hasSuffix("_planks") || below.hasSuffix("_log") { inst = 1 }            // bass
        else if below == "sand" || below == "gravel" { inst = 2 }                          // snare
        else if below == "glass" || below == "sea_lantern" { inst = 3 }                    // hat
        else if below == "stone" || below == "cobblestone" || below.hasSuffix("_ore") || below == "obsidian" || below == "netherrack" { inst = 4 } // bass drum
        else if below == "gold_block" { inst = 5 }                                         // bell
        else if below == "clay" { inst = 6 }                                               // flute
        else if below == "packed_ice" { inst = 7 }                                         // chime
        else if below.hasSuffix("_wool") { inst = 8 }                                      // guitar
        else if below == "bone_block" { inst = 9 }                                         // xylophone
        else if below == "iron_block" { inst = 10 }                                        // iron xylophone
        else if below == "hay_block" { inst = 11 }                                         // banjo
        else if below == "glowstone" { inst = 12 }                                         // pling
        else { inst = 0 }                                                                  // harp
        game?.sfx(.note(inst, note), 1, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5)
        game?.particles.hearts(at: V3(Float(p.x) + 0.5, Float(p.y) + 1.2, Float(p.z) + 0.5))
    }
}
