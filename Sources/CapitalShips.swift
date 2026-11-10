import Foundation
import simd

// Capital ships and the faction war (Remington, playtest 2: true-to-size frigates and a giant six-wheeled land
// dreadnought, very hostile, rare; Steelhold bases, frigates and six-wheelers are factions that fight each other).
// Original designs and names:
// - Stormwarden Frigate (Stormwarden Fleet): a 480-block flying warship. A hammerhead bow over a spinal rail cannon,
//   a hangar deck open on both flanks, a bridge tower, an engine block with four great drive nozzles; sixteen twin
//   naval-gun turrets (dorsal, ventral and on the flank skirts) and missile pods.
// - Ironback Crawler (Ironback Legion): a 77-block six-wheeled land dreadnought with a spinal rail cannon, two heavy
//   twin turrets, four autocannon sponsons and missile racks. It rolls over trees and fences.
// - Steelhold: the fortresses' soldiers and deck guns, and the Skyward Frigate / Siege Carriage they crew.
// Capital ships are kinematic: their AI sets velocity and turn rate directly (rigid-body forces and terrain contacts
// over a 5-million-cell grid would never fit the frame budget). Damage is counted incrementally (ShipCombat.blast),
// and their fate rests on critical systems: the bridge helm and the drive engines.

enum Faction: Int {
    case none = 0, steelhold, stormwarden, ironback, ashguard, meridian, greywall, corsairs
    var name: String { ["", "The Capital", "Stormwarden Fleet", "Ironback Legion", "The Ashguard", "Meridian Navy", "Greywall Command", "The Corsairs"][rawValue] }
    // P504 (Nov 1 09:33, Remington: "Greywall and crawlers are the same faction"): the Ironback Legion's crawlers fly
    // for Greywall Command. The old value stays for saves; whoever carries it is Greywall's.
    var side: Faction { self == .ironback ? .greywall : self }
}

// Per capital ship AI state (ShipManager.capState, keyed by the hull's id).
// P508: a dropship's lift, judged twice a second from its hull (CapitalShips.commandeeredTick).
enum DropLift {
    static var seen: [Int: (at: Double, lame: Bool)] = [:]
    static var told: Set<Int> = []
    static var base: [Int: (Int, Int)] = [:]
    static func lame(_ s: Ship, _ g: Game) -> Bool {
        if let k = seen[s.id], g.clock - k.at < 0.5 { return k.lame }
        var l = 0, r = 0
        let gr = s.grid, mid = Float(gr.sx) * 0.5
        for y in 0..<gr.sy { for z in 0..<gr.sz { for x in 0..<gr.sx where gr.get(x, y, z) != AIR {
            if Float(x) + 0.5 < mid { l += 1 } else { r += 1 }
        } } }
        // (each side against itself as built, where it was seen whole: the hull needn't sit square in its grid)
        if base[s.id] == nil && s.initialBlocks > 0 && s.blockCount * 20 >= s.initialBlocks * 19 { base[s.id] = (max(1, l), max(1, r)) }
        let (l0, r0) = base[s.id] ?? (max(1, max(l, r)), max(1, max(l, r)))
        let fl = Float(l) / Float(l0), fr = Float(r) / Float(r0)
        let lopsided = l + r > 60 && min(fl, fr) < max(fl, fr) * 0.67
        let torn = s.initialBlocks > 0 && s.blockCount * 10 < s.initialBlocks * 6
        let lame = lopsided || torn
        seen[s.id] = (g.clock, lame)
        if lame && !told.contains(s.id) && g.world.ships.pilot === s {
            told.insert(s.id)
            g.onToast?("The \(s.name) is losing lift")
            g.sfx(.explode, 0.6, at: s.pos)
        }
        return lame
    }
}

final class CapitalState {
    static let oldCrewAim = ProcessInfo.processInfo.environment["BS_OLDCREWAIM"] == "1"   // (harness: cleared as before)
    // P476 (Oct 27, "these four giant things are engines... thruster blocks back here. The engines connect to the
    // thruster blocks and somehow are what drives the frigate... if it doesn't have enough thrust, it doesn't get off
    // the ground"): the stern's thruster cores as built (the cells by the exhaust mouths), how many still burn, and
    // the hull's block count as built (her load).
    var thrustCells: [IVec3] = []
    var thrustLive = 0
    // P508 (Nov 1 16:04:40, in the Meridian's engine room: "this little reactor you have in here, if anything hits that,
    // ship's dead"): the reactor core's cells as built and how many are left (Capital.countThrust).
    var reactorCells: [IVec3] = []
    var reactorLive = 0
    var thrustT: Float = 0
    var blocks0 = 0
    // P476: the hull as built (HullBuilder blocks, the root grid's layout) for repairs, drawn up off the frame once she
    // is his; its solid cell count for the helm's hull readout.
    var blueprint: [BlockID]?
    var blueprintSolid = 0
    var blueprintAsked = false
    // Crew of a role still able to serve: posts not yet manned by a spawned soldier count (the crew is aboard
    // but not simulated yet), spawned soldiers count while alive.
    func crewAlive(_ role: CrewRole) -> Int {
        var n = 0
        for (i, r) in crewRoles.enumerated() where r == role {
            if !crewDone.contains(i) { n += 1 } else if let m = crewMobs[i], m.health > 0 { n += 1 }
        }
        return n
    }
    func hasRole(_ role: CrewRole) -> Bool { crewRoles.contains(role) }
    var driverAlive: Bool { crewless || !hasRole(.driver) || crewAlive(.driver) > 0 }
    var crewless = false               // harness (--ridecheck): an empty vehicle that still drives as if crewed
    var heaveTo = false                // a player is at the boarding winch's foot: the frigate slows to a crawl (FrigateBoarding)
    var winchTold = false
    // Turret i is manned while its gunner (posts shared round-robin over the turrets) lives.
    func turretManned(_ i: Int) -> Bool {
        let posts = crewRoles.indices.filter { crewRoles[$0] == .gunner }
        if posts.isEmpty { return true }
        let k = posts[i % posts.count]
        if !crewDone.contains(k) { return true }
        return (crewMobs[k]?.health ?? 0) > 0
    }
    var wheelsLost: Int { wheels.filter { $0.lost }.count }

    var region: String?
    var engines0 = 0
    var engineCells: [(IVec3, BlockID)] = []   // T9: a crawler's drive engine cells as built (rebuilt with ingots)
    var mainGunCD: Float = 8           // seconds until the spinal gun can fire
    var missiles = -1                  // small missiles left (P135; -1: not loaded yet)
    var smallCD: Float = 4             // ... seconds to the next launch from a hull with no pods
    var mainGunMuzzle = V3(0, 0, 0)    // ship space (grid coordinates)
    var mainGunDir = V3(0, 0, -1)
    var mainCharge: Float = 0
    var gunSalvaged = false            // H4: the Tidebreaker's breech was taken out of this frigate
    var mainGunLength: Float = 0       // barrel length back from the muzzle along -mainGunDir (the Tidebreaker's glow)
    var gunCharge: Float = -1          // the Tidebreaker: seconds charged (>= 0 while charging; MainGun.swift)
    var gunByPlayer = false            // the charge was started from the helm (fires along the barrel, P325)
    var gunPulse: Float = 0            // seconds to the next haptic coil thump while charging
    var aimPoint: V3?                  // the helm's predicted impact (MainGun.swift mainGunAimTick), nil when off the world
    var bombardAt: V3?                 // P99: the ground the crew's charging Tidebreaker will strike near a player
    var pingAt: V3?                    // C8: where its sonar last heard a submarine (it steers there while nothing is in sight)
    var pingT: Float = 0               // ... seconds since that ping (it gives up after 60)
    var bombardShots = 0               // ... shots so far at that player (each lands nearer)
    var aimTimer: Float = 0            // seconds to the next aim prediction (10 a second)
    var rounds = -1                    // P483: the guns' magazine while he holds the helm (-1: not filled yet; Capital.magazine)
    var missileCD: Float = 5
    var pods: [(V3, V3)] = []          // missile pod mouths and launch directions (ship space)
    var enginesShaken = false            // P434 (g): the drive engines knocked off their mounts by a hard knock, till an ingot restarts them
    var restartT: Float = 0              // P464: seconds the stopped (not missing) engines have been coughing back to life
    var exhausts: [V3] = []            // drive nozzle mouths (ship space)
    var retarget: Float = 0
    var target: CapTarget?
    var orbitDir: Float = 1
    var groundOffset: Float = 0        // centre of mass above the lowest wheel (crawlers)
    var groundTimer: Float = 0
    var groundMax: Float = 0           // highest terrain under and ahead of a frigate (sampled twice a second)
    var isles: [(c: V2, top: Float, r: Float)]? = nil   // T11: sky isles near a frigate's home (found once)
    var crushTimer: Float = 0
    var crushNextZ: Float?             // store review: a pass under way left part done (crawlerCrush), its next row
    var crushEndZ: Float = 0           // (the pass's last row: the stern on a whole sweep, the bow rows on a straight run)
    var crushFullYaw: Float = 0, crushFullAt = -1.0     // (heading and clock of the last whole sweep)
    var crushedAll = false
    var sinkSpeed: Float = 0
    var wreckFx: Float = 0
    var settled = false
    var announced = false
    var shelling = false               // T8: has told the player it is shelling a shore position
    var engaged = false
    var sight: Float = 250
    var crew: [V3] = []                // crew posts (ship space); soldiers of the ship's faction appear there once
    var crewDone = Set<Int>()          // posts whose soldier has appeared
    var crewRoles: [CrewRole] = []
    var crewMobs: [Int: Mob] = [:]     // post -> its soldier, once it has appeared
    var wheels: [VehicleWheel] = []    // land vehicles: wheel components (lost at half their blocks)
    var wheelTimer: Float = 0
    var disabledWhy = ""               // why the vehicle stopped for good ("" while it runs)
    var testTurn: Float?               // harness (--ridecheck): drive at full speed, heading offset this far (radians)
    var testSpeed: Float?              // harness (--ridecheck): this speed instead of the AI's (with testTurn)
    var rampDown = true                // crawler: the rear ramp is lowered (built so)
    var rampTimer: Float = 0           // seconds the crawler has wanted the ramp the other way
    var rutCarved: [Int: V3] = [:]     // P511: crawler: where each wheel last cut its track (world space)
    var ground: V3?                    // crawler: smoothed ground under it (height, pitch, roll)
    var grind: Float = -1              // disabled crawler: forward speed while it grinds to a stop (-1 not yet)
    var impact: Float = 0              // crash-landed frigate: sink speed at touchdown (b/s)
    var sag = V2(0, 0)                 // disabled crawler: pitch / roll toward its lost wheels
    var wantSpeed: Float = 0           // crawler: the speed its AI wants (before the lowered ramp holds it to a creep)
    var goal: V3?                      // a citadel's crawler patrol (CapitalBases.swift): drive here when nothing is in sight
    var troopCD: Float = 12            // seconds until the next troop drop
    var parties = 0, partyCD: Float = 8   // Meridian boarding parties down the winch line (Navy.swift)
    var helmPitch: Float = 0           // P325 (c): a commandeered frigate's bow pitch (radians, up +) the helm holds
    var helmBank: Float = 0            // ... its bank into the turn
    var probes: [V3]?                  // P325 (d): the hull's outline cells (ship space) tested against the ground
    var probeBlocks = 0                // ... the hull's block count they were taken at (blasts change the outline)
    var bumpCD: Float = 0              // ... seconds until a knock can tear the hull again
    var partyMobs: [Mob] = []
    var troops: [Mob] = []             // soldiers it has deployed (alive ones count toward its limit)
    var ramp = V3(0, 0, 0)             // crawler: the rear ramp's foot (ship space)
    var dropships: [Ship] = []         // frigate: dropships it has launched (at most two out at once)
    // Dropships: 0 launch, 1 transit, 2 descend, 3 unload, 4 support, 5 leave; where to land; time in the phase.
    var phase = 0
    var dropPoint = V3(0, 0, 0)
    var launchDir = V3(1, 0, 0)
    var phaseT: Float = 0
    var troopsLeft = 0
    var rocketeer = false                               // P215: a raid's last trooper carries a rocket launcher
    var fuel: Float = CapitalState.dropFuel            // a commandeered drop craft: seconds of thrust left (P66)
    // P461 (Oct 25 16:40-16:44, "maybe 15 minutes of driving before... it needs to refuel", "the fuel should last
    // longer"): a full tank flies 15 minutes (was 4), and coal and the rest go three times as far.
    static let dropFuel: Float = 900
    var lightCells: [V3]?                               // P461: the craft's white light panels (overdrive glow)
    var crushT: Float = 0                               // P461: time to the next sweep for what the hull runs into
    var ramT: Float = 0                                 // P461: time before another ram can tear plating off
    var crushEvery: Float = 0.12                        // P461: the sweep's interval (shorter at speed)
    var fuelTold = 0
}

// Who stands at a capital vehicle's crew post. The vehicle is a machine: it drives while its driver lives and the
// helm stands, each turret fires while its gunner lives, and troops are the soldiers it carries.
enum CrewRole: Int { case driver = 0, gunner, troop }

// A wheel of a land vehicle: its cells in the grid (box) and how many wheel blocks it started with / has left.
struct VehicleWheel {
    var part: Int          // index into Ship.wheelParts
    var lo: IVec3, hi: IVec3
    var n0: Int
    var n: Int
    var orig: [BlockID] = []   // the part's cells as built (T9: a repair puts the missing ones back)
    var wear: Float = 0        // P511: blast damage taken as one part (ShipManager.wheelBlast)
    var burst = false          // worn through: lost however many of its blocks still stand
    var lost: Bool { n * 2 < n0 || burst }
}

struct CapTarget {
    var point: V3
    var vel: V3
    @WeakLink var ship: Ship? = nil
    weak var mob: Mob?
    var player = false
    var seat = 0                      // split screen: which player (frigates engaged only player 1)
    var fixed = false                 // T8: a shore position under bombardment (a base's keep, no mob or ship)
}

// Dense hull builder (a dictionary blueprint of 200 000 cells was too slow): grid coordinates are x + ox, y, z.
final class HullBuilder {
    let sx: Int, sy: Int, sz: Int, ox: Int
    var blocks: [BlockID]
    var turrets: [(ring: IVec3, bp: Blueprint, spec: GunSpec2)] = []
    var chests: [(IVec3, String)] = []
    var pods: [(V3, V3)] = []
    var enginesShaken = false            // P434 (g): the drive engines knocked off their mounts by a hard knock, till an ingot restarts them
    var exhausts: [V3] = []              // drive nozzle mouths (grid coordinates): glowing exhaust while the engines run
    var mainGun: (V3, V3) = (V3(0, 0, 0), V3(0, 0, -1))
    var mainGunLength: Float = 0         // visible barrel length behind the muzzle (blocks)
    var crew: [V3] = []                  // crew posts, grid coordinates (feet)
    var crewRoles: [CrewRole] = []       // per post (missing entries are troops)
    // A crew post at builder coordinates (x relative to the centreline).
    func post(_ x: Int, _ y: Int, _ z: Int, _ role: CrewRole) {
        crew.append(V3(Float(x + ox) + 0.5, Float(y), Float(z) + 0.5))
        while crewRoles.count < crew.count - 1 { crewRoles.append(.troop) }
        crewRoles.append(role)
    }
    init(sx: Int, sy: Int, sz: Int, ox: Int) {
        self.sx = sx; self.sy = sy; self.sz = sz; self.ox = ox
        blocks = [BlockID](repeating: AIR, count: sx * sy * sz)
    }
    @inline(__always) func set(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) {
        let gx = x + ox
        guard gx >= 0 && gx < sx && y >= 0 && y < sy && z >= 0 && z < sz else { return }
        blocks[gx + z * sx + y * sx * sz] = b
    }
    @inline(__always) func get(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
        let gx = x + ox
        guard gx >= 0 && gx < sx && y >= 0 && y < sy && z >= 0 && z < sz else { return AIR }
        return blocks[gx + z * sx + y * sx * sz]
    }
    // Pieces of the hull that touch the rest only along edges or corners (a skin stepping two blocks a cell): each gets one
    // block of its own kind in an open cell beside it that meets the main hull face to face (stairs count as one flight,
    // as FrigateLayoutCheck counts them). Returns the blocks added.
    static var keepIslands = false                  // (FrigateLayoutCheck: a hull as built, to list what floats)
    @discardableResult
    func joinIslands() -> Int {
        if HullBuilder.keepIslands { return 0 }
        let n = sx * sy * sz
        guard let start = blocks.firstIndex(where: { $0 != AIR }) else { return 0 }
        var main = [Bool](repeating: false, count: n)
        let faces: [(Int, Int, Int)] = [(0, 0, 1), (0, 0, -1), (1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0)]
        func idx(_ x: Int, _ y: Int, _ z: Int) -> Int? {
            guard x >= 0 && x < sx && y >= 0 && y < sy && z >= 0 && z < sz else { return nil }
            return x + z * sx + y * sx * sz
        }
        func flood(_ from: Int) {
            var stack = [from]
            main[from] = true
            while let i = stack.popLast() {
                let x = i % sx, z = (i / sx) % sz, y = i / (sx * sz)
                for (dx, dy, dz) in faces { if let j = idx(x + dx, y + dy, z + dz), !main[j], blocks[j] != AIR { main[j] = true; stack.append(j) } }
                if Blocks.shape[Int(blocks[i])] == "stairs" {
                    for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] { for dy in [1, -1] {
                        if let j = idx(x + dx, y + dy, z + dz), !main[j], Blocks.shape[Int(blocks[j])] == "stairs" { main[j] = true; stack.append(j) }
                    } }
                }
            }
        }
        // (the largest piece is the hull)
        var seen = [Bool](repeating: false, count: n)
        var best = start, bestSize = 0
        for i in 0..<n where blocks[i] != AIR && !seen[i] {
            var stack = [i], size = 0
            seen[i] = true
            while let k = stack.popLast() {
                size += 1
                let x = k % sx, z = (k / sx) % sz, y = k / (sx * sz)
                for (dx, dy, dz) in faces { if let j = idx(x + dx, y + dy, z + dz), !seen[j], blocks[j] != AIR { seen[j] = true; stack.append(j) } }
            }
            if size > bestSize { bestSize = size; best = i }
        }
        flood(best)
        var added = 0
        for _ in 0..<4 {
            var changed = false
            for i in 0..<n where blocks[i] != AIR && !main[i] {
                let x = i % sx, z = (i / sx) % sz, y = i / (sx * sz)
                for (dx, dy, dz) in faces {
                    guard let j = idx(x + dx, y + dy, z + dz), blocks[j] == AIR else { continue }
                    let jx = x + dx, jy = y + dy, jz = z + dz
                    let meets = faces.contains { f in idx(jx + f.0, jy + f.1, jz + f.2).map { main[$0] } ?? false }
                    guard meets else { continue }
                    blocks[j] = Blocks.shape[Int(blocks[i])] == "stairs" ? (Blocks.has("frigate_hull") ? Blocks.id("frigate_hull") : STONE) : blocks[i]
                    added += 1
                    flood(j)
                    changed = true
                    break
                }
            }
            if !changed { break }
        }
        return added
    }
    func fill(_ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int, _ z0: Int, _ z1: Int, _ b: BlockID) {
        for y in thru(min(y0, y1), max(y0, y1)) { for z in thru(min(z0, z1), max(z0, z1)) { for x in thru(min(x0, x1), max(x0, x1)) { set(x, y, z, b) } } }
    }
    func grid(_ x: Int, _ y: Int, _ z: Int) -> IVec3 { IVec3(x + ox, y, z) }
}

// Guns of a turret (ShipCombat.fire reads them from the turret ship).
struct GunSpec2 {
    var speed: Float, gravity: Float = 20, power: Float, reload: Float, pitchMin: Float, pitchMax: Float, scatter: Float = 0.01
}

enum Capital {
    static func id(_ n: String, _ fallback: BlockID = STONE) -> BlockID { Blocks.has(n) ? Blocks.id(n) : fallback }

    // A land vehicle's wheels as components, from the ship's wheel parts (connected wheel cells).
    static func vehicleWheels(_ s: Ship) -> [VehicleWheel] {
        s.wheelParts.enumerated().map { (i, p) -> VehicleWheel in
            let n = p.blocks.filter { $0 != AIR }.count
            return VehicleWheel(part: i, lo: p.lo, hi: IVec3(p.lo.x + p.size.x - 1, p.lo.y + p.size.y - 1, p.lo.z + p.size.z - 1), n0: n, n: n, orig: p.blocks)
        }
    }

    // MARK: Turrets

    // A naval gun mount: armoured housing, barrels, cannons at the muzzles. `hang` builds it upside down under the hull
    // (ventral turrets). R10 (Oct 13, again after P70: "every naval gun is the same copy-pasted model"): each mount
    // takes one of four builds by `style`, and fires to match (`spec(style, base)`):
    //   0 twin      two long barrels, the gunhouse with a stripe (the old one)
    //   1 triple    three barrels from a wider, sloped-faced house: a three-round salvo, a slower reload
    //   2 heavy     one very long barrel with a muzzle brake and a raised rangefinder: hits harder, reloads slowest
    //   3 quad      four short barrels in a low box with an open top: light quick shells, steeper elevation
    static func navalTurret(hang: Bool, size: Int = 3, style: Int = 0) -> Blueprint {
        let t = Blueprint()
        let s = size
        let up = hang ? -1 : 1
        let y0 = hang ? -3 : 0, y1 = hang ? -1 : 2
        func yy(_ k: Int) -> Int { hang ? -1 - k : k }                    // k up from the ring's floor (or down, hung)
        let by = hang ? -2 : 1
        // P477 (Oct 27 19:21, "Big, medium, and small gun barrels, and then fit them into the current naval gun systems";
        // P476 19:1x: "Not a cannon placed on the end of blocks connected to one of these guns. That's just low effort"):
        // each gun is a breech in the gunhouse's face and bored barrels laid on from it, as the Vehicle Works' guns are,
        // where an iron rod carried a cannon at its tip. Large bores on the naval mounts, medium on the quad.
        func gun(_ bx: Int, _ tubes: Int, _ bore: String) {
            t.set(bx, by, -s, "ship_cannon[south]")
            for z in (-s - tubes)...(-s - 1) { t.set(bx, by, z, "gun_barrel_\(bore)[south]") }
        }
        switch style % 4 {
        case 1:
            t.box(-s - 1, s + 1, y0, y1, -s, s, "warship_hull", hollow: true)
            let roof = hang ? -4 : 3
            t.box(-s, s, roof, roof, -s + 1, s - 1, "warship_panel")
            for x in (-s)...s { t.set(x, yy(2), -s - 1, "warship_panel") }        // the sloped face's lip
            for bx in [-2, 0, 2] { gun(bx, 8, "large") }
            t.set(-s - 1, yy(1) + up, s, "warship_stripe"); t.set(s + 1, yy(1) + up, s, "warship_stripe")
        case 2:
            t.box(-s, s, y0, y1, -s, s, "warship_hull", hollow: true)
            let roof = hang ? -4 : 3
            t.box(-s + 1, s - 1, roof, roof, -s + 1, s - 1, "warship_panel")
            gun(0, 8, "large")
            // The barrel's collar where it leaves the house, and the rangefinder: a bar across the roof on two posts.
            for (dx, dy) in [(-1, 0), (1, 0), (0, up)] { t.set(dx, by + dy, -s - 1, "warship_panel") }
            for x in (-s - 2)...(s + 2) { t.set(x, roof + up * 2, 1, "warship_panel") }
            t.set(-s, roof + up, 1, "iron_block"); t.set(s, roof + up, 1, "iron_block")
        case 3:
            t.box(-s, s, y0, hang ? -2 : 1, -s, s, "warship_hull", hollow: true)
            for bx in [-2, -1, 1, 2] { gun(bx, 4, "medium") }
            t.set(0, hang ? -2 : 1, s, "warship_stripe")
        default:
            t.box(-s, s, y0, y1, -s, s, "warship_hull", hollow: true)
            let roof = hang ? -4 : 3
            t.box(-s + 1, s - 1, roof, roof, -s + 1, s - 1, "warship_panel")
            for bx in [-1, 1] { gun(bx, 8, "large") }
            t.set(0, hang ? -1 : 2, s, "warship_stripe")
        }
        return t
    }
    // How each build fires (R10), from the mount's base spec.
    static func spec(_ style: Int, _ b: GunSpec2) -> GunSpec2 {
        var g = b
        switch style % 4 {
        case 1: g.reload *= 1.3; g.power *= 0.95
        case 2: g.reload *= 1.8; g.power *= 1.9; g.speed *= 1.25; g.scatter *= 0.5
        case 3: g.reload *= 0.45; g.power *= 0.5; g.pitchMax = max(g.pitchMax, 1.0); g.scatter *= 2
        default: break
        }
        return g
    }

    // A small autocannon sponson (crawlers): fast, light shells, steep elevation.
    static func autocannon() -> Blueprint {
        let t = Blueprint()
        t.box(-1, 1, 0, 1, -1, 1, "warship_hull")
        t.set(0, 2, 0, "warship_panel")
        t.set(0, 1, -1, "ship_cannon[south]")                              // (P477: breech in the face, small-bore barrels)
        for z in -4 ... -2 { t.set(0, 1, z, "gun_barrel_small[south]") }
        return t
    }

    static let naval = GunSpec2(speed: 120, power: 3.5, reload: 3.5, pitchMin: -0.35, pitchMax: 0.75)
    static let navalHung = GunSpec2(speed: 120, power: 3.5, reload: 3.5, pitchMin: -1.35, pitchMax: 0.2)
    static let heavy = GunSpec2(speed: 110, power: 4, reload: 4.5, pitchMin: -0.45, pitchMax: 0.7)     // (P455: "can't shoot down far enough")
    static let auto = GunSpec2(speed: 140, power: 1.8, reload: 1.2, pitchMin: -0.6, pitchMax: 1.0, scatter: 0.025)
    // P435: the same gun flown by him (ShipPlay.startPiloting): a quicker, heavier high-explosive round.
    static let frigateHeldReload: Float = 0.7      // P508: a frigate's guns at his helm (ShipPlay.startPiloting)
    static let autoHeld = GunSpec2(speed: 170, power: 3.4, reload: 0.4, pitchMin: -0.4, pitchMax: 1.0, scatter: 0.012)

    // MARK: Stormwarden Frigate (bow toward -Z at z 0, keel at y 0, centreline x 0)

    static let frigateLength = 480

