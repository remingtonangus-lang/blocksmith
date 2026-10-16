import Foundation
import simd

// The last war's end (backlog B7, docs/status/the-last-war.md). The Ash Marshal's fall no longer ends the war:
//   the last battle   the Ashguard throws its last army at the player in three waves (infantry and half-tracks; tanks
//                     under barrages; the Behemoth with tanks and heavies), 45-70 blocks out across the vault floor
//   the bunker        winning it opens the blast door in the command bunker's floor: stairs down to the Chancellor's
//                     Bunker, a sealed concrete complex (guard hall, radio room, generator room, map room, his study)
//   the Chancellor    waits in his study, calls his guard twice and brings the roof down on the way; his death is the
//                     victory: the army stands down, the ending rolls, the lift home opens
// The bunker is a fixed structure start (built with the citadel, after it); vaults saved before it get it stamped in
// as their chunks load (SaveManager.loadChunk). Its concrete and blast door break for nothing.
enum AshFinal {
    static let y0 = 14                                   // the complex's floor (internal y); rooms are 4 high
    static let hatchY = DeepGen.floorBase                // the blast door is the command bunker's floor
    static let hatchX = 7...9, hatchZ = 2...4
    static let lo = IVec3(-18, 12, 1), hi = IVec3(18, DeepGen.floorBase + 1, 48)
    static let chancellorAt = V3(8.5, Float(14 + 1), 42.5)

    static func start() -> StructureStart {
        StructureStart(kind: "ash_finalbunker", pieces: [Piece(min: lo, max: hi) { w in AshFinal.build(&w) }],
                       anchor: IVec3(8, y0 + 1, 40))
    }

    // Inside the complex or its stairs (below the command bunker's floor).
    static func inside(_ p: V3) -> Bool {
        p.y < Float(hatchY) && p.y > Float(y0 - 1) && p.x > -17 && p.x < 18 && p.z > 1 && p.z < 47
    }

    static let bc = Blocks.id("ash_bunkercrete"), door = Blocks.id("ash_blastdoor")

