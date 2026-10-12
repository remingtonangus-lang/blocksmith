import Foundation
import simd

// Greywall Command alarms, reinforcements and the leash (backlog A1b).
//   alarm          a hostile noise inside a base's walls (gunshots, blasts: Game.baseNoise), or one of its soldiers who
//                  sees a player inside, sets the alarm off: every red alarm lamp in the base lights, a klaxon blares
//                  from the keep and the gate, and every soldier of the base stands to and turns on the source. It
//                  stands down 45 s after the last noise or fight, and the lamps go dark again.
//   panels         alarm panels in the keep, the towers and the comms room. A base with every panel broken can't call
//                  for help: the alarm still sounds inside, but no reinforcements come.
//   reinforcements fortresses and command fortresses: while the alarm is up and a panel stands, a squad of three
//                  marches in at the gate every 45 s, at most four squads an alarm.
//   leash          a base's soldiers chase a player anywhere inside the walls (plus a few blocks), stop at the leash
//                  and hold there firing, and walk back in if anything carried them out (Mob.leash, applied in
//                  soldierAI).
// In memory only, like the Boreal Station alarm: a reload finds the base quiet (its lamps saved dark).
final class GreywallAlarmState {
    struct Site {
        var cx: Int, cz: Int, S: Int, tier: Greywall.Tier
        var on = false, quiet: Float = 0, blare: Float = 0, src = V3(0, 0, 0)
        var lamps: [IVec3] = [], panels: [IVec3] = []
        var lampsLit = false
        var squadT: Float = 0, squads = 0
        var panelsDown = false
        var consoles: [IVec3] = [], turrets: [IVec3] = [], flags: [IVec3] = []
        var hold: Float = 0                         // seconds a player has held the command console of a cleared base
    }
    var taken: Set<String> = []                     // bases the player has taken (saved: Effects.swift "greywallTaken")
    static let holdFor: Float = 10
    var sites: [String: Site] = [:]
    struct Gun { var windup: Float = 0, shots = 0, gap: Float = 0, cool: Float = 0, look: Float = 0, sees = false, hits = 0 }
    var guns: [IVec3: Gun] = [:]                    // wall turrets near a player (in memory: a reload repairs no damage, the block keeps it)
    var panelHits: [IVec3: Int] = [:]
    static let turretRange: Float = 40, turretWind: Float = 0.9, turretBurst = 3, turretCool: Float = 1.6, turretHits = 6
    var log: [String] = []
    static let blareEvery: Float = 4
    static let standDown: Float = 45
    static let squadEvery: Float = 45
    static let maxSquads = 4
    static let leashPad: Float = 4
    static let turretIds: (BlockID, BlockID) = (Blocks.id("wall_turret"), Blocks.id("wall_turret_damaged"))
    static let turretDirs = [V3(0, 0, -1), V3(0, 0, 1), V3(-1, 0, 0), V3(1, 0, 0)]
}

extension Greywall {
    static func inside(_ s: GreywallAlarmState.Site, _ p: V3, pad: Float = 1) -> Bool {
        let h = Float(s.tier.half) + pad
        return abs(p.x - Float(s.cx) - 0.5) < h && abs(p.z - Float(s.cz) - 0.5) < h && p.y > Float(s.S - 10) && p.y < Float(s.S + s.tier.wallH + 20)
    }
}

extension Game {
    var greywallAlarm: GreywallAlarmState { bases.greywall }

    // Finds the alarm lamps and panels of a base once (its whole footprint loaded), for the switch and the count.
    private func greywallScan(_ site: inout GreywallAlarmState.Site) -> Bool { Greywall.scan(world, &site) }
}

