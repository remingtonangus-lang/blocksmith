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
    private var pressedAt: [IVec3: Int] = [:]        // plates and detector rails: last tick something was on them
    var tracked = Set<IVec3>()                        // hoppers, plates, daylight detectors (periodic work)
    private var hopperCooldown: [IVec3: Int] = [:]
    // A hopper that was empty and just had an item put in waits a full transfer before passing it on (reference): a
    // filter hopper under it gets the first pull (hopper sorters).
    func hopperReceived(_ p: IVec3) { hopperCooldown[p] = 8 }
    private var busy = false
    private var condLevel: [IVec3: Int] = [:]         // conducting components: last block power (wake neighbours on change)
    private var lecternOn = Set<IVec3>()              // lecterns giving their page-turn pulse
    var lastNote: (Int, Int)?                         // (instrument, pitch) of the last note block played (tests)
    private(set) var notesPlayed = 0
    private(set) var bellsRung = 0
    // W1: ticks that fell due while their chunk was unloaded (a button pressed as the player walked away stayed
    // pressed for ever): they fire once the chunk is back.
    private var parked: [IVec3: Int] = [:]
    // W3: lightning rods in loaded chunks (registered by the periodic pass, pruned when broken) and the struck ones
    // giving their 8-tick pulse.
    var rods = Set<IVec3>()
    var rodOn = Set<IVec3>()
    // W5: cells a piston moved blocks into this tick or the last (the reference keeps them as moving blocks for 2
    // ticks: nothing pushes them again) and the tick each piston last started to extend (a sticky piston retracting
    // within that time leaves its block behind: block spitting).
    var moving: [IVec3: Int] = [:]
    var pistonStarted: [IVec3: Int] = [:]
    // W9: murk sensors' last vibration frequency (1-15: a comparator reads it) and their cooldown after firing.
    var sensorFreq: [IVec3: Int] = [:]
    var sensorCool: [IVec3: Int] = [:]
    // W6: plain rails at a T junction and whether power had them switched (edge detection for the junction swap).
    var railPowered = Set<IVec3>()

    init(world: World) {
        w = world
        load()
    }

    // MARK: Kinds

    enum K: UInt8 {
        case none, wire, torch, block, lamp, lever, button, plate, weightedPlate, repeater, comparator, observer, piston, stickyPiston
        case dispenser, dropper, hopper, note, daylight, target, door, trapdoor, gate, tnt, pistonHead, bell, ironDoor, ironTrapdoor
        case rail, poweredRail, detectorRail, activatorRail
        case tripHook, trappedChest, copperBulb, crafter, sculkSensor, lectern
        case lightningRod
    }
    // Components that are also solid blocks and conduct power like stone (reference: lamps, note blocks, dispensers...).
    static let conducting: Set<K> = [.lamp, .note, .dispenser, .dropper, .crafter, .copperBulb]

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
        for i in 1..<Blocks.count where Int(Blocks.groupBase[i]) == i {
            let k = Blocks.key(BlockID(i))
            if k.hasSuffix("copper_bulb") { set(k, .copperBulb) }
            // W2: copper doors and trapdoors follow power like wooden ones (and break when a piston pushes them).
            else if k.hasSuffix("copper_door") { set(k, .door) }
            else if k.hasSuffix("copper_trapdoor") { set(k, .trapdoor) }
            else if k.hasSuffix("lightning_rod") { set(k, .lightningRod) }
        }
        set("lectern", .lectern)
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
    func conductor(_ b: BlockID) -> Bool {
        guard Blocks.opaque[Int(b)] && b != AIR else { return false }
        let k = Circuit.kind(b)
        return k == .none || Circuit.conducting.contains(k)
    }

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
        // Wires beside it may change shape (point elsewhere) at the same level: wake what they touch.
        for d in 2..<6 {
            let n = p + Circuit.D[d]
            if Circuit.kind(block(n)) == .wire { wakeAround(n) }
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
        if k == .hopper || k == .plate || k == .weightedPlate || k == .daylight || k == .detectorRail || k == .tripHook || k == .sculkSensor || k == .comparator || k == .lightningRod { tracked.insert(p) }
        else if tracked.contains(p) { tracked.remove(p) }
        if Circuit.kind(old) == .lightningRod && k != .lightningRod { rods.remove(p); rodOn.remove(p) }     // W3: pruned on break
        if Circuit.kind(old) == .sculkSensor && k != .sculkSensor { sensor[p] = nil; sensorFreq[p] = nil; sensorCool[p] = nil }
        if Circuit.kind(old) == .rail && k != .rail { railPowered.remove(p) }
        settledWires.remove(p)
        if condLevel[p] != nil && Circuit.kind(new) != Circuit.kind(old) { condLevel[p] = nil }
        if Circuit.kind(new) != .lectern { lecternOn.remove(p) }
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
        for p in Circuit.trackedCells(c.blocks.data, cx: c.cx, cz: c.cz) { tracked.insert(p) }
    }

    // Components needing periodic work in a chunk's blocks (thread-safe: the world's workers run it when they
    // produce a chunk, so installing it on the main thread is just the inserts).
    static func trackedCells(_ blocks: [BlockID], cx: Int, cz: Int) -> [IVec3] {
        let bx = cx * CS, bz = cz * CS
        var out: [IVec3] = []
        for i in 0..<min(blocks.count, CSQ * CH) {
            let b = blocks[i]
            let k = kinds[Int(b)]
            switch k {
            case .hopper, .daylight, .plate, .weightedPlate, .detectorRail, .tripHook, .sculkSensor, .comparator, .lightningRod:
                out.append(IVec3(bx + (i & 15), i >> 8, bz + ((i >> 4) & 15)))
            case .button, .observer:
                // W1: a pressed button or a lit observer whose release tick was lost (a save from before circuit.json, or
                // a chunk that unloaded with it pending) gets one again (the periodic pass drops it from the list).
                let s = Int(b - Blocks.groupBase[Int(b)])
                if (k == .button && s >= 12) || (k == .observer && s >= 6) { out.append(IVec3(bx + (i & 15), i >> 8, bz + ((i >> 4) & 15))) }
            default: break
            }
        }
        return out
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
        case .lectern: return d == 0 && lecternOn.contains(q) ? 15 : 0
        case .lightningRod: return rodOn.contains(q) && d == Circuit.opp[Circuit.rodDir(s)] ? 15 : 0     // into what it is on
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
        case .wire: return (d == 0 || wirePoints(q, d)) ? s & 15 : 0
        case .detectorRail: return s >= 6 ? 15 : 0
        case .tripHook: return s >= 4 ? 15 : 0
        case .sculkSensor: return sensor[q]?.0 ?? 0
        case .trappedChest: return trapped[q] ?? 0
        case .lectern: return lecternOn.contains(q) ? 15 : 0
        case .lightningRod: return rodOn.contains(q) ? 15 : 0
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
                let lv = st(nb) & 15
                if lv > 0 && (d == 1 || wirePoints(n, Circuit.opp[d])) { weak = max(weak, lv) }
            }
        }
        return (strong, max(strong, weak))
    }

    // Power arriving at a component at p from direction d.
    func powerFrom(_ p: IVec3, _ d: Int, forWire: Bool = false) -> Int {
        let q = p + Circuit.D[d]
        let b = block(q)
        if conductor(b) { let bp = blockPower(q); return forWire ? bp.0 : bp.1 }
        if Circuit.kind(b) != .none { return Circuit.kind(b) == .wire && forWire ? 0 : sourceOut(q, Circuit.opp[d]) }
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
    func connectsDust(_ n: IVec3, _ d: Int) -> Bool { Circuit.dustConnects(block(n), d) }

    // The same rule by block (the mesher draws wire arms with it, off the main thread).
    static func dustConnects(_ b: BlockID, _ d: Int) -> Bool {
        let s = Int(b - Blocks.groupBase[Int(b)])
        switch kind(b) {
        case .wire, .torch, .block, .lever, .button, .plate, .weightedPlate, .target, .daylight, .comparator, .detectorRail, .tripHook, .trappedChest, .sculkSensor, .lectern: return true
        case .repeater: return (d6(s & 3) / 2) == d / 2
        case .observer: return s % 6 == d        // only its output (back) side, which faces the dust
        default: return false
        }
    }

    // Wire states: level 0-15, +16 for a lone wire right-clicked into a dot (powers nothing beside it).
    @inline(__always) static func wireLevel(_ s: Int) -> Int { s & 15 }

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
        if c.isEmpty { return st(block(q)) < 16 }                // cross: all four sides; dot: none
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
            e = min(15, e)                                       // the bucket table is 16 long
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
            if st(b) & 15 != lv {
                setQuiet(q, base(b) + BlockID(lv | (st(b) & 16)))
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
        w.scheduleFluid(around: p)              // a piston pulling a block away from water lets it flow
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
            // Each one leaves the schedule as it fires, not all first: one firing earlier in the tick that touches a
            // component already due (an observer clock's partner) must not schedule it again (reference: a block with
            // a tick pending ignores the update). Order: as scheduled.
            for e in due {
                scheduledSet.remove(e.p)
                // W1: a tick due in an unloaded chunk waits for it (it was lost: buttons stayed pressed).
                if !w.isLoaded(e.p.x, e.p.z) { if parked.count < 20000 { parked[e.p] = 1 }; continue }
                fire(e.p)
            }
        }
        if !parked.isEmpty && now % 20 == 0 {
            var back: [IVec3] = []
            for (p, _) in parked where w.isLoaded(p.x, p.z) { back.append(p) }
            for p in back { schedule(p, parked.removeValue(forKey: p) ?? 1) }
        }
        if !moving.isEmpty && now % 20 == 0 { moving = moving.filter { $0.value > now } }
        if !pistonStarted.isEmpty && now % 200 == 0 { pistonStarted = pistonStarted.filter { now - $0.value < 10 } }
        // First in, first out by a read index (removeFirst() moved the whole queue each time: quadratic in a big
        // circuit's 20,000 updates); updates may append more, which this tick still reaches up to the cap.
        var head = 0
        while head < dirty.count && head < 20000 {
            let p = dirty[head]
            head += 1
            dirtySet.remove(p)
            update(p)
        }
        if head > 0 { dirty.removeFirst(head) }
        periodic()
    }

    private func update(_ p: IVec3) {
        let b = block(p)
        let s = st(b)
        if Circuit.conducting.contains(Circuit.kind(b)) && conductor(b) {
            let bp = blockPower(p).1
            if (condLevel[p] ?? 0) != bp {
                condLevel[p] = bp == 0 ? nil : bp
                for d in 0..<6 { let n = p + Circuit.D[d]; if Circuit.kind(block(n)) != .none { mark(n) } }
            }
        }
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
                    let door = k == .door || k == .ironDoor
                    let h = door ? w.doorHingeFlip(p, s) : 0      // P128: a pair swings apart
                    setQuiet(p, base(b) + BlockID(s ^ 4 ^ h))
                    if door {
                        let o = p + IVec3(0, (s & 8) != 0 ? -1 : 1, 0)
                        let ob = block(o)
                        if base(ob) == base(b) { setQuiet(o, base(b) + BlockID(st(ob) ^ 4 ^ h)); edge.insert(o) }
                    }
                    let iron = k == .ironDoor || Blocks.key(base(b)).hasPrefix("iron")
                    game?.audioOpenable(shape: Blocks.shape[Int(b)], iron: iron, opening: powered, at: p)
                    vibrate(at: V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5), freq: powered ? 10 : 9)
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
                else if Circuit.kind(b) == .bell { bellsRung += 1; game?.sfx(.bell, 1.2, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5) }
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
        case .rail:
            // W6: a plain rail at a T junction switches its curve when power arrives or goes (reference: unpowered it
            // takes the south-east curve, powered the north-west one).
            let on = received(p) > 0
            if on != railPowered.contains(p) {
                if on { railPowered.insert(p) } else { railPowered.remove(p) }
                Rails.junctionSwitch(w, p, powered: on)
            }
        default:
            // A conductor changed power: wake the components around it.
            if conductor(b) { for d in 0..<6 { let n = p + Circuit.D[d]; if Circuit.kind(block(n)) != .none { mark(n) } } }
        }
    }

    // A vibration (steps, block changes, landings...) of a reference frequency (W9: 1 step, 2 landing/projectile,
    // 3 item use, 9 close/deactivate, 10 open/activate, 11 block change, 12 block broken, 13 block placed, 14 entity
    // placed/lightning, 15 death/explosion). Murk sensors within 8 blocks (calibrated: 16) fire with a strength that
    // falls off with distance: 30 ticks (calibrated 10), then a 10-tick cooldown. A calibrated sensor powered from a
    // side listens only to the frequency equal to that power. Wool between the source and the sensor blocks it, and
    // steps on wool make none. A comparator reads the sensor's last frequency.
    func vibrate(at pos: V3, freq: Int = 11, onWool: Bool = false) {
        if onWool && freq == 1 { return }
        let f = max(1, min(15, freq))
        for p in tracked where Circuit.kind(block(p)) == .sculkSensor && sensor[p] == nil {
            if let c = sensorCool[p], c > now { continue }
            let calibrated = Blocks.key(base(block(p))) == "calibrated_sculk_sensor"
            let range: Float = calibrated ? 16 : 8
            let centre = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)
            let d = simd_length(centre - pos)
            guard d <= range else { continue }
            if calibrated {
                var input = 0
                for e in 2..<6 { input = max(input, powerFrom(p, e)) }
                if input > 0 && input != f { continue }
            }
            if woolBetween(pos, centre) { continue }
            let level = max(1, 15 - Int(d * 15 / range))
            sensor[p] = (level, now + (calibrated ? 10 : 30))
            sensorFreq[p] = f
            game?.sfx(.sculkClick, 0.5, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5)
            wakeAround(p)
            let q = p + IVec3(0, -1, 0); mark(q); wakeAround(q)
        }
    }

    // Wool blocks on the straight line from a vibration to a sensor (sampled every quarter block; the end cells
    // themselves don't count: a sheep's step on wool is handled by onWool).
    static let woolTable: [Bool] = (0..<Blocks.count).map { Blocks.key(Blocks.groupBase[$0]).hasSuffix("_wool") }
    func woolBetween(_ a: V3, _ b: V3) -> Bool {
        let v = b - a
        let len = simd_length(v)
        guard len > 1 else { return false }
        let steps = Int(len * 4)
        let ca = IVec3(Int(floor(a.x)), Int(floor(a.y)), Int(floor(a.z))), cb = IVec3(Int(floor(b.x)), Int(floor(b.y)), Int(floor(b.z)))
        for i in 1..<steps {
            let t = Float(i) / Float(steps)
            let q = a + v * t
            let c = IVec3(Int(floor(q.x)), Int(floor(q.y)), Int(floor(q.z)))
            if c == ca || c == cb { continue }
            if Circuit.woolTable[Int(block(c))] { return true }
        }
        return false
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
    // A projectile struck a target block at `hit` (world space): 1-15 by how close to the face centre, for 8 ticks
    // (arrows, tridents) or 20 (anything else) (reference; nothing ever powered a target).
    func hitTarget(_ p: IVec3, at hit: V3, arrow: Bool) {
        let b = block(p)
        guard Circuit.kind(b) == .target else { return }
        let c = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)
        let o = simd_abs(hit - c)
        // The face is the axis the hit is furthest along; the distance is the larger of the other two.
        let d: Float = o.x >= o.y && o.x >= o.z ? max(o.y, o.z) : (o.y >= o.z ? max(o.x, o.z) : max(o.x, o.y))
        let k: Float = min(1, max(0, (0.5 - d) / 0.5))
        let level = max(1, Int((15 * k).rounded(.up)))
        setQuiet(p, base(b) + BlockID(level))
        wakeAround(p)
        schedule(p, arrow ? 8 : 20)
    }

    private func fire(_ p: IVec3) {
        let b = block(p)
        let s = st(b)
        switch Circuit.kind(b) {
        case .target:
            if s > 0 { setQuiet(p, base(b)); wakeAround(p) }
        case .lightningRod:
            if rodOn.remove(p) != nil {
                wakeAround(p)
                let q = p + Circuit.D[Circuit.opp[Circuit.rodDir(s)]]
                mark(q); wakeAround(q)
            }
        case .lectern:
            if lecternOn.remove(p) != nil { wakeAround(p); let q = p + IVec3(0, -1, 0); mark(q); wakeAround(q) }
        case .torch:
            let attached = s < 2 ? IVec3(0, -1, 0) : Circuit.D[Circuit.opp[Circuit.d6((s - 2) % 4)]]
            let q = p + attached
            let powered = conductor(block(q)) ? blockPower(q).1 > 0 : false
            let lit = s == 0 || (s >= 2 && s < 6)
            guard lit == powered else { return }
            // Burnout (reference): 8 turn-offs within 60 ticks leave the torch off for a while. Only turn-offs count
            // (every toggle did, so a 6-tick clock burnt out here and not there).
            var hist = (burn[p] ?? []).filter { now - $0 < 60 }
            if lit { hist.append(now) }
            burn[p] = hist
            if hist.count >= 8 && !lit { schedule(p, 160); return }
            let ns: Int = s < 2 ? (lit ? 1 : 0) : (lit ? s + 4 : s - 4)
            setQuiet(p, base(b) + BlockID(ns))
            if hist.count >= 8 && lit { game?.sfx(.fizz, 0.4, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5) }
            wakeAround(p); mark(p + IVec3(0, 1, 0)); wakeAround(p + IVec3(0, 1, 0))
        case .lamp:
            if received(p) == 0 && s == 1 { setQuiet(p, base(b)); wakeAround(p) }
        case .repeater:
            let f = s & 3
            if lockInput(p, f) { return }
            let input = powerFrom(p, Circuit.opp[Circuit.d6(f)]) > 0
            let powered = (s & 16) != 0
            // Reference: a due tick turns an unpowered repeater on even if the input already went (a 1-tick pulse
            // comes out as long as the delay; it used to vanish), then schedules the turn-off.
            if powered && input { return }
            setQuiet(p, base(b) + BlockID(s ^ 16))
            let front = p + Circuit.D[Circuit.d6(f)]
            mark(front); wakeAround(front)
            if !powered && !input { schedule(p, ((s >> 2) & 3) * 2 + 2) }
        case .comparator:
            let out = comparatorOutput(p, s)
            comparatorOut[p] = out
            let on = out > 0
            if on != ((s & 8) != 0) { setQuiet(p, base(b) + BlockID(s ^ 8)) }
            let front = p + Circuit.D[Circuit.d6(s & 3)]
            mark(front); wakeAround(front)
        case .observer:
            if s < 6 {
                // Its own turn-off first, then the change its watchers see (reference order: in an observer clock the
                // partner's tick lands after this one's, so each sees the other's every change: on 2 of every 4 ticks).
                schedule(p, 2)
                setQuiet(p, base(b) + BlockID(s + 6))
            } else {
                setQuiet(p, base(b) + BlockID(s - 6))
            }
            let back = p + Circuit.D[Circuit.opp[s % 6]]
            mark(back); wakeAround(back)
        case .lever, .button:
            // Button release.
            if Circuit.kind(b) == .button && s >= 12 {
                // A wooden button stays pressed while an arrow is stuck in it (reference).
                if !Circuit.stoneButton(b), game?.arrowStuck(in: p) == true { schedule(p, 30); return }
                setQuiet(p, base(b) + BlockID(s - 12))
                game?.sfx(Blocks.key(base(b)).hasPrefix("stone") || Blocks.key(base(b)).hasPrefix("polished") ? .buttonStone : .buttonWood, 0.5, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5)
                switchChanged(p, s - 12)
            }
        case .dispenser, .dropper:
            game?.dispense(at: p, dir: s % 6, dropper: Circuit.kind(b) == .dropper)
        case .crafter:
            game?.crafterFire(p)
        default: break
        }
    }

    static func stoneButton(_ b: BlockID) -> Bool {
        let k = Blocks.key(Blocks.groupBase[Int(b)])
        return k.hasPrefix("stone") || k.hasPrefix("polished")
    }

    // An arrow came to rest in the cell `p`: wooden buttons there press (reference).
    func arrowLanded(_ p: IVec3) {
        let b = block(p)
        guard Circuit.kind(b) == .button, !Circuit.stoneButton(b) else { return }
        let s = st(b)
        guard s < 12 else { return }
        w.setBlock(p.x, p.y, p.z, base(b) + BlockID(s + 12))
        switchChanged(p, s + 12)
        schedule(p, 30)
        game?.sfx(.buttonWood, 0.6, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5)
    }

    // A lectern's page turned: a 2-tick pulse (15, strong into the block below) (reference).
    func lecternTurned(_ p: IVec3) {
        guard Circuit.kind(block(p)) == .lectern else { return }
        lecternOn.insert(p)
        wakeAround(p); let q = p + IVec3(0, -1, 0); mark(q); wakeAround(q)
        schedule(p, 3)               // the page turns between ticks and the wire sees it next tick: 2 ticks of power
    }

    // Right-click on a lone wire: cross <-> dot (reference, Java). Returns false for a wire that runs somewhere.
    func toggleDot(_ p: IVec3) -> Bool {
        let b = block(p)
        guard Circuit.kind(b) == .wire, wireConnections(p).isEmpty else { return false }
        w.setBlock(p.x, p.y, p.z, base(b) + BlockID(st(b) ^ 16))
        wakeAround(p)
        return true
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
            // Comparators take any source's direct power at the side (reference): an observer pointed in counts too.
            if k == .wire || k == .block || k == .repeater || k == .comparator || k == .observer { side = max(side, powerFrom(p, d)) }
        }
        if (s & 4) != 0 { return max(0, rear - side) }
        return rear >= side ? rear : 0
    }

    // Reference disc numbers (comparator reading of a jukebox).
    static let discSignal: [String: Int] = ["13": 1, "cat": 2, "blocks": 3, "chirp": 4, "far": 5, "mall": 6, "mellohi": 7, "stal": 8,
                                            "strad": 9, "ward": 10, "11": 11, "wait": 12, "pigstep": 13, "otherside": 14, "5": 15,
                                            "relic": 14, "creator": 12, "creator_music_box": 11, "precipice": 13, "tears": 10, "lava_chicken": 9]

    func containerSignal(_ q: IVec3) -> Int? {
        guard let be = w.blockEntities[q], be.kind != .spawner else {
            let k = Blocks.key(base(block(q)))
            let off = Int(block(q) - base(block(q)))
            switch k {                                                          // reference readings (they read nothing)
            case "composter": return off                                        // fill level 0-8
            case "water_cauldron": return off + 1                               // W4: water level 1-3
            case "lava_cauldron", "powder_snow_cauldron": return 3              // full
            case "cauldron": return 0
            case "bee_nest", "beehive": return off                              // honey level 0-5
            case "sculk_sensor", "calibrated_sculk_sensor": return sensorFreq[q] ?? 0   // W9: last vibration's frequency
            case "cake": return (7 - off) * 2                                   // slices left x 2
            case "end_portal_frame": return off > 0 ? 15 : 0                    // with an eye
            case "respawn_anchor": return off * 15 / 4                          // 0, 3, 7, 11, 15
            case _ where k.hasSuffix("copper_bulb"): return off == 1 ? 15 : 0     // lit (the bulb T flip-flop's output)
            case "jukebox":                                                     // the disc's number while one is in
                guard let j = game?.jukeboxes.first(where: { $0.pos == q }) else { return 0 }
                return Circuit.discSignal[j.disc.replacingOccurrences(of: "music_disc_", with: "")] ?? 1
            case "detector_rail":                                               // a cart's contents while it is on the rail
                guard off >= 6 else { return nil }
                let cart = game?.mobs.mobs.first { $0.kind == .minecart && $0.cargo != nil && Int(floor($0.pos.x)) == q.x
                    && Int(floor($0.pos.z)) == q.z && abs($0.pos.y - Float(q.y)) < 1.2 }
                guard let c = cart?.cargo else { return 0 }
                return Circuit.fill(c)
            default: break
            }
            return nil
        }
        switch be.kind {
        case .frame:                                                            // rotation 1-8 with an item in it
            return be.container.count > 0 && !be.container[0].isEmpty ? (Int(be.delay) & 7) + 1 : 0
        case .lectern:                                                          // how far through the book
            guard be.container.count > 0, !be.container[0].isEmpty else { return 0 }
            let pages = max(1, be.container[0].pages?.count ?? 1)
            if pages <= 1 { return 15 }
            let page = min(pages - 1, max(0, Int(be.delay)))
            return Int(floor(1 + Float(page) / Float(pages - 1) * 14))
        case .crafter:                                                          // W4: slots filled or disabled
            var n = 0
            for i in 0..<min(9, be.container.count) where !be.container[i].isEmpty || be.crafterDisabled(i) { n += 1 }
            return n
        case .shelf: return max(0, min(6, be.level))                            // last slot used (1-6)
        case .chest:                                                            // W4: a double chest reads as one
            if let o = chestPartner(q), let ob = w.blockEntities[o], ob.kind == .chest {
                return Circuit.fill(be.container, ob.container)
            }
            return Circuit.fill(be.container)
        default: return Circuit.fill(be.container)
        }
    }

    // W4: the other half of a double chest at p (two chests of the same kind side by side facing the same way, the
    // pairing the chest screen uses: the +x/+z neighbour first).
    func chestPartner(_ p: IVec3) -> IVec3? {
        let b = block(p)
        let k = Blocks.key(base(b))
        guard k == "chest" || k == "trapped_chest" else { return nil }
        let facing = st(b) & 3
        let a = facing < 2 ? IVec3(1, 0, 0) : IVec3(0, 0, 1)
        if block(p + a) == b { return p + a }
        if block(p - a) == b { return p - a }
        return nil
    }

    // Both halves of a double chest as one 54-slot reading.
    static func fill(_ a: ItemContainer, _ b: ItemContainer) -> Int {
        let n = a.count + b.count
        guard n > 0 else { return 0 }
        var fill: Float = 0
        var any = false
        for i in 0..<a.count where !a[i].isEmpty { fill += Float(a[i].count) / Float(a[i].maxStack); any = true }
        for i in 0..<b.count where !b[i].isEmpty { fill += Float(b[i].count) / Float(b[i].maxStack); any = true }
        return any ? min(15, Int(floor(1 + fill / Float(n) * 14))) : 0
    }

    // Reference container reading: floor(1 + average slot fullness * 14), 0 when empty.
    static func fill(_ c: ItemContainer) -> Int {
        guard c.count > 0 else { return 0 }
        var fill: Float = 0
        var any = false
        for i in 0..<c.count where !c[i].isEmpty { fill += Float(c[i].count) / Float(c[i].maxStack); any = true }
        return any ? min(15, Int(floor(1 + fill / Float(c.count) * 14))) : 0      // over-full slots (older saves) stay at 15
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
                if n > 0 { pressedAt[p] = now }
                if level != s {
                    // Plates release 20 ticks (10 weighted) after the last press (reference; a global 20-tick boundary
                    // gave pulses of 1 to 20 ticks).
                    if level < s && now - (pressedAt[p] ?? 0) < (Circuit.kind(b) == .weightedPlate ? 10 : 20) { continue }
                    setQuiet(p, base(b) + BlockID(level))
                    g.sfx(level > s ? .plateOn : .plateOff, 0.5, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5)
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
            case .comparator:
                // Containers (menus, mobs, crafters, cake bites...) change without a block update: re-read the rear.
                if comparatorOutput(p, s) != (comparatorOut[p] ?? 0) { schedule(p, 2) }
            case .sculkSensor:
                if let v = sensor[p], now >= v.1 {
                    sensor[p] = nil; sensorCool[p] = now + 10
                    wakeAround(p); let q = p + IVec3(0, -1, 0); mark(q); wakeAround(q)
                }
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
                    g.sfx(.tripwire, 0.5, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5)
                    wakeAround(p)
                    let a = p + Circuit.D[Circuit.opp[Circuit.d6(s & 3)]]
                    mark(a); wakeAround(a)
                }
            case .button:
                // W1: pressed with no release pending (an old save, or the tick was lost): it releases as usual.
                if s >= 12 && !scheduledSet.contains(p) && parked[p] == nil { schedule(p, Circuit.stoneButton(b) ? 20 : 30) }
                remove.append(p)
            case .observer:
                if s >= 6 && !scheduledSet.contains(p) && parked[p] == nil { schedule(p, 2) }
                remove.append(p)
            case .lightningRod:
                rods.insert(p)                                          // W3: rebuilt from the chunks as they load
                if rodOn.contains(p) && !scheduledSet.contains(p) && parked[p] == nil { schedule(p, 8) }
                remove.append(p)
            case .none: remove.append(p)
            default: break
            }
        }
        for p in remove { tracked.remove(p); pressedAt[p] = nil }
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
            if has { pressedAt[p] = now }
            if has && s < 6 { setQuiet(p, base(b) + BlockID(s + 6)); wakeAround(p); mark(p + IVec3(0, -1, 0)); wakeAround(p + IVec3(0, -1, 0)) }
            else if !has && s >= 6 && now - (pressedAt[p] ?? 0) >= 20 { setQuiet(p, base(b) + BlockID(s - 6)); wakeAround(p); wakeAround(p + IVec3(0, -1, 0)) }
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
        // Reference "destroy on push": gourds (piston farms), leaves, beds, carpets, lanterns, pots, cocoa, heads, the egg.
        let g = Blocks.key(Blocks.groupBase[Int(b)])
        if ["pumpkin", "carved_pumpkin", "jack_o_lantern", "melon", "flower_pot", "cocoa", "dragon_egg", "lantern", "soul_lantern",
            "zombie_head", "creeper_head", "piglin_head", "dragon_head", "player_head"].contains(g)
            || g.hasSuffix("_leaves") || g.hasSuffix("_bed") || g.hasSuffix("_bed_head") || g.hasSuffix("_carpet") || g.hasSuffix("_skull")
            || g.hasPrefix("potted_") { return true }
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
            let head = p + Circuit.D[face]
            guard head.y >= 0 && head.y < CH else { return }               // W5: not out of the world
            // A fragile block where the head goes breaks and drops (the head used to overwrite it: a torch or a flower
            // right in front vanished).
            let hb = block(head)
            if move(from: head, dir: face, push: true, piston: p) {
                let nb = block(head)
                if nb == hb && hb != AIR && !Blocks.isLiquid(hb) && Circuit.fragile(hb) { game?.breakDrops(head, hb) }
                setQuiet(p, base(b) + BlockID(face + 6))
                setQuiet(head, Blocks.id("piston_head") + BlockID(face + (sticky ? 6 : 0)))
                pistonStarted[p] = now
                moving[head] = now + 2
                wakeAround(p)
                game?.sfx(.pistonExtend, 0.6, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5)
                wakeAround(head + Circuit.D[face])
            }
        } else if !powered && extended {
            let head = p + Circuit.D[face]
            if Circuit.kind(block(head)) == .pistonHead { setQuiet(head, AIR) }
            setQuiet(p, base(b) + BlockID(face))
            wakeAround(p)                                    // its neighbours see it change (a quasi-powered piston below retracts too)
            // W5: retracting within the 2 ticks of its extension, a sticky piston leaves the block where it was pushed
            // (block spitting: an observer's pulse); later it pulls it back. Glazed terracotta is never pulled.
            let spit = now - (pistonStarted[p] ?? -100) <= 2
            if sticky && !spit {
                let q = head + Circuit.D[face]
                let qb = block(q)
                if !Circuit.fragile(qb) && !Circuit.immovable(qb, w, q) && !Circuit.glazed(qb) && !isMoving(q) {
                    _ = move(from: q, dir: Circuit.opp[face], push: false, piston: p)
                }
            }
            game?.sfx(.pistonContract, 0.5, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5)
            wakeAround(head)
        }
    }

    // W5: glazed terracotta doesn't stick to slime or honey and sticky pistons can't pull it (reference).
    static let glazedTable: [Bool] = (0..<Blocks.count).map { Blocks.key(Blocks.groupBase[$0]).hasSuffix("glazed_terracotta") }
    @inline(__always) static func glazed(_ b: BlockID) -> Bool { glazedTable[Int(b)] }
    // A cell a piston moved a block into this tick or the last: still a moving block (it can't be pushed again).
    @inline(__always) func isMoving(_ q: IVec3) -> Bool { (moving[q] ?? -1) > now }

    // Moves the block structure starting at `start` one step in `dir` (slime/honey drag their
    // neighbours). Push fails beyond 12 blocks, on immovable or still-moving blocks, or past the top or bottom of the
    // world; fragile blocks in the way break.
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
            if Circuit.immovable(b, w, q) || isMoving(q) { return false }
            inSet.insert(q); set.append(q)
            if set.count > 12 { return false }
            queue.append(q + Circuit.D[dir])
            if b == slime || b == honey {
                for d in 0..<6 {
                    let n = q + Circuit.D[d]
                    if n == piston { continue }
                    let nb = block(n)
                    if (b == slime && nb == honey) || (b == honey && nb == slime) { continue }
                    if Circuit.glazed(nb) { continue }
                    if !Circuit.fragile(nb) && !Circuit.immovable(nb, w, n) && !isMoving(n) { queue.append(n) }
                }
            }
        }
        // Fragile blocks where the structure moves into break and drop.
        var destroy: [IVec3] = []
        for q in set {
            let t = q + Circuit.D[dir]
            if t.y < 0 || t.y >= CH { return false }                    // W5: the world's height limits
            if inSet.contains(t) { continue }
            if t == piston { return false }
            let tb = block(t)
            if tb != AIR && !Blocks.isLiquid(tb) { destroy.append(t) }
        }
        for q in destroy {
            game?.breakDrops(q, block(q))
            // Its block entity goes with it, contents dropped (a sign, frame, banner or painting broken by a piston left
            // its entity in the empty cell: text and paintings floating, the framed item lost, the cell immovable, and a
            // frame hung there later read the stale entity's slots).
            if let g = game, let be = g.world.blockEntities.removeValue(forKey: q) {
                let at = V3(Float(q.x), Float(q.y), Float(q.z)) + 0.5
                for s in be.container.slots where !s.isEmpty { g.drops.spawn(s, at: at) }
            }
            // W5: a door broken by the push takes its other half with it (copper and wooden doors break when pushed).
            let k = Circuit.kind(block(q))
            if k == .door || k == .ironDoor {
                let o = q + IVec3(0, (st(block(q)) & 8) != 0 ? -1 : 1, 0)
                if base(block(o)) == base(block(q)) && !inSet.contains(o) { setQuiet(o, AIR) }
            }
            setQuiet(q, AIR)
        }
        let ids = set.map { block($0) }
        let dv = Circuit.D[dir]
        for q in set where !inSet.contains(q - dv) { setQuiet(q, AIR) }
        for (i, q) in set.enumerated() { setQuiet(q + dv, ids[i]) }
        let moved = set.map { $0 + dv }
        let until = now + 2
        for q in moved { moving[q] = until }
        // W5: moved observers: a lit one turns off as usual; one whose front block moved with it sees the change.
        let movedSet = Set(moved)
        for (i, q) in moved.enumerated() where Circuit.kind(ids[i]) == .observer {
            let s = st(ids[i])
            if s >= 6 || movedSet.contains(q + Circuit.D[s % 6]) { schedule(q, 2) }
        }
        game?.entitiesPushed(moved, dir: dv)
        for q in set { wakeAround(q); wakeAround(q + dv) }
        return true
    }

    // MARK: Note blocks

    func playNote(_ p: IVec3, _ note: Int) {
        let aboveKey = Blocks.key(base(block(p + IVec3(0, 1, 0))))
        // A mob head on top plays that mob's call instead of a note.
        let headMobs: [String: MobKind] = ["skeleton_skull": .skeleton, "wither_skeleton_skull": .witherSkeleton, "zombie_head": .zombie,
                                           "creeper_head": .creeper, "piglin_head": .piglin, "dragon_head": .enderDragon, "player_head": .villager]
        if let k = headMobs[aboveKey] {
            let at = V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5
            if k == .enderDragon { game?.sfx(.dragonGrowl, 1, at: at) } else if k == .creeper { game?.sfx(.creeperHiss, 1, at: at) } else { game?.sfx(.mob(k, .ambient), 1, at: at) }
            return
        }
        guard block(p + IVec3(0, 1, 0)) == AIR else { return }
        let belowID = block(p + IVec3(0, -1, 0))
        let below = Blocks.key(base(belowID))
        let mat = soundMat(belowID)
        let inst: Int
        if below == "gold_block" { inst = 5 }                                              // bell
        else if below == "clay" { inst = 6 }                                               // flute
        else if below == "packed_ice" { inst = 7 }                                         // chime
        else if below.hasSuffix("_wool") { inst = 8 }                                      // guitar
        else if below == "bone_block" { inst = 9 }                                         // xylophone
        else if below == "iron_block" { inst = 10 }                                        // iron xylophone
        else if below == "hay_block" { inst = 11 }                                         // banjo
        else if below == "glowstone" { inst = 12 }                                         // pling
        else if below == "soul_sand" { inst = 13 }                                         // cow bell
        else if below == "pumpkin" { inst = 14 }                                           // didgeridoo
        else if below == "emerald_block" { inst = 15 }                                     // bit
        else if mat == .wood { inst = 1 }                                                  // bass
        else if below == "sand" || below == "gravel" || below.hasSuffix("concrete_powder") || mat == .sand || mat == .gravel { inst = 2 } // snare
        else if below.hasSuffix("glass") || below == "sea_lantern" || mat == .glass { inst = 3 }                                        // hat
        else if mat == .stone || mat == .deepslate || mat == .netherrack || below == "obsidian" { inst = 4 }                            // bass drum
        else { inst = 0 }                                                                  // harp
        lastNote = (inst, note); notesPlayed += 1
        game?.sfx(.note(inst, note), 1, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5)
        game?.particles.hearts(at: V3(Float(p.x) + 0.5, Float(p.y) + 1.2, Float(p.z) + 0.5))
    }
}