    static func build(_ w: inout StructWriter) {
        let bc = AshFinal.bc
        let floor = Blocks.id("polished_blackstone"), lamp = Blocks.id("ash_lamp"), plating = Blocks.id("ash_plating")
        let console = Blocks.has("command_console") ? Blocks.id("command_console") : plating
        let red = Blocks.has("red_wool") ? Blocks.id("red_wool") : Blocks.id("ash_mark")
        let drum = Blocks.id("ash_drum"), crate = Blocks.id("ash_crate"), table = Blocks.id("crafting_table")
        let top = y0 + 4                                  // the rooms' highest air layer
        func room(_ x0: Int, _ z0: Int, _ x1: Int, _ z1: Int) {
            w.fill(x0, y0 + 1, z0, x1, top, z1, AIR)
            w.fill(x0, y0, z0, x1, y0, z1, floor)
        }
        func doorway(_ x0: Int, _ z0: Int, _ x1: Int, _ z1: Int) { w.fill(x0, y0 + 1, z0, x1, y0 + 3, z1, AIR); w.fill(x0, y0, z0, x1, y0, z1, floor) }
        // A banner hanging on a wall face, from just under the ceiling (`alongX`: on a wall facing along x).
        func hang(_ x: Int, _ z: Int, alongX: Bool) { AshWar.banner(&w, x: x, z: z, top: top, normalX: alongX) }

        // The shell: one block of bunker concrete round everything, two under and over.
        w.fill(-17, y0 - 1, 17, 17, top + 2, 47, bc)
        room(4, 18, 12, 26)                               // the guard hall at the foot of the stairs
        room(-15, 27, 15, 29)                             // the corridor
        room(-6, 20, 1, 25); doorway(-4, 26, -3, 26)      // the radio room
        room(-15, 20, -9, 25); doorway(-13, 26, -11, 26)  // the generator room
        room(-15, 31, -2, 41); doorway(-10, 30, -8, 30)   // the map room
        room(1, 32, 15, 45); doorway(7, 30, 9, 31)        // the Chancellor's study

        // The stairs: from the hatch in the command bunker's floor down to the hall, encased in bunker concrete; the
        // bunker floor over them is concrete too, so the only way down is the blast door.
        w.fill(6, hatchY, 1, 10, hatchY, 6, bc)
        w.fill(6, hatchY - 5, 1, 10, hatchY - 1, 1, bc)
        for z in 2...17 {
            let fy = hatchY - 1 - (z - 2)                 // 29 at the hatch down to 14 at the hall
            let ceil = min(hatchY, fy + 5)
            w.fill(6, fy - 1, z, 10, ceil, z, bc)
            w.fill(7, fy, z, 9, fy, z, floor)
            if fy + 1 <= ceil - 1 { w.fill(7, fy + 1, z, 9, ceil - 1, z, AIR) }
            if z % 4 == 3 && ceil < hatchY { w.set(8, ceil, z, lamp) }
        }
        w.fill(hatchX.lowerBound, hatchY, hatchZ.lowerBound, hatchX.upperBound, hatchY, hatchZ.upperBound, door)

        // Guard hall: lamps, sandbag-free concrete, banners either side of the way in, crates.
        for (x, z) in [(5, 19), (11, 19), (5, 25), (11, 25)] { w.set(x, top + 1, z, lamp) }
        hang(4, 22, alongX: true); hang(12, 22, alongX: true)
        w.set(11, y0 + 1, 18, crate); w.set(11, y0 + 2, 18, crate); w.set(5, y0 + 1, 18, crate)
        // Corridor lamps every six blocks.
        for x in stride(from: -12, through: 12, by: 6) { w.set(x, top + 1, 28, lamp) }
        // Radio room: consoles along the back wall.
        w.fill(-6, y0 + 1, 20, 1, y0 + 1, 20, console)
        w.set(-2, top + 1, 22, lamp)
        // Generator room: plated machinery and fuel drums.
        w.fill(-14, y0 + 1, 21, -12, y0 + 3, 23, plating)
        for (x, z) in [(-10, 21), (-10, 22), (-9, 21), (-14, 25), (-10, 25)] { w.set(x, y0 + 1, z, drum) }
        w.set(-12, top + 1, 24, lamp)
        // Map room: the big map table, consoles round the walls, the standard on the end wall.
        w.fill(-11, y0 + 1, 34, -6, y0 + 1, 38, console)
        w.fill(-10, y0 + 2, 35, -7, y0 + 2, 37, table)
        w.fill(-15, y0 + 1, 31, -15, y0 + 2, 41, console)
        AshWar.standard(&w, x: -6, z: 41, top: top, normalX: false)
        for (x, z) in [(-12, 33), (-5, 33), (-12, 39), (-5, 39)] { w.set(x, top + 1, z, lamp) }
        // The study: a red runner to his desk, banners down the walls, the standard behind the desk.
        w.fill(7, y0, 32, 9, y0, 44, red)
        w.fill(5, y0 + 1, 41, 11, y0 + 1, 41, plating)            // the desk
        w.fill(6, y0 + 2, 41, 10, y0 + 2, 41, table)
        AshWar.standard(&w, x: 8, z: 45, top: top, normalX: false)
        for z in stride(from: 34, through: 43, by: 3) { hang(1, z, alongX: true); hang(15, z, alongX: true) }
        hang(4, 45, alongX: false); hang(12, 45, alongX: false)
        for (x, z) in [(4, 34), (12, 34), (4, 40), (12, 40), (8, 37)] { w.set(x, top + 1, z, lamp) }
        w.fill(2, y0 + 1, 44, 3, y0 + 2, 45, crate)
        w.fill(13, y0 + 1, 44, 14, y0 + 1, 45, drum)
    }

    // A saved vault chunk from before the bunker: build it in, unless it already holds bunker concrete (it was
    // generated with the bunker). Only chunks the bunker reaches.
    static func stamp(_ b: inout [BlockID], cx: Int, cz: Int) {
        let bx = cx * CS, bz = cz * CS
        let complex = bx + CS > -17 && bx <= 17 && bz + CS > 17 && bz <= 47
        let stairs = bx + CS > 6 && bx <= 10 && bz + CS > 1 && bz <= 17
        guard complex || stairs, b.count == CSQ * CH else { return }
        let c = bc
        for v in b where v == c { return }
        b.withUnsafeMutableBufferPointer { buf in
            var w = StructWriter(bx: bx, bz: bz, blocks: buf.baseAddress!)
            build(&w)
        }
    }