    // Hull section at z: half-width, bottom, top.
    static func frigateSection(_ z: Int) -> (Float, Float, Float) {
        let zf = Float(z)
        func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * max(0, min(1, t)) }
        if z < 100 {
            // The prow: a long chisel wedge (the top slopes down over 45 blocks to the brow over the rail-cannon
            // muzzle, the chin rises over 30, the flanks draw in over 35), not a flat-faced box.
            let ft: Float = min(1, zf / 45), fb: Float = min(1, zf / 30), fw: Float = min(1, zf / 35)
            return (26 + 18 * fw * (2 - fw), 22 - 12 * fb, 68 + 20 * ft * (2 - ft))
        }
        if z < 140 { let t: Float = (zf - 100) / 40; return (lerp(44, 30, t), lerp(10, 20, t), lerp(88, 72, t)) }
        if z < 360 { return (30, 20, 72) }
        if z < 380 { let t: Float = (zf - 360) / 20; return (lerp(30, 42, t), lerp(20, 12, t), lerp(72, 80, t)) }
        return (42, 12, 80)
    }

    static func frigateInside(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        guard z >= 0 && z < frigateLength && y >= 0 else { return false }
        let ax = Float(abs(x)), yf = Float(y)
        let (hw, yb, yt) = frigateSection(z)
        if ax <= hw && yf >= yb && yf <= yt {
            // Chamfered top and bottom edges.
            let topC: Float = (ax - (hw - 10)) + (yf - (yt - 10))
            let botC: Float = (ax - (hw - 8)) + ((yb + 8) - yf)
            if topC <= 10 && botC <= 8 { return true }
        }
        // Ventral keel.
        if z >= 170 && z <= 330 && abs(x) <= 10 && y >= 6 && yf < yb { return true }
        // Bridge tower with a sloped front.
        if z >= 296 && z <= 336 && abs(x) <= 10 && yf > yt - 1 && y <= 90 {
            if Float(z - 296) >= Float(y - 72) * 0.5 { return true }
        }
        // Drive nacelles bulging from the aft flanks, and a dorsal spine ridge along the midships.
        if z >= 386 && z <= 470 && ax <= 48 && y >= 22 && y <= 50 {
            let cut: Float = Float(max(0, 392 - z)) * 1.2
            if ax <= 48 - cut { return true }
        }
        if z >= 140 && z <= 296 && abs(x) <= 5 && yf > yt - 1 && yf <= yt + 3 - Float(abs(x)) * 0.5 { return true }
        // Armour skirts along the flanks (tapered at both ends).
        if y >= 40 && y <= 42 && z >= 150 && z <= 350 {
            let taper: Float = min(Float(z - 150), Float(350 - z)) / 3
            if ax <= hw + min(12, taper) { return true }
        }
        return false
    }

    static func frigate() -> HullBuilder {
        let W = 56, L = frigateLength
        let hb = HullBuilder(sx: 2 * W + 1, sy: 92, sz: L, ox: W)
        let hull = id("warship_hull"), panel = id("warship_panel"), stripe = id("warship_stripe"), deck = id("steel_grating")
        let light = id("light_panel"), iron = id("iron_block"), glass = id("armored_glass", GLASS)
        let engine = id("ship_engine"), console = id("command_console")
        // Shell: inside cells with an outside neighbour.
        for z in 0..<L {
            for y in 0..<92 { for x in -W...W where frigateInside(x, y, z) {
                let edge: Bool = !frigateInside(x + 1, y, z) || !frigateInside(x - 1, y, z) || !frigateInside(x, y + 1, z)
                    || !frigateInside(x, y - 1, z) || !frigateInside(x, y, z + 1) || !frigateInside(x, y, z - 1)
                if !edge { continue }
                // Plating: fine seams (a lighter plate line every 10 rows and every 24 along the hull, the odd plate
                // a shade lighter), a trim stripe along the upper flank, and rows of small lit windows on the flanks at
                // the deck levels, which give the hull its scale (a coarse checkerboard read as a toy: run 402).
                let (hw, _, yt) = frigateSection(z)
                var b = hull
                if y % 10 == 0 || z % 24 == 0 { b = panel }
                else if hashf(z / 8, y / 5, x / 8, 0x5A1) < 0.12 { b = panel }
                if y == Int(yt) - 6 || y == 41 { b = stripe }
                let flank: Bool = Float(abs(x)) >= hw - 0.5
                // Windows only where people live: two rows along the habitation decks midships, one under the
                // bridge, the engineering gallery aft (rows the whole length lit like a liner: run 404 shots).
                let habit: Bool = (y == 50 || y == 54) && z > 140 && z < 360 && z % 5 == 1
                let under: Bool = y == 66 && z > 270 && z < 350 && z % 3 == 1
                let aft: Bool = y == 56 && z > 392 && z < 466 && z % 6 == 1
                if flank && (habit || under || aft) { b = light }
                hb.set(x, y, z, b)
            } }
        }
        // Spinal rail cannon: a tube along the centreline, its muzzle open in the bow.
        let my = 60
        for z in 0...400 { for y in (my - 5)...(my + 5) { for x in -5...5 {
            let r: Float = sqrtf(Float(x * x + (y - my) * (y - my)))
            if r >= 3.5 && r < 4.6 { hb.set(x, y, z, iron) } else if r < 3.5 && z < 3 { hb.set(x, y, z, AIR) }
        } } }
        hb.mainGun = (V3(Float(W) + 0.5, Float(my) + 0.5, -1), V3(0, 0, -1))
        // Hangar deck (floor 26) open through both flanks, the upper deck (floor 46) above it.
        hb.fill(-27, 27, 26, 26, 160, 340, deck)
        hb.fill(-27, 27, 46, 46, 140, 360, deck)
        for z in stride(from: 166, through: 334, by: 12) { for x in stride(from: -24, through: 24, by: 12) { hb.set(x, 45, z, light) } }
        for z in stride(from: 146, through: 354, by: 16) { for x in [-20, 0, 20] { hb.set(x, 71, z, light) } }
        for z in 214...292 { for y in 27...42 { hb.set(-30, y, z, AIR); hb.set(30, y, z, AIR); hb.set(-29, y, z, AIR); hb.set(29, y, z, AIR) } }
        for x in [-30, 30] { for z in [213, 293] { for y in 27...42 { hb.set(x, y, z, stripe) } } }
        // Two parked dropships in the hangar, the same craft it launches (its hull blocks copied in; the turret ring
        // stays empty: the parked ones carry no gun).
        let ds = dropship()
        let ring = Blocks.id("ship_turret_ring"), dsHelm = Blocks.groupBase[Int(Blocks.id("ship_helm[south]"))]
        for (cx, cz) in [(-12, 230), (12, 270)] {
            for y in 0..<ds.sy { for z in 0..<ds.sz { for gx in 0..<ds.sx {
                var b = ds.blocks[gx + z * ds.sx + y * ds.sx * ds.sz]
                if b == AIR || b == ring { continue }
                if Blocks.groupBase[Int(b)] == dsHelm { b = console }      // (P449: a parked craft's wheel steered the frigate)
                hb.set(cx + gx - ds.ox, 26 + y, cz - 10 + z, b)
            } } }
        }
        for (i, z) in [180, 200, 300, 320].enumerated() {
            hb.set(26, 27, z, Blocks.id("chest") + 3)
            hb.chests.append((hb.grid(26, 27, z), i % 2 == 0 ? "steelhold_armory" : "steelhold_supply"))
        }
        // Bridge: floor 76 in the tower, armoured glass round the front, the helm, consoles, the captain's chest.
        hb.fill(-9, 9, 76, 76, 298, 335, deck)
        for x in -8...8 { for y in 80...84 { hb.set(x, y, 296 + Int(ceilf(Float(y - 72) * 0.5)), glass) } }
        for z in 304...330 { for y in 80...83 { hb.set(-10, y, z, glass); hb.set(10, y, z, glass) } }
        hb.set(0, 77, 316, Blocks.id("ship_helm[south]"))
        for x in [-6, -3, 3, 6] { hb.set(x, 77, 310, console) }
        hb.set(0, 77, 330, Blocks.id("chest"))
        hb.chests.append((hb.grid(0, 77, 330), "steelhold_vault"))
        for x in [-6, 6] { hb.set(x, 88, 320, light) }
        // Decks, hallways, cabins and staircases (P450, P461: FrigateDecks.swift; the ladders are gone).
        if !decksOff { frigateDecks(hb) }
        // Engine room: four drive cores (critical systems) and the stern nozzles glowing in their recesses.
        hb.fill(-38, 38, 20, 20, 384, 474, deck)
        for x in [-18, 18] { for cy in [30, 54] { hb.fill(x - 2, x + 2, cy - 2, cy + 2, 438, 446, engine) } }
        for x in stride(from: -30, through: 30, by: 15) { hb.set(x, 70, 410, light); hb.set(x, 70, 450, light) }
        hb.set(0, 21, 460, Blocks.id("chest"))
        hb.chests.append((hb.grid(0, 21, 460), "steelhold_supply"))
        for nx in [-20, 20] { for ny in [30, 60] {
            for y in (ny - 11)...(ny + 11) { for x in (nx - 11)...(nx + 11) {
                let r: Float = sqrtf(Float((x - nx) * (x - nx) + (y - ny) * (y - ny)))
                if r < 10 { for z in 474...479 { hb.set(x, y, z, AIR) }; hb.set(x, y, 473, light) }
                else if r < 11.5 { for z in 474...479 { hb.set(x, y, z, iron) } }
            } }
        } }
        // Crew: the helmsman on the bridge, six gunners (hangar and upper deck, each serving every sixth turret),
        // officers on the bridge and troops in the engine room.
        hb.post(0, 77, 317, .driver)
        for (x, y, z) in [(-10, 27, 200), (10, 27, 250), (0, 27, 310), (-15, 47, 180), (15, 47, 260), (0, 47, 340)] { hb.post(x, y, z, .gunner) }
        for (x, y, z) in [(-4, 77, 320), (4, 77, 312), (-20, 21, 420), (20, 21, 455)] { hb.post(x, y, z, .troop) }
        // Turrets: six dorsal, six ventral, four on the flank skirts.
        for (ti, z) in [34, 72, 170, 215, 262, 405].enumerated() {
            let (_, _, yt) = frigateSection(z)
            var top = Int(yt) + 4                                   // over the dorsal spine where it runs
            while top > 0 && !frigateInside(0, top, z) { top -= 1 }
            hb.set(0, top, z, Blocks.id("ship_turret_ring"))
            hb.turrets.append((hb.grid(0, top, z), navalTurret(hang: false, size: 4, style: [2, 1, 0, 1, 0, 2][ti]), spec([2, 1, 0, 1, 0, 2][ti], naval)))
        }
        for (ti, z) in [40, 80, 150, 350, 410, 450].enumerated() {
            var bot = 0
            while bot < 90 && !frigateInside(0, bot, z) { bot += 1 }
            // The ring sits in the bottom plate; the hung turret's cells are below the cell above the ring.
            hb.set(0, bot, z, Blocks.id("ship_turret_ring"))
            hb.turrets.append((hb.grid(0, bot, z), navalTurret(hang: true, style: ti % 2 == 0 ? 3 : 0), spec(ti % 2 == 0 ? 3 : 0, navalHung)))
        }
        for sx in [-1, 1] { for z in [205, 295] {
            let x = sx * 38
            hb.set(x, 42, z, Blocks.id("ship_turret_ring"))
            hb.turrets.append((hb.grid(x, 42, z), navalTurret(hang: false, size: 2, style: z == 205 ? 3 : 1), spec(z == 205 ? 3 : 1, naval)))
        } }
        // Missile pods along the upper flanks.
        for sx in [-1, 1] { for z in [120, 240, 340, 420] {
            let (hw, _, _) = frigateSection(z)
            let x = sx * Int(hw)
            hb.fill(x, x, 62, 64, z - 1, z + 1, iron)
            hb.pods.append((V3(Float(x + W) + 0.5 + Float(sx) * 1.5, 63.5, Float(z) + 0.5), simd_normalize(V3(Float(sx), 1.2, 0))))
        } }
        hb.joinIslands()                         // (P512: no piece of the hull hangs on nothing: FrigateLayoutCheck)
        return hb
    }

    // MARK: Ironback Crawler (bow toward -Z)

    static func crawler() -> HullBuilder {
        let W = 17
        // 84 long: the hull ends at z 76, the lowered rear ramp reaches back to z 83.
        let hb = HullBuilder(sx: 2 * W + 1, sy: 36, sz: 84, ox: W)
        let hull = id("warship_hull"), panel = id("warship_panel"), stripe = id("warship_stripe"), deck = id("steel_grating")
        let iron = id("iron_block"), glass = id("armored_glass", GLASS), wheel = id("ship_wheel"), engine = id("ship_engine")
        let light = id("light_panel"), console = id("command_console")
        func chassis(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            guard z >= 8 && z <= 73 && abs(x) <= 11 && y >= 8 && y <= 20 else { return false }
            return Float(y - 8) <= Float(z - 8) * 1.5 + 4 && Float(y - 8) <= Float(73 - z) * 2 + 6
        }
        func superstructure(_ x: Int, _ y: Int, _ z: Int) -> Bool {
            guard z >= 20 && z <= 66 && abs(x) <= 8 && y >= 21 && y <= 28 else { return false }
            return Float(z - 20) >= Float(y - 21) * 0.8 && Float(abs(x) - 5) <= Float(28 - y) * 0.7 + 3
        }
        func inside(_ x: Int, _ y: Int, _ z: Int) -> Bool { chassis(x, y, z) || superstructure(x, y, z) }
        for z in 0..<77 { for y in 0..<36 { for x in -W...W where inside(x, y, z) {
            let edge: Bool = !inside(x + 1, y, z) || !inside(x - 1, y, z) || !inside(x, y + 1, z) || !inside(x, y - 1, z)
                || !inside(x, y, z + 1) || !inside(x, y, z - 1)
            if !edge { continue }
            var b = ((z / 8) + (y / 6)) % 3 == 0 ? panel : hull
            if y == 17 { b = stripe }
            hb.set(x, y, z, b)
        } } }
        // Six great wheels under fenders.
        for zc in [18, 41, 64] {
            for sx in [-1, 1] {
                for y in 0...14 { for z in (zc - 7)...(zc + 7) {
                    let dy = Float(y) - 7, dz = Float(z - zc)
                    if dy * dy + dz * dz <= 53 { for k in 12...15 { hb.set(sx * k, y, z, wheel) } }
                } }
                hb.fill(min(sx * 16, sx * 12), max(sx * 16, sx * 12), 15, 15, zc - 9, zc + 9, hull)
                hb.fill(sx * 16, sx * 16, 12, 14, zc - 9, zc + 9, hull)
            }
            hb.fill(-11, 11, 7, 7, zc - 1, zc + 1, iron)                // axle beam
        }
        // Details: hubs on the wheels, headlights on the glacis, exhaust stacks and an antenna aft.
        for zc in [18, 41, 64] { for sx in [-1, 1] {
            for y in 4...10 { for z in (zc - 3)...(zc + 3) {
                let dy = Float(y) - 7, dz = Float(z - zc)
                if dy * dy + dz * dz <= 6.5 { hb.set(sx * 16, y, z, iron) }
            } }
        } }
        for x in [-8, -7, 7, 8] { hb.set(x, 13, 11, light) }
        for sx in [-1, 1] { for y in 21...27 { hb.set(sx * 9, y, 68, iron) }; hb.set(sx * 9, 28, 68, id("blackstone", hull)) }
        for y in 29...35 { hb.set(5, y, 60, id("iron_bars", iron)) }
        // (P507, Nov 1 12:08:59 at the crawler's helm: "instead of having that giant cannon thing on the top, replace it with
        // like another naval gun": the spinal rail cannon over the bow, a tube that never fired, and its pedestal in the
        // command deck are gone; a twin naval gun stands on the superstructure's front instead, below.)
        hb.mainGun = (V3(Float(W) + 0.5, 30.5, -1), V3(0, 0, -1))
        // Command deck: windows, helm, consoles; troop bay below with a rear ramp; engines aft.
        for x in -6...6 { for y in 23...25 { hb.set(x, y, 20 + Int(Float(y - 21) * 0.8) + 1, glass) } }
        hb.fill(-7, 7, 21, 21, 24, 64, deck)
        hb.set(0, 22, 28, Blocks.id("ship_helm[south]"))
        for x in [-4, 4] { hb.set(x, 22, 26, console) }
        hb.set(0, 27, 40, light); hb.set(0, 27, 56, light)
        hb.fill(-10, 10, 9, 9, 10, 72, deck)
        for z in stride(from: 16, through: 64, by: 12) { hb.set(0, 19, z, light) }
        // P507 (Nov 1 12:10:58-12:11:04 aboard a crawler: "we need to update the engine room on the crawler... Should
        // also be a place to fill up the guns inside"): two engine banks either side of a walkway (it was one solid lump
        // of engines), exhaust pipes over the walkway, a light, and two shell hoists where the gun crews load the
        // magazine from Shell Crates (ShipShells).
        for sx in [-1, 1] { hb.fill(min(sx * 3, sx * 6), max(sx * 3, sx * 6), 10, 13, 62, 70, engine) }
        let pipeX = id("depot_pipe_x", iron), hoist = id(ShipShells.hoistKey, iron)
        for z in [63, 66, 69] { for x in -6...6 { hb.set(x, 14, z, pipeX) } }
        hb.set(0, 14, 61, light)
        hb.set(-2, 10, 63, hoist); hb.set(2, 10, 67, hoist)
        for z in 73...73 { for y in 10...15 { for x in -4...4 { hb.set(x, y, z, AIR) } } }
        hb.set(-9, 10, 30, Blocks.id("chest") + 3); hb.chests.append((hb.grid(-9, 10, 30), "steelhold_armory"))
        hb.set(9, 10, 50, Blocks.id("chest") + 2); hb.chests.append((hb.grid(9, 10, 50), "steelhold_supply"))
        let ladder = Blocks.id("ladder")
        for y in 10...21 { hb.set(-8, y, 58, panel); hb.set(-7, y, 58, ladder + 3) }
        // Boarding (vehicle riding): a ladder up each flank between the front and middle wheels, from the ground to the
        // walkway on the chassis roof, a step and a hatch from there into the command deck; the rear ramp from the
        // troop bay to the ground (built lowered; it folds up into a door while the crawler drives: crawlerRamp).
        // P507 (Nov 1 12:07:01, "Look at that giant ladder hanging off the crawler. It just looks like shit"): the ladder
        // is let into the flank, flush with the chassis side, on a steel backing (it stood a block proud the whole height).
        for sx in [-1, 1] {
            for y in 0...20 { hb.set(sx * 10, y, 29, panel) }
            for y in 0...20 { hb.set(sx * 11, y, 29, ladder + (sx > 0 ? 3 : 2)) }
            for y in 22...23 { hb.set(sx * 8, y, 30, AIR) }
            hb.set(sx * 9, 21, 30, Capital.id(sx > 0 ? "steel_plating_stairs[west]" : "steel_plating_stairs[east]", panel))
        }
        for (c, b) in crawlerRamp(down: true) { hb.set(c.x, c.y, c.z, b) }
        crawlerDense(hb, chassis: chassis, upper: superstructure, inside: inside)     // (P511: first: its fittings take their places)
        crawlerRooms(hb, chassis: chassis)
        // Crew: a driver at the helm, a gunner for each turret (two heavies served from the command deck, four
        // sponsons from the chassis), and a squad of troops in the bay who go out by the rear ramp.
        hb.post(0, 22, 29, .driver)
        for (x, y, z) in [(2, 22, 53), (-2, 22, 61), (2, 22, 33), (-9, 10, 15), (-9, 10, 68), (9, 10, 15), (9, 10, 68)] { hb.post(x, y, z, .gunner) }
        for (x, y, z) in [(-5, 10, 40), (5, 10, 55), (-3, 10, 46), (3, 10, 34), (-5, 10, 52), (4, 10, 44), (0, 22, 36), (-3, 22, 47)] {
            hb.post(x, y, z, .troop)
        }
        // P511 (Nov 2 08:49:46-08:49:49, in its bunk room: "The crew's not even this many. So you need to expand the crew"):
        // the upper deck's own hands, one for each bed left over (22 beds, 16 posts): the radio room, the bunks, the mess,
        // the workshop and the sick bay. They stay aboard (the troops sent out are the lower deck's).
        for (x, y, z) in [(0, 16, 18), (-2, 16, 25), (2, 16, 33), (0, 16, 46), (6, 16, 53), (-7, 16, 54)] {
            hb.post(x, y, z, .troop)
        }
        // Turrets: two heavy mounts on the superstructure and (P507) a twin on its front over the command deck where the
        // rail cannon was, four autocannon sponsons at the chassis corners.
        for (ti, z) in [54, 63, 32].enumerated() {
            var top = 28
            while top > 20 && !inside(0, top, z) { top -= 1 }
            hb.set(0, top, z, Blocks.id("ship_turret_ring"))
            let style = [2, 1, 0][ti]
            hb.turrets.append((hb.grid(0, top, z), navalTurret(hang: false, size: 3, style: style), spec(style, heavy)))
        }
        for sx in [-1, 1] { for z in [14, 70] {
            var top = 20
            while top > 8 && !inside(sx * 10, top, z) { top -= 1 }
            hb.set(sx * 10, top, z, Blocks.id("ship_turret_ring"))
            hb.turrets.append((hb.grid(sx * 10, top, z), autocannon(), auto))
        } }
        for sx in [-1, 1] { for z in [32, 44] {
            hb.fill(sx * 8, sx * 8, 25, 26, z, z + 1, iron)
            hb.pods.append((V3(Float(sx * 9 + W) + 0.5, 26.5, Float(z) + 1), simd_normalize(V3(Float(sx) * 0.5, 1.5, -0.3))))
        } }
        hb.joinIslands()                         // (P512: no piece of the hull hangs on nothing: FrigateLayoutCheck)
        return hb
    }

    // P511 (Nov 2 12:13, "the crawler's interior design sucks. Should be dense, no big open room. A way to take up space
    // is actual gun stuff underneath the positions. Like, things that hold ammo... Each wheel can have its own engine
    // or something too and have a realistic design set up for the whole thing"). Diesel-electric, as a real land
    // dreadnought would be: the engine banks aft turn generators, a cable run along each side of the lower deck carries
    // their power to a drive motor at every wheel (a motor housing, a gearbox, the shaft out through the hull; the
    // motors count among its engines, so shooting them out slows it). The command deck, one long open room under the
    // three gun mounts, is split by two bulkheads into the bridge, the gun mounts' ammunition rooms and the fire control
    // room between them: under each mount its trunk (the turret's armoured column down to the deck) with a shell hoist
    // in its face, ready racks and crates round it, propellant charges in barrels aft; consoles for the gunners and the
    // fire controllers. The aisles either side, the gunners' and the crew's places, the hatches and the ladder stay clear.
    static func crawlerDense(_ hb: HullBuilder, chassis: (Int, Int, Int) -> Bool, upper: (Int, Int, Int) -> Bool,
                             inside: (Int, Int, Int) -> Bool) {
        func g(_ n: String, _ f: BlockID) -> BlockID { id(n, f) }
        let iron = id("iron_block"), panel = id("warship_panel"), engine = id("ship_engine"), light = id("light_panel")
        let crate = g("ammo_crate", iron), ash = g("ash_crate", crate), cab = g("data_cabinet", iron), barrel = g("barrel", iron)
        let console = id("command_console"), term = g("greywall_terminal", console), table = g("greywall_map_table", console)
        let hoist = g(ShipShells.hoistKey, iron), bars = g("iron_bars", iron), gen = g("generator_vent", iron)
        let pipeX = g("depot_pipe_x", bars), pipeZ = g("depot_pipe_z", bars), armour = g("warship_hull", iron)
        func low(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) {
            guard chassis(x, y, z), hb.get(x, y, z) == AIR else { return }
            hb.set(x, y, z, b)
        }
        // (the command deck's air: inside the superstructure, off its skin)
        func deck(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) {
            guard upper(x, y, z), y >= 22, hb.get(x, y, z) == AIR,
                  inside(x + 1, y, z) && inside(x - 1, y, z) && inside(x, y + 1, z) && inside(x, y, z + 1) && inside(x, y, z - 1) else { return }
            hb.set(x, y, z, b)
        }
        func deckStack(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID, _ h: Int) { for k in 0..<h { deck(x, y + k, z, b) } }
        // Drive motors: one at each wheel, on the lower deck against the hull side by its axle.
        for zc in [18, 41, 64] { for sx in [-1, 1] {
            for z in (zc - 1)...(zc + 1) { for y in 10...11 { low(sx * 10, y, z, engine) } }
            low(sx * 10, 12, zc, gen)                                   // (its cooling vent)
            low(sx * 9, 10, zc, iron)                                   // the gearbox
            low(sx * 9, 11, zc, pipeX)                                  // the shaft out to the wheel
        } }
        // The cable runs from the generators aft to the motors, under the upper deck along both sides.
        for sx in [-1, 1] { for z in 17...66 { low(sx * 9, 14, z, pipeZ) } }
        // The command deck. Clear: the aisles (x -5...-3 and 3...5) and the centreline forward of the first trunk, the
        // posts, the hatches (8, 30) and the ladder head (-7, 58).
        var keep = Set<IVec3>()
        for (x, z) in [(2, 53), (-2, 61), (2, 33), (0, 36), (-3, 47), (0, 29), (-4, 26), (4, 26)] { for y in 22...23 { keep.insert(IVec3(x, y, z)) } }
        for sx in [-1, 1] { for x in 5...7 { for z in 29...31 { for y in 22...23 { keep.insert(IVec3(sx * x, y, z)) } } } }
        for x in -7...(-5) { for z in 57...59 { for y in 22...24 { keep.insert(IVec3(x, y, z)) } } }
        func put(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) {
            guard !keep.contains(IVec3(x, y, z)), abs(x) < 3 || abs(x) > 5 || b == panel else { return }
            deck(x, y, z, b)
        }
        // The bridge: cabinets and the chart table along the walls behind the helm.
        for sx in [-1, 1] { for z in 22...27 { put(sx * 7, 22, z, cab); put(sx * 7, 23, z, cab) } }
        put(-6, 22, 28, table); put(6, 22, 28, term)
        // Two bulkheads across the deck (z 37 and 49), a door in each aisle.
        for z in [37, 49] { for x in -7...7 where !(abs(x) >= 3 && abs(x) <= 4) { for y in 22...27 { deck(x, y, z, panel) } }
            for sx in [-1, 1] { for x in 3...4 { for y in 25...27 { deck(sx * x, y, z, panel) } } }
            deck(0, 26, z, light)
        }
        // The gunners' consoles beside their posts (before the racks take the places).
        put(2, 22, 52, console); put(-2, 22, 60, console); put(2, 22, 34, console)
        // Each mount's trunk under its ring, a hoist in its face, ready racks and crates round it.
        for zc in [32, 54, 63] {
            var top = 28
            while top > 20 && !inside(0, top, zc) { top -= 1 }
            for z in (zc - 1)...(zc + 1) { for x in -1...1 { for y in 22..<top { put(x, y, z, armour) } } }
            put(0, 22, zc - 2, hoist); put(0, 23, zc - 2, bars)
            for sx in [-1, 1] { for z in (zc - 2)...(zc + 2) {
                // (beside the trunk; the forward mount's port side stays open: the way in from the port hatch, ridecheck)
                if abs(z - zc) <= 1 && !(zc == 32 && sx < 0) { put(sx * 2, 22, z, z % 2 == 0 ? crate : ash); put(sx * 2, 23, z, bars) }
                put(sx * 6, 22, z, crate); put(sx * 6, 23, z, ash); put(sx * 7, 22, z, ash); put(sx * 7, 23, z, crate); put(sx * 7, 24, z, crate)
            } }
        }
        // Fire control (z 38...48): rangefinder and plotting consoles along both walls, the plot table down the middle.
        for sx in [-1, 1] { for z in stride(from: 38, through: 47, by: 2) { put(sx * 7, 22, z, z % 4 == 2 ? term : console); put(sx * 7, 23, z, cab)
            put(sx * 7, 22, z + 1, cab); put(sx * 7, 23, z + 1, cab); put(sx * 6, 22, z + 1, g("oak_chair[\(sx < 0 ? "west" : "east")]", AIR)) } }
        for z in 41...44 { put(0, 22, z, table); put(-1, 22, z, table); put(1, 22, z, table) }
        // Propellant aft of the last mount, in barrels, two high.
        for x in -7...7 where abs(x) < 3 || abs(x) > 5 { for z in 65...66 { put(x, 22, z, barrel); put(x, 23, z, barrel) } }
    }

    // P510 (Nov 1 20:34:20-39 aboard: "we need an engine room for the crawler... It also needs to be more dense inside...
    // realistically laid out"): the chassis was one bay ten blocks high with the engines at the back. It is two decks
    // now under a two-storey engine hall. The lower deck (standing at 10): the magazine forward (ammunition racks, the
    // sponson gunners' posts kept clear), the troop compartment (benches facing in along both sides, lockers, weapon
    // racks; the aisle down the middle kept clear to the ramp), a bulkhead with a wide door. The upper deck (standing at
    // 16, a grating floor at 15): the radio room forward, bunks, the mess, the workshop and sick bay, ladders between
    // the decks. The engine hall (z 60 on): the two engine banks with their exhaust stacks to the roof, fuel tanks and
    // generators along the sides, the engineer's panel, a gantry along each side at the upper deck's height. The
    // command deck gets its chart table, signal consoles and cabinets. Only air inside the hull is filled, the
    // centreline aisle, the ramp's way round the engines, the hatches, ladders and crew posts are left clear.
    static func crawlerRooms(_ hb: HullBuilder, chassis: (Int, Int, Int) -> Bool) {
        func g(_ n: String, _ f: BlockID) -> BlockID { id(n, f) }
        let panel = id("warship_panel"), grating = id("steel_grating"), light = id("light_panel"), iron = id("iron_block")
        let ladder = Blocks.id("ladder"), crate = g("ammo_crate", iron), ash = g("ash_crate", crate), cab = g("data_cabinet", iron)
        let console = id("command_console"), term = g("greywall_terminal", console), barrel = g("barrel", iron)
        let tank = g("depot_tank", iron), band = g("depot_tank_band", tank), vent = g("generator_vent", iron)
        let pipeY = g("depot_pipe_y", g("iron_bars", iron)), pipeZ = g("depot_pipe_z", g("iron_bars", iron))
        let post = g("oak_fence", iron), plate = g("oak_pressure_plate", AIR), bench = g("steel_plating_stairs", panel)
        // (only into the chassis' air, never into its hull or a fitting already there)
        func room(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID) {
            guard chassis(x, y, z), hb.get(x, y, z) == AIR else { return }
            hb.set(x, y, z, b)
        }
        func stack(_ x: Int, _ y: Int, _ z: Int, _ b: BlockID, _ h: Int) { for k in 0..<h { room(x, y + k, z, b) } }
        func bed(_ x: Int, _ zFoot: Int, _ zHead: Int, _ colour: String) {
            guard Blocks.has("\(colour)_bed"), Blocks.has("\(colour)_bed_head") else { return }
            let s = BlockID(zHead < zFoot ? 1 : 0)
            room(x, 16, zFoot, Blocks.id("\(colour)_bed") + s); room(x, 16, zHead, Blocks.id("\(colour)_bed_head") + s)
        }
        func chair(_ x: Int, _ y: Int, _ z: Int, _ face: String) {
            let n = face == "north" ? "oak_chair" : "oak_chair[\(face)]"
            if Blocks.has(n) { room(x, y, z, Blocks.id(n)) }
        }
        let stairE = Blocks.has("steel_plating_stairs[east]") ? Blocks.id("steel_plating_stairs[east]") : bench
        let stairW = Blocks.has("steel_plating_stairs[west]") ? Blocks.id("steel_plating_stairs[west]") : bench
        // The upper deck's floor over the magazine, troops and bunks (z 14-59); the engine hall stays open to the roof.
        // Wells for the ladders (the command deck's at -7, 58; one forward at 7, 21) and a light every few steps.
        for z in 14...59 { for x in -10...10 { room(x, 15, z, (x == 0 || abs(x) == 6) && z % 8 == 2 ? light : grating) } }
        hb.set(-7, 15, 58, ladder + 3)
        for y in 10...16 { hb.set(8, y, 21, panel); hb.set(7, y, 21, ladder + 2) }
        // Lower deck: the magazine forward, racks two and three high along both walls (the sponson gunners' places at
        // 9, 15 and their way to the aisle kept clear).
        for sx in [-1, 1] { for z in 11...20 where !(z >= 14 && z <= 16) {
            stack(sx * 10, 10, z, z % 2 == 0 ? crate : ash, 3)
            if z != 20 { stack(sx * 9, 10, z, crate, 2) }
        } }
        for z in [12, 13] { for x in [-5, -4, 4, 5] { stack(x, 10, z, ash, 2) } }
        room(-3, 10, 19, id(ShipShells.hoistKey, iron)); room(3, 10, 19, barrel)
        // The troop compartment: benches facing in along both walls, a locker or a weapon rack between every few seats,
        // a light over the aisle (the chests at -9, 30 and 9, 50 and the flank ladders' backing at 29 stay).
        for sx in [-1, 1] { for z in 22...57 {
            let wall = sx * 10, seat = sx * 8
            if z % 6 == 0 { stack(wall, 10, z, cab, 2); continue }
            if z % 6 == 3 { stack(wall, 10, z, crate, 1); room(wall, 11, z, g("iron_bars", iron)); continue }
            room(seat, 10, z, sx < 0 ? stairE : stairW)
            room(wall, 10, z, panel)
        } }
        // The bulkhead to the engine hall, a door the aisle's width and a way along each side.
        for x in -10...10 where abs(x) > 2 && abs(x) < 7 { for y in 10...14 { room(x, y, 59, panel) } }
        for x in [-2, 2] { room(x, 14, 59, panel) }
        // The upper deck (standing at 16): the radio room forward.
        for sx in [-1, 1] { for z in 15...19 { stack(sx * 10, 16, z, cab, 2) } }
        for x in [-8, -7, 7, 8] { room(x, 16, 20, console); chair(x, 16, 19, "south") }
        room(-4, 16, 16, g("greywall_map_table", console)); room(-3, 16, 16, g("greywall_map_table", console))
        room(4, 16, 16, term); chair(4, 16, 17, "north")
        // Bunks: heads to the bulkheads in pairs along both walls, a locker at each pair.
        for sx in [-1, 1] { for z0 in stride(from: 23, through: 39, by: 4) {
            for x in [sx * 9, sx * 7] { bed(x, z0 + 1, z0, sx < 0 ? "light_gray" : "white") }
            room(sx * 10, 16, z0, barrel); room(sx * 10, 16, z0 + 1, cab)
        } }
        // The mess: a long table with chairs either side.
        for z in 43...49 { room(-6, 16, z, post); room(-6, 17, z, plate); chair(-7, 16, z, "east"); chair(-5, 16, z, "west") }
        for z in 43...49 { room(6, 16, z, post); room(6, 17, z, plate); chair(7, 16, z, "west"); chair(5, 16, z, "east") }
        for sx in [-1, 1] { stack(sx * 10, 16, 44, barrel, 1); stack(sx * 10, 16, 46, g("bookshelf", cab), 2) }
        // The workshop and sick bay.
        room(8, 16, 52, g(GunsmithBench.key, iron)); room(8, 16, 54, g("anvil", iron)); stack(10, 16, 53, crate, 2)
        for z in [51, 55] { stack(10, 16, z, cab, 2) }
        for z0 in [52, 55] { bed(-9, z0 + 1, z0, "white") }
        room(-10, 16, 51, g("brewing_stand", cab)); stack(-10, 16, 58, cab, 2)
        // The engine hall: exhaust stacks from the engine banks to the roof, fuel tanks along the walls, generators and
        // the engineer's panel by the bulkhead, a gantry along each wall at the upper deck's height.
        for sx in [-1, 1] { for z in [64, 68] { for y in 14...19 { room(sx * 4, y, z, pipeY) } } }
        for x in -8...8 { room(x, 16, 60, g("iron_bars", iron)) }                 // (the upper deck's rail over the hall)
        for sx in [-1, 1] {
            // (the sponson gunner's place at 9, 68 gets a bay three wide: the tanks either side of it pressed him)
            for z in 61...71 where z < 66 || z > 69 {
                stack(sx * 10, 10, z, (z % 3 == 0) ? band : tank, 4)
            }
            for z in 60...71 { room(sx * 9, 15, z, grating) }
            room(sx * 8, 10, 61, vent); room(sx * 8, 11, 61, vent)
            for z in 61...71 { room(sx * 10, 15, z, grating) }
            for z in 60...71 { room(sx * 7, 18, z, pipeZ) }
        }
        room(-8, 10, 60, console); room(8, 10, 60, term)
        for z in [62, 66, 70] { room(0, 19, z, light) }
    }

    // The crawler's rear ramp cells (builder coordinates): lowered, steel stairs from the bay floor (y 9) down to the
    // ground behind the hull (y 0 at z 83); raised, a door plate closing the bay's rear opening.
    static func crawlerRamp(down: Bool) -> [(IVec3, BlockID)] {
        let stairs = id("steel_plating_stairs", id("stone_brick_stairs", STONE)), plate = id("warship_panel")
        var out: [(IVec3, BlockID)] = []
        for k in 0...9 { for x in -2...2 { out.append((IVec3(x, 9 - k, 74 + k), down ? stairs : AIR)) } }
        for y in 9...15 { for x in -4...4 where !(down && y == 9 && abs(x) <= 2) { out.append((IVec3(x, y, 74), down ? AIR : plate)) } }
        return out
    }

    // MARK: Ships from a builder (any thread)

    // MARK: Stormwarden dropship (bow toward -Z)

    // A 19-block troop carrier: a boxy fuselage with an open troop bay and rear ramp, a glazed cockpit nose, stub
    // wings with engine pods glowing aft, a tail fin and an autocannon on its back.
    // P461: what a flown craft breaks through (Ship crush) and lands through: leaves, plants, logs, wood, wool, glass,
    // snow; not ground, stone, metal or ore.
    // What a ground crawler drives through (crawler crush), per block state: trees, wood, glass, cactus, bamboo.
    static let crawlerSoft: [Bool] = (0..<Blocks.count).map { i in
        let key = Blocks.key(Blocks.groupBase[i])
        return key.hasSuffix("_leaves") || key.hasSuffix("_log") || key.hasSuffix("_planks") || key.hasSuffix("_fence")
            || key.contains("glass") || key.hasSuffix("_wood") || key.contains("mushroom_block") || key == "cactus" || key == "bamboo"
    }
    static func crushable(_ b: BlockID) -> Bool {
        guard !Blocks.isLiquid(b), Blocks.hardness[Int(b)] >= 0 else { return false }
        switch Blocks.def(b).sound {
        case .leaves, .wood, .wool, .glass: return Blocks.hardness[Int(b)] < 3.5
        case .plant, .grass, .snow: return !Blocks.opaque[Int(b)]          // plants and snow layers, not the grass block
        default: return false
        }
    }
    // The highest block in the column that a landing craft rests on (the top block, under any crown of leaves, trunk
    // or plants it would crush on the way down).
    static func firmTop(_ w: World, _ x: Int, _ z: Int) -> Int {
        var y = w.topY(x, z)
        var k = 0
        while y > 1 && k < 48 && (w.block(x, y, z) == AIR || crushable(w.block(x, y, z))) && !w.groundAt(x, y, z) { y -= 1; k += 1 }
        // P461 (Oct 25 16:43, "if I like drop this drop ship into the volcano, the lava just degrades it"): lava holds
        // nothing up: a craft let down onto it settles two blocks in, and melts (ShipMelt).
        if Blocks.fluidKind[Int(w.block(x, y, z))] == 2 { return y - 2 }
        return y
    }

    static func dropship() -> HullBuilder {
        let W = 6
        let hb = HullBuilder(sx: 2 * W + 1, sy: 8, sz: 20, ox: W)
        let hull = id("warship_hull"), panel = id("warship_panel"), stripe = id("warship_stripe")
        let glass = id("armored_glass", GLASS), engine = id("ship_engine"), light = id("light_panel"), deck = id("steel_grating")
        hb.fill(-2, 2, 1, 4, 4, 17, hull)
        hb.fill(-1, 1, 2, 3, 6, 17, AIR)                         // troop bay, open at the rear ramp
        hb.fill(-1, 1, 1, 1, 6, 17, deck)
        hb.fill(-2, 2, 4, 4, 8, 15, panel)
        for z in 4...17 { hb.set(-2, 3, z, stripe); hb.set(2, 3, z, stripe) }
        hb.fill(-1, 1, 1, 2, 1, 3, hull)                         // nose
        hb.fill(-1, 1, 3, 4, 1, 3, glass)                        // cockpit glazing
        hb.set(0, 3, 0, glass)
        // P66 (Oct 11 evening playtest: "the pilot can hardly see"): the bulkhead between the helm and the glazing was
        // solid hull at eye height. Open it into a cockpit, with side windows beside the helm.
        hb.fill(-1, 1, 2, 3, 3, 5, AIR)
        hb.fill(-1, 1, 3, 4, 2, 3, glass)
        for sx in [-2, 2] { hb.set(sx, 3, 4, glass); hb.set(sx, 3, 5, glass); hb.set(sx, 3, 6, glass) }
        for sx in [-1, 1] {
            hb.fill(min(sx * 3, sx * 4), max(sx * 3, sx * 4), 3, 3, 9, 13, panel)     // stub wings
            hb.fill(sx * 5, sx * 5, 2, 3, 8, 14, hull)           // engine pods
            hb.set(sx * 5, 2, 14, engine); hb.set(sx * 5, 3, 14, engine)
            hb.set(sx * 5, 2, 15, light); hb.set(sx * 5, 3, 15, light)
        }
        hb.fill(0, 0, 5, 6, 13, 17, panel)                       // tail fin
        hb.set(0, 2, 7, light); hb.set(0, 2, 15, light)
        hb.set(0, 4, 10, Blocks.id("ship_turret_ring"))
        hb.turrets.append((hb.grid(0, 4, 10), autocannon(), auto))
        hb.set(0, 2, 6, Blocks.id("ship_helm[south]"))           // the pilot's controls at the front of the bay (commandeer)
        // P334 (a): a crew that flies and fights it: the pilot at the controls, the gunner under the turret ring.
        hb.post(0, 2, 7, .driver)
        hb.post(0, 2, 10, .gunner)
        return hb
    }

    static func makeShips(_ hb: HullBuilder, ids: [Int], name: String, role: String, faction: Faction) -> [Ship] {
        let hull = ShipGrid(sx: hb.sx, sy: hb.sy, sz: hb.sz, blocks: hb.blocks)
        if role != "dropship" { Capital.addGunStations(hull, rings: hb.turrets.map { $0.ring }) }     // P512 (GunStations.swift)
        let s = Ship(id: ids[0], grid: hull)
        s.name = name
        s.role = role
        s.kinematic = true
        s.faction = faction.rawValue
        s.rebuild()
        for (c, table) in hb.chests {
            let be = BlockEntity(.chest)
            var rng = SRng(UInt64(bitPattern: Int64(c.x * 73856093 ^ c.z * 19349663 ^ c.y * 83492791)) | 1)
            Loot.fill(be.container, table: table, rng: &rng)
            s.blockEntities[c] = be
        }
        var out = [s]
        for (i, (ring, tb, spec)) in hb.turrets.enumerated() where i + 1 < ids.count {
            var lo = IVec3(Int.max, Int.max, Int.max), hi = IVec3(Int.min, Int.min, Int.min)
            for c in tb.cells.keys {
                lo = IVec3(min(lo.x, c.x), min(lo.y, c.y), min(lo.z, c.z)); hi = IVec3(max(hi.x, c.x), max(hi.y, c.y), max(hi.z, c.z))
            }
            let tg = ShipGrid(sx: hi.x - lo.x + 1, sy: hi.y - lo.y + 1, sz: hi.z - lo.z + 1)
            for (c, b) in tb.cells { tg.set(c.x - lo.x, c.y - lo.y, c.z - lo.z, b) }
            let t = Ship(id: ids[i + 1], grid: tg)
            t.name = name + " turret"
            t.faction = faction.rawValue
            t.rebuild()
            t.parent = s
            t.parentId = s.id
            t.mountLocal = V3(Float(ring.x) + 0.5, Float(ring.y) + 1, Float(ring.z) + 0.5)
            t.pivot = V3(0.5 - Float(lo.x), -Float(lo.y), 0.5 - Float(lo.z))
            t.gunSpeed = spec.speed; t.gunGravity = spec.gravity; t.gunPower = spec.power; t.reloadTime = spec.reload
            t.pitchMin = spec.pitchMin; t.pitchMax = spec.pitchMax; t.gunScatter = spec.scatter
            // P477: the crews lay a barrelled gun for its own shell (flat and fast), not the old lobbed ball.
            if role != "dropship", t.cannonCalibre.contains(where: { $0 > 0 }) { (t.gunSpeed, t.gunGravity) = t.shellFlight }
            t.reload = Float(i % 5) * 0.6                                     // staggered first volleys
            out.append(t)
        }
        return out
    }
}

