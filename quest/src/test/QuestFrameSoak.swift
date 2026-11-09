import Foundation
import simd
import Metal
import CVulkan

// Store review (Meta, Nov 2: VRC.Quest.Performance.1 failed on build 0.129 b18429a6, "Your app fluctuates under and
// over 60 frames per second... the frame rate must maintain a steady rate above 60"). questcheck --framesoak [--only
// crawler,citadel,naval,train,hell,battle] [--seconds 40] [--rd 10]: each of the heavy scenes of normal play, played in
// real time at 72 Hz with the headset's settings (QuestApp's world statics, a Polygons world, its mesh workers running
// beside the frame as they do on the headset), the frame thread doing what QuestApp.frame does: Game.tick, then the
// world's record on the Quest renderer. Every frame's split is kept; the report gives, per scene, the frame thread's
// time (host ms and the headset's estimate), how many frames the headset would miss on the CPU side, the longest run
// of them, what the slowest frames spent their time on, and the GPU's load as the quads and draws it is handed.
// The headset's estimate is the host time x `questFactor` (P385: his headset log had the record at 10-12 ms where the
// host took 6.95 ms for the same view; 1.7 is the pessimistic end). The cloud has no Adreno: the GPU side is the quads
// and draws, never a time.
enum QuestFrameSoak {
    static let questFactor = 1.7
    static let budgetMs = 1000.0 / 72
    static var hostBudgetMs: Double { budgetMs / questFactor }

