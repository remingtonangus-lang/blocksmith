import Foundation
import simd

let DAY_LENGTH: Double = 1200 // seconds per full day/night cycle

final class Game {
    let world: World
    let player = Player()
    let input = InputState()
    let save: SaveManager?
    let persistent: Bool

    var time: Double = DAY_LENGTH * 0.06
    var hotbar: [UInt8] = [GRASS, DIRT, STONE, COBBLE, PLANKS, LOG, GLASS, TORCH, LAMP]
    var selected = 0
    var paused = true { didSet { if paused != oldValue { onPauseChanged?(paused) } } }
    var showDebug = false
    var target: (hit: IVec3, normal: IVec3)?

    var onPauseChanged: ((Bool) -> Void)?
    var onToast: ((String) -> Void)?
    var onRenderDistanceChanged: ((Int) -> Void)?

    private var breakCooldown: Double = 0
    private var placeCooldown: Double = 0
    private var lastSpaceTap: Double = -1
    private var clock: Double = 0
    private var prevPad = PadSnapshot()
    private var autosaveTimer: Double = 0
    private var fluidTimer: Double = 0
    var padConnected = false

    init(world: World, save: SaveManager?, persistent: Bool) {
        self.world = world
        self.save = save
        self.persistent = persistent
    }

    // MARK: Setup / persistence

    func findSpawn() -> V3 {
        // Spiral outward from the origin until we find dry land.
        var x = 0, z = 0, dx = 0, dz = -1
        for _ in 0..<4000 {
            let (h, biome) = world.gen.column(x * 16 + 8, z * 16 + 8)
            if h > SEA + 1 && biome != .ocean && biome != .mountains {
                return V3(Float(x * 16 + 8) + 0.5, Float(h + 1), Float(z * 16 + 8) + 0.5)
            }
            if x == z || (x < 0 && x == -z) || (x > 0 && x == 1 - z) { (dx, dz) = (-dz, dx) }
            x += dx; z += dz
        }
        return V3(0.5, Float(CH - 20), 0.5)
    }

    func apply(_ m: WorldMeta) {
        player.pos = V3(m.x, m.y, m.z)
        player.yaw = m.yaw
        player.pitch = m.pitch
        player.flying = m.flying
        time = m.time
        if m.hotbar.count == 9 { hotbar = m.hotbar }
        selected = max(0, min(8, m.selected))
        world.renderDistance = m.renderDistance
    }

    var meta: WorldMeta {
        WorldMeta(seed: world.seed, x: player.pos.x, y: player.pos.y, z: player.pos.z,
                  yaw: player.yaw, pitch: player.pitch, time: time, flying: player.flying,
                  hotbar: hotbar, selected: selected, renderDistance: world.renderDistance)
    }

    func saveNow() {
        guard persistent, let s = save else { return }
        world.saveAll()
        s.saveMeta(meta)
    }

    // MARK: Sky

    var dayFraction: Double { (time.truncatingRemainder(dividingBy: DAY_LENGTH)) / DAY_LENGTH }

    // Sun rises in +X at fraction 0, peaks at 0.25, sets at 0.5.
    var sunDir: V3 {
        let a = Float(dayFraction * 2 * .pi)
        return simd_normalize(V3(cosf(a), sinf(a), 0.35))
    }

    var daylight: Float {
        let s = sunDir.y
        let t = simd_clamp((s + 0.12) / 0.4, 0, 1)
        return 0.12 + 0.88 * t * t * (3 - 2 * t)
    }

    var skyColor: V3 {
        let day = V3(0.52, 0.72, 0.96), night = V3(0.015, 0.02, 0.06)
        var c = simd_mix(night, day, V3(repeating: (daylight - 0.12) / 0.88))
        let s = sunDir.y
        let dusk = max(0, 1 - abs(s - 0.02) / 0.22)
        c = simd_mix(c, V3(0.95, 0.5, 0.28), V3(repeating: dusk * 0.45))
        return c
    }

    // MARK: Hotbar

    func select(_ i: Int) {
        selected = (i % 9 + 9) % 9
        onToast?(Blocks.name(hotbar[selected]))
    }

    func cycleBlock(_ d: Int) {
        let list = Blocks.placeable
        let cur = list.firstIndex(of: hotbar[selected]) ?? 0
        hotbar[selected] = list[((cur + d) % list.count + list.count) % list.count]
        onToast?(Blocks.name(hotbar[selected]))
    }

    func pickBlock() {
        guard let t = target else { return }
        let b = world.block(t.hit.x, t.hit.y, t.hit.z)
        if let i = hotbar.firstIndex(of: b) { select(i); return }
        hotbar[selected] = b
        onToast?(Blocks.name(b))
    }

    func toggleFly() {
        player.flying.toggle()
        if player.flying { player.vel.y = 0 }
        onToast?(player.flying ? "Flying" : "Walking")
    }

    func cycleRenderDistance() {
        let opts = [4, 6, 8, 10, 12, 16]
        let i = opts.firstIndex(of: world.renderDistance) ?? 2
        world.renderDistance = opts[(i + 1) % opts.count]
        onRenderDistanceChanged?(world.renderDistance)
    }

    // MARK: Tick