// MARK: Blocks and textures

extension BlockRegistry {
    func registerCapitalBlocks() {
        // Warship plate: tougher than stone against blasts (resistance 9; steel plating is 600, which no shell could
        // ever break), so naval guns and rail slugs tear real holes in a hull. (P476: the hull skin is armour grade now,
        // Armour in MilitaryBase.swift: shells and the main gun bite it, nothing smaller does.)
        for (n, disp) in [("warship_hull", "Warship Hull"), ("warship_panel", "Warship Panel"), ("warship_stripe", "Warship Trim")] where !has(n) {
            var d = BlockDef(n, disp)
            d.tex = [n]
            d.hardness = 8; d.resistance = 9; d.tool = .pickaxe; d.requiresTool = true; d.harvestLevel = 2; d.sound = .stone
            if Armour.skins.contains(n) { Armour.harden(&d) }                 // P476: the hull skin is armour
            add(d)
        }
        registerCapitalFactionBlocks()
        registerMeridianBlocks()
        registerMeridianEngineering()
        registerShellHoist()                       // P507 (ShipShells.swift)
    }
}

extension TextureGen {
    static func capitalPainters(_ p: inout [String: Painter]) {
        capitalFactionPainters(&p)
        meridianPainters(&p)
        meridianEngineeringPainters(&p)
        shellHoistPainters(&p)                     // P507 (ShipShells.swift)
        p["warship_hull"] = { x, y in
            if y == 0 || x == 0 { return hex(0x5C636B) }
            if y == 15 || x == 15 { return hex(0x30353B) }
            if (x == 7 || x == 8) && y % 5 == 2 { return hex(0x3A4047) }              // panel seam rivets
            return hex(0x4A5058, 0.94 + 0.04 * r(x / 4, y, 2101) + 0.03 * r(x, y, 2102))
        }
        p["warship_panel"] = { x, y in
            if y == 0 || x == 0 { return hex(0x8A9198) }
            if y == 15 || x == 15 { return hex(0x484E55) }
            let vent = y >= 5 && y <= 10 && x >= 3 && x <= 12 && y % 2 == 1
            return hex(vent ? 0x50565D : 0x6D747C, 0.95 + 0.04 * r(x, y, 2103))
        }
        p["warship_stripe"] = { x, y in
            if y < 3 || y > 12 { return hex(0x3E444B, 0.95 + 0.04 * r(x, y, 2104)) }
            let chevron = ((x + (y > 7 ? 15 - y : y)) / 3) % 2 == 0
            return hex(chevron ? 0xC8A23A : 0x2C3035, 0.94 + 0.05 * r(x, y, 2105))
        }
    }
}

// MARK: Spawning, AI, factions

extension Ship {
    var factionValue: Faction {
        let r = root
        if r.faction != 0, let f = Faction(rawValue: r.faction) { return f.side }
        switch r.role {
        case "frigate", "carriage": return .steelhold
        case "capfrigate": return .meridian
        case "warfrigate": return .stormwarden
        case "crawler": return .greywall                  // (P504: Greywall's, was the Ironback Legion's)
        case "sloop": return .corsairs                   // T15 (Pirates.swift)
        case NavalPatrol.role: return .meridian          // P243 (NavalPatrol.swift)
        default: return .none
        }
    }
}

extension Ship {
    // Frigates fly (the Stormwarden and Capital ones); the crawler drives.
    var isFlyingCapital: Bool { role == "warfrigate" || role == "capfrigate" }
}

extension Mob {
    var factionValue: Faction {
        // P507 (Nov 1 12:38:28-12:38:32, a Greywall truck bringing reinforcements "somehow blew up... like the soldier
        // shot the truck"): an Ash-built vehicle given to another side (Greywall's reinforcement trucks, the Capital's
        // radio trucks, a Boreal station's, a Capital wreck's) is that side's. Every Ash kind was the Ashguard's, so
        // the base's own soldiers took their truck for the enemy and shot it to pieces at the gate.
        if kind.ash { return faction != 0 ? (Faction(rawValue: faction) ?? .ashguard).side : .ashguard }
        if posse == 3 || posse == Prisoners.posse || posse == Marauders.posse { return .none }        // R21 (+ P347's prisoners): a bounty hunter on the soldier AI belongs to no faction (BountyHunters)
        guard Soldier.rank(kind) != nil || kind == .deckGun else { return .none }
        return faction != 0 ? (Faction(rawValue: faction) ?? .steelhold).side : .steelhold
    }
}