    static func arg(_ k: String) -> String? {
        guard let i = CommandLine.arguments.firstIndex(of: k), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    // A scene: its world, where he is and what he does each frame.
    struct Setup {
        var name: String
        var what: String
        var seed: UInt64
        var dim: Dim = .overworld
        var at: V3                       // (internal y)
        var prepare: (Game) -> Void      // after the first load, before the frames
        var step: (Game, Int) -> Void    // every frame, before the tick
    }

    static let crawlerSeed: UInt64 = 7653607216494784574
    static let crawlerAt = V3(-22251.7, 160.4, 15846.4)

    // The crawler at his Nov 2 spot (FAILURES list: "i can't see shit around me when i am driving it"), driving on at
    // 8 b/s with him at its helm; its main gun fired ahead every 5 s.
    static func crawlerScene(parkedBy citadel: Bool) -> Setup {
        var crawler: Ship?
        var aim = V3(0, 0, 0)
        return Setup(name: citadel ? "citadel" : "crawler",
                     what: citadel ? "the crawler parked 40 blocks off a capital citadel's wall, main gun firing into it every 5 s, the garrison awake"
                                   : "driving the Ironback Crawler at 8 b/s over new land, main gun fired ahead every 5 s",
                     seed: crawlerSeed, at: crawlerAt,
                     prepare: { g in
            let w = g.world
            w.ships.encounters = false
            var home = g.player.pos
            var yaw: Float = 0
            if citadel, let st = w.gen.structures?.nearest("military_base", x: Int(home.x), z: Int(home.z), maxRegions: 24) {
                let cx = Float(st.min.x + st.max.x) / 2, cz = Float(st.min.z + st.max.z) / 2
                home = V3(Float(st.min.x) - 40, home.y, cz)
                aim = V3(cx, Float(st.pieces[0].min.y + 12), cz)
                yaw = -.pi / 2                                       // (facing east, at the citadel)
                g.player.pos = home
                _ = w.loadSync(center: home, radius: w.renderDistance)
                for (name, p) in w.pendingMobs { if let m = Mob.structureMob(name, at: p) { g.mobs.mobs.append(m) } }
                w.pendingMobs.removeAll()
                print(String(format: "framesoak: citadel at %.0f %.0f, the crawler 40 blocks off its west wall", cx, cz))
            }
            w.ships.spawnCapital("crawler", home: IVec3(Int(floor(home.x)), 0, Int(floor(home.z))), yaw: yaw, region: nil, sync: true)
            guard let c = w.ships.capitals.first(where: { $0.role == "crawler" }), let st = w.ships.capState[c.id], let hc = c.helm else {
                print("framesoak: no crawler could be spawned"); return
            }
            st.crewDone = Set(0..<st.crew.count); st.crewless = true
            st.testTurn = 0; st.testSpeed = citadel ? 0 : 8
            crawler = c
            g.player.flying = false
            g.player.pos = c.toWorld(V3(Float(hc.x) + 0.5, Float(hc.y) + 1.02, Float(hc.z) + 1.5))
            g.player.vel = c.velocity(at: g.player.pos)
            g.player.yaw = yaw; g.player.pitch = -0.15
        }, step: { g, f in
            guard let c = crawler, let st = g.world.ships.capState[c.id] else { return }
            if citadel { g.survival = true; g.health = 20; g.alive = true }
            if f % 360 == 180 {
                let mw = c.toWorld(st.mainGunMuzzle)
                let dir = citadel ? simd_normalize(aim - mw + V3(1e-5, 0, 0)) : simd_normalize(c.dirToWorld(st.mainGunDir) + V3(0, -0.08, 0))
                g.world.ships.fireMainGun(c, st, dir: dir, game: g)
            }
        })
    }

    // A naval gun fight: two hostile Meridian frigates shelling him on a stone float at sea (the P283 ocean spot).
    static func navalScene() -> Setup {
        Setup(name: "naval", what: "two hostile frigates firing on him at sea, 80-100 blocks off",
              seed: 3931512493184456980, at: V3(11576.9, 62.8 + Float(YOFF), -12552.1),
              prepare: { g in
            let w = g.world
            w.ships.encounters = false
            let x = Int(floor(g.player.pos.x)), z = Int(floor(g.player.pos.z))
            let top = SEA
            for dz in -3...3 { for dx in -3...3 { w.setBlock(x + dx, top, z + dz, STONE) } }
            g.player.pos = V3(Float(x) + 0.5, Float(top + 1), Float(z) + 0.5)
            g.player.flying = false
            g.survival = true; g.difficulty = 2
            w.ships.spawnCapital("capfrigate", home: IVec3(x, 0, z + 90), yaw: 0, region: nil, sync: true)
            w.ships.spawnCapital("capfrigate", home: IVec3(x - 85, 0, z - 30), yaw: .pi / 2, region: nil, sync: true)
            g.player.yaw = .pi; g.player.pitch = -0.1
            print("framesoak: \(w.ships.capitals.count) frigates at sea round him")
        }, step: { g, _ in g.survival = true; g.health = 20; g.alive = true })
    }

    // Riding a passenger train from the cab along the nearest line to his jungle spot (seed of FAILURES 3).
    static func trainScene(_ kind: Trains.Kind = .passenger, name: String = "train") -> Setup {
        var drive: (() -> Void)?
        let what = kind == .passenger ? "a passenger" : (kind == .cargo ? "a freight" : (kind == .troop ? "a troop" : "a bullion"))
        return Setup(name: name, what: "driving \(what) train from the cab, regulator open",
                     seed: crawlerSeed, at: V3(-5572, 141, 2813),
                     prepare: { g in
            guard let gen = g.world.gen as? WorldGen else { return }
            let ax = Int(g.player.pos.x), az = Int(g.player.pos.z)
            guard let l = Railways.near(gen, x0: ax - 3000, z0: az - 3000, x1: ax + 3000, z1: az + 3000, pad: 0)
                .filter({ $0.stations.count >= 2 })
                .min(by: { abs($0.minX - ax) + abs($0.minZ - az) < abs($1.minX - ax) + abs($1.minZ - az) }) else { print("framesoak: no line near"); return }
            let t = Trains.track(l)
            let c0 = l.cells[l.stations[0].index]
            g.player.pos = V3(Float(c0.x) + 0.5, Float(c0.y), Float(c0.z - 2) + 0.5)
            _ = g.world.loadSync(center: g.player.pos, radius: g.world.renderDistance)
            Trains.trains.removeAll()
            var at = g.time
            for k in 0..<Int(t.period) { let a = t.at(g.time + Double(k)); if a.stop == 0 && a.dir > 0 { at = g.time + Double(k) + 1; break } }
            g.time = at
            Trains.forceKind = kind
            Trains.tick(g)
            Trains.forceKind = nil
            guard let tr = Trains.trains[t.id], let lead = tr.cars.first else { print("framesoak: no train built on \(l.name)"); return }
            _ = Trains.use(g, lead)
            drive = { tr.throttle = 2; if g.riding == nil, let c = tr.cars.first { _ = Trains.use(g, c) } }
            print("framesoak: on \(l.name) (\(l.cells.count) cells), \(tr.cars.count) cars")
        }, step: { _, _ in drive?() })
    }

    // The Emberdeep: flying on through it at 8 b/s from over a fortress, its mobs about.
    static func hellScene() -> Setup {
        Setup(name: "hell", what: "the Emberdeep, flying on at 8 b/s from a fortress",
              seed: crawlerSeed, dim: .nether, at: V3(0, 80 + Float(YOFF) - 64, 0),
              prepare: { g in
            if let st = g.world.gen.structures?.nearest("fortress", x: 0, z: 0, maxRegions: 16) {
                g.player.pos = V3(Float(st.anchor.x) + 0.5, Float(st.anchor.y + 6), Float(st.anchor.z) + 0.5)
                print("framesoak: fortress at \(st.anchor.x) \(st.anchor.y) \(st.anchor.z)")
            }
            g.player.flying = true
            g.player.yaw = 0.7; g.player.pitch = -0.2
        }, step: { g, _ in
            g.player.flying = true
            let yaw = g.player.yaw
            g.player.pos += V3(-sinf(yaw), 0, -cosf(yaw)) * (8.0 / 72)
            g.player.vel = .zero
        })
    }

    // The biggest battle: the Ash Vault citadel's north gate at Total War (AshVaultGapTests.battleScene).
    static func battleScene() -> Setup {
        var stand = V3(0, 0, 0)
        return Setup(name: "battle", what: "the Ash Vault citadel's gate at Total War, every garrison awake",
                     seed: crawlerSeed, at: V3(0, 160, 0),
                     prepare: { g in stand = AshVaultGapTests.battleScene(g); g.player.yaw = .pi; g.player.pitch = 0.05 },
                     step: { g, _ in g.health = 20; g.alive = true; g.ashSpot = stand; g.ashSpotSeen = g.clock })
    }

    // Ordinary play (Meta didn't say where the dips were: "These fluctuations can be found in the game"): on foot with
    // the stick forward, or flying at the creative sprint, through his own slow spots.
    static func moving(_ name: String, _ what: String, seed: UInt64, x: Float, y: Float, z: Float, yaw: Float, pitch: Float, fly: Bool) -> Setup {
        Setup(name: name, what: what, seed: seed, at: V3(x, y + Float(YOFF), z),
              prepare: { g in
            g.player.flying = fly
            g.survival = !fly
            g.player.yaw = -yaw * .pi / 180; g.player.pitch = pitch * .pi / 180
            if fly {
                // (over the land, not into the hill ahead: 30 over the highest ground within 64 blocks)
                var top = Int(g.player.pos.y)
                for d in stride(from: 0, through: 64, by: 4) {
                    let px = Int(g.player.pos.x - sinf(g.player.yaw) * Float(d)), pz = Int(g.player.pos.z - cosf(g.player.yaw) * Float(d))
                    if let c = g.world.chunkAt(px, pz) { top = max(top, Int(c.height[mod(px, CS) + mod(pz, CS) * CS])) }
                }
                g.player.pos.y = Float(top + 30)
            } else {
                let px = Int(floor(g.player.pos.x)), pz = Int(floor(g.player.pos.z))
                var y = CH - 2
                while y > 1 && !g.world.solidAt(px, y - 1, pz) { y -= 1 }
                g.player.pos.y = Float(y) + 0.01
            }
        }, step: { g, f in
            if !fly { g.survival = true; g.health = 20; g.alive = true }
            var pad = PadSnapshot()
            pad.ly = 1
            pad.rx = f % 720 < 360 ? 0.25 : -0.25            // (looking about as he walks)
            PadManager.shared.touch = pad
            g.input.control = fly
        })
    }

    static var ordinary: [Setup] {
        [moving("jungle", "walking through his Nov 2 08:23 jungle (49-56 fps in his notes)", seed: crawlerSeed, x: -5583.8, y: 75.7, z: 2823.8, yaw: 344, pitch: -20, fly: false),
         moving("town", "walking through Stone Gulch, the savanna town (P374: 45-54 fps)", seed: 13480747113613945685, x: 6094.4, y: 88.0, z: 688.6, yaw: 123, pitch: -12, fly: false),
         moving("forest", "flying at the creative sprint over the Oct 24 forest", seed: 5663059916303033239, x: 692.3, y: 119.8, z: 638.9, yaw: 340, pitch: -20, fly: true),
         moving("taiga", "flying at the creative sprint into new taiga (Oct 24: 41-49 fps)", seed: 5933896066598527833, x: 4740.5, y: 143.5, z: -3278.6, yaw: 320, pitch: -20, fly: true)]
    }

    // Week plan item 6 (Remington, Nov 3: "grow the 10 soak scenes to 25: towns, hell, the Ash Vault, sea battles, trains,
    // big fights"): fifteen more. Ordinary play in the other biomes (found from the seed's spawn, the middle of each), the
    // weather and the night, towns and the capital city on foot, the Hollow, his frigate under way, the other trains,
    // the sea hunters, and item 7's worst case all at once.
    static let biomeSeed: UInt64 = 12345

    // The middle of `biome` on `seed`'s world, the player moved there and the land loaded round him.
    // (spiralling out from spawn in 48-block steps, the column and eight points 40 out all in it: well inside, not its edge)
    // (Nov 8: at the soak seed no swamp or badlands 80 blocks across lies within 3,400 blocks, and both scenes walked
    // the world's middle instead, under their names. A second, wider search takes a biome 48 blocks across.)
    static func findBiome(_ gen: TerrainGenerator, _ want: String) -> V3? {
        findBiome(gen, want, reach: 40, steps: 20000) ?? findBiome(gen, want, reach: 24, steps: 120000)
    }
    static func findBiome(_ gen: TerrainGenerator, _ want: String, reach r: Int, steps: Int) -> V3? {
        var x = 0, z = 0, dx = 0, dz = -1
        let probes: [(Int, Int)] = [(0, 0), (r, 0), (-r, 0), (0, r), (0, -r), (r, r), (-r, r), (r, -r), (-r, -r)]
        for _ in 0..<steps {
            let wx = x * 48 + 8, wz = z * 48 + 8
            if probes.allSatisfy({ gen.column(wx + $0.0, wz + $0.1).biome.name == want }) {
                return V3(Float(wx) + 0.5, Float(max(gen.column(wx, wz).height, SEA) + 1), Float(wz) + 0.5)
            }
            if x == z || (x < 0 && x == -z) || (x > 0 && x == 1 - z) { (dx, dz) = (-dz, dx) }
            x += dx; z += dz
        }
        return nil
    }
    static func goTo(_ g: Game, biome: String) {
        guard let p = findBiome(g.world.gen, biome) else { print("framesoak: no \(biome) found within 8,000 blocks: this scene walks the world's middle"); return }
        g.player.pos = p
        _ = g.world.loadSync(center: p, radius: g.world.renderDistance)
        print(String(format: "framesoak: %@ at %.0f %.0f", biome, p.x, p.z))
    }

    // Walking (or flying) through the middle of a biome, with the weather and the hour it asks for.
    static func biomeScene(_ name: String, _ what: String, biome: String, fly: Bool, storm: Bool = false, night: Bool = false) -> Setup {
        let base = moving(name, what, seed: biomeSeed, x: 0, y: 70, z: 0, yaw: 300, pitch: fly ? -20 : -10, fly: fly)
        return Setup(name: name, what: what, seed: biomeSeed, at: base.at, prepare: { g in
            goTo(g, biome: biome)
            if night { g.time = 0.75 * DAY_LENGTH; g.difficulty = 2 }
            base.prepare(g)
            if storm { g.weather.raining = true; g.weather.rain = 1; g.weather.thundering = true; g.weather.thunder = 1 }
        }, step: { g, f in
            if storm { g.weather.raining = true; g.weather.thundering = true; g.weather.rainTime = 600; g.weather.thunderTime = 600 }
            base.step(g, f)
        })
    }

    // On foot through the middle of the nearest structure of `kind` (a village, the capital city).
    static func townScene(_ name: String, _ what: String, kind: String) -> Setup {
        let base = moving(name, what, seed: biomeSeed, x: 0, y: 70, z: 0, yaw: 300, pitch: -10, fly: false)
        return Setup(name: name, what: what, seed: biomeSeed, at: base.at, prepare: { g in
            if let st = g.world.gen.structures?.nearest(kind, x: 0, z: 0, maxRegions: 24) {
                let c = V3(Float(st.min.x + st.max.x) / 2 + 0.5, g.player.pos.y, Float(st.min.z + st.max.z) / 2 + 0.5)
                // (from its edge, walking in toward the middle)
                let r = Float(max(st.max.x - st.min.x, st.max.z - st.min.z)) / 2
                g.player.pos = c + V3(r * 0.6, 0, 0)
                _ = g.world.loadSync(center: g.player.pos, radius: g.world.renderDistance)
                for (n, q) in g.world.pendingMobs { if let m = Mob.structureMob(n, at: q) { g.mobs.mobs.append(m) } }
                g.world.pendingMobs.removeAll()
                print(String(format: "framesoak: %@ at %.0f %.0f, %.0f across", kind, c.x, c.z, 2 * r))
            } else { print("framesoak: no \(kind) near spawn") }
            base.prepare(g)
            g.player.yaw = .pi / 2                                       // (facing west, into it)
        }, step: base.step)
    }

    // The Hollow: flying over the main island past the spikes at the creative sprint.
    static func hollowScene() -> Setup {
        Setup(name: "hollow", what: "the Hollow, flying over the main island and its spikes",
              seed: crawlerSeed, dim: .end, at: V3(60, 150, 0),
              prepare: { g in g.player.flying = true; g.player.yaw = .pi / 2; g.player.pitch = -0.25 },
              step: { g, _ in
            g.player.flying = true
            let yaw = g.player.yaw
            g.player.pos += V3(-sinf(yaw), 0, -cosf(yaw)) * (8.0 / 72)
            g.player.vel = .zero
        })
    }

    // His Stormwarden frigate under way: aboard at its helm, flying on at 10 b/s over new land.
    static func frigateScene() -> Setup {
        var ship: Ship?
        return Setup(name: "frigate", what: "aboard a Stormwarden frigate at its helm, flying on at 10 b/s over new land",
                     seed: biomeSeed, at: V3(400, 160, 400),
                     prepare: { g in
            let w = g.world
            w.ships.encounters = false
            // (the Stormwarden's role is "warfrigate": spawned as "frigate" she was driven as a crawler, along the ground)
            w.ships.spawnCapital("warfrigate", home: IVec3(Int(floor(g.player.pos.x)), 0, Int(floor(g.player.pos.z))), yaw: 0, region: nil, sync: true)
            guard let s = w.ships.capitals.first(where: { $0.role == "warfrigate" }), let st = w.ships.capState[s.id], let stand = g.helmStand(s) else {
                print("framesoak: no frigate could be spawned"); return
            }
            st.crewDone = Set(0..<st.crew.count); st.crewless = true
            st.testTurn = 0; st.testSpeed = 10
            ship = s
            g.player.flying = false
            g.player.pos = s.toWorld(stand)
            g.player.vel = s.velocity(at: g.player.pos)
            g.player.yaw = 0; g.player.pitch = -0.1
            print(String(format: "framesoak: %@ at %.0f %.0f %.0f", s.name, s.pos.x, s.pos.y, s.pos.z))
        }, step: { g, _ in
            guard let s = ship, let stand = g.helmStand(s) else { return }
            // (held at the helm as the deck carries him)
            if simd_length(g.player.pos - s.toWorld(stand)) > 3 { g.player.pos = s.toWorld(stand); g.player.vel = s.velocity(at: g.player.pos) }
        })
    }

    // The sea hunters: on his raft at sea with a corsair sloop and the Corsair Cruiser closing and firing (SeaHunt).
    static func seaHuntScene() -> Setup {
        var sc = navalScene()
        sc.name = "seahunt"
        sc.what = "the Corsair Cruiser and a corsair sloop hunting him at sea, closing from 150 blocks"
        sc.prepare = { g in
            let w = g.world
            w.ships.encounters = true; w.ships.spawnEncounters = false
            let x = Int(floor(g.player.pos.x)), z = Int(floor(g.player.pos.z))
            let surf = Submarine.surface(w, x + 10, z) ?? (SEA - 1)
            for dz in -3...3 { for dx in -3...3 { for y in surf...(surf + 1) { w.setBlock(x + dx, y, z + dz, STONE) } } }
            g.player.pos = V3(Float(x) + 0.5, Float(surf + 2), Float(z) + 0.5)
            g.player.flying = false
            g.survival = true; g.difficulty = 2
            for (role, a) in [(NavalPatrol.role, Float(0.3)), ("sloop", Float(2.2))] {
                let hx = Int(floor(g.player.pos.x + cosf(a) * 150)), hz = Int(floor(g.player.pos.z + sinf(a) * 150))
                guard let y = Submarine.surface(w, hx, hz) else { continue }
                let s = w.ships.spawnVessel(role, home: IVec3(hx, y + 1, hz), game: g, yaw: atan2f(cosf(a), sinf(a)))
                s.home = g.player.pos
                SeaHunt.hunters.insert(s.id)
                Corsairs.landed.insert(s.id)
                if role == NavalPatrol.role { s.name = SeaHunt.cruiserName; for m in g.mobs.mobs where m.deck === s { Corsairs.dress(m) } }
            }
            g.player.yaw = .pi; g.player.pitch = -0.05
            print("framesoak: \(SeaHunt.hunters.count) hunters out for him")
        }
        return sc
    }

    // Item 7, the worst case: the crawler parked by the citadel firing into it, two frigates shelling him, rain at night.
    static func worstScene() -> Setup {
        var sc = crawlerScene(parkedBy: true)
        let prep = sc.prepare
        sc.name = "worst"
        sc.what = "item 7: the crawler firing into a citadel, two hostile frigates shelling him, rain at night"
        sc.prepare = { g in
            g.time = 0.75 * DAY_LENGTH
            prep(g)
            let w = g.world
            let x = Int(floor(g.player.pos.x)), z = Int(floor(g.player.pos.z))
            w.ships.spawnCapital("capfrigate", home: IVec3(x - 30, 0, z + 90), yaw: 0, region: nil, sync: true)
            w.ships.spawnCapital("capfrigate", home: IVec3(x - 110, 0, z - 30), yaw: .pi / 2, region: nil, sync: true)
            g.weather.raining = true; g.weather.rain = 1
            g.survival = true; g.difficulty = 2
            print("framesoak: \(w.ships.capitals.count) capitals about him")
        }
        let step = sc.step
        sc.step = { g, f in
            g.weather.raining = true; g.weather.rainTime = 600
            g.survival = true; g.health = 20; g.alive = true
            step(g, f)
        }
        return sc
    }

    // Item 61 and item 8 (his Oct 31 16:21 note, a turret's shells through a building: "I literally saw the building in
    // half and it was all trying to fall", and the game crashed): five three-storey stone houses on corner pillars in a
    // row 26 blocks in front of him on the plains, one blown out from under every 7 s (two pillars, then its wall high
    // up), the load checks finding what no longer stands and the pieces coming down whole or block by block.
    static func collapseScene() -> Setup {
        let base = moving("collapse", "", seed: biomeSeed, x: 0, y: 70, z: 0, yaw: 0, pitch: -5, fly: false)
        var houses: [IVec3] = []                       // (each house's south-west corner on the ground)
        let side = 12, legs = 5, storeys = 3
        return Setup(name: "collapse", what: "item 61: five stone houses on pillars blown out from under, one every 7 s, 26 blocks in front of him",
                     seed: biomeSeed, at: base.at, prepare: { g in
            goTo(g, biome: "plains")
            base.prepare(g)
            g.player.yaw = 0; g.player.pitch = -5 * .pi / 180
            let w = g.world, bricks = Blocks.id("stone_bricks"), planks = Blocks.id("oak_planks"), glass = Blocks.has("glass") ? Blocks.id("glass") : AIR
            let px = Int(floor(g.player.pos.x)), pz = Int(floor(g.player.pos.z))
            Felling.toppled = 0; Structure.fallen = 0
            w.editBatch {
                for i in 0..<5 {
                    let x0 = px - 40 + i * 16, z0 = pz - 26 - side
                    var gy = 0
                    for z in z0..<(z0 + side) { for x in x0..<(x0 + side) { gy = max(gy, w.topY(x, z)) } }
                    let floorY = gy + legs
                    houses.append(IVec3(x0, gy, z0))
                    // (the four corner pillars, 2 x 2, from the ground up to the first floor)
                    for (cx, cz) in [(x0, z0), (x0 + side - 2, z0), (x0, z0 + side - 2), (x0 + side - 2, z0 + side - 2)] {
                        for z in cz...(cz + 1) { for x in cx...(cx + 1) {
                            var y = w.topY(x, z) + 1
                            while y < floorY { w.setBlock(x, y, z, bricks); y += 1 }
                        } }
                    }
                    for st in 0..<storeys {
                        let fy = floorY + st * 4
                        for z in z0..<(z0 + side) { for x in x0..<(x0 + side) {
                            let rim = x == x0 || x == x0 + side - 1 || z == z0 || z == z0 + side - 1
                            w.setBlock(x, fy, z, rim ? bricks : planks)
                            if rim {
                                for y in 1...3 {
                                    let win = y == 2 && (x - x0) % 4 == 2 || y == 2 && (z - z0) % 4 == 2
                                    w.setBlock(x, fy + y, z, win ? glass : bricks)
                                }
                            }
                        } }
                    }
                    let roof = floorY + storeys * 4
                    for z in z0..<(z0 + side) { for x in x0..<(x0 + side) { w.setBlock(x, roof, z, bricks) } }
                }
            }
            print("framesoak: \(houses.count) houses on pillars, \(storeys) storeys over \(legs - 1)-block legs")
        }, step: { g, f in
            g.player.vel.x = 0; g.player.vel.z = 0                                    // (he stands and watches)
            g.health = 20; g.alive = true
            // (house i: its two near pillars at 2 s + 7 s x i, its near wall's top storey half a second later)
            let t = f - 5 * 72, i = t / (7 * 72), k = t % (7 * 72)
            guard t >= 0, i < houses.count else { return }
            let h = houses[i], top = Float(h.y + legs + storeys * 4 - 2)
            let near = Float(h.z + side - 1)
            if k == 0 { Explosion.explode(at: V3(Float(h.x) + 1, Float(h.y) + 2, near), power: 4, game: g) }
            if k == 18 { Explosion.explode(at: V3(Float(h.x + side) - 1, Float(h.y) + 2, near), power: 4, game: g) }
            if k == 36 { Explosion.explode(at: V3(Float(h.x) + Float(side) / 2, top, near), power: 4, game: g) }
            if f == 5 * 72 + houses.count * 7 * 72 - 1 || k == 7 * 72 - 1 {
                print("framesoak: collapse after house \(i + 1): \(Structure.fallen) blocks fell, \(Felling.toppled) pieces came down whole, \(g.falling.count) falling now")
            }
        })
    }

    static var more: [Setup] {
        [biomeScene("desert", "walking through the middle of a desert", biome: "desert", fly: false),
         biomeScene("snowstorm", "walking the snowy plains in a snow storm (item 14: the snow slowdown)", biome: "snowy_plains", fly: false, storm: true),
         biomeScene("swamp", "walking through a swamp", biome: "swamp", fly: false),
         biomeScene("peaks", "flying at the creative sprint over jagged peaks", biome: "jagged_peaks", fly: true),
         biomeScene("ocean", "flying at the creative sprint over the deep ocean", biome: "deep_ocean", fly: true),
         biomeScene("night", "walking a dark forest at midnight in a thunderstorm, the night's mobs about", biome: "dark_forest", fly: false, storm: true, night: true),
         biomeScene("badlands", "walking through the badlands", biome: "badlands", fly: false),
         biomeScene("cherry", "walking through a cherry grove", biome: "cherry_grove", fly: false),
         townScene("village", "walking into a village, its people about", kind: "village"),
         townScene("city", "walking into the capital city, its garrison about", kind: "capital_city"),
         hollowScene(), frigateScene(),
         trainScene(.cargo, name: "freight"), trainScene(.troop, name: "troops"),
         seaHuntScene(), worstScene(), collapseScene()]
    }

    static var scenes: [Setup] { ordinary + [crawlerScene(parkedBy: false), crawlerScene(parkedBy: true), navalScene(), trainScene(), hellScene(), battleScene()] + more }

    struct Slow { var cpu: Double; var tick: Double; var record: Double; var why: String }

    static func run(ctx: VkContext) -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        QuestApp.headsetWorld()                                                       // (as on the headset)
        // (as the game runs, not the host checks' fixtures: bases planned on workers, the headset's world rules)
        StructureCache.plansOffThread = true
        World.resultsProfile = true                                                // (the slowest single hand-over, per scene)
        ShipManager.stepRate = 72; ShipManager.stepSlack = 0.2 / 72                // (QuestApp: one ship step a drawn frame)
        Blueprints.on = true; TownSizes.on = true; MobVary.on = true; Soldier.unarmedPeace = true
        World.fewerLakesUnsaved = true; World.lessWaterUnsaved = true; WorldRules.p44 = true
        SceneRenderer.skipGPU = true
        let only = arg("--only").map { Set($0.split(separator: ",").map(String.init)) }
        let secs = Int(arg("--seconds") ?? "") ?? 40
        let rd = Int(arg("--rd") ?? "") ?? 10
        print(String(format: "framesoak: %d s a scene in real time at 72 Hz, view %d, %d cores; the headset's frame thread taken as %.1fx the host's (budget %.1f ms there = %.1f ms here)",
                     secs, rd, ProcessInfo.processInfo.activeProcessorCount, questFactor, budgetMs, hostBudgetMs))
        var bad = 0
        var table: [String] = []
        for sc in scenes where only == nil || only!.contains(sc.name) {
            do { let (ok, line) = try scene(sc, rd: rd, secs: secs, ctx: ctx); table.append(line); if !ok { bad += 1 } }
            catch { print("framesoak: \(sc.name): \(error)"); return 1 }
        }
        print("framesoak summary (headset estimate; a miss = a frame thread over \(String(format: "%.1f", budgetMs)) ms there):")
        for l in table { print("  " + l) }
        return bad == 0 ? 0 : 1
    }