// MARK: Lightning rods (W3)

extension Circuit {
    // Lightning rod states: 0 up (the old single state), 1 down, 2 north, 3 south, 4 west, 5 east -> the dir6 it
    // points along (the block it is mounted on is the opposite way).
    @inline(__always) static func rodDir(_ s: Int) -> Int { s == 0 ? 1 : (s == 1 ? 0 : min(5, s)) }

    // The lightning rod nearest (x, y, z) within `within` blocks that is the top block of its column; broken ones
    // are pruned on the way (reference: a strike within 128 blocks of a rod goes to the closest one).
    func nearestRod(x: Int, y: Int, z: Int, within: Int = 128) -> IVec3? {
        var best: IVec3?
        var bd = within * within
        var gone: [IVec3] = []
        for r in rods {
            guard w.isLoaded(r.x, r.z) else { continue }
            guard Circuit.kind(block(r)) == .lightningRod else { gone.append(r); continue }
            let dx = r.x - x, dy = r.y - y, dz = r.z - z
            let d = dx * dx + dy * dy + dz * dz
            guard d <= bd else { continue }
            // Exposed to the sky: nothing solid above it.
            var open = true
            var yy = r.y + 1
            while yy < CH && yy <= r.y + 48 {
                let ab = w.block(r.x, yy, r.z)
                if ab != AIR && Blocks.collide[Int(ab)] { open = false; break }
                yy += 1
            }
            if open { bd = d; best = r }
        }
        for r in gone { rods.remove(r); rodOn.remove(r) }
        return best
    }