extension ShipManager {
    // P464: the capital vessels he has taken (saved in takencaps.json, Ships.swift) come back where he left them, his,
    // unmanned and whole (their grids are too big to save: the hull is built afresh from its plans).
    func restoreTaken() {
        guard !takenStarted else { return }
        takenStarted = true
        for c in takenToRestore where c.pos.count == 3 && c.rot.count == 4 {
            let p = V3(c.pos[0], c.pos[1], c.pos[2])
            spawnCapital(c.kind, home: IVec3(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z))), yaw: 0, region: nil,
                         faction: Faction(rawValue: c.faction), taken: (p, Quat(vector: V4(c.rot[0], c.rot[1], c.rot[2], c.rot[3])), c.name),
                         takenSave: c)
        }
        takenToRestore.removeAll { $0.pos.count != 3 || $0.rot.count != 4 }     // (the rest leave the list as each is installed)
    }

    // Starts building a capital ship on a worker thread (sync: here and now, for the harness). It appears with its
    // turrets when finished (capitalTick picks it up).
    // (taken: one of his, built where he left it.)
    func spawnCapital(_ kind: String, home: IVec3, yaw: Float, region: String?, sync: Bool = false, faction: Faction? = nil,
                      taken: (V3, Quat, String)? = nil, takenSave: ShipManager.TakenCap? = nil) {
        if let r = region { capitalPending.insert(r) }
        let ids = (0..<24).map { _ in newId() }
        let gen = world.gen
        let work: () -> ([Ship], CapitalState) = {
            let frigate = kind != "crawler"
            let cap = kind == "capfrigate"
            let hb = cap ? Capital.capitalFrigate() : (frigate ? Capital.frigate() : Capital.crawler())
            let own: Faction = (faction ?? (cap ? .meridian : (frigate ? .stormwarden : .greywall))).side
            let name = cap ? "Meridian Frigate" : (frigate ? "Stormwarden Frigate" : (own == .steelhold ? "Capital Crawler" : "Ironback Crawler"))
            let ships = Capital.makeShips(hb, ids: ids, name: name, role: kind, faction: own)
            let s = ships[0]
            // (batch 3.4) a taken one comes back as he left her: her hull's cells and her chests from the save.
            let asBuilt = s.blockCount
            if let ts = takenSave, let size = ts.size, let pal = ts.palette, let cells = ts.cells,
               let blocks = ShipManager.unpackGrid(size, pal, cells) {
                s.grid = ShipGrid(sx: size[0], sy: size[1], sz: size[2], blocks: blocks)
                s.rebuild()
                if let ents = ts.entities {
                    s.blockEntities = [:]
                    for (k, v) in ents {
                        let p = k.split(separator: ",").compactMap { Int($0) }
                        if p.count == 3 { s.blockEntities[IVec3(p[0], p[1], p[2])] = v }
                    }
                }
            }
            let st = CapitalState()
            st.region = region
            st.engines0 = s.engines
            st.mainGunMuzzle = hb.mainGun.0
            st.mainGunDir = hb.mainGun.1
            st.mainGunLength = hb.mainGunLength
            st.pods = hb.pods
            st.exhausts = hb.exhausts
            if let thr = Blocks.has("frigate_thruster") ? Blocks.id("frigate_thruster") : nil, !hb.exhausts.isEmpty {
                let gr = s.grid
                for e in hb.exhausts {
                    let ex = Int(floor(e.x)), ey = Int(floor(e.y)), ez = Int(floor(e.z))
                    for y in (ey - 7)...(ey + 7) { for z in (ez - 7)...(ez + 1) { for x in (ex - 7)...(ex + 7) where gr.get(x, y, z) == thr {
                        let c = IVec3(x, y, z)
                        if !st.thrustCells.contains(c) { st.thrustCells.append(c) }
                    } } }
                }
                st.thrustLive = st.thrustCells.count
            }
            if cap, Blocks.has("frigate_reactor") {
                let core = Blocks.id("frigate_reactor"), gr = s.grid, c = hb.grid(0, 17, 128)
                for y in thru(max(0, c.y - 12), (c.y + 12)) { for z in (c.z - 10)...(c.z + 10) { for x in (c.x - 10)...(c.x + 10) where gr.get(x, y, z) == core {
                    st.reactorCells.append(IVec3(x, y, z))
                } } }
                st.reactorLive = st.reactorCells.count
            }
            st.blocks0 = asBuilt
            st.crew = hb.crew
            st.crewRoles = hb.crewRoles + [CrewRole](repeating: .troop, count: max(0, hb.crew.count - hb.crewRoles.count))
            st.wheels = Capital.vehicleWheels(s)
            do {                                                  // (frigates too: P325's drive readout)
                let kinds = ShipParts.kinds, gr = s.grid
                for y in 0..<gr.sy { for z in 0..<gr.sz { for x in 0..<gr.sx {
                    let b = gr.get(x, y, z)
                    if kinds[Int(b)] == .engine { st.engineCells.append((IVec3(x, y, z), b)) }
                } } }
            }
            st.ramp = V3(Float(hb.ox) + 0.5, 1, Float(hb.sz) + 3)
            st.sight = cap ? 260 : (frigate ? 300 : 210)
            st.orbitDir = (home.x + home.z) % 2 == 0 ? 1 : -1
            st.groundOffset = s.com.y - s.localMin.y
            let hx = Float(home.x) + 0.5, hz = Float(home.z) + 0.5
            if frigate {
                // Cruise with the keel 30 above the highest ground under the hull's length.
                var top = 0
                for k in -4...4 { for j in -1...1 {
                    let h = gen.column(home.x + k * 60, home.z + j * 40).height
                    top = max(top, h)
                } }
                let keel = s.com.y - s.localMin.y
                let maxY = Float(CH - 4) - (s.localMax.y - s.com.y)
                st.groundMax = Float(top)
                s.pos = V3(hx, min(maxY, Float(max(top, SEA)) + Capital.cruiseClearance(kind) + keel), hz)
                s.hoverY = s.pos.y
            } else {
                let h = gen.column(home.x, home.z).height
                s.pos = V3(hx, Float(h + 1) + st.groundOffset, hz)
            }
            s.rot = Quat(angle: yaw, axis: V3(0, 1, 0))
            if let (p, q, n) = taken {
                s.pos = p; s.rot = q
                if frigate { s.hoverY = p.y }
                s.name = n
                s.captured = true
                st.crewDone = Set(st.crew.indices)                // (no crew of theirs aboard)
                st.announced = true
            }
            s.prevPos = s.pos; s.prevRot = s.rot
            s.home = V3(hx, s.pos.y, hz)
            s.initialBlocks = takenSave?.initial ?? asBuilt
            s.updateBounds()
            for t in ships.dropFirst() { t.followParent(0); t.prevPos = t.pos; t.prevRot = t.rot }
            return (ships, st)
        }
        if sync {
            installCapital(work())
            return
        }
        DispatchQueue.global(qos: .utility).async { [me = weakLink] in    // (item 8: by link: WeakLink.swift)
            let built = work()
            guard let self = me.wrappedValue else { return }
            self.capitalLock.lock()
            self.capitalReady.append(built)
            self.capitalLock.unlock()
        }
    }

    private func installCapital(_ built: ([Ship], CapitalState)) {
        let (ships, st) = built
        for s in ships {
            add(s)
            s.mesh.rebuildAll(s, device: world.device, queue: meshQueue)
        }
        if let s = ships.first {
            capState[s.id] = st
            if s.captured, let i = takenToRestore.firstIndex(where: { $0.kind == s.role && $0.name == s.name }) { takenToRestore.remove(at: i) }
        }
        if let r = st.region { capitalPending.remove(r); st.parties = max(st.parties, navyParties[r] ?? 0) }
    }

    var capitals: [Ship] { list.filter { $0.kinematic && $0.parent == nil } }

    // Mobility for the HUD bar: the drive engines left above the 40 % line, and for land vehicles the wheels left
    // above the half-lost line, whichever is worse.
    func capitalIntegrity(_ s: Ship) -> Float {
        guard let st = capState[s.id], st.engines0 > 0 else { return 0 }
        let e = Float(s.engines) / Float(st.engines0)
        var m = max(0, min(1, (e - 0.4) / 0.6))
        if !st.wheels.isEmpty {
            let left = Float(st.wheels.count - st.wheelsLost) / Float(st.wheels.count)
            m = min(m, max(0, min(1, (left - 0.5) / 0.5)))
        }
        return m
    }

    // The HUD label: the vehicle's components (helm, engines, wheels) and crew instead of one health pool.
    func capitalStatus(_ s: Ship) -> String {
        guard let st = capState[s.id] else { return s.name }
        var parts: [String] = []
        parts.append(s.helm == nil ? "helm destroyed" : (st.driverAlive ? "helm manned" : "no driver"))
        if st.engines0 > 0 {
            let pct: Float = Float(s.engines) / Float(st.engines0) * 100
            parts.append("engines \(Int(pct.rounded()))%")
        }
        if !st.wheels.isEmpty { parts.append("wheels \(st.wheels.count - st.wheelsLost)/\(st.wheels.count)") }
        let ts = turrets(of: s)
        let manned = ts.indices.filter { st.turretManned($0) }.count
        if !ts.isEmpty { parts.append("guns \(manned)/\(ts.count)") }
        return s.name + ": " + parts.joined(separator: ", ")
    }

    // Wheel components: recount each wheel's blocks twice a second; a wheel at under half is lost (it stops
    // turning and drawing the cells that are gone).
    // T9: a captured land vehicle is repaired a wheel at a time: an ingot of steel (or iron) used on it rebuilds the
    // damaged wheel nearest the struck cell, and once fewer than half its wheels are lost it can drive again.
    // Returns a toast, nil when there is nothing to repair.
    func repairVehicle(_ s: Ship, near cell: IVec3) -> String? {
        guard s.captured, let st = capState[s.id], !st.wheels.isEmpty || st.engines0 > 0 else { return nil }
        let at = V3(Float(cell.x), Float(cell.y), Float(cell.z))
        var best = -1, bd = Float.greatestFiniteMagnitude
        for (k, w) in st.wheels.enumerated() where (w.n < w.n0 || w.burst || w.wear > 0) && !w.orig.isEmpty {
            let c = (V3(Float(w.lo.x), Float(w.lo.y), Float(w.lo.z)) + V3(Float(w.hi.x), Float(w.hi.y), Float(w.hi.z))) * 0.5
            let d = simd_length(c - at)
            if d < bd { bd = d; best = k }
        }
        var what = ""
        if best >= 0 {
            let w = st.wheels[best]
            let sx = w.hi.x - w.lo.x + 1, sz = w.hi.z - w.lo.z + 1
            for y in w.lo.y...w.hi.y { for z in w.lo.z...w.hi.z { for x in w.lo.x...w.hi.x {
                let i = (x - w.lo.x) + (z - w.lo.z) * sx + (y - w.lo.y) * sx * sz
                guard i < w.orig.count, w.orig[i] != AIR, s.grid.get(x, y, z) == AIR else { continue }
                setBlock(s, IVec3(x, y, z), w.orig[i])
            } } }
            if w.part < s.wheelParts.count, s.wheelParts[w.part].blocks.count == w.orig.count { s.wheelParts[w.part].blocks = w.orig }
            st.wheels[best].n = w.n0
            st.wheels[best].wear = 0; st.wheels[best].burst = false
            s.wheelGen += 1
            st.wheelTimer = 0
            what = "Wheel rebuilt (\(st.wheels.count - st.wheelsLost)/\(st.wheels.count) wheels)"
        } else {
            // The drive engines: knocked out by a shock (the main gun) with their blocks still in place, an ingot gets
            // them running again; else up to eight missing engine blocks an ingot, nearest the struck cell first.
            let kinds = ShipParts.kinds
            let present = st.engineCells.filter { kinds[Int(s.grid.get($0.0.x, $0.0.y, $0.0.z))] == .engine }.count
            if s.engines < present {
                s.engines = present
                st.enginesShaken = false
                what = "Engines restarted (\(s.engines)/\(st.engines0) engine blocks)"
            }
            let missing = st.engineCells.filter { s.grid.get($0.0.x, $0.0.y, $0.0.z) == AIR }
                .sorted { simd_length(V3(Float($0.0.x), Float($0.0.y), Float($0.0.z)) - at) < simd_length(V3(Float($1.0.x), Float($1.0.y), Float($1.0.z)) - at) }
            if what.isEmpty && !missing.isEmpty {
                for (c, b) in missing.prefix(8) { setBlock(s, c, b) }
                what = "Engine rebuilt (\(s.engines)/\(st.engines0) engine blocks)"
            }
            if what.isEmpty {
                guard let m = patchHull(s, st, near: at) else { return nil }
                what = m
            }
        }
        let drives = st.wheelsLost * 2 < st.wheels.count && (st.engines0 == 0 || s.engines * 10 >= st.engines0 * 4)
        if drives && !st.disabledWhy.isEmpty {
            st.disabledWhy = ""; st.grind = -1; st.sag = V2(0, 0)
            return what + ": the \(s.name) can drive again"
        }
        return what
    }

    // P476 (Oct 27 19:1x, "I wanted to figure out how to repair it. I should be able to go to the helm and figure out
    // how"): a warship he took is mended with ingots, at her helm or anywhere on her: once her engines run, each ingot
    // puts back up to 64 of her blocks as built, the main gun's barrel first while it is torn away (and the gun works
    // again once it is whole), then those nearest where the ingot was used, and smooths the chipped plating there.
    // The plans are drawn up from her builder off the frame the first time she is his (requestBlueprint).
    func requestBlueprint(_ s: Ship, _ st: CapitalState) {
        guard !st.blueprintAsked, ["capfrigate", "frigate", "crawler"].contains(s.role ?? "") else { return }
        st.blueprintAsked = true
        let role = s.role ?? "", sx = s.grid.sx, sy = s.grid.sy, sz = s.grid.sz, id = s.id
        DispatchQueue.global(qos: .utility).async {
            let hb = role == "capfrigate" ? Capital.capitalFrigate() : (role == "frigate" ? Capital.frigate() : Capital.crawler())
            guard hb.sx == sx && hb.sy == sy && hb.sz == sz else { return }
            let solid = hb.blocks.reduce(0) { $0 + ($1 == AIR ? 0 : 1) }
            ShipManager.plansLock.lock()
            ShipManager.plans[id] = (hb.blocks, solid)
            ShipManager.plansLock.unlock()
        }
    }
    static var plans: [Int: ([BlockID], Int)] = [:]               // drawn up, waiting to be taken on the frame
    static let plansLock = NSLock()
    private func takePlan(_ s: Ship, _ st: CapitalState) {
        guard st.blueprint == nil, st.blueprintAsked else { return }
        ShipManager.plansLock.lock()
        if let (b, n) = ShipManager.plans.removeValue(forKey: s.id) { st.blueprint = b; st.blueprintSolid = n }
        ShipManager.plansLock.unlock()
    }

    // P504: rounds left in a war vessel's magazine for the helm's panel (nil: a vessel without one).
    func magazineLeft(_ ship: Ship) -> Int? {
        let r = ship.root
        guard r.kinematic && r.role != nil, let st = capState[r.id] else { return nil }
        if st.rounds >= 0 { return st.rounds }
        return Capital.magazine(r, barrels: ([r] + turrets(of: r)).reduce(0) { $0 + $1.cannons.count })
    }

    func hullShare(_ s: Ship, _ st: CapitalState) -> Float? {
        takePlan(s, st)
        guard st.blueprint != nil, st.blueprintSolid > 0 else { return nil }
        return min(1, Float(s.blockCount) / Float(st.blueprintSolid))
    }

    func patchHull(_ s: Ship, _ st: CapitalState, near at: V3) -> String? {
        requestBlueprint(s, st)
        takePlan(s, st)
        guard let bp = st.blueprint, bp.count == s.grid.blocks.count else { return nil }
        let gr = s.grid
        let gunOut = st.mainGunLength > 0 && st.mainGunCD >= 1e30
        let mz = st.mainGunMuzzle, md = simd_normalize(st.mainGunDir)
        var want: [(Float, IVec3, BlockID)] = []
        for y in 0..<gr.sy { for z in 0..<gr.sz { for x in 0..<gr.sx {
            let i = gr.index(x, y, z)
            let b = bp[i]
            guard b != AIR, gr.blocks[i] == AIR else { continue }
            let p = V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)
            var d = simd_length(p - at)
            if gunOut {
                let rel = p - mz, along = -simd_dot(rel, md)
                if along >= -2 && along <= st.mainGunLength && simd_length(rel + md * along) < 4.5 { d -= 100_000 }
            }
            want.append((d, IVec3(x, y, z), b))
        } } }
        var chips: [IVec3] = []
        for (c, _) in s.damage where simd_length(V3(Float(c.x), Float(c.y), Float(c.z)) - at) < 6 { chips.append(c) }
        guard !want.isEmpty || !chips.isEmpty else { return nil }
        want.sort { $0.0 < $1.0 }
        var cells: [IVec3] = []
        let kinds = ShipParts.kinds
        for (_, c, b) in want.prefix(64) {
            gr.set(c.x, c.y, c.z, b)
            s.blockCount += 1
            if kinds[Int(b)] == .engine { s.engines += 1 }
            if kinds[Int(b)] == .helm && s.helm == nil { s.helm = c }
            cells.append(c)
        }
        for c in chips.prefix(64) { s.damage.removeValue(forKey: c) }
        s.mesh.rebuildAround(s, cells + chips.prefix(64), device: world.device, queue: meshQueue)
        st.probes = nil                                            // (hullContact's outline drawn again)
        var what = cells.isEmpty ? "Plating smoothed" : "Hull patched: \(cells.count) blocks"
        if gunOut && !Capital.barrelTorn(s, st) {
            st.mainGunCD = 0
            what += ", the \(MainGun.name)'s barrel is whole again"
        }
        if let k = hullShare(s, st) { what += String(format: " (hull %d%%)", Int((k * 100).rounded(.down))) }
        return what
    }

    // P511 (Nov 2 12:17, "the crawler wheels, I think they can't be destroyed or something, maybe we can fix that so
    // that they get damaged"): a great wheel is some 600 tyre blocks and was lost only at half of them, past what any
    // gun of his gets through. Blasts now wear a big wheel down as one part: each takes its strength, less with the
    // distance, off every wheel it reaches; at wheelHP the tyre bursts: the blocks round the hit go, the wheel counts
    // as lost (the hull sags onto it, the drive slows, half the wheels gone and it stops), and an ingot rebuilds it.
    static let wheelHP: Float = 18, bigWheel = 40
    func wheelBlast(_ s: Ship, _ lc: V3, power: Float) {
        guard s.parent == nil, let st = capState[s.id], !st.wheels.isEmpty else { return }
        let reach = power * 1.5 + 1
        for k in st.wheels.indices where !st.wheels[k].lost && st.wheels[k].n0 > ShipManager.bigWheel {
            let w = st.wheels[k]
            let lo = V3(Float(w.lo.x), Float(w.lo.y), Float(w.lo.z))
            let hi = V3(Float(w.hi.x + 1), Float(w.hi.y + 1), Float(w.hi.z + 1))
            let near = simd_clamp(lc, lo, hi)
            let d = simd_length(lc - near)
            guard d < reach else { continue }
            let hit: Float = power * (1 - d / reach)
            st.wheels[k].wear += hit
            guard st.wheels[k].wear >= ShipManager.wheelHP else { continue }
            st.wheels[k].burst = true
            var gone = Set<IVec3>()
            let kinds = ShipParts.kinds
            for y in w.lo.y...w.hi.y { for z in w.lo.z...w.hi.z { for x in w.lo.x...w.hi.x {
                let c = V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)
                if simd_length(c - near) < 3.6 && kinds[Int(s.grid.get(x, y, z))] == .wheel { gone.insert(IVec3(x, y, z)) }
            } } }
            if !gone.isEmpty { removeCells(s, gone, chipped: [], center: s.toWorld(near), power: power, game: nil, detach: false) }   // (no hundred tyres on the ground)
            st.wheelTimer = 0
            ShipManager.wheelsBurst += 1
        }
    }
    static var wheelsBurst = 0                                 // (checks)

    func trackWheels(_ s: Ship, _ st: CapitalState, _ dt: Float) {
        st.wheelTimer -= dt
        guard st.wheelTimer <= 0 else { return }
        st.wheelTimer = 0.5
        let kinds = ShipParts.kinds
        let g = s.grid
        var changed = false
        for k in st.wheels.indices {
            let w = st.wheels[k]
            var n = 0
            for y in w.lo.y...w.hi.y { for z in w.lo.z...w.hi.z { for x in w.lo.x...w.hi.x where kinds[Int(g.get(x, y, z))] == .wheel { n += 1 } } }
            guard n != w.n else { continue }
            st.wheels[k].n = n
            changed = true
            if w.part < s.wheelParts.count {
                var part = s.wheelParts[w.part]
                for y in 0..<part.size.y { for z in 0..<part.size.z { for x in 0..<part.size.x {
                    let c = part.lo + IVec3(x, y, z)
                    let i = x + z * part.size.x + y * part.size.x * part.size.z
                    if part.blocks[i] != AIR && kinds[Int(g.get(c.x, c.y, c.z))] != .wheel { part.blocks[i] = AIR }
                } } }
                s.wheelParts[w.part] = part
            }
        }
        if changed { s.wheelGen += 1 }
    }

    // Horizontal distance from a point to a ship's bounds.
    func boundsDistance(_ s: Ship, _ p: V3) -> Float {
        let dx = max(s.worldMin.x - p.x, 0, p.x - s.worldMax.x), dz = max(s.worldMin.z - p.z, 0, p.z - s.worldMax.z)
        let dy = max(s.worldMin.y - p.y, 0, p.y - s.worldMax.y)
        return simd_length(V3(dx, dy, dz))
    }

    // The nearest foe of `faction` within `range` of p: an enemy vessel (aim point on its hull) or an enemy soldier.
    func nearestFoe(of faction: Faction, near p: V3, range: Float, game g: Game) -> CapTarget? {
        var best: CapTarget?
        var bd = range
        let truce = Reckoning.truce(g, faction, p)            // P450: the armies hunting him leave each other be
        for o in list where o.parent == nil && !o.wrecked {
            let f = o.factionValue
            if f == .none || f == faction || truce && Reckoning.hunting(f) { continue }
            let d = boundsDistance(o, p)
            if d < bd {
                bd = d
                // Aim at the closest point of its bounds, pulled toward its centre (a point on the hull, not empty air).
                let c = simd_clamp(p, o.worldMin, o.worldMax)
                let aim = c + (o.pos - c) * 0.35
                best = CapTarget(point: aim, vel: o.vel, ship: o, mob: nil, player: false)
            }
        }
        do {
            for m in g.mobs.mobs where m.health > 0 && m.factionValue != .none && m.factionValue != faction && !(truce && Reckoning.hunting(m.factionValue)) {
                let d = simd_length(m.pos - p)
                if d < bd { bd = d; best = CapTarget(point: m.pos + V3(0, m.height * 0.5, 0), vel: m.vel, ship: nil, mob: m, player: false) }
            }
        }
        return best
    }

    // MARK: Per-frame AI

    func capitalTick(_ dt: Float, game g: Game) {
        capitalLock.lock()
        let ready = capitalReady
        capitalReady.removeAll()
        capitalLock.unlock()
        for b in ready { installCapital(b) }
        guard dt > 0 else { return }
        restoreTaken()
        salvagedGunsTick(dt, g)
        for s in capitals {
            guard let st = capState[s.id] else { continue }
            let pd = boundsDistance(s, g.player.pos)
            // Far behind the player: gone, and its region may bring it back (wrecks stay gone). P464 (Oct 25 20:29,
            // "there was a frigate here and it's not here anymore"): one he has taken stays where he left it.
            if pd > 1400 && aboard?.root !== s && !s.captured {
                if let r = st.region, !s.wrecked { spawnedRegions.remove(r) }
                remove(s)
                capState.removeValue(forKey: s.id)
                continue
            }
            if !st.announced && pd < 420 && s.role != "dropship" && !s.captured {
                st.announced = true
                g.onToast?(s.role == "crawler" ? "The ground shakes: an Ironback Crawler is near" : "A \(s.name) looms on the horizon")
            }
            if s.asleep { continue }                 // P376: past the active distance a capital ship waits where it is
            if s.captured { requestBlueprint(s, st) }                       // P476: her plans, for repairs
            if s.captured && !s.wrecked && (s.role == "dropship" || s.isFlyingCapital) { commandeeredTick(s, st, dt, g); continue }
            if s.captured && s.wrecked && s.isFlyingCapital { founder(s, st, dt, g); downedGunsTick(s, st, dt, g); continue }
            if s.captured && s.role == "crawler" { capturedCrawlerTick(s, st, dt, g); continue }
            if s.role == "dropship" { dropshipTick(s, st, dt, g); continue }
            // Drive exhaust: a blue-white glow streaming aft from the nozzles while the engines hold (blind critic: the
            // frigate showed no sign of what keeps it up).
            if !st.exhausts.isEmpty && pd < 260 && st.engines0 > 0 && !s.wrecked {
                let k = Float(s.engines) / Float(st.engines0)
                if k > 0.4 {
                    let aft = s.dirToWorld(V3(0, 0, 1))
                    let layer = Int(Tex.id("smoke"))
                    for n in st.exhausts where Rand.float(in: 0..<1) < dt * 40 * k {
                        let jitter = V3(Rand.float(in: -1.2...1.2), Rand.float(in: -1.2...1.2), 0.8)
                        let speed: Float = Rand.float(in: 8...14)
                        g.particles.add(Particle(pos: s.toWorld(n + jitter), vel: s.vel + aft * speed, life: Rand.float(in: 0.4...0.8), maxLife: 0.8,
                                                 layer: layer, uv0: V2(0, 0), uvSize: 1, size: Rand.float(in: 0.5...0.9), gravity: 0,
                                                 color: V3(0.55, 0.8, 1.0), collide: false, glow: true))
                    }
                }
            }
            driveGlow(s, st, pd, dt, g)
            spawnCrew(s, st, pd, g)
            if !st.wheels.isEmpty { trackWheels(s, st, dt) }
            // Disabled for good: a crawler with half its wheels or its drive engines gone, a frigate with its drive
            // engines gone (it goes down and settles where it falls). The crew fights on as soldiers.
            if !s.wrecked {
                let enginesOut = st.engines0 > 0 && s.engines * 10 < st.engines0 * 4
                let wheelsOut = !st.wheels.isEmpty && st.wheelsLost * 2 >= st.wheels.count
                if enginesOut || wheelsOut {
                    s.wrecked = true
                    st.disabledWhy = enginesOut ? "engines destroyed" : "wheels destroyed"
                    let frigate = s.role != "crawler"
                    if pd < 400 {
                        g.onToast?(frigate ? "The \(s.name)'s drive engines are out: it is going down!" : "The \(s.name) is disabled (\(st.disabledWhy))")
                        if g.survival { g.achieve("wreck_vessel") }
                    }
                    g.sfx(.explode, 1, at: s.pos)
                    for t in turrets(of: s) { t.aimAt = nil }
                    // The crew stay aboard and fight on as soldiers (no longer tied to their posts, never off a ledge).
                    for m in st.crewMobs.values where m.deck === s && m.health > 0 {
                        m.crewFree = true
                        m.home = m.pos
                        m.aggro = true
                    }
                }
            }
            if s.role == "crawler" { crawlerRamp(s, st, dt, g) }
            TickProf.mark("cap: crew, wheels, ramp")             // (store review: the capital tick split for questcheck --framesoak)
            if s.wrecked { st.gunCharge = -1; founder(s, st, dt, g); continue }      // a charge dies with the ship
            st.retarget -= dt
            if st.retarget <= 0 || (st.target.map { !targetValid($0, g, spareBases: s.factionValue == .steelhold) } ?? false) {
                st.retarget = 1
                st.target = pickTarget(s, st, g)
                if st.target?.player != true { st.bombardShots = 0 }      // a new barrage starts with a warning shot again
            } else if var t = st.target {
                refresh(&t, g)
                st.target = t
            }
            TickProf.mark("cap: target")
            if s.isFlyingCapital { flyFrigate(s, st, dt, g) } else { driveCrawler(s, st, dt, g) }
            TickProf.mark("cap: drive")
            capitalGuns(s, st, dt, g)
            TickProf.mark("cap: guns")
            shipMissiles(s, st, dt, g)
            if s.role == "capfrigate" { mainGunTick(s, st, dt, g); boardingWinch(s, st, dt, g); boardingParty(s, st, dt, g) }
            deployTroops(s, st, dt, g)
            TickProf.mark("cap: missiles, boarding, troops")
        }
    }

    // `spareBases`: a Capital ship's target inside a citadel is dropped (its own base); others keep firing.
    private func targetValid(_ t: CapTarget, _ g: Game, spareBases: Bool = true) -> Bool {
        if t.player {
            var ok = false
            g.coop.withSeat(t.seat < max(1, g.coop.seatCount) ? t.seat : 0, g) { ok = g.alive && g.survival && g.difficulty > 0 && !Reckoning.won && !(spareBases && g.bases.inAnyBase(g.player.pos)) }
            return ok
        }
        if let s = t.ship { return !s.wrecked && list.contains { $0 === s } }
        if let m = t.mob { return m.health > 0 && !(spareBases && g.bases.inAnyBase(m.pos)) }
        return t.fixed
    }

    private func refresh(_ t: inout CapTarget, _ g: Game) {
        if t.player { let p = g.coop.seatPlayer(t.seat, g); t.point = p.pos + V3(0, 1, 0); t.vel = p.vel }
        else if let o = t.ship { t.point = o.pos; t.vel = o.vel }
        else if let m = t.mob { t.point = m.pos + V3(0, m.height * 0.5, 0); t.vel = m.vel }
    }

    // The player (in survival, unless aboard or on Peaceful) or the nearest enemy-faction target, within sight; the current one is
    // kept unless something is much closer.
    private func pickTarget(_ s: Ship, _ st: CapitalState, _ g: Game) -> CapTarget? {
        let c = s.pos
        var best: CapTarget?
        var bd = st.sight
        // Capital ships spare their own citadels; other factions' (the Meridian's Tidebreaker) don't.
        let spare: (V3) -> Bool = { p in s.factionValue == .steelhold && g.bases.inAnyBase(p) }
        // A survival player only, like vessel guns (gunsEngage) and soldiers (canTarget); every player in split screen.
        for i in 0..<max(1, g.coop.seatCount) {
            g.coop.withSeat(i, g) {
                let pp = g.player.pos
                let onIt = self.aboard?.root === s || self.standing(on: pp)?.root === s
                // A Capital ship never fires on a player inside a citadel: its shells would land on its own base (Quest round 3).
                guard g.alive && g.survival && g.difficulty > 0 && !Reckoning.won && !onIt && !spare(pp) else { return }   // (P98: at peace)
                let d = self.boundsDistance(s, pp)
                // In sight and in a sane range only: a frigate killed a player inside a house the moment they
                // switched to survival, nobody near (Quest round 4). Sighted from the hull's centre or its top.
                // P483 (Oct 28 17:34, "the frigate's guns aren't hurting me at all on survival normal"): once her crew has
                // spotted him (st.engaged) she keeps him in her whole sight; at 180 her orbit carried him out of it and
                // her guns fell silent for most of a fight.
                guard d < min(bd, st.engaged ? st.sight : 180) else { return }
                let eye = g.player.eye
                // (Or from any of her gun mounts: overhead, her centre and top looked down through her own decks' shadow of
                // trees and roofs while a boom gun had him in plain view; P483 frigatefire: 30 s of 40 without a target.)
                guard self.world.clearShot(s.pos, eye) || self.world.clearShot(V3(s.pos.x, s.worldMax.y + 1, s.pos.z), eye)
                      || self.turrets(of: s).contains(where: { self.world.clearShot($0.toWorld($0.pivot) + V3(0, 1, 0), eye) }) else { return }
                if d < bd { bd = d; best = CapTarget(point: pp + V3(0, 1, 0), vel: g.player.vel, ship: nil, mob: nil, player: true, seat: i) }
            }
        }
        if let foe = nearestFoe(of: s.factionValue, near: c, range: st.sight + simd_length(s.worldMax - s.worldMin) * 0.5, game: g) {
            let d = boundsDistance(s, foe.point)
            if !spare(foe.point) && (d < bd * 0.8 || best == nil) { best = foe; bd = d }
        }
        if let cur = st.target, targetValid(cur, g, spareBases: s.factionValue == .steelhold), let b = best {
            let dc = boundsDistance(s, cur.point)
            if dc < bd * 1.3 && dc < st.sight { return cur }
            _ = b
        }
        if best == nil, let shore = shoreTarget(s, st, g) { best = shore }      // T8: nothing in sight: shell a shore base
        if let b = best, b.player, !st.engaged {
            st.engaged = true
            g.onToast?("The \(s.name)'s crew has spotted you!")
            g.sfx(.gun(10), 1.5, at: g.player.pos)
        }
        return best
    }

    // T8: a non-Capital warship over the sea with nothing in sight bombards the nearest enemy shore position within its
    // sight: a Greywall base's keep or a Capital citadel's tower (Meridian and Stormwarden ships alike).
    private func shoreTarget(_ s: Ship, _ st: CapitalState, _ g: Game) -> CapTarget? {
        guard s.isFlyingCapital, !s.captured, s.factionValue != .steelhold else { return nil }
        let ix = Int(floor(s.pos.x)), iz = Int(floor(s.pos.z))
        let top = world.topY(ix, iz)
        guard top > 0, Blocks.isLiquid(world.builtBlock(ix, top, iz)) || Blocks.isLiquid(world.builtBlock(ix, top - 1, iz)) else { return nil }
        var best: V3?, bd = st.sight + 60
        if s.factionValue != .greywall {
            for site in g.bases.greywall.sites.values {
                let p = V3(Float(site.cx) + 0.5, Float(site.S + site.tier.wallH + 6), Float(site.cz) + 0.5)
                let d = simd_length(V2(p.x - s.pos.x, p.z - s.pos.z))
                if d < bd { bd = d; best = p }
            }
        }
        for r in g.bases.records.values where r.cleared != true {
            let p = r.centre + V3(0, 20, 0)
            let d = simd_length(V2(p.x - s.pos.x, p.z - s.pos.z))
            if d < bd { bd = d; best = p }
        }
        guard let p = best else { return nil }
        if !st.shelling && simd_length(p - g.player.pos) < 200 {
            st.shelling = true
            g.onToast?("The \(s.name) is shelling the shore!")
        }
        return CapTarget(point: p, vel: V3(0, 0, 0), ship: nil, mob: nil, player: false, fixed: true)
    }

    // Yaw rate toward a wanted heading, limited (heavy hulls turn slowly).
    private func turnToward(_ s: Ship, _ want: V2, maxRate: Float) -> Float {
        let wantYaw = atan2f(-want.x, -want.y)
        var d = wantYaw - s.yaw
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return max(-maxRate, min(maxRate, d * 0.5))
    }

    // Stormwarden Frigate: patrol a wide circle round home; with a target, close to 160, then circle it broadside
    // (every gun bears), swinging its bow on for the spinal gun when that is charged.
    private func flyFrigate(_ s: Ship, _ st: CapitalState, _ dt: Float, _ g: Game) {
        // Nobody at the helm (helmsman dead or the helm shot away): she holds her height and drifts to a stop.
        if !st.driverAlive || s.helm == nil {
            let holdY: Float = s.hoverY ?? s.pos.y
            let want = V3(0, (holdY - s.pos.y) * 0.3, 0)
            s.vel += (want - s.vel) * min(1, dt * 0.25)
            s.angVel = V3(0, s.angVel.y * max(0, 1 - dt), 0)
            levelUp(s, dt)
            return
        }
        if g.stormGrounds { st.target = nil }                      // O7: grounded by the storm: break off and hold over home
        let home = s.home ?? s.pos
        let fw = s.dirToWorld(V3(0, 0, -1))
        let fh = simd_normalize(V2(fw.x, fw.z) + V2(1e-5, 0))
        var want = fh
        // The Meridian frigate is a fast ship: roughly twice the Stormwarden's speeds and a quicker helm.
        let fast: Float = s.role == "capfrigate" ? 2.2 : 1
        var speed: Float = 7 * fast
        if let t = st.target {
            let to = V2(t.point.x - s.pos.x, t.point.z - s.pos.z)
            let d = max(1, simd_length(to))
            let dir = to / d
            if st.mainGunCD <= 2 && d < 450 {
                want = dir; speed = 5 * fast
            } else if d > 220 {
                want = dir; speed = 10 * fast
            } else {
                let tangent = V2(-dir.y, dir.x) * st.orbitDir
                want = simd_normalize(tangent + dir * ((d - 160) / 80))
                speed = 6 * fast
            }
        } else if let ping = st.pingAt, st.pingT < 60 {
            // C8: the sonar heard a submarine: run to the last ping and circle over it, ready to drop charges.
            st.pingT += dt
            let to = V2(ping.x - s.pos.x, ping.z - s.pos.z)
            let d = max(1, simd_length(to))
            let dir = to / d
            if d > 40 { want = dir; speed = 9 * fast }
            else { want = simd_normalize(V2(-dir.y, dir.x) * st.orbitDir + dir * 0.3); speed = 4 * fast }
        } else if let goal = st.goal {
            // Nov 4 (ledger 16): sent for someone (the Reckoning's warship, made past the fog: from there her circle round
            // home never came near him): fly in, then circle the spot with her near end 120 off until she has him in her
            // sight. (Circling with her middle 100 off, a 480-block hull hung over him and its own decks hid him from every
            // gun: --huntwarship, build 138.)
            let to = V2(goal.x - s.pos.x, goal.z - s.pos.z)
            let d = max(1, simd_length(to))
            let dir = to / d
            let near = boundsDistance(s, goal)
            if near > 180 { want = dir; speed = 10 * fast }
            else { want = simd_normalize(V2(-dir.y, dir.x) * st.orbitDir + dir * ((near - 120) / 60)); speed = 6 * fast }
        } else if let isle = st.isles?.first {
            // T11: a frigate with a sky isle near its home keeps its own route: a wide circle round the isle, at
            // cruise clearance over its turf (the altitude below counts the isle as ground).
            let toIsle = isle.c - V2(s.pos.x, s.pos.z)
            let dist = max(1, simd_length(toIsle))
            let r = isle.r + (s.role == "capfrigate" ? 110 : 90)
            let tangent = V2(-toIsle.y, toIsle.x) / dist * st.orbitDir
            want = simd_normalize(tangent + toIsle * ((dist - r) / (r * dist)) + V2(1e-4, 0))
        } else {
            let toHome = V2(home.x - s.pos.x, home.z - s.pos.z)
            let dist = max(1, simd_length(toHome))
            let r: Float = s.role == "capfrigate" ? 320 : 420
            let tangent = V2(-toHome.y, toHome.x) / dist * st.orbitDir
            let steer: V2 = tangent + toHome * ((dist - r) / (r * dist))
            want = simd_normalize(steer + V2(1e-4, 0))                  // at home exactly: no NaN
        }
        if let k = st.testTurn {
            want = V2(fh.x * cosf(k) - fh.y * sinf(k), fh.x * sinf(k) + fh.y * cosf(k))
            speed = st.testSpeed ?? 10
        }
        if st.heaveTo { speed = min(speed, 0.6) }       // a player at the boarding winch's foot (FrigateBoarding)
        // Altitude: the keel 30 above the highest ground under and ahead of the hull, below the world's ceiling.
        st.groundTimer -= dt
        if st.groundTimer <= 0 {
            st.groundTimer = 0.5
            if st.isles == nil { st.isles = SkyIsle.near(world.gen, x: home.x, z: home.z, range: 700) }
            var top = 0
            var isleTop: Float = 0
            let side = V2(-fh.y, fh.x)
            for k in -4...6 { for j in -1...1 {
                let p = V2(s.pos.x, s.pos.z) + fh * Float(k * 50) + side * Float(j * 40)
                top = max(top, world.gen.column(Int(floor(p.x)), Int(floor(p.y))).height)
                // A sky isle under or ahead of the hull counts as ground (its turf, plus the hull's half width).
                for i in st.isles ?? [] where simd_length(p - i.c) < i.r + 40 { isleTop = max(isleTop, i.top) }
            } }
            st.groundMax = max(Float(max(top, SEA)), isleTop)
        }
        let keel = s.com.y - s.localMin.y
        let maxY = Float(CH - 4) - (s.localMax.y - s.com.y)
        let wantY = min(maxY, st.groundMax + Capital.cruiseClearance(s.role ?? "") + keel)
        s.hoverY = wantY
        let yawRate = st.heaveTo ? 0 : turnToward(s, want, maxRate: s.role == "capfrigate" ? 0.13 : 0.07)   // (holds its heading: the line's foot stays put)
        let vy = max(-4, min(4, (wantY - s.pos.y) * 0.4))
        let target = V3(fw.x, 0, fw.z) * speed + V3(0, vy, 0)
        s.vel += (target - s.vel) * min(1, dt * 0.6)
        s.angVel = V3(0, s.angVel.y + (yawRate - s.angVel.y) * min(1, dt * 0.8), 0)
        levelUp(s, dt)
    }

    // The crew aboard a capital craft: soldiers of its faction at their posts, appearing as the player comes near
    // (P334: dropships too, so a pilot flies it and a gunner works its gun).
    private func spawnCrew(_ s: Ship, _ st: CapitalState, _ pd: Float, _ g: Game) {
        if st.crewDone.count < st.crew.count && pd < 96 {
            // The crew aboard: soldiers of the ship's faction at their posts (they ride the hull and fight as
            // soldiers). Only over loaded ground (mobs there don't update, so they'd be left hanging as the hull
            // moved on).
            let troopRanks: [MobKind] = [.soldierTrooper, .soldierTrooper, .soldierRecruit, .soldierIronclad]
            var made = 0                                  // (P476: fifty aboard a frigate come six a frame)
            for (i, post) in st.crew.enumerated() where !st.crewDone.contains(i) && made < 6 {
                let at = s.toWorld(post + V3(0, 0.05, 0))
                guard world.isLoaded(Int(floor(at.x)), Int(floor(at.z))), simd_length(at - g.player.pos) < 120 else { continue }
                st.crewDone.insert(i)
                let role = i < st.crewRoles.count ? st.crewRoles[i] : .troop
                var kind: MobKind = role == .driver ? .soldierTrooper : (role == .gunner ? .soldierMarksman : troopRanks[i % troopRanks.count])
                var m = Mob(kind, at: at)
                // (P510, ridecheck: an Ironclad's broad body at a post walked out for a trooper, by the frigate's skin,
                // stood in the hull plates; such a post gets a trooper)
                if kind == .soldierIronclad {
                    let f0 = world.frame
                    world.frame = s
                    let tight = m.collides(post + V3(0, 0.05, 0), world)
                    world.frame = f0
                    if tight { kind = .soldierTrooper; m = Mob(kind, at: at) }
                }
                m.faction = s.faction
                m.persistent = true
                m.deck = s
                m.crewPost = post
                if s.role == "capfrigate" && role == .troop && post.z >= 121 { m.customName = "Meridian Engineer" }    // P472: the engine room's watch
                if s.wrecked { m.crewFree = true }
                if m.kind == .soldierIronclad { m.variant = Guns.arc }
                if st.rocketeer && st.troopsLeft == 1 {
                    // P215 (Oct 13 18:57, "a rocket launcher that blows holes in houses, I liked that").
                    m.variant = Guns.launcher
                    m.soldierBrain.gun = Guns.launcher; m.soldierBrain.mag = Guns.all[Guns.launcher].mag
                    m.customName = FactionRaids.rocketeerName
                }        // no rockets bursting inside their own hull
                g.mobs.mobs.append(m)
                st.crewMobs[i] = m
                made += 1
            }
        }
    }

    // Holds a frigate upright (only yaw is steered; drift from rounding is taken out).
    // Capital fliers the player can take command of from the helm (Quest round 4: the frigate's helm was locked and a
    // dropship had none). Crawlers stay locked.
    func canCommandeer(_ s: Ship) -> Bool {
        // T9: a crawler whose driver is dead can be taken too, wrecked or not (its wheels are rebuilt with ingots).
        if s.kinematic && s.parent == nil && s.helm != nil && s.role == "crawler" { return capState[s.id].map { !$0.driverAlive } ?? false }
        // P334 (a): a crewed dropship is taken once its pilot is dead (it has come down by then).
        if s.role == "dropship" && !s.captured, let st = capState[s.id], !st.crew.isEmpty, st.driverAlive { return false }
        // P483 (Oct 28 17:37, his frigate crashed: "Things should still work, and I should definitely still be able to
        // use the guns"): a flier he took that has come down can be manned again for its guns; it flies no more.
        if s.wrecked && s.captured && s.isFlyingCapital { return s.kinematic && s.parent == nil && s.helm != nil }
        return s.kinematic && s.parent == nil && !s.wrecked && s.helm != nil && (s.role == "dropship" || s.isFlyingCapital)
    }

    // T9: a captured crawler driven from its helm: throttle forward and back, steer turns it; it follows the ground as
    // under its own crew. With half its wheels lost it won't move until they are rebuilt (ShipManager.repairVehicle).
    private func capturedCrawlerTick(_ s: Ship, _ st: CapitalState, _ dt: Float, _ g: Game) {
        trackWheels(s, st, dt)
        if st.rampDown { crawlerRamp(s, st, dt, g) }                     // P511: up, for good
        let steered = pilot === s
        let lost = st.wheels.isEmpty ? 0 : Float(st.wheelsLost) / Float(st.wheels.count)
        let drives = lost < 0.5 && (st.engines0 == 0 || s.engines * 10 >= st.engines0 * 4)
        if steered && !drives && abs(s.throttle) > 0.1 && !st.winchTold {
            st.winchTold = true
            g.onToast?("The \(s.name) is too damaged to drive")
        }
        if drives { st.winchTold = false }
        let fw = s.dirToWorld(V3(0, 0, -1))
        let fh = simd_normalize(V2(fw.x, fw.z) + V2(1e-5, 0))
        // P499 (Oct 30 20:19, "its turning is inverted"): a positive angle turns the bow clockwise seen from above (right).
        let a = steered ? s.steer * 0.7 : 0
        let want = V2(fh.x * cosf(a) - fh.y * sinf(a), fh.x * sinf(a) + fh.y * cosf(a))
        // P507 (Nov 1 12:08:26, at a captured crawler's helm: "let's make this thing go like 100 kilometers per hour"):
        // full ahead is 28 blocks a second (100 km/h; was 9), astern a third of it.
        let top: Float = s.throttle > 0 ? 28 : 9
        let speed = steered && drives ? s.throttle * top * (1 - lost) : 0
        st.wantSpeed = abs(speed)
        crawlerMotion(s, st, dt, want: want, speed: speed, turnRate: steered && drives && abs(s.steer) > 0.05 ? 0.18 : 0, piloted: steered)
        // P455 (Oct 25 14:21, driving one: "this thing's, like, impossible to drive 'cause of the trees"): it crushes
        // what stands in its way as it does under its own crew; and its rail gun reloads (ShipManager.playerRail).
        if st.wantSpeed > 0.3 { crawlerCrush(s, st, dt, g) }
        st.mainGunCD -= dt
    }

    // P455 (Oct 25 14:24-14:25, at a captured Ironback Crawler's helm: "the main gun doesn't do anything, so it's just
    // all these little guns in the back that I have to use"): attack fires the spinal rail gun along the bow too when
    // it is loaded (raised or lowered a little toward the view), a slug as its crew fires it, reloading in 8 s.
    func playerRail(_ s: Ship, pitch: Float, game g: Game) -> Bool {
        // (P507, Nov 1 12:08:59: "instead of having that giant cannon thing on the top, replace it with another naval gun":
        // the crawler's rail cannon is gone, a twin naval turret in its place, Capital.crawler.)
        guard ShipManager.crawlerRail, s.role == "crawler", s.captured, let st = capState[s.id], st.mainGunCD <= 0 else { return false }
        let mw = s.toWorld(st.mainGunMuzzle)
        let md = s.dirToWorld(st.mainGunDir)
        let flat = simd_normalize(V3(md.x, 0, md.z) + V3(1e-5, 0, 0))
        let p = max(-0.3, min(0.3, pitch))
        let dir = simd_normalize(flat * cosf(p) + V3(0, sinf(p), 0))
        st.mainGunCD = 8
        railShot(s, from: mw, dir: dir, power: 7, game: g)
        g.addShake(0.35)
        return true
    }

    // P499 (Oct 30 20:20, at a captured Ironback Crawler's helm: "his main cannon should be more of a railgun, not whatever
    // the hell it currently is"): a Capital main gun's rail slug flew at 260 m/s on a shell's arc, drawn as a magma-red
    // streak, left the muzzle in a fireball and burst like a shell where it struck. Now a slug at 700 m/s that hardly
    // drops, a white-blue bolt leaving a glowing line in the air, a blue flash and sparks at the muzzle, and where it
    // strikes it drives on through what it hits (up to `railReach` blocks, ShipManager.railBore) before it bursts.
    static let railSpeed: Float = 700
    static let crawlerRail = false                       // (P507: the crawler's spinal rail gun, replaced by a naval twin)
    static let railReach = 14
    func railShot(_ s: Ship, from mw: V3, dir: V3, power: Float, game g: Game) {
        let sh = Shell(pos: mw + dir * 2, vel: dir * ShipManager.railSpeed, owner: s.id, power: power)
        sh.gravity = 0.4
        sh.kind = 1
        sh.life = 2
        shells.append(sh)
        g.sfx(.gun(9), 2, at: mw)
        g.sfx(.gun(12), 1.4, at: mw)
        g.addFlash(at: mw + dir, color: V3(3, 4.5, 7), radius: 22, life: 0.25)
        let layer = Int(Tex.id("puff"))
        for _ in 0..<14 {
            let v = dir * Rand.float(in: 4...14) + V3(Rand.float(in: -3...3), Rand.float(in: -3...3), Rand.float(in: -3...3))
            g.particles.add(Particle(pos: mw + dir * 1.5, vel: v, life: 0.35, maxLife: 0.35, layer: layer, uv0: V2(0, 0), uvSize: 1,
                                     size: Rand.float(in: 0.12...0.3), gravity: 4, color: V3(0.7, 0.9, 1.4), collide: false, glow: true))
        }
    }

    // A commandeered Capital flier: a dropship flown straight from the helm's throttle, steer and climb (kinematic, as
    // its AI flew it), a frigate like a ship (flyCommandeered); with nobody at the helm it holds station. Its AI, guns and
    // troop drops stay off for good.
    private func commandeeredTick(_ s: Ship, _ st: CapitalState, _ dt: Float, _ g: Game) {
        if s.role == "dropship" {
            // P334 (c): flown as an agile VTOL. The stick's forward/back drives along the nose and dips or lifts it,
            // left/right slides the craft sideways and banks it into the slide, the turn yaws it with the nose
            // following quickly and a bank into the turn, climb lifts; let go and it brakes to a hover in place.
            let steered = pilot === s
            let fw = s.dirToWorld(V3(0, 0, -1))
            let fh = simd_normalize(V2(fw.x, fw.z) + V2(1e-5, 0))
            let fwd = V3(fh.x, 0, fh.y), right = V3(-fh.y, 0, fh.x)
            let thr: Float = steered ? s.throttle : 0, side: Float = steered ? s.strafe : 0, turn: Float = steered ? s.steer : 0
            // P461 (Oct 25 16:40-16:41, "make the thing go faster when you sprint with it", "the white things on it, make
            // them light up blue when it's in overdrive"): sprint at the helm drives it 1.8 times as fast (burning fuel
            // twice as quickly) and its light panels glow blue.
            let over = steered && s.boost && thr > 0.3
            // P499 (Oct 30 20:38: "this drop ship should go two hundred, maybe 300 kilometres per hour when you do the whole
            // boost thing"): 55 m/s flat out (about 200 km/h, was 28), 83 in overdrive (300 km/h, was 50).
            var want = fwd * (thr * (thr > 0 ? (over ? 83 : 55) : 12)) + right * (side * 14)
            want.y = steered ? s.climb * 9 : 0
            if steered && !dropFuel(s, st, dt, g) { want = V3(0, -2.5, 0) }       // dry tanks: it settles to the ground
            // P508 (Nov 1 16:04:57-16:05:13 at a dropship shot half away: "No way this thing should be flying... If it has
            // one wing destroyed, like that thing is going down"): with a wing torn off (one side of the hull a third
            // lighter than the other) or under three fifths of its blocks left it has no lift: it goes down, slewing,
            // and can't climb off the ground again.
            if DropLift.lame(s, g) {
                want.y = min(want.y * 0.2, -7)
                want.x *= 0.5; want.z *= 0.5
            }
            // P461 (16:42, "after landing it's somehow floating into midair instead of falling"): left without a pilot
            // it comes down and rests on the ground instead of hanging where it was left.
            // Never into the ground. P461 (16:41, "This thing should be able to crush trees on landing"): the keel
            // comes down onto the ground itself (it kept 2 blocks over the top block, a tree's crown included), and
            // what stands in its way, leaves, trunks, plants, tents and planking, is crushed (crush).
            let gx = Int(floor(s.pos.x)), gz = Int(floor(s.pos.z))
            let top = Float(world.isLoaded(gx, gz) ? Capital.firmTop(world, gx, gz) : world.gen.column(gx, gz).height)
            // P499 (Oct 30 20:40, left landed: "keeps shaking up and down after I landed it"): unpiloted it eased down
            // at 3 m/s and was pushed back up at the ground each frame, a bob that never settled; it now eases onto the
            // ground (gently damped) and stays there.
            if !steered {
                want.y = max(-3, min(3, top + 1.05 - s.worldMin.y))
                if abs(top + 1.05 - s.worldMin.y) < 0.05 && abs(s.vel.y) < 0.3 { want.y = 0; s.vel.y = 0 }
            }
            if s.worldMin.y < top + 1.05 { want.y = max(want.y, (top + 1.05 - s.worldMin.y) * 2) }
            if s.worldMax.y > Float(CH - 4) { want.y = min(want.y, 0) }
            let accel = want - s.vel
            s.vel += accel * min(1, dt * 1.8)
            let yawRate: Float = -turn * 1.3
            let yawNow = s.angVel.y + (yawRate - s.angVel.y) * min(1, dt * 4)
            // The attitude shown: the nose dips as it speeds up (lifts as it brakes), the hull banks into a slide or
            // a turn; how far depends on Craft Bank (comfort, P334 d) while the player is aboard.
            let along = simd_dot(accel, fwd), across = simd_dot(accel, right)
            let speed = simd_length(V2(s.vel.x, s.vel.z))
            st.helmPitch += (max(-1, min(1, -along / 12)) * Capital.vtolPitch - st.helmPitch) * min(1, dt * 3)
            st.helmBank += (max(-1, min(1, -across / 10 + yawNow * min(1, speed / 12) * 0.8)) * Capital.vtolBank - st.helmBank) * min(1, dt * 3)
            steerAttitude(s, pitch: st.helmPitch, bank: st.helmBank, yawRate: yawNow)
            crush(s, st, dt, g)
            if over { overdriveGlow(s, st, g) }
        } else {
            flyCommandeered(s, st, dt, g)
            hullContact(s, st, dt, g)
            if s.wrecked { return }
        }
        st.target = nil
        driveGlow(s, st, boundsDistance(s, g.player.pos), dt, g)
        st.mainGunCD -= dt                                  // the Tidebreaker recharges for its new captain (playerMainGun)
        if s.role == "capfrigate" { mainGunTick(s, st, dt, g); boardingWinch(s, st, dt, g); if pilot === s { mainGunAimTick(s, st, dt, g) } }
        // (code reader Nov 10, batch 3.1: this ran after the crews laid their guns (gunCrewTick, earlier in the same
        // update), so on a frigate he had taken the crew's guns never turned onto anything and only fired at what
        // happened to lie in line. A gun a crew laid this update keeps its mark.)
        for t in turrets(of: s) where CapitalState.oldCrewAim || t.crewAimStamp != riderStamp { t.aimAt = nil }   // (batch 3.1)
    }

    // P483: a frigate he took that crashed keeps its guns. Manned at the helm the turrets and the Tidebreaker work as
    // they did in flight (the bow's aim is wherever it came to rest); the hull itself goes nowhere.
    private func downedGunsTick(_ s: Ship, _ st: CapitalState, _ dt: Float, _ g: Game) {
        st.target = nil
        st.mainGunCD -= dt
        if s.role == "capfrigate" { mainGunTick(s, st, dt, g); if pilot === s { mainGunAimTick(s, st, dt, g) } }
        for t in turrets(of: s) where CapitalState.oldCrewAim || t.crewAimStamp != riderStamp { t.aimAt = nil }   // (batch 3.1)
    }

    // P325 (c) (Oct 15 19:15, "a drivable ship where I angle it and momentum goes forward, not this up and down, left,
    // right nonsense"): a commandeered frigate flies like a ship. The climb control pitches the bow (the hull holds the
    // angle it is left at, up to 26 degrees either way), the steer turns it and banks it into the turn, and the drive
    // pushes along the bow: way builds and dies away slowly, sideways drift bleeds off as the hull carves round, and
    // nothing moves it straight up, down or sideways. The drive's strength follows the engines left (the engine room's
    // empty sockets smoke: driveGlow). With nobody at the helm it holds its attitude and coasts to a stop.
    private func flyCommandeered(_ s: Ship, _ st: CapitalState, _ dt: Float, _ g: Game) {
        let steered = pilot === s
        let meridian = s.role == "capfrigate"
        let pitchIn: Float = steered ? s.climb : 0, steerIn: Float = steered ? s.steer : 0
        let fw = s.dirToWorld(V3(0, 0, -1))
        var way = simd_dot(s.vel, fw)
        // P476 (Oct 27 19:11, "There's not really any landing the frigate... harder to do than it ought to be... Maybe
        // there has to be a VTOL mode"): with no way on (under 3 blocks/s along the bow) and the drive off she hovers on
        // her lift jets: she levels out, and the bow's pitch control lifts or lowers her straight up and down instead
        // (6 blocks/s, easing to 1.5 over the last dozen blocks so she settles onto the ground gently); the steer still
        // turns her on the spot. Drive on and she flies along her bow again.
        Capital.countThrust(s, st, dt)
        if Capital.reactorBreached(st) && !s.wrecked {
            s.wrecked = true
            let c = st.reactorCells[0]
            let at = s.toWorld(V3(Float(c.x) + 0.5, Float(c.y) + 0.5, Float(c.z) + 0.5))
            Explosion.explode(at: at, power: 8, game: g, breakBlocks: false)
            g.onToast?("The reactor is breached! The \(s.name) is going down")
            return
        }
        let lift = Capital.power(s, st)
        // Under half the thrust her weight wants she can't hold her height: she settles toward the ground, faster the
        // less she has (8 blocks/s with none), whoever is at the helm.
        let sink: Float = lift < 0.5 ? -(0.5 - lift) * 16 : 0
        let hover = steered && abs(way) < 3 && abs(s.throttle) < 0.15
        if hover { st.helmPitch += -st.helmPitch * min(1, dt * 1.5) }
        else { st.helmPitch = max(-Capital.maxPitch, min(Capital.maxPitch, st.helmPitch + pitchIn * 0.32 * dt)) }
        st.helmBank += (-steerIn * Capital.maxBank - st.helmBank) * min(1, dt * 1.5)
        var drift = s.vel - fw * way
        // P499 (Oct 30 20:27-20:28, at the Meridian's helm: "Let's make it so the frigate goes like... a thousand
        // kilometers per hour"): the sprint held with the throttle up runs her up to 280 m/s (1,000 km/h) in about ten
        // seconds, the whole of it only with 80 blocks of air under the keel (none under 30), so low down, where the
        // ground ahead may not be made yet, she keeps her cruising speed. Let go and she sheds it as quickly.
        let cruise = Capital.helmSpeed(s, st)
        var top = cruise
        if meridian && steered && s.boost && s.throttle > 0.3 {
            let gx = Int(floor(s.pos.x)), gz = Int(floor(s.pos.z))
            let ground = Float(world.isLoaded(gx, gz) ? world.topY(gx, gz) : world.gen.column(gx, gz).height)
            let air = s.worldMin.y - ground
            top += (Capital.dashSpeed * Capital.drive(s, st) - top) * max(0, min(1, (air - 30) / 50))
        }
        let want = steered ? max(-0.35, s.throttle) * top : 0
        let dash = abs(want) > cruise + 1 || abs(way) > cruise + 1
        // (P504: the Meridian gains 16 m/s a second and sheds 24: to 400 km/h in 7 s, stopped from it in under 5)
        let acc: Float = dash ? 26 : (meridian ? (abs(want) > abs(way) && want * way >= 0 ? 16 : 24) : (abs(want) > abs(way) && want * way >= 0 ? 4.5 : 6) * 1.4)
        way += max(-acc * dt, min(acc * dt, want - way))
        drift *= max(0, 1 - dt * 2)                         // (the hull carves round: sideways way bleeds off fast)
        s.vel = fw * way + drift
        if hover {
            var below: Float = 0
            for (i, j) in [(1, 1), (0, 0), (2, 0), (0, 2), (2, 2)] {
                let x = Int(floor(s.worldMin.x + (s.worldMax.x - s.worldMin.x) * Float(i) * 0.5))
                let z = Int(floor(s.worldMin.z + (s.worldMax.z - s.worldMin.z) * Float(j) * 0.5))
                below = max(below, Float(world.isLoaded(x, z) ? world.topY(x, z) : world.gen.column(x, z).height) + 1)
            }
            let clear = s.worldMin.y - below
            // (Short of thrust she climbs slower, and not at all under 0.5 of it.)
            // P499 (Oct 30 20:33, "it's still a little difficult to climb... should go the climb to like 400"): she
            // rises on her lift jets at 16 blocks/s (was 6): from the ground to the sky's ceiling in about 15 s.
            let rate: Float = pitchIn > 0 ? (meridian ? 16 : 6) * max(0, min(1, (lift - 0.5) / 0.3)) : max(1.5, min(6, clear * 0.5))
            s.vel.y += (min(pitchIn * rate, sink < 0 ? sink : .infinity) - s.vel.y) * min(1, dt * 2)
            Capital.hovering = true
        } else if steered { Capital.hovering = false }
        if !hover && sink < 0 { s.vel.y += (min(s.vel.y, sink) - s.vel.y) * min(1, dt * 1.5) }
        if s.worldMax.y > Float(CH - 4) { s.vel.y = min(s.vel.y, 0) }        // the sky's ceiling
        // Turning: slow with no way on, quicker under way; the pitch and bank eased toward the helm's.
        let under = min(1, abs(way) / 12)
        let yawRate = -steerIn * (meridian ? 0.18 + 0.24 * under : 0.1 + 0.16 * under)
        let wantRot = Capital.attitude(yaw: s.yaw, pitch: st.helmPitch, bank: st.helmBank)
        var e = wantRot * s.rot.inverse
        if e.real < 0 { e = Quat(vector: -e.vector) }
        let ang = 2 * acosf(max(-1, min(1, e.real)))
        let axis: V3 = ang > 1e-4 ? simd_normalize(e.imag) : V3(0, 1, 0)
        s.angVel = axis * min(0.8, ang * 3) + V3(0, yawRate, 0)
        // P464 (Remington, Oct 25 20:15, "Engine's out? What? How are the engines out?... there should be a way more
        // intuitive way"): engines stopped with their blocks still in place (a hard knock, a heavy shell) catch again
        // on their own after Capital.restartTime seconds; an ingot on the hull still restarts them at once, and
        // engine blocks shot away still need the ingots.
        if st.engines0 > 0 {
            var present = 0
            for (c, _) in st.engineCells where ShipParts.kinds[Int(s.grid.get(c.x, c.y, c.z))] == .engine { present += 1 }
            if s.engines < present {
                st.restartT += dt
                if st.restartT >= Capital.restartTime {
                    s.engines = present
                    st.enginesShaken = false
                    st.restartT = 0
                    g.sfx(.anvil, 0.6, at: s.pos)
                    if aboard?.root === s || pilot === s { g.onToast?("The \(s.name)'s engines caught again") }
                }
            } else { st.restartT = 0 }
        }
        // (e) The engine room shows what the drive has lost: smoke rises from the empty engine sockets.
        if !st.engineCells.isEmpty && simd_length(g.player.pos - s.pos) < 160 {
            for _ in 0..<4 {
                let c = st.engineCells[Int.random(in: 0..<st.engineCells.count)].0
                if (s.grid.get(c.x, c.y, c.z) == AIR || st.enginesShaken) && Rand.float(in: 0..<1) < dt * 30 {
                    g.particles.smoke(at: s.toWorld(V3(Float(c.x) + 0.5, Float(c.y) + 0.5, Float(c.z) + 0.5)), dark: true)
                }
            }
        }
    }

    // P325 (d) (Oct 15 19:15, "if I go way into the ground the way I just did, I should be dead"): a commandeered
    // frigate is solid against the world. The hull's outline (its outermost blocks, every fourth) is tested against the
    // ground each frame. Driving into it tears hull and ground where they meet (blasts scaled by the speed), shakes and
    // hurts those aboard and stops the hull there; at Capital.crashSpeed or more the drive goes up and the frigate is a
    // wreck where it lies (a pilot is thrown from the helm and, in survival, takes a blow that kills at full speed).
    // Leaves and plants don't count; resting against the ground without moving into it does nothing.
    private func hullContact(_ s: Ship, _ st: CapitalState, _ dt: Float, _ g: Game) {
        st.bumpCD -= dt
        // Broadphase: the hull's lowest point against the highest ground under its outline.
        var high = -Float.greatestFiniteMagnitude
        for i in 0..<3 { for j in 0..<3 {
            let x = Int(floor(s.worldMin.x + (s.worldMax.x - s.worldMin.x) * Float(i) * 0.5))
            let z = Int(floor(s.worldMin.z + (s.worldMax.z - s.worldMin.z) * Float(j) * 0.5))
            high = max(high, Float(world.isLoaded(x, z) ? world.topY(x, z) : world.gen.column(x, z).height) + 1)
        } }
        guard s.worldMin.y < high + 2 else { return }
        if st.probes == nil || abs(s.blockCount - st.probeBlocks) > 150 { st.probes = Capital.hullProbes(s.grid); st.probeBlocks = s.blockCount }
        let leaf = Mesher.leafT
        var hits: [V3] = []
        // P472 (Oct 26 20:14, "the frigate should also break through trees and break through blocks too, to a degree"):
        // under way she breaks what her hull runs into a moment ahead: trees (leaves, trunks), plants, planking, glass
        // and wool always; built blocks short of stone's hardness at 8 blocks a second or more. Natural ground, stone
        // and harder stop her as before. A budget a frame (160 blocks) keeps a forest from stalling it.
        let speed = simd_length(s.vel)
        var broke = 0
        func breakable(_ q: IVec3) -> Bool {
            let ab = world.block(q.x, q.y, q.z)
            guard ab != AIR, !Blocks.isLiquid(ab), world.blockEntities[q] == nil, !world.groundAt(q.x, q.y, q.z) else { return false }
            return Capital.crushable(ab) || (speed >= 8 && !ShipParts.natural[Int(ab)] && Blocks.hardness[Int(ab)] >= 0 && Blocks.hardness[Int(ab)] < 1.5)
        }
        for l in st.probes ?? [] {
            let p = s.toWorld(l)
            if speed > 1.5 && broke < 160 {
                // (the probes stand 3 cells apart: a probe meeting something breakable clears the cells round it too)
                let a = p + s.vel * 0.15
                let q0 = IVec3(Int(floor(a.x)), Int(floor(a.y)), Int(floor(a.z)))
                if breakable(q0) {
                    for dy in -1...1 { for dz in -1...1 { for dx in -1...1 where broke < 160 {
                        let q = IVec3(q0.x + dx, q0.y + dy, q0.z + dz)
                        guard dx == 0 && dy == 0 && dz == 0 || breakable(q) else { continue }
                        // A few break as he would (pieces, a drop now and then); the rest go at once, unremeshed here.
                        if broke % 8 == 0 { g.breakBlock(q, world.block(q.x, q.y, q.z), drop: broke % 16 == 0) } else { world.setBlockAsync(q.x, q.y, q.z, AIR) }
                        broke += 1
                    } } }
                }
            }
            let b = world.block(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)))
            if Blocks.collide[Int(b)] && !leaf[Int(b)] && !(speed > 1.5 && Capital.crushable(b)) { hits.append(p); if hits.count >= 12 { break } }
        }
        ShipManager.crushed += broke
        guard !hits.isEmpty else { return }
        var c = V3(0, 0, 0)
        for h in hits { c += h }
        c /= Float(hits.count)
        // How fast the touching part drives in: the hull's velocity there along the way from the hull's middle out to it.
        let inward = simd_normalize(c - s.pos + V3(0, 1e-4, 0))
        let impact = simd_dot(s.velocity(at: c), inward)
        guard impact > 0.3 else { return }
        s.vel -= inward * max(0, simd_dot(s.vel, inward))                 // no further in
        s.angVel = V3(0, s.angVel.y * 0.3, 0)
        let aboard = (self.aboard?.root === s || pilot === s) && g.alive
        if impact >= Capital.crashSpeed {
            Capital.crashes += 1
            // P476 (Oct 27 19:14, "crashing it shouldn't really do that much damage. It'll damage the front. Maybe if it
            // crashed too hard, it would destroy enough blocks to disrupt the main gun"): a crash tears the hull open
            // where it struck, wider the harder, and stops her there; she flies on unless it was too hard (Capital.
            // wreckSpeed: the drive goes up and the hull is a wreck, as every crash was before) or it tore the main gun's
            // barrel away (the gun is out). Engines knocked off their mounts stall as from a hard knock.
            let k = min(1, (impact - Capital.crashSpeed) / (Capital.wreckSpeed - Capital.crashSpeed))
            let wreck = impact >= Capital.wreckSpeed
            // P472 (Oct 26 19:48 and 20:14, "crashing shouldn't kill you like that... if I hit the ground, I don't see
            // why that needs to kill me"): whoever is aboard rides out the crash shaken, not hurt; the ship takes it.
            Explosion.sparePlayer = aboard
            defer { Explosion.sparePlayer = false }
            let had = s.blockCount
            for h in hits.prefix(wreck ? 4 : 1) { Explosion.explode(at: h, power: wreck ? 6 : 1.5 + 3 * k, game: g, fire: wreck || k > 0.6) }
            let blasted = had - s.blockCount
            // P357 (c), (d) (Oct 16 20:14): a crash breaks the ship apart where it struck (wider the faster it hit, and
            // what is torn loose falls away: removeCells); a wrecking one puts every light aboard out.
            var torn = 0
            for h in hits.prefix(wreck ? 6 : 2) { torn += tearHull(s, at: h, radius: wreck ? 9.5 : 1.5 + 4 * k, game: g) }
            Capital.crashLog.append(String(format: "crash %.1f b/s: blast %d, torn %d, loose %d", impact, blasted, torn, had - s.blockCount - blasted - torn))
            g.sfx(.shipCollideHard, 2, at: c)
            if simd_length(g.player.pos - c) < 200 { g.addShake(min(1, 0.5 + 0.5 * k)) }
            s.vel *= 0.15
            s.angVel = .zero
            let hurt = Int(((impact - 8) * (wreck ? 3 : 1)).rounded())
            for m in g.mobs.mobs where m.deck === s && m.health > 0 { m.health -= hurt; m.hurt = 0.3; if wreck { m.crewFree = true } }
            guard wreck else {
                st.bumpCD = 1.5                                          // (her rebound off it is the same crash)
                let before = s.blockCount
                engineShock(s, st, impact, g)
                Capital.crashLog.append("engines \(before - s.blockCount)")
                if st.mainGunLength > 0 && st.mainGunCD < 1e30 && Capital.barrelTorn(s, st) {
                    st.mainGunCD = .greatestFiniteMagnitude; st.gunCharge = -1
                    if aboard || simd_length(g.player.pos - c) < 200 { g.onToast?("The crash tore away the \(MainGun.name)'s barrel") }
                }
                return
            }
            lightsOut(s)
            if !st.exhausts.isEmpty {                                    // the drive goes up
                let e = st.exhausts.reduce(V3(0, 0, 0), +) / Float(st.exhausts.count)
                blast(at: s.toWorld(e + V3(0, 0, -8)), power: 6, game: g)
            }
            s.wrecked = true
            st.disabledWhy = "crashed"
            st.gunCharge = -1
            if pilot === s { g.leaveHelm() }
            return
        }
        s.vel -= inward * min(2, impact * 0.25)                          // a recoil off the ground
        // P357 (c): a careful landing (under 6 blocks/s where it touches) only scrapes: smoke, no damage.
        guard impact >= 6, st.bumpCD <= 0 else {
            if Rand.float(in: 0..<1) < dt * 20 { g.particles.smoke(at: c, dark: true) }
            return
        }
        // A hard knock: hull and ground torn where they met, the deck jolts.
        st.bumpCD = 0.8
        let k = min(1, (impact - 6) / 8)
        let had = s.blockCount
        defer { Capital.crashLog.append(String(format: "knock %.1f b/s: %d", impact, had - s.blockCount)) }
        Explosion.sparePlayer = aboard
        for h in hits.prefix(2) { Explosion.explode(at: h, power: 1.5 + 2 * k, game: g) }
        Explosion.sparePlayer = false
        tearHull(s, at: hits[0], radius: 1.5 + 2 * k, game: g)
        engineShock(s, st, impact, g)
        g.sfx(.shipCollideHard, 1 + k, at: c)
        for _ in 0..<Int(6 + 10 * k) { g.particles.smoke(at: c + V3(Rand.float(in: -2...2), Rand.float(in: 0...2), Rand.float(in: -2...2)), dark: true) }
        if aboard {
            g.addShake(0.35 + 0.4 * k)
        }
    }

    // P434 (g) (Remington, Oct 24 15:33, his idea: "when the ship hits something hard, its momentum breaks parts loose in
    // the engine room and it stops working, with a simple repair if the hit wasn't too hard"). A hard knock short of the
    // crash that wrecks her (9 blocks/s or more where she struck) throws the drive engines off their mounts: they stop,
    // their blocks still in place, and she coasts to a stop where she is; at 11 or more a few engine blocks are torn
    // loose too. An ingot of steel or iron used on the hull gets them going (repairVehicle: the stopped engines restart,
    // and up to eight torn-out engine blocks are refitted an ingot). The stopped engines smoke and spark (flyCommandeered).
    func engineShock(_ s: Ship, _ st: CapitalState, _ impact: Float, _ g: Game) {
        guard impact >= 9, st.engines0 > 0, s.engines > 0 else { return }
        let kinds = ShipParts.kinds
        let mounted = st.engineCells.map { $0.0 }.filter { kinds[Int(s.grid.get($0.x, $0.y, $0.z))] == .engine }
        if impact >= 11 && !mounted.isEmpty {
            let n = min(mounted.count, 2 + Int((impact - 11) * 0.7))
            let torn = Set(mounted.shuffled().prefix(n))
            let mid = torn.reduce(V3(0, 0, 0)) { $0 + V3(Float($1.x) + 0.5, Float($1.y) + 0.5, Float($1.z) + 0.5) } / Float(torn.count)
            // (P476: torn off their mounts, not cut loose: a block or two gone from an engine never dropped the rest of it
            // through the hull, 952 blocks at a 17 b/s crash.)
            removeCells(s, torn, chipped: [], center: s.toWorld(mid), power: 2, game: g, detach: false)
        }
        s.engines = 0
        st.enginesShaken = true
        if let e = mounted.first { g.sfx(.explode, 0.5, at: s.toWorld(V3(Float(e.x) + 0.5, Float(e.y) + 0.5, Float(e.z) + 0.5))) }
        if aboard?.root === s || pilot === s { g.onToast?("The \(s.name)'s engines shook loose and stopped") }
    }

    // P357 (c): the hull broken open round a world point: every breakable cell within a ragged ball of the radius goes
    // (dropping now and then; loose pieces fall away: removeCells -> detachLoose). Returns the cells taken.
    @discardableResult
    func tearHull(_ s: Ship, at p: V3, radius r: Float, game g: Game) -> Int {
        let l = s.toLocal(p)
        let ri = Int(ceilf(r))
        let cx = Int(floor(l.x)), cy = Int(floor(l.y)), cz = Int(floor(l.z))
        var gone = Set<IVec3>()
        for dy in -ri...ri { for dz in -ri...ri { for dx in -ri...ri {
            let d2 = Float(dx * dx + dy * dy + dz * dz)
            let edge = r * (0.7 + 0.3 * hashf(cx + dx, cy + dy, cz + dz, 3572))
            guard d2 <= edge * edge else { continue }
            let b = s.grid.get(cx + dx, cy + dy, cz + dz)
            if b != AIR && Blocks.hardness[Int(b)] >= 0 { gone.insert(IVec3(cx + dx, cy + dy, cz + dz)) }
        } } }
        if !gone.isEmpty { removeCells(s, gone, chipped: [], center: p, power: max(2, r), game: g) }
        return gone.count
    }

    // P357 (d): every light aboard dark: panels dead, portholes unlit, thruster cores and coils cold.
    func lightsOut(_ s: Ship) {
        let panelOff = Capital.id("light_panel_off", AIR), port = Capital.id("frigate_porthole_dark", AIR)
        let trim = Capital.id("frigate_trim", AIR)
        var swap: [BlockID: BlockID] = [:]
        for (n, to) in [("light_panel", panelOff), ("frigate_porthole", port), ("frigate_thruster", trim)] where Blocks.has(n) && to != AIR {
            swap[Blocks.id(n)] = to
        }
        guard !swap.isEmpty else { return }
        let gr = s.grid
        var changed: [IVec3] = []
        for y in 0..<gr.sy { for z in 0..<gr.sz { for x in 0..<gr.sx {
            if let to = swap[gr.blocks[gr.index(x, y, z)]] { gr.set(x, y, z, to); changed.append(IVec3(x, y, z)) }
        } } }
        if !changed.isEmpty { s.mesh.rebuildAround(s, changed, device: world.device, queue: meshQueue) }
        Capital.darkened.insert(s.id)
    }

    // P325: sets a commandeered capital flier's attitude at once (its heading kept): the bow pitched, the wings level.
    func pointHull(_ s: Ship, pitch: Float) {
        guard let st = capState[s.id] else { return }
        st.helmPitch = max(-Capital.maxPitch, min(Capital.maxPitch, pitch))
        st.helmBank = 0
        s.rot = Capital.attitude(yaw: s.yaw, pitch: st.helmPitch, bank: 0)
        s.prevRot = s.rot
        s.angVel = .zero
        s.updateBounds()
        for t in turrets(of: s) { t.followParent(0) }
    }

    // P66: a commandeered drop craft burns fuel while it thrusts (P461: fifteen minutes on full tanks). Running dry, it
    // pours in a Fuel Can from the pilot's pack (a third of a tank); with none, it sinks gently to the ground. Returns
    // false when there is no fuel.
    // P461 (Oct 25 16:40, "It needs to refuel... fuel we have to get from a fuel depot. Make that one of the bases, base
    // types, a fuel depot"): fuel comes in Fuel Cans (VehicleDepot) and from a Fuel Depot base he has taken, which
    // fills it standing there (BaseSpecialties); coal and blaze rods no longer run it.
    static let canFuel: Float = CapitalState.dropFuel / 3
    func dropFuel(_ s: Ship, _ st: CapitalState, _ dt: Float, _ g: Game) -> Bool {
        if abs(s.throttle) > 0.05 || abs(s.climb) > 0.05 { st.fuel -= dt * (s.boost && s.throttle > 0.05 ? 2 : 1) }
        if st.fuel <= 0, Items.has(VehicleDepot.canKey), g.inventory.main.remove(Items.id(VehicleDepot.canKey), 1) == 1 {
            st.fuel += ShipManager.canFuel
            g.sfx(.bucketEmpty, 0.8, at: g.player.pos)
            g.onToast?("Poured a Fuel Can into the \(s.name)")
        }
        if st.fuel > 30 { st.fuelTold = 0 }
        if st.fuel <= 30 && st.fuel > 0 && st.fuelTold == 0 { st.fuelTold = 1; g.onToast?("\(s.name): fuel low") }
        if st.fuel <= 0 {
            st.fuel = 0
            if st.fuelTold < 2 { st.fuelTold = 2; g.onToast?("\(s.name): out of fuel. It settles to the ground") }
            return false
        }
        return true
    }

    // The drive's glow (done audit 25b6, G8: "thrusters read as two small points at night"): a soft blue-white sprite
    // over each nozzle as wide as the nozzle, growing with distance so the stern still reads as engines a few hundred
    // blocks off (a fixed-size face shrinks to a dot), and the nozzles' light on the hull near by. One particle per
    // nozzle per frame (five on the Meridian frigate).
    func driveGlow(_ s: Ship, _ st: CapitalState, _ pd: Float, _ dt: Float, _ g: Game) {
        guard !st.exhausts.isEmpty, st.engines0 > 0, !s.wrecked, pd < 700 else { return }
        let k = Float(s.engines) / Float(st.engines0)
        guard k > 0.4 else { return }
        let aft = s.dirToWorld(V3(0, 0, 1))
        let layer = FrigateBoarding.puffLayer
        let far = min(3, max(1, pd / 150))
        let night = 1 + 0.8 * (1 - g.daylight)
        for (i, n) in st.exhausts.enumerated() {
            let small = s.role == "capfrigate" && i == st.exhausts.count - 1      // the centre nozzle (radius 2)
            let at = s.toWorld(n) + aft * 0.8
            let flicker = 0.9 + 0.1 * sinf(Float(g.clock) * 37 + Float(i) * 1.7)
            g.particles.add(Particle(pos: at, vel: s.vel, life: dt * 1.5, maxLife: dt * 1.5, layer: layer, uv0: V2(0, 0), uvSize: 1,
                                     size: (small ? 3.5 : 7.5) * far * flicker, gravity: 0, color: V3(0.45, 0.75, 1.3) * k * night,
                                     collide: false, glow: true))
        }
        // One light for the whole stern (the flash list is shared with gunfire: 32 at most).
        if pd < 160 {
            let c = st.exhausts.reduce(V3(0, 0, 0), +) / Float(st.exhausts.count)
            g.addFlash(at: s.toWorld(c) + aft * 3, color: V3(0.5, 0.8, 1.6) * (1.5 * k), radius: 22, life: dt * 1.5)
        }
    }

    // P334: turns the hull toward a pitch and bank (radians) at its own yaw while yawing at `yawRate`.
    private func steerAttitude(_ s: Ship, pitch: Float, bank: Float, yawRate: Float) {
        let wantRot = Capital.attitude(yaw: s.yaw, pitch: pitch, bank: bank)
        var e = wantRot * s.rot.inverse
        if e.real < 0 { e = Quat(vector: -e.vector) }
        let ang = 2 * acosf(max(-1, min(1, e.real)))
        let axis: V3 = ang > 1e-4 ? simd_normalize(e.imag) : V3(0, 1, 0)
        s.angVel = axis * min(1.5, ang * 4) + V3(0, yawRate, 0)
    }

    private func levelUp(_ s: Ship, _ dt: Float) {
        let up = s.dirToWorld(V3(0, 1, 0))
        let axis = simd_cross(up, V3(0, 1, 0))
        s.angVel += axis * 1.5
    }

    // Ironback Crawler: roll toward the target to 100, then hold and turn the bow on for the rail gun; without one,
    // patrol round home. The hull follows the ground (pitch and roll from the terrain under its wheels), turns back
    // from water and cliffs, and crushes trees and other small things in its way.
    private func driveCrawler(_ s: Ship, _ st: CapitalState, _ dt: Float, _ g: Game) {
        let home = s.home ?? s.pos
        let fw = s.dirToWorld(V3(0, 0, -1))
        let fh = simd_normalize(V2(fw.x, fw.z) + V2(1e-5, 0))
        var want = fh
        var speed: Float = 3.5
        if let t = st.target {
            let to = V2(t.point.x - s.pos.x, t.point.z - s.pos.z)
            let d = max(1, simd_length(to))
            want = to / d
            speed = d > 100 ? 6 : (st.mainGunCD <= 2 ? 1 : 0)
        } else if let goal = st.goal {
            // Patrol: drive to the goal and wait there.
            let to = V2(goal.x - s.pos.x, goal.z - s.pos.z)
            let d = max(1, simd_length(to))
            want = d > 12 ? to / d : fh
            speed = d > 12 ? min(5, d * 0.15 + 1) : 0
        } else {
            let toHome = V2(home.x - s.pos.x, home.z - s.pos.z)
            let dist = max(1, simd_length(toHome))
            let r: Float = 140
            let tangent = V2(-toHome.y, toHome.x) / dist * st.orbitDir
            let steer: V2 = tangent + toHome * ((dist - r) / (r * dist))
            want = simd_normalize(steer + V2(1e-4, 0))                  // at home exactly: no NaN
        }
        if let k = st.testTurn {
            want = V2(fh.x * cosf(k) - fh.y * sinf(k), fh.x * sinf(k) + fh.y * cosf(k))
            speed = st.testSpeed ?? 6
        }
        // Lost wheels slow it; without a driver (or helm) it rolls to a halt where it is.
        if !st.wheels.isEmpty { speed *= 1 - Float(st.wheelsLost) / Float(st.wheels.count) }
        if !st.driverAlive || s.helm == nil { speed = 0; want = fh }
        st.wantSpeed = speed
        // The ramp down (troops going out, riders walking up): it creeps until it is raised.
        if st.rampDown { speed = min(speed, 1.5) }
        crawlerMotion(s, st, dt, want: want, speed: speed, turnRate: 0.18)
        TickProf.mark("cap: drive motion")                   // (store review: the drive split for the frame soak)
        crawlerCrush(s, st, dt, g)
    }

    // Blocks a vehicle rests on: terrain (not leaves, logs or plants, which it crushes or rolls over).
    static let groundBlock: [Bool] = {
        var t = [Bool](repeating: false, count: Blocks.count)
        // (Water isn't ground: under a lake the bottom is, so the crawler still sees the lake as too deep and turns.)
        for i in 0..<Blocks.count where Blocks.collide[i] && !Blocks.isLiquid(BlockID(i)) {
            let k = Blocks.key(Blocks.groupBase[i])
            t[i] = ShipParts.natural[i] && !k.hasSuffix("_leaves") && !k.hasSuffix("_log") && !k.contains("mushroom")
        }
        return t
    }()

    // The ground's top block at a column: the real world surface where it is loaded (trees and plants skipped), else
    // the generator's height (which misses carved valleys: a crawler floated 17 blocks over one, ride check board scene).
    func groundTop(_ x: Int, _ z: Int) -> Float {
        guard world.isLoaded(x, z) else { return Float(world.gen.column(x, z).height) }
        var y = world.topY(x, z)
        var k = 0
        let gb = ShipManager.groundBlock
        while y > 0 && k < 48 && !gb[Int(world.rawBlock(x, y, z))] { y -= 1; k += 1 }
        return Float(y)
    }

    // Moves a crawler at `speed` toward heading `want`, its hull following the ground (pitch and roll from the terrain
    // under its wheels, smoothed: the four samples step a block at a time as they cross block edges, and the hull's
    // turn rate eases in, so riders on deck feel no jolts), turning back from water and cliffs.
    private func crawlerMotion(_ s: Ship, _ st: CapitalState, _ dt: Float, want want0: V2, speed speed0: Float, turnRate: Float, piloted: Bool = false) {
        var want = want0, speed = speed0
        let fw = s.dirToWorld(V3(0, 0, -1))
        let fh = simd_normalize(V2(fw.x, fw.z) + V2(1e-5, 0))
        // P510 (Nov 1 20:29-20:30, at a crawler's helm on a beach: "For some reason it can't move... Maybe it's 'cause I'm
        // trying to go in water... It should be able to go into water no problem"; 20:51, "the crawler doesn't like water
        // but moves great elsewhere"): under his hand water no longer stops it short. It wades in on its wheels, the hull
        // riding the bottom; where the water is deeper than its draft it swims, the hull at the surface less the draft,
        // at a third of its pace on land, and climbs out on the far bank. (Its own crew still turn back from water.)
        var wet = 0
        func ground(_ p: V2) -> Float {
            let x = Int(floor(p.x)), z = Int(floor(p.y))
            let g = groundTop(x, z)
            guard piloted, world.isLoaded(x, z) else { return g }
            var wy = Int(g) + 1, k = 0
            while k < 64 && wy < CH - 1 && Blocks.isLiquid(world.rawBlock(x, wy, z)) { wy += 1; k += 1 }
            guard k > 0 else { return g }
            wet += 1
            return max(g, Float(wy) - ShipManager.crawlerDraft)
        }
        let half: Float = 28, track: Float = 13
        let c2 = V2(s.pos.x, s.pos.z)
        let side = V2(-fh.y, fh.x)
        let hF = ground(c2 + fh * half), hB = ground(c2 - fh * half)
        let hL = ground(c2 - side * track), hR = ground(c2 + side * track)
        // Water or a cliff ahead: turn away.
        // P499 (Oct 30 20:19, at a captured crawler's helm: "its turning is inverted"): under the player it no longer
        // swings itself round its patrol's way (the stick turned it the other way, or not at all): it stops short and
        // the stick still turns it, or backs it off.
        if wet >= 2 { speed *= 0.35; ShipManager.crawlerWaded += 1 }
        if turnRate > 0 || (piloted && speed > 0) {
            let hA = ground(c2 + fh * (half + 14))
            if (hA < Float(SEA) && !piloted) || hA - hF > 8 {
                if piloted { speed = min(speed, 0) }
                else { want = V2(-fh.y, fh.x) * st.orbitDir; speed = min(speed, 1.5) }
            }
        }
        let yawRate = turnRate > 0 ? turnToward(s, want, maxRate: turnRate) : 0
        let pitch = atan2f(hF - hB, 2 * half), roll = atan2f(hR - hL, 2 * track)
        let raw = V3((hF + hB + hL + hR) * 0.25 + 1, pitch + st.sag.x, roll + st.sag.y)
        var gs = st.ground ?? raw
        gs += (raw - gs) * min(1, dt * 4)
        st.ground = gs
        let wantRot = Quat(angle: s.yaw + yawRate * 0.4, axis: V3(0, 1, 0)) * Quat(angle: gs.y, axis: V3(1, 0, 0)) * Quat(angle: gs.z, axis: V3(0, 0, 1))
        var e = wantRot * s.rot.inverse
        if e.real < 0 { e = Quat(vector: -e.vector) }
        let ang = 2 * acosf(max(-1, min(1, e.real)))
        let axis = ang > 1e-4 ? simd_normalize(e.imag) : V3(0, 1, 0)
        let av: V3 = axis * min(0.6, ang / 0.4)
        s.angVel += (av - s.angVel) * min(1, dt * 6)
        let vy = max(-6, min(6, (gs.x + st.groundOffset - s.pos.y) * 3))
        let target = V3(fw.x, 0, fw.z) * speed + V3(0, vy, 0)
        s.vel += (target - s.vel) * min(1, dt * 1.2)
    }

    // The crawler's rear ramp: lowered while it stands or creeps (troops walk out, the player walks up), raised into a
    // door once it means to drive off and nobody stands on it (after 8 s it closes anyway). A disabled crawler drops it.
    func crawlerRamp(_ s: Ship, _ st: CapitalState, _ dt: Float, _ g: Game) {
        let troopsOut = st.crewMobs.values.contains { !$0.crewRoute.isEmpty && $0.deck === s && $0.health > 0 }
        // P510 (Nov 1 20:30:10, driving a captured one slowly out of the water: "this thing dragging off its rear end.
        // Like that's-- We don't need that"): at his helm the ramp stays up however slowly it goes; it comes down
        // only once he has let go of the helm with it standing.
        let his = pilot === s
        // P511 (Nov 2 08:51:09, at a captured one's helm: "Still got the back ramp on the crawler. It's gotta go"): a
        // captured crawler's ramp goes up and stays up (its tick never ran this, so it kept the ramp it was built with,
        // dragging down behind it); he boards by the roof hatch.
        let want = s.captured ? false : s.wrecked || (his ? false : (troopsOut || st.wantSpeed < 1.6))
        if want == st.rampDown { st.rampTimer = 0; return }
        st.rampTimer += dt
        if st.rampTimer < 0.6 { return }
        if !want && st.rampTimer < 8 {
            // Anyone on the ramp or in the doorway (ship space: behind the bay floor's end) holds it down.
            let ox = Float(s.grid.sx / 2)
            func onRamp(_ w: V3) -> Bool {
                let l = s.toLocal(w)
                return l.z > 72.6 && l.z < 85 && abs(l.x - ox - 0.5) < 5 && l.y > -1 && l.y < 17
            }
            if onRamp(g.player.pos) { return }
            for m in g.mobs.mobs where m.health > 0 && m.deck === s && onRamp(m.pos) { return }
        }
        st.rampDown = want
        st.rampTimer = 0
        let ox = s.grid.sx / 2
        setBlocks(s, Capital.crawlerRamp(down: want).map { (IVec3($0.0.x + ox, $0.0.y, $0.0.z), $0.1) })
        g.sfx(want ? .pistonContract : .pistonExtend, 1.2, at: s.toWorld(V3(Float(ox) + 0.5, 9, 78)))
    }

    // Trees, plants, fences, glass and timber under the crawler's front give way (no drops); driving on, so does
    // masonry (P65).
    static var rutCells = 0, rutDug = 0, crawlerFelled = 0     // (checks)
    static let crawlerDraft: Float = 6                          // P510: its wheels and lower hull under the water when it swims
    static var crawlerWaded = 0                                 // (checks: steps it moved with water under its wheels)
    private func crawlerCrush(_ s: Ship, _ st: CapitalState, _ dt: Float, _ g: Game) {
        st.crushTimer -= dt
        // Store review (Nov 2, VRC.Quest.Performance.1; questcheck --framesoak crawler: the capital tick 37-57 ms on a
        // pass's frame): a pass under way sweeps the whole footprint, tens of thousands of cells, so it is spread over
        // the frames after it starts, `crushSeconds` of work a frame, and carries on from the row it reached.
        let resume = st.crushNextZ
        st.crushNextZ = nil
        guard st.crushTimer <= 0 || resume != nil else { return }
        if resume == nil { st.crushTimer = st.wantSpeed > 12 ? 0.1 : 0.25 }           // (P507: at 100 km/h a pass every 3 blocks)
        // P511: its wear (ruts, what the hull sweeps through, plants under the bow) meshes in the queue's order, at most
        // every settleGap (World.vehicleEdits); only what the bow rams that stands up in the way (a trunk, a wall) goes
        // ahead of the queue, so it is seen to give way.
        if World.vehicleWear == "off" { return }
        let wear = World.vehicleWear != "0"
        let was = (World.backgroundEdits, World.vehicleEdits, World.ramEdits)
        defer { World.backgroundEdits = was.0; World.vehicleEdits = was.1; World.ramEdits = was.2 }
        func worn(_ on: Bool) { if wear { World.backgroundEdits = on || was.0; World.vehicleEdits = on; World.ramEdits = !on } }
        worn(true)
        // (the ground round its footprint, a chunk out: what settles there after the pass is wear too)
        if wear && resume == nil {
            let lo = s.worldMin, hi = s.worldMax
            for cz in floorDiv(Int(floor(lo.z)) - CS, CS)...floorDiv(Int(floor(hi.z)) + CS, CS) {
                for cx in floorDiv(Int(floor(lo.x)) - CS, CS)...floorDiv(Int(floor(hi.x)) + CS, CS) {
                    world.chunkAt(cx * CS, cz * CS)?.wornAt = World.frameNow
                }
            }
            World.wearZone(s.id, cx0: floorDiv(Int(floor(lo.x)), CS), cz0: floorDiv(Int(floor(lo.z)), CS),
                           cx1: floorDiv(Int(floor(hi.x)), CS), cz1: floorDiv(Int(floor(hi.z)), CS))
        }
        if st.wantSpeed > 0.3 && resume == nil { crawlerRuts(s, st); TickProf.mark("cap: drive ruts") }
        // (a felled trunk lies as a body for good: one a pass, only where he can see it, and not past a dozen about)
        var felled = simd_length(g.player.pos - s.pos) < 110 ? 0 : 1
        if felled == 0 && world.ships.list.reduce(0, { $0 + (Felling.isFelled($1) && simd_length($1.pos - s.pos) < 160 ? 1 : 0) }) >= 12 { felled = 1 }
        let fwd = s.dirToWorld(V3(0, 0, -1))
        let lo = s.localMin, hi = s.localMax
        var n = 0
        let hardness = Blocks.hardness
        // On arrival the whole footprint is cleared once (it spawned among trees that hid its wheels: run 404).
        // The full pass waits until every corner of the footprint is loaded and repeats until one pass finishes under
        // the cap (done when only the centre had loaded, the rest of the trees stayed in the hull: blind critic, run 417
        // ship_crawler, an oak through a wheel arch).
        var cornersLoaded = true
        for (cx, cz) in [(lo.x, lo.z), (hi.x, lo.z), (lo.x, hi.z), (hi.x, hi.z)] {
            let c = s.toWorld(V3(cx, lo.y, cz))
            if !world.isLoaded(Int(floor(c.x)), Int(floor(c.z))) { cornersLoaded = false }
        }
        let full = !st.crushedAll && cornersLoaded
        // P499 (Oct 30 20:18-20:21, "the crawler is not destroying trees as it travels", "the trees are bullying the
        // crawler", "a bunch of trees it's just morphing through"): under way every pass sweeps the whole footprint, from
        // four rows ahead of the bow back to the stern (a turn swings the sides and the stern through trees the bow
        // never met; a quarter second at full speed is over two rows), and a crown of leaves no longer uses up the pass
        // before the trunks behind it (80 blocks a pass left most of a tree standing in the hull). Buildings break only
        // where the bow and the first rows ram them.
        if !full && st.wantSpeed < 0.3 { return }          // (parked: nothing new under it)
        let cap = full ? 4000 : 900
        defer { if full && n < cap { st.crushedAll = true } }
        let ahead = max(Float(4), (st.wantSpeed * 0.3).rounded(.up))
        // Store review (frame soak: the sweep was 1.3 ms of every frame under way): going straight, what comes into the
        // footprint comes in at the bow, so a pass sweeps the bow's rows (and those ahead); the whole footprint is swept
        // once it has turned two degrees since the last whole sweep (the sides and the stern swing through trees), and at
        // least once a second (climbing, sliding).
        if resume == nil {
            let dy = atan2f(sinf(s.yaw - st.crushFullYaw), cosf(s.yaw - st.crushFullYaw))
            if full || abs(dy) > 0.035 || g.clock - st.crushFullAt > 1 {
                st.crushEndZ = hi.z; st.crushFullYaw = s.yaw; st.crushFullAt = g.clock
            } else {
                st.crushEndZ = min(hi.z, lo.z + 8)
            }
        }
        let deadline = full ? Double.infinity : CFAbsoluteTimeGetCurrent() + ShipManager.crushSeconds
        for lz in stride(from: resume ?? (lo.z - ahead), through: st.crushEndZ, by: 1) {
            if CFAbsoluteTimeGetCurrent() > deadline { st.crushNextZ = lz; return }
            let bow = lz <= lo.z + 6
            for lx in stride(from: lo.x, through: hi.x, by: 1) {
                if lx > lo.x && CFAbsoluteTimeGetCurrent() > deadline { st.crushNextZ = lz; return }   // (a row of leaves: a column at a time)
                // From the bottom row (trunks stood through the wheel arches); soft blocks only, so ground is never dug.
                for ly in stride(from: lo.y, through: hi.y, by: 1) {
                    let w = s.toWorld(V3(lx, ly, lz))
                    let x = Int(floor(w.x)), y = Int(floor(w.y)), z = Int(floor(w.z))
                    guard world.isLoaded(x, z) else { continue }
                    let b = world.block(x, y, z)
                    if b == AIR || Blocks.isLiquid(b) { continue }
                    let soft = Capital.crawlerSoft[Int(b)] || (!Blocks.collide[Int(b)] && hardness[Int(b)] >= 0)
                    // P65: driving on, it breaks through buildings (walls, brick, stone work) instead of passing
                    // through them; natural ground and unbreakable blocks stay.
                    let built = bow && !full && !ShipParts.natural[Int(b)] && hardness[Int(b)] >= 0
                    if !soft && !built { continue }
                    // P507 (Nov 1 12:07:22, "It's definitely despawning trees. It's just the trees aren't falling, they're
                    // just despawning"): under way, a tree the bow meets goes over, out to the side it stood on and
                    // ahead, a felled trunk with its crown (Felling); the rest give way as before.
                    // (Store review, crawler soak build 103: a topple is 1-2 ms. On a frame with the carving allowance
                    // spent the trunk stands for a later pass; the bow's rows sweep four ahead of it.)
                    if bow && !full && felled < 1 && CapitalBase.isLog(b) && CraterJob.allowance() < 0.001 { continue }
                    if bow && !full && felled < 1 && CapitalBase.isLog(b), let trunk = treeAt(x, y, z) {
                        worn(false)
                        let off = simd_dot(V3(Float(x) + 0.5 - s.pos.x, 0, Float(z) + 0.5 - s.pos.z), simd_cross(fwd, V3(0, 1, 0)))
                        let out = simd_normalize(V3(fwd.x, 0, fwd.z) + simd_cross(fwd, V3(0, 1, 0)) * (off >= 0 ? 1.2 : -1.2) + V3(1e-5, 0, 0))
                        TickProf.mark("cap: drive sweep")
                        let t0 = CFAbsoluteTimeGetCurrent()
                        g.topple(trunk, away: out)
                        CraterJob.spend(CFAbsoluteTimeGetCurrent() - t0)
                        TickProf.mark("cap: drive topple")
                        felled += 1; ShipManager.crawlerFelled += 1
                        n += trunk.count
                        if n >= cap { return }
                        continue
                    }
                    worn(!(bow && Blocks.collide[Int(b)] && ShapeClass.kind[Int(b)] != .foliage))     // (P511: leaves wear too)
                    world.setBlockAsync(x, y, z, AIR)
                    n += 1
                    if n >= cap { return }
                }
            }
        }
    }

    // The trunk a log at (x, y, z) belongs to, from its foot up (26-connected logs; nil: not a standing tree, or too big).
    private func treeAt(_ x: Int, _ y: Int, _ z: Int) -> [IVec3]? {
        var foot = IVec3(x, y, z)
        while foot.y > 1 && CapitalBase.isLog(world.block(foot.x, foot.y - 1, foot.z)) { foot.y -= 1 }
        guard ShipManager.groundBlock[Int(world.rawBlock(foot.x, foot.y - 1, foot.z))] else { return nil }
        var logs: Set<IVec3> = [foot], queue = [foot]
        while let c = queue.popLast() {
            for dy in -1...1 { for dz in -1...1 { for dx in -1...1 where !(dx == 0 && dy == 0 && dz == 0) {
                let q = IVec3(c.x + dx, c.y + dy, c.z + dz)
                guard q.y >= foot.y, !logs.contains(q), CapitalBase.isLog(world.block(q.x, q.y, q.z)) else { continue }
                logs.insert(q); queue.append(q)
                if logs.count > Felling.maxLogs { return nil }
            } } }
        }
        return Array(logs)
    }

    // P507 (Nov 1 12:07:07, beside a crawler under way: "It's not leaving ruts in the ground"): the ground each of its
    // wheels rolls on is churned to bare earth (grass, snow, moss and the like), a pair of dark tracks behind it.
    private func crawlerRuts(_ s: Ship, _ st: CapitalState) {
        guard Blocks.has("coarse_dirt") else { return }
        let rut = Blocks.id("coarse_dirt")
        var dug = 0
        func hardnessOK(_ b: BlockID) -> Bool { let h = Blocks.hardness[Int(b)]; return h >= 0 && h < 2 }   // (soil, not rock)
        // P511 (questcheck --streamtest --crawler at his spot): every wheel cut a ball into the field ground on every pass
        // (up to 24 a second): each cut remeshed the ground round it, and the land round him waited. A wheel cuts again
        // only once it has rolled on most of a ball's width from its last cut, one cut a pass at most (below).
        // (The fine ground a few blocks ahead of each wheel made before it gets there, one section a pass: with it made
        // only when a cut needed it, the cut waited and the rut had gaps at the sections' borders.)
        let hv = V3(s.vel.x, 0, s.vel.z)
        if simd_length(hv) > 0.3 && CraterJob.allowance() >= 0.001 {
            let t0 = CFAbsoluteTimeGetCurrent()
            defer { CraterJob.spend(CFAbsoluteTimeGetCurrent() - t0) }
            let ahead = simd_normalize(hv) * 5
            for wh in st.wheels where !wh.lost {
                let mid = V3(Float(wh.lo.x + wh.hi.x + 1) * 0.5, Float(wh.lo.y) + 0.6, Float(wh.lo.z + wh.hi.z + 1) * 0.5)
                if world.prefetchFine(s.toWorld(mid) + ahead, radius: 1.8) { break }
            }
        }
        for (wi, wh) in st.wheels.enumerated() where !wh.lost {
            var sunk = 0
            defer {
                let mid0 = V3(Float(wh.lo.x + wh.hi.x + 1) * 0.5, Float(wh.lo.y), Float(wh.lo.z + wh.hi.z + 1) * 0.5)
                let at = s.toWorld(mid0)
                let rolled = st.rutCarved[wi].map { simd_length(V2($0.x - at.x, $0.z - at.z)) } ?? .infinity
                // (store review, the crawler soak: two cuts a pass were up to 21 ms of one frame; one a pass now, the
                // wheels taking turns as they roll on)
                // (and from the frame's shared carving, CraterJob.allowance: build 96's crawler soak had a rut's cut,
                // 4-7 ms, in the frames the ground collapse and the drive were heaviest; it waits for a frame with a millisecond
                // of carving left, after a light tick)
                if sunk > 0 && dug < 1 && rolled > 1.4 && CraterJob.allowance() >= 0.001 {
                    let t0 = CFAbsoluteTimeGetCurrent()
                    defer { CraterJob.spend(CFAbsoluteTimeGetCurrent() - t0) }
                    // (a ball whose bottom is a third of a block under the wheel: a shallow rut, not a trench)
                    let r = min(1.8, max(0.9, Float(min(wh.hi.x - wh.lo.x, wh.hi.z - wh.lo.z) + 1) * 0.5))
                    let mid = V3(Float(wh.lo.x + wh.hi.x + 1) * 0.5, Float(wh.lo.y) + r - 0.3, Float(wh.lo.z + wh.hi.z + 1) * 0.5)
                    // (the fine ground of a new section made first, one section a frame, World.prefetchFine: the cut
                    // comes on a later frame, once the ball's sections all have theirs)
                    if !world.prefetchFine(s.toWorld(mid), radius: r) {
                        st.rutCarved[wi] = at
                        ShipManager.rutDug += world.carve(at: s.toWorld(mid), radius: r, mode: .dig)
                    }
                    dug += 1
                }
            }
            for lz in wh.lo.z...wh.hi.z { for lx in wh.lo.x...wh.hi.x {
                let wp = s.toWorld(V3(Float(lx) + 0.5, Float(wh.lo.y), Float(lz) + 0.5))
                let x = Int(floor(wp.x)), z = Int(floor(wp.z))
                guard world.isLoaded(x, z) else { continue }
                // (ground standing up into the wheel's lower rows: on a rise the wheel cuts its track into the ground
                // instead of sinking through it, 12:07:07 "its wheels morphing through the terrain")
                for ly in thru(wh.lo.y, min(wh.hi.y, wh.lo.y + 1)) {
                    let cp = s.toWorld(V3(Float(lx) + 0.5, Float(ly) + 0.5, Float(lz) + 0.5))
                    let cb = world.rawBlock(Int(floor(cp.x)), Int(floor(cp.y)), Int(floor(cp.z)))
                    if ShipManager.groundBlock[Int(cb)] && hardnessOK(cb) { sunk += 1 }
                }
                let y = Int(groundTop(x, z))
                guard y > 1, abs(Float(y) + 1 - wp.y) < 3 else { continue }
                let b = world.rawBlock(x, y, z)
                guard ShipManager.rutGround[Int(b)] else { continue }
                world.setBlockAsync(x, y, z, rut)
                if world.isAir(x, y + 1, z) == false && !Blocks.collide[Int(world.rawBlock(x, y + 1, z))] { world.setBlockAsync(x, y + 1, z, AIR) }
                ShipManager.rutCells += 1
            } }
        }
    }
    static let rutGround: [Bool] = (0..<Blocks.count).map { i in
        let k = Blocks.key(Blocks.groupBase[i])
        return ["grass_block", "snowy_grass_block", "podzol", "mycelium", "moss_block", "dirt", "rooted_dirt", "snow_block"].contains(k)
    }

    // Guns: turrets track the target and fire on their own reloads; the spinal gun charges and fires a rail slug
    // down the bow when the target is within 25 degrees of it; missile salvos from the pods.
    // P334 (b) ("drop ship guns do almost nothing"): a dropship's autocannon fires rounds at a flak gun's strength (the
    // Armory's explosive slugs: a direct hit hurts like a rifle round, the burst like a flak shell, AirDefence.power),
    // red tracers, a proximity fuze against a flying player; the bursts break no blocks and spare its own side.
    private func dropshipBurst(_ s: Ship, _ tr: Ship, _ t: CapTarget, pitch: Float, _ g: Game) {
        for (c, d) in tr.cannons {
            let muzzle = tr.toWorld(c + d * 0.9)
            let horiz = simd_normalize(V3(tr.dirToWorld(d).x, 0, tr.dirToWorld(d).z) + V3(1e-5, 0, 0))
            let dir = Guns.scatter(simd_normalize(horiz * cosf(pitch) + V3(0, sinf(pitch), 0)), 0.012)
            var sl = Slug(pos: muzzle, vel: dir * AirDefence.flakSpeed + tr.velocity(at: muzzle), kind: .shell, damage: 7, fromPlayer: false,
                          shooter: nil, by: s.name, life: 3, gravity: tr.gunGravity)
            sl.power = AirDefence.power
            sl.tracer = true
            sl.side = s.factionValue
            if t.player && (g.player.flying || aboard != nil || pilot != nil) { sl.prox = AirDefence.prox }
            g.arms.spawn(sl)
            g.particles.smoke(at: muzzle)
        }
        tr.reload = tr.reloadTime
        g.sfx(.gun(9), 1.2, at: tr.pos)
        g.baseNoise(at: tr.pos, kind: .cannon, hostile: s.factionValue != .steelhold)
    }

    private func capitalGuns(_ s: Ship, _ st: CapitalState, _ dt: Float, _ g: Game) {
        st.mainGunCD -= dt
        st.missileCD -= dt
        let ts = turrets(of: s)
        guard let t = st.target else {
            for tr in ts { tr.aimAt = nil; tr.gunPitch *= max(0, 1 - dt) }
            st.mainCharge = 0
            return
        }
        for (i, tr) in ts.enumerated() {
            // An unmanned turret (its gunner dead) stays where it was left.
            guard st.turretManned(i) else { tr.aimAt = nil; continue }
            let muzzle = tr.toWorld(tr.pivot)
            var aim = t.point
            let flight0 = simd_length(aim - muzzle) / tr.gunSpeed
            aim += t.vel * flight0 * 0.8
            tr.aimAt = aim
            let d = aim - muzzle
            let horiz = simd_length(V2(d.x, d.z))
            if horiz < 6 { continue }
            let v = tr.gunSpeed, gr = tr.gunGravity
            let disc: Float = v * v * v * v - gr * (gr * horiz * horiz + 2 * d.y * v * v)
            let elev: Float = disc > 0 ? atanf((v * v - sqrtf(disc)) / (gr * horiz)) : 0.6
            tr.gunPitch += (max(tr.pitchMin, min(tr.pitchMax, elev)) - tr.gunPitch) * min(1, dt * 3)
            let tf = tr.dirToWorld(V3(0, 0, -1))
            let a = simd_normalize(V2(tf.x, tf.z) + V2(1e-5, 0)), b = simd_normalize(V2(d.x, d.z) + V2(1e-5, 0))
            let aimErr = acosf(max(-1, min(1, simd_dot(a, b))))
            // Out of the barrels' reach (straight below a dorsal gun): hold fire.
            if elev < tr.pitchMin - 0.05 || elev > tr.pitchMax + 0.05 { continue }
            // P483 (Oct 28 17:34-17:36, "the frigate's guns aren't hurting me at all", "the little guns just are not
            // shooting where one would expect"): a gun fired while still turning, up to 7 degrees off, so its rounds
            // burst 15 to 40 blocks from a man 150 off. It fires once laid within about two blocks of him (or 0.12 rad,
            // close in).
            // (Or once it has come round onto its bearing, on a hull pitched so that its plane never quite meets him.)
            // (Dropships as they were: "the aiming for the drop ship... it's actually working".)
            let laid: Float = s.role == "dropship" ? 0.12 : max(0.02, min(0.12, 2.5 / max(1, simd_length(d))))
            let onBearing = tr.aimYaw.map { t in abs(remainderf(t - tr.turretYaw, 2 * .pi)) < 0.01 } ?? false
            if (aimErr < laid || (onBearing && aimErr < 0.12)) && tr.reload <= 0 {
                if s.role == "dropship" { dropshipBurst(s, tr, t, pitch: elev, g) } else { fire(tr, pitch: elev, game: g) }
            }
        }
        // Spinal gun.
        let mw = s.toWorld(st.mainGunMuzzle)
        let md = s.dirToWorld(st.mainGunDir)
        let toT = t.point - mw
        let dist = simd_length(toT)
        let cosA = simd_dot(md, toT / max(1, dist))
        if s.role == "capfrigate" {
            // The Meridian's Tidebreaker: a long, telegraphed charge (whine, glowing barrel, MainGun.swift), then a slug
            // that craters whatever it hits. Once charging it commits and fires along the bow, toward the target if it
            // is still within the cone.
            if st.driverAlive && st.mainGunCD <= 0 && st.gunCharge < 0 && cosA > 0.9 && dist < 600 && dist > 40 { startMainGunCharge(s, st, g, byPlayer: false) }
        } else if (s.role != "crawler" || ShipManager.crawlerRail) && st.driverAlive && st.mainGunCD <= 0 && cosA > 0.9 && dist < 600 && dist > 20 {
            if st.mainCharge == 0 { g.sfx(.gun(12), 2, at: mw) }
            st.mainCharge += dt
            if Int(st.mainCharge * 20) % 2 == 0 { g.particles.smoke(at: mw, dark: false) }
            if st.mainCharge >= 1.6 {
                st.mainCharge = 0
                let frigate = s.isFlyingCapital
                st.mainGunCD = frigate ? 24 : 16
                var dir = simd_normalize(t.point + t.vel * (dist / ShipManager.railSpeed) - mw)
                if simd_dot(dir, md) < 0.85 { dir = simd_normalize(md + (dir - md) * 0.5) }
                railShot(s, from: mw, dir: dir, power: frigate ? 10 : 7, game: g)       // (P499: a rail gun)
            }
        } else if st.mainCharge > 0 && cosA <= 0.9 {
            st.mainCharge = 0
        }
        // Missile salvo.
        // P135: small missiles from a limited load (three salvos' worth), each a small blast.
        if st.missiles < 0 { st.missiles = st.pods.count * SmallMissiles.podSalvos }
        if st.driverAlive && st.missileCD <= 0 && !st.pods.isEmpty && st.missiles > 0 && boundsDistance(s, t.point) < 320 {
            st.missileCD = s.isFlyingCapital ? 7 : 10
            for (k, (p, d)) in st.pods.enumerated() where st.missiles > 0 {
                st.missiles -= 1
                SmallMissiles.launched += 1
                let at = s.toWorld(p)
                let dir = s.dirToWorld(d)
                let sh = Shell(pos: at + dir, vel: dir * 30 + s.vel, owner: s.id, power: SmallMissiles.podPower)
                sh.kind = 2
                sh.gravity = 0
                sh.life = 12
                sh.age = -Float(k) * 0.05
                sh.seekShip = t.ship; sh.seekMob = t.mob; sh.seekPlayer = t.player; sh.seekPoint = t.point
                shells.append(sh)
                if k % 2 == 0 { g.sfx(.fireworkLaunch, 0.9, at: at) }
            }
        }
    }

    // Troops: a crawler lowers its ramp and sends soldiers out when an enemy is within 70 blocks; a frigate lands
    // drop troops round a target on the ground within 220 (pods hit with a blast of smoke). At most six of its
    // soldiers alive at a time.
    private func deployTroops(_ s: Ship, _ st: CapitalState, _ dt: Float, _ g: Game) {
        st.troopCD -= dt
        st.troops.removeAll { t in t.health <= 0 || !g.mobs.mobs.contains(where: { $0 === t }) }
        guard st.troopCD <= 0, let t = st.target, st.troops.count < 6 else { return }
        // The Capital frigate keeps its security detail aboard (no drop troops).
        if s.role == "capfrigate" { return }
        let frigate = s.isFlyingCapital
        let reach: Float = frigate ? 220 : 70
        guard boundsDistance(s, t.point) < reach else { return }
        st.troopCD = frigate ? 35 : 25
        if frigate {
            // Drop troops ride down in a dropship launched from the hangar flank facing the target.
            st.dropships.removeAll { d in !list.contains { $0 === d } }
            if st.dropships.count < 2 && launchDropship(s, st, toward: t.point, g) { return }
        } else {
            // The crawler's troops are the squad it carries: two at a time leave their posts in the bay and walk out
            // round the engine room, through the rear door and down the ramp (it lowers for them); troops not yet
            // simulated appear at their posts first. Troops on the command deck stay aboard. When the bay is empty there
            // are no more.
            let ox = Float(s.grid.sx / 2)
            var sent = 0
            for (i, r) in st.crewRoles.enumerated() where r == .troop && sent < 2 && i < st.crew.count && st.crew[i].y < 15 {
                let post = st.crew[i]
                let m: Mob
                if let have = st.crewMobs[i] {
                    guard have.health > 0, have.deck === s, have.crewPost != nil, !st.troops.contains(where: { $0 === have }) else { continue }
                    m = have
                } else if !st.crewDone.contains(i) {
                    let at = s.toWorld(post + V3(0, 0.05, 0))
                    guard world.isLoaded(Int(floor(at.x)), Int(floor(at.z))) else { continue }
                    st.crewDone.insert(i)
                    m = Mob(i % 3 == 2 ? .soldierRecruit : .soldierTrooper, at: at)
                    m.faction = s.faction
                    m.persistent = true
                    m.deck = s
                    g.mobs.mobs.append(m)
                    st.crewMobs[i] = m
                } else { continue }
                // Out down the aisle: the centreline is kept clear from the magazine through the bulkhead door and between
                // the engine banks to the ramp (P510's rooms). (The lanes beside the engine room they used ran through the
                // troop benches and the supply chest: ridecheck's troops stepped onto the seats and inside them.)
                m.crewPost = nil
                m.crewRoute = [V3(ox + 0.5, 10, post.z), V3(ox + 0.5, 10, 72.5),
                               V3(ox + 0.5, 10, 74.2), V3(ox + 0.5 + Float(sent) - 0.5, 0.5, 83.5), V3(ox + 0.5 + Float(sent) * 2 - 1, 0, 88)]
                m.aggro = true
                st.troops.append(m)
                sent += 1
            }
            if sent > 0 && t.player && st.troops.count <= 2 { g.onToast?("The \(s.name) drops its ramp: troops!") }
            return
        }
        let ranks: [MobKind] = [.soldierTrooper, .soldierRecruit, .soldierTrooper, .soldierIronclad]
        var spots: [V3] = []
        if frigate {
            for k in 0..<3 {
                let a = Float(k) * 2.1 + Rand.float(in: 0..<1)
                let x = t.point.x + cosf(a) * 9, z = t.point.z + sinf(a) * 9
                let ix = Int(floor(x)), iz = Int(floor(z))
                guard world.isLoaded(ix, iz) else { continue }
                spots.append(V3(x, Float(world.topY(ix, iz) + 1), z))
            }
        } else {
            let foot = s.toWorld(st.ramp)
            let ix = Int(floor(foot.x)), iz = Int(floor(foot.z))
            if world.isLoaded(ix, iz) {
                for k in 0..<2 { spots.append(V3(foot.x + Float(k) * 1.5 - 0.75, Float(world.topY(ix, iz) + 1), foot.z)) }
            }
        }
        if spots.isEmpty { return }
        let first = st.troops.isEmpty
        for (i, p) in spots.enumerated() {
            let m = Mob(ranks[(i + st.troops.count) % ranks.count], at: p)
            m.faction = s.faction
            m.aggro = true
            if m.kind == .soldierIronclad { m.variant = Guns.arc }
            g.mobs.mobs.append(m)
            st.troops.append(m)
            if frigate {
                g.particles.explosion(at: p, power: 1.5)
                g.particles.smoke(at: p + V3(0, 1, 0))
                g.sfx(.explodeSmall, 0.9, at: p)
            }
        }
        if t.player && first { g.onToast?(frigate ? "Stormwarden drop troops are landing!" : "The Ironback Crawler drops its ramp: troops!") }
    }

    // Launches a dropship from the frigate's hangar opening on the side facing `p` (built in place: 600 blocks).
    private func launchDropship(_ s: Ship, _ st: CapitalState, toward p: V3, _ g: Game) -> Bool {
        let hb = Capital.dropship()
        let ids = (0..<2).map { _ in newId() }
        let ships = Capital.makeShips(hb, ids: ids, name: "Stormwarden Dropship", role: "dropship", faction: .stormwarden)
        let d = ships[0]
        let right = s.dirToWorld(V3(1, 0, 0))
        let side: Float = simd_dot(p - s.pos, right) >= 0 ? 1 : -1
        let gridX = Float(56) + side * 38
        let at = s.toWorld(V3(gridX, 32, 253))
        guard world.isLoaded(Int(floor(at.x)), Int(floor(at.z))) || simd_length(at - g.player.pos) < 400 else { return false }
        d.pos = at
        d.rot = s.rot
        d.prevPos = d.pos; d.prevRot = d.rot
        d.home = d.pos
        d.initialBlocks = d.blockCount
        d.updateBounds()
        for t in ships.dropFirst() { t.followParent(0); t.prevPos = t.pos; t.prevRot = t.rot }
        let ds = CapitalState()
        ds.mainGunCD = .greatestFiniteMagnitude                 // no spinal gun
        ds.missileCD = .greatestFiniteMagnitude
        ds.sight = 140
        ds.dropPoint = p
        ds.launchDir = right * side
        ds.troopsLeft = 4
        ds.ramp = V3(Float(hb.ox) + 0.5, 2, 18.5)
        ds.groundOffset = d.com.y - d.localMin.y
        ds.crew = hb.crew; ds.crewRoles = hb.crewRoles             // P334 (a)
        installCapital((ships, ds))
        st.dropships.append(d)
        g.sfx(.engineStart, 1, at: at)
        return true
    }

    // A dropship of `faction` flying in from `from` (no mothership) to land troops at `to`: the citadels' call for
    // reinforcements (CapitalBases.swift). Same flight as a frigate's dropship from the transit phase on.
    // The hull is built on a worker thread (about 20 ms on the main thread) and joins the world on a later frame.
    @discardableResult
    func callDropship(faction: Faction, from at: V3, to p: V3, game g: Game, sync: Bool = false, troops: Int = 4, rocketeer: Bool = false) -> Bool {
        if g.stormGrounds { return false }                          // O7: a storm grounds flyers (WeatherWar.swift)
        if g.foreignBase(p, for: faction) { return false }          // R23: never into a rival faction's base (Soldiers.swift)
        let ids = (0..<2).map { _ in newId() }
        let work = { () -> ([Ship], CapitalState) in
            let hb = Capital.dropship()
            let name = faction == .steelhold ? "Capital Dropship" : faction == .meridian ? "Meridian Launch" : faction.side == .greywall ? "Greywall Dropship" : "Stormwarden Dropship"
            let ships = Capital.makeShips(hb, ids: ids, name: name, role: "dropship", faction: faction)
            let d = ships[0]
            d.pos = at
            let yaw = atan2f(-(p.x - at.x), -(p.z - at.z))
            d.rot = simd_quatf(angle: yaw, axis: V3(0, 1, 0))
            d.prevPos = d.pos; d.prevRot = d.rot
            d.home = d.pos
            d.initialBlocks = d.blockCount
            d.updateBounds()
            for t in ships.dropFirst() { t.followParent(0); t.prevPos = t.pos; t.prevRot = t.rot }
            let ds = CapitalState()
            ds.mainGunCD = .greatestFiniteMagnitude
            ds.missileCD = .greatestFiniteMagnitude
            ds.sight = 140
            ds.dropPoint = p
            ds.launchDir = simd_normalize(V3(p.x - at.x, 0, p.z - at.z) + V3(1e-4, 0, 0))
            ds.troopsLeft = troops
            ds.rocketeer = rocketeer
            ds.phase = 1                                              // already airborne: straight to the transit
            ds.ramp = V3(Float(hb.ox) + 0.5, 2, 18.5)
            ds.groundOffset = d.com.y - d.localMin.y
            ds.crew = hb.crew; ds.crewRoles = hb.crewRoles         // P334 (a)
            return (ships, ds)
        }
        g.sfx(.engineStart, 1, at: at)
        if sync { installCapital(work()); return true }
        DispatchQueue.global(qos: .userInitiated).async { [me = weakLink] in    // (item 8: by link: WeakLink.swift)
            let built = work()
            guard let self = me.wrappedValue else { return }
            self.capitalLock.lock()
            self.capitalReady.append(built)
            self.capitalLock.unlock()
        }
        return true
    }

    // Dropship flight: out of the hangar, across to the drop point, down to a hover, the ramp troops out one by one,
    // then it circles the fight with its autocannon and finally climbs away. Shot to pieces it falls and blows up.
    private func dropshipTick(_ s: Ship, _ st: CapitalState, _ dt: Float, _ g: Game) {
        st.phaseT += dt
        // P334 (a): its crew aboard (spawnCrew); with the pilot dead nobody flies it (pilotless, below).
        spawnCrew(s, st, boundsDistance(s, g.player.pos), g)
        // T7: the squad keeps round its officer and takes up the fight the officer has seen.
        if let lead = st.troops.first(where: { $0.kind == .soldierOfficer && $0.health > 0 }) {
            for (i, m) in st.troops.enumerated() where m !== lead && m.health > 0 {
                let a = Float(i) * 2.1
                m.home = lead.pos + V3(cosf(a) * 2.5, 0, sinf(a) * 2.5)
                if lead.aggro && !m.aggro, let seen = lead.brain?.lastSeen { m.aggro = true; m.soldierBrain.lastSeen = seen }
                // P460 (Oct 25 16:38, a Capital Dropship's troops round him: "These guys didn't do anything"): they come
                // off the ramp already in the fight, so the line above never passed the officer's sighting on, and a
                // trooper that hadn't seen him itself (behind the ramp, a rise, past its rank's sight) strolled round its
                // spot. While the officer has him in sight the squad knows where he is and closes in.
                if lead.aggro && lead.soldierBrain.seenAgo < 1 {
                    m.lockTime = max(m.lockTime, 2)
                    if m.soldierBrain.seenAgo > 2 { m.soldierBrain.lastSeen = g.player.pos; m.soldierBrain.seenAgo = 2 }
                }
            }
        }
        let keel = st.groundOffset
        let gx = Int(floor(s.pos.x)), gz = Int(floor(s.pos.z))
        // Over loaded ground, the real top block (tree crowns too: hovering at terrain height put it in the canopy).
        let top: Int = world.isLoaded(gx, gz) ? world.topY(gx, gz) : world.gen.column(gx, gz).height
        // P483 (Oct 28 17:37, "the dropship just went, drove through the frigate, which is not okay"): another craft's
        // hull under it or a little ahead (a crash-landed frigate, a crawler, a parked hull) is ground to it as well.
        var hullTop: Float = -1
        let reachA = V3(abs(s.vel.x), 0, abs(s.vel.z)) * 1.5 + V3(3, 0, 3)
        let mn = s.worldMin - reachA, mx = s.worldMax + reachA
        let land = Float(max(top, SEA))
        for o in list where o !== s && o.parent == nil && o.blockCount > 40 && o.worldMin.y < land + 10 {   // (one at rest)
            if o.worldMax.x < mn.x || o.worldMin.x > mx.x || o.worldMax.z < mn.z || o.worldMin.z > mx.z { continue }
            hullTop = max(hullTop, o.worldMax.y + 1)
        }
        let ground = max(land, hullTop)
        // P65 (Oct 11 evening playtest: dropships flew through Capital towers): in flight it clears the highest block
        // under its whole hull and a hull length ahead, not just the column at its centre.
        var clear = ground
        if st.phase == 1 || st.phase >= 4 {
            let lo = s.localMin, hi = s.localMax
            // (P504: three seconds ahead, time to slow and climb; it took a second and a half to turn its speed over)
            var ahead = V3(s.vel.x, 0, s.vel.z) * 3
            // (P505: and never less than 16 blocks the way it means to go. Slowed to a hover at a tower's foot, it looked
            // only a block or two ahead, lost the tower, sped on and clipped its face: 12 ticks in the dropflight tower.)
            var way = V2(s.vel.x, s.vel.z)
            if st.phase == 1 { way = V2(st.dropPoint.x - s.pos.x, st.dropPoint.z - s.pos.z) }
            let wl = simd_length(way)
            if wl > 0.01 { let u = way / wl, n = max(16, simd_length(V2(ahead.x, ahead.z))); ahead = V3(u.x, 0, u.y) * n }
            for c in [V3(lo.x, 0, lo.z), V3(hi.x, 0, lo.z), V3(lo.x, 0, hi.z), V3(hi.x, 0, hi.z), (lo + hi) * 0.5] {
                for a in [V3(0, 0, 0), ahead * 0.25, ahead * 0.5, ahead * 0.75, ahead] {        // (P499: and on the way, at a chase's speed)
                    let w = s.toWorld(c) + a
                    let x = Int(floor(w.x)), z = Int(floor(w.z))
                    if world.isLoaded(x, z) { clear = max(clear, Float(world.topY(x, z))) }
                }
            }
        }
        let keelY = s.pos.y - keel
        if !s.wrecked && s.initialBlocks > 0 && s.blockCount * 10 < s.initialBlocks * 6 {
            s.wrecked = true
            g.sfx(.explode, 1, at: s.pos)
            for t in turrets(of: s) { t.aimAt = nil }
        }
        if s.wrecked {
            s.vel.y = max(-30, s.vel.y - 12 * dt)
            s.angVel = V3(0.4, 1.2, 0.2)
            if Int(st.phaseT * 6) % 2 == 0 { g.particles.smoke(at: s.pos) }
            if keelY <= ground + 1 || st.phaseT > 30 {
                Explosion.explode(at: s.pos, power: 4, game: g)          // (P510: a crash breaks what it lands on, a citadel too)
                remove(s)
                capState.removeValue(forKey: s.id)
            }
            return
        }
        if !st.driverAlive {
            // P334 (a): the pilot is dead: the craft yaws off its heading and sinks under its idling engines until it
            // sits on the ground, unflown, its gun silent. Then it can be taken from the helm (canCommandeer).
            for t in turrets(of: s) { t.aimAt = nil }
            let sink: Float = keelY > ground + 0.6 ? max(-7, -(keelY - ground) * 0.5 - 0.6) : 0
            s.vel += (V3(0, sink, 0) - s.vel) * min(1, dt * 0.8)
            s.angVel = V3(0, s.angVel.y + ((keelY > ground + 1 ? 0.35 : 0) - s.angVel.y) * min(1, dt), 0)
            levelUp(s, dt)
            return
        }
        st.retarget -= dt
        if st.retarget <= 0 || (st.target.map { !targetValid($0, g) } ?? false) {
            st.retarget = 1
            st.target = pickTarget(s, st, g)
        } else if var t = st.target {
            refresh(&t, g)
            st.target = t
        }
        var want = V3(0, 0, 0)                                  // wanted velocity
        let drop2 = V2(st.dropPoint.x, st.dropPoint.z), here = V2(s.pos.x, s.pos.z)
        let toDrop = drop2 - here
        let dd = simd_length(toDrop)
        switch st.phase {
        case 0:
            want = st.launchDir * 14 + V3(0, -1, 0)
            if st.phaseT > 3 { st.phase = 1; st.phaseT = 0 }
        case 1:
            let dir = toDrop / max(1, dd)
            let cruise = max(ground + 22, clear + 6) + keel
            want = V3(dir.x, 0, dir.y) * min(24, max(6, dd * 0.6)) + V3(0, max(-6, min(6, (cruise - s.pos.y) * 0.8)), 0)
            if dd < 10 || st.phaseT > 60 { st.phase = 2; st.phaseT = 0 }
        case 2:
            let dir = toDrop / max(1, dd)
            want = V3(dir.x, 0, dir.y) * min(6, dd) + V3(0, max(-5, min(3, (ground + 4 + keel - s.pos.y) * 0.9)), 0)
            if keelY < ground + 5.5 || st.phaseT > 15 { st.phase = 3; st.phaseT = 0 }
        case 3:
            want = V3(0, (ground + 4 + keel - s.pos.y) * 0.9, 0)
            if st.phaseT > 0.7 && st.troopsLeft > 0 {
                st.phaseT = 0
                let foot = s.toWorld(st.ramp)
                let ix = Int(floor(foot.x)), iz = Int(floor(foot.z))
                if world.isLoaded(ix, iz) {
                    // T7: an officer first down the ramp, then a trooper, a Spec Ops marksman and a recruit.
                    let ranks: [MobKind] = s.faction == Faction.steelhold.rawValue ? [.soldierOfficer, .soldierRecruit, .soldierMarksman, .soldierTrooper]
                        : [.soldierTrooper, .soldierRecruit, .soldierTrooper, .soldierIronclad]
                    let m = Mob(ranks[st.troopsLeft % ranks.count], at: V3(foot.x, Float(world.topY(ix, iz) + 1), foot.z))
                    m.faction = s.faction
                    m.aggro = true
                    if m.kind == .soldierIronclad { m.variant = Guns.arc }
                    if m.kind == .soldierMarksman && s.faction == Faction.steelhold.rawValue { m.setTroop(.specOps, rearm: true) }
                    g.mobs.mobs.append(m)
                    st.troops.append(m)
                    if simd_length(m.pos - g.player.pos) < 120 && st.troopsLeft == 4 { g.onToast?("A \(s.name) is landing troops!") }
                }
                st.troopsLeft -= 1
            }
            if st.troopsLeft <= 0 && st.phaseT > 1 { st.phase = 4; st.phaseT = 0 }
        case 4 where (st.target.map { simd_length(V2($0.vel.x, $0.vel.z)) > 8 } ?? false):
            // P499 (Oct 30 20:35, flying the Meridian past a citadel: "the drop ship should chase, chase my ship and just
            // start firing at me relentlessly"): a target on the move (a hull, a rider) is chased: it holds a slot 30
            // blocks behind and 25 off its quarter, matching its speed up to 55 m/s, 10 over it and clear of what stands
            // below, its guns on it the while; it turns for home 15 s after it loses it.
            let t = st.target!
            let tv = V2(t.vel.x, t.vel.z), sp = simd_length(tv)
            let back = tv / sp, side = V2(-back.y, back.x)
            let slot = V2(t.point.x, t.point.z) - back * 30 + side * 25
            var hv = tv + (slot - here) * 0.8
            if simd_length(hv) > Capital.dropChase { hv = simd_normalize(hv) * Capital.dropChase }
            let alt = max(t.point.y + 10, max(ground + 16, clear + 6) + keel)
            want = V3(hv.x, max(-10, min(10, (alt - s.pos.y) * 0.8)), hv.y)
            st.phaseT = min(st.phaseT, 30)
        case 4:
            let c = st.target.map { V2($0.point.x, $0.point.z) } ?? drop2
            let to = c - here
            let d = max(1, simd_length(to))
            let tangent = V2(-to.y, to.x) / d
            let h = simd_normalize(tangent + to / d * ((d - 30) / 20))
            want = V3(h.x, 0, h.y) * 10 + V3(0, max(-4, min(4, (max(ground + 16, clear + 6) + keel - s.pos.y) * 0.6)), 0)
            if st.phaseT > 45 { st.phase = 5; st.phaseT = 0 }
        default:
            let away = simd_normalize(here - V2(g.player.pos.x, g.player.pos.z) + V2(1e-3, 0))
            // (P499: "Drop ship just flew through one of its own buildings": heading home it climbs over what stands
            // under and ahead of it, as on the way in.)
            want = V3(away.x, 0, away.y) * 20 + V3(0, max(8, min(14, (clear + 8 + keel - s.pos.y) * 0.8)), 0)
            if st.phaseT > 20 || s.pos.y > Float(CH - 12) { remove(s); capState.removeValue(forKey: s.id); return }
        }
        // P504 (Nov 1 07:50:43, at a Capital city: "the drop ship is still morphing through buildings when it flies. That
        // shouldn't be possible"): the climb over what stands ahead was capped at 4-6 blocks a second while it kept its
        // speed, so a tower taller than it could climb in a second and a half's run went through the hull. Short of the
        // height that clears it, it slows (to a hover 8 blocks short) and climbs as fast as it must.
        if st.phase == 1 || st.phase >= 4 {
            let short = clear + 2 + keel - s.pos.y
            if short > 0 {
                let f = max(0, 1 - short / 8)
                want.x *= f; want.z *= f
                want.y = max(want.y, min(16, 3 + short * 1.5))
            }
        }
        s.vel += (want - s.vel) * min(1, dt * 1.5)
        // Face the way it flies (hovering: toward the target).
        var face = V2(s.vel.x, s.vel.z)
        if simd_length(face) < 2, let t = st.target { face = V2(t.point.x - s.pos.x, t.point.z - s.pos.z) }
        var yawRate: Float = 0
        if simd_length(face) > 0.5 {
            let wantYaw = atan2f(-face.x, -face.y)
            var dy = wantYaw - s.yaw
            while dy > .pi { dy -= 2 * .pi }
            while dy < -Float.pi { dy += 2 * Float.pi }
            yawRate = max(-1.2, min(1.2, dy * 1.5))
        }
        // P334 (7): flown by its pilot: it banks into its turns and dips the nose as it gathers speed.
        let yawNow = s.angVel.y + (yawRate - s.angVel.y) * min(1, dt * 3)
        let fwh = s.dirToWorld(V3(0, 0, -1))
        let fh2 = simd_normalize(V3(fwh.x, 0, fwh.z) + V3(1e-5, 0, 0))
        let along = simd_dot(want - s.vel, fh2) + simd_dot(s.vel, fh2) * 0.15
        st.helmPitch += (max(-1, min(1, -along / 12)) * Capital.vtolPitch - st.helmPitch) * min(1, dt * 2)
        st.helmBank += (max(-1, min(1, yawNow * 0.9)) * Capital.vtolBank - st.helmBank) * min(1, dt * 2)
        steerAttitude(s, pitch: st.helmPitch, bank: st.helmBank, yawRate: yawNow)
        if st.phase >= 1 { capitalGuns(s, st, dt, g) }
    }

    // A crippled capital ship: a frigate comes down out of the sky with fires breaking out and crash-lands; a crawler
    // grinds to a halt, burning. Neither vanishes: the wreck stays where it came to rest, its crew aboard.
    // P461 (Oct 25 17:02, a crash-landed Stormwarden Frigate in the jungle: "Why are trees spawning inside the ship?"): what
    // stood where the hull came down (trees, plants, anything not ground and not a chest) is gone: every cell in its hull
    // and between its keel and its deckhead, column by column.
    func clearInside(_ s: Ship, _ g: Game) {
        let gr = s.grid, w = g.world
        var lowY = [Int](repeating: Int.max, count: gr.sx * gr.sz), highY = [Int](repeating: -1, count: gr.sx * gr.sz)
        for z in 0..<gr.sz { for x in 0..<gr.sx { for y in 0..<gr.sy where gr.get(x, y, z) != AIR {
            let c = x + z * gr.sx
            lowY[c] = min(lowY[c], y); highY[c] = max(highY[c], y)
        } } }
        let a = s.worldMin, b = s.worldMax
        var gone = 0
        for y in stride(from: max(1, Int(floor(a.y))), through: min(CH - 2, Int(floor(b.y))), by: 1) {
            for z in Int(floor(a.z))...Int(floor(b.z)) { for x in Int(floor(a.x))...Int(floor(b.x)) {
                let blk = w.block(x, y, z)
                guard blk != AIR, !Blocks.isLiquid(blk), !w.groundAt(x, y, z), w.blockEntities[IVec3(x, y, z)] == nil else { continue }
                let l = s.toLocal(V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5))
                let lx = Int(floor(l.x)), ly = Int(floor(l.y)), lz = Int(floor(l.z))
                guard lx >= 0, lz >= 0, lx < gr.sx, lz < gr.sz else { continue }
                let c = lx + lz * gr.sx
                guard ly >= lowY[c] && ly <= highY[c] else { continue }
                _ = w.setBlockAsync(x, y, z, AIR)
                gone += 1
            } }
        }
        ShipManager.insideCleared += gone
    }
    static var insideCleared = 0                // (checks)

    // P461 (Oct 25 16:41-16:42, "This thing should be able to crush trees on landing", ramming a tent: "it didn't crash.
    // Just going through shit... This thing should either be getting damaged or be damaging other things"): a flown
    // craft tears through what its hull runs into that isn't ground or stone: leaves, trunks, plants, wool (tents),
    // planking, glass and the like break as the hull meets them (a few spill their drops), with the crunch of each.
    // Ground, stone, metal and anything with a block entity are left alone.
    // Ramming (16:42, "This thing should either be getting damaged or be damaging other things. From the new physics"):
    // ground, stone and metal ahead of it stop the craft (it flew through hillsides and walls): it is put back out of
    // them and bounces off (a rise only as high as its keel row it rides up over), and a hit over 10 m/s tears hull
    // plates off where it struck (more the faster: 30 m/s takes six), with a crash. Anyone in its way at speed is hit by the hull.
    static var crushed = 0, rams = 0, ramTorn = 0, smashed = 0   // (checks)
    static var crushSeconds = 0.0012              // (store review: a crush pass's work a frame, crawlerCrush)
    func crush(_ s: Ship, _ st: CapitalState, _ dt: Float, _ g: Game) {
        st.crushT -= dt
        st.ramT -= dt
        guard st.crushT <= 0 else { return }
        let speed = simd_length(s.vel)
        let step = st.crushT + st.crushEvery        // (seconds since the last sweep)
        st.crushEvery = speed > 10 ? 0.04 : 0.12    // (fast: often enough that the nose never gets through a wall)
        st.crushT = st.crushEvery
        guard speed > 0.5 || abs(s.angVel.y) > 0.2 else { return }
        let gr = s.grid, w = g.world
        let a = s.worldMin - V3(0.5, 0.5, 0.5), b = s.worldMax + V3(0.5, 0.5, 0.5)
        var n = 0, smashed = 0, smAt = V3.zero
        let smash = speed > 12
        var hard: [IVec3] = [], at = V3.zero, lift: Float = 0
        for y in stride(from: max(1, Int(floor(a.y))), through: min(CH - 2, Int(floor(b.y))), by: 1) {
            for z in Int(floor(a.z))...Int(floor(b.z)) { for x in Int(floor(a.x))...Int(floor(b.x)) {
                let blk = w.block(x, y, z)
                guard blk != AIR, Blocks.collide[Int(blk)] || Capital.crushable(blk) else { continue }
                let wc = V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5)
                let l = s.toLocal(wc)
                let cell = IVec3(Int(floor(l.x)), Int(floor(l.y)), Int(floor(l.z)))
                guard Blocks.collide[Int(gr.get(cell.x, cell.y, cell.z))] else { continue }
                if Capital.crushable(blk) && !w.groundAt(x, y, z) && w.blockEntities[IVec3(x, y, z)] == nil {
                    if n < 48 { g.breakBlock(IVec3(x, y, z), blk, drop: n % 4 == 0); n += 1 }
                } else if smash && smashed < 160 && !ShipParts.natural[Int(blk)] && !w.groundAt(x, y, z)
                            && Blocks.hardness[Int(blk)] >= 0 && Blocks.hardness[Int(blk)] < 50 && w.blockEntities[IVec3(x, y, z)] == nil
                            && simd_dot(wc - s.pos, s.vel) > 0 {
                    // P507 (Nov 1 12:26:42, "the frigate should have had the physics to literally crash through a
                    // building"): at speed a built wall ahead gives way to the hull (brick, stone work, concrete, plate
                    // under obsidian's hardness) and it ploughs on, slowed and torn; the ground and rock still stop it.
                    g.breakBlock(IVec3(x, y, z), blk, drop: smashed % 8 == 0)
                    smashed += 1; smAt += wc
                } else if Blocks.collide[Int(blk)] {
                    // Under the keel row: ground it rides up over (a rise in the ground isn't a ram); ahead: a ram.
                    if wc.y < s.worldMin.y + 1.2 { lift = max(lift, Float(y) + 1 - s.worldMin.y) }
                    else if hard.count < 64 && simd_dot(wc - s.pos, s.vel) > 0 { hard.append(cell); at += wc }
                }
            } }
        }
        ShipManager.crushed += n
        if smashed > 0 {
            // Through it: the wall takes some of the way off her, the bow plates take the blow (as a ram, lighter).
            ShipManager.smashed += smashed
            let spot = smAt / Float(smashed)
            s.vel *= max(0.6, 1 - Float(smashed) * 0.004)
            g.particles.explosion(at: spot, power: min(3, Float(smashed) / 20 + 1))
            if st.ramT <= 0 { st.ramT = 0.4; g.sfx(.shipCollideHard, min(1.4, 0.7 + Float(smashed) / 60), at: spot) }
        }
        if lift > 0 && hard.isEmpty {                // (a wall's foot is part of the wall: rammed, not climbed)
            s.pos.y += min(lift, 1)
            s.vel.y = max(s.vel.y, 0)
            s.updateBounds()
        }
        if !hard.isEmpty && speed > 1 {
            at /= Float(hard.count)
            // Back out the way it came (at most this sweep's travel) and bounce off.
            let back = min(simd_length(s.vel * step), 3) + 0.2
            let dir = s.vel / speed
            s.pos -= dir * back
            s.updateBounds()
            s.vel = -dir * min(speed * 0.25, 4)
            if speed > 10 && st.ramT <= 0 {
                st.ramT = 0.6
                ShipManager.rams += 1
                let k = min(hard.count, min(12, Int((speed - 10) / 3.5) + 1))
                var torn = Set<IVec3>()
                for c in hard.sorted(by: { simd_length(s.toWorld(V3(Float($0.x), Float($0.y), Float($0.z)) + 0.5) - at) < simd_length(s.toWorld(V3(Float($1.x), Float($1.y), Float($1.z)) + 0.5) - at) }) where torn.count < k {
                    if c != s.helm, let t = ShipManager.meltTime(gr.get(c.x, c.y, c.z)), t < 60 { torn.insert(c) }      // (not the helm or the hardest plate)
                }
                ShipManager.ramTorn += torn.count
                g.particles.explosion(at: at, power: min(3, speed / 12))
                g.sfx(.shipCollideHard, min(1.4, 0.6 + speed / 40), at: at)
                if !torn.isEmpty { removeCells(s, torn, chipped: [], center: at, power: 0, game: nil) }
            } else if st.ramT <= 0 {
                st.ramT = 0.3
                g.sfx(.shipCollide, 0.5, at: at)
            }
        }
        // Anyone in its way at speed: struck by the hull and thrown aside (not those riding in it, moving with it).
        if speed > 8 {
            for m in g.mobs.mobs where m.health > 0 && simd_length(m.vel - s.vel) > 6 && m.pos.x > a.x && m.pos.x < b.x && m.pos.z > a.z && m.pos.z < b.z && m.pos.y > a.y - 2 && m.pos.y < b.y {
                let l = s.toLocal(m.pos + V3(0, m.height * 0.5, 0))
                let near = (-1...1).contains { dx in (-1...1).contains { dz in Blocks.collide[Int(gr.get(Int(floor(l.x)) + dx, Int(floor(l.y)), Int(floor(l.z)) + dz))] } }
                if near { m.hit(from: m.pos - s.vel, damage: Int(4 + speed / 3), knockback: 2.5) }
            }
        }
    }

    // The blue glow on a craft's light panels in overdrive (one sprite each a frame).
    func overdriveGlow(_ s: Ship, _ st: CapitalState, _ g: Game) {
        if st.lightCells == nil {
            let light = Blocks.has("light_panel") ? Blocks.id("light_panel") : AIR
            var cells: [V3] = []
            let gr = s.grid
            for y in 0..<gr.sy { for z in 0..<gr.sz { for x in 0..<gr.sx where light != AIR && gr.get(x, y, z) == light {
                cells.append(V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5))
            } } }
            st.lightCells = cells
        }
        let layer = FrigateBoarding.puffLayer
        for c in st.lightCells ?? [] where Blocks.collide[Int(s.grid.get(Int(c.x), Int(c.y), Int(c.z)))] {
            g.particles.add(Particle(pos: s.toWorld(c), vel: s.vel, life: 0.05, maxLife: 0.05, layer: layer, uv0: V2(0, 0), uvSize: 1,
                                     size: 1.8, gravity: 0, color: V3(0.35, 0.65, 2.2), collide: false, glow: true))
        }
    }

    private func founder(_ s: Ship, _ st: CapitalState, _ dt: Float, _ g: Game) {
        if st.settled { s.vel = .zero; s.angVel = .zero; return }
        st.wreckFx -= dt
        let lo = s.localMin, hi = s.localMax
        // (A hull shot down to nothing has empty bounds, min above max: no range to pick from.)
        if st.wreckFx <= 0 && lo.x <= hi.x && lo.y <= hi.y && lo.z <= hi.z {
            st.wreckFx = 0.35
            let p = V3(Rand.float(in: lo.x...hi.x), Rand.float(in: lo.y...hi.y), Rand.float(in: lo.z...hi.z))
            let w = s.toWorld(p)
            g.particles.explosion(at: w, power: 3)
            g.particles.smoke(at: w)
            if simd_length(w - g.player.pos) < 160 { g.sfx(.explode, 0.7, at: w) }
        }
        let fw = s.dirToWorld(V3(0, 0, -1))
        let fh = simd_normalize(V2(fw.x, fw.z) + V2(1e-5, 0))
        if s.isFlyingCapital {
            crashLand(s, st, dt, g)
            return
        }
        // Crawler: it keeps following the ground while it grinds to a stop (about 1.4 b/s lost per second), sagging
        // toward the wheels it lost, sparks and smoke at the wheels.
        if st.grind < 0 {
            st.grind = max(0, simd_dot(s.vel, fw))
            var sag = V2(0, 0)
            for w in st.wheels where w.lost && w.part < s.wheelParts.count {
                let c = s.wheelParts[w.part].center
                sag.x += c.z < s.com.z ? -0.025 : 0.025
                sag.y += c.x > s.com.x ? -0.03 : 0.03
            }
            st.sag = simd_clamp(sag, V2(-0.08, -0.1), V2(0.08, 0.1))
        }
        let moving = st.grind > 0.05
        st.grind = max(0, st.grind - dt * 1.4)
        crawlerMotion(s, st, dt, want: fh, speed: st.grind, turnRate: 0)
        if moving && !s.wheelParts.isEmpty && Rand.float(in: 0..<1) < dt * 8 {
            let w = s.wheelParts[min(s.wheelParts.count - 1, Int(Rand.float(in: 0..<Float(s.wheelParts.count))))]
            let at = s.toWorld(V3(w.center.x, w.center.y - w.radius + 0.5, w.center.z))
            g.particles.smoke(at: at, dark: true)
            if Rand.float(in: 0..<1) < 0.3 { g.sfx(.shipCollideHard, 0.5, at: at) }
        }
        if !moving && simd_length(s.vel) < 0.06 && simd_length(s.angVel) < 0.01 { st.settled = true }
    }

    // A frigate with its drive engines out comes down: it keeps a little way on and sinks faster and faster, then its
    // crew flare it over the ground (the lift strips still bear some of her weight) and she settles on the terrain,
    // pitched to it. Riders are carried down with the deck and feel the touchdown: damage only for a hard one.
    private func crashLand(_ s: Ship, _ st: CapitalState, _ dt: Float, _ g: Game) {
        let fw = s.dirToWorld(V3(0, 0, -1))
        let fh = simd_normalize(V2(fw.x, fw.z) + V2(1e-5, 0))
        let side = V2(-fh.y, fh.x)
        let keel = s.com.y - s.localMin.y
        let half = (s.localMax.z - s.localMin.z) * 0.42
        let beam = (s.localMax.x - s.localMin.x) * 0.35
        // Highest ground under the bow, the middle and the stern (sampled twice a second).
        st.groundTimer -= dt
        if st.groundTimer <= 0 || st.ground == nil {
            st.groundTimer = 0.5
            let c2 = V2(s.pos.x, s.pos.z)
            func top(_ along: Float) -> Float {
                var t: Float = Float(SEA)
                for j in [Float(-1), 0, 1] {
                    let p = c2 + fh * along + side * (j * beam)
                    t = max(t, groundTop(Int(floor(p.x)), Int(floor(p.y))) + 1)
                }
                return t
            }
            let bow = top(half), mid = top(0), stern = top(-half)
            st.ground = V3(max(bow, mid, stern), bow, stern)
        }
        let gr = st.ground ?? V3(0, 0, 0)
        let keelY = s.pos.y - keel
        let clear = keelY - gr.x
        if st.grind < 0 { st.grind = max(1, simd_dot(s.vel, fw)) }
        st.grind = max(1, st.grind - dt * 0.4)
        let wantSink: Float = clear > 24 ? 7 : 2.6 + clear * 0.18
        st.sinkSpeed += (wantSink - st.sinkSpeed) * min(1, dt * 0.7)
        // Level, a touch nose-down in the fall; over the ground, pitched to it (a few degrees at most).
        let pitch: Float = clear < 30 ? max(-0.1, min(0.1, atan2f(gr.y - gr.z, 2 * half))) : -0.02
        let wantRot = Quat(angle: s.yaw, axis: V3(0, 1, 0)) * Quat(angle: pitch, axis: V3(1, 0, 0))
        var e = wantRot * s.rot.inverse
        if e.real < 0 { e = Quat(vector: -e.vector) }
        let ang = 2 * acosf(max(-1, min(1, e.real)))
        let axis = ang > 1e-4 ? simd_normalize(e.imag) : V3(0, 1, 0)
        let av: V3 = axis * min(0.1, ang * 0.8)
        s.angVel += (av - s.angVel) * min(1, dt * 2)
        s.vel = V3(fh.x, 0, fh.y) * st.grind + V3(0, -st.sinkSpeed, 0)
        if clear > 0.05 { return }
        // Touchdown.
        st.settled = true
        st.impact = st.sinkSpeed
        s.pos.y += -clear
        s.vel = .zero
        s.angVel = .zero
        s.updateBounds()
        clearInside(s, g)
        let lo = s.localMin, hi = s.localMax
        Explosion.sparePlayer = aboard?.root === s || pilot === s
        for k in 0..<3 {
            let p = V3((lo.x + hi.x) * 0.5, lo.y + 0.5, lo.z + (hi.z - lo.z) * (0.2 + 0.3 * Float(k)))
            Explosion.explode(at: s.toWorld(p) - V3(0, 1, 0), power: 3, game: g)
        }
        Explosion.sparePlayer = false
        g.sfx(.shipCollideHard, 2, at: s.pos)
        // The jolt: the crew on deck take damage for a hard touchdown (over 3.5 b/s), none for a flared one; the
        // player rides it out (P472).
        let hurt = Int(max(0, (st.impact - 3.5) * 2).rounded())
        if hurt > 0 {
            for m in g.mobs.mobs where m.deck === s && m.health > 0 { m.health -= hurt; m.hurt = 0.3 }
        }
        if simd_length(s.pos - g.player.pos) < 400 { g.onToast?("The \(s.name) has crash-landed") }
    }
}

