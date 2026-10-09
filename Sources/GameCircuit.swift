import Foundation
import simd

// Player interaction with sparkstone components and the world services the engine calls back into
// (dispensing, hoppers, pressure plate detection, piston-pushed entities, drops).
extension Game {
    // 6-way look direction: 0 down, 1 up, 2 north, 3 south, 4 west, 5 east.
    func lookDir6() -> Int {
        if player.pitch > 0.785 { return 1 }
        if player.pitch < -0.785 { return 0 }
        let f = BlockRegistry.facingToward(yaw: player.yaw)       // side facing the player
        return [3, 2, 5, 4][f]                                     // look = opposite of that side
    }

    // State for a sparkstone component placed with the player at `at`, clicked face normal `n`.
    // Returns nil when the component cannot be placed there.
    func redstonePlacement(_ item: BlockID, at: IVec3, normal n: IVec3, upperHalf: Bool) -> BlockID? {
        let facing = BlockRegistry.facingToward(yaw: player.yaw)  // side toward the player
        let away = facing ^ 1                                      // direction the player looks (horizontal)
        let below = world.block(at.x, at.y - 1, at.z)
        let solidBelow = Blocks.opaque[Int(below)]
        func normalDir6() -> Int { n.y == 1 ? 1 : (n.y == -1 ? 0 : (n.z == -1 ? 2 : (n.z == 1 ? 3 : (n.x == -1 ? 4 : 5)))) }
        switch Blocks.shape[Int(item)] {
        case "lever", "button":
            if n.y == 1 { return solidBelow ? item + BlockID(away) : nil }
            if n.y == -1 { return item + BlockID(away + 8) }
            let f = normalDir6() - 2                              // faces away from the wall it is on
            return item + BlockID(f + 4)
        case "plate": return solidBelow ? item : nil
        case "repeater", "comparator": return solidBelow ? item + BlockID(away) : nil
        case "observer": return item + BlockID(lookDir6())
        case "piston", "dispenser": return item + BlockID([1, 0, 3, 2, 5, 4][lookDir6()])
        case "hopper":
            // Outputs into the block it was placed against.
            if n.y != 0 { return item }
            return item + BlockID(n.z == 1 ? 1 : (n.z == -1 ? 2 : (n.x == 1 ? 3 : 4)))
        case "daylight": return item
        default: break
        }
        if Circuit.kind(item) == .torch {
            if n.y == 0 { return item + BlockID(2 + (normalDir6() - 2)) }
            return solidBelow ? item : nil
        }
        return item
    }

    // Right-click on a component. Returns true if it was handled.
    func useCircuit(_ p: IVec3) -> Bool {
        let b = world.block(p.x, p.y, p.z)
        let base = Blocks.groupBase[Int(b)]
        let s = Int(b - base)
        let rs = world.redstone
        let at = V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5
        switch Circuit.kind(b) {
        case .wire:
            guard rs.toggleDot(p) else { return false }
            sfx(.click, 0.3, at: at)
        case .lever:
            let ns = s >= 12 ? s - 12 : s + 12
            world.setBlock(p.x, p.y, p.z, base + BlockID(ns))
            rs.switchChanged(p, ns)
            sfx(.lever, 0.6, at: at)
        case .button:
            guard s < 12 else { return true }
            world.setBlock(p.x, p.y, p.z, base + BlockID(s + 12))
            rs.switchChanged(p, s + 12)
            let stone = Blocks.key(base).hasPrefix("stone") || Blocks.key(base).hasPrefix("polished")
            rs.schedule(p, stone ? 20 : 30)
            sfx(stone ? .buttonStone : .buttonWood, 0.6, at: at)
        case .repeater:
            let delay = ((s >> 2) & 3 + 1) & 3
            world.setBlock(p.x, p.y, p.z, base + BlockID((s & ~12) | (delay << 2)))
            sfx(.click, 0.4, at: at)
        case .comparator:
            world.setBlock(p.x, p.y, p.z, base + BlockID(s ^ 4))
            sfx(.click, 0.4, at: at)
        case .note:
            world.setBlock(p.x, p.y, p.z, base + BlockID((s + 1) % 25))
            world.redstone.playNote(p, (s + 1) % 25)          // the instrument of the block below (it always played the harp)
        case .daylight:
            world.setBlock(p.x, p.y, p.z, base + BlockID((s & 15) + (s >= 16 ? 0 : 16)))
        case .dispenser, .dropper:
            let be = world.entity(p, .dispenser)
            world.blockEntities[p] = be
            openMenu(DispenserMenu(game: self, entity: be, title: Circuit.kind(b) == .dropper ? "Dropper" : "Dispenser"))
        case .hopper:
            let be = world.entity(p, .hopper)
            world.blockEntities[p] = be
            openMenu(HopperMenu(game: self, entity: be))
        default: return false
        }
        return true
    }