    static func pct(_ a: [Double], _ p: Int) -> Double { a.isEmpty ? 0 : a.sorted()[min(a.count - 1, a.count * p / 100)] }

    // Week item 63 ("zero void gaps: an automated void count in every soak, held at zero"; FAILURES 4): once a scene's
    // frames are done, eight probe shots from where it ended (four quarters round him, 25 and 50 degrees down; the frame
    // cleared to magenta with no sky drawn, RenderTest.countVoid) count the pixels below the horizon that the sky shows
    // through. Not in the Hollow, whose islands hang over open sky. --novoids leaves it out.
    static func voidCheck(_ g: Game, ctx: VkContext, scene: SceneRenderer, wr: WorldRenderer) -> (holes: Int, below: Int, backstop: Int, worst: String)? {
        guard g.dim.dim != .end, !CommandLine.arguments.contains("--novoids") else { return nil }
        // (the soak drops its frames' GPU commands, SceneRenderer.skipGPU: these shots are drawn; build 257's were not, and
        // read back whatever the buffer's memory held before)
        let probe0 = WorldRenderer.voidProbe, skip0 = WorldRenderer.debugSkip, gpu0 = SceneRenderer.skipGPU
        let pos0 = g.player.pos, yaw0 = g.player.yaw, pitch0 = g.player.pitch
        WorldRenderer.voidProbe = true; WorldRenderer.debugSkip.insert("sky"); SceneRenderer.skipGPU = false
        defer {
            WorldRenderer.voidProbe = probe0; WorldRenderer.debugSkip = skip0; SceneRenderer.skipGPU = gpu0
            g.player.pos = pos0; g.player.yaw = yaw0; g.player.pitch = pitch0
        }
        let size = 256, fov: Float = 90
        guard let rig = try? RenderTest.ShotRig(game: g, scene: scene, wr: wr, ctx: ctx, width: size, height: size, fovDeg: fov, ring: true) else { return nil }
        let eye = g.player.eye
        var holes = 0, below = 0, backstop = 0, worst = (0, "")
        var first = true
        ParticleManager.drawnCount = 0; ParticleManager.darkCount = 0
        defer { print("    void shots: particles drawn \(ParticleManager.drawnCount), with no light at all \(ParticleManager.darkCount) (ledger 64)") }
        for down in [25, 50] as [Float] { for k in 0..<4 {
            let yaw = yaw0 + Float(k) * .pi / 2, pitch = -down * .pi / 180
            guard let img = try? rig.grab(eye: eye, yaw: yaw, pitch: pitch, frames: first ? 3 : 2) else { continue }
            first = false
            let c = RenderTest.countVoid(img, width: size, height: size, eyes: 1, fovDeg: fov, pitch: pitch)
            holes += c.holes; below += c.below; backstop += c.backstop
            // (BS_VOIDSHOTS=DIR: every shot saved there, each hole ringed in green)
            if let dir = ProcessInfo.processInfo.environment["BS_VOIDSHOTS"] {
                var m = img
                for (mx, my) in c.marks { for dy in -3...3 { for dx in -3...3 where abs(dx) == 3 || abs(dy) == 3 {
                    let x = mx + dx, y = my + dy
                    guard x >= 0, y >= 0, x < size, y < size else { continue }
                    let i = (y * size + x) * 4
                    m[i] = 0; m[i + 1] = 255; m[i + 2] = 0
                } } }
                let path = String(format: "%@/void-%.0f-%.0f-%.0f.png", dir, eye.x, eye.z, yaw * 180 / .pi + down * 1000)
                try? PNG.encode(rgba: m, width: size, height: size).write(to: URL(fileURLWithPath: path))
            }
            if c.holes > worst.0 {
                // (as questcheck --view takes it: --at the feet, internal y; --look yaw is the player's yaw negated)
                worst = (c.holes, String(format: "--at %.1f,%.1f,%.1f --look %.0f,%.0f: %d", pos0.x, pos0.y, pos0.z, -yaw * 180 / .pi, -down, c.holes))
            }
        } }
        return (holes, below, backstop, worst.1)
    }

