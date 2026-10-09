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
            ships.riderShip = nil
            player.update(dt: dt, input: mi, world: world)
            return
        }
        if let s = ships.pilot {
            if pilotTick(s, mi, dt) { ships.riderShip = nil; return }
        }
        commandeerHintTick()
        let p = player
        var cand = ships.frameShip(for: p.pos, height: p.height, current: ships.aboard)
        // Boarding takes a hold on the ship (its deck under the feet, its ladder, its cabin air): beside or under a
        // moving hull you stay in the world.
        if let s = cand, s !== ships.aboard, !ships.canBoard(s, p.pos, halfW: p.halfW) { cand = nil }
        guard let s = cand else {
            ships.aboard = nil
            ships.riderShip = nil
            player.update(dt: dt, input: mi, world: world)
            return
        }
        // Into ship space: position, velocity relative to the deck, heading. A rider who rode this ship last tick keeps
        // its deck-relative velocity (plus any outside push since); one who just boarded takes its world velocity
        // minus the deck's.
        let w0 = p.pos
        let fall = p.airPeak - w0.y
        let yawOff = s.yaw
        let lv: V3
        // (Only from the tick before: a tick spent at a turret or the helm starts afresh.)
        if ships.riderShip === s && ships.riderAt == ships.riderStamp - 1 { lv = ships.riderVel + s.dirToLocal(p.vel - ships.riderOut) }
        else { lv = s.dirToLocal(p.vel - s.velocity(at: w0)) }
        p.vel = lv
        p.pos = s.toLocal(w0)
        p.lastUpdatePos = s.toLocal(p.lastUpdatePos)
        p.yaw -= yawOff
        p.airPeak = p.pos.y + fall
        world.frame = s
        p.update(dt: dt, input: mi, world: world)
        world.frame = nil
        let held = ships.holdsRider(s, p.pos, halfW: p.halfW) || ships.atShipLadder(s, p.pos, halfW: p.halfW)
        // Back to world space.
        ships.riderShip = s
        ships.riderAt = ships.riderStamp
        ships.riderVel = p.vel
        let fall2 = p.airPeak - p.pos.y
        let w1 = s.toWorld(p.pos)
        p.pos = w1
        p.lastUpdatePos = s.toWorld(p.lastUpdatePos)
        p.vel = s.dirToWorld(p.vel) + s.velocity(at: w1)
        ships.riderOut = p.vel
        p.yaw += yawOff
        p.airPeak = w1.y + fall2
        ships.aboard = s
        // Standing on the world's ground (off the foot of a ramp or a ladder): off the deck, once the body is clear
        // of the hull's world-space boxes (leaving inside one would pop the player up onto it).
        // The ground under a turned hull is sampled per ship cell in its frame, so the world's own ground there can stand
        // up to a block higher: the rider steps up onto it as it leaves.
        if p.onGround && !held {
            let hw = p.halfW - 0.02
            for up in [Float(0), 0.5, 1.0, 1.25] {
                let y = w1.y + up
                if world.collides(V3(w1.x - hw, y + 0.02, w1.z - hw), V3(w1.x + hw, y + p.height - 0.02, w1.z + hw)) { continue }
                p.pos.y = y
                p.airPeak += up
                ships.aboard = nil
                ships.riderShip = nil
                break
            }
        }
    }

    // /vessel frigate|carriage: summon one ahead; /vessel locate: the nearest encounter home.
    func vesselCommand(_ a: [String]) -> [String] {
        let ships = world.ships
        guard a.count >= 2 else { return ["Usage: /vessel <frigate|carriage|locate>"] }
        let f = V3(-sinf(player.yaw), 0, -cosf(player.yaw))
        switch a[1].lowercased() {
        case "frigate":
            // The Capital frigate (CapitalFrigate.swift), built here and now ahead of the player.
            let at = player.pos + f * 160
            ships.spawnCapital("capfrigate", home: IVec3(Int(floor(at.x)), 0, Int(floor(at.z))), yaw: player.yaw, region: nil, sync: true)
            return ["Summoned the Meridian Frigate"]
        case "skyward", "carriage":
            let at = player.pos + f * (a[1].lowercased() == "skyward" ? 50 : 30)
            let x = Int(floor(at.x)), z = Int(floor(at.z))
            let ground = world.topY(x, z)
            let sky = a[1].lowercased() == "skyward"
            let s = ships.spawnVessel(sky ? "frigate" : "carriage", home: IVec3(x, sky ? max(ground, SEA) + 30 : ground + 1, z), game: self)
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
            let name = b.0 == "frigate" ? "Meridian Frigate" : "Ironstride Siege Carriage"
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
        if let m = world.ships.macCharge(s) { t += m > 0 ? String(format: "  MAC %.0f s", m.rounded(.up)) : "  MAC ready" }
        return t
    }

    // Boss-style bars for crewed vessels near the player: name and how much of the hull is left.
    func shipBars() -> [(String, Float)] {
        var out: [(String, Float)] = []
        for s in world.ships.list where s.isVessel && s.parent == nil && !s.captured && !s.wrecked && s.initialBlocks > 0 {
            if s.kinematic {
                // Capital ships: the drive engines and the helm decide (ShipManager.capitalIntegrity).
                // Capital vehicles: a machine, not a health pool: the label lists its components and crew.
                if world.ships.boundsDistance(s, player.pos) < 300 { out.append((world.ships.capitalStatus(s), world.ships.capitalIntegrity(s))) }
            } else if simd_length(s.pos - player.pos) < 96 {
                out.append((s.name, Float(s.blockCount) / Float(s.initialBlocks)))
            }
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
        s.piloted = true
        // Per-vehicle keyboard / controller layout (VehicleControls.swift).
        let c = VehicleControls.read(self, s, mi)
        if s.wheels.isEmpty {
            // Ships and aircraft keep their throttle (an engine telegraph): W/S, the stick or the triggers move it,
            // letting go holds it, and passing through stop pauses there for a moment so stopping is easy.
            let f = c.throttle
            if s.telegraphPause > 0 {
                s.telegraphPause -= dt
                if abs(f) < 0.1 { s.telegraphPause = 0 }
            } else if abs(f) > 0.1 {
                let old = s.throttle
                let t = max(-1, min(1, old + f * 0.8 * dt))
                if old != 0 && (t > 0) != (old > 0) {
                    s.throttle = 0; s.telegraphPause = 0.6
                } else {
                    s.throttle = t
                }
            }
        } else {
            s.throttle = c.throttle
        }
        s.steer = c.steer
        s.climb = c.climb
        if let fm = s.flight { fm.playerInput(self, s, mi, dt) }          // helicopter controls (FlightModel.swift)
        // Turrets follow the view; barrels rise with it.
        let elev = max(-0.2, min(0.6, player.pitch + 0.05))
        s.gunPitch = elev
        for t in ships.turrets(of: s) {
            t.gunPitch = elev
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

    // MARK: Commandeering (Quest round 4: dropships and frigates couldn't be taken, and a helm had to be hit exactly)
    // A vessel whose helm the player may take from where they stand: within 6 blocks of the helm (a dropship: 9, it
    // hovers while unloading), or anywhere aboard a Capital flier. The use button takes it (Game.interact), with a toast
    // on entering the zone and a label on the Quest.
    func commandeerable() -> Ship? {
        let ships = world.ships
        guard ships.pilot == nil, alive, menu == nil else { return nil }
        let p = player.pos
        var best: Ship?
        var bd = Float.greatestFiniteMagnitude
        for s in ships.list where s.parent == nil && !s.wrecked && s.helm != nil {
            // Crewed vessels and Capital fliers only: near the player's own builds use keeps placing blocks.
            if s.kinematic ? !ships.canCommandeer(s) : !s.isVessel { continue }
            guard let stand = helmStand(s) else { continue }
            let d = simd_length(s.toWorld(stand) - p)
            let zone: Float = s.role == "dropship" ? 9 : 6
            let aboard = s.kinematic && (ships.aboard?.root === s || ships.boundsDistance(s, p) < (s.role == "dropship" ? 3 : 0.5))
            if (d < zone || aboard) && d < bd { best = s; bd = d }
        }
        return best
    }

    func takeCommand(_ s: Ship) {
        let first = s.kinematic && !s.captured
        world.ships.aboard = s
        startPiloting(s)
        player.vel = s.velocity(at: player.pos)
        if first { onToast?("You have taken command of the \(s.name)! \(Prompt.g(.sneak)) leaves the helm") }
    }

    // The zone prompt: a toast each time the player comes within reach of a helm they can take.
    func commandeerHintTick() {
        let s = commandeerable()
        if let s, s !== commandeerHint { onToast?("\(Prompt.g(.use)) Take command of the \(s.name)") }
        commandeerHint = s
    }

    func startPiloting(_ s: Ship) {
        let ships = world.ships
        ships.pilot = s
        ships.aboard = s
        s.piloted = true
        achieve("pilot_ship")
        if s.isVessel && !s.captured { achieve("capture_vessel") }
        s.captured = true
        s.wrecked = false                // a new crew (the player) takes over
        if s.balloons > 0 && s.hoverY == nil { s.hoverY = s.pos.y }
        if let stand = helmStand(s) { player.pos = s.toWorld(stand) }
        player.flying = false
        sfx(.helmTake, 0.8, at: player.pos)
        // Controls show as prompts (VehicleControls.prompts); ships and aircraft hold their throttle.
        onToast?("Steering \(s.name) (\(VehicleControls.name(VehicleControls.kind(s)))\(s.wheels.isEmpty ? ", throttle holds" : ""))")
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
            // Attack fires the MAC when a Meridian frigate's is charged, else the cannons, raised to the view pitch.
            if breakNow && ships.playerMAC(s, pitch: player.pitch, game: self) { swing = 1; return true }
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
                if let ship { sfx(.hullCreak, 1, at: ship.pos); sfx(.helmTake, 0.8, at: ship.pos); target = nil }
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
                if ships.mineCell == nil || ships.mineCell!.0 !== s || ships.mineCell!.1 != cell {
                    ships.mineCell = (s, cell)
                    ships.mineProgress = Float(Int(s.damage[cell] ?? 0) & 31) / 8      // a chipped plate picks up where it was left
                }
                let secs = Mining.breakSeconds(b, held, onGround: player.onGround || player.flying, inWater: player.headInWater, mul: miningSpeedMul)
                if secs.isFinite {
                    let before = Int(ships.mineProgress * 8)
                    ships.mineProgress += secs <= 0 ? 1 : dt / secs
                    swing = max(swing, 0.5)
                    // Capital hulls chip like the world's blocks: an eighth of the struck face at a time.
                    let level = Int(ships.mineProgress * 8)
                    if s.kinematic && Settings.shared.chipping && level > before && level >= 1 && level < 8
                        && Blocks.render[Int(b)] == RenderType.cube.rawValue {
                        let n = normal
                        let face = n.x > 0 ? 0 : (n.x < 0 ? 1 : (n.y > 0 ? 2 : (n.y < 0 ? 3 : (n.z > 0 ? 4 : 5))))
                        let f = s.damage[cell].map { Int($0 >> 5) } ?? face
                        s.damage[cell] = UInt8(f << 5 | level)
                        s.mesh.rebuildAround(s, cell, device: world.device, queue: ships.meshQueue)
                        swing = 1
                        let nw = s.rot.act(V3(Float(n.x), Float(n.y), Float(n.z)))
                        particles.chipBits(b, at: centre + nw * 0.45, normal: nw, face: face, count: 6)
                        sfx(.hit(soundMat(b)), 0.7, at: centre)
                    }
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
            // Capital fliers can be commandeered; other Capital ships can't be steered or taken apart: break the helm to
            // cripple one (CapitalShips.swift).
            if s.root.kinematic && ships.canCommandeer(s) && !sneak { takeCommand(s); return true }
            if s.root.kinematic {
                onToast?("The \(s.root.name)'s helm is locked. Destroy it to cripple the ship.")
                return true
            }
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