    func isCircuitInteractive(_ p: IVec3) -> Bool {
        switch Circuit.kind(world.block(p.x, p.y, p.z)) {
        case .wire: return world.redstone.wireConnections(p).isEmpty
        case .lever, .button, .repeater, .comparator, .note, .daylight, .dispenser, .dropper, .hopper: return true
        default: return false
        }
    }

    // MARK: Engine services

    func breakDrops(_ q: IVec3, _ b: BlockID) {
        let c = V3(Float(q.x) + 0.5, Float(q.y) + 0.3, Float(q.z) + 0.5)
        for s in Mining.drops(b, .empty) { drops.spawn(s, at: c) }
        if Circuit.kind(b) == .wire { drops.spawn(ItemStack(Items.id("redstone"), 1), at: c) }
    }

    // Players and mobs inside blocks that a piston just moved ride along.
    func entitiesPushed(_ cells: [IVec3], dir: IVec3) {
        let d = V3(Float(dir.x), Float(dir.y), Float(dir.z))
        let set = Set(cells)
        func inside(_ pos: V3, _ hw: Float, _ h: Float) -> Bool {
            for y in Int(floor(pos.y))...Int(floor(pos.y + h - 0.01)) {
                for z in Int(floor(pos.z - hw))...Int(floor(pos.z + hw)) { for x in Int(floor(pos.x - hw))...Int(floor(pos.x + hw)) where set.contains(IVec3(x, y, z)) { return true } }
            }
            // Standing on top of a moved block.
            return set.contains(IVec3(Int(floor(pos.x)), Int(floor(pos.y - 0.05)), Int(floor(pos.z))))
        }
        // Every player (split screen: a piston didn't carry player 2).
        coop.eachSeat(self) {
            let pl = self.player
            if inside(pl.pos, pl.halfW, pl.height) { pl.pos += d; pl.airPeak = pl.pos.y }
        }
        for m in mobs.mobs where inside(m.pos, m.halfW, m.height) { m.pos += d }
    }

    // How many entities press a plate (players and mobs; items too for wooden/weighted plates).
    func entitiesOn(_ p: IVec3, items: Bool) -> Int {
        func on(_ pos: V3, _ hw: Float) -> Bool {
            pos.y >= Float(p.y) - 0.01 && pos.y < Float(p.y) + 0.3 &&
            pos.x + hw > Float(p.x) + 0.06 && pos.x - hw < Float(p.x) + 0.94 && pos.z + hw > Float(p.z) + 0.06 && pos.z - hw < Float(p.z) + 0.94
        }
        var n = 0
        coop.eachSeat(self) { if self.alive && on(self.player.pos, self.player.halfW) { n += 1 } }   // player 2 presses plates too
        for m in mobs.mobs where on(m.pos, m.halfW) { n += 1 }
        if items {
            for e in drops.items where on(e.pos, 0.125) { n += 1 }      // each item entity counts once, whatever its stack
            for a in projectiles.arrows where a.stuck && !a.dead && on(a.pos, 0.05) { n += 1 }      // arrows too (reference)
        }
        return n
    }

    // An arrow stuck in the cell `p` (wooden buttons stay pressed while one is).
    func arrowStuck(in p: IVec3) -> Bool {
        projectiles.arrows.contains { $0.stuck && !$0.dead && Int(floor($0.pos.x)) == p.x && Int(floor($0.pos.y)) == p.y && Int(floor($0.pos.z)) == p.z }
    }