extension Greywall {
    // (also run on generated bases by GreywallTests: what the alarm, capture and turrets will find)
    static func scan(_ world: World, _ site: inout GreywallAlarmState.Site) -> Bool {
        let e = site.tier.half + 2
        // (every chunk of the footprint, not just the corners: a middle one not in yet would read as air)
        for cz in floorDiv(site.cz - e, CS)...floorDiv(site.cz + e, CS) { for cx in floorDiv(site.cx - e, CS)...floorDiv(site.cx + e, CS)
            where !world.isLoaded(cx * CS, cz * CS) { return false } }
        let lampOff = Blocks.groupBase[Int(Blocks.id("alarm_lamp"))], lampOn = Blocks.groupBase[Int(Blocks.id("alarm_lamp_lit"))]
        let panel = Blocks.groupBase[Int(Blocks.id("alarm_panel"))]
        let console = Blocks.has("command_console") ? Blocks.groupBase[Int(Blocks.id("command_console"))] : BlockID.max
        let gun = Blocks.groupBase[Int(Blocks.id("wall_turret"))], gunHurt = Blocks.groupBase[Int(Blocks.id("wall_turret_damaged"))]
        let flag = Blocks.id("greywall_flag"), mine = Blocks.id("taken_flag")
        for z in (site.cz - e)...(site.cz + e) { for x in (site.cx - e)...(site.cx + e) {
            for y in (site.S - 8)...(site.S + site.tier.wallH + 12) {
                let g = Blocks.groupBase[Int(world.block(x, y, z))]
                if g == lampOff || g == lampOn { site.lamps.append(IVec3(x, y, z)) } else if g == panel { site.panels.append(IVec3(x, y, z)) }
                else if g == console { site.consoles.append(IVec3(x, y, z)) }
                else if g == gun || g == gunHurt { site.turrets.append(IVec3(x, y, z)) }
                else if g == flag || g == mine { site.flags.append(IVec3(x, y, z)) }
            }
        } }
        return true
    }
}

extension Game {
    // Lights or darkens every lamp still standing (same facing: the lit lamps are the dark ones' twins).
    func greywallLamps(_ site: inout GreywallAlarmState.Site, lit: Bool) {
        let off = Blocks.id("alarm_lamp"), on = Blocks.id("alarm_lamp_lit")
        for p in site.lamps where world.isLoaded(p.x, p.z) {
            let b = world.block(p.x, p.y, p.z)
            if !lit && b >= on && b < on + 4 { world.setBlock(p.x, p.y, p.z, off + (b - on)) }
            if lit && b >= off && b < off + 4 { world.setBlock(p.x, p.y, p.z, on + (b - off)) }
        }
        site.lampsLit = lit
    }

    func greywallPanelsStanding(_ site: GreywallAlarmState.Site) -> Int {
        let panel = Blocks.groupBase[Int(Blocks.id("alarm_panel"))]
        return site.panels.filter { !world.isLoaded($0.x, $0.z) || Blocks.groupBase[Int(world.block($0.x, $0.y, $0.z))] == panel }.count
    }

