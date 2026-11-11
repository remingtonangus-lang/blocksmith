import Foundation
import simd

// Pause menu > Shortcuts: teleports to the nearest notable structure (the same search as /locate) and back to spawn.
extension Game {
    static let shortcutList: [(String, String)] = [
        ("military_base", "Capital Citadel"), ("boreal_station", "Boreal Station"), ("capital_city", "Capital City"), ("crawler", "Ironback Crawler"), ("frigate", "Meridian Frigate"),
        ("warfrigate", "Stormwarden Frigate"), ("carriage", "Siege Carriage"), ("village", "Village"),
        ("pillager_outpost", "Marauder Watchtower"), ("mansion", "Brigand Roost"), ("monument", "Sunken Dreadnought"),
        ("temple", "Temple"), ("great_ruin", "Ancient Spire"), ("ancient_city", "Buried Citadel"),
        ("trial_chambers", "Sealed Armoury"), ("stronghold", "Stronghold"), ("greywall_base", "Greywall Base"), ("train", "Train")]

    // The nearest start of a shortcut target (x, z), nil if none is near.
    private func shortcutTarget(_ key: String) -> (Int, Int)? {
        let px = Int(player.pos.x), pz = Int(player.pos.z)
        if ["warfrigate", "crawler", "frigate", "carriage"].contains(key) {
            return vesselTarget(key).map { ($0.0.x, $0.0.z) }
        }
        if key == "train" { return trainTarget().map { ($0.0.x, $0.0.z) } }
        guard let s = world.gen.structures?.nearest(key, x: px, z: pz) ?? world.gen.structures?.nearest(key, x: px, z: pz, maxRegions: 40) else { return nil }
        return (s.anchor.x, s.anchor.z)
    }

    // The nearest vessel of a kind (/locate, Shortcuts): one already out (P437: a crawler on patrol is rarely at its
    // home point), else the nearest encounter region's home that is out in the world yet (Vessels.out).
    func vesselTarget(_ key: String) -> (IVec3, Float, Bool)? {
        let role = key == "frigate" ? "capfrigate" : key
        var best: (IVec3, Float, Bool)?
        for s in world.ships.list where s.role == role && !s.wrecked {
            let d = simd_length(V2(s.pos.x - player.pos.x, s.pos.z - player.pos.z))
            if best == nil || d < best!.1 { best = (IVec3(Int(floor(s.pos.x)), Int(floor(s.pos.y)), Int(floor(s.pos.z))), d, true) }
        }
        if best != nil { return best }
        return Game.vesselRegions(key, from: player.pos, seed: world.seed, gen: world.gen, fleetSails: fleetSails).map { ($0.0, $0.1, false) }
    }
    // The encounter regions' homes, nearest first out to 40 regions (no game state: also run on a worker, ledger 80).
    static func vesselRegions(_ key: String, from p: V3, seed: UInt64, gen: TerrainGenerator, fleetSails: Bool) -> (IVec3, Float)? {
        var best: (IVec3, Float)?
        let R = Vessels.region
        let rx = floorDiv(Int(p.x), R), rz = floorDiv(Int(p.z), R)
        for r in 0...40 { for dz in -r...r { for dx in -r...r where max(abs(dx), abs(dz)) == r {      // (P504: however far: was 12)
            guard let e = Vessels.encounter(seed: seed, rx: rx + dx, rz: rz + dz, gen: gen),
                  Vessels.out(e.0, fleetSails: fleetSails) else { continue }
            let match = e.0 == key || (e.0 == "battle" && (key == "warfrigate" || key == "crawler"))
            if !match { continue }
            let d = simd_length(V2(Float(e.1.x) - p.x, Float(e.1.z) - p.z))
            if best == nil || d < best!.1 { best = (e.1, d) }
        } }
        if best != nil && r >= 2 { break } }
        return best
    }

    // P504 (Nov 1 09:33, "...a crawler, a train or frigate"): the nearest train on the Surface: one running near him (its
    // locomotive), else where its timetable has it now on the nearest line out to 4,000 blocks. (point, distance, line)
    func trainTarget() -> (IVec3, Float, String)? {
        guard dim.dim == .overworld, let gen = world.gen as? WorldGen else { return nil }
        let p = player.pos
        var best: (IVec3, Float, String)?
        for tr in Trains.trains.values where !tr.wrecked && tr.track.dim == .overworld {
            guard let c = tr.cars.first else { continue }
            let d = simd_length(V2(c.pos.x - p.x, c.pos.z - p.z))
            if best == nil || d < best!.1 { best = (IVec3(Int(floor(c.pos.x)), Int(floor(c.pos.y)), Int(floor(c.pos.z))), d, tr.track.name) }
        }
        if best != nil { return best }
        return Game.trainLines(gen, from: p, time: time, cached: true)
    }
    // Where the timetables have trains now on the nearest lines (cached: the shared track cache, frame thread only).
    static func trainLines(_ gen: WorldGen, from p: V3, time: Double, cached: Bool) -> (IVec3, Float, String)? {
        var best: (IVec3, Float, String)?
        let x = Int(floor(p.x)), z = Int(floor(p.z))
        for r in [1500, 4000] {
            for l in Railways.near(gen, x0: x - r, z0: z - r, x1: x + r, z1: z + r, pad: 0) where !l.cells.isEmpty {
                let t = cached ? Trains.cachedTrack(l) : Trains.track(l)
                let c = t.cells[max(0, min(t.cells.count - 1, Int(t.at(time).s)))]
                let d = simd_length(V2(Float(c.x) - p.x, Float(c.z) - p.z))
                if best == nil || d < best!.1 { best = (c, d, t.name) }
            }
            if best != nil { break }
        }
        return best
    }