    // Lightning struck the rod at p: signal 15 for 8 ticks (strong into the block it is mounted on).
    func rodStruck(_ p: IVec3) {
        let b = block(p)
        guard Circuit.kind(b) == .lightningRod else { return }
        rods.insert(p)
        rodOn.insert(p)
        wakeAround(p)
        let q = p + Circuit.D[Circuit.opp[Circuit.rodDir(st(b))]]
        mark(q); wakeAround(q)
        schedule(p, 8)
    }
}

// MARK: Save (W1)

// The engine's pending state, written with the world (circuit.json in each dimension's folder) so a reload carries
// on where it stopped: pending ticks (button releases, observer and torch ticks, repeater delays), the edges powered
// components saw (bulbs, dispensers, droppers, crafters, doors would fire again), torch burnout history, hopper
// cooldowns, comparator outputs, plate presses, murk sensors, lectern pulses, struck rods, junction rails.
// Positions are [x, y, z, values...]; a missing file (an older save) starts empty as before.
struct CircuitSave: Codable {
    var now: Int
    var sched: [[Int]]? = nil        // x, y, z, tick due
    var edge: [[Int]]? = nil
    var burn: [[Int]]? = nil         // x, y, z, turn-off ticks...
    var hop: [[Int]]? = nil          // x, y, z, cooldown
    var cmp: [[Int]]? = nil          // x, y, z, output
    var press: [[Int]]? = nil        // x, y, z, tick last pressed
    var sensor: [[Int]]? = nil       // x, y, z, output, until, frequency, cooldown until
    var lectern: [[Int]]? = nil
    var rods: [[Int]]? = nil         // x, y, z, powered (0/1)
    var rails: [[Int]]? = nil        // junction rails switched by power
    var pistons: [[Int]]? = nil      // x, y, z, tick its extension started
}

