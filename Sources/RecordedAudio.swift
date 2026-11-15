import Foundation
import simd

// Nov 15, 2026: the 77 recorded sounds of the second ElevenLabs batch (tools/elevenlabs_nov15.py; the takes and their
// numbers in docs/status/elevenlabs-takes.md) and the moments they play. Most new events are found here, once a tick,
// from state the game already keeps (a train's speed and stop, a falling body's landing, a contract's state, a paid
// customs post), so the systems they belong to are untouched; the rest are a line where the moment happens.
// BS_OLDNOV15SOUNDS=1: none of them play, the old sounds do (each call site keeps its old sound).
enum RecordedNov15 {
    static let oldDeskDrawer = Env.all["BS_OLDDESKDRAWER"] == "1"
    static let oldWellReach = Env.all["BS_OLDWELLREACH"] == "1"
    // A narrow shaft over the water at f: two blocks over it, at least two of its four sides walled (a village well's
    // 2x2 shaft walls two sides of each cell; a cliff over the sea walls none).
    static func shaft(_ w: World, _ f: IVec3) -> Bool {
        let y = f.y + 2
        guard !Blocks.collide[Int(w.block(f.x, y, f.z))] else { return false }
        let walls = [(1, 0), (-1, 0), (0, 1), (0, -1)].filter { Blocks.collide[Int(w.block(f.x + $0.0, y, f.z + $0.1))] }.count
        return walls >= 2
    }
    static let off = Env.all["BS_OLDNOV15SOUNDS"] == "1"
    static func pick(_ new: Snd, _ old: Snd) -> Snd { off ? old : new }

    // Per-tick state of the watchers (keys: the train's or ship's id, a fall's body).
    static var trainState: [Int64: TrainEar] = [:]
    final class TrainEar {
        var moving = false
        var stoppedFor: Float = 0
        var braked = false
        var stop: Int? = nil
    }
    static var falls: [ObjectIdentifier: (landed: Bool, rolled: Bool)] = [:]
    static var crawlerMoving: [Int: Bool] = [:]
    static var iceWeight: [Int: Double] = [:]
    static var contracts: [String: Int] = [:]          // 0 open, 1 taken, 2 paid, 3 failed
    static var contractsRead = false
    static var paidPost: String? = nil
    static var bought = -1
    static var heldGun: Int? = nil
    static var chute = false
    static var radarSeen: Set<String> = []
    static var radarAt: Double = -10
    static var collapseAt: Double = -10
    static var treesAt: Double = -10
    static var coaxLast: Double = -10, coaxFrom: Double = -10, coaxPos = V3.zero
    static var volcanoes: [Volcano] = [], volcanoesAt: Double = -10
    static var played: [String: Int] = [:]            // (checks: how often each new event played)

    static func note(_ s: Snd) { played[s.name, default: 0] += 1 }

    // A building piece coming down (never a tree: those are the tree sounds), at most one a second.
    static func bulletImpact(_ b: BlockID) -> Snd {
        let k = Blocks.key(Blocks.groupBase[Int(b)])
        if !off && (k == "ice" || k == "packed_ice" || k == "sea_ice" || k == "blue_ice") { return .bulletIce }
        return .bulletImpact(soundMat(b))
    }
    static func isConcrete(_ k: String) -> Bool { k.hasSuffix("concrete") }

    // A tree a capital vehicle drives through goes over (CapitalShips.crawlerCrush), at most one crash in 1.2 s.
    static func treePush(_ g: Game, at p: V3) {
        guard !off, g.clock - treesAt > 1.2 else { return }
        treesAt = g.clock
        g.sfx(.carriageTrees, 1, at: p); note(.carriageTrees)
    }

    // The Cinder Tank's coaxial gun: each round marks the burst (the loop plays while it runs; Game.recordedTick).
    static func coaxRound(_ g: Game, at p: V3) -> Bool {
        guard !off else { return false }
        if g.clock - coaxLast > 0.3 { coaxFrom = g.clock }
        coaxLast = g.clock; coaxPos = p
        return true
    }
}

extension Guns {
    // The reload sound of a gun: its own slot's, the revolver's its own (it fires as the sidearm).
    static func reloadSound(_ gi: Int) -> Snd {
        if gi == revolver && !RecordedNov15.off { return .gunReload(WeaponAudio.revolverReloadSlot) }
        return .gunReload(all[gi].sound)
    }
}

