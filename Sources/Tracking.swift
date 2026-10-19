import Foundation
import simd

// D46: bait and wind, tracks and blood trails, snares.
//   wind     game smells you on the wind: an animal downwind of you notices you half again as far off as its eyes would
//            (deer at 30 blocks), one upwind barely at all (six in ten of it). Sneak with game near and a word tells
//            you which way the wind sits. The wind is the sky's (the clouds drift with it).
//   bait     Game Bait (wheat, an apple and sugar; two a craft): use it to set a pile at your feet. Deer, elk, bison and
//            boar within 40 blocks come to it and stand eating for eight seconds, noticing you at half the distance.
//   tracks   game leaves prints as it walks (deer, elk, bison, boar, and the hunted kinds: rabbit, fox, wolf, goat and
//            bear). Crouch and the prints within 28 blocks show, fading over four minutes.
//   blood    a wounded animal drips blood and leaves red prints you can see without crouching, for longer.
//   snares   a Snare (string and a stick) set on the ground holds a rabbit, fox, chicken, boar or deer that walks into
//            it until you come for it; an elk or a bison tears it away.
enum Tracking {
    static let baitKey = "game_bait", snareKey = "snare"
    struct Print { var pos: V3; var t: Double; var blood: Bool }
    static var prints: [Print] = []
    static var last: [ObjectIdentifier: V3] = [:]
    static var eating: [ObjectIdentifier: Float] = [:]
    static var caughtToasted = Set<ObjectIdentifier>()
    static var windToldAt: Double = -1e9
    static var wasSneaking = false
    static var printsMade = 0, baitEaten = 0, snared = 0                // (harness)
    static let printLife: Double = 240, bloodLife: Double = 420

    static let tracked: Set<MobKind> = Set(Hunting.animals.map { $0.kind }).union([.deer, .elk, .bison, .boar])
    static let snareable: Set<MobKind> = [.rabbit, .fox, .chicken, .boar, .deer]

    // MARK: Wind

    // How far off an animal at `animal` notices a player at `player`, as a share of its eyes' reach.
    static func scent(_ g: Game, player: V3, animal: V3) -> Float {
        let d = V2(animal.x - player.x, animal.z - player.z)
        let l = simd_length(d)
        guard l > 0.5 else { return 1 }
        let along = simd_dot(d / l, g.sky.wind)
        return along > 0.5 ? 1.7 : (along < -0.3 ? 0.6 : 1)
    }

    static func compass(_ v: V2) -> String {
        let names = ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
        let a = atan2f(v.y, v.x)
        let i = Int((a / (.pi / 4)).rounded())
        return names[((i % 8) + 8) % 8]
    }

    // Q2: where the wind comes from as you face (a compass point means little in a headset).
    static func relative(_ g: Game) -> String {
        let w = g.sky.wind
        guard simd_length(w) > 0.01 else { return "" }
        let u = -simd_normalize(w)
        let yaw = g.player.yaw
        let fwd = V2(-sinf(yaw), -cosf(yaw)), right = V2(cosf(yaw), -sinf(yaw))
        let f = simd_dot(u, fwd), r = simd_dot(u, right)
        if f > 0.7 { return ", in your face" }
        if f < -0.7 { return ", at your back" }
        return r > 0 ? ", from your right" : ", from your left"
    }

    // MARK: Prints (animalAI)

    static func step(_ m: Mob, _ g: Game, _ dt: Float) {
        guard tracked.contains(m.kind), m.onGround, !m.baby else { return }
        let id = ObjectIdentifier(m)
        let wounded = m.health < m.spec.health && m.health > 0
        let lp = last[id] ?? m.pos
        if simd_length(V2(lp.x - m.pos.x, lp.z - m.pos.z)) > (wounded ? 0.9 : 1.4) || last[id] == nil {
            last[id] = m.pos
            prints.append(Print(pos: V3(m.pos.x, floorf(m.pos.y) + 0.04, m.pos.z), t: g.clock, blood: wounded))
            printsMade += 1
            if prints.count > 900 { prints.removeFirst(200) }
            if last.count > 400 { last = last.filter { k, _ in g.mobs.mobs.contains { ObjectIdentifier($0) == k } } }
        }
        if wounded && Rand.float(in: 0..<1) < dt * 2 {
            g.particles.add(Particle(pos: m.pos + V3(Rand.float(in: -0.2...0.2), m.height * 0.5, Rand.float(in: -0.2...0.2)), vel: V3(0, -0.5, 0),
                                     life: 0.8, maxLife: 0.8, layer: Int(Tex.id("smoke")), uv0: .zero, uvSize: 1, size: 0.06, gravity: 9,
                                     color: V3(0.5, 0.03, 0.03), collide: true))
        }
    }