// MARK: Breakaway pieces (block-based damage on capital hulls)

enum DetachLooseTiming {
    static let oldSearch = ProcessInfo.processInfo.environment["BS_DETACHOLD"] == "1"     // (--detachcheck: the search before Nov 4)
    // detachLoose's cell table (the main thread's blasts only), grown to the largest hull blasted; `base` moves past
    // each blast's searches, so the table is never cleared (but when it would run past the top).
    private static var buf: UnsafeMutablePointer<UInt32>? = nil
    private static var cap = 0
    static var base: UInt32 = 1
    static func table(_ n: Int) -> UnsafeMutablePointer<UInt32> {
        if n > cap || buf == nil {
            buf?.deallocate()
            cap = max(n, 1 << 16)
            buf = UnsafeMutablePointer<UInt32>.allocate(capacity: cap)
            buf!.initialize(repeating: 0, count: cap)
            base = 1
        } else if base > UInt32.max - 1024 {
            buf!.update(repeating: 0, count: cap)
            base = 1
        }
        return buf!
    }
}

extension ShipManager {
    // After a blast on a capital hull: flood out from the cells next to the hole, each search capped at `limit`
    // cells. A search that runs dry before the cap found a piece no longer joined to the hull: it breaks away as a
    // ship of its own (ordinary physics: it falls, tumbles, and can be walked on). A search that reaches the cap is
    // still part of the main hull (the full-grid flood fill that small ships use would scan 5 million cells per hit).
    func detachLoose(_ s: Ship, around holes: [IVec3], limit: Int = 4000) {
        let g = s.grid
        var seen = Set<IVec3>()
        var pieces: [[IVec3]] = []
        let dirs = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 1, 0), IVec3(0, -1, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)]
        var starts: [IVec3] = []
        for h in holes { for d in dirs {
            let c = h + d
            if g.inside(c.x, c.y, c.z) && g.get(c.x, c.y, c.z) != AIR && !seen.contains(c) { starts.append(c) }
        } }
        if starts.count > 400 { starts = Array(starts.prefix(400)) }
        // (P461: a small hull, the dropship's 295 blocks, is itself under the limit: one block melted or shot out of
        // it cut the whole craft loose as a wreck. A piece holding half the hull or more is the hull and stays.)
        let limit = min(limit, max(1, s.blockCount / 2))
        // (Nov 4, the worst-case soak: one shell's blast on a crawler took 11 of its 12 ms here. A search from the far
        // side of the hole never met the cells an earlier search had already found joined to the hull, and walked its
        // own 4,000 again, up to 400 times a blast. Every cell already seen is the hull's (a loose piece's search runs
        // dry, so no later search can reach its cells): meeting one, the search is joined to the hull and stops.)
        if DetachLooseTiming.oldSearch {
            for st in starts where !seen.contains(st) {
                var comp: [IVec3] = [st]
                var local = Set<IVec3>([st])
                var head = 0
                var open = true
                while head < comp.count {
                    let c = comp[head]; head += 1
                    for d in dirs {
                        let n = c + d
                        if local.contains(n) || !g.inside(n.x, n.y, n.z) { continue }
                        let b = g.get(n.x, n.y, n.z)
                        if b == AIR { continue }
                        local.insert(n)
                        comp.append(n)
                    }
                    if comp.count > limit { open = false; break }
                }
                seen.formUnion(local)
                if open && comp.count >= 1 { pieces.append(comp) }
            }
        } else {
            // (one table of cell index -> the search that found it, in place of a set per search and their union. Nov 4,
            // the next profile: as a dictionary it was still 4.6 million instructions a blast on the crawler in game,
            // the first search's 4,000 cells hashed six times each; now a flat buffer over the grid, reused from blast
            // to blast: a cell holds base + its search, anything under base is unseen.)
            let cells = g.sx * g.sy * g.sz
            let owner = DetachLooseTiming.table(cells)
            let base = DetachLooseTiming.base
            var k: UInt32 = 0
            defer { DetachLooseTiming.base = base + k + 1 }
            for st in starts {
                let si = g.index(st.x, st.y, st.z)
                if owner[si] >= base { continue }
                k += 1
                owner[si] = base + k
                var comp: [IVec3] = [st]
                var head = 0
                var open = true
                search: while head < comp.count {
                    let c = comp[head]; head += 1
                    for d in dirs {
                        let n = c + d
                        guard g.inside(n.x, n.y, n.z) else { continue }
                        let ni = g.index(n.x, n.y, n.z)
                        let o = owner[ni]
                        if o >= base {
                            if o == base + k { continue }
                            open = false; break search             // an earlier search's cell: joined to the hull
                        }
                        if g.get(n.x, n.y, n.z) == AIR { continue }
                        owner[ni] = base + k
                        comp.append(n)
                    }
                    if comp.count > limit { open = false; break }
                }
                if open { pieces.append(comp) }
            }
        }
        guard !pieces.isEmpty else { return }
        let kinds = ShipParts.kinds
        var changed: [IVec3] = []
        for cells in pieces {
            var lo = IVec3(Int.max, Int.max, Int.max), hi = IVec3(Int.min, Int.min, Int.min)
            for c in cells { lo = IVec3(min(lo.x, c.x), min(lo.y, c.y), min(lo.z, c.z)); hi = IVec3(max(hi.x, c.x), max(hi.y, c.y), max(hi.z, c.z)) }
            let ng = ShipGrid(sx: hi.x - lo.x + 1, sy: hi.y - lo.y + 1, sz: hi.z - lo.z + 1)
            let part = Ship(id: newId(), grid: ng)
            for c in cells {
                let b = g.get(c.x, c.y, c.z)
                ng.set(c.x - lo.x, c.y - lo.y, c.z - lo.z, b)
                if kinds[Int(b)] == .engine { s.engines -= 1 }
                if s.helm == c { s.helm = nil }
                if let be = s.blockEntities.removeValue(forKey: c) { part.blockEntities[ivSub(c, lo)] = be }
                g.set(c.x, c.y, c.z, AIR)
                changed.append(c)
            }
            s.blockCount -= cells.count
            let off = V3(Float(lo.x), Float(lo.y), Float(lo.z))
            part.name = s.name + " wreckage"
            part.rebuild()
            part.rot = s.rot
            part.pos = s.toWorld(off + part.com)
            part.prevPos = part.pos; part.prevRot = part.rot
            // Flung outward a little from the hull.
            let out = part.pos - s.pos
            part.vel = s.velocity(at: part.pos) + simd_normalize(out + V3(0, 1e-3, 0)) * 3
            part.angVel = V3(Rand.float(in: -0.6...0.6), Rand.float(in: -0.3...0.3), Rand.float(in: -0.6...0.6))
            part.updateBounds()
            // Turrets whose ring went with the piece ride on it.
            for t in turrets(of: s) {
                let ring = t.mountLocal - V3(0.5, 1, 0.5)
                let rc = IVec3(Int(floor(ring.x + 0.01)), Int(floor(ring.y + 0.01)), Int(floor(ring.z + 0.01)))
                if rc.x >= lo.x && rc.x <= hi.x && rc.y >= lo.y && rc.y <= hi.y && rc.z >= lo.z && rc.z <= hi.z && ng.get(rc.x - lo.x, rc.y - lo.y, rc.z - lo.z) != AIR {
                    t.parent = part; t.parentId = part.id
                    t.mountLocal -= off
                }
            }
            add(part)
            part.mesh.rebuildAll(part, device: world.device, queue: meshQueue)
        }
        s.mesh.rebuildAround(s, changed, device: world.device, queue: meshQueue)
    }
}

