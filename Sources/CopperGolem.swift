import Foundation
import simd

// Copper Golem: built from a carved pumpkin (or jack o'lantern) placed on a block of copper. It sorts storage:
// it takes up to 16 items at a time out of a copper chest within 16 blocks and carries them to an ordinary
// chest (or trapped chest) that already holds that item, or else to an empty one, trying up to 10 chests per
// trip before carrying the load back. It oxidizes like copper (slower as it ages); an oxidized golem
// eventually stops for good and becomes a Copper Golem Statue. Honeycomb waxes a golem (no ageing), an axe
// scrapes off the wax or one stage of oxidation, and an axe on an unwaxed statue scrapes it back to life.
// The mob's `variant` holds its stage (0...3) plus 4 when waxed; the load rides in `cargo` (saved with it).
enum CopperGolem {
    static let range = 16, rangeY = 6, cargoMax = 16, maxVisits = 10

    static func stage(_ m: Mob) -> Int { m.variant & 3 }
    static func waxed(_ m: Mob) -> Bool { m.variant >= 4 }
    static func color(_ stage: Int) -> V3 {
        let h = Copper.stages[min(3, max(0, stage))].hex
        return V3(Float((h >> 16) & 255), Float((h >> 8) & 255), Float(h & 255)) / 255
    }
    static func isCopperChest(_ key: String) -> Bool { key.hasSuffix("copper_chest") }
    static func isPlainChest(_ key: String) -> Bool { key == "chest" || key == "trapped_chest" }
}

extension Game {
    // Carved pumpkin placed on a copper block (any stage, waxed or not): a Copper Golem of that stage.
    func trySummonCopperGolem(_ p: IVec3) -> Bool {
        let below = world.block(p.x, p.y - 1, p.z)
        guard case let (form, stage, waxed)? = Copper.index[Blocks.key(Blocks.groupBase[Int(below)])], form == "block" else { return false }
        world.setBlock(p.x, p.y, p.z, AIR)
        world.setBlock(p.x, p.y - 1, p.z, AIR)
        let g = Mob(.copperGolem, at: V3(Float(p.x) + 0.5, Float(p.y - 1), Float(p.z) + 0.5))
        g.variant = stage + (waxed ? 4 : 0)
        g.persistent = true
        g.cargo = ItemContainer(1)
        mobs.mobs.append(g)
        particles.explosion(at: g.pos + V3(0, 0.7, 0), power: 0.2)
        sfx(.place(.metal), 0.8, at: g.pos)
        return true
    }

    // Honeycomb / axe on a golem. Returns true when it changed the golem.
    func copperGolemUse(_ m: Mob) -> Bool {
        guard m.kind == .copperGolem else { return false }
        let key = Items.key(held.item)
        let st = CopperGolem.stage(m), waxed = CopperGolem.waxed(m)
        if key == "honeycomb" && !waxed {
            m.variant = st + 4
            consumeHeld()
            sfx(.waxOn, 0.8, at: m.pos)
            return true
        }
        guard key.hasSuffix("_axe") else { return false }
        if waxed { m.variant = st; sfx(.waxOff, 0.8, at: m.pos) }
        else if st > 0 { m.variant = st - 1; sfx(.scrape, 0.8, at: m.pos) }
        else { return false }
        damageHeld(1)
        return true
    }

    // An axe on an unwaxed statue scrapes it back into a golem one stage cleaner.
    func reviveCopperStatue(_ p: IVec3) -> Bool {
        let b = world.block(p.x, p.y, p.z)
        guard case let (form, stage, waxed)? = Copper.index[Blocks.key(Blocks.groupBase[Int(b)])], form == "copper_golem_statue", !waxed else { return false }
        world.setBlock(p.x, p.y, p.z, AIR)
        let g = Mob(.copperGolem, at: V3(Float(p.x) + 0.5, Float(p.y), Float(p.z) + 0.5))
        g.variant = max(0, stage - 1)
        g.persistent = true
        g.cargo = ItemContainer(1)
        g.yaw = player.yaw + .pi
        mobs.mobs.append(g)
        sfx(.scrape, 0.9, at: g.pos)
        damageHeld(1)
        swing = 1
        return true
    }