    // Once a second from basesTick, with that second's noises.
    func greywallAlarmTick(_ b: BaseWatch, _ dt: Float) {
        let st = b.greywall
        guard let sc = world.gen.structures else { return }
        let players = (0..<max(1, coop.seatCount)).map { coop.seatPlayer($0, self).pos }
        for pp in players {
            guard let s = sc.nearest(Greywall.kind, x: Int(pp.x), z: Int(pp.z), maxRegions: 1) else { continue }
            let (cx, cz) = Greywall.centre(s)
            let key = "greywall:\(cx),\(cz)"
            guard st.sites[key] == nil, simd_length(V2(pp.x - Float(cx), pp.z - Float(cz))) < 160 else { continue }
            var site = GreywallAlarmState.Site(cx: cx, cz: cz, S: Greywall.yardY(s), tier: Greywall.Tier.of(s))
            if greywallScan(&site) {
                if site.lamps.contains(where: { world.block($0.x, $0.y, $0.z) >= Blocks.id("alarm_lamp_lit") && world.block($0.x, $0.y, $0.z) < Blocks.id("alarm_lamp_lit") + 4 }) {
                    greywallLamps(&site, lit: false)           // saved mid-alarm: quiet again
                }
                st.sites[key] = site
            }
        }
        for key in Array(st.sites.keys) {
            guard var site = st.sites[key] else { continue }
            // Forget a base nobody is near (its lamps stay as they are: dark unless the alarm was up).
            if !players.contains(where: { simd_length(V2($0.x - Float(site.cx), $0.z - Float(site.cz))) < 200 }) {
                if site.lampsLit { greywallLamps(&site, lit: false) }
                st.sites[key] = nil; continue
            }
            let mine: (Mob) -> Bool = { m in
                m.faction == Faction.greywall.rawValue && m.kind != .deckGun && m.health > 0 && Greywall.inside(site, m.pos, pad: 8)
            }
            // A base the player has taken: quiet for good. One not yet taken: cleared and its console held, it is theirs.
            if st.taken.contains(key) { st.sites[key] = site; continue }
            if greywallCaptureTick(&site, key, players, dt) { st.sites[key] = site; continue }
            var trigger: V3? = nil
            for n in b.noises where n.hostile && Greywall.inside(site, n.pos) { trigger = n.pos }
            // (a net that found out a spoofer: every base of it sounds as soon as a player is inside, C6 RadioSpoof.swift)
            if survival, trigger == nil, radio.alerted(.greywall, clock), let p = players.first(where: { Greywall.inside(site, $0) }) { trigger = p }
            if survival, trigger == nil, let p = players.first(where: { Greywall.inside(site, $0) }) {
                if mobs.mobs.contains(where: { mine($0) && $0.aggro && $0.troopClass != .specOps && ($0.brain?.sees ?? false) }) { trigger = p }    // (Spec Ops hunt quietly)
            }
            var fresh = false
            if let t = trigger {
                site.quiet = 0
                fresh = simd_length(t - site.src) > 4 || !site.on
                site.src = t
                if !site.on {
                    site.on = true; site.blare = 0; site.squadT = GreywallAlarmState.squadEvery * 0.5; site.squads = 0
                    greywallLamps(&site, lit: true)
                    st.log.append("\(key) alarm on at \(Int(t.x)),\(Int(t.y)),\(Int(t.z))")
                    onToast?("The \(site.tier.name) is sounding the alarm!")
                }
            } else if site.on {
                site.quiet += dt
                let fighting = mobs.mobs.contains { mine($0) && $0.aggro && $0.troopClass != .specOps && ($0.brain?.sees ?? false) }    // (Spec Ops hunt quietly)
                if site.quiet > GreywallAlarmState.standDown && !fighting {
                    site.on = false
                    greywallLamps(&site, lit: false)
                    st.log.append("\(key) alarm off")
                }
            }
            if site.on {
                for m in mobs.mobs where mine(m) && m.kind != .deckGun {
                    let br = m.soldierBrain
                    br.ready = true
                    if !m.aggro { m.aggro = true; br.react = max(br.react, 0.5) }
                    if fresh && !br.sees { br.lastSeen = site.src; br.seenAgo = min(br.seenAgo, 2) }
                    m.lockTime = max(m.lockTime, 20)
                }
                // The klaxon from the keep or the gate, whichever is nearer a player.
                site.blare -= dt
                if site.blare <= 0 {
                    site.blare = GreywallAlarmState.blareEvery
                    let speakers = [V3(Float(site.cx) + 0.5, Float(site.S + 5), Float(site.cz + site.tier.keepC) + 0.5),
                                    V3(Float(site.cx) + 0.5, Float(site.S + 5), Float(site.cz + site.tier.half - 2) + 0.5)]
                    func dist(_ q: V3) -> Float { players.map { simd_length($0 - q) }.min() ?? .infinity }
                    if let sp = speakers.min(by: { dist($0) < dist($1) }), dist(sp) < 96 { sfx(.gun(10), 1.2, at: sp) }
                }
                // Reinforcements: a squad at the gate while a panel stands (fortress and up).
                let standing = greywallPanelsStanding(site)
                if standing == 0 && !site.panelsDown && !site.panels.isEmpty {
                    site.panelsDown = true
                    st.log.append("\(key) panels down")
                    onToast?("Every alarm panel is down: the \(site.tier.name) can't call for help")
                }
                // (and never past the base's own strength plus 12: squads stay, so alarm after alarm can't pile them up)
                if site.tier.rawValue >= 2 && standing > 0 && site.squads < GreywallAlarmState.maxSquads
                    && greywallStrength(site) < site.tier.troops + 12 {
                    site.squadT -= dt
                    if site.squadT <= 0 {
                        site.squadT = GreywallAlarmState.squadEvery
                        site.squads += 1
                        greywallSquad(site)
                        st.log.append("\(key) squad \(site.squads)")
                    }
                }
            }
            st.sites[key] = site
        }
    }