extension Circuit {
    var saveURL: URL? { w.save?.dir.appendingPathComponent("circuit.json") }

    func snapshot() -> CircuitSave {
        func row(_ p: IVec3, _ v: [Int] = []) -> [Int] { [p.x, p.y, p.z] + v }
        // Entries for blocks that are gone are dropped (where the chunk is loaded to tell).
        func keep(_ p: IVec3) -> Bool { !w.isLoaded(p.x, p.z) || Circuit.kind(block(p)) != .none }
        var sv = CircuitSave(now: now)
        sv.sched = scheduled.map { row($0.p, [$0.at]) } + parked.map { row($0.key, [now + $0.value]) }
        sv.edge = edge.filter(keep).map { row($0) }
        sv.burn = burn.compactMap { kv -> [Int]? in
            let r = kv.value.filter { now - $0 < 60 }
            return r.isEmpty ? nil : row(kv.key, r)
        }
        sv.hop = hopperCooldown.filter { $0.value > 0 && keep($0.key) }.map { row($0.key, [$0.value]) }
        sv.cmp = comparatorOut.filter { $0.value > 0 && keep($0.key) }.map { row($0.key, [$0.value]) }
        sv.press = pressedAt.filter { now - $0.value < 40 }.map { row($0.key, [$0.value]) }
        var sens: [[Int]] = []
        for p in Set(sensor.keys).union(sensorFreq.keys).union(sensorCool.keys) where keep(p) {
            let v = sensor[p]
            sens.append(row(p, [v?.0 ?? 0, v?.1 ?? 0, sensorFreq[p] ?? 0, sensorCool[p] ?? 0]))
        }
        sv.sensor = sens
        sv.lectern = lecternOn.map { row($0) }
        sv.rods = rods.filter(keep).map { row($0, [rodOn.contains($0) ? 1 : 0]) }
        sv.rails = railPowered.filter(keep).map { row($0) }
        sv.pistons = pistonStarted.filter { now - $0.value < 10 }.map { row($0.key, [$0.value]) }
        return sv
    }

