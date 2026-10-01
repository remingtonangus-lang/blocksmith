import Foundation
import simd

// The player and ships: moving in a ship's frame while aboard, steering from the helm, and breaking,
// placing and using blocks on ships. Controls at the helm (keyboard / controller):
//   W/S, left stick up/down     throttle (propellers, wheels; the helm alone paddles a boat slowly)
//   A/D, left stick left/right  turn (aircraft also bank)
//   Space / A or RB             climb (airships: more lift; aircraft: nose up)
//   Ctrl / LB                   descend (airships: less lift; aircraft: nose down)
//   look                        turrets turn to the view
//   attack (click / RT)         fire the cannons (elevated to the view pitch)
//   Shift / B                   leave the helm
// Using a helm that isn't part of a ship assembles everything connected to it; sneak-using the helm of a
// ship docks it back into the world, snapped to the block grid.
extension Game {
    // Player movement, in a ship's frame when aboard one (replaces player.update in Game.tick).
    func shipPlayerUpdate(_ dt: Float, _ mi: MoveInput) {
        let ships = world.ships
        if ships.isEmpty {
            ships.aboard = nil
            player.update(dt: dt, input: mi, world: world)
            return
        }
        if let s = ships.pilot {
            if pilotTick(s, mi, dt) { return }
        }
        guard let s = ships.frameShip(for: player.pos, height: player.height, current: ships.aboard) else {
            ships.aboard = nil
            player.update(dt: dt, input: mi, world: world)
            return
        }
        ships.aboard = s
        let p = player
        // Into ship space: position, velocity relative to the deck, heading.
        let w0 = p.pos
        let fall = p.airPeak - w0.y
        let yawOff = s.yaw
        p.vel = s.dirToLocal(p.vel - s.velocity(at: w0))
        p.pos = s.toLocal(w0)
        p.yaw -= yawOff
        p.airPeak = p.pos.y + fall
        world.frame = s
        p.update(dt: dt, input: mi, world: world)
        world.frame = nil
        // Back to world space.
        let fall2 = p.airPeak - p.pos.y
        let w1 = s.toWorld(p.pos)
        p.pos = w1
        p.vel = s.dirToWorld(p.vel) + s.velocity(at: w1)
        p.yaw += yawOff
        p.airPeak = w1.y + fall2
    }

    // /vessel frigate|carriage: summon one ahead; /vessel locate: the nearest encounter home.
    func vesselCommand(_ a: [String]) -> [String] {
        let ships = world.ships
        guard a.count >= 2 else { return ["Usage: /vessel <frigate|carriage|locate>"] }
        let f = V3(-sinf(player.yaw), 0, -cosf(player.yaw))
        switch a[1].lowercased() {
        case "frigate", "carriage":
            let at = player.pos + f * (a[1].lowercased() == "frigate" ? 50 : 30)
            let x = Int(floor(at.x)), z = Int(floor(at.z))
            let ground = world.topY(x, z)
            let s = ships.spawnVessel(a[1].lowercased(), home: IVec3(x, a[1].lowercased() == "frigate" ? max(ground, SEA) + 30 : ground + 1, z), game: self)
            return ["Summoned \(s.name) (\(s.blockCount) blocks)"]
        case "locate":
            let rx = floorDiv(Int(player.pos.x), Vessels.region), rz = floorDiv(Int(player.pos.z), Vessels.region)
            var best: (String, IVec3, Float)?
            for dz in -3...3 { for dx in -3...3 {
                guard let e = Vessels.encounter(seed: world.seed, rx: rx + dx, rz: rz + dz, gen: world.gen) else { continue }
                let d = simd_length(V2(Float(e.1.x) - player.pos.x, Float(e.1.z) - player.pos.z))
                if best == nil || d < best!.2 { best = (e.0, e.1, d) }
            } }
            guard let b = best else { return ["No vessel within \(Vessels.region * 3) blocks"] }
            let name = b.0 == "frigate" ? "Skyward Frigate" : "Ironstride Siege Carriage"
            return ["The nearest \(name) patrols around [\(b.1.x), ~, \(b.1.z)] (\(Int(b.2)) blocks away)"]
        default:
            return ["Unknown vessel \(a[1])"]
        }
    }

    // Third-person camera distance: farther back while steering, scaled to the ship.
    var thirdPersonDistance: Float {
        guard let s = world.ships.pilot else { return 4 }
        let size = simd_length(s.localMax - s.localMin)
        return max(4, min(48, size * 0.9))
    }

    // HUD while steering: speed, height above sea level, throttle and lift.
    func shipHUDLine() -> String? {
        guard let s = world.ships.pilot else { return nil }
        let sp = (s.vel.x * s.vel.x + s.vel.z * s.vel.z).squareRoot()
        var t = String(format: "%@  %.1f b/s  alt %d  throttle %d%%", s.name, sp, Int(s.pos.y) - YOFF, Int(s.throttle * 100))
        if s.balloons > 0 { t += String(format: "  lift %d%%", Int(s.liftLevel * 100)) }
        let guns = ([s] + world.ships.turrets(of: s)).reduce(0) { $0 + $1.cannons.count }
        if guns > 0 { t += s.reload > 0 || world.ships.turrets(of: s).contains(where: { $0.reload > 0 }) ? "  guns reloading" : "  guns ready" }
        return t
    }