extension Game {
    // Once an audio tick (AudioAmbience, beside the vehicles): the new loops, and the one-shots the watchers find.
    func recordedTick(_ dt: Float, ask: (String, Snd, Float, V3?) -> Void) {
        guard !RecordedNov15.off else { return }
        let eye = player.eye
        trainSounds(dt, eye, ask: ask)
        fallSounds(eye)
        // Elevators: the car's motor and cables while it rides.
        for (k, r) in Elevators.runs where r.phase == 3 {
            if let s = r.ship, simd_length(s.pos - eye) < 32 { ask("lift\(k)", .elevatorLoop, 0.8, s.pos) }
        }
        // A parachute: the canopy's flutter while he hangs under it; the landing as it folds.
        if player.parachute {
            ask("chute", .chuteLoop, 0.8, nil)
        } else if RecordedNov15.chute && player.onGround {
            sfx(.chuteLand, 0.9, at: player.pos); RecordedNov15.note(.chuteLand)
        }
        RecordedNov15.chute = player.parachute
        // The Cinder Tank's coaxial gun: a steady stream while the trigger is held, the last rounds and the brass after.
        let c = RecordedNov15.self
        if clock - c.coaxLast < 0.2 {
            ask("tankmg", .tankMGLoop, 0.9, c.coaxPos)
        } else if c.coaxLast > c.coaxFrom && clock - c.coaxLast < 0.25 + Double(dt) && c.coaxLast - c.coaxFrom > 0.3 {
            sfx(.tankMGTail, 0.9, at: c.coaxPos); c.note(.tankMGTail)
            sfx(.casingsSteel, 0.6, at: c.coaxPos); c.note(.casingsSteel)
            c.coaxFrom = c.coaxLast
        }
        // Radar: the set's hum while its scope or list shows; a new contact pings, a new vessel warns.
        let showing = frigateRadar || holdingRadar || clock < consoleRadarUntil
        if showing && menu == nil {
            ask("radar", .radarLoop, 0.5, nil)
            let list = Game.radarCache.list
            let names = Set(list.map { "\($0.kind) \($0.name)" })
            let fresh = list.filter { !c.radarSeen.contains("\($0.kind) \($0.name)") }
            if !c.radarSeen.isEmpty, let n = fresh.first, clock - c.radarAt > 1.5 {
                let warn = n.kind.hasPrefix("vessel_")
                sfx(warn ? .radarWarning : .radarContact, 0.7); c.note(warn ? .radarWarning : .radarContact)
                c.radarAt = clock
            }
            c.radarSeen = names.isEmpty ? ["-"] : names
        } else { c.radarSeen = [] }
        // Capital land vehicles: the crawler's own drone; its grinding halt.
        for s in world.ships.list where s.role == "crawler" && s.parent == nil {
            let v = simd_length(s.vel)
            let was = c.crawlerMoving[s.id] ?? false
            if v > 0.6 { c.crawlerMoving[s.id] = true } else if v < 0.1 {
                c.crawlerMoving[s.id] = false
                let at = simd_clamp(eye, s.worldMin, s.worldMax)
                if was && simd_length(at - eye) < 160 { sfx(.crawlerStop, 1, at: at); c.note(.crawlerStop) }
            }
        }
        // Ice under weight: a vehicle on sheet ice sets it cracking, now and then.
        if Game.seaIceID != AIR {
            let ice = Blocks.groupBase[Int(Game.seaIceID)]
            func onIce(_ p: V3) -> Bool { Blocks.groupBase[Int(world.block(Int(floor(p.x)), Int(floor(p.y - 0.5)), Int(floor(p.z))))] == ice }
            for s in world.ships.list where s.parent == nil && s.blockCount >= 12 && simd_length(s.pos - eye) < 48 {
                let low = V3(s.pos.x, s.worldMin.y + 0.2, s.pos.z)
                guard onIce(low), clock >= c.iceWeight[s.id] ?? 0 else { continue }
                c.iceWeight[s.id] = clock + 6
                sfx(.iceCrack, 1, at: low); c.note(.iceCrack)
            }
            for m in mobs.mobs where m.kind.ashVehicle && m.health > 0 && simd_length(m.pos - eye) < 48 {
                let key = Int(truncatingIfNeeded: ObjectIdentifier(m).hashValue)
                guard onIce(m.pos + V3(0, 0.3, 0)), clock >= c.iceWeight[key] ?? 0 else { continue }
                c.iceWeight[key] = clock + 6
                sfx(.iceCrack, 1, at: m.pos); c.note(.iceCrack)
            }
        }
        // Towns and the capital: a square's crowd, a market street, a crowd running, a fight in the streets.
        if TownLaw.inTown != nil {
            var people = 0, keepers = 0, panic = 0, fight = false
            for m in mobs.mobs where m.health > 0 {
                let d = simd_length(m.pos - eye)
                if d > 48 { continue }
                if let r = m.villager?.role, ["citizen", "shopkeeper", "banker", "lawman", "child", "elder"].contains(r) || m.kind == .villager {
                    people += 1
                    if r == "shopkeeper" && d < 24 { keepers += 1 }
                    if m.panic > 0 { panic += 1 }
                } else if m.kind.steelhold && m.aggro && d < 40 { fight = true }
            }
            let day = max(0, min(1, (0.55 - abs(dayFraction - 0.25)) * 3))
            if people >= 12 { ask("citycrowd", .cityCrowdLoop, min(1, Float(people) / 30) * 0.7 * Float(day), nil) }
            if keepers >= 2 { ask("market", .marketLoop, 0.6 * Float(day), nil) }
            if panic >= 3 { ask("panic", .crowdPanicLoop, min(1, Float(panic) / 8), nil) }
            if fight { ask("cityfight", .cityFightLoop, 0.6, nil) }
        }
        // A stagecoach or freight wagon on the road: hooves, axle and harness.
        if let m = mobs.mobs.filter({ $0.coach > 0 && $0.health > 0 && simd_length(V2($0.vel.x, $0.vel.z)) > 0.5 })
            .min(by: { simd_length($0.pos - eye) < simd_length($1.pos - eye) }), simd_length(m.pos - eye) < 40 {
            ask("convoy", .convoyCartLoop, 0.8 * (1 - simd_length(m.pos - eye) / 40), m.pos)
        }
        // A volcano in the land he can see: its low growl, louder while it erupts.
        if dim.dim == .overworld, let wg = world.gen as? WorldGen {
            if clock - c.volcanoesAt > 2 {
                c.volcanoesAt = clock
                c.volcanoes = wg.terrain.volcanoes(near: eye.x, eye.z, reach: 700)
            }
            let reach = Float(world.renderDistance * CS) + 64
            if let v = c.volcanoes.min(by: { simd_length(V2($0.x - eye.x, $0.z - eye.z)) < simd_length(V2($1.x - eye.x, $1.z - eye.z)) }) {
                let d = simd_length(V2(v.x - eye.x, v.z - eye.z))
                if d < reach + v.r {
                    let near = max(0, 1 - d / (reach + v.r))
                    ask("volcano", .volcanoLoop, (0.25 + 0.5 * near) * (eruption != nil ? 1.6 : 1), V3(v.x, Float(YOFF) + v.base + v.peak, v.z))
                }
            }
        }
        // Once a second: contracts taken, done and failed; a customs post paid; a house bought; the Faustrohr shouldered.
        if Int(clock) != Int(clock - Double(dt)) { bookSounds() }
        if heldGun != c.heldGun {
            if heldGun == Guns.faust && clock > 2 { sfx(.faustShoulder, 0.8); c.note(.faustShoulder) }
            c.heldGun = heldGun
        }
    }

