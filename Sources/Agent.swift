import Foundation
import Metal
import simd

// Agent API: bots play the real game. Every tick a bot reads an AgentState (what a player could know: position,
// health, the block in front, nearby blocks and mobs, the open menu) and returns an AgentAction, which is written
// into the same InputState the window's key and mouse handlers fill (held keys, mouse deltas, clicks), then
// Game.tick runs as in play. Nothing is teleported or granted after the start fixture.
//
// Determinism (for replays): Rand is seeded, World.deterministic applies streaming results in a fixed order,
// the pathfinder's wall-clock budget is off, SWIFT_DETERMINISTIC_HASHING fixes dictionary order (the runner
// re-executes itself with it set) and the tick is a fixed 1/60 s. A replay file (JSON lines: header + one
// action per tick) reproduces a run; `--agent replay FILE` plays it back with the oracles.
struct AgentAction: Equatable {
    var forward: Float = 0
    var strafe: Float = 0
    var yaw: Float = 0                 // look change this tick (radians, + = left)
    var pitch: Float = 0               // + = up
    var jump = false
    var sneak = false
    var sprint = false
    var attack = false                 // left button held
    var use = false                    // right button held
    var slot = -1                      // hotbar slot to select (0...8)
    var key: UInt16 = 0xFFFF           // one key tapped this tick (inventory, escape...), 0xFFFF none

    static let idle = AgentAction()

    var flags: Int { (jump ? 1 : 0) | (sneak ? 2 : 0) | (sprint ? 4 : 0) | (attack ? 8 : 0) | (use ? 16 : 0) }

    // Compact replay encoding: [forward, strafe, yaw, pitch, flags, slot, key].
    func encode() -> String {
        let f: String = String(format: "%.3f,%.3f,%.5f,%.5f", forward, strafe, yaw, pitch)
        return "[" + f + ",\(flags),\(slot),\(key)]"
    }
    static func decode(_ s: Substring) -> AgentAction? {
        let parts = s.trimmingCharacters(in: CharacterSet(charactersIn: "[] \n")).split(separator: ",")
        guard parts.count == 7, let f = Float(parts[0]), let st = Float(parts[1]), let y = Float(parts[2]), let p = Float(parts[3]),
              let fl = Int(parts[4]), let sl = Int(parts[5]), let k = UInt16(parts[6]) else { return nil }
        var a = AgentAction()
        a.forward = f; a.strafe = st; a.yaw = y; a.pitch = p
        a.jump = fl & 1 != 0; a.sneak = fl & 2 != 0; a.sprint = fl & 4 != 0; a.attack = fl & 8 != 0; a.use = fl & 16 != 0
        a.slot = sl; a.key = k
        return a
    }
}

struct AgentMob { let kind: String; let pos: V3; let dist: Float; let health: Int }

struct AgentState {
    let tick: Int
    let pos: V3, vel: V3
    let yaw: Float, pitch: Float
    let onGround: Bool, inWater: Bool, headInWater: Bool
    let health: Int, hunger: Int, alive: Bool
    let dim: String
    let menu: String?                  // open screen class name, nil while playing
    let paused: Bool, sleeping: Bool
    let held: String
    let target: IVec3?                 // block under the crosshair
    let targetBlock: String
    let timeOfDay: Double              // 0 sunrise, 0.25 noon, 0.5 sunset, 0.75 midnight
    let mobs: [AgentMob]               // within 24 blocks, nearest first

    static func glyph(_ b: BlockID) -> Character {
        if b == AIR { return "." }
        let fk = Blocks.fluidKind[Int(b)]
        if fk == 1 { return "~" }
        if fk == 2 { return "!" }
        return Blocks.fullCollide[Int(b)] ? "#" : "+"
    }

    // Text summary for LLM-driven turns (cheap: no pixels).
    func summary(_ w: World) -> String {
        var s = String(format: "tick %d  pos %.1f %.1f %.1f  yaw %.0f° pitch %.0f°  ", tick, pos.x, pos.y - Float(YOFF), pos.z,
                       yaw * 180 / .pi, pitch * 180 / .pi)
        s += "health \(health)/20 hunger \(hunger)/20  \(onGround ? "on ground" : (inWater ? "swimming" : "in the air"))  "
        s += String(format: "time %.2f  held %@\n", timeOfDay, held)
        if let m = menu { s += "screen open: \(m)\n" }
        if let t = target { s += "looking at \(targetBlock) at \(t.x) \(t.y - YOFF) \(t.z)\n" }
        // A 7x3x7 slice of solid/air/water around the feet, as rows.
        let fx = Int(floor(pos.x)), fy = Int(floor(pos.y)), fz = Int(floor(pos.z))
        for dy in [1, 0, -1] {
            var row = "y\(dy >= 0 ? "+" : "")\(dy): "
            for dz in -3...3 {
                for dx in -3...3 {
                    let b = w.block(fx + dx, fy + dy, fz + dz)
                    row.append(dx == 0 && dz == 0 ? "@" : AgentState.glyph(b))
                }
                row.append(" ")
            }
            s += row + "\n"
        }
        for m in mobs.prefix(6) { s += String(format: "mob %@ %.1f blocks away (health %d)\n", m.kind, m.dist, m.health) }
        return s
    }
}