    // Ledger 78 (Nov 11, the VR fuzz's stack sampler): the landing spot was found by loading the chunks round it on the
    // frame (settleSpawn's loadSync), which also waited there for the railways' plan of that land: a 1.8 s freeze on
    // the host, 53-68 ms of it the frame's own work. On the headset (arrivalHold) he now waits at the target like any
    // trip (ledger 40: held, the view dark, while the workers load the ground) and the spot is found once it is there.
    // BS_OLDSHORTCUT=1: on the frame as before.
    static let oldShortcutLand = ProcessInfo.processInfo.environment["BS_OLDSHORTCUT"] == "1"
    private func shortcutLand(_ x: Int, _ z: Int, on: V3? = nil) {
        let g = world.gen.column(x, z).0
        let guess = on ?? V3(Float(x) + 0.5, Float(g + 2), Float(z) + 0.5)
        let land = { [unowned self] in
            let p = settleSpawn(guess)
            player.pos = p
            player.vel = .zero
            player.airPeak = p.y
        }
        if Game.arrivalHold && !Game.oldShortcutLand {
            player.pos = guess
            player.vel = .zero
            player.airPeak = guess.y
            arrivalSince = clock; arrivalOpened = -1; arrivalThen = land
            return
        }
        land()
    }

    func shortcutTeleport(_ key: String) {
        guard dim.dim == .overworld else { onToast?("Shortcuts work on the Surface"); return }
        if key == "spawn" {
            shortcutLand(Int(spawnPoint.x), Int(spawnPoint.z), on: spawnPoint)
            onToast?("Back at spawn")
            return
        }
        if Game.arrivalHold && !Game.oldShortcutLand { shortcutFind(key); return }
        shortcutArrive(key, shortcutTarget(key))
    }
    private func shortcutArrive(_ key: String, _ at: (Int, Int)?) {
        let name = Game.shortcutList.first { $0.0 == key }?.1 ?? key
        guard let (x, z) = at else {
            onToast?(key == "warfrigate" && !fleetSails ? "The Stormwarden Frigates sail once a Greywall Fortress falls" : "No \(name) found")
            return
        }
        shortcutLand(x, z)
        onToast?("Teleported to the \(name)")
    }

    // Ledger 80 (Nov 11, the VR fuzz's stack sampler: a frigate shortcut held one frame 685 ms): the search ran on the
    // frame, out to 40 rings of encounter regions (a terrain column read in each), or 40 rings of a structure's regions
    // planned there for a rare kind. On the headset the vessels and trains already out are looked at on the frame (the
    // game's own lists) and the rest of the search runs on a worker; the trip starts on the first frame after it is
    // done (shortcutFindTick, every frame, paused included). One search at a time. BS_OLDSHORTCUT=1: all on the frame.
    private func shortcutFind(_ key: String) {
        guard ShortcutFind.pending == nil else { return }
        let p = player.pos
        if ["warfrigate", "crawler", "frigate", "carriage"].contains(key) {
            let role = key == "frigate" ? "capfrigate" : key
            if let s = world.ships.list.filter({ $0.role == role && !$0.wrecked }).min(by: {
                simd_length(V2($0.pos.x - p.x, $0.pos.z - p.z)) < simd_length(V2($1.pos.x - p.x, $1.pos.z - p.z)) }) {
                shortcutArrive(key, (Int(floor(s.pos.x)), Int(floor(s.pos.z)))); return
            }
        }
        if key == "train", let c = Trains.trains.values.filter({ !$0.wrecked && $0.track.dim == .overworld }).compactMap({ $0.cars.first }).min(by: {
            simd_length(V2($0.pos.x - p.x, $0.pos.z - p.z)) < simd_length(V2($1.pos.x - p.x, $1.pos.z - p.z)) }) {
            shortcutArrive(key, (Int(floor(c.pos.x)), Int(floor(c.pos.z)))); return
        }
        ShortcutFind.pending = key
        let seed = world.seed, gen = world.gen, fleet = fleetSails, t = time, sc = world.gen.structures
        DispatchQueue.global(qos: .userInitiated).async {
            var at: (Int, Int)?
            if ["warfrigate", "crawler", "frigate", "carriage"].contains(key) {
                at = Game.vesselRegions(key, from: p, seed: seed, gen: gen, fleetSails: fleet).map { ($0.0.x, $0.0.z) }
            } else if key == "train" {
                if let wg = gen as? WorldGen { at = Game.trainLines(wg, from: p, time: t, cached: false).map { ($0.0.x, $0.0.z) } }
            } else if let s = sc?.nearest(key, x: Int(p.x), z: Int(p.z)) ?? sc?.nearest(key, x: Int(p.x), z: Int(p.z), maxRegions: 40) {
                at = (s.anchor.x, s.anchor.z)
            }
            ShortcutFind.lock.lock(); ShortcutFind.found = (key, at); ShortcutFind.lock.unlock()
        }
    }
    func shortcutFindTick() {
        guard let key = ShortcutFind.pending else { return }
        ShortcutFind.lock.lock(); let f = ShortcutFind.found; ShortcutFind.found = nil; ShortcutFind.lock.unlock()
        guard let f, f.0 == key else { return }
        ShortcutFind.pending = nil
        guard dim.dim == .overworld, alive else { return }               // (he left the Surface or died meanwhile)
        shortcutArrive(key, f.1)
    }
}

// A shortcut's search on a worker (ledger 80): the key searched for (frame thread) and the answer (under the lock).
enum ShortcutFind {
    static let lock = NSLock()
    static var pending: String?
    static var found: (String, (Int, Int)?)?
}
