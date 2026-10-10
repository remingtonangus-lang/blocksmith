import Foundation
import simd

// Boreal Station infiltration (an operation per station, run once a second from basesTick after the alarm):
//   enter     stepping inside the fence starts the operation (a toast lists the three objectives; the HUD bar
//             under the boss bars shows the next one)
//   codes     use a command console in the control room (north wing) and stay within reach while the uplink codes
//             copy (8 s); stepping away pauses the copy, and while the alarm sounds the uplink is locked
//   sabotage  use the generator in the generator hall (south-east room) to set a charge on a 45 s fuse; it blows
//             the machine (a real explosion, so the station hears it)
//   extract   with the codes copied and the charge set, get out past the fence
// Stealth against noise: if the alarm never sounded before the extraction the operation is rated silent and pays
// the better reward (a Farsight Rifle and rounds, more money, the "Nobody Was Here" challenge); a loud run still
// pays, less. While the alarm sounds the garrison opens the bulkhead doors (Mob.stationDoors: no room keeps it
// shut in) and squads come down the stairwell from the blockhouse every 25 s, three at most.
// Operations are saved in world.json ("stationOps"): a finished station stays finished.
struct StationOp: Codable {
    var key: String
    var cx: Int, cz: Int, S: Int
    var stage = 0                     // 0 not started, 1 under way, 2 done
    var codes: Float = 0              // copy progress, 1 = copied
    var copyAt: [Float]? = nil        // the console being copied from (nil: not copying)
    var fuse: Float? = nil            // seconds left on the charge
    var planted = false
    var blown = false
    var loud = false                  // the alarm sounded during the operation
    var alarmWas = false
    var waves = 0
    var waveT: Float = 0
    var silent: Bool? = nil           // the rating, once done
    var doneClock: Double? = nil

    var F: Int { S - BorealStation.depth }
    var console: V3 { V3(Float(cx) + 0.5, Float(F + 1), Float(cz - 21) + 0.5) }
    var generator: V3 { V3(Float(cx + 20), Float(F + 2), Float(cz + 16) + 0.5) }
    var stairFoot: V3 { V3(Float(cx - 5) + 0.5, Float(F + 1), Float(cz + 19) + 0.5) }

    // Fields added later default when missing (see BaseRecord).
    init(key: String, cx: Int, cz: Int, S: Int) { self.key = key; self.cx = cx; self.cz = cz; self.S = S }
    init(from dec: Decoder) throws {
        let c = try dec.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        cx = try c.decode(Int.self, forKey: .cx); cz = try c.decode(Int.self, forKey: .cz); S = try c.decode(Int.self, forKey: .S)
        stage = (try? c.decodeIfPresent(Int.self, forKey: .stage)) ?? 0
        codes = (try? c.decodeIfPresent(Float.self, forKey: .codes)) ?? 0
        copyAt = try? c.decodeIfPresent([Float].self, forKey: .copyAt)
        fuse = try? c.decodeIfPresent(Float.self, forKey: .fuse)
        planted = (try? c.decodeIfPresent(Bool.self, forKey: .planted)) ?? false
        blown = (try? c.decodeIfPresent(Bool.self, forKey: .blown)) ?? false
        loud = (try? c.decodeIfPresent(Bool.self, forKey: .loud)) ?? false
        alarmWas = (try? c.decodeIfPresent(Bool.self, forKey: .alarmWas)) ?? false
        waves = (try? c.decodeIfPresent(Int.self, forKey: .waves)) ?? 0
        waveT = (try? c.decodeIfPresent(Float.self, forKey: .waveT)) ?? 0
        silent = try? c.decodeIfPresent(Bool.self, forKey: .silent)
        doneClock = nil
    }
}

extension BorealStation {
    static let copySeconds: Float = 8
    static let fuseSeconds: Float = 45
    static let waveEvery: Float = 25
    static let maxWaves = 3
    static let copyReach: Float = 4