    // With the world's other files (World.saveAll): on the save queue for the autosave.
    func save(background: Bool = false) {
        guard let url = saveURL else { return }
        SaveIO.write(snapshot(), to: url, background: background)
    }

    // Before the first tick (Circuit.init). Every field is optional: older files and a missing file load as empty.
    fileprivate func load() {
        guard let url = saveURL, let d = try? Data(contentsOf: url),
              let sv = try? JSONDecoder().decode(CircuitSave.self, from: d) else { return }
        restore(sv)
    }

    func restore(_ sv: CircuitSave) {
        now = max(0, sv.now)
        func pos(_ r: [Int]) -> IVec3? { r.count >= 3 ? IVec3(r[0], r[1], r[2]) : nil }
        for r in sv.sched ?? [] where r.count >= 4 {
            guard let p = pos(r), scheduledSet.insert(p).inserted else { continue }
            scheduled.append((at: max(now + 1, r[3]), p: p))
        }
        for r in sv.edge ?? [] { if let p = pos(r) { edge.insert(p) } }
        for r in sv.burn ?? [] where r.count > 3 { if let p = pos(r) { burn[p] = Array(r[3...]) } }
        for r in sv.hop ?? [] where r.count >= 4 { if let p = pos(r) { hopperCooldown[p] = r[3] } }
        for r in sv.cmp ?? [] where r.count >= 4 { if let p = pos(r) { comparatorOut[p] = r[3] } }
        for r in sv.press ?? [] where r.count >= 4 { if let p = pos(r) { pressedAt[p] = r[3] } }
        for r in sv.sensor ?? [] where r.count >= 7 {
            guard let p = pos(r) else { continue }
            if r[3] > 0 { sensor[p] = (r[3], r[4]) }
            if r[5] > 0 { sensorFreq[p] = r[5] }
            if r[6] > now { sensorCool[p] = r[6] }
        }
        for r in sv.lectern ?? [] { if let p = pos(r) { lecternOn.insert(p) } }
        for r in sv.rods ?? [] where r.count >= 4 {
            guard let p = pos(r) else { continue }
            rods.insert(p)
            if r[3] != 0 { rodOn.insert(p) }
        }
        for r in sv.rails ?? [] { if let p = pos(r) { railPowered.insert(p) } }
        for r in sv.pistons ?? [] where r.count >= 4 { if let p = pos(r) { pistonStarted[p] = r[3] } }
    }
}
