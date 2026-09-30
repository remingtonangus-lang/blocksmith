import Foundation
import simd

// Minecart variants (variant: 0 plain, 1 chest, 2 hopper, 3 TNT, 4 furnace).
enum Carts {
    static let items = ["minecart", "chest_minecart", "hopper_minecart", "tnt_minecart", "furnace_minecart"]
    static let blocks = ["", "chest", "hopper", "tnt", "furnace"]
    static func variant(of key: String) -> Int? { items.firstIndex(of: key) }
}

extension Mob {
    // Extra behaviour on top of the rail physics.
    func cartExtras(_ dt: Float, _ g: Game) {
        switch variant {
        case 2:
            // Hopper cart: vacuums items lying on or just above it.
            if cargo == nil { cargo = ItemContainer(5) }
            for e in g.drops.items where e.pickupDelay <= 0 && simd_length(e.pos - (pos + V3(0, 0.6, 0))) < 1 {
                let rest = cargo!.add(e.stack)
                if rest.count != e.stack.count { e.stack = rest; if rest.isEmpty { e.age = 1e9 } }
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
                    Explosion.explode(at: pos + V3(0, 0.5, 0), power: 4 + Float.random(in: 0...1.5) * speed, game: g, except: self)
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
                if Float.random(in: 0..<1) < dt * 6 { g.particles.smoke(at: pos + V3(0, 1, 0), dark: true) }
            }
        default: break
        }
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
    default: return []
    }
}

extension Game {
    // Right-click a cart: ride (plain), open (chest/hopper), fuel (furnace).
    func useCart(_ m: Mob) -> Bool {
        guard m.kind == .minecart else { return false }
        switch m.variant {
        case 1, 2:
            if m.cargo == nil { m.cargo = ItemContainer(m.variant == 1 ? 27 : 5) }
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
        default: return false
        }
    }
}

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
        h.tag = (screaming ? 4 : 0) + Int.random(in: 0..<4)
        g.drops.spawn(h, at: a)
        g.sfx(.goatRam, 1, at: a)
    }
}
