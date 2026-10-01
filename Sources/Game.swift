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
    let arms = Armory()               // gun rounds in flight and the player's gun state (Ballistics.swift)
    var lastHurtAt: Double = -10      // hurt cooldown (reference: 10 ticks of invulnerability after a hit)
    var lastHurtAmount = 0
    var bulletHit = false             // gun rounds ignore the hurt cooldown (each round lands)
    let inventory = PlayerInventory()
    let save: SaveManager?
    let persistent: Bool

    var time: Double = DAY_LENGTH * 0.06
    var selected: Int {
        get { inventory.selected }
        set { inventory.selected = newValue }
    }
    var paused = true {
        didSet {
            guard paused != oldValue else { return }
            // Pausing opens the in-game pause menu (unless another screen is up); resuming closes it.
            if paused && menu == nil { openMenu(PauseMenu(game: self)) }
            else if !paused && menu is PauseMenu { menu = nil }
            onPauseChanged?(paused)
        }
    }
    var appAction: ((String) -> Void)?
    var invertY: Bool = UserDefaults.standard.bool(forKey: "invertY") { didSet { UserDefaults.standard.set(invertY, forKey: "invertY") } }
    // Graphics: Fancy (sky gradient, water reflections, extra effects) or Fast (the plain renderer). Default Fancy.
    // Fancy only: the 3D world renders at this fraction of the window size and is upscaled (HUD stays sharp).
    // Saved as "fancyWorldScale": "renderScale" is the Resolution option (Settings.renderScale, whole frame).
    var renderScale: Float = { let v = UserDefaults.standard.float(forKey: "fancyWorldScale"); return v > 0 ? v : 1 }() {
        didSet { UserDefaults.standard.set(renderScale, forKey: "fancyWorldScale") }
    }
    var fancyGraphics: Bool = UserDefaults.standard.object(forKey: "fancyGraphics") == nil ? true : UserDefaults.standard.bool(forKey: "fancyGraphics") {
        didSet { UserDefaults.standard.set(fancyGraphics, forKey: "fancyGraphics") }
    }
    var autoJump: Bool = UserDefaults.standard.bool(forKey: "autoJump") { didSet { UserDefaults.standard.set(autoJump, forKey: "autoJump"); player.autoJump = autoJump } }
    var deadZone: Float = { let v = UserDefaults.standard.float(forKey: "deadZone"); return v > 0 ? v : 0.15 }() {
        didSet { UserDefaults.standard.set(deadZone, forKey: "deadZone") }
    }
    var showDebug = false
    var hideHUD = false               // F1
    var commandLog: [String] = []     // console output (Commands.swift)
    var commandHistory: [String] = []
    var hearts: [IVec3] = []          // Barkwraith hearts near the player (AshenGrove.swift)
    var heartTimer: Float = 0
    var heartScanAge: Float = 100
    var cameraMode = 0                // F5 / View button: 0 first person, 1 behind, 2 in front
    var screenshotRequested = false   // F2
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
    var credits: Float?            // seconds into the hollow credits while they are showing
    var dragonSpawnTimer: Float = 3
    let effects = EffectSet()      // active status effects on the player
    var absorption: Float = 0      // golden hearts (half-hearts)
    var enchantSeed = UInt64.random(in: 1...UInt64.max)   // enchanting-table offers; changes after each enchant
    var eyes: [SeekerEye] = []
    var elytraWear: Float = 0
    var bullets: [SentryBolt] = []
    weak var riding: Mob?          // the minecart the player sits in
    var riderPush: Float = 0
    var clouds: [AcidCloud] = []
    var fangs: [Fang] = []         // conjurer fangs
    var blocking = false           // holding a raised shield
    var lastPearl: Double = -10
    var rideInput = MoveInput()
    var falling: [FallingBlock] = []
    let enderChest = ItemContainer(27)     // the player's void chest inventory (shared by all void chests)
    var timeSinceRest: Float = 0
    var anchorSpawn: IVec3?          // charged rebirth anchor in the Emberdeep
    var jukeboxes: [JukeboxPlayer] = []
    var fovScale: Float = 1
    // Options (saved in user defaults).
    var fovSetting: Float = { let v = UserDefaults.standard.float(forKey: "fov"); return v > 0 ? v : 70 }() {
        didSet { UserDefaults.standard.set(fovSetting, forKey: "fov") }
    }
    var sensitivity: Float = { let v = UserDefaults.standard.float(forKey: "sensitivity"); return v > 0 ? v : 1 }() {
        didSet { UserDefaults.standard.set(sensitivity, forKey: "sensitivity") }
    }
    var volumeSetting: Float = { UserDefaults.standard.object(forKey: "volume") == nil ? 0.8 : UserDefaults.standard.float(forKey: "volume") }() {
        didSet { UserDefaults.standard.set(volumeSetting, forKey: "volume"); sound?.volume = volumeSetting }
    }
    var rockets: [Rocket] = []
    var lastWind: Double = -10
    var deathScore = 0
    var lastDeath: V3?
    let music = MusicDirector()
    var caveTimer: Float = 30
    let audio = AudioState()
    let subtitles = SubtitleState()
    var musicVolume: Float = { UserDefaults.standard.object(forKey: "musicVolume") == nil ? 1 : UserDefaults.standard.float(forKey: "musicVolume") }() {
        didSet { AudioSettings.set(.music, musicVolume) }
    }
    var equipAnim: Float = 0          // lowers and raises the held item after switching
    var lastSiegeDay = -1
    var respawnTimer: Float = 0
    var respawnCrystals: [Mob] = []
    var stepVibe: Float = 0
    var freeze: Float = 0
    var freezeTick: Float = 0
    var advancements = Set<String>()
    var advToasts: [(String, Bool, Double)] = []
    var lastAdvCheck: Double = 0
    var visitedBiomes = Set<String>()
    var killedKinds = Set<String>()
    var eatenFoods = Set<String>()
    var composterReady: [IVec3: Double] = [:]
    var scoping = false
    var lastHorn: Double = -100
    var difficulty = 2               // 0 peaceful, 1 easy, 2 normal, 3 hard
    static let difficultyNames = ["Peaceful", "Easy", "Normal", "Hard"]
    var maps: [Int: MapData] = [:]
    var mapRow = 0
    var brushProgress: Float = 0
    var shriekCooldown = 0
    var warningLevel = 0
    var shriekDecay = 600    // nightwings appear after 3 days (3600 s) without sleep
    private var beaconTicks = 0
    var shieldCooldown: Float = 0
    var shieldRaise: Float = 0
    var crossbowCharge: Float = 0
    var tridentCharge: Float = 0
    var spearCharge: Float = 0             // seconds the use button has held a spear level (Spear.swift)
    var spearHitAt: [ObjectIdentifier: Float] = [:]
    var bobber: Bobber?
    var weather = Weather()
    let emberAtmosphere = EmberAtmosphere()
    var flashes: [LightFlash] = []
    var bolts: [Bolt] = []
    var lightningFlash: Float = 0
    var rainSoundTimer: Float = 0
    var lightningTimer: Float = 8
    var lightningRods: [IVec3] = []
    var raid: Raid?
    var raidOmenAt: V3?
    var patrolTimer: Float = 600
    private var raidTimer: Float = 0
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
        // Far-off gunfire is heard as its distant boom and echo instead of the close crack.
        if case .gun(let k) = s, WeaponAudio.hasDistant(k), let p = pos, simd_length(p - player.eye) > 32 {
            sfx(.gunDistant(k), v, at: p)
            return
        }
        if audio.record != nil { audio.record![s.name, default: 0] += 1 }
        Feedback.sound(self, s, v, at: pos)        // rumble + the one subtitle system (HudExtras, AudioSettings.subtitles)
        guard let snd = sound else { return }
        let occ = pos.map { audioOcclusion(player.eye, $0) } ?? 0
        snd.play(s, volume: v, at: pos, occlusion: occ)
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

    static var alive = 0            // live Game objects (leak check in --bench)
    deinit { Game.alive -= 1 }

    init(world: World, save: SaveManager?, persistent: Bool) {
        Game.alive += 1
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
        if let s = save, let d = try? Data(contentsOf: s.dir.appendingPathComponent("maps.json")), let mm = try? JSONDecoder().decode([Int: MapData].self, from: d) { maps = mm }
        effects.load(m.effects)
        absorption = m.absorption ?? 0
        if let e = m.enchantSeed { enchantSeed = e }
        loadExtra(m.extra ?? [:])
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
                  dragonKilled: dragonKilled, gateways: gateways, seenCredits: seenCredits,
                  effects: effects.saved, absorption: absorption, enchantSeed: enchantSeed, extra: saveExtra())
    }

    func saveNow() {
        guard persistent, let s = save else { return }
        world.saveAll()
        mobs.save(to: world.save)
        if let d = try? JSONEncoder().encode(maps) { try? d.write(to: s.dir.appendingPathComponent("maps.json"), options: .atomic) }
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
        w.redstone.game = self
        w.onFluidEvent = { [weak self] p in self?.sfx(.fizz, 0.8, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5) }
        w.onIgnite = { [weak self] p, b in
            guard let self else { return }
            if Blocks.key(b) == "tnt" { self.world.setBlockAsync(p.x, p.y, p.z, AIR); self.tnts.prime(at: p) }
        }
    }

    // Moves the player to another dimension (saving and unloading the one we leave).
    func changeDimension(to d: Dim, at p: V3) {
        let old = world
        let oldMobs = mobs
        if persistent { old.saveAll() }
        for m in oldMobs.mobs where m.keepOnUnload { oldMobs.stash(m) }
        oldMobs.mobs.removeAll()
        if persistent { oldMobs.save(to: old.save) }
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

    // Moon phase 0...7 (0 = full), one step per day.
    var moonPhase: Int { ((Int(time / DAY_LENGTH) % 8) + 8) % 8 }

    var daylight: Float {
        if !dim.dim.hasSky { return dim.dim == .end ? 0.75 : 1 }
        let s = sunDir.y
        let t = simd_clamp((s + 0.12) / 0.4, 0, 1)
        let d = 0.12 + 0.88 * t * t * (3 - 2 * t)
        // Rain and thunder darken the day (reference: -5/16 and another -5/16 of sky light).
        let overcast = 1 - 0.3 * weather.rain - 0.25 * weather.thunder
        return max(0.1, d * overcast) + lightningFlash * 0.6
    }

    var skyColor: V3 {
        if dim.dim == .nether { return emberAtmosphere.fog(at: player.pos, gen: world.gen) }
        if !dim.dim.hasSky { return dim.dim.fogColor }
        let day = V3(0.52, 0.72, 0.96), night = V3(0.015, 0.02, 0.06)
        var c = simd_mix(night, day, V3(repeating: (daylight - 0.12) / 0.88))
        let s = sunDir.y
        let dusk = max(0, 1 - abs(s - 0.02) / 0.22)
        c = simd_mix(c, V3(0.95, 0.5, 0.28), V3(repeating: dusk * 0.45))
        // Overcast: desaturate toward grey; lightning flashes it white.
        let grey = V3(repeating: (c.x + c.y + c.z) / 3 * 0.6)
        c = simd_mix(c, grey, V3(repeating: weather.rain * 0.75))
        c = simd_mix(c, V3(0.8, 0.82, 0.9), V3(repeating: min(1, lightningFlash)))
        return c
    }

    // Colour straight up for the Fancy sky gradient: a deeper blue than the horizon by day, near black at night.
    var skyZenith: V3 {
        let c = skyColor
        return simd_mix(c * V3(0.45, 0.6, 0.92), c, V3(repeating: min(1, weather.rain * 0.6 + lightningFlash)))
    }

    // MARK: Hotbar / items

    var held: ItemStack { inventory.held }

    func select(_ i: Int) {
        let n = (i % 9 + 9) % 9
        if n != selected { eatProgress = 0; mining = nil; equipAnim = 1; Tutorial.selected(self) }
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
        dropItem(h.with(count: n))
        h.count -= n
        inventory.held = h.count > 0 ? h : .empty
    }

    // Uses up durability of the held tool; breaks it when worn out.
    func damageHeld(_ amount: Int) {
        guard survival else { return }
        var h = held
        guard !h.isEmpty, h.def.durability > 0 else { return }
        for _ in 0..<amount where !Enchant.wearSkipped(h) { h.damage += 1 }
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
        audioMenuOpened(m)
    }

    func closeMenu() {
        guard let m = menu, !(m is DeathMenu) else { return }
        audioMenuClosed(m)
        m.onClose()
        if !carried.isEmpty {
            let rest = inventory.add(carried)
            if !rest.isEmpty { dropItem(rest) }
            carried = .empty
        }
        menu = nil
    }

    func openInventory() {
        openMenu(survival ? InventoryMenu(game: self) : CreativeMenu(game: self))
    }

    // MARK: Tick

    func tick(_ rawDt: Double) {
        let dt = min(rawDt, 0.05)
        clock += dt
        world.update(center: player.pos)

        let pad = readPad()
        padConnected = pad != nil
        PadManager.shared.note(pad: pad, input: input)
        HudExtras.tick(self)
        let p = pad ?? PadSnapshot()
        let q = prevPad
        defer { prevPad = p; input.endFrame() }

        if p.menu && !q.menu && !(menu is KeyboardMenu) && (menu as? PauseMenu)?.padBinding == nil {
            if paused { if menu is PauseMenu { closeMenu() } else { paused = false } }
            else { if menu != nil { closeMenu() }; paused = true }
        }
        if paused {
            if menu == nil { openMenu(PauseMenu(game: self)) }
            tickMenu(p, q, dt)
            return
        }

        let fdt = Float(dt)
        swing = max(0, swing - fdt * 4)
        equipAnim = max(0, equipAnim - fdt * 5)
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
            shipPlayerUpdate(fdt, MoveInput())
            survivalTick(dt, from: before)
            target = nil
            mining = nil
            advance(dt)
            return
        }
        if input.tapped(KeyBinds.key(.inventory)) || (p.y && !q.y) { openInventory(); return }
        if input.tapped(KeyBinds.key(.advancements)) { openMenu(AdvancementMenu(game: self)); return }

        // Look (the weapon wheel takes the sticks / mouse while open; aiming down sights slows the view)
        let wheelOpen = WeaponWheel.shared.tick(self, p, q, fdt)
        let adsK = AimAssist.lookScale(self)
        if input.captured && !wheelOpen {
            let sens: Float = 0.0022 * sensitivity * adsK
            player.yaw -= input.mouseDX * sens
            player.pitch -= input.mouseDY * sens * (invertY ? -1 : 1)
        }
        let look = wheelOpen ? V2(0, 0) : PadLook.shared.update(rx: p.rx, ry: p.ry, dead: deadZone, sensitivity: sensitivity * adsK, invert: invertY,
                                                              friction: AimAssist.friction(self), dt: fdt)
        player.yaw += look.x
        player.pitch += look.y
        AimAssist.gunTick(self, p, q, fdt)
        player.pitch = simd_clamp(player.pitch, -1.55, 1.55)
        player.yaw = player.yaw.truncatingRemainder(dividingBy: 2 * .pi)

        // Movement
        var mi = MoveInput()
        if input.down(KeyBinds.key(.forward)) { mi.forward += 1 }
        if input.down(KeyBinds.key(.back)) { mi.forward -= 1 }
        if input.down(KeyBinds.key(.right)) { mi.strafe += 1 }
        if input.down(KeyBinds.key(.left)) { mi.strafe -= 1 }
        let ls = stick(p.lx, p.ly, dead: deadZone)
        mi.forward += ls.y
        mi.strafe += ls.x
        mi.forward = simd_clamp(mi.forward, -1, 1)
        mi.strafe = simd_clamp(mi.strafe, -1, 1)
        mi.jump = input.down(KeyBinds.key(.jump)) || p.a
        mi.sneak = input.shift || PadActions.sneak(p, q, self)
        if input.control || (p.l3 && !q.l3) || PadActions.autoSprint(ls, fdt) { player.sprinting = true }
        mi.sprint = player.sprinting && (mi.forward > 0.3) && !(survival && hunger <= 6) && eatProgress == 0
        if mi.forward <= 0.3 { player.sprinting = false }
        if eatProgress > 0 || blocking || bowCharge > 0 || crossbowCharge > 0 || tridentCharge > 0 { mi.forward *= 0.3; mi.strafe *= 0.3 }

        if input.tapped(KeyBinds.key(.jump)) || (p.a && !q.a) {
            let chest = inventory.armor[1]
            let hasElytra = !chest.isEmpty && Items.key(chest.item) == "elytra" && chest.damage < chest.def.durability - 1
            if hasElytra && !player.onGround && !player.flying && !player.inWater && !player.gliding {
                player.gliding = true
            } else if clock - lastSpaceTap < 0.3 { toggleFly(); lastSpaceTap = -1 } else { lastSpaceTap = clock }
        }
        if player.gliding {
            // Glider Wings wear: 1 durability per second of flight; breaks at 1 left like the reference game.
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
        if input.tapped(KeyBinds.key(.fly)) || (p.up && !q.up) { toggleFly() }
        if input.tapped(Key.f3) { showDebug.toggle() }
        if input.tapped(Key.f1) { hideHUD.toggle() }
        if input.tapped(KeyBinds.key(.chat)) { openMenu(CommandMenu(game: self)); return }
        if input.tapped(Key.slash) { openMenu(CommandMenu(game: self, prefill: "/")); return }
        if input.tapped(Key.f2) || (p.share && !q.share) { screenshotRequested = true }
        if PadActions.extras(p, q, self) { return }
        if input.tapped(KeyBinds.key(.map)) { openMenu(MapMenu(game: self)); return }
        // View: a tap cycles the camera, holding it opens the world map (WorldMap.swift).
        if input.tapped(KeyBinds.key(.camera)) || MapInput.viewTap(self, p, q) { cameraMode = (cameraMode + 1) % 3 }
        if menu != nil { return }
        if input.tapped(KeyBinds.key(.drop)) { dropHeld(all: input.control) }

        // Hotbar
        for (i, k) in Key.digits.enumerated() where input.tapped(k) { select(i) }
        if input.scrollSteps != 0 { select(selected - input.scrollSteps) }
        let bumpersFree = world.ships.pilot == nil      // at the helm RB / LB climb and descend
        if bumpersFree && p.rb && !q.rb && !WeaponWheel.shared.ownsRB(self) { select(selected + 1) }
        if bumpersFree && p.lb && !q.lb { select(selected - 1) }

        if Turrets.shared.tick(self, p, q, sneak: mi.sneak, dt: fdt) { updateFov(Float(dt)); advance(dt); return }
        let before = player.pos
        if let r = riding, r.health <= 0 { dismount() }
        if riding != nil {
            riderPush = mi.forward
            rideInput = mi
            if mi.sneak { dismount() }
        } else {
            player.autoJump = autoJump
            shipPlayerUpdate(fdt, mi)
            powderSnowTick(fdt)
            vibrationTick(fdt)
        }
        let hmove = simd_length(V2(player.pos.x - before.x, player.pos.z - before.z))
        walkBob += hmove * 2.2
        walkAmount += ((player.onGround && !player.flying ? min(1, hmove / fdt / 4) : 0) - walkAmount) * min(1, fdt * 8)
        audioTick(from: before)
        survivalTick(dt, from: before)

        interact(p, q, dt)
        updateFov(Float(dt))
        if input.middleClicked || (p.x && !q.x && heldGun == nil) { pickBlock() }

        advance(dt)
    }

    // MARK: Interaction (attack, mine, use)

    private func interact(_ p: PadSnapshot, _ q: PadSnapshot, _ dt: Double) {
        let fdt = Float(dt)
        let reach: Float = survival ? 4.5 : 5
        target = AimAssist.sticky(self, world.raycast(player.eye, player.look, maxDist: reach), reach: reach)
        breakCooldown -= dt
        placeCooldown -= dt
        let breakHeld = input.leftDown || p.rt > 0.5
        let breakNow = input.leftClicked || (p.rt > 0.5 && q.rt <= 0.5)
        let useHeld = input.rightDown || p.lt > 0.5
        let useNow = input.rightClicked || (p.lt > 0.5 && q.lt <= 0.5)
        // Deck guns: use one to take its controls (VehicleControls.swift).
        if useNow, world.ships.pilot == nil, let hit = mobs.raycast(player.eye, player.look, maxDist: 4), Turrets.canMan(hit.0) {
            Turrets.shared.mount(self, hit.0); return
        }
        // A held gun fires even when aimed at a ship (unless piloting one, where the helm owns the buttons).
        if world.ships.pilot == nil && gunInteract(p, q, fire: breakHeld, firePressed: breakNow, aim: useHeld, dt: fdt) { mining = nil; return }
        if shipInteract(breakHeld: breakHeld, breakNow: breakNow, useNow: useNow, sneak: input.shift || p.b, dt: fdt) { return }

        // Attack: an animal in front of the block takes priority.
        var mobHit: Mob?
        if let hit = mobs.raycast(player.eye, player.look, maxDist: Spear.isSpear(held.item) ? Spear.reach : 3.5) {
            let (m, dist) = hit
            if let t = target {
                let c = V3(Float(t.hit.x), Float(t.hit.y), Float(t.hit.z)) + 0.5
                if dist < simd_length(c - player.eye) - 0.4 { mobHit = m }
            } else {
                mobHit = m
            }
        }
        if breakNow { swing = 1 }
        // Lunge (spear): the jab carries the player forward (not when digging a block, swimming or gliding).
        if breakNow, Spear.isSpear(held.item), mobHit != nil || target == nil, !player.inWater && !player.gliding {
            let lv = Enchant.level(.lunge, held)
            if lv > 0 && (!survival || hunger > 6) {
                let f = simd_normalize(V3(player.look.x, 0, player.look.z) + V3(1e-4, 0, 0))
                player.vel += f * (2.5 + 2.5 * Float(lv))
                if survival { exhaustion += Float(lv) }
            }
        }
        if breakNow && (projectiles.deflect(from: player.eye, look: player.look) || punchBullet()) { attackTimer = 0; sfx(.attack, 0.7); return }
        // Punching a filled item frame takes the item out first.
        if breakNow, let t = target, Blocks.shape[Int(world.block(t.hit.x, t.hit.y, t.hit.z))] == "frame", let be = world.blockEntities[t.hit], !be.container[0].isEmpty {
            drops.spawn(be.container[0], at: V3(Float(t.hit.x), Float(t.hit.y), Float(t.hit.z)) + 0.5)
            be.container[0] = .empty
            blockSound(.itemFrameRemove, at: t.hit, 0.7)
            return
        }
        if let m = mobHit {
            mining = nil
            if useNow && useItemOnMob(m) { swing = 1; return }
            if breakNow {
                // Attack cooldown: damage scales with how charged the swing is.
                let spd = held.isEmpty ? 4 : held.def.attackSpeed
                let charge = min(1, attackTimer * spd)
                var base = held.isEmpty ? 1 : held.def.attack
                base += 3 * Float(effects.level(.strength)) - 4 * Float(effects.level(.weakness))
                var dmg = max(0, base) * (0.2 + 0.8 * charge * charge)
                let crit = charge > 0.9 && player.vel.y < -0.5 && !player.onGround
                if crit { dmg *= 1.5 }
                dmg += Enchant.damageBonus(held, against: m) * charge
                // Mace smash: bonus damage from the fall, which is then cancelled.
                let fallen = player.airPeak - player.pos.y
                if Items.key(held.item) == "mace" && fallen > 1.5 && !player.onGround {
                    let f = fallen
                    var bonus = min(3, f) * 4 + max(0, min(5, f - 3)) * 2 + max(0, f - 8)
                    bonus += Float(Enchant.level(.density, held)) * 0.5 * f
                    dmg += bonus
                    player.airPeak = player.pos.y
                    player.vel.y = max(player.vel.y, 0)
                    let wb = Enchant.level(.windBurst, held)
                    if wb > 0 { player.vel.y = 8 + 4 * Float(wb) }
                    for o in mobs.mobs where o !== m && simd_length(o.pos - m.pos) < 3.5 { o.hit(from: m.pos, damage: 0, knockback: 1.2) }
                    sfx(.anvil, 0.6, at: m.pos)
                }
                attackTimer = 0
                let kb = Float(Enchant.level(.knockback, held))
                m.hit(from: player.pos, damage: max(1, Int(dmg.rounded())), knockback: (player.sprinting ? 1.6 : 1) + kb)
                m.provoke(self)
                m.killedByPlayer = true
                m.lootingLevel = Enchant.level(.looting, held)
                let fa = Enchant.level(.fireAspect, held)
                if fa > 0 && !m.spec.fireImmune { m.fire = max(m.fire, Float(4 * fa)) }
                if m.arthropod && Enchant.level(.baneOfArthropods, held) > 0 {
                    m.applyEffect(.slowness, amp: 3, seconds: Float.random(in: 1...(1 + 0.5 * Float(Enchant.level(.baneOfArthropods, held)))), game: self)
                }
                // Sweep attack: a full-charge sword swing on the ground (not sprinting, no crit) hits mobs beside the target.
                if held.def.tool == .sword && charge > 0.9 && player.onGround && !player.sprinting && !crit {
                    let se = Enchant.level(.sweepingEdge, held)
                    let sweep = max(1, Int((1 + base * Float(se) / Float(se + 1)).rounded()))
                    for o in mobs.mobs where o !== m && o.health > 0 && simd_length(o.pos - m.pos) < 1.5 && simd_length(o.pos - player.pos) < 4
                        && o.kind != .villager && o.kind.spec.behavior != .vehicle {
                        o.hit(from: player.pos, damage: sweep, knockback: 0.4)
                        o.killedByPlayer = true
                    }
                    particles.crit(at: m.pos + V3(0, m.height * 0.5, 0))
                }
                if crit { particles.crit(at: m.pos + V3(0, m.height * 0.7, 0)) }
                let swept = held.def.tool == .sword && charge > 0.9 && player.onGround && !player.sprinting && !crit
                let hitSound: Snd = crit ? .attackCrit : (swept ? .attackSweep : (charge < 0.5 ? .attackWeak : (player.sprinting ? .attackKnockback : .attack)))
                sfx(hitSound, 0.8, at: m.pos + V3(0, m.height * 0.5, 0))
                if survival { exhaustion += 0.1 }
                damageHeld(held.def.tool == .sword ? 1 : 2)
            }
            return
        }

        // Mining
        if survival, breakNow, let t = target, teleportEgg(t.hit) { swing = 1; mining = nil; return }
        if let t = target, breakHeld {
            let b = world.block(t.hit.x, t.hit.y, t.hit.z)
            if !survival {
                if breakNow || breakCooldown <= 0 {
                    breakBlock(t.hit, b, drop: false)
                    breakCooldown = 0.3
                }
            } else {
                if mining != t.hit { mining = t.hit; mineProgress = 0 }
                let aqua = Enchant.level(.aquaAffinity, inventory.armor[0]) > 0
                var secs = Mining.breakSeconds(b, held, onGround: player.onGround || player.flying, inWater: player.headInWater && !aqua)
                if secs > 0 && secs.isFinite { secs /= miningSpeedMul }
                if secs.isInfinite {
                    mineProgress = 0
                } else {
                    mineProgress += secs <= 0 ? 1 : fdt / secs
                    swing = max(swing, 0.5)
                    mineSoundTimer -= fdt
                    if mineSoundTimer <= 0 { mineSoundTimer = 0.25; sfx(.hit(soundMat(b)), 0.5, at: V3(Float(t.hit.x), Float(t.hit.y), Float(t.hit.z)) + 0.5) }
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
        if useNow && Items.key(h.item) == "ender_eye" && useSeekerEye(on: target) { swing = 1; return }
        if useNow && useSpawnEgg(on: target) { swing = 1; return }
        if useNow && Items.key(h.item) == "firework_rocket" && player.gliding {
            player.boost = 0.5 + 0.6 * Float(max(1, h.tag))
            consumeHeld()
            sfx(.fireball, 0.5)
            swing = 1
            return
        }
        // Shield: raised 0.25 s after holding use (not while an axe hit has it disabled).
        shieldCooldown = max(0, shieldCooldown - fdt)
        if useHeld && shieldInHand && shieldCooldown <= 0 && eatProgress == 0 { shieldRaise += fdt } else { shieldRaise = 0 }
        blocking = shieldRaise >= 0.25
        if useHeld && shieldInHand && Items.key(held.item) == "shield" { return }
        if crossbowUse(useHeld, useNow, fdt) { return }
        if tridentUse(useHeld, fdt) { return }
        if spearUse(useHeld, fdt) { return }
        if fishingUse(useNow) { return }
        // Bow: hold to draw, release to shoot.
        // Brushing suspicious sand / gravel (archaeology).
        if Items.key(h.item) == "brush", useHeld, let t = target, Blocks.key(world.block(t.hit.x, t.hit.y, t.hit.z)).hasPrefix("suspicious_") {
            brushProgress += fdt
            if Int(brushProgress * 4) != Int((brushProgress - fdt) * 4) { sfx(.step(.sand), 0.4, at: V3(Float(t.hit.x), Float(t.hit.y), Float(t.hit.z)) + 0.5) }
            if brushProgress >= 2.5 {
                brushProgress = 0
                let k = Blocks.key(world.block(t.hit.x, t.hit.y, t.hit.z))
                let biome = world.gen.column(t.hit.x, t.hit.z).biome
                let table = biome == .desert ? "archaeology_desert" : (biome.isOcean ? "archaeology_ocean" : "archaeology_trail")
                let tmp = ItemContainer(3)
                var rng = SRng(UInt64.random(in: 1...UInt64.max))
                Loot.fill(tmp, table: table, rng: &rng)
                let at = V3(Float(t.hit.x), Float(t.hit.y), Float(t.hit.z)) + 0.5 + V3(Float(t.normal.x), Float(t.normal.y), Float(t.normal.z)) * 0.6
                for s in tmp.slots where !s.isEmpty { drops.spawn(s, at: at) }
                world.setBlock(t.hit.x, t.hit.y, t.hit.z, k == "suspicious_sand" ? SAND : Blocks.id("gravel"))
                damageHeld(1)
            }
            return
        }
        brushProgress = 0
        if Items.key(h.item) == "bow" {
            let ammo = arrowSlot()
            let infinity = Enchant.level(.infinity, h) > 0
            let hasArrow = !survival || ammo != nil || infinity
            if useHeld && hasArrow { bowCharge += fdt; return }
            if !useHeld && bowCharge > 0 {
                let t = bowCharge * 20
                let f = min(1, (t * t / 400 + t / 10) / 3)
                bowCharge = 0
                if f >= 0.1 {
                    let power = Enchant.level(.power, h)
                    let a = projectiles.shoot(from: player.eye, dir: player.look, speed: f * 60, fromPlayer: true,
                                              damage: 2 + (power > 0 ? 0.5 * Float(power) + 0.5 : 0))
                    a.punch = Enchant.level(.punch, h)
                    a.flame = Enchant.level(.flame, h) > 0
                    if let i = ammo, Potions.potion(of: inventory.main[i].item) != nil { a.tip = inventory.main[i].item }
                    let plain = ammo.map { Items.key(inventory.main[$0].item) == "arrow" } ?? true
                    a.pickup = survival && !(infinity && plain)
                    sfx(.bow, 0.8)
                    if survival && !(infinity && plain), let i = ammo {
                        var s = inventory.main[i]; s.count -= 1; inventory.main[i] = s
                    }
                    damageHeld(1)
                }
                return
            }
        } else {
            bowCharge = 0
        }
        if useNow && throwHeld() { return }
        if useNow && useEmptyMap() { swing = 1; return }
        if useNow && useExplorerMap() { swing = 1; return }
        if useNow {
            switch Items.key(h.item) {
            case "snowball": throwItem(.snowball); return
            case "wind_charge": throwWindCharge(); return
            case "egg", "brown_egg", "blue_egg": throwEgg(); return
            case "ender_pearl" where clock - lastPearl > 1: lastPearl = clock; throwItem(.pearl); return
            default: break
            }
        }
        if useGadget(useHeld: useHeld, useNow: useNow) { return }
        if useNow && !(target.map { isInteractive($0.hit) } ?? false) && (useBook() || useBundle()) { return }
        let alwaysEdible = ["golden_apple", "enchanted_golden_apple", "chorus_fruit", "honey_bottle", "suspicious_stew"]
        let hk = Items.key(h.item)
        let canEat = h.def.food != nil && survival && (hunger < 20 || alwaysEdible.contains { hk.hasPrefix($0) })
        let canDrink = h.def.drink && (survival || Potions.potion(of: h.item) != nil)
        if (canEat || canDrink) && useHeld && target.map({ !isInteractive($0.hit) }) ?? true {
            eatProgress += fdt
            if Int(eatProgress * 5) != Int((eatProgress - fdt) * 5) { sfx(h.def.drink || hk.hasSuffix("_bottle") || hk.hasSuffix("_stew") || hk.hasSuffix("_soup") ? .drink : .eat, 0.5) }
            if eatProgress >= 1.61 {
                if let f = h.def.food { eat(f, h.def.display) }
                foodEffects(hk)
                if h.def.drink {
                    finishDrink(h)
                    if hk == "honey_bottle" { consumeHeld(); giveOrReplaceHeldAfterConsume(ItemStack(Items.id("glass_bottle"), 1)) }
                } else {
                    consumeHeld()
                    if hk == "mushroom_stew" || hk == "beetroot_soup" || hk == "rabbit_stew" || hk.hasPrefix("suspicious_stew") {
                        giveOrReplaceHeldAfterConsume(ItemStack(Items.id("bowl"), 1))
                    }
                }
                eatProgress = 0
            }
            return
        }
        eatProgress = 0
        guard useNow || (useHeld && placeCooldown <= 0) else { return }
        placeCooldown = 0.25
        if useNow && useBottleOrCauldron(target) { swing = 1; return }
        if useBucket() { return }
        if useNow && placeBoat() { return }
        guard let t = target else { return }
        if useNow && !(input.shift || p.b) && teleportEgg(t.hit) { swing = 1; return }
        if useNow && !(input.shift || p.b) && isCircuitInteractive(t.hit) && useCircuit(t.hit) { swing = 1; return }
        if isInteractive(t.hit) && !(input.shift || p.b) && useNow {
            openBlock(t.hit)
            return
        }
        if useNow && useItemOnBlock(t) { return }
        if Items.key(h.item) == "redstone" {
            // Sparkstone dust goes on top of solid blocks.
            let c0 = world.block(t.hit.x, t.hit.y, t.hit.z)
            let at = Blocks.replaceable[Int(c0)] && !Blocks.isLiquid(c0) ? t.hit : t.hit + t.normal
            if Blocks.replaceable[Int(world.block(at.x, at.y, at.z))] && Blocks.opaque[Int(world.block(at.x, at.y - 1, at.z))] {
                world.setBlock(at.x, at.y, at.z, Blocks.id("redstone_wire"))
                sfx(.place(.stone), 0.6, at: V3(Float(at.x), Float(at.y), Float(at.z)) + 0.5)
                consumeHeld(); swing = 1
            }
            return
        }
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
        if Blocks.has(key + "[south]") && Blocks.shape[Int(blockItem)].isEmpty {
            // Any block registered with four facings turns its front toward the player.
            id = blockItem + BlockID(BlockRegistry.facingToward(yaw: player.yaw))
        }
        if Blocks.has(key + "[x]") && Blocks.shape[Int(blockItem)].isEmpty {
            // Pillars (logs, stems, basalt...) lie along the axis of the clicked face.
            if t.normal.x != 0 { id = Blocks.id(key + "[x]") } else if t.normal.z != 0 { id = Blocks.id(key + "[z]") }
        }
        let fracY = hitPoint(t).y - Float(t.hit.y)
        let upperHalf = t.normal.y == -1 || (t.normal.y == 0 && fracY > 0.5)
        let facing = BlockRegistry.facingToward(yaw: player.yaw)
        switch Blocks.shape[Int(blockItem)] {
        case "stairs": id = blockItem + BlockID((upperHalf ? 4 : 0) + (facing ^ 1))
        case "slab": id = blockItem + (upperHalf ? 1 : 0)
        case "door":
            // Two blocks tall; needs room above and ground below.
            guard useNow, at.y + 1 < CH, Blocks.replaceable[Int(world.block(at.x, at.y + 1, at.z))],
                  Blocks.opaque[Int(world.block(at.x, at.y - 1, at.z))] || Blocks.collide[Int(world.block(at.x, at.y - 1, at.z))],
                  !player.intersectsBlock(at), !player.intersectsBlock(IVec3(at.x, at.y + 1, at.z)) else { return }
            world.setBlock(at.x, at.y + 1, at.z, blockItem + BlockID(facing + 8))
            world.setBlock(at.x, at.y, at.z, blockItem + BlockID(facing))
            sfx(.place(soundMat(blockItem)), at: V3(Float(at.x), Float(at.y), Float(at.z)) + 0.5)
            consumeHeld(); swing = 1
            return
        case "trapdoor": id = blockItem + BlockID(facing + (upperHalf ? 8 : 0))
        case "gate": id = blockItem + BlockID(facing)
        case "ladder":
            guard t.normal.y == 0 else { return }
            let f = t.normal.z == -1 ? 0 : (t.normal.z == 1 ? 1 : (t.normal.x == -1 ? 2 : 3))
            id = blockItem + BlockID(f)
        case "lantern": id = blockItem + (t.normal.y == -1 ? 1 : 0)
        case "sign":
            if t.normal.y == 0 {
                let f = t.normal.z == -1 ? 0 : (t.normal.z == 1 ? 1 : (t.normal.x == -1 ? 2 : 3))
                id = blockItem + BlockID(4 + f)
            } else if t.normal.y == 1 {
                id = blockItem + BlockID(facing)
            } else { return }
        case "frame":
            if t.normal.y == 0 { id = blockItem + BlockID(t.normal.z == -1 ? 0 : (t.normal.z == 1 ? 1 : (t.normal.x == -1 ? 2 : 3))) }
            else { id = blockItem + (t.normal.y == 1 ? 4 : 5) }
        case "torch":
            if t.normal.y == -1 { return }
            if t.normal.y == 0 {
                guard Blocks.opaque[Int(clicked)] else { return }
                id = blockItem + BlockID(1 + (t.normal.z == -1 ? 0 : (t.normal.z == 1 ? 1 : (t.normal.x == -1 ? 2 : 3))))
            }
        case "hsign":
            if t.normal.y == -1 { id = blockItem + BlockID(facing) }
            else if t.normal.y == 0 {
                let f = t.normal.z == -1 ? 0 : (t.normal.z == 1 ? 1 : (t.normal.x == -1 ? 2 : 3))
                id = blockItem + BlockID(4 + (f < 2 ? 2 : 0))        // the board runs along the wall
            } else { return }
        case "hook":
            guard t.normal.y == 0 else { return }
            id = blockItem + BlockID(t.normal.z == -1 ? 0 : (t.normal.z == 1 ? 1 : (t.normal.x == -1 ? 2 : 3)))
        case "banner":
            guard let bs = bannerState(blockItem, normal: t.normal) else { return }
            id = bs
        case "painting":
            guard t.normal.y == 0, useNow else { return }
            let f = t.normal.z == -1 ? 0 : (t.normal.z == 1 ? 1 : (t.normal.x == -1 ? 2 : 3))
            placePainting(at: at, facing: f)
            if Blocks.groupBase[Int(world.block(at.x, at.y, at.z))] == blockItem { consumeHeld(); swing = 1; blockSound(.paintingPlace, at: at, 0.8) }
            return
        case "skull":
            if t.normal.y == 0 {
                let f = t.normal.z == -1 ? 0 : (t.normal.z == 1 ? 1 : (t.normal.x == -1 ? 2 : 3))
                id = blockItem + BlockID(4 + f)
            } else {
                id = blockItem + BlockID(facing)
            }
        default: break
        }
        let rsShapes: Set<String> = ["lever", "button", "plate", "repeater", "comparator", "observer", "piston", "dispenser", "hopper", "daylight"]
        if rsShapes.contains(Blocks.shape[Int(blockItem)]) || Circuit.kind(blockItem) == .torch {
            guard let rid = redstonePlacement(blockItem, at: at, normal: t.normal, upperHalf: upperHalf) else { return }
            id = rid
        }
        let supported: Bool
        if Blocks.shape[Int(id)] == "torch" && id == Blocks.groupBase[Int(id)] {
            supported = Blocks.opaque[Int(world.block(at.x, at.y - 1, at.z))]
                || [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)].contains { d in Blocks.opaque[Int(world.block(at.x + d.x, at.y, at.z + d.z))] }
        } else if Blocks.shape[Int(id)] == "rail" {
            supported = Blocks.opaque[Int(world.block(at.x, at.y - 1, at.z))]
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
            if key == "chest" || key.hasSuffix("copper_chest") { world.blockEntities[at] = BlockEntity(.chest) }
            if key == "dispenser" || key == "dropper" { world.blockEntities[at] = BlockEntity(.dispenser) }
            if key == "hopper" { world.blockEntities[at] = BlockEntity(.hopper) }
            if key == "brewing_stand" { world.blockEntities[at] = BlockEntity(.brewing) }
            if key == "beacon" { world.blockEntities[at] = BlockEntity(.beacon) }
            if key.hasSuffix("shulker_box") {
                let be = BlockEntity(.shulker)
                if let c = h.contents { for (i, s) in c.prefix(27).enumerated() { be.container[i] = s } }
                world.blockEntities[at] = be
            }
            if key == "trapped_chest" { world.blockEntities[at] = BlockEntity(.chest) }
            if key.hasSuffix("lightning_rod") { lightningRods.append(at) }
            placedReactions(at)
            world.redstone.vibrate(at: V3(Float(at.x) + 0.5, Float(at.y) + 0.5, Float(at.z) + 0.5))
            if Blocks.shape[Int(id)] == "sign" || Blocks.shape[Int(id)] == "hsign" { openSignEditor(at) }
            if Blocks.shape[Int(id)] == "banner" { let be = BlockEntity(.banner); be.patterns = h.pat ?? []; world.blockEntities[at] = be }
            if Rails.isRail(id) { Rails.autoShape(world, at) }
            if key == "wither_skeleton_skull" { trySummonBlight(at) }
            if key == "carved_pumpkin" || key == "jack_o_lantern" { if !trySummonCopperGolem(at) { trySummonGolem(at) } }
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
        let b = world.block(p.x, p.y, p.z)
        let k = Blocks.key(Blocks.groupBase[Int(b)])
        let shape = Blocks.shape[Int(b)]
        if (shape == "door" || shape == "trapdoor") && !k.hasPrefix("iron_") { return true }
        if shape == "gate" { return true }
        return k == "crafting_table" || k == "furnace" || k == "lit_furnace" || k == "chest" || k == "brewing_stand"
            || k == "enchanting_table" || k.hasSuffix("anvil") || k == "beacon" || k == "smithing_table" || k == "stonecutter" || k == "grindstone"
            || k == "ender_chest" || k == "trapped_chest" || k.hasSuffix("copper_chest") || k.hasSuffix("shulker_box") || k == "cake" || k.hasSuffix("candle")
            || k.hasSuffix("item_frame") || k.hasSuffix("_sign") || k == "cartography_table" || k == "loom" || k == "smoker" || k == "blast_furnace" || k == "barrel" || k == "bell" || k == "composter" || k == "lectern" || k == "chiseled_bookshelf" || k == "crafter" || k == "decorated_pot" || k.hasSuffix("_shelf")
    }

    // Opens/closes a wooden door (both halves), trapdoor or fence gate.
    func toggleOpenable(_ p: IVec3) {
        let b = world.block(p.x, p.y, p.z)
        let base = Blocks.groupBase[Int(b)]
        let st = Int(b - base)
        let shape = Blocks.shape[Int(b)]
        let flipped = BlockID(st ^ 4)
        world.setBlock(p.x, p.y, p.z, base + flipped)
        if shape == "door" {
            let other = IVec3(p.x, p.y + (st & 8 != 0 ? -1 : 1), p.z)
            let ob = world.block(other.x, other.y, other.z)
            if Blocks.groupBase[Int(ob)] == base { world.setBlock(other.x, other.y, other.z, base + BlockID(Int(ob - base) ^ 4)) }
        }
        audioOpenable(shape: shape, base: base, opening: (flipped & 4) != 0, at: p)
    }

    func openBlock(_ p: IVec3) {
        let k = Blocks.key(Blocks.groupBase[Int(world.block(p.x, p.y, p.z))])
        if ["door", "trapdoor", "gate"].contains(Blocks.shape[Int(world.block(p.x, p.y, p.z))]) { toggleOpenable(p); return }
        switch k {
        case "crafting_table": openMenu(CraftingTableMenu(game: self))
        case "furnace", "lit_furnace":
            let be = world.blockEntities[p] ?? BlockEntity(.furnace)
            world.blockEntities[p] = be
            openMenu(FurnaceMenu(game: self, entity: be))
        case "smoker", "blast_furnace":
            let be = world.blockEntities[p] ?? BlockEntity(.furnace)
            be.mob = k
            world.blockEntities[p] = be
            let m = FurnaceMenu(game: self, entity: be)
            m.title = k == "smoker" ? "Smoker" : "Blast Furnace"
            openMenu(m)
        case "barrel":
            let be = world.blockEntities[p] ?? BlockEntity(.chest)
            world.blockEntities[p] = be
            openMenu(ChestMenu(game: self, container: be.container, title: "Barrel"))
        case "bell":
            sfx(.bell, 1.5, at: V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5))
            ringBell(p)
        case "composter": useComposter(p)
        case "lectern": useLectern(p)
        case "chiseled_bookshelf": useShelf(p)
        case _ where k.hasSuffix("_shelf"): useDisplayShelf(p)
        case "crafter":
            let be = world.blockEntities[p] ?? BlockEntity(.crafter)
            world.blockEntities[p] = be
            openMenu(CrafterMenu(game: self, entity: be))
        case "decorated_pot": usePot(p)
        case "chest":
            boarlingsGuard(p, block: world.block(p.x, p.y, p.z))
            let be = world.blockEntities[p] ?? BlockEntity(.chest)
            world.blockEntities[p] = be
            // A neighbouring chest with the same facing along the chest's width makes a large chest.
            let b = world.block(p.x, p.y, p.z)
            let facing = Int(b - Blocks.groupBase[Int(b)])
            let side = facing < 2 ? [IVec3(1, 0, 0), IVec3(-1, 0, 0)] : [IVec3(0, 0, 1), IVec3(0, 0, -1)]
            if let q = side.map({ p + $0 }).first(where: { world.block($0.x, $0.y, $0.z) == b }) {
                let other = world.blockEntities[q] ?? BlockEntity(.chest)
                world.blockEntities[q] = other
                let first = (q.x + q.z) < (p.x + p.z) ? other : be, second = first === be ? other : be
                openMenu(DoubleChestMenu(game: self, a: first.container, b: second.container))
                return
            }
            openMenu(ChestMenu(game: self, entity: be))
        case "brewing_stand":
            let be = world.blockEntities[p] ?? BlockEntity(.brewing)
            world.blockEntities[p] = be
            openMenu(BrewingMenu(game: self, entity: be))
        case "enchanting_table": openMenu(EnchantMenu(game: self, at: p))
        case "smithing_table": openMenu(SmithingMenu(game: self))
        case "stonecutter": openMenu(StonecutterMenu(game: self))
        case "grindstone": openMenu(GrindstoneMenu(game: self))
        case "ender_chest": openMenu(ChestMenu(game: self, container: enderChest, title: "Void Chest"))
        case _ where k.hasSuffix("copper_chest"):
            let be = world.blockEntities[p] ?? BlockEntity(.chest)
            world.blockEntities[p] = be
            let m = ChestMenu(game: self, entity: be)
            m.title = "Copper Chest"
            openMenu(m)
        case "trapped_chest":
            let be = world.blockEntities[p] ?? BlockEntity(.chest)
            world.blockEntities[p] = be
            let m = ChestMenu(game: self, entity: be)
            m.title = "Trapped Chest"
            world.redstone.setTrapped(p, 1)
            m.closed = { [weak self] in self?.world.redstone.setTrapped(p, 0) }
            openMenu(m)
        case _ where k.hasSuffix("shulker_box"):
            let be = world.blockEntities[p] ?? BlockEntity(.shulker)
            world.blockEntities[p] = be
            openMenu(ShellBoxMenu(game: self, entity: be))
        case "item_frame", "glow_item_frame": _ = useItemFrame(p)
        case "cartography_table": openMenu(CartographyMenu(game: self))
        case "loom": openMenu(LoomMenu(game: self))
        case _ where k.hasSuffix("_sign"): openSignEditor(p)
        case "cake":
            // Eat a slice: 2 hunger, 0.4 saturation; seven slices.
            guard !survival || hunger < 20 else { return }
            let b = world.block(p.x, p.y, p.z)
            let bite = Int(b - Blocks.groupBase[Int(b)])
            eat(FoodInfo(hunger: 2, saturation: 0.4), "Cake")
            world.setBlock(p.x, p.y, p.z, bite >= 6 ? AIR : b + 1)
        case _ where k.hasSuffix("candle"):
            // Right-click a lit candle to blow it out.
            let b = world.block(p.x, p.y, p.z)
            let st = Int(b - Blocks.groupBase[Int(b)])
            if st >= 4 { world.setBlock(p.x, p.y, p.z, b - 4); blockSound(.candleOut, at: p, 0.6) }
        case "beacon":
            let be = world.blockEntities[p] ?? BlockEntity(.beacon)
            world.blockEntities[p] = be
            openMenu(BeaconMenu(game: self, at: p, entity: be))
        case "anvil", "chipped_anvil", "damaged_anvil": openMenu(AnvilMenu(game: self, at: p))
        default: break
        }
    }

    func breakBlock(_ p: IVec3, _ b: BlockID, drop: Bool) {
        boarlingsGuard(p, block: b)
        blockSound(audioBreakSound(b), at: p)
        particles.blockBreak(b, at: p)
        world.setBlock(p.x, p.y, p.z, AIR)
        world.redstone.vibrate(at: V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5))
        // Wall torches hanging on this block fall off.
        for (f, d) in [IVec3(0, 0, -1), IVec3(0, 0, 1), IVec3(-1, 0, 0), IVec3(1, 0, 0)].enumerated() {
            let q = p + d
            let tb = world.block(q.x, q.y, q.z)
            if Blocks.shape[Int(tb)] == "torch" && Int(tb - Blocks.groupBase[Int(tb)]) == f + 1 {
                world.setBlock(q.x, q.y, q.z, AIR)
                if drop { drops.spawn(ItemStack(Items.item(forBlock: tb) ?? 0, 1), at: V3(Float(q.x) + 0.5, Float(q.y) + 0.5, Float(q.z) + 0.5)) }
            }
        }
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
            if let r = ores[bk], Mining.canHarvest(b, held), Enchant.level(.silkTouch, held) == 0 { addXP(Int.random(in: r)) }
        }
        let center = V3(Float(p.x) + 0.5, Float(p.y) + 0.3, Float(p.z) + 0.5)
        if bk.hasPrefix("infested_") && survival { mobs.mobs.append(Mob(.silverfish, at: center)) }
        if Rails.isRail(b) {
            for (dx, dz) in [(0, -1), (0, 1), (-1, 0), (1, 0)] { if let q = Rails.neighbour(world, p, dx, dz) { Rails.autoShape(world, q, recurse: false) } }
        }
        if Circuit.kind(b) == .pistonHead {
            // The piston behind the head goes too (and drops).
            let face = Int(b - Blocks.groupBase[Int(b)]) % 6
            let back = p + BlockRegistry.dir6[[1, 0, 3, 2, 5, 4][face]]
            let bb = world.block(back.x, back.y, back.z)
            if Circuit.kind(bb) == .piston || Circuit.kind(bb) == .stickyPiston {
                if drop && survival { drops.spawn(ItemStack(Items.item(forBlock: bb) ?? 0, 1), at: center) }
                world.setBlock(back.x, back.y, back.z, AIR)
            }
        }
        if (Circuit.kind(b) == .piston || Circuit.kind(b) == .stickyPiston) && Int(b - Blocks.groupBase[Int(b)]) >= 6 {
            let face = Int(b - Blocks.groupBase[Int(b)]) % 6
            let head = p + BlockRegistry.dir6[face]
            if Circuit.kind(world.block(head.x, head.y, head.z)) == .pistonHead { world.setBlock(head.x, head.y, head.z, AIR) }
        }
        if Blocks.shape[Int(b)] == "door" {
            // Take the other half with it (only one door drops).
            let upper = Int(b - Blocks.groupBase[Int(b)]) & 8 != 0
            let o = IVec3(p.x, p.y + (upper ? -1 : 1), p.z)
            if Blocks.groupBase[Int(world.block(o.x, o.y, o.z))] == Blocks.groupBase[Int(b)] { world.setBlock(o.x, o.y, o.z, AIR) }
        }
        if bk == "chorus_plant" || bk == "chorus_flower" {
            // Spiral plants collapse above a broken stem.
            var y = p.y + 1
            while y < CH, ["chorus_plant", "chorus_flower"].contains(Blocks.key(world.block(p.x, y, p.z))) {
                let above = world.block(p.x, y, p.z)
                world.setBlockAsync(p.x, y, p.z, AIR)
                if drop { for s in Mining.drops(above, .empty) { drops.spawn(s, at: V3(Float(p.x) + 0.5, Float(y) + 0.3, Float(p.z) + 0.5)) } }
                y += 1
            }
        }
        if let be = world.blockEntities.removeValue(forKey: p) {
            if be.kind == .banner {
                var s = ItemStack(Items.item(forBlock: b) ?? 0, 1)
                s.pat = be.patterns.isEmpty ? nil : be.patterns
                if s.item != 0 && (drop || survival) { drops.spawn(s, at: center) }
                return
            }
            if be.kind == .shulker {
                // Shellsentry boxes keep their contents as an item.
                var box = ItemStack(Items.item(forBlock: b) ?? 0, 1)
                if be.container.slots.contains(where: { !$0.isEmpty }) { box.contents = be.container.slots }
                if box.item != 0 { drops.spawn(box, at: center) }
                return
            }
            for s in be.container.slots where !s.isEmpty { drops.spawn(s, at: center) }
        }
        if drop {
            for s in Mining.enchantedDrops(b, held) { drops.spawn(s, at: center, vel: V3(Float.random(in: -1...1), 2, Float.random(in: -1...1)), delay: 0.5) }
            exhaustion += 0.005
        }
        // Plants can't float: pop the one standing on the broken block.
        let above = world.block(p.x, p.y + 1, p.z)
        if Blocks.isPlant(above) || (Blocks.shape[Int(above)] == "torch" && above == Blocks.groupBase[Int(above)]) {
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
                    sfx(.fireExtinguish, 0.8)          // water evaporates in the Emberdeep
                } else {
                    world.setBlock(a.x, a.y, a.z, k == "water_bucket" ? WATER : LAVA)
                    sfx(k == "water_bucket" ? .bucketEmpty : .bucketEmptyLava, 0.8, at: V3(Float(a.x), Float(a.y), Float(a.z)) + 0.5)
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
            let looting = m.killedByPlayer ? m.lootingLevel : 0
            for (n, lo, hi) in m.spec.drops where Items.has(n) && !(m.kind == .minecart && m.variant > 0) {
                let c = Int.random(in: lo...(hi + looting))
                var item = Items.id(n)
                if m.fire > 0, let cooked = Recipes.smelt(item), Items.def(item).food != nil { item = cooked }
                if c > 0 { drops.spawn(ItemStack(item, c), at: at) }
            }
            if m.kind == .sheep && !m.sheared, Items.has("\(m.woolColor)_wool") { drops.spawn(ItemStack(Items.id("\(m.woolColor)_wool"), 1), at: at) }
            if m.kind == .zombie && Float.random(in: 0..<1) < 0.025 {
                drops.spawn(ItemStack(Items.id(["iron_ingot", "carrot", "potato"][Int.random(in: 0...2)]), 1), at: at)
            }
            let r = Float.random(in: 0..<1)
            if m.kind == .blaze && m.killedByPlayer {
                // Cinder rods: 0-1, +0-1 per Looting level, only from player kills (reference loot table).
                let n = Int.random(in: 0...1) + (looting > 0 ? Int.random(in: 0...looting) : 0)
                if n > 0 { drops.spawn(ItemStack(Items.id("blaze_rod"), n), at: at) }
            }
            if m.kind == .magmaCube && m.slimeSize > 1 && r < 0.25 { drops.spawn(ItemStack(Items.id("magma_cream"), 1), at: at) }
            // A chicken jockey's rider drops the "Hot Coop" disc.
            if m.isZombie && m.baby && m.mount?.kind == .chicken && m.killedByPlayer && Items.has("music_disc_lava_chicken") {
                drops.spawn(ItemStack(Items.id("music_disc_lava_chicken"), 1), at: at)
            }
            if m.kind == .creeper && m.lastHitBySkeleton, let d = MusicDiscs.creeperDrops.randomElement(), Items.has("music_disc_\(d)") {
                drops.spawn(ItemStack(Items.id("music_disc_\(d)"), 1), at: at)
            }
            if m.kind == .zombifiedPiglin && m.killedByPlayer && r < 0.025 { drops.spawn(ItemStack(Items.id("gold_ingot"), 1), at: at) }
            if m.kind == .witherSkeleton && m.killedByPlayer && r < 0.025 + 0.01 * Float(looting), Items.has("wither_skeleton_skull") {
                drops.spawn(ItemStack(Items.id("wither_skeleton_skull"), 1), at: at)
            }
        }
        if m.kind == .minecart && m.variant > 0 && m.variant < Carts.items.count { drops.spawn(ItemStack(Items.id(Carts.items[m.variant]), 1), at: at) }
        if m.kind == .boat {
            let k = Boats.itemKey(m.variant, chest: m.chested)
            if Items.has(k) { drops.spawn(ItemStack(Items.id(k), 1), at: at) }
        }
        if let c = m.cargo { for s in c.slots where !s.isEmpty { drops.spawn(s, at: at) }; m.cargo = nil }
        if let e = m.equip {
            // Worn gear drops 8.5% (+1% per looting level) from mobs, always from armor stands.
            for s in e where !s.isEmpty && (m.kind == .armorStand || Float.random(in: 0..<1) < 0.085 + 0.01 * Float(m.killedByPlayer ? m.lootingLevel : 0)) { drops.spawn(s, at: at) }
            m.equip = nil
        }
        if m.leashed { drops.spawn(ItemStack(Items.id("lead"), 1), at: at) }
        if m.chested && m.kind != .boat { drops.spawn(ItemStack(Items.id("chest"), 1), at: at) }
        if m.killedByPlayer { advancementKill(m) }
        captainDied(m)
        soldierDied(m)
        sculkBloom(at: m.pos, xp: m.spec.xp)
        let xp = m.sized ? m.slimeSize : m.spec.xp
        if m.killedByPlayer && !m.baby { addXP(xp + (m.kind.hostile ? 0 : Int.random(in: 0...1))) }
        particles.explosion(at: m.pos + V3(0, m.height / 2, 0), power: 0.5)
        audioMobDied(m)
    }

    // MARK: Survival

    // Monster spawners: active with a player within 16 blocks; every 10-40 s up to 4 mobs of the
    // spawner's kind appear within ±4 blocks, unless 6 of that kind are already near.
    func spawnerTick(_ dt: Float) {
        let pp = player.pos
        for (p, be) in world.blockEntities where be.kind == .spawner {
            let c = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)
            guard simd_length(c - pp) < 16, let kind = MobKind.named(be.mob) else { continue }
            if be.trial {
                // Trial spawner: six mobs (two at a time) for a nearby player, then a reward and a 30-minute rest.
                if be.cooldown > 0 { be.cooldown -= dt; continue }
                guard simd_length(c - pp) < 14, survival else { continue }
                let alive = mobs.mobs.filter { $0.kind == kind && simd_length($0.pos - c) < 16 }.count
                be.delay -= dt
                if be.spawned < 6 && alive < 2 && be.delay <= 0 {
                    be.delay = 2
                    let sp = c + V3(Float.random(in: -3...3), 0, Float.random(in: -3...3))
                    let m = Mob(kind, at: V3(floor(sp.x) + 0.5, Float(p.y), floor(sp.z) + 0.5))
                    if m.sized { m.makeSlime(size: 2) }
                    if !m.collides(m.pos, world) { mobs.mobs.append(m); be.spawned += 1; particles.flame(at: m.pos + V3(0, 0.5, 0)) }
                } else if be.spawned >= 6 && alive == 0 {
                    be.spawned = 0
                    be.cooldown = 1800
                    let tmp = ItemContainer(3)
                    var rng = SRng(UInt64.random(in: 1...UInt64.max))
                    Loot.fill(tmp, table: "trial_spawner", rng: &rng)
                    for s in tmp.slots where !s.isEmpty { drops.spawn(s, at: c + V3(0, 0.8, 0), vel: V3(0, 3, 0)) }
                    sfx(.vaultEject, 0.8, at: c)
                }
                continue
            }
            if Float.random(in: 0..<1) < 0.3 { particles.flame(at: c + V3(Float.random(in: -0.5...0.5), Float.random(in: -0.5...0.5), Float.random(in: -0.5...0.5))) }
            be.delay -= dt
            guard be.delay <= 0 else { continue }
            be.delay = Float.random(in: 10...40)
            var near = mobs.mobs.filter { $0.kind == kind && abs($0.pos.x - c.x) < 4.5 && abs($0.pos.y - c.y) < 2.5 && abs($0.pos.z - c.z) < 4.5 }.count
            for _ in 0..<4 where near < 6 {
                let sp = V3(c.x + Float.random(in: -4...4), Float(p.y + Int.random(in: -1...1)), c.z + Float.random(in: -4...4))
                let bx = Int(floor(sp.x)), by = Int(floor(sp.y)), bz = Int(floor(sp.z))
                guard Blocks.collide[Int(world.block(bx, by - 1, bz))] else { continue }
                // Hostile mobs from spawners need block light ≤ 11 (cinderwisps and silverfish ignore it in practice).
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

    func addXP(_ n0: Int) {
        guard n0 > 0 else { return }
        var n = n0
        // Mending: a random worn/held mending item takes the XP as durability (2 per point).
        var menders: [(ItemContainer, Int)] = []
        for (c, idx) in [(inventory.main, selected), (inventory.offhand, 0), (inventory.armor, 0), (inventory.armor, 1), (inventory.armor, 2), (inventory.armor, 3)] {
            let s = c[idx]
            if !s.isEmpty && s.damage > 0 && Enchant.level(.mending, s) > 0 { menders.append((c, idx)) }
        }
        if case let (c, idx)? = menders.randomElement() {
            var s = c[idx]
            let fix = min(s.damage, n * 2)
            s.damage -= fix
            c[idx] = s
            n -= (fix + 1) / 2
            if n <= 0 { sfx(.xp, 0.5); return }
        }
        xpPoints += n
        var leveled = false
        while xpPoints >= Game.xpToNext(xpLevel) { xpPoints -= Game.xpToNext(xpLevel); xpLevel += 1; leveled = true }
        sfx(leveled && xpLevel % 5 == 0 ? .levelUp : .xp, 0.5)
    }

    // Mob hits on the player: armor-reduced damage plus knockback away from the attacker.
    func hurtPlayer(_ amount: Int, from src: V3, cause: String, knockback: Float = 1, type: DamageType = .generic, attacker: Mob? = nil) {
        guard survival, alive, amount > 0 else { return }
        CombatHUD.shared.hurt(self, from: src, amount: amount)
        if let a = attacker { petsAttack(a) }
        if shieldBlocks(amount, from: src, type: type, attacker: attacker) { return }
        var amount = amount
        if attacker != nil || type == .projectile {
            // Reference difficulty scaling of mob damage: easy min(x/2+1, x), hard x*1.5.
            switch difficulty {
            case 0: return
            case 1: amount = min(amount / 2 + 1, amount)
            case 3: amount = amount * 3 / 2
            default: break
            }
        }
        damage(amount, cause, type: type, attacker: attacker)
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
        achieve("eat")
        // Omnivore: the reference list of 40 foods.
        if eatenFoods.insert(name).inserted && eatenFoods.count >= 40 { achieve("ate_all") }
        hunger = min(20, hunger + f.hunger)
        saturation = min(Float(hunger), saturation + f.saturation)
        if name == "Spiral Fruit" { chorusTeleport() }
    }

    // Spiral fruit: up to 16 tries at a random spot within 8 blocks with ground and room to stand.
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
                sfx(.teleport, 0.8)
                return
            }
        }
    }

    // Damage in half-hearts: armor (reference formula), resistance, enchantment protection,
    // absorption hearts, then the totem of rebirth.
    func damage(_ amount0: Int, _ cause: String, bypassArmor: Bool = false, type: DamageType = .generic, attacker: Mob? = nil) {
        guard survival, alive, amount0 > 0 else { return }
        if type == .fire && effects.has(.fireResistance) { return }
        // Hurt cooldown: within half a second of a hit, only the part of a bigger hit that exceeds it lands
        // (a blight skull and its blast, a creeper after an arrow...). The void and gun rounds skip it.
        var amount = amount0
        if type != .void && !bulletHit {
            if clock - lastHurtAt < 0.5 {
                guard amount > lastHurtAmount else { return }
                amount -= lastHurtAmount
                lastHurtAmount = amount0
            } else {
                lastHurtAt = clock
                lastHurtAmount = amount0
            }
        }
        var dmg = Float(amount)
        if !bypassArmor {
            let a = Float(inventory.armorPoints), tough = inventory.toughness
            let eff = min(20, max(a / 5, a - dmg / (2 + tough / 4)))
            dmg *= 1 - eff / 25
            for i in 0..<4 where !inventory.armor[i].isEmpty {
                var s = inventory.armor[i]
                if Enchant.wearSkipped(s) { continue }
                s.damage += max(1, amount / 4)
                inventory.armor[i] = s.damage >= s.def.durability ? .empty : s
            }
        }
        let res = effects.level(.resistance)
        if res > 0 { dmg *= max(0, 1 - 0.2 * Float(res)) }
        if type != .void && type != .starve {
            let epf = Enchant.protection(inventory.armor, type)
            dmg *= 1 - Float(epf) * 0.04
        }
        if absorption > 0 {
            let a = min(absorption, dmg)
            absorption -= a
            dmg -= a
        }
        if let m = attacker {
            // Thorns: 15% per level to hit back for 1-4.
            for s in inventory.armor.slots where !s.isEmpty {
                let t = Enchant.level(.thorns, s)
                if t > 0 && Float.random(in: 0..<1) < 0.15 * Float(t) {
                    m.hit(from: player.pos, damage: Int.random(in: 1...4), knockback: 0.3)
                }
            }
        }
        hurtFlash = 0.35
        audioHurt(type)
        guard dmg >= 0.5 else { return }
        health -= max(1, Int(dmg.rounded()))
        if health <= 0 && useTotem() { return }
        if health <= 0 { die(cause) }
    }

    // Totem of undying in either hand: survive with half a heart and a burst of effects.
    func useTotem() -> Bool {
        let key = "totem_of_undying"
        if Items.key(inventory.offhand[0].item) == key { inventory.offhand[0] = .empty }
        else if Items.key(held.item) == key { inventory.held = .empty }
        else { return false }
        health = 1
        effects.clear()
        absorption = 0
        achieve("totem")
        applyEffect(.regeneration, amp: 1, seconds: 45)
        applyEffect(.absorption, amp: 1, seconds: 5)
        applyEffect(.fireResistance, amp: 0, seconds: 40)
        particles.explosion(at: player.pos + V3(0, 1, 0), power: 0.6)
        sfx(.levelUp, 1)
        onToast?("Totem of Rebirth")
        return true
    }

    func die(_ cause: String) {
        guard !(menu is DeathMenu) else { return }
        sfx(.playerDeath)
        deathScore = xpPoints + xpLevel * 7
        lastDeath = player.pos
        // Drop everything where we died (plus up to 100 XP worth: 7 per level).
        let at = player.pos + V3(0, 1, 0)
        let lostXP = min(100, xpLevel * 7)
        effects.clear()
        absorption = 0
        for c in [inventory.main, inventory.armor, inventory.offhand] {
            for i in 0..<c.count where !c[i].isEmpty {
                if Enchant.level(.vanishingCurse, c[i]) > 0 { c[i] = .empty; continue }
                drops.spawn(c[i], at: at, vel: V3(Float.random(in: -2...2), Float.random(in: 1...4), Float.random(in: -2...2)), delay: 1)
                c[i] = .empty
            }
        }
        if lostXP > 0 { addXPOrbs(lostXP, at: at) }
        xpLevel = 0; xpPoints = 0
        if menu != nil { closeMenu() }
        riding = nil
        alive = false        // no pickups, no targeting until respawn (the dropped items stay where they fell)
        openMenu(DeathMenu(game: self, message: "Player \(cause)"))
    }

    // Respawn (from the death screen): anchor, bed/world spawn.
    func respawn() {
        alive = true
        if let a = anchorSpawn {
            // Respawn at a charged anchor in the Emberdeep (uses a charge).
            let nether = dimensionState(.nether).world
            let b = nether.block(a.x, a.y, a.z)
            if Blocks.key(Blocks.groupBase[Int(b)]) == "respawn_anchor" && Int(b - Blocks.groupBase[Int(b)]) > 0 {
                nether.setBlock(a.x, a.y, a.z, b - 1)
                let at = V3(Float(a.x) + 0.5, Float(a.y) + 1, Float(a.z) + 0.5)
                if dim.dim != .nether { changeDimension(to: .nether, at: at) }
                player.pos = at; player.vel = .zero; player.airPeak = at.y; player.pendingFall = 0
                health = 20; hunger = 20; saturation = 5; exhaustion = 0; air = 15; xpLevel = 0; xpPoints = 0; timeSinceRest = 0
                return
            }
            anchorSpawn = nil
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
        xpLevel = 0
        xpPoints = 0
        timeSinceRest = 0
    }

    // Footsteps, landing thuds and splashes.
    private func audioTick(from before: V3) {
        let p = player
        if p.inWater && !wasInWater && p.vel.y < -3 { sfx(.splash, min(1, -p.vel.y / 12)) }
        wasInWater = p.inWater
        if p.inWater && !p.onGround {
            // Swimming strokes while moving through water.
            audio.stepTimer += simd_length(V2(p.pos.x - before.x, p.pos.z - before.z)) + abs(p.pos.y - before.y) * 0.5
            if audio.stepTimer > 1.6 { audio.stepTimer = 0; sfx(.swim, p.headInWater ? 0.35 : 0.6) }
        }
        if p.pendingFall > 1.2 && !p.inWater {
            let under = world.block(Int(floor(p.pos.x)), Int(floor(p.pos.y - 0.2)), Int(floor(p.pos.z)))
            sfx(p.pendingFall > 3 && under != AIR ? .fall(soundMat(under)) : .land, min(1, p.pendingFall / 8))
            // Landing kicks up bits of the block underneath (more for bigger falls).
            if under != AIR { particles.dust(under, at: p.pos, count: min(24, Int(p.pendingFall * 3)), spread: 0.5) }
        }
        if p.sprinting && p.onGround && !p.inWater && Float.random(in: 0..<1) < 0.5 {
            let under = world.block(Int(floor(p.pos.x)), Int(floor(p.pos.y - 0.2)), Int(floor(p.pos.z)))
            if under != AIR { particles.dust(under, at: p.pos, count: 1, spread: 0.25) }
        }
        guard p.onGround && !p.flying && !p.inWater else { stepDist = 0.8; return }
        stepDist += simd_length(V2(p.pos.x - before.x, p.pos.z - before.z))
        if stepDist > (p.sprinting ? 2.1 : 1.7) {
            stepDist = 0
            let under = world.block(Int(floor(p.pos.x)), Int(floor(p.pos.y - 0.2)), Int(floor(p.pos.z)))
            if under != AIR { sfx(.step(soundMat(under)), p.sneaking ? 0.35 : 0.9) }
        }
    }

    // Hunger, regeneration, starvation, drowning and fall damage.
    private func survivalTick(_ dt: Double, from before: V3) {
        hurtFlash = max(0, hurtFlash - Float(dt))
        let fall = player.pendingFall
        player.pendingFall = 0
        guard survival else { air = 15; return }

        let safeFall = 3.5 + Float(effects.level(.jumpBoost))
        if fall > safeFall && !player.inWater { damage(Int(ceilf(fall - safeFall)), "fell from a high place", bypassArmor: true, type: .fall) }
        if player.pos.y < -60 { die("fell out of the world"); return }

        let moved = simd_length(V2(player.pos.x - before.x, player.pos.z - before.z))
        exhaustion += moved * (player.sprinting ? 0.1 : (player.inWater ? 0.01 : 0))
        if player.jumped { exhaustion += player.sprinting ? 0.2 : 0.05 }
        while exhaustion >= 4 {
            exhaustion -= 4
            if saturation > 0 { saturation = max(0, saturation - 1) } else { hunger = max(0, hunger - 1) }
        }

        // Fast regen with full hunger and saturation, slow regen at hunger >= 18.
        if hunger >= 20 && saturation > 0 && health < maxHealth {
            regenTimer += dt
            if regenTimer >= 0.5 { regenTimer = 0; health += 1; exhaustion += 6 }
        } else if hunger >= 18 && health < maxHealth {
            regenTimer += dt
            if regenTimer >= 4 { regenTimer = 0; health += 1; exhaustion += 6 }
        } else {
            regenTimer = 0
        }
        if hunger == 0 {
            starveTimer += dt
            if starveTimer >= 4 {
                starveTimer = 0
                // Easy stops at 5 hearts, normal at half a heart, hard can kill.
                let floorHP = difficulty == 1 ? 10 : (difficulty == 2 ? 1 : 0)
                if health > floorHP && difficulty > 0 { damage(1, "starved to death", bypassArmor: true, type: .starve) }
            }
        } else {
            starveTimer = 0
        }

        let respiration = Enchant.level(.respiration, inventory.armor[0])
        let turtle = Items.key(inventory.armor[0].item) == "turtle_helmet"
        if player.headInWater && !effects.has(.waterBreathing) && !effects.has(.conduitPower) {
            air -= Float(dt) / Float(respiration + 1)
            if air <= 0 {
                air = 0
                drownTimer += dt
                if drownTimer >= 1 { drownTimer = 0; damage(2, "drowned", bypassArmor: true, type: .drown) }
            }
        } else {
            if turtle && !player.headInWater { applyEffect(.waterBreathing, amp: 0, seconds: 10) }
            air = min(15, air + Float(dt) * 5)
            drownTimer = 0
        }
    }

    // World clock, fluids, furnaces, entities and autosave (runs whenever the game isn't paused).
    private func advance(_ dt: Double) {
        world.ships.update(Float(dt), game: self)
        mobs.update(Float(dt), game: self)
        drops.update(Float(dt), game: self)
        projectiles.update(Float(dt), game: self)
        armsTick(Float(dt))
        tnts.update(Float(dt), game: self)
        particles.update(Float(dt), world)
        ambientParticles(Float(dt))
        emberMotes(Float(dt))
        updateFlashes(Float(dt))
        if survival { timeSinceRest += Float(dt) }
        if sleeping > 0 {
            timeSinceRest = 0
            sleeping += Float(dt)
            if sleeping > 2.5 {
                // Skip to morning.
                let day = floor(time / DAY_LENGTH)
                time = (day + 1) * DAY_LENGTH + 0.01 * DAY_LENGTH
                sleeping = 0
                catGifts()
                onToast?("Good morning")
                weather.raining = false; weather.thundering = false; weather.rain = 0; weather.thunder = 0
                weather.rainTime = Float.random(in: 600...9000); weather.thunderTime = Float.random(in: 600...9000)
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
        dragonRespawnTick(Float(dt))
        hazardTick(Float(dt))
        effectTick(Float(dt))
        cloudTick(Float(dt))
        fangTick(Float(dt))
        bobberTick(Float(dt))
        fallingTick(Float(dt))
        jukeboxTick(Float(dt))
        mapTick()
        rocketTick(Float(dt))
        composterTick()
        musicTick(Float(dt))
        audioAmbientTick(Float(dt))
        siegeTick()
        ashenTick(Float(dt))
        advancementTick()
        weatherTick(Float(dt))
        world.rainLevel = wetWorld ? weather.rain : 0
        raidTimer += Float(dt)
        if raidTimer >= 1 { raidTick(raidTimer); patrolTick(raidTimer); blockSecondTick(); raidTimer = 0 }
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
        precipitationTicks()
        blockEntityTicks()
        gravityTick()
        beaconTicks += 1
        if beaconTicks >= 80 { beaconTicks = 0; beaconTick() }
        spawnerTick(0.05)
        world.redstone.tick()
        world.redstone.detectorCheck(mobs.mobs.filter { $0.kind == .minecart }.map { $0.pos })
        for (p, be) in world.blockEntities where be.kind == .brewing {
            if be.brewTime > 0 && be.brewIngredient == 0, !be.container[3].isEmpty { be.brewIngredient = be.container[3].item }
            if be.tickBrewing() { sfx(.brew, 0.5, at: V3(Float(p.x), Float(p.y), Float(p.z)) + 0.5) }
            // Bottle display follows the three bottle slots.
            let b = world.block(p.x, p.y, p.z)
            let base = Blocks.groupBase[Int(b)]
            guard Blocks.key(base) == "brewing_stand" else { continue }
            var m = 0
            for i in 0..<3 where !be.container[i].isEmpty { m |= 1 << i }
            if Int(b - base) != m { world.setBlock(p.x, p.y, p.z, base + BlockID(m)) }
        }
        for (p, be) in world.blockEntities where be.kind == .furnace {
            if be.tickFurnace() && be.mob.isEmpty {
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
