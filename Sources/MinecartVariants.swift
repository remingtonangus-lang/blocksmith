import Foundation
import simd

// Minecart variants (variant: 0 plain, 1 chest, 2 hopper, 3 TNT, 4 furnace, 5 engine).
enum Carts {
    static let items = ["minecart", "chest_minecart", "hopper_minecart", "tnt_minecart", "furnace_minecart", "engine_cart"]
    static let blocks = ["", "chest", "hopper", "tnt", "furnace", ""]
    static func variant(of key: String) -> Int? { items.firstIndex(of: key) }

    // P132 (Oct 12 PM, "minecarts where you can... put an engine on them... it requires a power source"): the engine
    // cart. You ride it; push the stick (or W) to drive along the track, back to brake and reverse, up to 14 blocks a
    // second on straights and 7 through curves. It runs on fuel put into it: coal or charcoal 2 minutes, a block of coal
    // 18, a blaze rod 3, a Copper Battery 10 (the power source); fuel burns only while it drives. With rails in hand
    // and use held, any cart you ride lays track ahead of itself where the line runs out (Game.cartLayTrack).
    static let engine = 5
    static let engineTop: Float = 14, engineCurve: Float = 7, engineAccel: Float = 9
    static let fuelCap: Float = 1800
    static func fuelSeconds(_ key: String) -> Float? {
        switch key {
        case "coal", "charcoal": return 120
        case "coal_block": return 1080
        case "blaze_rod": return 180
        case "redstone_block": return 600
        default: return nil
        }
    }
}

extension Mob {
    // Extra behaviour on top of the rail physics.
    func cartExtras(_ dt: Float, _ g: Game) {
        switch variant {
        case 2:
            // Hopper cart: vacuums items lying on or just above it and (W6) pulls one item a tick from a container
            // above the track. An activator rail turns it off while powered and back on while unpowered (reference);
            // hoppers under the track empty it (Game.hopperTransfer through Game.cartContainer).
            if cargo == nil { cargo = ItemContainer(5) }
            let cell = IVec3(Int(floor(pos.x)), Int(floor(pos.y + 0.1)), Int(floor(pos.z)))
            let rb = g.world.block(cell.x, cell.y, cell.z)
            if Circuit.kind(rb) == .activatorRail { hopperDisabled = Int(rb - Blocks.groupBase[Int(rb)]) >= 6 }
            if hopperDisabled { break }
            for e in g.drops.items where e.pickupDelay <= 0 && simd_length(e.pos - (pos + V3(0, 0.6, 0))) < 1 {
                let rest = cargo!.add(e.stack)
                if rest.count != e.stack.count { e.stack = rest; if rest.isEmpty { e.age = 1e9 } }
            }
            jobTimer = min(jobTimer, 0.05) - dt
            if jobTimer <= 0 {
                jobTimer = 0.05
                let above = cell + IVec3(0, 1, 0)
                if g.world.blockEntities[above] != nil, let c = cargo, g.containerExtract(above, into: c) { g.world.redstone.wakeAround(above) }
            }
        case 3:
            // TNT cart: fuse lit by an active activator rail, fire, or a hard hit; blows up when the fuse ends.
            let cell = IVec3(Int(floor(pos.x)), Int(floor(pos.y + 0.1)), Int(floor(pos.z)))
            let b = g.world.block(cell.x, cell.y, cell.z)
            if fuse <= 0 && (Circuit.kind(b) == .activatorRail && Int(b - Blocks.groupBase[Int(b)]) >= 6 || fire > 0) { fuse = 4 }
            if fuse > 0 {
                fuse -= dt
                if fuse <= 0 {
                    health = -1000
                    let speed = min(5, simd_length(vel))
                    Explosion.explode(at: pos + V3(0, 0.5, 0), power: 4 + Rand.float(in: 0...1.5) * speed, game: g, except: self)
                }
            }
        case 4:
            // Furnace cart: burns fuel (3 minutes per coal) and pushes itself along the track.
            if jobTimer > 0 {
                jobTimer -= dt
                let dir = forward
                vel += V3(dir.x, 0, dir.z) * 6 * dt
                let sp = simd_length(V2(vel.x, vel.z))
                if sp > 4 { vel.x *= 4 / sp; vel.z *= 4 / sp }
                if Rand.float(in: 0..<1) < dt * 6 { g.particles.smoke(at: pos + V3(0, 1, 0), dark: true) }
            }
        default: break
        }
    }
}