    // Once a second (TownLaw.tick): show the prints, tell the wind.
    static func tick(_ g: Game) {
        guard g.dim.dim == .overworld else { return }
        let now = g.clock
        prints.removeAll { now - $0.t > ($0.blood ? bloodLife : printLife) }
        let p = g.player.pos
        let sneak = g.player.sneaking
        var shown = 0
        let smoke = Int(Tex.id("smoke"))
        for pr in prints.reversed() where shown < 160 {
            let d = simd_length(pr.pos - p)
            guard (sneak && d < 28) || (pr.blood && d < 16) else { continue }
            let age = Float((now - pr.t) / (pr.blood ? bloodLife : printLife))
            let c = pr.blood ? V3(0.45, 0.04, 0.04) : V3(0.16, 0.12, 0.08) * (1 + age * 2)
            g.particles.add(Particle(pos: pr.pos, vel: .zero, life: 1.15, maxLife: 1.15, layer: smoke, uv0: .zero, uvSize: 1,
                                     size: pr.blood ? 0.1 : 0.13 * (1 - age * 0.5), gravity: 0, color: c, collide: false))
            shown += 1
        }
        // The wind, told once in a while when you start to stalk game.
        if sneak && !wasSneaking && now - windToldAt > 45,
           g.mobs.mobs.contains(where: { $0.kind.herdGame && $0.health > 0 && simd_length($0.pos - p) < 48 }) {
            windToldAt = now
            let from = compass(-g.sky.wind)
            g.onToast?("The wind's from the \(from)\(relative(g))")
        }
        wasSneaking = sneak
    }

    // MARK: Bait

    static func useBait(_ g: Game) -> Bool {
        guard !g.held.isEmpty, Items.key(g.held.item) == baitKey else { return false }
        let at = g.player.pos + V3(g.player.look.x, 0, g.player.look.z) * 1.2 + V3(0, 0.3, 0)
        g.drops.spawn(ItemStack(Items.id(baitKey), 1), at: at, vel: .zero, delay: 8)
        if g.survival { g.consumeHeld() }
        g.sfx(.place(.grass), 0.5, at: at)
        g.onToast?("Bait set")
        return true
    }

    // herdAI: walk to bait and eat it (nil: no bait to see to).
    static func baitStep(_ m: Mob, _ g: Game, _ dt: Float) -> Float? {
        let id = ObjectIdentifier(m)
        if let t = eating[id] {
            if t <= dt { eating[id] = nil; return nil }
            eating[id] = t - dt
            m.moving = false
            m.walkAmount = 0
            return 0
        }
        guard Items.has(baitKey) else { return nil }
        let bait = Items.id(baitKey)
        var best: ItemEntity?, bd: Float = 40
        for it in g.drops.items where it.stack.item == bait {
            let d = simd_length(it.pos - m.pos)
            if d < bd { bd = d; best = it }
        }
        guard let b = best else { return nil }
        if bd < 1.4 {
            if b.stack.count > 1 { b.stack.count -= 1 } else { g.drops.items.removeAll { $0 === b } }
            eating[id] = 8
            baitEaten += 1
            g.sfx(.eat, 0.6, at: m.pos)
            return 0
        }
        m.face(b.pos)
        m.moving = true
        return m.spec.speed * 0.5
    }

    static func isEating(_ m: Mob) -> Bool { eating[ObjectIdentifier(m)] != nil }

    // MARK: Snares

    // animalAI: true while the animal is held in a snare.
    static func snaredStep(_ m: Mob, _ g: Game) -> Bool {
        guard Blocks.has(snareKey) else { return false }
        let x = Int(floor(m.pos.x)), y = Int(floor(m.pos.y + 0.1)), z = Int(floor(m.pos.z))
        guard g.world.builtBlock(x, y, z) == Blocks.id(snareKey) else { return false }
        if m.kind == .elk || m.kind == .bison {
            g.world.setBlock(x, y, z, AIR)
            g.sfx(.itemBreak, 0.6, at: m.pos)
            return false
        }
        guard snareable.contains(m.kind) else { return false }
        m.vel.x = 0; m.vel.z = 0
        m.moving = false
        let id = ObjectIdentifier(m)
        if !caughtToasted.contains(id) {
            caughtToasted.insert(id)
            snared += 1
            let d = simd_length(m.pos - g.player.pos)
            if d < 96 { g.onToast?("A \(m.spec.name.lowercased()) is caught in your snare, \(Int(d)) m \(Waymarks.side(g, m.pos))") }   // Q2: where
        }
        return true
    }
}

extension ItemRegistry {
    func registerTrackingItems() {
        guard !has(Tracking.baitKey) else { return }
        var d = ItemDef(Tracking.baitKey, "Game Bait")
        d.sprite = Sprite(mask: "seeds", base: 0xB89048, extras: [:])
        d.maxStack = 16
        add(d)
    }
}

extension BlockRegistry {
    func registerSnare() {
        guard !has(Tracking.snareKey) else { return }
        var d = BlockDef(Tracking.snareKey, "Snare")
        d.tex = ["snare"]; d.render = .cross; d.layer = .cutout; d.opaque = false; d.collide = false
        d.hardness = 0.2; d.sound = .wood; d.skyStop = false
        add(d)
    }
}

extension TextureGen {
    // A wire loop on a peg, the rest see-through.
    static func snarePainters(_ p: inout [String: Painter]) {
        p["snare"] = { x, y in
            if (x == 7 || x == 8) && y >= 10 { return hex(0x7A5232) }                     // the peg
            let dx = Float(x) - 7.5, dy = Float(y) - 6.5
            let r = (dx * dx + dy * dy).squareRoot()
            if r > 3.6 && r < 4.7 { return hex(0x9A9488, 0.85 + 0.25 * TextureGen.r(x, y, 4613)) }
            if x == 8 && y > 10 - 1 && y < 11 { return hex(0x9A9488) }
            return TextureGen.clear
        }
    }
}

extension Tracking {
    static func recipes() -> [Recipe?] {
        [Recipes.shapeless(["wheat", "apple", "sugar"], baitKey, 2), Recipes.shapeless(["string", "string", "stick"], snareKey, 2)]
    }
}
