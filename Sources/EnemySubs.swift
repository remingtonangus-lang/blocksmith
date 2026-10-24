import Foundation
import simd

// Enemy submarines (backlog C8 leftover). Out over deep water a navy submarine now and then comes hunting the player:
// it closes under water, holds a depth near the player's, and looses a torpedo from its bow when in range. Hurt its
// hull (a sixth of it gone) and her crew gives up: she blows her tanks, surfaces, stops dead and shows the white flag
// of an "Abandoned Submarine". Board her and take the helm to claim her (ShipPlay.startPiloting marks her captured),
// a submarine of your own without a kit. At most one hunts at a time; none at peace (the Reckoning won), in creative,
// or on peaceful. A hunter left 400 blocks behind dives off and is gone. Her state is her name (saved with the ship):
// "Navy Submarine" hunts, "Abandoned Submarine" waits to be claimed.
enum EnemySub {
    static let name = "Navy Submarine"
    static let abandoned = "Abandoned Submarine"
    static let checkEvery: Double = 20
    static let cooldown: Double = 240            // seconds after one is gone before another may come
    static let spawnDist: Float = 70
    static let torpedoRange: Float = 60
    static let torpedoEvery: Float = 9
    static let giveUpAt = 85                     // percent of the hull left when the crew gives up
    static var nextCheck: Double = 0
    static var nextSpawn: Double = 90            // (the first not in the first minute and a half of a session)
    static var fireCD: [Int: Float] = [:]
    static var spawned = 0, surrendered = 0, torpedoes = 0   // counters (harness)

    static func hunting(_ s: Ship) -> Bool { s.parent == nil && s.name == name && !s.captured }

    // The depth of open water in a column: (surface y, seabed y) or nil when it's not 10+ deep.
    static func deep(_ w: World, _ x: Int, _ z: Int) -> (Int, Int)? {
        guard w.isLoaded(x, z), let top = Submarine.surface(w, x, z) else { return nil }
        var y = top
        while y > 1 && Blocks.fluidKind[Int(w.builtBlock(x, y - 1, z))] == 1 { y -= 1 }
        return top - y >= 10 ? (top, y) : nil
    }
}

extension Game {
    // Every tick (submarinesTick).
    func enemySubTick(_ dt: Float) {
        guard dim.dim == .overworld else { return }
        let ships = world.ships
        var live = 0
        for s in ships.list where EnemySub.hunting(s) {
            live += 1
            enemySubDrive(s, dt)
        }
        guard live == 0, clock >= EnemySub.nextCheck else { return }
        EnemySub.nextCheck = clock + EnemySub.checkEvery
        guard clock >= EnemySub.nextSpawn, survival, difficulty > 0, alive, !Reckoning.won else { return }
        let p = player.pos
        guard EnemySub.deep(world, Int(floor(p.x)), Int(floor(p.z))) != nil else { return }
        // P434 (e): no hunt while the player rides a ship that isn't a submarine (the frigate, an airship).
        if let on = ships.aboardOrPilot, on.root.ballast == 0 { return }
        guard Rand.float(in: 0..<1) < 0.35 else { return }
        let a0 = Rand.float(in: 0..<(2 * .pi))
        for k in 0..<8 {
            let a = a0 + Float(k) * .pi / 4
            let c = p + V3(cosf(a), 0, sinf(a)) * EnemySub.spawnDist
            let cx = Int(floor(c.x)), cz = Int(floor(c.z))
            guard let (top, bed) = EnemySub.deep(world, cx, cz) else { continue }
            var ok = true
            for dz in [-5, 0, 5] { for dx in [-5, 0, 5] where EnemySub.deep(world, cx + dx, cz + dz) == nil { ok = false } }
            guard ok else { continue }
            let yaw = atan2f(c.x - p.x, c.z - p.z)                 // bow (-Z) toward the player
            let s = ships.spawn(Submarine.blueprint(), at: V3(c.x, Float(top) + 1, c.z), yaw: yaw, name: EnemySub.name, role: "")
            s.role = nil
            s.faction = Faction.meridian.rawValue
            let keel = Float(min(top - 6, bed + 4))
            s.pos.y += keel - s.toWorld(V3(0, s.localMin.y, 0)).y
            s.prevPos = s.pos
            s.depthY = s.pos.y
            s.updateBounds()
            s.initialBlocks = s.blockCount
            EnemySub.spawned += 1
            EnemySub.fireCD[s.id] = 6
            onToast?("Sonar contact: a navy submarine is hunting you")
            sfx(.click, 1.3, at: p)
            return
        }
    }