extension Mob {
    // W6: a hopper minecart switched off by a powered activator rail (kept in `sheared`, which is saved for every mob
    // and means nothing else for a cart).
    var hopperDisabled: Bool {
        get { sheared }
        set { sheared = newValue }
    }
}

// The block riding in a cart.
func cartTop(_ m: Mob) -> [Part] {
    switch m.variant {
    case 1: return [box(-6, 4, -6, 12, 12, 12, V3(0.62, 0.45, 0.22)), box(-1, 10, -6.3, 2, 3, 0.4, V3(0.8, 0.8, 0.8))]
    case 2: return [box(-7, 10, -7, 14, 5, 14, V3(0.3, 0.3, 0.32)), box(-4, 4, -4, 8, 6, 8, V3(0.26, 0.26, 0.28))]
    case 3:
        let lit = m.fuse > 0 && Int(m.fuse * 8) % 2 == 0
        return [box(-6, 4, -6, 12, 12, 12, lit ? V3(1, 1, 1) : V3(0.8, 0.2, 0.15)), box(-6.1, 8, -6.1, 12.2, 4, 12.2, V3(0.85, 0.85, 0.8))]
    case 4: return [box(-6, 4, -6, 12, 12, 12, V3(0.45, 0.45, 0.45)), box(-3, 6, -6.3, 6, 4, 0.4, m.jobTimer > 0 ? V3(1, 0.6, 0.2) : V3(0.1, 0.1, 0.1))]
    case Carts.engine:
        // The engine at the front: a copper-banded firebox, its stack and a lamp; the seat stays open behind it.
        let fire = m.jobTimer > 0 ? V3(1, 0.55, 0.15) : V3(0.12, 0.1, 0.1)
        return [box(-6, 4, -7, 12, 8, 5, V3(0.24, 0.24, 0.26)), box(-6.2, 6, -7.2, 12.4, 1.2, 5.4, V3(0.78, 0.45, 0.25)),
                box(-2.5, 5, -7.4, 5, 3, 0.4, fire), box(-1.5, 12, -6, 3, 6, 3, V3(0.16, 0.16, 0.17)),
                box(-1, 9, -7.6, 2, 2, 0.4, V3(1, 0.95, 0.7))]
    default: return []
    }
}

extension Game {
    // Right-click a cart: ride (plain), open (chest/hopper), fuel (furnace).
    func useCart(_ m: Mob) -> Bool {
        guard m.kind == .minecart else { return false }
        switch m.variant {
        case 1, 2:
            // Its own size (a saved cart came back with whatever slot count was stored, an empty list included).
            let want = m.variant == 1 ? 27 : 5
            if m.cargo == nil { m.cargo = ItemContainer(want) }
            if let c = m.cargo, c.count < want {
                let grown = ItemContainer(want)
                for i in 0..<c.count { grown[i] = c[i] }
                m.cargo = grown
            }
            openMenu(m.variant == 1 ? ChestMenu(game: self, container: m.cargo!, title: "Minecart with Chest")
                                    : PackMenu(game: self, container: m.cargo!, title: "Minecart with Hopper"))
            return true
        case 4:
            let k = Items.key(held.item)
            if k == "coal" || k == "charcoal" {
                m.jobTimer = min(m.jobTimer + 180, 900)
                m.yaw = player.yaw
                if survival { consumeHeld() }
                return true
            }
            return true
        case 3: return true
        case Carts.engine:
            let k = Items.key(held.item)
            if let secs = Carts.fuelSeconds(k) {
                guard m.jobTimer < Carts.fuelCap - 1 else { onToast?("The engine's bunker is full"); return true }
                m.jobTimer = min(Carts.fuelCap, m.jobTimer + secs)
                if survival { consumeHeld() }
                sfx(.place(.stone), 0.5, at: m.pos)
                onToast?("Engine fuel: \(Int(m.jobTimer / 60)) min \(Int(m.jobTimer.truncatingRemainder(dividingBy: 60))) s")
                return true
            }
            return false                                  // anything else: climb in (Game.interactMob)
        default: return false
        }
    }