    // Trains: inside a coach the wheels' clatter; beside the line one going by; at a station the engine simmering. Brakes
    // before a stop, the bell and the couplers at it, the start away from it.
    private func trainSounds(_ dt: Float, _ eye: V3, ask: (String, Snd, Float, V3?) -> Void) {
        var nearest: (Trains.Train, Mob, Float)? = nil
        for (id, tr) in Trains.trains where !tr.cars.isEmpty {
            guard let lead = Trains.lead(tr) else { continue }
            let d = simd_length(lead.pos - eye)
            let ear = RecordedNov15.trainState[id] ?? RecordedNov15.TrainEar()
            RecordedNov15.trainState[id] = ear
            let sp = tr.blocksPerSec
            let aboard = riding.map { r in tr.cars.contains { $0 === r } } ?? false
            if aboard { ask("traincoach", .trainCoachLoop, min(0.9, 0.15 + sp / 14), nil) }
            if !aboard, nearest == nil || d < nearest!.2 { nearest = (tr, lead, d) }
            let stop = Trains.now(tr).stop
            // (the timetable says where it stops; driven, his brake does)
            let stopping = tr.driven ? tr.cabBrake > 0.5 && sp > 3 : stop == nil && tr.track.at(tr.time + 3).stop != nil && sp > 2
            if stopping && !ear.braked && d < 96 { sfx(.trainBrakes, 0.9, at: lead.pos); RecordedNov15.note(.trainBrakes) }
            ear.braked = stopping || (ear.braked && sp > 0.5)
            if sp > 0.6 {
                if !ear.moving && ear.stoppedFor > 3 && d < 96 { sfx(.trainDepart, 1, at: Trains.chimney(lead)); RecordedNov15.note(.trainDepart) }
                ear.moving = true; ear.stoppedFor = 0
            } else if sp < 0.2 {
                if ear.moving && d < 64 {
                    if let tail = tr.cars.last { sfx(.trainCoupler, 0.8, at: tail.pos); RecordedNov15.note(.trainCoupler) }
                    if stop != nil { sfx(.stationBell, 0.8, at: lead.pos); RecordedNov15.note(.stationBell) }
                }
                ear.moving = false; ear.stoppedFor += dt
            }
            ear.stop = stop
            if sp < 0.3 && d < 40 && !aboard { ask("trainidle\(id)", .trainIdleLoop, 0.7 * (1 - d / 40), Trains.chimney(lead)) }
        }
        if let (tr, lead, d) = nearest, tr.blocksPerSec > 1, d < 96 {
            ask("trainpass", .trainPassLoop, min(1, tr.blocksPerSec / 12) * (1 - d / 96), lead.pos)
        }
        if RecordedNov15.trainState.count > 64 { RecordedNov15.trainState = RecordedNov15.trainState.filter { Trains.trains[$0.key] != nil } }
    }