// A bot: one action per tick, plus its own goal bookkeeping (Agent reports unmet goals as findings).
protocol AgentBot: AnyObject {
    var name: String { get }
    func act(_ s: AgentState, _ a: Agent) -> AgentAction
    func goals() -> [(String, Bool, String)]          // (goal, met, detail)
}

struct Violation { let tick: Int; let oracle: String; let detail: String; let pos: V3 }

final class Agent {
    let game: Game
    let world: World
    var tick = 0
    var log: [String] = []                       // replay lines (header first)
    var violations: [Violation] = []
    var counts: [String: Int] = [:]
    private var prev = AgentAction()
    private var lastHealth = 20
    private var damageCauses: [String] = []
    private var insideTicks = 0
    private var stillTicks = 0, stillFrom = V3(0, 0, 0)
    private var menuTicks = 0
    var tickMsWorst: Double = 0
    var visitedChunks = Set<Int>()

    init(game: Game, world: World) {
        self.game = game; self.world = world
        Game.onDamage = { [weak self] amount, cause in self?.damageCauses.append("\(cause) (\(amount))") }
    }
    deinit { Game.onDamage = nil }

    // MARK: Setup

    // A fresh deterministic world + survival game at the seed's spawn (or `at`, a disclosed fixture).
    static func makeWorld(device: MTLDevice, seed: UInt64, botSeed: UInt64, rd: Int = 6, at: V3? = nil) -> (World, Game) {
        Rand.seed(botSeed)
        World.deterministic = true
        let world = World(seed: seed, device: device, save: nil)
        world.renderDistance = rd
        let game = Game(world: world, save: nil, persistent: false)
        var p = at ?? game.spawnPoint
        if at != nil {
            let x = Int(floor(p.x)), z = Int(floor(p.z))
            _ = world.loadSync(center: p, radius: 2)
            p.y = Float(world.topY(x, z) + 1)
        }
        game.player.pos = p
        game.player.flying = false
        game.survival = true
        game.paused = false
        game.time = 0.05 * DAY_LENGTH
        _ = world.loadSync(center: p, radius: min(rd, 4))
        game.input.captured = true
        return (world, game)
    }

    // The runner needs fixed dictionary order: re-exec once with SWIFT_DETERMINISTIC_HASHING=1.
    static func ensureDeterministicHashing() {
        if getenv("SWIFT_DETERMINISTIC_HASHING") != nil { return }
        setenv("SWIFT_DETERMINISTIC_HASHING", "1", 1)
        let args = CommandLine.arguments
        var cargs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        cargs.append(nil)
        execv(args[0], &cargs)
        print("agent: could not re-exec with deterministic hashing; dictionary order may vary")
    }

    // MARK: Observe / act

    func observe() -> AgentState {
        let p = game.player
        var mobs: [AgentMob] = []
        for m in game.mobs.mobs where m.health > 0 {
            let d: Float = simd_length(m.pos - p.pos)
            if d < 24 { mobs.append(AgentMob(kind: m.kind.key, pos: m.pos, dist: d, health: m.health)) }
        }
        mobs.sort { (a: AgentMob, b: AgentMob) -> Bool in a.dist < b.dist }
        let t = game.target?.hit
        let tb = t.map { Blocks.key(world.block($0.x, $0.y, $0.z)) } ?? ""
        let menuName: String? = game.menu.map { String(describing: type(of: $0)) }
        let tod: Double = (game.time / DAY_LENGTH).truncatingRemainder(dividingBy: 1)
        return AgentState(tick: tick, pos: p.pos, vel: p.vel, yaw: p.yaw, pitch: p.pitch, onGround: p.onGround, inWater: p.inWater,
                          headInWater: p.headInWater, health: game.health, hunger: game.hunger, alive: game.alive,
                          dim: game.dim.dim.rawValue, menu: menuName, paused: game.paused, sleeping: game.sleeping > 0,
                          held: game.held.isEmpty ? "nothing" : Items.key(game.held.item), target: t, targetBlock: tb,
                          timeOfDay: tod, mobs: mobs)
    }