    static func scene(_ sc: Setup, rd: Int, secs: Int, ctx: VkContext) throws -> (Bool, String) {
        let device = sharedSystemDevice
        TextureGen.registerAll()
        let w = World(seed: sc.seed, device: device, save: nil, dim: sc.dim)
        let field = sc.dim == .overworld
        if field { FieldTerrain.newWorlds = true; w.makeFieldWorld() }
        w.renderDistance = rd
        let g = Game(world: w, save: nil, persistent: false)
        g.smoothTerrain = field
        SmoothTerrain.use(world: field, world: w)
        g.survival = false
        g.paused = false
        g.input.captured = true
        g.time = 0.2 * DAY_LENGTH
        g.player.flying = true
        g.player.pos = sc.at
        let a0 = CFAbsoluteTimeGetCurrent()
        _ = w.loadSync(center: g.player.pos, radius: rd)
        StructureCache.plansOffThread = false                            // (the scene's own lookups answered at once)
        sc.prepare(g)
        _ = g.spawnPoint                                // (a save has it; a fresh game settles it at its spawn, not mid-soak)
        StructureCache.plansOffThread = true
        let plansMs = QuestWarmup.structures(g)                          // (as the game's loading does)
        TownVoice.ensure()                                               // (and this)
        QuestWarmup.lines()                                              // (and the lines' needs, on a worker)
        // (Nov 5: and the rings' first builds, which the game's loading does too: the soak built the middle ring's
        // first 17k columns in its first frame, 3.7 G instructions under callgrind, a frame no player has)
        HorizonRing.shared.request(g, eye: g.player.eye)
        FarRing.shared.request(g, eye: g.player.eye)
        let loadS = CFAbsoluteTimeGetCurrent() - a0

        let scene = try SceneRenderer(ctx: ctx, device: device as! QuestDevice, views: 2, colorFormat: VK_FORMAT_R8G8B8A8_UNORM)
        try scene.uploadTextures()
        let wr = WorldRenderer(scene: scene, game: g)
        wr.landmarkHost = Renderer(game: g)
        let size = 48
        let img = try VkImg(ctx, width: size, height: size, layers: 2, format: VK_FORMAT_R8G8B8A8_UNORM,
                            usage: VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT.rawValue | VK_IMAGE_USAGE_TRANSFER_SRC_BIT.rawValue)
        let targets = [try scene.makeTarget(image: img.image, width: size, height: size), try scene.makeTarget(image: img.image, width: size, height: size)]
        let t = tanf(52 * .pi / 180)
        func camera() -> EyeCamera {
            let gw = g.world
            let ringFar: Float = FarRing.enabled && gw.dim == Dim.overworld ? FarRing.outer + 96 : 0
            let ships = gw.ships.list.contains { $0.kinematic }
            let far = max(Float(gw.renderDistance * 16 + 96), ringFar, ships ? 1000 : 0)
            let proj = XRMath.projection(tanLeft: -t, tanRight: t, tanUp: t * 0.95, tanDown: -t * 0.95, near: 0.05, far: far)
            let head = simd_quatf(angle: g.player.yaw, axis: V3(0, 1, 0)) * simd_quatf(angle: g.player.pitch, axis: V3(1, 0, 0))
            let vps = ([-0.032, 0.032] as [Float]).map { proj * XRMath.inversePose(head, head.act(V3($0, 0, 0))) }
            return EyeCamera(center: g.player.eye, viewProj: vps, cullViewProj: proj * XRMath.inversePose(head, V3(0, 0, 0)),
                             yaw: g.player.yaw, pitch: g.player.pitch, far: far)
        }
        let dt = 1.0 / 72
        var cpu: [Double] = [], ticks: [Double] = [], recs: [Double] = [], quads: [Double] = [], draws: [Double] = []
        var slow: [Slow] = []
        var misses = 0, run = 0, longest = 0
        // (the frame thread's own CPU time too: on the 4-core host the mesh and gen workers can take its core for a few
        // ms; a missed frame whose CPU time fits the budget was the host's scheduler, not the game's work)
        var cpuMisses = 0, cpuRun = 0, cpuLongest = 0
        @inline(__always) func threadMs() -> Double {
            var ts = timespec()
            clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
            return Double(ts.tv_sec) * 1000 + Double(ts.tv_nsec) / 1e6
        }
        let frames = secs * 72
        let warm = 3 * 72                                                    // (the first 3 s: first meshes in, not counted)
        World.resultsWorstMs = 0; World.resultsWorst = ""; Explosion.worstMs = 0; Explosion.worstLaps = ""; StructureTip.worstMs = 0; StructureTip.worstSplit = ""; Felling.worstMs = 0; Felling.worstSplit = ""; Structure.dropWorstMs = 0; Structure.dropWorst = ""; Structure.crumbMs = 0; Structure.crumbN = 0; CraterJob.worstStepMs = 0; CraterJob.worstStep = ""; CraterJob.finesUnfetched = 0; CraterJob.stepsUnfetched = 0; CraterJob.unfetchedPhases = [:]; StructureCache.framePlans = []; Structure.tally = [:]; let checks0 = Structure.checks, loadMs0 = Structure.totalMs; Structure.worstMs = 0
        let t0 = CFAbsoluteTimeGetCurrent()
        var mobsPeak = 0, shellsPeak = 0
        var stages: [String: (Double, Double)] = [:]
        // (SOAK_MOBPROF=1: the slowest single mob update and where it went; off by default, its clock reads and strings
        // weigh on the mob tick being measured)
        let mobProf = ProcessInfo.processInfo.environment["SOAK_MOBPROF"] == "1"
        MobManager.profileOn = mobProf
        RandomTickRng.track = mobProf; RandomTickRng.worstMs = 0; RandomTickRng.worstWhat = ""; RandomTickRng.frameWorstMs = 0; RandomTickRng.frameWorst = ""; RandomTickRng.drawCpu = 0; RandomTickRng.drawTicks = 0
        defer { MobManager.profileOn = false; RandomTickRng.track = false }
        var worstMob = (0.0, "")
        for f in 0..<(frames + warm) {
            if g.menu != nil { g.closeMenu() }
            g.cine.active = false
            g.input.keys.removeAll(keepingCapacity: true)
            g.input.captured = true
            sc.step(g, f)
            let a = CFAbsoluteTimeGetCurrent()
            let ta = threadMs()
            g.tick(dt)
            let tk = (CFAbsoluteTimeGetCurrent() - a) * 1000
            let tickWhy = TickProf.summary()
            if mobProf && f >= warm && MobManager.prof.worst > worstMob.0 {
                worstMob = (MobManager.prof.worst, MobManager.prof.worstKind + ": " + MobManager.worstStages
                            + (MobManager.partSummary.isEmpty ? "" : "; loop " + MobManager.partSummary))
            }
            if f >= warm {
                for i in 0..<TickProf.count {
                    let k = TickProf.names[i].description, ms = TickProf.times[i] * 1000
                    let o = stages[k] ?? (0, 0)
                    stages[k] = (o.0 + ms, max(o.1, ms))
                }
            }
            let s = scene.beginFrame()
            let b = CFAbsoluteTimeGetCurrent()
            wr.record(s, targets[f % 2], camera())
            let rc = (CFAbsoluteTimeGetCurrent() - b) * 1000
            vkCmdEndRenderPass(s.cmd)
            let own = threadMs() - ta
            try scene.submit(s)
            if f >= warm {
                let c = tk + rc
                if own * questFactor > budgetMs { cpuMisses += 1; cpuRun += 1; cpuLongest = max(cpuLongest, cpuRun) } else { cpuRun = 0 }
                cpu.append(c); ticks.append(tk); recs.append(rc)
                quads.append(Double(scene.drawnQuads)); draws.append(Double(scene.drawCalls))
                mobsPeak = max(mobsPeak, g.mobs.mobs.count); shellsPeak = max(shellsPeak, g.world.ships.shells.count)
                if c * questFactor > budgetMs {
                    misses += 1; run += 1; longest = max(longest, run)
                    if slow.count < 400 {
                        let st = wr.stageFrame
                        let top = st.indices.sorted { st[$0] > st[$1] }.prefix(2)
                            .map { "\(WorldRenderer.stageNames[min($0, WorldRenderer.stageNames.count - 1)]) \(String(format: "%.1f", st[$0]))" }.joined(separator: " + ")
                        slow.append(Slow(cpu: c, tick: tk, record: rc, why: "tick: \(tickWhy); record: \(top); own CPU \(String(format: "%.1f", own))"))
                    }
                } else { run = 0 }
            }
            // Paced as the headset paces its frames (xrWaitFrame), so the mesh and gen workers get the time they get there.
            let due = t0 + Double(f + 1) * dt
            let now = CFAbsoluteTimeGetCurrent()
            if due > now { usleep(useconds_t((due - now) * 1_000_000)) }
        }
        scene.waitIdle()
        let voids = voidCheck(g, ctx: ctx, scene: scene, wr: wr)
        let n = Double(max(1, cpu.count))
        let mean = cpu.reduce(0, +) / n
        print(String(format: "framesoak %@ (%@): loaded in %.1f s (starts round him %.0f ms); %d frames; peak %d mobs, %d shells in flight, %d ships",
                     sc.name, sc.what, loadS, plansMs, cpu.count, mobsPeak, shellsPeak, g.world.ships.list.count))
        print(String(format: "    frame thread (host ms): mean %.2f p95 %.2f p99 %.2f worst %.1f; tick mean %.2f p99 %.2f worst %.1f; record mean %.2f p99 %.2f worst %.1f",
                     mean, pct(cpu, 95), pct(cpu, 99), cpu.max() ?? 0, ticks.reduce(0, +) / n, pct(ticks, 99), ticks.max() ?? 0,
                     recs.reduce(0, +) / n, pct(recs, 99), recs.max() ?? 0))
        print(String(format: "    headset estimate: mean %.1f ms, p99 %.1f ms, worst %.0f ms; %d frames of %d over %.1f ms (%.2f%%), longest run %d",
                     mean * questFactor, pct(cpu, 99) * questFactor, (cpu.max() ?? 0) * questFactor, misses, cpu.count, budgetMs, Double(misses) * 100 / n, longest))
        print(String(format: "    by the frame thread's own CPU time: %d frames over (%.2f%%), longest run %d (the rest of the misses: the host's scheduler)",
                     cpuMisses, Double(cpuMisses) * 100 / n, cpuLongest))
        print(String(format: "    GPU load: quads p50 %.0fk p95 %.0fk max %.0fk; draws p50 %.0f p95 %.0f max %.0f",
                     pct(quads, 50) / 1000, pct(quads, 95) / 1000, (quads.max() ?? 0) / 1000, pct(draws, 50), pct(draws, 95), draws.max() ?? 0))
        print("    tick stages (mean/worst ms): " + stages.sorted { $0.value.0 > $1.value.0 }.prefix(10)
            .map { "\($0.key) \(String(format: "%.2f/%.1f", $0.value.0 / n, $0.value.1))" }.joined(separator: ", "))
        print("    tick stages by worst (ms): " + stages.sorted { $0.value.1 > $1.value.1 }.prefix(8)
            .map { "\($0.key) \(String(format: "%.1f", $0.value.1))" }.joined(separator: ", "))
        if ProcessInfo.processInfo.environment["BS_RCPROBE"] == "1" { print("    side tables: " + RefcountProbe.census(g)) }
        if Explosion.worstMs > 0 { print(String(format: "    slowest blast: %.1f ms (%@)", Explosion.worstMs, Explosion.worstLaps)) }
        if StructureTip.worstMs > 0 { print(String(format: "    slowest collapse check: %.1f ms (%@)", StructureTip.worstMs, StructureTip.worstSplit)) }
        if StructureTip.tipVerify { print("    tip checks run both ways (BS_TIPVERIFY): \(StructureTip.verified), differing \(StructureTip.verifyDiffs)") }
        if Structure.loadVerify { print("    " + Structure.verifyLine) }
        if SoldierRig.clearVerify { print("    soldier clears run both ways (BS_CLEARVERIFY): \(SoldierRig.clearVerified), differing \(SoldierRig.clearVerifyDiffs)"); SoldierRig.clearVerified = 0; SoldierRig.clearVerifyDiffs = 0 }
        if Felling.worstMs > 0 { print(String(format: "    slowest piece brought down whole: %.1f ms (%@)", Felling.worstMs, Felling.worstSplit)) }
        if Structure.dropWorstMs > 0 { print(String(format: "    slowest load-check fall: %.1f ms (%@); crumbs %d blocks in %.1f ms, %.1f us a block", Structure.dropWorstMs, Structure.dropWorst,
                                                    Structure.crumbN, Structure.crumbMs, Structure.crumbN > 0 ? Structure.crumbMs * 1000 / Double(Structure.crumbN) : 0)) }
        if CraterJob.worstStepMs > 0 { print(String(format: "    slowest bowl step: %.1f ms (%@)", CraterJob.worstStepMs, CraterJob.worstStep)) }
        if CraterJob.worstStepMs > 0 {
            let byPhase: [String] = CraterJob.unfetchedPhases.sorted { $0.value > $1.value }.map { "\($0.key) \($0.value)" }
            let detail = byPhase.isEmpty ? "" : ": " + byPhase.joined(separator: ", ")
            print("    bowl steps that made fine sections past a prefetch: \(CraterJob.stepsUnfetched) (\(CraterJob.finesUnfetched) sections\(detail))")
        }
        if worstMob.0 > 0 { print(String(format: "    slowest mob update: %.1f ms (%@)", worstMob.0, worstMob.1)) }
        if RandomTickRng.worstMs > 0 && mobProf { print(String(format: "    slowest random tick: %.1f ms (%@)", RandomTickRng.worstMs, RandomTickRng.worstWhat)) }
        if RandomTickRng.frameWorstMs > 0 && mobProf { print(String(format: "    dearest frame of random ticks: %.1f ms (%@)", RandomTickRng.frameWorstMs, RandomTickRng.frameWorst)) }
        if mobProf {
            // (BlockStore.tickMask: every loaded chunk's sections passed over must hold nothing that ticks)
            var sections = 0, skipped = 0, misses = 0
            for c in w.chunks.values where !c.hollow {
                let top = min(NSEC - 1, (max(0, c.heightMax) + 1) >> 4)
                sections += top + 1
                for sy in 0...top where c.blocks.tickMask & (1 << UInt32(sy)) == 0 { skipped += 1 }
                misses += c.blocks.tickMaskMisses()
            }
            print(String(format: "    random tick sections: %d of %d passed over (nothing in them ticks); passed over but holding a ticking cell: %d; the draws' own CPU %.3f ms a game tick (%d ticks)",
                         skipped, sections, misses, RandomTickRng.drawTicks > 0 ? RandomTickRng.drawCpu / Double(RandomTickRng.drawTicks) : 0, RandomTickRng.drawTicks))
        }
        if let t = Structure.tally, !t.isEmpty {
            let top = t.sorted { $0.value > $1.value }.prefix(6).map { "\($0.key) \($0.value)" }.joined(separator: ", ")
            print(String(format: "    building checks: %d run, %.1f ms in the fills (worst %.2f ms); queued by %@", Structure.checks - checks0, Structure.totalMs - loadMs0, Structure.worstMs, top))
        }
        Structure.tally = nil
        if !StructureCache.framePlans.isEmpty { print("    starts planned on the frame thread: " + StructureCache.framePlans.joined(separator: ", ")) }
        if let v = voids {
            print(String(format: "    voids (week item 63): %d of %d pixels below the horizon show the sky through, in 8 views from where the soak ended%@; fog floor only %d",
                         v.holes, v.below, v.holes > 0 ? " (most at " + v.worst + ")" : "", v.backstop))
        }
        print("    record stages (ms a frame): " + wr.takeStages())
        print(String(format: "    slowest hand-over of a finished job: %.1f ms (%@)", World.resultsWorstMs, World.resultsWorst))
        // What the slow frames were doing: the most common slowest stage, and the five slowest frames.
        var why: [String: Int] = [:]
        for s in slow { why[String(s.why.split(separator: ";").first ?? ""), default: 0] += 1 }
        if !slow.isEmpty {
            print("    slow frames' tick leaders: " + why.sorted { $0.value > $1.value }.prefix(6).map { "\($0.key) x\($0.value)" }.joined(separator: ", "))
            for s in slow.sorted(by: { $0.cpu > $1.cpu }).prefix(6) {
                print(String(format: "    slow: %.1f ms (tick %.1f, record %.1f): %@", s.cpu, s.tick, s.record, s.why))
            }
        }
        PadManager.shared.touch = nil
        withExtendedLifetime((img, targets, wr)) {}
        let fast = Double(misses) / n < 0.005 && longest < 3, holes = voids?.holes ?? 0
        let ok = fast && holes == 0
        let line = String(format: "%@ %@: mean %.1f ms, p99 %.1f, worst %.0f; %d misses (%.2f%%), longest run %d; quads p95 %.0fk%@",
                          ok ? "ok  " : (fast ? "VOID" : "SLOW"), sc.name, mean * questFactor, pct(cpu, 99) * questFactor, (cpu.max() ?? 0) * questFactor,
                          misses, Double(misses) * 100 / n, longest, pct(quads, 95) / 1000, voids.map { "; voids \($0.holes)" } ?? "")
        return (ok, line)
    }
}