    // Three soldiers march in through the gate (from just outside it) and join the fight.
    func greywallSquad(_ site: GreywallAlarmState.Site) {
        let H = site.tier.half
        let kinds = ["soldier_trooper", "soldier_trooper", site.squadsKind]
        for (i, k) in kinds.enumerated() {
            let p = V3(Float(site.cx + i - 1) + 0.5, Float(site.S + 1), Float(site.cz + H + 2) + 0.5)
            guard let m = Mob.structureMob("\(k)@grey\(Greywall.leashTag(site.cx, site.cz, site.tier))", at: p) else { continue }
            m.aggro = true
            m.soldierBrain.ready = true
            m.soldierBrain.lastSeen = site.src; m.soldierBrain.seenAgo = 0
            m.lockTime = 20
            mobs.mobs.append(m)
        }
        if let p = players().first, simd_length(p - V3(Float(site.cx), p.y, Float(site.cz))) < 120 {
            onToast?("Greywall reinforcements at the gate")
        }
    }

    // The live and parked soldiers leashed to a base.
    func greywallStrength(_ site: GreywallAlarmState.Site) -> Int {
        let L = V3(Float(site.cx), Float(site.cz), Float(site.tier.half))
        let live = mobs.mobs.reduce(0) { $0 + ($1.leash == L && $1.health > 0 ? 1 : 0) }
        let parked = mobs.stored.values.reduce(0) { n, rs in n + rs.reduce(0) { m, r in
            m + (r.extra?["lsx"] == L.x && r.extra?["lsz"] == L.y && r.hp > 0 ? 1 : 0) } }
        return live + parked
    }

    private func players() -> [V3] { (0..<max(1, coop.seatCount)).map { coop.seatPlayer($0, self).pos } }
}

extension GreywallAlarmState.Site {
    var squadsKind: String { squads % 2 == 0 ? "soldier_ironclad" : "soldier_marksman" }
}

extension Greywall {
    // The structure-mob suffix that leashes a soldier to its base: "~cx,cz,half".
    static func leashTag(_ cx: Int, _ cz: Int, _ t: Tier) -> String { "~\(cx),\(cz),\(t.half)" }
}

extension Mob {
    // Keeps a leashed soldier (a Greywall base's) within its base's walls plus the pad: a step that would take it out is
    // held (it stands at the wall and keeps shooting); one already out walks back to the yard. A sighting outside the
    // leash isn't chased.
    func applyLeash(_ speed: Float) -> Float {
        guard let L = leash else { return speed }
        let h = L.z + GreywallAlarmState.leashPad
        func out(_ p: V3) -> Bool { abs(p.x - L.x) > h || abs(p.z - L.y) > h }
        let b = soldierBrain
        if let ls = b.lastSeen, out(ls) {
            b.lastSeen = V3(max(L.x - L.z, min(L.x + L.z, ls.x)), ls.y, max(L.y - L.z, min(L.y + L.z, ls.z)))
        }
        if out(pos) {
            // Back in through the gate (south wall): round the outside of the wall to the front first, so the wall doesn't
            // pin it, then along the front to the gate and in.
            let H = L.z
            let goal: V3
            if pos.z >= L.y + H { goal = abs(pos.x - L.x) > 1.5 ? V3(L.x, pos.y, pos.z) : V3(L.x, pos.y, L.y) }
            else if abs(pos.x - L.x) > H { goal = V3(pos.x, pos.y, L.y + H + 3) }
            else { goal = V3(L.x + (pos.x >= L.x ? 1 : -1) * (H + 3), pos.y, pos.z) }
            face(goal)
            strafe = 0
            return spec.speed * 0.8
        }
        let right = V3(cosf(yaw), 0, -sinf(yaw))
        let next = pos + forward * speed * 0.6 + right * strafe * 0.6
        if out(next) { strafe = 0; return 0 }
        return speed
    }
}

