import Foundation
import simd

let DAY_LENGTH: Double = 1200 // seconds per full day/night cycle (20 minutes, like the reference game)

final class Game {
    // The dimension the player is in; other dimensions are kept (unloaded) in `dims`.
    private(set) var dim: DimensionState
    private(set) var dims: [Dim: DimensionState] = [:]
    var world: World { dim.world }
    var mobs: MobManager { dim.mobs }
    var drops: ItemEntityManager { dim.drops }
    var projectiles: ProjectileManager { dim.projectiles }
    var tnts: TNTManager { dim.tnts }
    let player = Player()
    let input = InputState()
    let particles = ParticleManager()
    let inventory = PlayerInventory()
    let save: SaveManager?
    let persistent: Bool

    var time: Double = DAY_LENGTH * 0.06
    var selected: Int {
        get { inventory.selected }
        set { inventory.selected = newValue }
    }
    var paused = true { didSet { if paused != oldValue { onPauseChanged?(paused) } } }
    var showDebug = false
    var target: (hit: IVec3, normal: IVec3)?

    // Open container screen (nil = playing). The carried stack is the one on the cursor.
    var menu: Menu? {
        didSet {
            input.uiMode = menu != nil
            if (menu == nil) != (oldValue == nil) { onInventoryChanged?(menu != nil) }
        }
    }
    var inventoryOpen: Bool { menu != nil }
    var carried = ItemStack.empty
    var menuCursor = 0            // controller cursor (slot index)
    var menuHover: MenuSlot?      // slot under the mouse / controller cursor
    var screen = V2(1280, 800)    // drawable size, updated by the renderer each frame
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
    var alive = true
    var xpLevel = 0
    var xpPoints = 0               // points into the current level
    var sleeping: Float = 0        // > 0 while in bed (seconds)
    var leafQueue: [IVec3] = []
    var placedLeaves = Set<IVec3>()
    var bowCharge: Float = 0
    var portalTime: Float = 0
    var portalCooldown: Float = 0
    var onFire: Float = 0          // seconds the player keeps burning
    var fireDamageTimer: Float = 0
    var dragonKilled = false
    var gateways = 0
    var seenCredits = false
    var credits: Float?            // seconds into the end credits while they are showing
    var dragonSpawnTimer: Float = 3
    var witherTime: Float = 0      // seconds of the wither effect left
    var witherTick: Float = 0
    var eyes: [EnderEye] = []
    var elytraWear: Float = 0
    var bullets: [ShulkerBullet] = []
    var clouds: [AcidCloud] = []
    var contactTimer: Float = 0
    private var lavaTimer: Double = 0
    private var fireTimer: Double = 0
    var walkBob: Float = 0
    var walkAmount: Float = 0
    private var regenTimer: Double = 0
    private var starveTimer: Double = 0
    private var drownTimer: Double = 0
    lazy var spawnPoint: V3 = findSpawn()
    var onModeChanged: ((Bool) -> Void)?

    // Mining / using
    var mining: IVec3?
    var mineProgress: Float = 0       // 0...1
    private var mineSoundTimer: Float = 0
    var eatProgress: Float = 0        // seconds held while eating
    private var attackTimer: Float = 10    // seconds since last attack (attack cooldown)
    var swing: Float = 0              // arm swing animation 1 -> 0

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
    private(set) var clock: Double = 0
    var toastText = ""
    var toastTime: Double = -100
    private var prevPad = PadSnapshot()
    private var autosaveTimer: Double = 0
    private var fluidTimer: Double = 0
    private var tickAccum: Double = 0
    var padConnected = false

    init(world: World, save: SaveManager?, persistent: Bool) {
        dim = DimensionState(dim: world.dim, world: world)
        dims[world.dim] = dim
        self.save = save
        self.persistent = persistent
        onToast = { [weak self] s in
            guard let self else { return }
            self.toastText = s
            self.toastTime = self.clock
        }
        giveCreativeStarter()
        hookWorld(world)
    }

    func giveCreativeStarter() {
        let start = ["grass_block", "dirt", "stone", "cobblestone", "oak_planks", "oak_log", "glass", "torch", "crafting_table"]
        for (i, n) in start.enumerated() where Items.has(n) {
            inventory.main[i] = ItemStack(Items.id(n), 64)
        }
    }

    // MARK: Setup / persistence