    // An oxidized golem stops for good: it becomes a statue where it stands (its load drops).
    func petrifyCopperGolem(_ m: Mob) {
        let x = Int(floor(m.pos.x)), y = Int(floor(m.pos.y + 0.1)), z = Int(floor(m.pos.z))
        guard world.block(x, y, z) == AIR else { return }
        let n = Copper.name("copper_golem_statue", stage: 3, waxed: false)
        guard Blocks.has(n) else { return }
        if let c = m.cargo { for s in c.slots where !s.isEmpty { drops.spawn(s, at: m.pos + V3(0, 0.5, 0)) }; c.slots[0] = .empty }
        world.setBlock(x, y, z, Blocks.id(n))
        m.health = -1001                                   // removed without death drops
    }
}

extension Mob {
    func copperGolemAI(_ dt: Float, _ g: Game) -> Float {
        let w = g.world
        if cargo == nil { cargo = ItemContainer(1) }
        let st = CopperGolem.stage(self), waxed = CopperGolem.waxed(self)
        // Ageing: about one stage per half hour of loaded time; an oxidized golem may turn to a statue.
        if !waxed {
            if st < 3 {
                if Rand.float(in: 0..<1) < dt / 1800 { variant = st + 1 }
            } else if Rand.float(in: 0..<1) < dt / 1200 {
                g.petrifyCopperGolem(self)
                return 0
            }
        }
        let slow: [Float] = [1, 0.85, 0.7, 0.55]
        let speed: Float = spec.speed * slow[st]
        let load = cargo!.slots[0]
        golemTimer -= dt
        // Walk to the current goal chest; act on it when close.
        if let goal = golemGoal {
            let key = Blocks.key(Blocks.groupBase[Int(w.block(goal.x, goal.y, goal.z))])
            guard let be = w.blockEntities[goal], CopperGolem.isCopperChest(key) || CopperGolem.isPlainChest(key) else {
                golemGoal = nil
                return 0
            }
            let c = V3(Float(goal.x) + 0.5, Float(goal.y), Float(goal.z) + 0.5)
            let flat = simd_length(V2(c.x - pos.x, c.z - pos.z))
            if flat < 1.7 && abs(c.y - pos.y) < 2.5 {
                face(c)
                golemGoal = nil
                golemTimer = 0.8                                      // a beat at the chest
                if load.isEmpty {
                    // Take from the copper chest: up to 16 of the first stack.
                    if let i = be.container.slots.firstIndex(where: { !$0.isEmpty }) {
                        let s = be.container.slots[i]
                        let n = min(CopperGolem.cargoMax, s.count)
                        cargo!.slots[0] = s.with(count: n)
                        be.container[i] = s.count > n ? s.with(count: s.count - n) : .empty
                        golemVisited.removeAll(keepingCapacity: true)
                        g.sfx(.chestOpen, 0.5, at: c)
                    }
                } else {
                    let rest = be.container.add(load)
                    cargo!.slots[0] = rest
                    g.sfx(.chestClose, 0.5, at: c)
                    if rest.isEmpty { golemVisited.removeAll(keepingCapacity: true) } else { golemVisited.append(goal) }
                    if CopperGolem.isCopperChest(key) { golemTimer = 10 }        // carried it back: nowhere to put it, rest a while
                }
                return 0
            }
            if golemTimer < -12 { golemVisited.append(goal); golemGoal = nil; return 0 }   // can't reach it
            face(c)
            return speed
        }
        if golemTimer > 0 { return 0 }
        golemTimer = 0
        // Choose the next chest.
        let px = Int(floor(pos.x)), py = Int(floor(pos.y)), pz = Int(floor(pos.z))
        var best: IVec3?, bestScore = Float.greatestFiniteMagnitude
        for (p, be) in w.blockEntities where be.kind == .chest && abs(p.x - px) <= CopperGolem.range && abs(p.z - pz) <= CopperGolem.range
            && abs(p.y - py) <= CopperGolem.rangeY {
            let key = Blocks.key(Blocks.groupBase[Int(w.block(p.x, p.y, p.z))])
            let dx = p.x - px, dy = p.y - py, dz = p.z - pz
            var score = Float(dx * dx + dy * dy + dz * dz)
            if load.isEmpty {
                guard CopperGolem.isCopperChest(key), be.container.slots.contains(where: { !$0.isEmpty }) else { continue }
            } else if golemVisited.count >= CopperGolem.maxVisits {
                guard CopperGolem.isCopperChest(key) else { continue }             // give up: carry it back
            } else {
                guard CopperGolem.isPlainChest(key), !golemVisited.contains(p) else { continue }
                let slots: [ItemStack] = be.container.slots
                let partial: Bool = slots.contains { (t: ItemStack) -> Bool in !t.isEmpty && t.stacks(with: load) && t.count < t.maxStack }
                let hasItem: Bool = slots.contains { (t: ItemStack) -> Bool in t.stacks(with: load) }
                let hasRoom: Bool = slots.contains { (t: ItemStack) -> Bool in t.isEmpty }
                let matches: Bool = partial || (hasItem && hasRoom)
                if !matches {
                    guard slots.allSatisfy({ $0.isEmpty }) else { continue }
                    score += 10_000                                                  // empty chests only when nothing matches
                }
            }
            if score < bestScore { bestScore = score; best = p }
        }
        if let b = best {
            golemGoal = b
            return speed
        }
        golemTimer = 3                                                               // nothing to do: look again soon
        if !load.isEmpty { golemVisited.removeAll(keepingCapacity: true) }
        wander()
        return moving ? speed * 0.4 : 0
    }
}