    // The last battle's waves (structure-mob keys; "@ash" joins the Ashguard).
    static let waves: [[String]] = [
        ["soldier_recruit", "soldier_recruit", "soldier_trooper", "soldier_trooper", "soldier_trooper", "soldier_marksman",
         "soldier_officer", "ash_halftrack", "ash_halftrack"],
        ["ash_tank", "ash_tank", "ash_tank", "soldier_trooper", "soldier_trooper", "soldier_trooper", "soldier_ironclad", "soldier_ironclad"],
        ["ash_behemoth", "ash_tank", "ash_tank", "soldier_ironclad", "soldier_ironclad", "soldier_ironclad", "soldier_ironclad"],
    ]
    static let waveNames = ["their reserve infantry and half-tracks", "their last tank company", "the Behemoth"]
    static let cap = 24                  // live Ashguard units near the player before a wave's infantry is trimmed
    static let breather: Float = 15
}

// The last war's live state (not saved: Game.ashStage and ashWave are; a wave in progress comes again after a reload).
final class LastWar {
    var clock: Float = 0
    var breather: Float = 0
    var spawned = false
    var wave: [Mob] = []
    var barrage: Float = 0
    var inBunker: Float = 0
    var voice: Float = 0                // seconds to the Chancellor's loudspeaker line at the battle's start
    var vanished = 0                    // wave units gone without dying (unloaded: the player left, died or ran off)
    var stragglers: Float = 0           // seconds the wave has been down to its last few
    var spawnedWaves = 0                // harness counter
}

extension Game {
    // Once a second in the Deep: the last battle and the bunker (marked barrages land in ashArmyTick, AshArmy.swift).
    func lastWarTick(_ dt: Float) {
        guard dim.dim == .deep else { return }
        lastWar.clock += dt
        guard lastWar.clock >= 1 else { return }
        let s = lastWar.clock
        lastWar.clock = 0
        if ashVictory { ashStage = 3 }
        ashHatchTick()                                    // P318: the hatch console (AshSabotage.swift)
        switch ashStage {
        case 1: lastBattleSecond(s)
        case 2: bunkerSecond(s)
        default: break
        }
    }

    // Three marked shells round the player (leading them a little).
    func ashMarkBarrage(_ toast: String, from: Mob? = nil, by: String = "the Ashguard's guns") {
        let p = player.pos
        let lead = V3(player.vel.x, 0, player.vel.z) * 1.2
        for k in 0..<3 {
            let off = k == 0 ? V3.zero : V3(Rand.float(in: -4...4), 0, Rand.float(in: -4...4))
            let at = p + lead + off
            ashStrikes.append(AshStrike(at: at, t: 2 + Float(k) * 0.45, power: 1.5, from: from.map { ObjectIdentifier($0) }, by: by))
        }
        sfx(.gun(10), 1.2, at: p)
        onToast?(toast)
    }

    // The Marshal is dead: the last battle begins.
    func startLastBattle() {
        guard ashStage == 0, !ashVictory else { return }
        ashStage = 1
        ashWave = 0
        lastWar.spawned = false
        lastWar.wave.removeAll()
        lastWar.breather = 8
        sfx(.gun(10), 1.8, at: player.pos)
        onToast?("The Ash Marshal is dead. Sirens: the Ashguard is throwing its last army at you. Hold the citadel")
        lastWar.voice = 4
    }