// MARK: Taking a base (A1c)

extension Game {
    // Every soldier of the base down (a player inside, so its chunks and garrison are loaded), then a player stands at
    // a command console for 10 s: the base is theirs. Returns true when it was taken this second.
    func greywallCaptureTick(_ site: inout GreywallAlarmState.Site, _ key: String, _ players: [V3], _ dt: Float) -> Bool {
        guard survival, players.contains(where: { Greywall.inside(site, $0) }) else { site.hold = 0; return false }
        let s = site
        let garrison = mobs.mobs.contains { m in
            m.faction == Faction.greywall.rawValue && m.health > 0 && m.kind != .deckGun && Greywall.inside(s, m.pos, pad: 8)
        }
        // (soldiers parked in chunks outside a small render distance count too: they come back when the player walks over)
        let parked = mobs.stored.values.contains { rs in rs.contains { r in
            guard let f = r.extra?["fac"], Int(f) == Faction.greywall.rawValue, r.hp > 0, r.k != MobKind.deckGun.key, r.p.count == 3 else { return false }
            return Greywall.inside(s, V3(r.p[0], r.p[1], r.p[2]), pad: 8)
        } }
        guard !garrison && !parked else { site.hold = 0; return false }
        let atConsole = players.contains { p in s.consoles.contains { simd_length(V3(Float($0.x) + 0.5, Float($0.y), Float($0.z) + 0.5) - p) < 2.6 } }
        guard atConsole else {
            if site.hold > 0 { onToast?("Taking the base stopped: stay at the command console") }
            site.hold = 0; return false
        }
        if site.hold == 0 { onToast?("The garrison is down: hold the command console to take the base (10 s)") }
        site.hold += dt
        guard site.hold >= GreywallAlarmState.holdFor else { return false }
        greywallTake(&site, key)
        return true
    }

    func greywallTake(_ site: inout GreywallAlarmState.Site, _ key: String) {
        let st = greywallAlarm
        st.taken.insert(key)
        site.on = false; site.hold = 0
        if site.lampsLit { greywallLamps(&site, lit: false) }
        // Its guns stand down (dismounted), its alarm is silent for good.
        let s = site
        mobs.mobs.removeAll { $0.kind == .deckGun && $0.faction == Faction.greywall.rawValue && Greywall.inside(s, $0.pos, pad: 2) }
        // Your flag goes up on the keep; the wall turrets stand down (they never fire on a taken base).
        let mine = Blocks.id("taken_flag")
        for f in site.flags where world.isLoaded(f.x, f.z) && world.block(f.x, f.y, f.z) == Blocks.id("greywall_flag") { world.setBlock(f.x, f.y, f.z, mine) }
        // Its yard by the gate is the player's respawn point (until they sleep in a bed or take another base).
        spawnPoint = V3(Float(site.cx) + 0.5, Float(site.S + 1), Float(site.cz + site.tier.half - 5) + 0.5)
        st.log.append("\(key) taken")
        MapCache.shared.discover(self, kind: Greywall.kind, x: site.cx, z: site.cz, name: site.tier.name)
        onToast?("The \(site.tier.name) is yours: its yard is your respawn point, its map table reads the radar net")
    }