    // Riding a cart with rails in hand and use held: a rail goes down on the next cell ahead where the track ends
    // (with something solid under it), and the track shapes itself (P132).
    func cartLayTrack(_ cart: Mob, use: Bool? = nil) {
        guard riding === cart, Items.key(held.item) == "rail", use ?? (input.rightDown || (seatPad?.lt ?? 0) > 0.5) else { return }
        let fwd = simd_length(V2(cart.vel.x, cart.vel.z)) > 0.2 ? simd_normalize(V2(cart.vel.x, cart.vel.z))
                                                                  : V2(-sinf(player.yaw), -cosf(player.yaw))
        let step = abs(fwd.x) > abs(fwd.y) ? IVec3(fwd.x > 0 ? 1 : -1, 0, 0) : IVec3(0, 0, fwd.y > 0 ? 1 : -1)
        let cell = IVec3(Int(floor(cart.pos.x)), Int(floor(cart.pos.y + 0.1)), Int(floor(cart.pos.z)))
        // The cell ahead of the cart's own: a rail goes down there when the line runs out (and something solid is below).
        guard Rails.isRail(world.block(cell.x, cell.y, cell.z)) else { return }
        let n = cell + step
        guard !Rails.isRail(world.block(n.x, n.y, n.z)), !Rails.isRail(world.block(n.x, n.y - 1, n.z)),
              Blocks.replaceable[Int(world.materialAt(n.x, n.y, n.z))], world.solidAt(n.x, n.y - 1, n.z) else { return }
        world.setBlock(n.x, n.y, n.z, Blocks.id("rail"))
        Rails.autoShape(world, n)
        if survival { consumeHeld() }
        sfx(.place(.stone), 0.5, at: V3(Float(n.x) + 0.5, Float(n.y), Float(n.z) + 0.5))
        CartTrack.laid += 1
    }
}

enum CartTrack { static var laid = 0 }

// Goats ramming a log, stone, ore or packed ice drop a goat horn (two per goat; tag = horn variant).
enum GoatHorns {
    static let names = ["Ponder", "Sing", "Seek", "Feel", "Admire", "Call", "Yearn", "Dream"]
}

extension Mob {
    func goatRam(_ g: Game) {
        guard kind == .goat, !baby, simd_length(V2(vel.x, vel.z)) > 1.5 else { return }
        let a = pos + forward * (halfW + 0.4) + V3(0, 0.5, 0)
        let b = g.world.block(Int(floor(a.x)), Int(floor(a.y)), Int(floor(a.z)))
        let k = Blocks.key(Blocks.groupBase[Int(b)])
        guard k.hasSuffix("_log") || k == "stone" || k.hasSuffix("_ore") || k == "packed_ice" else { return }
        aggro = false
        let dropped = (variant >> 12) & 3
        guard dropped < 2, Items.has("goat_horn") else { return }
        variant = (variant & ~(3 << 12)) | ((dropped + 1) << 12)
        var h = ItemStack(Items.id("goat_horn"), 1)
        let screaming = variant & 1 == 1
        h.tag = (screaming ? 4 : 0) + Rand.int(in: 0..<4)
        g.drops.spawn(h, at: a)
        g.sfx(.goatRam, 1, at: a)
    }
}