    // The generator machine (BorealStation.build: hazard base and steel body, x 18...21, z 13...19, rows 1...4).
    static func isGenerator(_ dx: Int, _ ly: Int, _ dz: Int) -> Bool { dx >= 18 && dx <= 21 && dz >= 13 && dz <= 19 && ly >= 1 && ly <= 4 }
    static func inControlRoom(_ dx: Int, _ dz: Int) -> Bool { abs(dx) <= 6 && dz >= -24 && dz <= -16 }
    // Past the fence (the extraction line): a few blocks outside the yard, on or above the surface.
    static func outside(_ op: StationOp, _ p: V3) -> Bool {
        max(abs(p.x - Float(op.cx)), abs(p.z - Float(op.cz))) > Float(yard + 3) && p.y > Float(op.S - 4)
    }
}

extension Game {
    var stationOps: [String: StationOp] {
        get { bases.boreal.ops }
        set { bases.boreal.ops = newValue }
    }

    // The operation for the station whose plan holds this point (made on first use).
    func stationOp(near p: V3) -> StationOp? {
        guard world.dim == .overworld, let sc = world.gen.structures,
              let s = sc.nearest(BorealStation.kind, x: Int(p.x), z: Int(p.z), maxRegions: 1),
              let lv = BorealStation.levels(world, s) else { return nil }
        let cx = (s.min.x + s.max.x) / 2, cz = (s.min.z + s.max.z) / 2
        let key = "boreal:\(cx),\(cz)"
        if let o = stationOps[key] { return o }
        guard abs(p.x - Float(cx)) < Float(BorealStation.yard + 40), abs(p.z - Float(cz)) < Float(BorealStation.yard + 40) else { return nil }
        let o = StationOp(key: key, cx: cx, cz: cz, S: lv.S)
        stationOps[key] = o
        return o
    }

    private func seatPositions() -> [V3] { (0..<max(1, coop.seatCount)).map { coop.seatPlayer($0, self).pos } }

    private func startOp(_ op: inout StationOp) {
        guard op.stage == 0 else { return }
        op.stage = 1
        bases.boreal.log.append("\(op.key) operation started")
        onToast?("Station operation: copy the uplink codes in the control room, sabotage the generator, then get out")
    }

    // Use on a block (Game.interact, before guns and doors): a control-room console starts the copy, the generator
    // takes the charge. True when the use was taken.
    func stationUse(_ hit: IVec3) -> Bool {
        let hp = V3(Float(hit.x) + 0.5, Float(hit.y) + 0.5, Float(hit.z) + 0.5)
        guard var op = stationOp(near: hp) else { return false }
        let dx = hit.x - op.cx, dz = hit.z - op.cz, ly = hit.y - op.F
        let k = Blocks.key(Blocks.groupBase[Int(world.block(hit.x, hit.y, hit.z))])
        let isConsole = k == "command_console" && BorealStation.inControlRoom(dx, dz) && ly >= 1 && ly <= 4
        let isGen = BorealStation.isGenerator(dx, ly, dz)
        guard isConsole || isGen else { return false }
        defer { stationOps[op.key] = op }
        if op.stage == 2 { onToast?(isConsole ? "The uplink codes are already out" : "This station's operation is done"); return true }
        startOp(&op)
        if isConsole {
            if op.codes >= 1 { onToast?("Uplink codes already copied"); return true }
            if bases.boreal.sites[op.key]?.on == true { sfx(.dispenseFail, 0.8, at: hp); onToast?("Uplink locked down while the alarm sounds"); return true }
            op.copyAt = [hp.x, hp.y, hp.z]
            sfx(.click, 0.9, at: hp)
            onToast?(op.codes > 0 ? "Copy resumed: \(Int(op.codes * 100))%" : "Copying the uplink codes: stay at the console")
            bases.boreal.log.append("\(op.key) copy started")
        } else {
            if op.planted { onToast?(op.blown ? "The generator is already wrecked" : "The charge is already set"); return true }
            op.planted = true
            op.fuse = BorealStation.fuseSeconds
            sfx(.tntFuse, 1, at: hp)
            onToast?("Charge set on the generator: \(Int(BorealStation.fuseSeconds)) s. Get clear!")
            bases.boreal.log.append("\(op.key) charge set")
        }
        return true
    }