    // The map table of a base the player holds marks every other Greywall base within 3,000 blocks on the map (the
    // radar network). Returns true when the click was the table's.
    func greywallMapTableUse(_ p: IVec3) -> Bool {
        guard Blocks.has("greywall_map_table"), world.block(p.x, p.y, p.z) == Blocks.id("greywall_map_table") else { return false }
        guard world.dim == .overworld, let sc = world.gen.structures,
              let s = sc.nearest(Greywall.kind, x: p.x, z: p.z, maxRegions: 1), s.contains(p.x, p.y, p.z) else { return true }
        let (cx, cz) = Greywall.centre(s)
        guard greywallAlarm.taken.contains("greywall:\(cx),\(cz)") else {
            onToast?("The table's charts are locked to Greywall codes: take the base first")
            return true
        }
        let n = greywallRadarNet(from: cx, cz)
        onToast?(n.isEmpty ? "The radar net shows no other Greywall base within 3,000 blocks" : "The radar net marks \(n.count) Greywall bases on your map")
        return true
    }

    @discardableResult
    func greywallRadarNet(from cx: Int, _ cz: Int, range: Int = 3000) -> [StructureStart] {
        guard let sc = world.gen.structures, let type = sc.types.first(where: { $0.name == Greywall.kind }) else { return [] }
        let span = Greywall.spacing * CS
        let r = range / span + 1
        let rx0 = floorDiv(cx, span), rz0 = floorDiv(cz, span)
        var out: [StructureStart] = []
        for rz in (rz0 - r)...(rz0 + r) { for rx in (rx0 - r)...(rx0 + r) {
            guard let s = sc.start(type, regionX: rx, regionZ: rz) else { continue }
            let (x, z) = Greywall.centre(s)
            if (x, z) == (cx, cz) { continue }
            guard simd_length(V2(Float(x - cx), Float(z - cz))) <= Float(range) else { continue }
            out.append(s)
            MapCache.shared.discover(self, kind: Greywall.kind, x: x, z: z, name: Greywall.Tier.of(s).name)
        } }
        return out
    }
}

// MARK: Wall turrets (A1 objective 4)