    func findSpawn() -> V3 {
        var x = 0, z = 0, dx = 0, dz = -1
        for _ in 0..<4000 {
            let (h, biome) = world.gen.column(x * 16 + 8, z * 16 + 8)
            if h > SEA + 1 && !biome.isOcean && !biome.isRiver && !biome.isPeak && !biome.isBeach {
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
        if let inv = m.inventory {
            for i in 0..<36 { inventory.main[i] = .empty }
            inventory.load(inv)
        }
        selected = max(0, min(8, m.selected))
        world.renderDistance = m.renderDistance
        survival = m.survival ?? false
        health = max(1, min(20, m.health ?? 20))
        hunger = max(0, min(20, m.hunger ?? 20))
        saturation = m.saturation ?? 5
        xpLevel = m.xpLevel ?? 0
        xpPoints = m.xpPoints ?? 0
        if let sp = m.spawn, sp.count == 3 { spawnPoint = V3(sp[0], sp[1], sp[2]) }
        dragonKilled = m.dragonKilled ?? false
        gateways = m.gateways ?? 0
        seenCredits = m.seenCredits ?? false
        if let d = m.dimension, d != .overworld {
            dim = dimensionState(d)
            world.renderDistance = m.renderDistance
        }
    }

    var meta: WorldMeta {
        WorldMeta(seed: world.seed, x: player.pos.x, y: player.pos.y, z: player.pos.z,
                  yaw: player.yaw, pitch: player.pitch, time: time, flying: player.flying,
                  hotbar: nil, inventory: inventory.saved, dimension: dim.dim, spawn: [spawnPoint.x, spawnPoint.y, spawnPoint.z],
                  xpLevel: xpLevel, xpPoints: xpPoints, selected: selected, renderDistance: world.renderDistance,
                  survival: survival, health: health, hunger: hunger, saturation: saturation,
                  dragonKilled: dragonKilled, gateways: gateways, seenCredits: seenCredits)
    }

    func saveNow() {
        guard persistent, let s = save else { return }
        world.saveAll()
        s.saveMeta(meta)
    }

    // MARK: Dimensions

    func dimensionState(_ d: Dim) -> DimensionState {
        if let s = dims[d] { return s }
        let base = (dims[.overworld] ?? dim).world
        let sv = d.folder.flatMap { f in save.map { $0.sub(f) } }
        let w = World(seed: base.seed, device: base.device, save: sv, dim: d)
        w.renderDistance = base.renderDistance
        let s = DimensionState(dim: d, world: w)
        dims[d] = s
        hookWorld(w)
        return s
    }

    func hookWorld(_ w: World) {
        w.onFluidEvent = { [weak self] p in self?.sfx(.fizz, 0.8, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5) }
        w.onIgnite = { [weak self] p, b in
            guard let self else { return }
            if Blocks.key(b) == "tnt" { self.world.setBlockAsync(p.x, p.y, p.z, AIR); self.tnts.prime(at: p) }
        }
    }

    // Moves the player to another dimension (saving and unloading the one we leave).
    func changeDimension(to d: Dim, at p: V3) {
        let old = world
        if persistent { old.saveAll() }
        let rd = old.renderDistance
        dim = dimensionState(d)
        world.renderDistance = rd
        old.unloadAll()
        particles.list.removeAll()
        player.pos = p
        player.vel = .zero
        player.airPeak = p.y
        _ = world.loadSync(center: p, radius: min(4, rd))
        onToast?(d.displayName)
    }

    // MARK: Sky

    var dayFraction: Double { (time.truncatingRemainder(dividingBy: DAY_LENGTH)) / DAY_LENGTH }

    // Sun rises in +X at fraction 0, peaks at 0.25, sets at 0.5.
    var sunDir: V3 {
        let a = Float(dayFraction * 2 * .pi)
        return simd_normalize(V3(cosf(a), sinf(a), 0.35))
    }

    var daylight: Float {
        if !dim.dim.hasSky { return dim.dim == .end ? 0.75 : 1 }
        let s = sunDir.y
        let t = simd_clamp((s + 0.12) / 0.4, 0, 1)
        return 0.12 + 0.88 * t * t * (3 - 2 * t)
    }

    var skyColor: V3 {
        if !dim.dim.hasSky { return dim.dim.fogColor }
        let day = V3(0.52, 0.72, 0.96), night = V3(0.015, 0.02, 0.06)
        var c = simd_mix(night, day, V3(repeating: (daylight - 0.12) / 0.88))
        let s = sunDir.y
        let dusk = max(0, 1 - abs(s - 0.02) / 0.22)
        c = simd_mix(c, V3(0.95, 0.5, 0.28), V3(repeating: dusk * 0.45))
        return c
    }

    // MARK: Hotbar / items

    var held: ItemStack { inventory.held }

    func select(_ i: Int) {
        let n = (i % 9 + 9) % 9
        if n != selected { eatProgress = 0; mining = nil }
        selected = n
        let h = held
        if !h.isEmpty { onToast?(h.def.display) }
    }

    func dropItem(_ s: ItemStack, thrown: Bool = true) {
        if s.isEmpty { return }
        let dir = player.look
        let p = player.eye - V3(0, 0.3, 0)
        drops.spawn(s, at: p, vel: thrown ? dir * 6 + V3(0, 1, 0) : V3(0, 1, 0), delay: 2)
    }

    func dropHeld(all: Bool) {
        var h = held
        if h.isEmpty { return }
        let n = all ? h.count : 1
        dropItem(ItemStack(h.item, n, damage: h.damage))
        h.count -= n
        inventory.held = h.count > 0 ? h : .empty
    }

    // Uses up durability of the held tool; breaks it when worn out.
    func damageHeld(_ amount: Int) {
        guard survival else { return }
        var h = held
        guard !h.isEmpty, h.def.durability > 0 else { return }
        h.damage += amount
        if h.damage >= h.def.durability {
            inventory.held = .empty
            sfx(.breakBlock(.glass), 0.5)
            onToast?("\(h.def.display) broke")
        } else {
            inventory.held = h
        }
    }

    func consumeHeld() {
        guard survival else { return }
        var h = held
        h.count -= 1
        inventory.held = h.count > 0 ? h : .empty
    }

    func pickBlock() {
        guard let t = target else { return }
        let b = world.block(t.hit.x, t.hit.y, t.hit.z)
        guard let it = Items.item(forBlock: b) else { return }
        if let i = (0..<9).first(where: { inventory.main[$0].item == it }) { select(i); return }
        guard !survival else { return }
        let slot = (0..<9).first(where: { inventory.main[$0].isEmpty }) ?? selected
        inventory.main[slot] = ItemStack(it, Items.def(it).maxStack)
        select(slot)
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

    // MARK: Menus

    func openMenu(_ m: Menu) {
        menu = m
        menuCursor = m.slots.firstIndex(where: { $0.isHotbar && $0.index == selected }) ?? 0
        sfx(.open, 0.6)
    }

    func closeMenu() {
        guard let m = menu else { return }
        m.onClose()
        if !carried.isEmpty {
            let rest = inventory.add(carried)
            if !rest.isEmpty { dropItem(rest) }
            carried = .empty
        }
        menu = nil
        sfx(.open, 0.5)
    }

    func openInventory() {
        openMenu(survival ? InventoryMenu(game: self) : CreativeMenu(game: self))
    }

    private func tickMenu(_ p: PadSnapshot, _ q: PadSnapshot, _ dt: Double) {
        guard let m = menu else { return }
        let L = HudLayout(screen.x, screen.y)
        var mx = 0, my = 0
        if (p.left && !q.left) || input.tapped(Key.arrowLeft) { mx -= 1 }
        if (p.right && !q.right) || input.tapped(Key.arrowRight) { mx += 1 }
        if (p.up && !q.up) || input.tapped(Key.arrowUp) { my -= 1 }
        if (p.down && !q.down) || input.tapped(Key.arrowDown) { my += 1 }
        let ls = stick(p.lx, p.ly)
        var sx = 0, sy = 0
        if max(abs(ls.x), abs(ls.y)) > 0.45 {
            if abs(ls.x) > abs(ls.y) { sx = ls.x > 0 ? 1 : -1 } else { sy = ls.y > 0 ? -1 : 1 }
        }
        if sx != 0 || sy != 0 {
            navTimer -= dt
            if !navHeld || navTimer <= 0 {
                mx += sx; my += sy
                navTimer = navHeld ? 0.1 : 0.3
                navHeld = true
            }
        } else {
            navHeld = false
            navTimer = 0
        }
        let creative = m as? CreativeMenu
        var padMoved = false
        if mx != 0 || my != 0 {
            let before = menuCursor
            menuCursor = m.neighbour(of: menuCursor, dx: mx, dy: my)
            // Scroll the creative palette when pushing past its top/bottom row.
            if let c = creative, menuCursor == before, my != 0, before < c.rows * 9 { c.scrollBy(my) }
            padMoved = true
            sfx(.click, 0.3)
        }
        let rs = stick(p.rx, p.ry)
        if let c = creative {
            if input.scrollSteps != 0 { c.scrollBy(-input.scrollSteps) }
            if abs(rs.y) > 0.5 && (!navHeld || navTimer <= 0.05) { c.scrollBy(rs.y > 0 ? -1 : 1) }
        }
        let mouse = V2(input.mouseX, input.mouseY)
        if input.mouseMoved, let s = m.slotAt(mouse, L), let i = m.slots.firstIndex(where: { $0 === s }) { menuCursor = i }
        menuHover = menuCursor < m.slots.count ? m.slots[menuCursor] : nil
        if padMoved { input.mouseX = -1 }

        let shift = input.shift
        if input.leftClicked || input.rightClicked {
            let b = input.leftClicked ? 0 : 1
            if let s = m.slotAt(mouse, L) { m.click(s, button: b, shift: shift) }
            else if !m.inside(mouse, L) && !carried.isEmpty {
                if b == 0 { dropItem(carried); carried = .empty }
                else { dropItem(ItemStack(carried.item, 1, damage: carried.damage)); carried.count -= 1; if carried.count <= 0 { carried = .empty } }
            }
        }
        if let s = menuHover {
            if p.a && !q.a { m.click(s, button: 0, shift: false) }
            if p.x && !q.x { m.click(s, button: 1, shift: false) }
            if p.y && !q.y { m.click(s, button: 0, shift: true) }
            // Number keys swap the hovered slot with a hotbar slot.
            for (i, k) in Key.digits.enumerated() where input.tapped(k) {
                if case .normal = s.kind, s.container != nil {
                    let a = s.stack
                    s.stack = inventory.main[i]
                    inventory.main[i] = a
                    m.changed()
                }
            }
        }
        if input.tapped(Key.e) || input.tapped(Key.esc) || (p.b && !q.b) || (p.view && !q.view) { closeMenu() }
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
        swing = max(0, swing - fdt * 4)
        attackTimer += fdt

        if let c = credits {
            // End credits: scroll; any key, click or A/B skips.
            credits = c + fdt
            let skip = c > 1 && (input.tapped(Key.esc) || input.tapped(Key.space) || input.leftClicked || (p.a && !q.a) || (p.b && !q.b))
            if skip || c + fdt > Game.creditsLength { returnFromEnd() }
            return
        }

        if menu != nil {
            tickMenu(p, q, dt)
            let before = player.pos
            player.update(dt: fdt, input: MoveInput(), world: world)
            survivalTick(dt, from: before)
            target = nil
            mining = nil
            advance(dt)
            return
        }
        if input.tapped(Key.e) || (p.view && !q.view) || (p.y && !q.y) { openInventory(); return }

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
        mi.sprint = player.sprinting && (mi.forward > 0.3) && !(survival && hunger <= 6) && eatProgress == 0
        if mi.forward <= 0.3 { player.sprinting = false }
        if eatProgress > 0 { mi.forward *= 0.3; mi.strafe *= 0.3 }

        if input.tapped(Key.space) || (p.a && !q.a) {
            let chest = inventory.armor[1]
            let hasElytra = !chest.isEmpty && Items.key(chest.item) == "elytra" && chest.damage < chest.def.durability - 1
            if hasElytra && !player.onGround && !player.flying && !player.inWater && !player.gliding {
                player.gliding = true
            } else if clock - lastSpaceTap < 0.3 { toggleFly(); lastSpaceTap = -1 } else { lastSpaceTap = clock }
        }
        if player.gliding {
            // Elytra wear: 1 durability per second of flight; breaks at 1 left like the reference game.
            elytraWear += fdt
            if elytraWear >= 1 && survival {
                elytraWear = 0
                var c = inventory.armor[1]
                if !c.isEmpty { c.damage += 1; inventory.armor[1] = c; if c.damage >= c.def.durability - 1 { player.gliding = false } }
            }
        }
        if player.impact > 0 {
            if player.impact >= 1 { damage(Int(player.impact), "experienced kinetic energy") }
            player.impact = 0
        }
        if input.tapped(Key.f) || (p.up && !q.up) { toggleFly() }
        if input.tapped(Key.f3) { showDebug.toggle() }
        if input.tapped(Key.q) || (p.down && !q.down) { dropHeld(all: input.control) }

        // Hotbar
        for (i, k) in Key.digits.enumerated() where input.tapped(k) { select(i) }
        if input.scrollSteps != 0 { select(selected - input.scrollSteps) }
        if p.rb && !q.rb { select(selected + 1) }
        if p.lb && !q.lb { select(selected - 1) }

        let before = player.pos
        player.update(dt: fdt, input: mi, world: world)
        let hmove = simd_length(V2(player.pos.x - before.x, player.pos.z - before.z))
        walkBob += hmove * 2.2
        walkAmount += ((player.onGround && !player.flying ? min(1, hmove / fdt / 4) : 0) - walkAmount) * min(1, fdt * 8)
        audioTick(from: before)
        survivalTick(dt, from: before)

        interact(p, q, dt)
        if input.middleClicked || (p.x && !q.x) { pickBlock() }

        advance(dt)
    }

    // MARK: Interaction (attack, mine, use)

    private func interact(_ p: PadSnapshot, _ q: PadSnapshot, _ dt: Double) {
        let fdt = Float(dt)
        let reach: Float = survival ? 4.5 : 5
        target = world.raycast(player.eye, player.look, maxDist: reach)
        breakCooldown -= dt
        placeCooldown -= dt
        let breakHeld = input.leftDown || p.rt > 0.5
        let breakNow = input.leftClicked || (p.rt > 0.5 && q.rt <= 0.5)
        let useHeld = input.rightDown || p.lt > 0.5
        let useNow = input.rightClicked || (p.lt > 0.5 && q.lt <= 0.5)

        // Attack: an animal in front of the block takes priority.
        var mobHit: Mob?
        if let hit = mobs.raycast(player.eye, player.look, maxDist: 3.5) {
            let (m, dist) = hit
            if let t = target {
                let c = V3(Float(t.hit.x), Float(t.hit.y), Float(t.hit.z)) + 0.5
                if dist < simd_length(c - player.eye) - 0.4 { mobHit = m }
            } else {
                mobHit = m
            }
        }
        if breakNow { swing = 1 }
        if breakNow && (projectiles.deflect(from: player.eye, look: player.look) || punchBullet()) { attackTimer = 0; sfx(.attack, 0.7); return }
        if let m = mobHit {
            mining = nil
            if useNow && useItemOnMob(m) { swing = 1; return }
            if breakNow {
                // Attack cooldown: damage scales with how charged the swing is.
                let spd = held.isEmpty ? 4 : held.def.attackSpeed
                let charge = min(1, attackTimer * spd)
                let base = held.isEmpty ? 1 : held.def.attack
                var dmg = base * (0.2 + 0.8 * charge * charge)
                let crit = charge > 0.9 && player.vel.y < -0.5 && !player.onGround
                if crit { dmg *= 1.5 }
                attackTimer = 0
                m.hit(from: player.pos, damage: max(1, Int(dmg.rounded())), knockback: player.sprinting ? 1.6 : 1)
                m.provoke(self)
                m.killedByPlayer = true
                if crit { particles.crit(at: m.pos + V3(0, m.height * 0.7, 0)) }
                sfx(.attack, 0.7, at: m.pos)
                sfx(m.kind.call, 0.9, at: m.pos + V3(0, m.height * 0.8, 0))
                if m.health <= 0 { sfx(.breakBlock(.plant), 0.8, at: m.pos) }
                if survival { exhaustion += 0.1 }
                damageHeld(held.def.tool == .sword ? 1 : 2)
            }
            return
        }

        // Mining
        if let t = target, breakHeld {
            let b = world.block(t.hit.x, t.hit.y, t.hit.z)
            if !survival {
                if breakNow || breakCooldown <= 0 {
                    breakBlock(t.hit, b, drop: false)
                    breakCooldown = 0.3
                }
            } else {
                if mining != t.hit { mining = t.hit; mineProgress = 0 }
                let secs = Mining.breakSeconds(b, held, onGround: player.onGround || player.flying, inWater: player.headInWater)
                if secs.isInfinite {
                    mineProgress = 0
                } else {
                    mineProgress += secs <= 0 ? 1 : fdt / secs
                    swing = max(swing, 0.5)
                    mineSoundTimer -= fdt
                    if mineSoundTimer <= 0 { mineSoundTimer = 0.25; sfx(.step(soundMat(b)), 0.5, at: V3(Float(t.hit.x), Float(t.hit.y), Float(t.hit.z)) + 0.5) }
                    if mineProgress >= 1 && breakCooldown <= 0 {
                        breakBlock(t.hit, b, drop: true)
                        damageHeld(held.def.tool == .sword ? 2 : 1)
                        mining = nil
                        mineProgress = 0
                        breakCooldown = secs <= 0 ? 0 : 0.3
                    }
                }
            }
        } else {
            mining = nil
            mineProgress = 0
        }

        // Use
        let h = held
        if useNow, let m = mobHit ?? mobs.raycast(player.eye, player.look, maxDist: 3.5)?.0, useItemOnMob(m) { swing = 1; return }
        if useNow && Items.key(h.item) == "ender_eye" && useEnderEye(on: target) { swing = 1; return }
        if useNow && Items.key(h.item) == "firework_rocket" && player.gliding {
            player.boost = 1.1
            consumeHeld()
            sfx(.fireball, 0.5)
            swing = 1
            return
        }
        // Bow: hold to draw, release to shoot.
        if Items.key(h.item) == "bow" {
            let hasArrow = !survival || inventory.main.countOf(Items.id("arrow")) > 0
            if useHeld && hasArrow { bowCharge += fdt; return }
            if !useHeld && bowCharge > 0 {
                let t = bowCharge * 20
                let f = min(1, (t * t / 400 + t / 10) / 3)
                bowCharge = 0
                if f >= 0.1 {
                    projectiles.shoot(from: player.eye, dir: player.look, speed: f * 60, fromPlayer: true, damage: 2)
                    sfx(.bow, 0.8)
                    if survival { inventory.main.remove(Items.id("arrow"), 1) }
                    damageHeld(1)
                }
                return
            }
        } else {
            bowCharge = 0
        }
        if let f = h.def.food, useHeld && survival && (hunger < 20 || h.item == Items.id("golden_apple") || h.item == Items.id("chorus_fruit")) && target.map({ !isInteractive($0.hit) }) ?? true {
            eatProgress += fdt
            if Int(eatProgress * 5) != Int((eatProgress - fdt) * 5) { sfx(.eat, 0.5) }
            if eatProgress >= 1.61 {
                eat(f, h.def.display)
                consumeHeld()
                if h.item == Items.id("mushroom_stew") || h.item == Items.id("beetroot_soup") { inventory.held = ItemStack(Items.id("bowl"), 1) }
                eatProgress = 0
            }
            return
        }
        eatProgress = 0
        guard useNow || (useHeld && placeCooldown <= 0) else { return }
        placeCooldown = 0.25
        if useBucket() { return }
        guard let t = target else { return }
        if isInteractive(t.hit) && !(input.shift || p.b) && useNow {
            openBlock(t.hit)
            return
        }
        if useNow && useItemOnBlock(t) { return }
        guard let blockItem = h.def.block else { return }
        let clicked = world.block(t.hit.x, t.hit.y, t.hit.z)
        // Slabs: clicking a matching half slab from the open side makes a double slab.
        if Blocks.shape[Int(blockItem)] == "slab" {
            let cb = Blocks.groupBase[Int(clicked)]
            let part = Int(clicked) - Int(cb)
            if cb == blockItem && ((part == 0 && t.normal.y == 1) || (part == 1 && t.normal.y == -1)) {
                world.setBlock(t.hit.x, t.hit.y, t.hit.z, blockItem + 2)
                sfx(.place(soundMat(blockItem)), at: V3(Float(t.hit.x), Float(t.hit.y), Float(t.hit.z)) + 0.5)
                consumeHeld(); swing = 1
                return
            }
            let nb = t.hit + t.normal
            let nbb = world.block(nb.x, nb.y, nb.z)
            if Blocks.groupBase[Int(nbb)] == blockItem && Int(nbb) - Int(blockItem) < 2 {
                world.setBlock(nb.x, nb.y, nb.z, blockItem + 2)
                consumeHeld(); swing = 1
                return
            }
        }
        let at = Blocks.replaceable[Int(clicked)] && !Blocks.isLiquid(clicked) ? t.hit : t.hit + t.normal
        let existing = world.block(at.x, at.y, at.z)
        guard Blocks.replaceable[Int(existing)], at.y >= 0, at.y < CH else { return }
        var id = blockItem
        let key = Blocks.key(blockItem)
        if key.hasSuffix("_bed") {
            if useNow && placeBed(h.def, at: at) { sfx(.place(.wood), 1); consumeHeld(); swing = 1 }
            return
        }
        if key == "furnace" || key == "chest" {
            id = blockItem + BlockID(BlockRegistry.facingToward(yaw: player.yaw))
        }
        let fracY = hitPoint(t).y - Float(t.hit.y)
        let upperHalf = t.normal.y == -1 || (t.normal.y == 0 && fracY > 0.5)
        switch Blocks.shape[Int(blockItem)] {
        case "stairs": id = blockItem + BlockID((upperHalf ? 4 : 0) + (BlockRegistry.facingToward(yaw: player.yaw) ^ 1))
        case "slab": id = blockItem + (upperHalf ? 1 : 0)
        default: break
        }
        let supported: Bool
        if id == TORCH {
            supported = Blocks.opaque[Int(world.block(at.x, at.y - 1, at.z))]
                || [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)].contains { d in Blocks.opaque[Int(world.block(at.x + d.x, at.y, at.z + d.z))] }
        } else if Blocks.isPlant(id) {
            let below = world.block(at.x, at.y - 1, at.z)
            supported = below == GRASS || below == DIRT || Blocks.key(below) == "farmland" || Blocks.key(below) == "snowy_grass_block"
        } else {
            supported = true
        }
        let solid = Blocks.collide[Int(id)]
        if supported && !(solid && player.intersectsBlock(at)) && !(solid && mobs.mobs.contains { $0.intersects(at) }) {
            world.setBlock(at.x, at.y, at.z, id)
            if key == "furnace" { world.blockEntities[at] = BlockEntity(.furnace) }
            if key == "chest" { world.blockEntities[at] = BlockEntity(.chest) }
            if key.hasSuffix("leaves") { placedLeaves.insert(at) }
            sfx(.place(soundMat(id)), at: V3(Float(at.x), Float(at.y), Float(at.z)) + 0.5)
            swing = 1
            consumeHeld()
        }
    }

    // Exact point where the look ray meets the targeted face.
    func hitPoint(_ t: (hit: IVec3, normal: IVec3)) -> V3 {
        let o = player.eye, d = player.look
        let bmin = V3(Float(t.hit.x), Float(t.hit.y), Float(t.hit.z))
        var best: Float = .greatestFiniteMagnitude
        for (mn, mx) in world.selectionBoxes(world.block(t.hit.x, t.hit.y, t.hit.z)) {
            if let h = World.rayBox(o, d, bmin + mn, bmin + mx) { best = min(best, h.0) }
        }
        if best == .greatestFiniteMagnitude { return bmin + 0.5 }
        return o + d * best
    }

    func isInteractive(_ p: IVec3) -> Bool {
        let k = Blocks.key(Blocks.groupBase[Int(world.block(p.x, p.y, p.z))])
        return k == "crafting_table" || k == "furnace" || k == "lit_furnace" || k == "chest"
    }

    func openBlock(_ p: IVec3) {
        let k = Blocks.key(Blocks.groupBase[Int(world.block(p.x, p.y, p.z))])
        switch k {
        case "crafting_table": openMenu(CraftingTableMenu(game: self))
        case "furnace", "lit_furnace":
            let be = world.blockEntities[p] ?? BlockEntity(.furnace)
            world.blockEntities[p] = be
            openMenu(FurnaceMenu(game: self, entity: be))
        case "chest":
            let be = world.blockEntities[p] ?? BlockEntity(.chest)
            world.blockEntities[p] = be
            openMenu(ChestMenu(game: self, entity: be))
        default: break
        }
    }

    func breakBlock(_ p: IVec3, _ b: BlockID, drop: Bool) {
        sfx(.breakBlock(soundMat(b)), at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5)
        particles.blockBreak(b, at: p)
        world.setBlock(p.x, p.y, p.z, AIR)
        breakBedPartner(p, b)
        if b == OBSIDIAN || b == PORTAL_X || b == PORTAL_Z { breakPortal(near: p) }
        placedLeaves.remove(p)
        let bk = Blocks.key(b)
        if bk.hasSuffix("_log") || bk.hasSuffix("_wood") { queueLeafDecay(around: p) }
        if drop {
            let ores: [String: ClosedRange<Int>] = ["coal_ore": 0...2, "deepslate_coal_ore": 0...2, "diamond_ore": 3...7, "deepslate_diamond_ore": 3...7,
                                                     "emerald_ore": 3...7, "lapis_ore": 2...5, "deepslate_lapis_ore": 2...5,
                                                     "redstone_ore": 1...5, "deepslate_redstone_ore": 1...5,
                                                     "nether_quartz_ore": 2...5, "nether_gold_ore": 0...1, "spawner": 15...43]
            if let r = ores[bk], Mining.canHarvest(b, held) { addXP(Int.random(in: r)) }
        }
        let center = V3(Float(p.x) + 0.5, Float(p.y) + 0.3, Float(p.z) + 0.5)
        if bk.hasPrefix("infested_") && survival { mobs.mobs.append(Mob(.silverfish, at: center)) }
        if bk == "chorus_plant" || bk == "chorus_flower" {
            // Chorus plants collapse above a broken stem.
            var y = p.y + 1
            while y < CH, ["chorus_plant", "chorus_flower"].contains(Blocks.key(world.block(p.x, y, p.z))) {
                let above = world.block(p.x, y, p.z)
                world.setBlockAsync(p.x, y, p.z, AIR)
                if drop { for s in Mining.drops(above, .empty) { drops.spawn(s, at: V3(Float(p.x) + 0.5, Float(y) + 0.3, Float(p.z) + 0.5)) } }
                y += 1
            }
        }
        if let be = world.blockEntities.removeValue(forKey: p) {
            for s in be.container.slots where !s.isEmpty { drops.spawn(s, at: center) }
        }
        if drop {
            for s in Mining.drops(b, held) { drops.spawn(s, at: center, vel: V3(Float.random(in: -1...1), 2, Float.random(in: -1...1)), delay: 0.5) }
            exhaustion += 0.005
        }
        // Plants can't float: pop the one standing on the broken block.
        let above = world.block(p.x, p.y + 1, p.z)
        if Blocks.isPlant(above) || above == TORCH {
            world.setBlock(p.x, p.y + 1, p.z, AIR)
            if drop { for s in Mining.drops(above, .empty) { drops.spawn(s, at: center + V3(0, 1, 0)) } }
        }
    }

    // Buckets: pick up a water or lava source / pour it out.
    private func useBucket() -> Bool {
        let k = Items.key(held.item)
        guard k == "bucket" || k == "water_bucket" || k == "lava_bucket" else { return false }
        var fluidHit: IVec3?
        var lastAir: IVec3?
        let dir = player.look
        var t: Float = 0
        while t < 5 {
            let q = player.eye + dir * t
            let c = IVec3(Int(floor(q.x)), Int(floor(q.y)), Int(floor(q.z)))
            let b = world.block(c.x, c.y, c.z)
            if Blocks.fluidLevel[Int(b)] == 0 { fluidHit = c; break }
            if Blocks.targetable(b) { break }
            lastAir = c
            t += 0.05
        }
        if k == "bucket", let f = fluidHit {
            let lava = Blocks.fluidKind[Int(world.block(f.x, f.y, f.z))] == 2
            world.setBlock(f.x, f.y, f.z, AIR)
            sfx(lava ? .fizz : .splash, 0.4)
            if survival {
                consumeHeld()
                let rest = inventory.add(ItemStack(Items.id(lava ? "lava_bucket" : "water_bucket"), 1))
                if !rest.isEmpty { dropItem(rest) }
            }
            return true
        }
        if k == "water_bucket" || k == "lava_bucket" {
            var at: IVec3?
            if let tg = target { at = tg.hit + tg.normal } else if fluidHit == nil { at = lastAir }
            if let a = at, Blocks.replaceable[Int(world.block(a.x, a.y, a.z))] {
                if k == "water_bucket" && dim.dim == .nether {
                    sfx(.fizz, 0.8)          // water evaporates in the Nether
                } else {
                    world.setBlock(a.x, a.y, a.z, k == "water_bucket" ? WATER : LAVA)
                    sfx(.splash, 0.4)
                }
                if survival { inventory.held = ItemStack(Items.id("bucket"), 1) }
            }
            return true
        }
        return false
    }

    func mobDied(_ m: Mob) {
        let at = m.pos + V3(0, 0.5, 0)
        if !m.baby {
            for (n, lo, hi) in m.spec.drops where Items.has(n) {
                let c = Int.random(in: lo...hi)
                var item = Items.id(n)
                if m.fire > 0, let cooked = Recipes.smelt(item), Items.def(item).food != nil { item = cooked }
                if c > 0 { drops.spawn(ItemStack(item, c), at: at) }
            }
            if m.kind == .sheep && !m.sheared, Items.has("\(m.woolColor)_wool") { drops.spawn(ItemStack(Items.id("\(m.woolColor)_wool"), 1), at: at) }
            if m.kind == .zombie && Float.random(in: 0..<1) < 0.025 {
                drops.spawn(ItemStack(Items.id(["iron_ingot", "carrot", "potato"][Int.random(in: 0...2)]), 1), at: at)
            }
            let r = Float.random(in: 0..<1)
            if m.kind == .blaze && m.killedByPlayer && r < 0.5 { drops.spawn(ItemStack(Items.id("blaze_rod"), 1), at: at) }
            if m.kind == .magmaCube && m.slimeSize > 1 && r < 0.25 { drops.spawn(ItemStack(Items.id("magma_cream"), 1), at: at) }
            if m.kind == .zombifiedPiglin && m.killedByPlayer && r < 0.025 { drops.spawn(ItemStack(Items.id("gold_ingot"), 1), at: at) }
            if m.kind == .witherSkeleton && m.killedByPlayer && r < 0.025, Items.has("wither_skeleton_skull") {
                drops.spawn(ItemStack(Items.id("wither_skeleton_skull"), 1), at: at)
            }
        }
        let xp = m.sized ? m.slimeSize : m.spec.xp
        if m.killedByPlayer && !m.baby { addXP(xp + (m.kind.hostile ? 0 : Int.random(in: 0...1))) }
        particles.explosion(at: m.pos + V3(0, m.height / 2, 0), power: 0.5)
    }

    // MARK: Survival

    // Monster spawners: active with a player within 16 blocks; every 10-40 s up to 4 mobs of the
    // spawner's kind appear within ±4 blocks, unless 6 of that kind are already near.
    func spawnerTick(_ dt: Float) {
        let pp = player.pos
        for (p, be) in world.blockEntities where be.kind == .spawner {
            let c = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)
            guard simd_length(c - pp) < 16, let kind = MobKind.named(be.mob) else { continue }
            if Float.random(in: 0..<1) < 0.3 { particles.flame(at: c + V3(Float.random(in: -0.5...0.5), Float.random(in: -0.5...0.5), Float.random(in: -0.5...0.5))) }
            be.delay -= dt
            guard be.delay <= 0 else { continue }
            be.delay = Float.random(in: 10...40)
            var near = mobs.mobs.filter { $0.kind == kind && abs($0.pos.x - c.x) < 4.5 && abs($0.pos.y - c.y) < 2.5 && abs($0.pos.z - c.z) < 4.5 }.count
            for _ in 0..<4 where near < 6 {
                let sp = V3(c.x + Float.random(in: -4...4), Float(p.y + Int.random(in: -1...1)), c.z + Float.random(in: -4...4))
                let bx = Int(floor(sp.x)), by = Int(floor(sp.y)), bz = Int(floor(sp.z))
                guard Blocks.collide[Int(world.block(bx, by - 1, bz))] else { continue }
                // Hostile mobs from spawners need block light ≤ 11 (blazes and silverfish ignore it in practice).
                if kind != .blaze && world.lightAt(bx, by, bz).block > 11 { continue }
                let m = Mob(kind, at: V3(Float(bx) + 0.5, sp.y, Float(bz) + 0.5))
                if m.sized { m.makeSlime(size: 1) }
                if m.collides(m.pos, world) { continue }
                mobs.mobs.append(m)
                near += 1
                particles.explosion(at: m.pos + V3(0, 0.5, 0), power: 0.3)
            }
        }
    }

    // MARK: XP (reference level curve)

    static func xpToNext(_ level: Int) -> Int { level < 16 ? 2 * level + 7 : (level < 31 ? 5 * level - 38 : 9 * level - 158) }

    func addXP(_ n: Int) {
        guard n > 0 else { return }
        xpPoints += n
        var leveled = false
        while xpPoints >= Game.xpToNext(xpLevel) { xpPoints -= Game.xpToNext(xpLevel); xpLevel += 1; leveled = true }
        sfx(leveled && xpLevel % 5 == 0 ? .levelUp : .xp, 0.5)
    }

    // Mob hits on the player: armor-reduced damage plus knockback away from the attacker.
    func hurtPlayer(_ amount: Int, from src: V3, cause: String, knockback: Float = 1) {
        guard survival, alive, amount > 0 else { return }
        damage(amount, cause)
        if knockback > 0 {
            var d = player.pos - src
            d.y = 0
            let l = simd_length(d)
            if l > 0.01 { player.vel += d / l * 6 * knockback + V3(0, 4 * knockback, 0) }
        }
    }

    func toggleMode() {
        survival.toggle()
        onToast?(survival ? "Survival mode" : "Creative mode")
    }

    func eat(_ f: FoodInfo, _ name: String) {
        sfx(.burp, 0.6)
        hunger = min(20, hunger + f.hunger)
        saturation = min(Float(hunger), saturation + f.saturation)
        if name == "Chorus Fruit" { chorusTeleport() }
    }

    // Chorus fruit: up to 16 tries at a random spot within 8 blocks with ground and room to stand.
    func chorusTeleport() {
        let p = player.pos
        for _ in 0..<16 {
            let x = Int(floor(p.x)) + Int.random(in: -8...8), z = Int(floor(p.z)) + Int.random(in: -8...8)
            var y = min(CH - 3, Int(floor(p.y)) + 8)
            while y > max(1, Int(floor(p.y)) - 8) && !Blocks.collide[Int(world.block(x, y - 1, z))] { y -= 1 }
            let t = V3(Float(x) + 0.5, Float(y), Float(z) + 0.5)
            if Blocks.collide[Int(world.block(x, y - 1, z))] && !player.collides(at: t, world) && !Blocks.isLiquid(world.block(x, y, z)) {
                player.pos = t
                player.vel = .zero
                player.airPeak = t.y
                sfx(.mobEnderman, 0.6)
                return
            }
        }
    }

    // Damage in half-hearts, reduced by armor (reference formula).
    func damage(_ amount: Int, _ cause: String, bypassArmor: Bool = false) {
        guard survival, alive, amount > 0 else { return }
        var dmg = Float(amount)
        if !bypassArmor {
            let a = Float(inventory.armorPoints), tough = inventory.toughness
            let eff = min(20, max(a / 5, a - dmg / (2 + tough / 4)))
            dmg *= 1 - eff / 25
            for i in 0..<4 where !inventory.armor[i].isEmpty {
                var s = inventory.armor[i]
                s.damage += max(1, amount / 4)
                inventory.armor[i] = s.damage >= s.def.durability ? .empty : s
            }
        }
        health -= max(1, Int(dmg.rounded()))
        hurtFlash = 0.35
        sfx(.hurt)
        if health <= 0 { die(cause) }
    }

    func die(_ cause: String) {
        onToast?("You \(cause)")
        // Drop everything where we died.
        let at = player.pos + V3(0, 1, 0)
        for c in [inventory.main, inventory.armor, inventory.offhand] {
            for i in 0..<c.count where !c[i].isEmpty {
                drops.spawn(c[i], at: at, vel: V3(Float.random(in: -2...2), Float.random(in: 1...4), Float.random(in: -2...2)), delay: 1)
                c[i] = .empty
            }
        }
        if dim.dim != .overworld { changeDimension(to: .overworld, at: spawnPoint) }
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

    // Hunger, regeneration, starvation, drowning and fall damage.
    private func survivalTick(_ dt: Double, from before: V3) {
        hurtFlash = max(0, hurtFlash - Float(dt))
        let fall = player.pendingFall
        player.pendingFall = 0
        guard survival else { air = 15; return }

        if fall > 3.5 && !player.inWater { damage(Int(ceilf(fall - 3.5)), "fell from a high place", bypassArmor: true) }
        if player.pos.y < -60 { die("fell out of the world"); return }

        let moved = simd_length(V2(player.pos.x - before.x, player.pos.z - before.z))
        exhaustion += moved * (player.sprinting ? 0.1 : (player.inWater ? 0.01 : 0))
        if player.jumped { exhaustion += player.sprinting ? 0.2 : 0.05 }
        while exhaustion >= 4 {
            exhaustion -= 4
            if saturation > 0 { saturation = max(0, saturation - 1) } else { hunger = max(0, hunger - 1) }
        }

        // Fast regen with full hunger and saturation, slow regen at hunger >= 18.
        if hunger >= 20 && saturation > 0 && health < 20 {
            regenTimer += dt
            if regenTimer >= 0.5 { regenTimer = 0; health += 1; exhaustion += 6 }
        } else if hunger >= 18 && health < 20 {
            regenTimer += dt
            if regenTimer >= 4 { regenTimer = 0; health += 1; exhaustion += 6 }
        } else {
            regenTimer = 0
        }
        if hunger == 0 {
            starveTimer += dt
            if starveTimer >= 4 { starveTimer = 0; if health > 1 { damage(1, "starved to death", bypassArmor: true) } }
        } else {
            starveTimer = 0
        }

        if player.headInWater {
            air -= Float(dt)
            if air <= 0 {
                air = 0
                drownTimer += dt
                if drownTimer >= 1 { drownTimer = 0; damage(2, "drowned", bypassArmor: true) }
            }
        } else {
            air = min(15, air + Float(dt) * 5)
            drownTimer = 0
        }
    }

    // World clock, fluids, furnaces, entities and autosave (runs whenever the game isn't paused).
    private func advance(_ dt: Double) {
        mobs.update(Float(dt), game: self)
        drops.update(Float(dt), game: self)
        projectiles.update(Float(dt), game: self)
        tnts.update(Float(dt), game: self)
        particles.update(Float(dt), world)
        if sleeping > 0 {
            sleeping += Float(dt)
            if sleeping > 2.5 {
                // Skip to morning.
                let day = floor(time / DAY_LENGTH)
                time = (day + 1) * DAY_LENGTH + 0.01 * DAY_LENGTH
                sleeping = 0
                onToast?("Good morning")
            }
        }
        fluidTimer += dt
        if fluidTimer >= 0.2 { fluidTimer = 0; world.fluidTick() }
        lavaTimer += dt
        if lavaTimer >= (dim.dim == .nether ? 0.5 : 1.5) { lavaTimer = 0; world.fluidTick(lava: true) }
        fireTimer += dt
        if fireTimer >= Double.random(in: 1.2...1.8) { fireTimer = 0; world.fireTick() }
        portalTick(Float(dt))
        endPortalTick()
        updateEyes(Float(dt))
        endTick(Float(dt))
        hazardTick(Float(dt))
        if !world.pendingMobs.isEmpty {
            for (name, p) in world.pendingMobs {
                guard let k = MobKind.named(name) else { continue }
                let m = Mob(k, at: p)
                m.persistent = true
                mobs.mobs.append(m)
            }
            world.pendingMobs.removeAll()
        }
        tickAccum += dt
        while tickAccum >= 0.05 {
            tickAccum -= 0.05
            gameTick()
        }
        time += dt
        autosaveTimer += dt
        if autosaveTimer > 60 { autosaveTimer = 0; saveNow() }
    }

    // 20 Hz fixed-rate logic (furnaces...).
    private func gameTick() {
        randomTicks()
        spawnerTick(0.05)
        for (p, be) in world.blockEntities where be.kind == .furnace {
            if be.tickFurnace() {
                // Swap between furnace and lit furnace, keeping the facing.
                let b = world.block(p.x, p.y, p.z)
                let base = Blocks.groupBase[Int(b)]
                let facing = b - base
                let other = Blocks.key(base) == "furnace" ? Blocks.id("lit_furnace") : Blocks.id("furnace")
                world.setBlock(p.x, p.y, p.z, other + facing)
            }
        }
    }
}