    // Once a second, from basesTick (after borealAlarmTick, so the alarm state is this second's).
    func stationOpsTick(_ b: BaseWatch, _ dt: Float) {
        let st = b.boreal
        let players = seatPositions()
        // Every station with a live alarm site has an operation; a player at the fence starts it.
        for (key, site) in st.sites where st.ops[key] == nil {
            st.ops[key] = StationOp(key: key, cx: site.cx, cz: site.cz, S: site.S)
        }
        for key in Array(st.ops.keys) {
            guard var op = st.ops[key], world.isLoaded(op.cx, op.cz) else { continue }
            defer { st.ops[key] = op }
            let alarm = st.sites[key]?.on == true
            let inside = players.filter { BorealStation.insideSite(BorealAlarmState.Site(cx: op.cx, cz: op.cz, S: op.S), $0) }
            if op.stage == 0 && !inside.isEmpty { startOp(&op) }

            // The charge runs whatever the stage (a player may be long gone when it blows).
            if var f = op.fuse {
                f -= dt
                if f <= 10 && f > 0 { sfx(.click, 1, at: op.generator) }
                if f <= 0 {
                    op.fuse = nil
                    op.blown = true
                    st.log.append("\(key) generator blown")
                    Explosion.explode(at: op.generator, power: 4, game: self, decay: true)
                    stationWreckGenerator(op)
                    sfx(.explodeLarge, 1.2, at: op.generator)
                    if players.contains(where: { simd_length($0 - op.generator) < 160 }) { onToast?("The station's generator goes up!") }
                } else { op.fuse = f }
            }
            // Roused soldiers work the bulkhead doors (Mob.opensDoors), so no room keeps them shut in.
            if alarm {
                let site = BorealAlarmState.Site(cx: op.cx, cz: op.cz, S: op.S)
                for m in mobs.mobs where m.kind.steelhold && m.kind != .deckGun && m.health > 0 && BorealStation.insideSite(site, m.pos) { m.stationDoors = true }
            }
            guard op.stage == 1 else { continue }

            // Alarm consequences: a loud rating, the garrison through the doors, squads from the blockhouse.
            if alarm {
                op.loud = true
                if !op.alarmWas {
                    st.log.append("\(key) alarm during the operation")
                    if !inside.isEmpty { onToast?("Alarm! The garrison is coming through the bulkheads") }
                    op.waveT = 0
                }
                if !inside.isEmpty && op.waves < BorealStation.maxWaves {
                    op.waveT += dt
                    if op.waveT >= BorealStation.waveEvery {
                        op.waveT = 0
                        op.waves += 1
                        stationReinforce(op, toward: inside[0])
                        st.log.append("\(key) reinforcements \(op.waves)")
                        onToast?("Reinforcements coming down the stairwell")
                    }
                }
            }
            op.alarmWas = alarm

            // The copy: progresses while a player stays at the console and the uplink isn't locked.
            if let c = op.copyAt, op.codes < 1 {
                let at = V3(c[0], c[1], c[2])
                let near = players.contains { simd_length($0 + V3(0, 1, 0) - at) <= BorealStation.copyReach + 0.5 }
                if !near {
                    op.copyAt = nil
                    onToast?("Copy interrupted at \(Int(op.codes * 100))%: go back to the console")
                    st.log.append("\(key) copy interrupted")
                } else if !alarm {
                    op.codes = min(1, op.codes + dt / BorealStation.copySeconds)
                    if op.codes >= 1 {
                        op.copyAt = nil
                        sfx(.xp, 1, at: at)
                        onToast?(op.planted ? "Uplink codes copied. Now get out!" : "Uplink codes copied. Next: the generator")
                        st.log.append("\(key) codes copied")
                    } else { sfx(.click, 0.5, at: at) }
                }
            }

            // Extraction: both jobs done and every player past the fence.
            if op.codes >= 1 && op.planted && players.allSatisfy({ BorealStation.outside(op, $0) }) {
                op.stage = 2
                op.silent = !op.loud
                op.doneClock = clock
                stationReward(op)
                st.log.append("\(key) extracted \(op.loud ? "loud" : "silent")")
            }
        }
    }