    private func enemySubDrive(_ s: Ship, _ dt: Float) {
        let p = player.pos
        let to = V2(p.x - s.pos.x, p.z - s.pos.z)
        let d = simd_length(to)
        // Left far behind: she dives off and is gone.
        let onShip = world.ships.aboardOrPilot.map { $0.root.ballast == 0 } ?? false
        if d > 400 || !alive || (onShip && d > EnemySub.torpedoRange) {
            world.ships.remove(s)
            EnemySub.nextSpawn = clock + EnemySub.cooldown
            return
        }
        let x = Int(floor(s.pos.x)), z = Int(floor(s.pos.z))
        let col = EnemySub.deep(world, x, z)
        // Hull hurt: the crew gives up and she surfaces (the player claims her at the helm).
        if s.blockCount * 100 < s.initialBlocks * EnemySub.giveUpAt || s.helm == nil || Reckoning.won {
            s.name = EnemySub.abandoned
            s.autopilot = V3(0, 0, 0)
            if let (top, _) = col { s.depthY = Float(top) + 2 }
            EnemySub.surrendered += 1
            EnemySub.nextSpawn = clock + EnemySub.cooldown
            if d < 200 { onToast?("The navy submarine blows her tanks and surfaces: her crew gives up") }
            sfx(.splash, 1, at: s.pos)
            return
        }
        // Steer for the player; hold a depth near theirs, clear of the bed and the surface.
        let f = s.dirToWorld(s.fwd)
        let fh = simd_normalize(V2(f.x, f.z) + V2(1e-5, 0))
        let want = d > 1 ? to / d : fh
        var cross = fh.x * want.y - fh.y * want.x
        if simd_dot(fh, want) < 0 { cross = cross >= 0 ? 1 : -1 }
        // Shallows ahead: turn away from them.
        let ahead = s.pos + V3(fh.x, 0, fh.y) * 10
        if EnemySub.deep(world, Int(floor(ahead.x)), Int(floor(ahead.z))) == nil { cross = 1 }
        let throttle: Float = d > 30 ? 1 : 0.4
        s.autopilot = V3(throttle, max(-1, min(1, cross * 2)), 0)
        if let (top, bed) = col {
            let lo = Float(bed + 3), hi = Float(top - 4)
            if lo < hi { s.depthY = max(lo, min(hi, p.y - 1)) }
        }
        // A torpedo from the bow when the player is ahead and in range.
        var cd = (EnemySub.fireCD[s.id] ?? EnemySub.torpedoEvery) - dt
        if cd <= 0 && d < EnemySub.torpedoRange && simd_dot(fh, want) > 0.9 && s.submerged > 1 {
            cd = EnemySub.torpedoEvery
            let bow = s.toWorld(V3(0, 1.5, -5.5))
            let aim = simd_normalize(p + V3(0, 0.5, 0) - bow + V3(1e-5, 0, 0))
            let horiz = simd_normalize(V3(aim.x, max(-0.3, min(0.3, aim.y)), aim.z))
            let sh = Shell(pos: bow, vel: horiz * Submarine.torpedoSpeed + s.vel, owner: s.id, power: 3)
            sh.kind = 4; sh.gravity = 0; sh.life = Submarine.torpedoLife
            world.ships.shells.append(sh)
            EnemySub.torpedoes += 1
            sfx(.splash, 0.8, at: bow)
            if d < 80 { onToast?("Torpedo in the water!") }
        }
        EnemySub.fireCD[s.id] = cd
    }
}
