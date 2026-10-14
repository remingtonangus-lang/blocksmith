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
}

// Per capital ship AI state (ShipManager.capState, keyed by the hull's id).
final class CapitalState {
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
    var mainGunLength: Float = 0       // barrel length back from the muzzle along -mainGunDir (the Tidebreaker's glow)
    var gunCharge: Float = -1          // the Tidebreaker: seconds charged (>= 0 while charging; MainGun.swift)
    var gunByPlayer = false            // the charge was started from the helm (fires along the view pitch)
    var gunPitch: Float = 0            // the helm's view pitch, kept current while it charges
    var gunPulse: Float = 0            // seconds to the next haptic coil thump while charging
    var aimPoint: V3?                  // the helm's predicted impact (MainGun.swift mainGunAimTick), nil when off the world
    var bombardAt: V3?                 // P99: the ground the crew's charging Tidebreaker will strike near a player
    var pingAt: V3?                    // C8: where its sonar last heard a submarine (it steers there while nothing is in sight)
    var pingT: Float = 0               // ... seconds since that ping (it gives up after 60)
    var bombardShots = 0               // ... shots so far at that player (each lands nearer)
    var aimTimer: Float = 0            // seconds to the next aim prediction (10 a second)
    var missileCD: Float = 5
    var pods: [(V3, V3)] = []          // missile pod mouths and launch directions (ship space)
    var exhausts: [V3] = []            // drive nozzle mouths (ship space)
    var retarget: Float = 0
    var target: CapTarget?
    var orbitDir: Float = 1
    var groundOffset: Float = 0        // centre of mass above the lowest wheel (crawlers)
    var groundTimer: Float = 0
    var groundMax: Float = 0           // highest terrain under and ahead of a frigate (sampled twice a second)
    var isles: [(c: V2, top: Float, r: Float)]? = nil   // T11: sky isles near a frigate's home (found once)
    var crushTimer: Float = 0
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
    var ground: V3?                    // crawler: smoothed ground under it (height, pitch, roll)
    var grind: Float = -1              // disabled crawler: forward speed while it grinds to a stop (-1 not yet)
    var impact: Float = 0              // crash-landed frigate: sink speed at touchdown (b/s)
    var sag = V2(0, 0)                 // disabled crawler: pitch / roll toward its lost wheels
    var wantSpeed: Float = 0           // crawler: the speed its AI wants (before the lowered ramp holds it to a creep)
    var goal: V3?                      // a citadel's crawler patrol (CapitalBases.swift): drive here when nothing is in sight
    var troopCD: Float = 12            // seconds until the next troop drop
    var parties = 0, partyCD: Float = 8   // Meridian boarding parties down the winch line (Navy.swift)
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
    static let dropFuel: Float = 240
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
    var lost: Bool { n * 2 < n0 }
}