extension Capital {
    // P325 (c), (d): a commandeered frigate's flight and its hull against the ground.
    static let maxPitch: Float = 0.45          // the most the helm pitches the bow, up or down (radians, ~26 degrees)
    static let maxBank: Float = 0.3            // the bank into a full turn
    // P334 (d): how far a dropship pitches and banks; Craft Bank (Quest comfort option) picks gentle or full while the
    // player rides one (the view itself keeps a level horizon: the rig follows only the craft's yaw).
    static var fullBank = false
    static var hovering = false                                  // P476: the frigate at the helm hovers (checks)
    static var vtolPitch: Float { fullBank ? 0.21 : 0.09 }      // 12 or 5 degrees
    static var vtolBank: Float { fullBank ? 0.38 : 0.14 }       // 22 or 8 degrees
    static let crashSpeed: Float = 14          // closing speed (blocks/s) at the touching part that tears the hull (a crash)
    static let wreckSpeed: Float = 30          // ... and that wrecks it (P476: below it she flies on, torn where she struck)
    // P476: the main gun's barrel torn away: under half its tube left 3 to 9 blocks back from the muzzle (the ring two
    // out from the axis: the axis itself is the bore, open air).
    static func barrelTorn(_ s: Ship, _ st: CapitalState) -> Bool {
        let d = simd_normalize(st.mainGunDir)
        let side = simd_normalize(simd_cross(d, abs(d.y) > 0.9 ? V3(1, 0, 0) : V3(0, 1, 0)))
        let up = simd_cross(side, d)
        var have = 0, n = 0
        for b in 3...9 where Float(b) <= max(3, st.mainGunLength) {
            for o in [side, -side, up, -up] {
                let p = st.mainGunMuzzle - d * Float(b) + o * 2
                n += 1
                if s.grid.get(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z))) != AIR { have += 1 }
            }
        }
        return n > 0 && have * 2 < n
    }
    static var crashLog: [String] = []         // (FrigateCheck: the hull blocks each part of a crash took)
    static var crashes = 0                     // (FrigateCheck)
    static var darkened = Set<Int>()           // hulls whose lights a crash put out (P357 d; FrigateCheck)

    // The hull's attitude from its heading, bow pitch (up +) and bank (right wing up +): yaw about the world's up, then
    // pitch about the hull's beam, then bank about its keel.
    static func attitude(yaw: Float, pitch: Float, bank: Float) -> Quat {
        Quat(angle: yaw, axis: V3(0, 1, 0)) * Quat(angle: pitch, axis: V3(1, 0, 0)) * Quat(angle: bank, axis: V3(0, 0, 1))
    }

    // The drive's strength, 0...1: nothing with under 40 % of the engine blocks left (the line that disables a frigate
    // under its own crew), a third at that line, full with every engine.
    static let restartTime: Float = 12     // P464: seconds till stopped engines (blocks in place) catch again
    // P483: rounds aboard for the guns he fires from the helm: a dropship's autocannon 600 (four minutes held), a
    // frigate's 40 a gun (each salvo spends one a barrel), a crawler's 30 a gun.
    static func magazine(_ s: Ship, barrels: Int) -> Int {
        if s.role == "dropship" { return 600 }
        // P507 (Nov 1 12:10:30 at a crawler's helm: "The magazine should hold more"): two and a half times what it was
        // (the guns he steers reload quicker as well: ShipManager.fire).
        return max(150, barrels * (s.isFlyingCapital ? 100 : 75))
    }

    static func drive(_ s: Ship, _ st: CapitalState) -> Float {
        guard st.engines0 > 0 else { return 1 }
        let k = power(s, st)
        return k < 0.4 ? 0 : min(1, 0.35 + 0.65 * (k - 0.4) / 0.6)
    }

    // P476: her thrust over her load, 1 as built: the engines drive the stern's thruster cores, so the weaker of the
    // two sets it (each a share of what she was built with), and every block added past her built weight drags it down.
    static func power(_ s: Ship, _ st: CapitalState) -> Float {
        guard st.engines0 > 0 else { return 1 }
        let ke = Float(s.engines) / Float(st.engines0)
        let kt: Float = st.thrustCells.isEmpty ? 1 : Float(st.thrustLive) / Float(st.thrustCells.count)
        let load: Float = st.blocks0 > 0 ? max(1, Float(s.blockCount) / Float(st.blocks0)) : 1
        return min(ke, kt) / load
    }
    static func countThrust(_ s: Ship, _ st: CapitalState, _ dt: Float) {
        st.thrustT -= dt
        guard st.thrustT <= 0, !st.thrustCells.isEmpty else { return }
        st.thrustT = 0.5
        let thr = Blocks.has("frigate_thruster") ? Blocks.id("frigate_thruster") : AIR
        st.thrustLive = st.thrustCells.reduce(0) { $0 + (s.grid.get($1.x, $1.y, $1.z) == thr ? 1 : 0) }
        if !st.reactorCells.isEmpty {
            let core = Blocks.has("frigate_reactor") ? Blocks.id("frigate_reactor") : AIR
            st.reactorLive = st.reactorCells.reduce(0) { $0 + (s.grid.get($1.x, $1.y, $1.z) == core ? 1 : 0) }
        }
    }
    // P508: the reactor breached (under half its core left): the ship is lost.
    static func reactorBreached(_ st: CapitalState) -> Bool { !st.reactorCells.isEmpty && st.reactorLive * 2 < st.reactorCells.count }

    // Top speed along the bow at full throttle (blocks/s).
    static let dropChase: Float = 55          // P499: a Capital Dropship's top speed giving chase (200 km/h, as his own)
    static let dashSpeed: Float = 280         // P499: the Meridian's top speed with the sprint held, high up (1,000 km/h)
    // P504 (Nov 1 07:45:22-07:45:29, at the Meridian's helm: "it's still maxing at a hundred and fifty kilometers per
    // hour. It needs to go four hundred kilometers per hour... We should be able to get up to that speed and slow down
    // pretty quickly"): she cruises at 111 m/s (400 km/h), was 42; the sprint still runs her to 1,000 high up.
    static func helmSpeed(_ s: Ship, _ st: CapitalState) -> Float {
        (s.role == "capfrigate" ? 111 : 18) * drive(s, st)
    }

    // The hull's outline in ship space: the outermost solid cell of every third row each way (the keel and the top of
    // every column, both ends of every row along the keel and across it), each moved half a block out to its face.
    static func hullProbes(_ g: ShipGrid) -> [V3] {
        var out: [V3] = []
        func solid(_ x: Int, _ y: Int, _ z: Int) -> Bool { Blocks.collide[Int(g.get(x, y, z))] }
        func add(_ x: Int, _ y: Int, _ z: Int, _ n: V3) { out.append(V3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5) + n * 0.45) }
        for z in stride(from: 0, to: g.sz, by: 3) {
            for x in stride(from: 0, to: g.sx, by: 3) {
                if let lo = (0..<g.sy).first(where: { solid(x, $0, z) }) { add(x, lo, z, V3(0, -1, 0)) }
                if let hi = (0..<g.sy).reversed().first(where: { solid(x, $0, z) }) { add(x, hi, z, V3(0, 1, 0)) }
            }
            for y in stride(from: 0, to: g.sy, by: 3) {
                if let lo = (0..<g.sx).first(where: { solid($0, y, z) }) { add(lo, y, z, V3(-1, 0, 0)) }
                if let hi = (0..<g.sx).reversed().first(where: { solid($0, y, z) }) { add(hi, y, z, V3(1, 0, 0)) }
            }
        }
        for y in stride(from: 0, to: g.sy, by: 3) {
            for x in stride(from: 0, to: g.sx, by: 3) {
                if let lo = (0..<g.sz).first(where: { solid(x, y, $0) }) { add(x, y, lo, V3(0, 0, -1)) }
                if let hi = (0..<g.sz).reversed().first(where: { solid(x, y, $0) }) { add(x, y, hi, V3(0, 0, 1)) }
            }
        }
        return out
    }
}