    // Boss-style bars for crewed vessels near the player: name and how much of the hull is left.
    func shipBars() -> [(String, Float)] {
        var out: [(String, Float)] = []
        for s in world.ships.list where s.isVessel && s.parent == nil && !s.captured && s.initialBlocks > 0
            && simd_length(s.pos - player.pos) < 96 {
            out.append((s.name, Float(s.blockCount) / Float(s.initialBlocks)))
        }
        return out
    }

    // Where the pilot stands: on the pilot's side of the helm (its front).
    func helmStand(_ s: Ship) -> V3? {
        guard let h = s.helm else { return nil }
        let b = s.grid.get(h.x, h.y, h.z)
        let front = ShipParts.facingDir[ShipParts.facing(b)]
        return V3(Float(h.x) + 0.5, Float(h.y), Float(h.z) + 0.5) + front * 0.9
    }

    // Steering from the helm. Returns false when the player no longer pilots.
    @discardableResult
    func pilotTick(_ s: Ship, _ mi: MoveInput, _ dt: Float) -> Bool {
        let ships = world.ships
        guard ships.list.contains(where: { $0 === s }), let stand = helmStand(s), alive else { leaveHelm(); return false }
        let at = s.toWorld(stand)
        // Teleported, respawned or knocked away: no longer at the helm.
        if simd_length(at - player.pos) > 4 { leaveHelm(); return false }
        if mi.sneak { leaveHelm(); return false }
        let pad = readPad()
        s.piloted = true
        s.throttle = max(-1, min(1, mi.forward))
        s.steer = max(-1, min(1, mi.strafe))
        var climb: Float = 0
        if mi.jump || (pad?.rb ?? false) { climb += 1 }
        if input.control || (pad?.lb ?? false) { climb -= 1 }
        s.climb = climb
        // Turrets follow the view.
        for t in ships.turrets(of: s) {
            var rel = player.yaw - s.yaw
            while rel > .pi { rel -= 2 * .pi }
            while rel < -.pi { rel += 2 * .pi }
            t.aimAt = nil
            t.aimYaw = rel
        }
        player.pos = at
        player.vel = s.velocity(at: at)
        player.onGround = true
        player.airPeak = at.y
        player.flying = false
        return true
    }

    func startPiloting(_ s: Ship) {
        let ships = world.ships
        ships.pilot = s
        ships.aboard = s
        s.piloted = true
        s.captured = true
        if s.balloons > 0 && s.hoverY == nil { s.hoverY = s.pos.y }
        if let stand = helmStand(s) { player.pos = s.toWorld(stand) }
        player.flying = false
        sfx(.place(.wood), 0.5, at: player.pos)
        onToast?("Steering \(s.name): W/S throttle, A/D turn, Space/Ctrl climb, click fire, Shift leave")
    }

    func leaveHelm() {
        let ships = world.ships
        guard let s = ships.pilot else { return }
        ships.pilot = nil
        s.piloted = false
        s.throttle = 0; s.steer = 0; s.climb = 0
        ships.aboard = s
        player.vel = s.velocity(at: player.pos)
        player.airPeak = player.pos.y
    }