struct CapTarget {
    var point: V3
    var vel: V3
    weak var ship: Ship?
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
    func fill(_ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int, _ z0: Int, _ z1: Int, _ b: BlockID) {
        for y in min(y0, y1)...max(y0, y1) { for z in min(z0, z1)...max(z0, z1) { for x in min(x0, x1)...max(x0, x1) { set(x, y, z, b) } } }
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
        switch style % 4 {
        case 1:
            t.box(-s - 1, s + 1, y0, y1, -s, s, "warship_hull", hollow: true)
            let roof = hang ? -4 : 3
            t.box(-s, s, roof, roof, -s + 1, s - 1, "warship_panel")
            for x in (-s)...s { t.set(x, yy(2), -s - 1, "warship_panel") }        // the sloped face's lip
            for bx in [-2, 0, 2] {
                for z in (-s - 8)...(-s - 1) { t.set(bx, by, z, "iron_block") }
                t.set(bx, by, -s - 9, "ship_cannon[south]")
            }
            t.set(-s - 1, yy(1) + up, s, "warship_stripe"); t.set(s + 1, yy(1) + up, s, "warship_stripe")
        case 2:
            t.box(-s, s, y0, y1, -s, s, "warship_hull", hollow: true)
            let roof = hang ? -4 : 3
            t.box(-s + 1, s - 1, roof, roof, -s + 1, s - 1, "warship_panel")
            for z in (-s - 13)...(-s - 1) { t.set(0, by, z, "iron_block") }
            t.set(-1, by, -s - 12, "iron_block"); t.set(1, by, -s - 12, "iron_block")   // muzzle brake
            t.set(0, by, -s - 14, "ship_cannon[south]")
            // The rangefinder: a bar across the roof, standing off on two posts.
            for x in (-s - 2)...(s + 2) { t.set(x, roof + up * 2, 1, "warship_panel") }
            t.set(-s, roof + up, 1, "iron_block"); t.set(s, roof + up, 1, "iron_block")
        case 3:
            t.box(-s, s, y0, hang ? -2 : 1, -s, s, "warship_hull", hollow: true)
            for bx in [-2, -1, 1, 2] {
                for z in (-s - 4)...(-s - 1) { t.set(bx, by, z, "iron_block") }
                t.set(bx, by, -s - 5, "ship_cannon[south]")
            }
            t.set(0, hang ? -2 : 1, s, "warship_stripe")
        default:
            t.box(-s, s, y0, y1, -s, s, "warship_hull", hollow: true)
            let roof = hang ? -4 : 3
            t.box(-s + 1, s - 1, roof, roof, -s + 1, s - 1, "warship_panel")
            for bx in [-1, 1] {
                for z in (-s - 8)...(-s - 1) { t.set(bx, by, z, "iron_block") }
                t.set(bx, by, -s - 9, "ship_cannon[south]")
            }
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
        for z in -3 ... -2 { t.set(0, 1, z, "iron_block") }
        t.set(0, 1, -4, "ship_cannon[south]")
        return t
    }

    static let naval = GunSpec2(speed: 120, power: 3.5, reload: 3.5, pitchMin: -0.35, pitchMax: 0.75)
    static let navalHung = GunSpec2(speed: 120, power: 3.5, reload: 3.5, pitchMin: -1.35, pitchMax: 0.2)
    static let heavy = GunSpec2(speed: 110, power: 4, reload: 4.5, pitchMin: -0.3, pitchMax: 0.7)
    static let auto = GunSpec2(speed: 140, power: 1.8, reload: 1.2, pitchMin: -0.4, pitchMax: 1.0, scatter: 0.025)

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
        let ring = Blocks.id("ship_turret_ring")
        for (cx, cz) in [(-12, 230), (12, 270)] {
            for y in 0..<ds.sy { for z in 0..<ds.sz { for gx in 0..<ds.sx {
                let b = ds.blocks[gx + z * ds.sx + y * ds.sx * ds.sz]
                if b == AIR || b == ring { continue }
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
        // Ladders: hangar -> upper deck -> bridge.
        let ladder = Blocks.id("ladder")
        for y in 27...46 { hb.set(-7, y, 300, panel); hb.set(-6, y, 300, ladder + 3) }
        for y in 47...76 { hb.set(7, y, 330, panel); hb.set(6, y, 330, ladder + 2) }
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
        // Spinal rail cannon over the bow.
        for z in 0...46 { for y in 26...34 { for x in -4...4 {
            let r: Float = sqrtf(Float(x * x + (y - 30) * (y - 30)))
            if r >= 1.5 && r < 2.6 { hb.set(x, y, z, iron) }
        } } }
        hb.fill(-3, 3, 21, 25, 40, 46, hull)
        hb.mainGun = (V3(Float(W) + 0.5, 30.5, -1), V3(0, 0, -1))
        // Command deck: windows, helm, consoles; troop bay below with a rear ramp; engines aft.
        for x in -6...6 { for y in 23...25 { hb.set(x, y, 20 + Int(Float(y - 21) * 0.8) + 1, glass) } }
        hb.fill(-7, 7, 21, 21, 24, 64, deck)
        hb.set(0, 22, 28, Blocks.id("ship_helm[south]"))
        for x in [-4, 4] { hb.set(x, 22, 26, console) }
        hb.set(0, 27, 40, light); hb.set(0, 27, 56, light)
        hb.fill(-10, 10, 9, 9, 10, 72, deck)
        for z in stride(from: 16, through: 64, by: 12) { hb.set(0, 19, z, light) }
        hb.fill(-6, 6, 10, 14, 62, 70, engine)
        for z in 73...73 { for y in 10...15 { for x in -4...4 { hb.set(x, y, z, AIR) } } }
        hb.set(-9, 10, 30, Blocks.id("chest") + 3); hb.chests.append((hb.grid(-9, 10, 30), "steelhold_armory"))
        hb.set(9, 10, 50, Blocks.id("chest") + 2); hb.chests.append((hb.grid(9, 10, 50), "steelhold_supply"))
        let ladder = Blocks.id("ladder")
        for y in 10...21 { hb.set(-8, y, 58, panel); hb.set(-7, y, 58, ladder + 3) }
        // Boarding (vehicle riding): a ladder up each flank between the front and middle wheels, from the ground to the
        // walkway on the chassis roof, a step and a hatch from there into the command deck; the rear ramp from the
        // troop bay to the ground (built lowered; it folds up into a door while the crawler drives: crawlerRamp).
        for sx in [-1, 1] {
            for y in 0...7 { hb.set(sx * 11, y, 29, panel) }
            for y in 0...20 { hb.set(sx * 12, y, 29, ladder + (sx > 0 ? 3 : 2)) }
            for y in 22...23 { hb.set(sx * 8, y, 30, AIR) }
            hb.set(sx * 9, 21, 30, Capital.id(sx > 0 ? "steel_plating_stairs[west]" : "steel_plating_stairs[east]", panel))
        }
        for (c, b) in crawlerRamp(down: true) { hb.set(c.x, c.y, c.z, b) }
        // Crew: a driver at the helm, a gunner for each turret (two heavies served from the command deck, four
        // sponsons from the chassis), and a squad of troops in the bay who go out by the rear ramp.
        hb.post(0, 22, 29, .driver)
        for (x, y, z) in [(2, 22, 53), (-2, 22, 61), (-9, 10, 15), (-9, 10, 68), (9, 10, 15), (9, 10, 68)] { hb.post(x, y, z, .gunner) }
        for (x, y, z) in [(-5, 10, 40), (5, 10, 55), (-3, 10, 46), (3, 10, 34), (-5, 10, 52), (4, 10, 44), (0, 22, 36), (-3, 22, 48)] {
            hb.post(x, y, z, .troop)
        }
        // Turrets: two heavy twins on the superstructure, four autocannon sponsons at the chassis corners.
        for (ti, z) in [54, 63].enumerated() {
            var top = 28
            while top > 20 && !inside(0, top, z) { top -= 1 }
            hb.set(0, top, z, Blocks.id("ship_turret_ring"))
            hb.turrets.append((hb.grid(0, top, z), navalTurret(hang: false, size: 3, style: ti == 0 ? 2 : 1), spec(ti == 0 ? 2 : 1, heavy)))
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
        return hb
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
        return hb
    }

    static func makeShips(_ hb: HullBuilder, ids: [Int], name: String, role: String, faction: Faction) -> [Ship] {
        let s = Ship(id: ids[0], grid: ShipGrid(sx: hb.sx, sy: hb.sy, sz: hb.sz, blocks: hb.blocks))
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
        // ever break), so naval guns and rail slugs tear real holes in a hull.
        for (n, disp) in [("warship_hull", "Warship Hull"), ("warship_panel", "Warship Panel"), ("warship_stripe", "Warship Trim")] where !has(n) {
            var d = BlockDef(n, disp)
            d.tex = [n]
            d.hardness = 8; d.resistance = 9; d.tool = .pickaxe; d.requiresTool = true; d.harvestLevel = 2; d.sound = .stone
            add(d)
        }
        registerCapitalFactionBlocks()
        registerMeridianBlocks()
    }
}

extension TextureGen {
    static func capitalPainters(_ p: inout [String: Painter]) {
        capitalFactionPainters(&p)
        meridianPainters(&p)
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
        if r.faction != 0, let f = Faction(rawValue: r.faction) { return f }
        switch r.role {
        case "frigate", "carriage": return .steelhold
        case "capfrigate": return .meridian
        case "warfrigate": return .stormwarden
        case "crawler": return .ironback
        case "sloop": return .corsairs                   // T15 (Pirates.swift)
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
        if kind.ash { return .ashguard }
        if posse == 3 { return .none }        // R21: a bounty hunter on the soldier AI belongs to no faction (BountyHunters)
        guard Soldier.rank(kind) != nil || kind == .deckGun else { return .none }
        return faction != 0 ? (Faction(rawValue: faction) ?? .steelhold) : .steelhold
    }
}

extension ShipManager {
    // Starts building a capital ship on a worker thread (sync: here and now, for the harness). It appears with its
    // turrets when finished (capitalTick picks it up).
    func spawnCapital(_ kind: String, home: IVec3, yaw: Float, region: String?, sync: Bool = false, faction: Faction? = nil) {
        if let r = region { capitalPending.insert(r) }
        let ids = (0..<24).map { _ in newId() }
        let gen = world.gen
        let work: () -> ([Ship], CapitalState) = {
            let frigate = kind != "crawler"
            let cap = kind == "capfrigate"
            let hb = cap ? Capital.capitalFrigate() : (frigate ? Capital.frigate() : Capital.crawler())
            let own: Faction = faction ?? (cap ? .meridian : (frigate ? .stormwarden : .ironback))
            let name = cap ? "Meridian Frigate" : (frigate ? "Stormwarden Frigate" : (own == .steelhold ? "Capital Crawler" : "Ironback Crawler"))
            let ships = Capital.makeShips(hb, ids: ids, name: name, role: kind, faction: own)
            let s = ships[0]
            let st = CapitalState()
            st.region = region
            st.engines0 = s.engines
            st.mainGunMuzzle = hb.mainGun.0
            st.mainGunDir = hb.mainGun.1
            st.mainGunLength = hb.mainGunLength
            st.pods = hb.pods
            st.exhausts = hb.exhausts
            st.crew = hb.crew
            st.crewRoles = hb.crewRoles + [CrewRole](repeating: .troop, count: max(0, hb.crew.count - hb.crewRoles.count))
            st.wheels = Capital.vehicleWheels(s)
            if !frigate {
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
            s.prevPos = s.pos; s.prevRot = s.rot
            s.home = V3(hx, s.pos.y, hz)
            s.initialBlocks = s.blockCount
            s.updateBounds()
            for t in ships.dropFirst() { t.followParent(0); t.prevPos = t.pos; t.prevRot = t.rot }
            return (ships, st)
        }
        if sync {
            installCapital(work())
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let built = work()
            guard let self else { return }
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
        if let s = ships.first { capState[s.id] = st }
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
        guard s.captured, let st = capState[s.id], !st.wheels.isEmpty else { return nil }
        let at = V3(Float(cell.x), Float(cell.y), Float(cell.z))
        var best = -1, bd = Float.greatestFiniteMagnitude
        for (k, w) in st.wheels.enumerated() where w.n < w.n0 && !w.orig.isEmpty {
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
                what = "Engines restarted (\(s.engines)/\(st.engines0) engine blocks)"
            }
            let missing = st.engineCells.filter { s.grid.get($0.0.x, $0.0.y, $0.0.z) == AIR }
                .sorted { simd_length(V3(Float($0.0.x), Float($0.0.y), Float($0.0.z)) - at) < simd_length(V3(Float($1.0.x), Float($1.0.y), Float($1.0.z)) - at) }
            if what.isEmpty {
                guard !missing.isEmpty else { return nil }
                for (c, b) in missing.prefix(8) { setBlock(s, c, b) }
                what = "Engine rebuilt (\(s.engines)/\(st.engines0) engine blocks)"
            }
        }
        let drives = st.wheelsLost * 2 < st.wheels.count && (st.engines0 == 0 || s.engines * 10 >= st.engines0 * 4)
        if drives && !st.disabledWhy.isEmpty {
            st.disabledWhy = ""; st.grind = -1; st.sag = V2(0, 0)
            return what + ": the \(s.name) can drive again"
        }
        return what
    }

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
        for o in list where o.parent == nil && !o.wrecked {
            let f = o.factionValue
            if f == .none || f == faction { continue }
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
            for m in g.mobs.mobs where m.health > 0 && m.factionValue != .none && m.factionValue != faction {
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
        for s in capitals {
            guard let st = capState[s.id] else { continue }
            let pd = boundsDistance(s, g.player.pos)
            // Far behind the player: gone, and its region may bring it back (wrecks stay gone).
            if pd > 1400 && aboard?.root !== s {
                if let r = st.region, !s.wrecked { spawnedRegions.remove(r) }
                remove(s)
                capState.removeValue(forKey: s.id)
                continue
            }
            if s.captured && !s.wrecked && (s.role == "dropship" || s.isFlyingCapital) { commandeeredTick(s, st, dt, g); continue }
            if s.captured && s.role == "crawler" { capturedCrawlerTick(s, st, dt, g); continue }
            if s.role == "dropship" { dropshipTick(s, st, dt, g); continue }
            if !st.announced && pd < 420 {
                st.announced = true
                g.onToast?(s.role == "crawler" ? "The ground shakes: an Ironback Crawler is near" : "A \(s.name) looms on the horizon")
            }
            if s.asleep { continue }
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
            if st.crewDone.count < st.crew.count && pd < 96 {
                // The crew aboard: soldiers of the ship's faction at their posts (they ride the hull and fight as
                // soldiers). Only over loaded ground (mobs there don't update, so they'd be left hanging as the hull
                // moved on).
                let troopRanks: [MobKind] = [.soldierTrooper, .soldierTrooper, .soldierRecruit, .soldierIronclad]
                for (i, post) in st.crew.enumerated() where !st.crewDone.contains(i) {
                    let at = s.toWorld(post + V3(0, 0.05, 0))
                    guard world.isLoaded(Int(floor(at.x)), Int(floor(at.z))), simd_length(at - g.player.pos) < 120 else { continue }
                    st.crewDone.insert(i)
                    let role = i < st.crewRoles.count ? st.crewRoles[i] : .troop
                    let kind: MobKind = role == .driver ? .soldierTrooper : (role == .gunner ? .soldierMarksman : troopRanks[i % troopRanks.count])
                    let m = Mob(kind, at: at)
                    m.faction = s.faction
                    m.persistent = true
                    m.deck = s
                    m.crewPost = post
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
                }
            }
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
            if s.isFlyingCapital { flyFrigate(s, st, dt, g) } else { driveCrawler(s, st, dt, g) }
            capitalGuns(s, st, dt, g)
            shipMissiles(s, st, dt, g)
            if s.role == "capfrigate" { mainGunTick(s, st, dt, g); boardingWinch(s, st, dt, g); boardingParty(s, st, dt, g) }
            deployTroops(s, st, dt, g)
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
                guard d < min(bd, 180) else { return }
                let eye = g.player.eye
                guard self.world.clearShot(s.pos, eye) || self.world.clearShot(V3(s.pos.x, s.worldMax.y + 1, s.pos.z), eye) else { return }
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
        guard top > 0, Blocks.isLiquid(world.block(ix, top, iz)) || Blocks.isLiquid(world.block(ix, top - 1, iz)) else { return nil }
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

    // Holds a frigate upright (only yaw is steered; drift from rounding is taken out).
    // Capital fliers the player can take command of from the helm (Quest round 4: the frigate's helm was locked and a
    // dropship had none). Crawlers stay locked.
    func canCommandeer(_ s: Ship) -> Bool {
        // T9: a crawler whose driver is dead can be taken too, wrecked or not (its wheels are rebuilt with ingots).
        if s.kinematic && s.parent == nil && s.helm != nil && s.role == "crawler" { return capState[s.id].map { !$0.driverAlive } ?? false }
        return s.kinematic && s.parent == nil && !s.wrecked && s.helm != nil && (s.role == "dropship" || s.isFlyingCapital)
    }

    // T9: a captured crawler driven from its helm: throttle forward and back, steer turns it; it follows the ground as
    // under its own crew. With half its wheels lost it won't move until they are rebuilt (ShipManager.repairVehicle).
    private func capturedCrawlerTick(_ s: Ship, _ st: CapitalState, _ dt: Float, _ g: Game) {
        trackWheels(s, st, dt)
        let steered = pilot === s
        let lost = st.wheels.isEmpty ? 0 : Float(st.wheelsLost) / Float(st.wheels.count)
        let drives = lost < 0.5 && (st.engines0 == 0 || s.engines * 10 >= st.engines0 * 4)
        if steered && !drives && abs(s.throttle) > 0.1 && !st.winchTold {
            st.winchTold = true
            g.onToast?("The \(s.name) is too damaged to drive: use steel or iron ingots on it to rebuild its wheels and engines")
        }
        if drives { st.winchTold = false }
        let fw = s.dirToWorld(V3(0, 0, -1))
        let fh = simd_normalize(V2(fw.x, fw.z) + V2(1e-5, 0))
        let a = steered ? -s.steer * 0.7 : 0
        let want = V2(fh.x * cosf(a) - fh.y * sinf(a), fh.x * sinf(a) + fh.y * cosf(a))
        let speed = steered && drives ? s.throttle * 9 * (1 - lost) : 0
        st.wantSpeed = abs(speed)
        crawlerMotion(s, st, dt, want: want, speed: speed, turnRate: steered && drives && abs(s.steer) > 0.05 ? 0.18 : 0)
    }

    // A commandeered Capital flier, flown straight from the helm's throttle, steer and climb (kinematic, as its AI
    // flew it); with nobody at the helm it holds station. Its AI, guns and troop drops stay off for good.
    private func commandeeredTick(_ s: Ship, _ st: CapitalState, _ dt: Float, _ g: Game) {
        let steered = pilot === s
        let drop = s.role == "dropship"
        let fw = s.dirToWorld(V3(0, 0, -1))
        let fh = simd_normalize(V2(fw.x, fw.z) + V2(1e-5, 0))
        let meridian = s.role == "capfrigate"
        let speed: Float = drop ? 24 : (meridian ? 42 : 16)
        var want = V3(fh.x, 0, fh.y) * (steered ? s.throttle * speed : 0)
        want.y = steered ? s.climb * (drop ? 8 : (meridian ? 10 : 5)) : 0
        if drop && steered && !dropFuel(s, st, dt, g) { want = V3(0, -2.5, 0) }       // dry tanks: it settles to the ground
        // Never into the ground: the keel keeps 2 blocks over the top block under the hull's centre.
        let gx = Int(floor(s.pos.x)), gz = Int(floor(s.pos.z))
        let top = Float(world.isLoaded(gx, gz) ? world.topY(gx, gz) : world.gen.column(gx, gz).height)
        if s.worldMin.y < top + 3 { want.y = max(want.y, (top + 3 - s.worldMin.y) * 2) }
        if s.worldMax.y > Float(CH - 4) { want.y = min(want.y, 0) }
        s.vel += (want - s.vel) * min(1, dt * (meridian ? 0.8 : 1.2))
        let yawRate: Float = steered ? -s.steer * (drop ? 0.9 : (meridian ? 0.45 : 0.3)) : 0
        s.angVel = V3(0, s.angVel.y + (yawRate - s.angVel.y) * min(1, dt * 2), 0)
        levelUp(s, dt)
        st.target = nil
        driveGlow(s, st, boundsDistance(s, g.player.pos), dt, g)
        st.mainGunCD -= dt                                  // the Tidebreaker recharges for its new captain (playerMainGun)
        if s.role == "capfrigate" { mainGunTick(s, st, dt, g); boardingWinch(s, st, dt, g); if pilot === s { mainGunAimTick(s, st, dt, g) } }
        for t in turrets(of: s) { t.aimAt = nil }
    }

    // P66: a commandeered drop craft burns fuel while it thrusts (four minutes on full tanks). Running dry, it takes
    // coal, charcoal or blaze rods from the pilot's pack (a lump is 40 s, a rod 80 s); with none, it sinks gently
    // to the ground. Returns false when there is no fuel.
    static let fuelItems: [(String, Float)] = [("blaze_rod", 80), ("coal", 40), ("charcoal", 40), ("coal_block", 360)]
    func dropFuel(_ s: Ship, _ st: CapitalState, _ dt: Float, _ g: Game) -> Bool {
        if abs(s.throttle) > 0.05 || abs(s.climb) > 0.05 { st.fuel -= dt }
        if st.fuel <= 0 {
            for (k, secs) in ShipManager.fuelItems where Items.has(k) {
                let id = Items.id(k)
                if g.inventory.main.remove(id, 1) == 1 {
                    st.fuel += secs
                    g.onToast?("Refuelled the \(s.name) with \(Items.def(id).display)")
                    break
                }
            }
        }
        if st.fuel > 30 { st.fuelTold = 0 }
        if st.fuel <= 30 && st.fuel > 0 && st.fuelTold == 0 { st.fuelTold = 1; g.onToast?("\(s.name): fuel low. Carry coal or blaze rods") }
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
        crush(s, st, dt)
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
    private func crawlerMotion(_ s: Ship, _ st: CapitalState, _ dt: Float, want want0: V2, speed speed0: Float, turnRate: Float) {
        var want = want0, speed = speed0
        let fw = s.dirToWorld(V3(0, 0, -1))
        let fh = simd_normalize(V2(fw.x, fw.z) + V2(1e-5, 0))
        func ground(_ p: V2) -> Float { groundTop(Int(floor(p.x)), Int(floor(p.y))) }
        let half: Float = 28, track: Float = 13
        let c2 = V2(s.pos.x, s.pos.z)
        let side = V2(-fh.y, fh.x)
        let hF = ground(c2 + fh * half), hB = ground(c2 - fh * half)
        let hL = ground(c2 - side * track), hR = ground(c2 + side * track)
        // Water or a cliff ahead: turn away.
        if turnRate > 0 {
            let hA = ground(c2 + fh * (half + 14))
            if hA < Float(SEA) || hA - hF > 8 {
                want = V2(-fh.y, fh.x) * st.orbitDir
                speed = min(speed, 1.5)
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
        let want = s.wrecked || troopsOut || st.wantSpeed < 1.6
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
    private func crush(_ s: Ship, _ st: CapitalState, _ dt: Float) {
        st.crushTimer -= dt
        guard st.crushTimer <= 0 else { return }
        st.crushTimer = 0.25
        let lo = s.localMin, hi = s.localMax
        var n = 0
        let hardness = Blocks.hardness
        // On arrival the whole footprint is cleared once (it spawned among trees that hid its wheels: run 404),
        // afterwards only the front rows it drives into.
        // The full pass waits until every corner of the footprint is loaded and repeats until one pass finishes under
        // the cap (done when only the centre had loaded, the rest of the trees stayed in the hull: blind critic, run 417
        // ship_crawler, an oak through a wheel arch).
        var cornersLoaded = true
        for (cx, cz) in [(lo.x, lo.z), (hi.x, lo.z), (lo.x, hi.z), (hi.x, hi.z)] {
            let c = s.toWorld(V3(cx, lo.y, cz))
            if !world.isLoaded(Int(floor(c.x)), Int(floor(c.z))) { cornersLoaded = false }
        }
        let full = !st.crushedAll && cornersLoaded
        let zEnd: Float = full ? hi.z : lo.z + 6
        let cap = full ? 4000 : 80
        defer { if full && n < cap { st.crushedAll = true } }
        for lz in stride(from: lo.z - 1, through: zEnd, by: 1) {
            for lx in stride(from: lo.x, through: hi.x, by: 1) {
                // From the bottom row (trunks stood through the wheel arches); soft blocks only, so ground is never dug.
                for ly in stride(from: lo.y, through: hi.y, by: 1) {
                    let w = s.toWorld(V3(lx, ly, lz))
                    let x = Int(floor(w.x)), y = Int(floor(w.y)), z = Int(floor(w.z))
                    guard world.isLoaded(x, z) else { continue }
                    let b = world.block(x, y, z)
                    if b == AIR || Blocks.isLiquid(b) { continue }
                    let key = Blocks.key(Blocks.groupBase[Int(b)])
                    let soft: Bool = key.hasSuffix("_leaves") || key.hasSuffix("_log") || key.hasSuffix("_planks") || key.hasSuffix("_fence")
                        || key.contains("glass") || key.hasSuffix("_wood") || key.contains("mushroom_block") || key == "cactus"
                        || key == "bamboo" || (!Blocks.collide[Int(b)] && hardness[Int(b)] >= 0)
                    // P65: driving on, it breaks through buildings (walls, brick, stone work) instead of passing
                    // through them; natural ground and unbreakable blocks stay.
                    let built = !full && !ShipParts.natural[Int(b)] && hardness[Int(b)] >= 0
                    if !soft && !built { continue }
                    world.setBlockAsync(x, y, z, AIR)
                    n += 1
                    if n >= cap { return }
                }
            }
        }
    }

    // Guns: turrets track the target and fire on their own reloads; the spinal gun charges and fires a rail slug
    // down the bow when the target is within 25 degrees of it; missile salvos from the pods.
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
            if aimErr < 0.12 && tr.reload <= 0 { fire(tr, pitch: elev, game: g) }
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
        } else if st.driverAlive && st.mainGunCD <= 0 && cosA > 0.9 && dist < 600 && dist > 20 {
            if st.mainCharge == 0 { g.sfx(.gun(12), 2, at: mw) }
            st.mainCharge += dt
            if Int(st.mainCharge * 20) % 2 == 0 { g.particles.smoke(at: mw, dark: false) }
            if st.mainCharge >= 1.6 {
                st.mainCharge = 0
                let frigate = s.isFlyingCapital
                st.mainGunCD = frigate ? 24 : 16
                var dir = simd_normalize(t.point + t.vel * (dist / 260) - mw)
                if simd_dot(dir, md) < 0.85 { dir = simd_normalize(md + (dir - md) * 0.5) }
                let sh = Shell(pos: mw + dir * 2, vel: dir * 260, owner: s.id, power: frigate ? 10 : 7)
                sh.gravity = 1.5
                sh.kind = 1
                sh.life = 4
                shells.append(sh)
                g.sfx(.gun(9), 2, at: mw)
                g.sfx(.explode, 0.8, at: mw)
                g.particles.explosion(at: mw, power: 2)
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
                let sh = Shell(pos: at + dir, vel: dir * 30 + s.vel, owner: s.id, power: SmallMissiles.power)
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
                // Lanes beside the engine room: port outboard of the bay ladder, starboard inboard of the supply chest.
                let lane: Float = post.x < ox + 0.5 ? -9.5 : 7.5
                m.crewPost = nil
                m.crewRoute = [V3(ox + 0.5 + lane, 10, post.z), V3(ox + 0.5 + lane, 10, 71.5), V3(ox + 0.5, 10, 72.5),
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
            let name = faction == .steelhold ? "Capital Dropship" : faction == .meridian ? "Meridian Launch" : faction == .greywall ? "Greywall Dropship" : faction == .ironback ? "Ironback Dropship" : "Stormwarden Dropship"
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
            return (ships, ds)
        }
        g.sfx(.engineStart, 1, at: at)
        if sync { installCapital(work()); return true }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let built = work()
            guard let self else { return }
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
        // T7: the squad keeps round its officer and takes up the fight the officer has seen.
        if let lead = st.troops.first(where: { $0.kind == .soldierOfficer && $0.health > 0 }) {
            for (i, m) in st.troops.enumerated() where m !== lead && m.health > 0 {
                let a = Float(i) * 2.1
                m.home = lead.pos + V3(cosf(a) * 2.5, 0, sinf(a) * 2.5)
                if lead.aggro && !m.aggro, let seen = lead.brain?.lastSeen { m.aggro = true; m.soldierBrain.lastSeen = seen }
            }
        }
        let keel = st.groundOffset
        let gx = Int(floor(s.pos.x)), gz = Int(floor(s.pos.z))
        // Over loaded ground, the real top block (tree crowns too: hovering at terrain height put it in the canopy).
        let top: Int = world.isLoaded(gx, gz) ? world.topY(gx, gz) : world.gen.column(gx, gz).height
        let ground = Float(max(top, SEA))
        // P65 (Oct 11 evening playtest: dropships flew through Capital towers): in flight it clears the highest block
        // under its whole hull and a hull length ahead, not just the column at its centre.
        var clear = ground
        if st.phase == 1 || st.phase >= 4 {
            let lo = s.localMin, hi = s.localMax
            let ahead = V3(s.vel.x, 0, s.vel.z) * 1.5
            for c in [V3(lo.x, 0, lo.z), V3(hi.x, 0, lo.z), V3(lo.x, 0, hi.z), V3(hi.x, 0, hi.z), (lo + hi) * 0.5] {
                for a in [V3(0, 0, 0), ahead] {
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
                Explosion.explode(at: s.pos, power: 4, game: g, breakBlocks: !g.bases.inAnyBase(s.pos))
                remove(s)
                capState.removeValue(forKey: s.id)
            }
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
            want = V3(away.x, 0, away.y) * 20 + V3(0, 8, 0)
            if st.phaseT > 20 || s.pos.y > Float(CH - 12) { remove(s); capState.removeValue(forKey: s.id); return }
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
        s.angVel = V3(0, s.angVel.y + (yawRate - s.angVel.y) * min(1, dt * 3), 0)
        levelUp(s, dt)
        if st.phase >= 1 { capitalGuns(s, st, dt, g) }
    }

    // A crippled capital ship: a frigate comes down out of the sky with fires breaking out and crash-lands; a crawler
    // grinds to a halt, burning. Neither vanishes: the wreck stays where it came to rest, its crew aboard.
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
        let lo = s.localMin, hi = s.localMax
        for k in 0..<3 {
            let p = V3((lo.x + hi.x) * 0.5, lo.y + 0.5, lo.z + (hi.z - lo.z) * (0.2 + 0.3 * Float(k)))
            Explosion.explode(at: s.toWorld(p) - V3(0, 1, 0), power: 3, game: g)
        }
        g.sfx(.shipCollideHard, 2, at: s.pos)
        // The jolt: riders on deck take damage for a hard touchdown (over 3.5 b/s), none for a flared one.
        let hurt = Int(max(0, (st.impact - 3.5) * 2).rounded())
        if hurt > 0 {
            if aboard?.root === s { g.damage(hurt, "was thrown about in a crash landing", type: .fall) }
            for m in g.mobs.mobs where m.deck === s && m.health > 0 { m.health -= hurt; m.hurt = 0.3 }
        }
        if simd_length(s.pos - g.player.pos) < 400 { g.onToast?("The \(s.name) has crash-landed") }
    }
}

// MARK: Breakaway pieces (block-based damage on capital hulls)

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