    // Dispenser / dropper firing out of side `dir` (dir6).
    func dispense(at p: IVec3, dir: Int, dropper: Bool) {
        guard let be = world.blockEntities[p] else { sfx(.click, 0.4); return }
        let c = be.container
        let filled = (0..<c.count).filter { !c[$0].isEmpty }
        guard let slot = filled.pick() else { sfx(.click, 0.4, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5); return }
        let dv = BlockRegistry.dir6[dir]
        let front = p + dv
        let fd = V3(Float(dv.x), Float(dv.y), Float(dv.z))
        let from = V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5 + fd * 0.7
        var stack = c[slot]
        let key = Items.key(stack.item)
        func take() { stack.count -= 1; c[slot] = stack.count > 0 ? stack : .empty }
        if dropper {
            // Into a container in front, else out as an item.
            if let t = world.blockEntities[front], t.kind == .furnace {
                // By face like a hopper (reference): from above into the input, from the side fuel only; else it holds.
                let one = stack.with(count: 1)
                let slot = fd.y < -0.5 ? 0 : (fd.y > 0.5 ? -1 : (Recipes.fuel(one.item) > 0 ? 1 : -1))
                if slot >= 0 {
                    let cur = t.container[slot]
                    if cur.isEmpty || (cur.stacks(with: one) && cur.count < cur.maxStack) {
                        var n = cur.isEmpty ? one : cur
                        if !cur.isEmpty { n.count += 1 }
                        t.container[slot] = n
                        take()
                    }
                }
            } else if let t = world.blockEntities[front], t.kind != .spawner {
                let one = stack.with(count: 1)
                if t.container.add(one).isEmpty { take() }
            } else { drops.spawn(stack.with(count: 1), at: from, vel: fd * 4 + V3(0, 1, 0), delay: 0.5); take() }
            sfx(.click, 0.5, at: from)
            return
        }
        let fb = world.block(front.x, front.y, front.z)
        let aim = simd_normalize(fd + V3(0, 0.1, 0))
        // Splash/lingering potions and bottles o' enchanting are thrown (reference).
        if key == "experience_bottle" || (Potions.potion(of: stack.item).map { $0.form == 1 || $0.form == 2 } ?? false) {
            projectiles.fireball(from: from, dir: aim, big: false, byPlayer: false, potion: stack.item)
            if let f = projectiles.fireballs.last { f.vel = aim * (key == "experience_bottle" ? 14 : 10) }
            take(); sfx(.potionThrow, 0.6, at: from)
            return
        }
        // Spawn eggs hatch in front.
        if let kind = SpawnEggs.kindOf[stack.item] {
            let m = Mob(kind, at: V3(Float(front.x) + 0.5, Float(front.y), Float(front.z) + 0.5))
            m.persistent = kind.category != .creature
            if kind == .slime || kind == .magmaCube { m.makeSlime(size: 1) }
            mobs.mobs.append(m); take(); sfx(.click, 0.5, at: from)
            return
        }
        switch key {
        case "snowball", "egg", "brown_egg", "blue_egg":
            let f = Fireball(from, aim * 22, big: false, byPlayer: false)
            f.kind = key == "snowball" ? .snowball : .egg
            if f.kind == .egg { f.egg = stack.item }
            projectiles.fireballs.append(f); take(); sfx(.bow, 0.4, at: from)
        case "shears":
            // Shears the first unsheared sheep in front (reference); otherwise nothing happens.
            let box = V3(Float(front.x) + 0.5, Float(front.y), Float(front.z) + 0.5)
            if let m = mobs.mobs.first(where: { $0.kind == .sheep && !$0.sheared && !$0.baby && abs($0.pos.x - box.x) < 1 && abs($0.pos.z - box.z) < 1 && abs($0.pos.y - box.y) < 1.5 }) {
                m.sheared = true
                let wool = "\(m.woolColor)_wool"
                if Items.has(wool) { drops.spawn(ItemStack(Items.id(wool), Rand.int(in: 1...3)), at: m.pos + V3(0, 1, 0)) }
                stack.damage += 1; c[slot] = stack.damage >= stack.def.durability ? .empty : stack
                sfx(.shearsSnip, 1, at: m.pos)
            }
        case "glass_bottle" where Blocks.fluidKind[Int(fb)] == 1:
            // Fills from water in front; the water bottle goes back into the dispenser (or out if it is full).
            if let wb = Potions.item(0, "water") {
                take()
                let rest = c.add(ItemStack(wb, 1))
                if !rest.isEmpty { drops.spawn(rest, at: from, vel: fd * 4 + V3(0, 1, 0), delay: 0.5) }
            }
        case _ where Boats.parse(key) != nil:
            // Boats go onto water in front (or water just below it), else out as an item.
            let below = world.block(front.x, front.y - 1, front.z)
            let y: Float? = Blocks.fluidKind[Int(fb)] == 1 ? Float(front.y) + 0.6 : (fb == AIR && Blocks.fluidKind[Int(below)] == 1 ? Float(front.y) - 0.4 : nil)
            if let y = y, case let (variant, chest)? = Boats.parse(key) {
                let boat = Mob(.boat, at: V3(Float(front.x) + 0.5, y, Float(front.z) + 0.5))
                boat.variant = variant; boat.chested = chest
                if chest { boat.cargo = ItemContainer(27) }
                boat.yaw = [0, Float.pi, 0, Float.pi, Float.pi / 2, -Float.pi / 2][dir]
                mobs.mobs.append(boat); take()
            } else { drops.spawn(stack.with(count: 1), at: from, vel: fd * 4 + V3(0, 1, 0), delay: 0.5); take() }
        case _ where key.hasSuffix("shulker_box") && Blocks.has(key):
            // Placed in front with its contents (reference).
            if Blocks.replaceable[Int(fb)] {
                world.setBlock(front.x, front.y, front.z, Blocks.id(key))
                let be = BlockEntity(.shulker)
                if let items = stack.contents { for (i, s) in items.prefix(27).enumerated() { be.container[i] = s } }
                world.blockEntities[front] = be
                take()
            }
        case "minecart" where Rails.isRail(fb):
            mobs.mobs.append(Mob(.minecart, at: V3(Float(front.x) + 0.5, Float(front.y) + 0.0625, Float(front.z) + 0.5))); take()
        case "arrow": projectiles.shoot(from: from, dir: simd_normalize(fd + V3(0, 0.1, 0)), speed: 22, fromPlayer: true, damage: 2); take(); sfx(.bow, 0.6, at: from)
        case "fire_charge": projectiles.fireball(from: from, dir: fd, big: false, byPlayer: true); take(); sfx(.fireball, 0.5, at: from)
        case "water_bucket", "lava_bucket":
            if Blocks.replaceable[Int(fb)] { world.setBlock(front.x, front.y, front.z, key == "water_bucket" ? WATER : LAVA); c[slot] = ItemStack(Items.id("bucket"), 1) }
        case "bucket":
            if fb == WATER || fb == LAVA { world.setBlock(front.x, front.y, front.z, AIR); c[slot] = ItemStack(Items.id(fb == WATER ? "water_bucket" : "lava_bucket"), 1) }
        case "flint_and_steel":
            if fb == AIR { world.placeFire(front) } else if Blocks.key(fb) == "tnt" { world.setBlock(front.x, front.y, front.z, AIR); tnts.prime(at: front) }
            stack.damage += 1; c[slot] = stack.damage >= stack.def.durability ? .empty : stack
        case "tnt":
            if Blocks.replaceable[Int(fb)] { tnts.prime(at: front); take() }
        case "bone_meal":
            if boneMealGrow(front) { take() }
        default:
            if stack.def.armorSlot != nil, simd_length(player.pos + V3(0, 0.9, 0) - (V3(Float(front.x), Float(front.y), Float(front.z)) + 0.5)) < 1.5,
               let sl = stack.def.armorSlot, inventory.armor[sl.rawValue].isEmpty {
                inventory.armor[sl.rawValue] = stack.with(count: 1); take()
            } else {
                drops.spawn(stack.with(count: 1), at: from, vel: fd * 4 + V3(0, 1, 0), delay: 0.5); take()
            }
        }
        sfx(.click, 0.5, at: from)
    }