    private func lastBattleSecond(_ s: Float) {
        let lw = lastWar
        if !lw.wave.isEmpty {
            let live = Set(mobs.mobs.map { ObjectIdentifier($0) })
            var gone = 0
            lw.wave.removeAll { u in
                if u.health <= 0 { return true }
                if !live.contains(ObjectIdentifier(u)) { gone += 1; return true }
                return false
            }
            lw.vanished += gone
        }
        if lw.voice > 0 {
            lw.voice -= s
            if lw.voice <= 0 { onToast?("The Chancellor, over the loudspeakers: \"Every last man to the citadel. Crush them!\"") }
        }
        if !lw.spawned {
            lw.breather -= s
            guard lw.breather <= 0, DeepGen.inVault(player.pos.y), !AshFinal.inside(player.pos) else { return }
            if spawnAshWave(ashWave) {
                lw.spawned = true
                lw.vanished = 0
                lw.barrage = 10
                onToast?("Wave \(ashWave + 1) of 3: \(AshFinal.waveNames[ashWave]) are coming")
                sfx(.gun(10), 1.6, at: player.pos)
            }
            return
        }
        // Their guns: barrages over the field once the tanks roll.
        if ashWave >= 1 && DeepGen.inVault(player.pos.y) {
            lw.barrage -= s
            if lw.barrage <= 0 {
                lw.barrage = difficulty >= 3 ? 10 : 13
                ashMarkBarrage("Their guns have your range: move!")
            }
        }
        // A wave is beaten when at most two of it are left standing (the last one: when none is).
        // Units that vanished alive (unloaded) still stand; with none of the wave left here to fight, it regroups and
        // comes again (leaving the vault or dying never skips a wave).
        let left = lw.wave.count + lw.vanished
        let beaten = ashWave == 2 ? left == 0 : left <= 2
        if !beaten && lw.wave.isEmpty {
            lw.spawned = false
            lw.vanished = 0
            lw.breather = 6
            onToast?("The Ashguard regroups: wave \(ashWave + 1) is coming again")
            return
        }
        // P249 (Oct 13 22:02, before the endgame): the last few of a wave can be stuck in a trench or behind a bunker
        // far off, and the battle waits on them. After 25 s down to its last few they glow and the toast says where.
        if !beaten && left <= (ashWave == 2 ? 4 : 6) {
            lw.stragglers += s
            if lw.stragglers >= 25 && Int(lw.stragglers) % 20 == 5, let u = lw.wave.min(by: { simd_length_squared($0.pos - player.pos) < simd_length_squared($1.pos - player.pos) }) {
                for m in lw.wave { m.applyEffect(.glowing, amp: 0, seconds: 21, game: self) }
                onToast?("\(lw.wave.count) of the wave still stand: the nearest \(radarBearing(RadarContact(name: "", kind: "", x: Int(u.pos.x), z: Int(u.pos.z))))")
            }
        } else {
            lw.stragglers = 0
        }
        guard beaten else { return }
        lw.vanished = 0
        lw.stragglers = 0
        ashWave += 1
        lw.spawned = false
        lw.wave.removeAll()
        if ashWave >= AshFinal.waves.count {
            ashStage = 2
            ashWave = 0
            achieve("ash_last_battle")
            sfx(.gun(14), 1.4, at: player.pos)
            onToast?("The Ashguard's last army is broken")            // P318: the hatch console's lamp lights (AshSabotage.swift)
            bunkerSecond(0)
        } else {
            lw.breather = AshFinal.breather
            onToast?("Wave \(ashWave) beaten. Next, \(AshFinal.waveNames[ashWave]): \(Int(AshFinal.breather)) seconds")
        }
    }

    // Spawns a wave 45-70 blocks out on open vault floor, every unit already hunting the player. False when no ground
    // was found (tried again next second).
    @discardableResult
    func spawnAshWave(_ n: Int) -> Bool {
        guard n >= 0 && n < AshFinal.waves.count else { return false }
        let here = player.pos
        let near = mobs.mobs.reduce(0) { $0 + ($1.faction == Faction.ashguard.rawValue && $1.health > 0 && simd_length_squared($1.pos - here) < 96 * 96 ? 1 : 0) }
        var room = max(4, AshFinal.cap - near)
        let base = Rand.float(in: 0..<(2 * .pi))
        var made: [Mob] = []
        for (i, key) in AshFinal.waves[n].enumerated() {
            let vehicle = key.hasPrefix("ash_")
            if !vehicle && room <= 0 { continue }
            guard let p = ashWaveGround(angle: base + Float(i) * 0.35, wide: vehicle) else { continue }
            guard let m = Mob.structureMob(key + "@ash", at: p) else { continue }
            m.persistent = false                       // a wave isn't saved: the wave comes again after a reload
            m.waveUnit = true                          // and doesn't despawn while the player is in the vault
            let d = here - p
            m.yaw = -atan2f(d.x, -d.z)
            m.soldierBrain.turret = m.yaw
            m.aggro = true
            m.soldierBrain.lastSeen = player.eye
            m.soldierBrain.seenAgo = 0
            m.lockTime = 60
            mobs.mobs.append(m)
            made.append(m)
            if !vehicle { room -= 1 }
        }
        guard !made.isEmpty else { return false }
        lastWar.wave = made
        lastWar.spawnedWaves += 1
        return true
    }