    // Writes an action into the input state exactly as the window's event handlers would.
    func apply(_ a: AgentAction) {
        let inp = game.input
        inp.keys.removeAll(keepingCapacity: true)
        func hold(_ k: UInt16, _ on: Bool, _ was: Bool) {
            if on { inp.keys.insert(k); if !was { inp.pressed.insert(k) } }
        }
        hold(KeyBinds.key(.forward), a.forward > 0.3, prev.forward > 0.3)
        hold(KeyBinds.key(.back), a.forward < -0.3, prev.forward < -0.3)
        hold(KeyBinds.key(.right), a.strafe > 0.3, prev.strafe > 0.3)
        hold(KeyBinds.key(.left), a.strafe < -0.3, prev.strafe < -0.3)
        hold(KeyBinds.key(.jump), a.jump, prev.jump)
        inp.shift = a.sneak
        inp.control = a.sprint
        inp.leftDown = a.attack
        inp.leftClicked = a.attack && !prev.attack
        inp.rightDown = a.use
        inp.rightClicked = a.use && !prev.use
        if a.key != 0xFFFF { inp.keys.insert(a.key); inp.pressed.insert(a.key) }
        if a.slot >= 0 && a.slot < 9 { inp.pressed.insert(Key.digits[a.slot]) }
        // Look through the mouse path (Game.tick: yaw -= dx * 0.0022 * sensitivity).
        let sens: Float = 0.0022 * max(0.05, game.sensitivity)
        inp.captured = true
        inp.mouseDX = -a.yaw / sens
        inp.mouseDY = -a.pitch / sens * (game.invertY ? -1 : 1)
        prev = a
    }

    // One fixed tick: act, run the game, check the oracles.
    func step(_ bot: AgentBot) {
        let s = observe()
        let a = s.alive ? bot.act(s, self) : AgentAction.idle
        log.append(a.encode())
        apply(a)
        let t0 = CFAbsoluteTimeGetCurrent()
        game.tick(1.0 / 60)
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        tickMsWorst = max(tickMsWorst, ms)
        check(a, ms)
        tick += 1
    }

    // MARK: Oracles (checked every tick)

    func flag(_ oracle: String, _ detail: String) {
        counts[oracle, default: 0] += 1
        if counts[oracle]! <= 3 { violations.append(Violation(tick: tick, oracle: oracle, detail: detail, pos: game.player.pos)) }
    }