    static let hopperOut: [IVec3] = [IVec3(0, -1, 0), IVec3(0, 0, -1), IVec3(0, 0, 1), IVec3(-1, 0, 0), IVec3(1, 0, 0)]

    // One hopper step: push one item out, then pull one in from above (container or dropped items).
    func hopperTransfer(_ p: IVec3, out: Int) -> Bool {
        let be = world.blockEntities[p] ?? { let e = BlockEntity(.hopper); world.blockEntities[p] = e; return e }()
        let c = be.container
        var moved = false
        let target = p + Game.hopperOut[out]
        // Not into campfires or item frames (a campfire turned whatever arrived into its smelt result or nothing).
        if let t = world.blockEntities[target], t.kind != .spawner, t.kind != .campfire, t.kind != .frame {
            for i in 0..<c.count where !c[i].isEmpty {
                let one = c[i].with(count: 1)
                let ok: Bool
                if t.kind == .furnace {
                    let slot = out == 0 ? 0 : 1                                  // from above: input; from the side: fuel
                    if slot == 1 && Recipes.fuel(one.item) == 0 { continue }
                    let cur = t.container[slot]
                    ok = cur.isEmpty || (cur.stacks(with: one) && cur.count < cur.maxStack)
                    if ok { var n = cur.isEmpty ? one : cur; if !cur.isEmpty { n.count += 1 }; t.container[slot] = n }
                } else if t.kind == .brewing {
                    // Brewing stand faces (reference): from above the ingredient slot only; from the side blaze powder
                    // into the fuel slot and potions into empty bottle slots (everything went into slot 0 first).
                    var slot = -1
                    if out == 0 { slot = Potions.isIngredient(one.item) ? 3 : -1 }
                    else if Items.key(one.item) == "blaze_powder" { slot = 4 }
                    else if Potions.potion(of: one.item) != nil { slot = (0..<3).first { t.container[$0].isEmpty } ?? -1 }
                    if slot < 0 || slot >= t.container.count { continue }
                    let cur = t.container[slot]
                    ok = cur.isEmpty || (slot >= 3 && cur.stacks(with: one) && cur.count < cur.maxStack)
                    if ok { var n = cur.isEmpty ? one : cur; if !cur.isEmpty { n.count += 1 }; t.container[slot] = n }
                } else { ok = t.container.add(one).isEmpty }
                if ok { var s = c[i]; s.count -= 1; c[i] = s.count > 0 ? s : .empty; moved = true; break }
            }
        }
        // Pull from above.
        let above = p + IVec3(0, 1, 0)
        if let src = world.blockEntities[above], src.kind != .spawner {
            // Furnaces give their output, brewing stands their bottles (not the ingredient or the powder).
            let range: Range<Int> = src.kind == .furnace ? 2..<3 : (src.kind == .brewing ? 0..<min(3, src.container.count) : 0..<src.container.count)
            for i in range where !src.container[i].isEmpty {
                let one = src.container[i].with(count: 1)
                if c.add(one).isEmpty {
                    var s = src.container[i]; s.count -= 1; src.container[i] = s.count > 0 ? s : .empty
                    moved = true; break
                }
            }
        } else if !Blocks.opaque[Int(world.block(above.x, above.y, above.z))] {
            for e in drops.items where !e.stack.isEmpty && Int(floor(e.pos.x)) == p.x && Int(floor(e.pos.z)) == p.z && e.pos.y >= Float(p.y) + 0.6 && e.pos.y < Float(p.y) + 2 {
                let rest = c.add(e.stack)
                if rest.count != e.stack.count { e.stack = rest; moved = true; break }
            }
        }
        if moved { world.redstone.wakeAround(p); world.redstone.wakeAround(target) }
        return moved
    }
}