    // Falling bodies (Felling.falls, read only): a tree going over cracks, lands with a crash (in snow, muffled), its
    // trunk rolls a little; a small tree just falls; a building's piece coming down collapses.
    private func fallSounds(_ eye: V3) {
        var live = Set<ObjectIdentifier>()
        for f in Felling.falls {
            guard let s = f.ship else { continue }
            let id = ObjectIdentifier(f)
            live.insert(id)
            let d = simd_length(s.pos - eye)
            let tree = Felling.isFelled(s)
            if RecordedNov15.falls[id] == nil {
                RecordedNov15.falls[id] = (false, false)
                guard d < 64 else { continue }
                if tree {
                    let small = s.blockCount < 24
                    sfx(small ? .treeFallSmall : .treeCrack, 1, at: s.pos); RecordedNov15.note(small ? .treeFallSmall : .treeCrack)
                } else if s.blockCount >= 8 && clock - RecordedNov15.collapseAt > 1 {
                    RecordedNov15.collapseAt = clock
                    sfx(.wallCollapse, min(1.3, 0.7 + Float(s.blockCount) / 200), at: s.pos); RecordedNov15.note(.wallCollapse)
                }
                continue
            }
            var st = RecordedNov15.falls[id]!
            if tree && f.landed && !st.landed && d < 64 {
                st.landed = true
                if s.blockCount >= 24 {
                    let b = world.block(Int(floor(s.pos.x)), Int(floor(s.worldMin.y - 0.5)), Int(floor(s.pos.z)))
                    let snow = soundMat(b) == .snow || AmbientBiomes.snowy.contains(world.gen.column(Int(floor(s.pos.x)), Int(floor(s.pos.z))).biome)
                    sfx(snow ? .treeLandSnow : .treeLand, 1, at: s.pos); RecordedNov15.note(snow ? .treeLandSnow : .treeLand)
                }
            } else if tree && st.landed && !st.rolled && f.landedAge >= 0 && f.age - f.landedAge > 0.6 {
                st.rolled = true
                if simd_length(V2(s.vel.x, s.vel.z)) > 0.6 && d < 48 { sfx(.logRoll, 0.8, at: s.pos); RecordedNov15.note(.logRoll) }
            }
            RecordedNov15.falls[id] = st
        }
        if RecordedNov15.falls.count > live.count { RecordedNov15.falls = RecordedNov15.falls.filter { live.contains($0.key) } }
    }

    // Once a second: what changed in the books.
    private func bookSounds() {
        let c = RecordedNov15.self
        if let all = TownLaw.state.contracts {
            var now: [String: Int] = [:]
            for (k, v) in all { now[k] = v.failed ? 3 : (v.paid ? 2 : (v.taken ? 1 : 0)) }
            if c.contractsRead {
                for (k, v) in now where v != (c.contracts[k] ?? 0) && v > (c.contracts[k] ?? 0) {
                    let s: Snd = v == 1 ? .questAccept : (v == 2 ? .questDone : .questFail)
                    sfx(s, 0.8); c.note(s)
                    break
                }
            }
            c.contracts = now
        }
        c.contractsRead = true
        if let pk = Countries.paidPost, pk != c.paidPost, let spot = Countries.postSpots[pk] ?? nil {
            let at = V3(Float(spot.0) + 0.5, player.pos.y, Float(spot.1) + 0.5)
            if simd_length(at - player.pos) < 48 { sfx(.customsGate, 0.9, at: at); c.note(.customsGate) }
        }
        c.paidPost = Countries.paidPost
        if c.bought >= 0 && Property.bought > c.bought { sfx(.houseBought, 0.9); c.note(.houseBought) }
        c.bought = Property.bought
    }
}