// Model: a small copper figure with a lightning-rod antenna; it holds a crate while carrying.
func copperGolemParts(_ m: Mob, swing: Float) -> [Part] {
    let c = CopperGolem.color(CopperGolem.stage(m))
    let dark = c * 0.7
    let carrying = !(m.cargo?.slots[0].isEmpty ?? true)
    let arm: Float = carrying ? 1.2 : swing * 0.6
    var p = [
        Part(mn: V3(-3, 0, -1.5), mx: V3(-0.5, 5, 1.5), pivot: V3(-1.75, 5, 0), rotX: swing, color: dark),
        Part(mn: V3(0.5, 0, -1.5), mx: V3(3, 5, 1.5), pivot: V3(1.75, 5, 0), rotX: -swing, color: dark),
        box(-4, 5, -2.5, 8, 6, 5, c, 4),
        Part(mn: V3(-6, 4, -1), mx: V3(-4, 11, 1), pivot: V3(-5, 11, 0), rotX: arm, color: c),
        Part(mn: V3(4, 4, -1), mx: V3(6, 11, 1), pivot: V3(5, 11, 0), rotX: carrying ? arm : -arm, color: c),
        box(-4.5, 11, -4, 9, 6, 7, c, 4),
        box(-1, 12.5, -5, 2, 3, 1, dark),                                   // nose
        box(-0.5, 17, -0.5, 1, 3, 1, dark),                                  // antenna
        box(-1, 20, -1, 2, 2, 2, c * 1.1),
        box(-4.6, 14, -4.1, 2.5, 1.2, 0.3, V3(0.95, 0.85, 0.5)), box(2.1, 14, -4.1, 2.5, 1.2, 0.3, V3(0.95, 0.85, 0.5)),   // eyes
    ]
    if carrying { p.append(box(-3, 6, -8, 6, 5, 4, V3(0.62, 0.45, 0.25), 4)) }
    return p
}