    private func check(_ a: AgentAction, _ ms: Double) {
        let p = game.player
        let pos = p.pos
        if !(pos.x.isFinite && pos.y.isFinite && pos.z.isFinite && p.vel.x.isFinite && p.vel.y.isFinite && p.vel.z.isFinite) {
            flag("non_finite", "player position or velocity is not finite"); return
        }
        for m in game.mobs.mobs where !(m.pos.x.isFinite && m.pos.y.isFinite && m.pos.z.isFinite) {
            flag("non_finite", "\(m.kind.key) position is not finite")
            break
        }
        if game.dim.dim == .overworld && pos.y < 0 { flag("fell_out", String(format: "player fell to y %.1f", pos.y - Float(YOFF))) }
        // Inside a solid block (two ticks in a row, not while the game itself is pushing the player out).
        let lo = V3(pos.x - p.halfW + 0.05, pos.y + 0.05, pos.z - p.halfW + 0.05)
        let hi = V3(pos.x + p.halfW - 0.05, pos.y + p.height - 0.1, pos.z + p.halfW - 0.05)
        if game.alive && world.collides(lo, hi) {
            insideTicks += 1
            if insideTicks == 2 {
                let b = world.block(Int(floor(pos.x)), Int(floor(pos.y + 1)), Int(floor(pos.z)))
                flag("inside_solid", "player overlaps a solid block (\(Blocks.key(b)) at head height)")
            }
        } else { insideTicks = 0 }
        // Stuck: pressing forward for 4 s on the ground without moving half a block.
        if a.forward > 0.3 && game.menu == nil && p.onGround {
            if stillTicks == 0 { stillFrom = pos }
            stillTicks += 1
            let moved: Float = simd_length(V2(pos.x - stillFrom.x, pos.z - stillFrom.z))
            if moved > 0.5 { stillTicks = 0 }
            else if stillTicks == 240 {
                let f = V3(-sinf(p.yaw), 0, -cosf(p.yaw))
                let ahead = pos + f * 0.8
                let b0 = world.block(Int(floor(ahead.x)), Int(floor(pos.y)), Int(floor(ahead.z)))
                let b1 = world.block(Int(floor(ahead.x)), Int(floor(pos.y + 1)), Int(floor(ahead.z)))
                counts["stuck_events", default: 0] += 1
                if b0 == AIR && b1 == AIR {
                    // What actually stops the body: a block whose boxes overlap it nudged forward, or a mob in the way.
                    var why = "nothing found"
                    let n = pos + f * 0.15
                    let blo = V3(n.x - 0.3, n.y + 0.01, n.z - 0.3), bhi = V3(n.x + 0.3, n.y + 1.79, n.z + 0.3)
                    var boxes: [(V3, V3)] = []
                    search: for dy in 0...1 { for dz in -1...1 { for dx in -1...1 {
                        let cx = Int(floor(n.x)) + dx, cy = Int(floor(n.y)) + dy, cz = Int(floor(n.z)) + dz
                        boxes.removeAll(keepingCapacity: true)
                        world.collisionBoxes(cx, cy, cz, &boxes)
                        for (l, h) in boxes where l.x < bhi.x && h.x > blo.x && l.y < bhi.y && h.y > blo.y && l.z < bhi.z && h.z > blo.z {
                            why = "\(Blocks.key(world.block(cx, cy, cz))) at \(dx),\(dy),\(dz)"
                            break search
                        }
                    } } }
                    if why == "nothing found", let m = game.mobs.mobs.first(where: { simd_length($0.pos - n) < 0.9 }) { why = "a \(m.kind.key)" }
                    flag("stuck_open", "pressing forward for 4 s into open space without moving (blocked by \(why))")
                }
            }
        } else { stillTicks = 0 }
        // Damage the player didn't walk into: anything but fall / mob / known hazards is reported with its cause.
        if game.health < lastHealth && !damageCauses.isEmpty {
            for c in damageCauses where c.contains("suffocat") || c.contains("in a wall") || c.contains("unknown") {
                flag("unexpected_damage", c)
            }
        }
        damageCauses.removeAll(keepingCapacity: true)
        lastHealth = game.health
        // Entity explosions.
        if game.mobs.mobs.count > 600 { flag("entity_explosion", "\(game.mobs.mobs.count) mobs loaded") }
        if game.drops.items.count > 3000 { flag("entity_explosion", "\(game.drops.items.count) dropped items") }
        // Frame-time spikes (tick only; headless, so no GPU).
        if ms > 50 && tick > 120 { counts["tick_spikes", default: 0] += 1; if ms > 250 { flag("tick_spike", String(format: "Game.tick took %.0f ms", ms)) } }
        // A screen that stays open for 20 s (bots close menus with Escape; a menu that ignores it is a dead end).
        if game.menu != nil { menuTicks += 1; if menuTicks == 1200 { flag("ui_dead_end", "\(String(describing: type(of: game.menu!))) open for 20 s") } } else { menuTicks = 0 }
        let ck = floorDiv(Int(floor(pos.x)), CS) &* 1_000_003 &+ floorDiv(Int(floor(pos.z)), CS)
        visitedChunks.insert(ck)
    }

    // MARK: Runs

    struct RunResult { let violations: [Violation]; let counts: [String: Int]; let goals: [(String, Bool, String)]; let ticks: Int; let hash: UInt64 }

    // A digest of the end state (determinism check: the same replay must end in the same state).
    func stateHash() -> UInt64 {
        var h: UInt64 = 1469598103934665603
        func mix(_ v: UInt64) { h = (h ^ v) &* 1099511628211 }
        let p = game.player.pos
        mix(UInt64(bitPattern: Int64(p.x * 1000))); mix(UInt64(bitPattern: Int64(p.y * 1000))); mix(UInt64(bitPattern: Int64(p.z * 1000)))
        mix(UInt64(game.health)); mix(UInt64(game.mobs.mobs.count))
        for m in game.mobs.mobs.prefix(64) { mix(UInt64(bitPattern: Int64(m.pos.x * 100))); mix(UInt64(bitPattern: Int64(m.pos.z * 100))) }
        return h
    }

    func run(_ bot: AgentBot, ticks: Int, header: String) -> RunResult {
        log = [header]
        for _ in 0..<ticks { step(bot) }
        return RunResult(violations: violations, counts: counts, goals: bot.goals(), ticks: tick, hash: stateHash())
    }
}

// Replays a recorded action list (for minimising and for reproducing a report).
final class ReplayBot: AgentBot {
    let name = "replay"
    var actions: [AgentAction]
    var i = 0
    init(_ actions: [AgentAction]) { self.actions = actions }
    func act(_ s: AgentState, _ a: Agent) -> AgentAction {
        defer { i += 1 }
        return i < actions.count ? actions[i] : .idle
    }
    func goals() -> [(String, Bool, String)] { [] }
}