    // Open loaded vault floor round the player at 30-66 blocks: on the floor itself (not a roof or a trench), off the
    // lines and out of the player's sight when it can be (the first pass); any open floor otherwise.
    func ashWaveGround(angle: Float, wide: Bool) -> V3? {
        let c = player.pos
        let dg = world.gen as? DeepGen
        for hidden in [true, false] {
            for r in [58, 48, 66, 38, 30] as [Float] {
                for k in 0..<6 {
                    let a = angle + Float(k) * 1.05
                    let x = Int(floor(c.x + sinf(a) * r)), z = Int(floor(c.z - cosf(a) * r))
                    guard world.isLoaded(x, z), AshLines.cut(x, z) == .none, AshLines.distance(x, z) > 2 else { continue }
                    let f = dg?.floorY(x, z) ?? DeepGen.floorBase
                    for y in [f + 1, f + 2, f, f + 3] where Blocks.collide[Int(world.block(x, y - 1, z))] && open(x, y, z, wide) {
                        let p = V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)
                        if hidden && world.canSee(player.eye, p + V3(0, 1.5, 0)) { break }
                        return p
                    }
                }
            }
        }
        return nil
    }

    private func open(_ x: Int, _ y: Int, _ z: Int, _ wide: Bool) -> Bool {
        let r = wide ? 2 : 0
        for dz in -r...r { for dx in -r...r {
            for dy in 0..<(wide ? 4 : 2) where world.block(x + dx, y + dy, z + dz) != AIR { return false }
        } }
        return true
    }

    // The bunker open: the hatch stays open, and the Chancellor waits in his study for the player to come down.
    private func bunkerSecond(_ s: Float) {
        let lw = lastWar
        guard AshFinal.inside(player.pos) else { lw.inBunker = 0; return }
        lw.inBunker += s
        guard lw.inBunker >= 3, !ashVictory, !mobs.mobs.contains(where: { $0.kind == .ashChancellor && $0.health > 0 }) else { return }
        let at = AshFinal.chancellorAt
        guard world.isLoaded(Int(at.x), Int(at.z)) else { return }
        guard let m = Mob.structureMob("ash_chancellor@ash", at: at) else { return }
        m.yaw = 0
        m.soldierBrain.turret = 0
        mobs.mobs.append(m)
        // His study guard: two heavies by the desk.
        for dx in [-3, 3] as [Float] {
            if let g = Mob.structureMob("soldier_ironclad@ash", at: at + V3(dx, 0, -2)) { mobs.mobs.append(g) }
        }
        sfx(.gun(10), 1.2, at: at)
        onToast?("The Ash Chancellor waits in his study at the end of the bunker")
    }

    // At half health the Chancellor's bunker shakes (the citadel above is burning): dust, a rumble, the lamps flicker.
    func ashBunkerQuake(at p: V3) {
        addShake(0.75)
        sfx(.explodeLarge, 0.9, at: p + V3(0, 6, 0))
        for _ in 0..<24 {
            particles.smoke(at: player.pos + V3(Rand.float(in: -5...5), Rand.float(in: 2...3.5), Rand.float(in: -5...5)))
        }
        onToast?("The bunker shakes. Dust pours from the ceiling")
    }
}

extension Mob {
    // The Chancellor: an officer with a machine pistol; at two thirds and one third he calls his guard, and at half
    // health the bunker shakes.
    func ashChancellorAI(_ dt: Float, _ g: Game, dist: Float, canTarget: Bool) -> Float {
        let b = soldierBrain
        if b.clock == 0 {
            let f = Float(health) / Float(spec.health)
            b.ashCalls = f < 0.34 ? 3 : (f < 0.5 ? 2 : (f < 0.67 ? 1 : 0))
        }
        let sp = soldierAI(dt, g, dist: dist, canTarget: canTarget)
        guard canTarget, aggro, health > 0 else { return sp }
        let frac = Float(health) / Float(spec.health)
        if b.ashCalls == 0 && frac < 0.67 { b.ashCalls = 1; ashCallGuard(g) }
        else if b.ashCalls == 1 && frac < 0.5 { b.ashCalls = 2; g.ashBunkerQuake(at: pos) }
        else if b.ashCalls == 2 && frac < 0.34 { b.ashCalls = 3; ashCallGuard(g) }
        return sp
    }
}
