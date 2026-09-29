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

    // Creative inventory (drawn by the HUD, driven by pad, keyboard or mouse)
    var inventoryOpen = false {
        didSet {
            input.uiMode = inventoryOpen
            if inventoryOpen != oldValue { onInventoryChanged?(inventoryOpen) }
        }
    }
    var invCursor = 0
    let inventoryItems: [UInt8] = Blocks.placeable
    var screen = V2(1280, 800) // drawable size, updated by the renderer each frame
    var onInventoryChanged: ((Bool) -> Void)?
    private var navTimer: Double = 0
    private var navHeld = false

    // Survival
    var survival = false {
        didSet {
            if survival { player.flying = false }
            if survival != oldValue { onModeChanged?(survival) }
        }
    }
    var health = 20            // half-hearts
    var hunger = 20            // half-drumsticks
    var saturation: Float = 5
    var exhaustion: Float = 0
    var air: Float = 15        // seconds of breath
    var hurtFlash: Float = 0   // seconds left of the red damage tint
    private var regenTimer: Double = 0
    private var starveTimer: Double = 0
    private var drownTimer: Double = 0
    private var eatCooldown: Double = 0
    lazy var spawnPoint: V3 = findSpawn()
    var onModeChanged: ((Bool) -> Void)?

    // Audio (nil when headless or if the audio device can't start)
    var sound: SoundEngine?
    private var stepDist: Float = 0
    private var wasInWater = false

    func sfx(_ s: Snd, _ v: Float = 1, at pos: V3? = nil) {
        sound?.play(s, volume: v, at: pos, listener: player.eye, yaw: player.yaw)
    }

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
        survival = m.survival ?? false
        health = max(1, min(20, m.health ?? 20))
        hunger = max(0, min(20, m.hunger ?? 20))
        saturation = m.saturation ?? 5
    }

    var meta: WorldMeta {
        WorldMeta(seed: world.seed, x: player.pos.x, y: player.pos.y, z: player.pos.z,
                  yaw: player.yaw, pitch: player.pitch, time: time, flying: player.flying,
                  hotbar: hotbar, selected: selected, renderDistance: world.renderDistance,
                  survival: survival, health: health, hunger: hunger, saturation: saturation)
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
        if survival { onToast?("No flying in survival"); return }
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
            if p.x && !q.x { toggleMode() }
            if (p.right && !q.right) || (p.left && !q.left) { cycleRenderDistance() }
            return
        }

        let fdt = Float(dt)

        if input.tapped(Key.e) || (p.view && !q.view) { inventoryOpen.toggle(); sfx(.open, 0.6) }
        if inventoryOpen {
            tickInventory(p, q, dt)
            let before = player.pos
            player.update(dt: fdt, input: MoveInput(), world: world)
            survivalTick(dt, from: before)
            target = nil
            advance(dt)
            return
        }

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
        mi.sprint = player.sprinting && (mi.forward > 0.3) && !(survival && hunger <= 6)
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

        let before = player.pos
        player.update(dt: fdt, input: mi, world: world)
        audioTick(from: before)
        survivalTick(dt, from: before)

        // Interact
        target = world.raycast(player.eye, player.look, maxDist: 5)
        breakCooldown -= dt
        placeCooldown -= dt
        let breakHeld = input.leftDown || p.rt > 0.5
        let breakNow = input.leftClicked || (p.rt > 0.5 && q.rt <= 0.5)
        if let t = target, breakNow || (breakHeld && breakCooldown <= 0) {
            let broken = world.block(t.hit.x, t.hit.y, t.hit.z)
            sfx(.breakBlock(soundMat(broken)), at: V3(Float(t.hit.x), Float(t.hit.y), Float(t.hit.z)) + 0.5)
            world.setBlock(t.hit.x, t.hit.y, t.hit.z, AIR)
            if survival { exhaustion += 0.005 }
            // Plants can't float: pop the one standing on the broken block.
            if Blocks.isPlant(world.block(t.hit.x, t.hit.y + 1, t.hit.z)) { world.setBlock(t.hit.x, t.hit.y + 1, t.hit.z, AIR) }
            breakCooldown = 0.25
            target = world.raycast(player.eye, player.look, maxDist: 5)
        }
        let placeHeld = input.rightDown || p.lt > 0.5
        let placeNow = input.rightClicked || (p.lt > 0.5 && q.lt <= 0.5)
        eatCooldown -= dt
        if Blocks.isItem(hotbar[selected]) {
            if (placeNow || placeHeld) && eatCooldown <= 0 { eat(hotbar[selected]); eatCooldown = 0.8 }
        } else if let t = target, placeNow || (placeHeld && placeCooldown <= 0) {
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
                sfx(.place(soundMat(id)), at: V3(Float(at.x), Float(at.y), Float(at.z)) + 0.5)
            }
            placeCooldown = 0.25
        }
        if input.middleClicked || (p.x && !q.x) { pickBlock() }

        advance(dt)
    }

    // MARK: Survival

    func toggleMode() {
        survival.toggle()
        onToast?(survival ? "Survival mode" : "Creative mode")
    }

    func eat(_ id: UInt8) {
        guard survival else { onToast?("Food only matters in survival"); return }
        guard hunger < 20 else { onToast?("Not hungry"); return }
        if id == APPLE {
            sfx(.eat)
            hunger = min(20, hunger + 4)
            saturation = min(Float(hunger), saturation + 2.4)
            onToast?("Ate an apple")
        }
    }

    func damage(_ amount: Int, _ cause: String) {
        guard survival, amount > 0 else { return }
        health -= amount
        hurtFlash = 0.35
        sfx(.hurt)
        if health <= 0 { die(cause) }
    }

    func die(_ cause: String) {
        onToast?("You \(cause). Respawning…")
        player.pos = spawnPoint
        player.vel = .zero
        player.airPeak = spawnPoint.y
        player.pendingFall = 0
        health = 20
        hunger = 20
        saturation = 5
        exhaustion = 0
        air = 15
    }

    // Footsteps, landing thuds and splashes.
    private func audioTick(from before: V3) {
        let p = player
        if p.inWater && !wasInWater && p.vel.y < -3 { sfx(.splash, min(1, -p.vel.y / 12)) }
        wasInWater = p.inWater
        if p.pendingFall > 1.2 && !p.inWater { sfx(.land, min(1, p.pendingFall / 8)) }
        guard p.onGround && !p.flying && !p.inWater else { stepDist = 0.8; return }
        stepDist += simd_length(V2(p.pos.x - before.x, p.pos.z - before.z))
        if stepDist > (p.sprinting ? 2.1 : 1.7) {
            stepDist = 0
            let under = world.block(Int(floor(p.pos.x)), Int(floor(p.pos.y - 0.2)), Int(floor(p.pos.z)))
            if under != AIR { sfx(.step(soundMat(under)), p.sneaking ? 0.4 : 1, at: p.pos) }
        }
    }

    // Hunger, regeneration, starvation, drowning and fall damage (MC-like rules, simplified).
    private func survivalTick(_ dt: Double, from before: V3) {
        hurtFlash = max(0, hurtFlash - Float(dt))
        let fall = player.pendingFall
        player.pendingFall = 0
        guard survival else { air = 15; return }

        if fall > 3.5 && !player.inWater { damage(Int(ceilf(fall - 3.5)), "fell too far") }
        if player.pos.y < -60 { die("fell out of the world"); return }

        let moved = simd_length(V2(player.pos.x - before.x, player.pos.z - before.z))
        exhaustion += moved * (player.sprinting ? 0.1 : (player.inWater ? 0.015 : 0.01))
        if player.jumped { exhaustion += player.sprinting ? 0.2 : 0.05 }
        while exhaustion >= 4 {
            exhaustion -= 4
            if saturation > 0 { saturation = max(0, saturation - 1) } else { hunger = max(0, hunger - 1) }
        }

        if hunger >= 18 && health < 20 {
            regenTimer += dt
            if regenTimer >= 4 { regenTimer = 0; health += 1; exhaustion += 6 }
        } else {
            regenTimer = 0
        }
        if hunger == 0 {
            starveTimer += dt
            if starveTimer >= 4 { starveTimer = 0; if health > 1 { damage(1, "starved") } }
        } else {
            starveTimer = 0
        }

        if player.headInWater {
            air -= Float(dt)
            if air <= 0 {
                air = 0
                drownTimer += dt
                if drownTimer >= 1 { drownTimer = 0; damage(2, "drowned") }
            }
        } else {
            air = min(15, air + Float(dt) * 5)
            drownTimer = 0
        }
    }

    // World clock, fluids and autosave (runs whenever the game isn't paused).
    private func advance(_ dt: Double) {
        fluidTimer += dt
        if fluidTimer >= 0.2 { fluidTimer = 0; world.fluidTick() }
        time += dt
        autosaveTimer += dt
        if autosaveTimer > 60 { autosaveTimer = 0; saveNow() }
    }

    private func tickInventory(_ p: PadSnapshot, _ q: PadSnapshot, _ dt: Double) {
        let items = inventoryItems
        let n = items.count
        let L = HudLayout(screen.x, screen.y)
        var mx = 0, my = 0
        if (p.left && !q.left) || input.tapped(Key.arrowLeft) { mx -= 1 }
        if (p.right && !q.right) || input.tapped(Key.arrowRight) { mx += 1 }
        if (p.up && !q.up) || input.tapped(Key.arrowUp) { my -= 1 }
        if (p.down && !q.down) || input.tapped(Key.arrowDown) { my += 1 }
        // Left stick: one step on push, then auto-repeat while held.
        let ls = stick(p.lx, p.ly)
        var sx = 0, sy = 0
        if max(abs(ls.x), abs(ls.y)) > 0.45 {
            if abs(ls.x) > abs(ls.y) { sx = ls.x > 0 ? 1 : -1 } else { sy = ls.y > 0 ? -1 : 1 }
        }
        if sx != 0 || sy != 0 {
            navTimer -= dt
            if !navHeld || navTimer <= 0 {
                mx += sx; my += sy
                navTimer = navHeld ? 0.11 : 0.32
                navHeld = true
            }
        } else {
            navHeld = false
            navTimer = 0
        }
        if mx != 0 || my != 0 {
            let cols = HudLayout.cols, rows = L.gridRows(n)
            let col = ((invCursor % cols) + mx + cols) % cols
            let row = max(0, min(rows - 1, invCursor / cols + my))
            invCursor = min(n - 1, row * cols + col)
            onToast?(Blocks.name(items[invCursor]))
            sfx(.click, 0.4)
        }
        let m = V2(input.mouseX, input.mouseY)
        if input.mouseMoved, let i = L.gridIndex(at: m, n), i != invCursor {
            invCursor = i
            onToast?(Blocks.name(items[i]))
        }

        for (i, k) in Key.digits.enumerated() where input.tapped(k) { select(i) }
        if input.scrollSteps != 0 { select(selected - input.scrollSteps) }
        if p.rb && !q.rb { select(selected + 1) }
        if p.lb && !q.lb { select(selected - 1) }

        var assign = (p.a && !q.a) || input.tapped(Key.enter)
        if input.leftClicked || input.rightClicked {
            if let i = L.gridIndex(at: m, n) { invCursor = i; assign = true }
            else if let h = L.hotbarIndex(at: m) { select(h) }
        }
        if assign {
            sfx(.click, 0.8)
            hotbar[selected] = items[invCursor]
            onToast?("\(Blocks.name(items[invCursor])) → slot \(selected + 1)")
        }
        if p.b && !q.b { inventoryOpen = false; sfx(.open, 0.5) }
    }
}