    func tick(_ rawDt: Double) {
        let dt = min(rawDt, 0.05)
        clock += dt
        world.update(center: player.pos)

        let pad = readPad()
        padConnected = pad != nil
        let p = pad ?? PadSnapshot()
        let q = prevPad
        defer { prevPad = p; input.endFrame() }

        if p.menu && !q.menu { paused.toggle() }
        if paused {
            if p.a && !q.a { paused = false }
            if (p.right && !q.right) || (p.left && !q.left) { cycleRenderDistance() }
            return
        }

        let fdt = Float(dt)

        // Look
        if input.captured {
            let sens: Float = 0.0022
            player.yaw -= input.mouseDX * sens
            player.pitch -= input.mouseDY * sens
        }
        let rs = stick(p.rx, p.ry)
        player.yaw -= rs.x * 3.4 * fdt
        player.pitch += rs.y * 2.6 * fdt
        player.pitch = simd_clamp(player.pitch, -1.55, 1.55)
        player.yaw = player.yaw.truncatingRemainder(dividingBy: 2 * .pi)

        // Movement
        var mi = MoveInput()
        if input.down(Key.w) { mi.forward += 1 }
        if input.down(Key.s) { mi.forward -= 1 }
        if input.down(Key.d) { mi.strafe += 1 }
        if input.down(Key.a) { mi.strafe -= 1 }
        let ls = stick(p.lx, p.ly)
        mi.forward += ls.y
        mi.strafe += ls.x
        mi.forward = simd_clamp(mi.forward, -1, 1)
        mi.strafe = simd_clamp(mi.strafe, -1, 1)
        mi.jump = input.down(Key.space) || p.a
        mi.sneak = input.shift || p.b || p.r3
        if input.control || (p.l3 && !q.l3) { player.sprinting = true }
        mi.sprint = player.sprinting && (mi.forward > 0.3)
        if mi.forward <= 0.3 { player.sprinting = false }

        if input.tapped(Key.space) {
            if clock - lastSpaceTap < 0.3 { toggleFly(); lastSpaceTap = -1 } else { lastSpaceTap = clock }
        }
        if input.tapped(Key.f) || (p.y && !q.y) { toggleFly() }
        if input.tapped(Key.f3) { showDebug.toggle() }

        // Hotbar
        for (i, k) in Key.digits.enumerated() where input.tapped(k) { select(i) }
        if input.scrollSteps != 0 { select(selected - input.scrollSteps) }
        if p.rb && !q.rb { select(selected + 1) }
        if p.lb && !q.lb { select(selected - 1) }
        if input.tapped(Key.rightBracket) || (p.up && !q.up) { cycleBlock(1) }
        if input.tapped(Key.leftBracket) || (p.down && !q.down) { cycleBlock(-1) }

        player.update(dt: fdt, input: mi, world: world)

        // Interact
        target = world.raycast(player.eye, player.look, maxDist: 5)
        breakCooldown -= dt
        placeCooldown -= dt
        let breakHeld = input.leftDown || p.rt > 0.5
        let breakNow = input.leftClicked || (p.rt > 0.5 && q.rt <= 0.5)
        if let t = target, breakNow || (breakHeld && breakCooldown <= 0) {
            world.setBlock(t.hit.x, t.hit.y, t.hit.z, AIR)
            // Plants can't float: pop the one standing on the broken block.
            if Blocks.isPlant(world.block(t.hit.x, t.hit.y + 1, t.hit.z)) { world.setBlock(t.hit.x, t.hit.y + 1, t.hit.z, AIR) }
            breakCooldown = 0.25
            target = world.raycast(player.eye, player.look, maxDist: 5)
        }
        let placeHeld = input.rightDown || p.lt > 0.5
        let placeNow = input.rightClicked || (p.lt > 0.5 && q.lt <= 0.5)
        if let t = target, placeNow || (placeHeld && placeCooldown <= 0) {
            // Clicking a plant replaces it (like tall grass); otherwise place against the face.
            let at = Blocks.isPlant(world.block(t.hit.x, t.hit.y, t.hit.z)) ? t.hit : t.hit + t.normal
            let existing = world.block(at.x, at.y, at.z)
            let id = hotbar[selected]
            let solid = Blocks.collide[Int(id)]
            let replaceable = existing == AIR || Blocks.isLiquid(existing) || Blocks.isPlant(existing)
            let supported: Bool
            if id == TORCH {
                // Torches stand on the floor or hang on a wall.
                supported = [IVec3(0, -1, 0), IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)].contains { d in
                    Blocks.opaque[Int(world.block(at.x + d.x, at.y + d.y, at.z + d.z))]
                }
            } else {
                supported = !Blocks.isPlant(id) || Blocks.opaque[Int(world.block(at.x, at.y - 1, at.z))]
            }
            if replaceable && supported && at.y >= 0 && at.y < CH && !(solid && player.intersectsBlock(at)) {
                world.setBlock(at.x, at.y, at.z, id)
            }
            placeCooldown = 0.25
        }
        if input.middleClicked || (p.x && !q.x) { pickBlock() }

        fluidTimer += dt
        if fluidTimer >= 0.2 { fluidTimer = 0; world.fluidTick() }

        time += dt
        autosaveTimer += dt
        if autosaveTimer > 60 { autosaveTimer = 0; saveNow() }
    }
}