extension Game {
    // Every frame (from basesTick): each working or damaged wall turret of a base that isn't the player's, with the
    // player in front of it within 40 blocks and in sight, winds up (0.9 s, damaged 1.4 s: a red flash and a whine, the
    // telegraph) and fires a three-round burst, then cools 1.6 s. Its shots are a noise in the base (the alarm).
    func greywallTurretsTick(_ dt: Float) {
        let st = greywallAlarm
        guard survival, alive, !st.sites.isEmpty else { return }
        let eye = player.eye
        let gun = GreywallAlarmState.turretIds.0, hurt = GreywallAlarmState.turretIds.1
        let dirs = GreywallAlarmState.turretDirs
        for (key, site) in st.sites where !st.taken.contains(key) {
            for p in site.turrets {
                guard world.isLoaded(p.x, p.z) else { continue }
                let b = world.block(p.x, p.y, p.z)
                let damaged = b >= hurt && b < hurt + 4
                guard (b >= gun && b < gun + 4) || damaged else { st.guns[p] = nil; continue }
                let f = Int(b - (damaged ? hurt : gun))
                let centre = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)
                let muzzle = centre + dirs[f] * 0.6
                let to = eye - muzzle
                let d = simd_length(to)
                var gs = st.guns[p] ?? GreywallAlarmState.Gun()
                gs.cool = max(0, gs.cool - dt)
                gs.look -= dt
                if gs.look <= 0 {
                    gs.look = 0.3
                    gs.sees = d < GreywallAlarmState.turretRange && simd_dot(to / max(d, 0.01), dirs[f]) > -0.05
                        && world.canSee(muzzle + dirs[f] * 0.5, eye)
                }
                let wind = damaged ? GreywallAlarmState.turretWind * 1.55 : GreywallAlarmState.turretWind
                if gs.shots > 0 {
                    gs.gap -= dt
                    if gs.gap <= 0 {
                        gs.gap = 0.12; gs.shots -= 1
                        let dir = Guns.scatter(to / max(d, 0.01), damaged ? 0.05 : 0.025)
                        arms.spawn(Slug(pos: muzzle + dir * 0.4, vel: dir * 140, kind: .bullet, damage: 3, fromPlayer: false,
                                        shooter: nil, by: "a Greywall wall turret", life: 0.6, gravity: 0))
                        addFlash(at: muzzle + dir * 0.5, color: V3(5, 3.5, 1.6), radius: 4, life: 0.06)
                        sfx(.gun(1), 0.9, at: muzzle)
                        if gs.shots == 0 { gs.cool = GreywallAlarmState.turretCool; baseNoise(at: muzzle, kind: .gunshot) }
                    }
                } else if gs.sees && gs.cool <= 0 {
                    if gs.windup == 0 {
                        sfx(.gun(12), 0.7, at: muzzle)
                        addFlash(at: muzzle, color: V3(4, 0.4, 0.3), radius: 3, life: wind)
                    }
                    gs.windup += dt
                    if gs.windup >= wind { gs.windup = 0; gs.shots = GreywallAlarmState.turretBurst; gs.gap = 0 }
                } else {
                    gs.windup = max(0, gs.windup - dt * 2)
                }
                if damaged && Rand.float(in: 0..<1) < dt * 2 {
                    particles.add(Particle(pos: centre + V3(0, 0.3, 0), vel: V3(Rand.float(in: -1...1), 2, Rand.float(in: -1...1)), life: 0.25, maxLife: 0.25,
                                           layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1, size: 0.05, gravity: 6, color: V3(2.4, 1.6, 0.5), collide: false, glow: true))
                }
                st.guns[p] = gs
            }
        }
    }

    // A player's round hitting a wall turret or an alarm panel: six hits damage a turret, six more wreck it; three hits
    // smash a panel. Returns true when the round was one of theirs (Armory.impactBlock).
    func greywallBlockShot(_ b: IVec3, _ id: BlockID, at: V3) -> Bool {
        let gun = Blocks.id("wall_turret"), hurt = Blocks.id("wall_turret_damaged"), wreck = Blocks.id("wall_turret_wreck")
        let panel = Blocks.id("alarm_panel")
        let st = greywallAlarm
        if (id >= gun && id < gun + 4) || (id >= hurt && id < hurt + 4) {
            var gs = st.guns[b] ?? GreywallAlarmState.Gun()
            gs.hits += 1
            particles.add(Particle(pos: at, vel: V3(0, 2, 0), life: 0.15, maxLife: 0.15, layer: Int(Tex.id("smoke")), uv0: V2(0, 0), uvSize: 1,
                                   size: 0.08, gravity: 4, color: V3(2.6, 1.8, 0.6), collide: false, glow: true))
            sfx(.bulletImpact(.metal), 0.7, at: at)
            if gs.hits >= GreywallAlarmState.turretHits {
                gs.hits = 0; gs.windup = 0; gs.shots = 0
                let healthy = id >= gun && id < gun + 4
                let f = id - (healthy ? gun : hurt)
                world.setBlock(b.x, b.y, b.z, (healthy ? hurt : wreck) + f)
                particles.explosion(at: V3(Float(b.x) + 0.5, Float(b.y) + 0.6, Float(b.z) + 0.5), power: healthy ? 0.6 : 1.2)
                sfx(.explode, healthy ? 0.4 : 0.8, at: at)
            }
            st.guns[b] = gs
            return true
        }
        if id >= panel && id < panel + 4 {
            let n = (st.panelHits[b] ?? 0) + 1
            st.panelHits[b] = n
            sfx(.bulletImpact(.metal), 0.7, at: at)
            if n >= 3 {
                st.panelHits[b] = nil
                world.setBlock(b.x, b.y, b.z, AIR)
                particles.blockBreak(id, at: b)
                sfx(.glassBreak, 0.6, at: at)
            }
            return true
        }
        return false
    }
}