    // The machine itself is steel plating a blast can't move: the charge tears it apart from inside (most of its
    // body gone, the rest left standing as a burnt-out shell).
    func stationWreckGenerator(_ op: StationOp) {
        let fire = Blocks.has("fire") ? Blocks.id("fire") : AIR
        for dz in 13...19 { for dx in 18...21 { for ly in 1...4 {
            let x = op.cx + dx, y = op.F + ly, z = op.cz + dz
            guard world.block(x, y, z) != AIR, hashf(dx, ly, dz, 0xB0E5) < 0.6 else { continue }
            world.setBlock(x, y, z, ly == 1 && hashf(dx, 0, dz, 0xF1E) < 0.3 ? fire : AIR)
        } } }
    }

    // A squad of three down the stairwell: they spawn at its foot and make for the player.
    func stationReinforce(_ op: StationOp, toward target: V3) {
        let kinds: [MobKind] = [.soldierTrooper, .soldierRecruit, .soldierRecruit]
        for (i, k) in kinds.enumerated() {
            let p = world.freeSpawn(op.stairFoot + V3(Float(i % 2) - 0.5, 0, Float(-i)))
            let m = Mob(Soldier.garrison(k, at: p), at: p)
            m.persistent = true
            m.home = p
            m.aggro = true
            m.stationDoors = true
            let br = m.soldierBrain
            br.ready = true
            br.lastSeen = target; br.seenAgo = min(br.seenAgo, 2)
            m.lockTime = max(m.lockTime, 20)
            mobs.mobs.append(m)
        }
        mobs.rebuildIndex()
    }

    func stationReward(_ op: StationOp) {
        let silent = op.silent ?? false
        var got: [ItemStack] = []
        func give(_ k: String, _ n: Int) { if Items.has(k) { got.append(ItemStack(Items.id(k), n)) } }
        if silent { give("gun_sniper", 1); give("heavy_rounds", 24) } else { give("rifle_rounds", 90) }
        give("golden_apple", silent ? 2 : 1)
        for s in got { let rest = inventory.add(s); if !rest.isEmpty { dropItem(rest, thrown: false) } }
        money += silent ? 25000 : 10000
        sfx(.levelUp, 1)
        achieve("station_op")
        if silent { achieve("station_silent") }
        onToast?(silent ? "Operation complete, silent: Farsight Rifle, rounds and $250" : "Operation complete, loud: rounds and $100")
    }

    // The HUD bar (Renderer boss-bar row): the next objective, the copy, or the fuse; red while the alarm sounds.
    func stationOpBar() -> (String, Float, V4)? {
        let p = player.pos
        guard world.dim == .overworld else { return nil }
        for op in stationOps.values {
            let near = max(abs(p.x - Float(op.cx)), abs(p.z - Float(op.cz))) < Float(BorealStation.yard + 40)
            guard near else { continue }
            let alarm = bases.boreal.sites[op.key]?.on == true
            let col = alarm ? V4(0.9, 0.25, 0.15, 1) : V4(0.45, 0.72, 0.95, 1)
            if op.stage == 2 {
                guard let d = op.doneClock, clock - d < 12 else { continue }
                return ((op.silent ?? false) ? "Operation complete - silent" : "Operation complete - loud", 1, V4(0.55, 0.85, 0.45, 1))
            }
            // Roused soldiers work the bulkhead doors (Mob.opensDoors), so no room keeps them shut in.
            if alarm {
                let site = BorealAlarmState.Site(cx: op.cx, cz: op.cz, S: op.S)
                for m in mobs.mobs where m.kind.steelhold && m.kind != .deckGun && m.health > 0 && BorealStation.insideSite(site, m.pos) { m.stationDoors = true }
            }
            guard op.stage == 1 else { continue }
            let tail = alarm ? " - ALARM" : ""
            if let f = op.fuse, op.codes >= 1 || f < 15 {
                return ("Charge \(Int(f.rounded(.up))) s - get out\(tail)", f / BorealStation.fuseSeconds, V4(0.95, 0.55, 0.15, 1))
            }
            if op.copyAt != nil && op.codes < 1 {
                return ((alarm ? "Uplink locked" : "Copying uplink codes \(Int(op.codes * 100))%") + tail, op.codes, col)
            }
            let done = (op.codes >= 1 ? 1 : 0) + (op.planted ? 1 : 0)
            let next = op.codes < 1 ? "Copy the uplink codes (control room)" : (!op.planted ? "Sabotage the generator" : "Extract: get past the fence")
            return ("\(next)\(tail)", Float(done) / 3, col)
        }
        return nil
    }
}