    // Breaking, placing and using blocks on ships, and assembling helms. Returns true when handled
    // (the rest of Game.interact is skipped).
    func shipInteract(breakHeld: Bool, breakNow: Bool, useNow: Bool, sneak: Bool, dt: Float) -> Bool {
        let ships = world.ships
        ships.breakCooldown -= dt
        if let s = ships.pilot {
            ships.target = nil; target = nil; mining = nil
            // Attack fires the cannons, raised to the view pitch.
            if breakNow && ships.fire(s, pitch: player.pitch + 0.05, game: self) > 0 { swing = 1 }
            return true
        }
        let eye = player.eye, look = player.look
        let reach: Float = survival ? 4.5 : 5
        var best: (Ship, IVec3, IVec3, Float)?
        for s in ships.list where eye.x > s.worldMin.x - reach && eye.x < s.worldMax.x + reach && eye.y > s.worldMin.y - reach
            && eye.y < s.worldMax.y + reach && eye.z > s.worldMin.z - reach && eye.z < s.worldMax.z + reach {
            if let h = s.raycast(eye, look, maxDist: reach, world: world), best == nil || h.t < best!.3 { best = (s, h.cell, h.normal, h.t) }
        }
        guard let hit = best else {
            ships.target = nil
            ships.mineCell = nil
            // Using a loose helm assembles the structure around it.
            if useNow && !sneak, let tg = target, ShipParts.kinds[Int(world.block(tg.hit.x, tg.hit.y, tg.hit.z))] == .helm {
                let (ship, msg) = ships.assemble(at: tg.hit, game: self)
                onToast?(msg)
                if let ship { sfx(.place(.wood), 1, at: ship.pos); target = nil }
                swing = 1
                return true
            }
            return false
        }
        let (s, cell, normal, t) = hit
        // Something nearer in the world, or a mob in front: not ours.
        if let tg = target, simd_length(hitPoint(tg) - eye) < t { ships.target = nil; return false }
        if let mh = mobs.raycast(eye, look, maxDist: 3.5), mh.1 < t { ships.target = nil; return false }
        ships.target = (s, cell, normal)
        target = nil
        mining = nil
        let b = s.grid.get(cell.x, cell.y, cell.z)
        let centre = s.toWorld(V3(Float(cell.x), Float(cell.y), Float(cell.z)) + 0.5)

        // Breaking.
        if breakHeld {
            var done = false
            if !survival {
                if breakNow || ships.breakCooldown <= 0 { done = true; ships.breakCooldown = 0.3 }
            } else {
                if ships.mineCell == nil || ships.mineCell!.0 !== s || ships.mineCell!.1 != cell { ships.mineCell = (s, cell); ships.mineProgress = 0 }
                let secs = Mining.breakSeconds(b, held, onGround: player.onGround || player.flying, inWater: player.headInWater)
                if secs.isFinite {
                    ships.mineProgress += secs <= 0 ? 1 : dt / secs
                    swing = max(swing, 0.5)
                    if ships.mineProgress >= 1 && ships.breakCooldown <= 0 { done = true; ships.breakCooldown = 0.25; ships.mineProgress = 0 }
                }
            }
            if done {
                if breakNow || !survival { swing = 1 }
                sfx(.breakBlock(soundMat(b)), at: centre)
                particles.blockBreak(b, at: IVec3(Int(floor(centre.x)), Int(floor(centre.y)), Int(floor(centre.z))))
                if let be = s.blockEntities[cell] { for st in be.container.slots where !st.isEmpty { drops.spawn(st, at: centre) } }
                if survival {
                    for st in Mining.enchantedDrops(b, held) { drops.spawn(st, at: centre) }
                    damageHeld(1)
                }
                if ships.pilot === s && s.helm == cell { leaveHelm() }
                ships.setBlock(s, cell, AIR)
                ships.mineCell = nil
            }
            return true
        }
        ships.mineCell = nil
        guard useNow else { return true }
        swing = 1

        // Using: a labelled name tag names the ship; the helm steers (sneak: docks the ship); containers open.
        if ShipParts.kinds[Int(b)] == .helm && s.helm == cell && Items.key(held.item) == "name_tag", let label = held.label, !label.isEmpty {
            s.name = label
            if survival { consumeHeld() }
            onToast?("Named the ship \(label)")
            return true
        }
        if ShipParts.kinds[Int(b)] == .helm && s.helm == cell {
            if sneak {
                let msg = ships.disassemble(s, game: self)
                onToast?(msg)
                sfx(.place(.wood), 1, at: centre)
            } else {
                startPiloting(s)
            }
            return true
        }
        if !sneak, let be = s.blockEntities[cell] ?? (Blocks.key(Blocks.groupBase[Int(b)]).hasSuffix("chest") ? newShipChest(s, cell) : nil) {
            openMenu(ChestMenu(game: self, container: be.container, title: Blocks.name(b)))
            return true
        }

        // Placing a block on the ship.
        guard let item = held.def.block else { return true }
        let at = cell + normal
        let here = s.grid.get(at.x, at.y, at.z)
        guard Blocks.replaceable[Int(here)] else { return true }
        var id = item
        let key = Blocks.key(item)
        let localYaw = player.yaw - s.yaw
        let facing = BlockRegistry.facingToward(yaw: localYaw)
        if Blocks.has(key + "[south]") && Blocks.shape[Int(item)].isEmpty { id = item + BlockID(facing) }
        else if Blocks.shape[Int(item)] == "stairs" { id = item + BlockID(facing ^ 1) }
        if Blocks.has(key + "[x]") && Blocks.shape[Int(item)].isEmpty {
            if normal.x != 0 { id = Blocks.id(key + "[x]") } else if normal.z != 0 { id = Blocks.id(key + "[z]") }
        }
        // Not inside the player.
        let lp = s.toLocal(player.pos)
        let ph = player.height
        if Float(at.x) < lp.x + 0.3 && Float(at.x + 1) > lp.x - 0.3 && Float(at.z) < lp.z + 0.3 && Float(at.z + 1) > lp.z - 0.3
            && Float(at.y) < lp.y + ph && Float(at.y + 1) > lp.y && Blocks.collide[Int(id)] { return true }
        ships.setBlock(s, at, id)
        if ShipParts.kinds[Int(id)] == .helm && s.helm == nil { s.rebuild() }
        sfx(.place(soundMat(id)), at: s.toWorld(V3(Float(at.x), Float(at.y), Float(at.z)) + 0.5))
        if survival { consumeHeld() }
        return true
    }

    private func newShipChest(_ s: Ship, _ c: IVec3) -> BlockEntity {
        let be = BlockEntity(.chest)
        s.blockEntities[c] = be
        return be
    }
}
