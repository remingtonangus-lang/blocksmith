import Foundation
import GameController
import simd

// Split-screen couch co-op (Future ideas #10). A second controller joins by pressing Menu (Start) while the game runs
// (or Pause > Split Screen); the screen splits top / bottom and each half is one player's view with its own HUD and
// menus. Everything that belongs to one local player lives in a seat (SeatState): Game.exchangeSeat swaps a seat's
// state with the live fields, so the whole game (survival, interaction, menus, the HUD) runs unchanged for whichever
// seat is being ticked or drawn. Seat 0 (keyboard + mouse + the first pad) is always the live one between frames.
// The world, mobs and time are shared: chunks stream round both players, each mob, item and arrow is updated by the
// seat nearest to it (so it chases, hurts and is picked up by that player), explosions reach everyone, and a
// dimension change (portal, respawn) takes both players along. Player 2 leaves from their pause menu.
struct SeatState {
    var player = Player()
    var input = InputState()
    var inventory = PlayerInventory()
    var effects = EffectSet()
    var lastHurtAt: Double = -10
    var lastHurtAmount = 0
    var bulletHit = false
    var cameraMode = 0
    var target: (hit: IVec3, normal: IVec3)?
    var menu: Menu?
    var carried = ItemStack.empty
    var menuCursor = 0
    var menuHover: MenuSlot?
    var screen = V2(1280, 400)
    var health = 20
    var hunger = 20
    var saturation: Float = 5
    var exhaustion: Float = 0
    var air: Float = 15
    var hurtFlash: Float = 0
    var alive = true
    var xpLevel = 0
    var xpPoints = 0
    var sleeping: Float = 0
    var bowCharge: Float = 0
    var portalTime: Float = 0
    var portalCooldown: Float = 0
    var onFire: Float = 0
    var fireDamageTimer: Float = 0
    var absorption: Float = 0
    var elytraWear: Float = 0
    var riding: Mob?
    var riderPush: Float = 0
    var blocking = false
    var lastPearl: Double = -10
    var rideInput = MoveInput()
    var levitateFromY: Float?
    var fovScale: Float = 1
    var equipAnim: Float = 0
    var stepVibe: Float = 0
    var freeze: Float = 0
    var freezeTick: Float = 0
    var scoping = false
    var brushProgress: Float = 0
    var shieldCooldown: Float = 0
    var shieldRaise: Float = 0
    var crossbowCharge: Float = 0
    var tridentCharge: Float = 0
    var spearCharge: Float = 0
    var spearHitAt: [ObjectIdentifier: Float] = [:]
    var bobber: Bobber?
    var contactTimer: Float = 0
    var walkBob: Float = 0
    var walkAmount: Float = 0
    var regenTimer: Double = 0
    var starveTimer: Double = 0
    var drownTimer: Double = 0
    var mining: IVec3?
    var mineProgress: Float = 0
    var mineSoundTimer: Float = 0
    var eatProgress: Float = 0
    var attackTimer: Float = 10
    var swing: Float = 0
    var stepDist: Float = 0
    var wasInWater = false
    var breakCooldown: Double = 0
    var placeCooldown: Double = 0
    var lastSpaceTap: Double = -1
    var toastText = ""
    var toastTime: Double = -100
    var prevPad = PadSnapshot()
    var lastDeath: V3?
    var deathScore = 0
    var timeSinceRest: Float = 0
    var lastHorn: Double = -100        // their own horn and wind-charge cooldowns (shared, one player's use blocked the other's)
    var lastWind: Double = -10
    var mapRow = 0                     // their held map's scan row (shared, two held maps each filled every other row)
    var hideHUD = false                // F1 / F3 are per half (player 1's hid player 2's HUD too)
    var showDebug = false
    var bookTab: CraftCategory = .craftable    // the crafting book's last tab, Show All and craft flash (shared statics)
    var bookShowAll = true
    var bookFlashItem: ItemID = 0
    var bookFlashAt: Double = -10
    // Per-player state kept outside Game.
    var padLook = PadLook()
    var wheel = WeaponWheel()
    var menuNav = MenuNav()
    var turrets = Turrets()
    var combatHUD = CombatHUD()
    var gun = GunSeat()
    var ship = ShipSeat()
    var pad = PadSeat()
}

// Controller state kept in statics (toggle sneak, auto-sprint, drop hold, sticky aim, the map's View hold).
struct PadSeat {
    var sneakLatched = false, forwardTime: Float = 0, dropPressedAt: Double = -1, dropStackDone = false
    var aimLast: (hit: IVec3, normal: IVec3)?
    var snapTarget: Mob?
    var snapTime: Float = 0
    var mapPrevPad = PadSnapshot()
    var viewDown: Double = -1, mapOpened = false

    mutating func exchange() {
        swap(&sneakLatched, &PadActions.sneakLatched); swap(&forwardTime, &PadActions.forwardTime)
        swap(&dropPressedAt, &PadActions.dropPressedAt); swap(&dropStackDone, &PadActions.dropStackDone)
        let l = aimLast; aimLast = AimAssist.last; AimAssist.last = l
        let t = snapTarget; snapTarget = AimAssist.snapTarget; AimAssist.snapTarget = t
        swap(&snapTime, &AimAssist.snapTime)
        swap(&mapPrevPad, &MapMenu.prevPad)
        swap(&viewDown, &MapInput.viewDown); swap(&mapOpened, &MapInput.opened)
    }
}

// The player's own gun handling (Armory holds the rounds in flight too, which stay shared).
struct GunSeat {
    var cooldown: Float = 0, reload: Float = 0, reloadGun = -1, aim: Float = 0, kick: Float = 0, recoilDebt: Float = 0
    var bloom: Float = 0, sinceShot: Float = 10, hitMarker: Float = 0, heldGun = -1, heldSlot = -1, placeCheck: Float = 0

    mutating func exchange(_ a: Armory) {
        swap(&cooldown, &a.cooldown); swap(&reload, &a.reload); swap(&reloadGun, &a.reloadGun); swap(&aim, &a.aim)
        swap(&kick, &a.kick); swap(&recoilDebt, &a.recoilDebt); swap(&bloom, &a.bloom); swap(&sinceShot, &a.sinceShot)
        swap(&hitMarker, &a.hitMarker); swap(&heldGun, &a.heldGun); swap(&heldSlot, &a.heldSlot); swap(&placeCheck, &a.placeCheck)
    }
}

// The player's ship controls (the helm they hold, the ship they stand on, the ship block they aim at or dig).
struct ShipSeat {
    var pilot: Ship?
    var aboard: Ship?
    var target: (ship: Ship, cell: IVec3, normal: IVec3)?
    var mineCell: (Ship, IVec3)?
    var mineProgress: Float = 0
    var breakCooldown: Float = 0
    // The rider's deck-relative motion (stream B's riding: velocity kept in the deck's frame tick to tick).
    var riderShip: Ship?
    var riderVel = V3(0, 0, 0)
    var riderOut = V3(0, 0, 0)
    var riderAt = -9

    mutating func exchange(_ m: ShipManager) {
        let p = pilot; pilot = m.pilot; m.pilot = p
        let a = aboard; aboard = m.aboard; m.aboard = a
        let t = target; target = m.target; m.target = t
        let c = mineCell; mineCell = m.mineCell; m.mineCell = c
        swap(&mineProgress, &m.mineProgress); swap(&breakCooldown, &m.breakCooldown)
        let rs = riderShip; riderShip = m.riderShip; m.riderShip = rs
        swap(&riderVel, &m.riderVel); swap(&riderOut, &m.riderOut); swap(&riderAt, &m.riderAt)
    }
}

final class Coop {
    // The seat whose turn it is is a second one: it always plays on a controller (seat 0 may be on the keyboard and
    // mouse), so prompts and aim assist treat it as on a pad (they followed player 1's last input device).
    static var secondSeat = false
    static var liveSeat = 0                 // the seat whose turn it is (rounds a player fires stay with that seat)

    static let maxSeats = 2
    // slots[i] holds seat i's state while another seat is live; the live seat's slot is nil.
    private(set) var slots: [SeatState?] = [nil]
    private(set) var current = 0
    var active: Bool { slots.count > 1 }
    var seatCount: Int { slots.count }
    private var pads: [Int: GCController] = [:]       // the controller each seat > 0 plays with
    var simulated: [Int: PadSnapshot] = [:]            // harness input for seats > 0
    private var joinScan: Float = 0
    private var padCheck = 0
    private var otherPads = 0
    private var parked: SeatState?                     // player 2's state after leaving (rejoining picks it up again)
    private var savedInventoryCallback: ((Bool) -> Void)?
    var lastDim: Dim?

    // Makes seat i the live one (no-op if it already is). Works from any seat.
    func switchTo(_ i: Int, _ g: Game) {
        guard i != current, i < slots.count, var s = slots[i] else { return }
        if current == 0 { savedInventoryCallback = g.onInventoryChanged }
        g.exchangeSeat(&s)
        slots[i] = nil
        slots[current] = s
        current = i
        Coop.secondSeat = i > 0
        Coop.liveSeat = i
        // Menus opening and closing for other seats must not release or capture the mouse.
        g.onInventoryChanged = i == 0 ? savedInventoryCallback : nil
    }

    // Runs body with seat i live, then returns to the seat that was live.
    func withSeat(_ i: Int, _ g: Game, _ body: () -> Void) {
        let back = current
        switchTo(i, g)
        body()
        switchTo(back, g)
    }

    // Runs body for every seat (the live one first).
    func eachSeat(_ g: Game, _ body: () -> Void) {
        body()
        guard active else { return }
        let me = current
        for i in 0..<slots.count where i != me { withSeat(i, g, body) }
    }

    func seatPlayer(_ i: Int, _ g: Game) -> Player { i == current || i >= slots.count ? g.player : (slots[i]?.player ?? g.player) }

    // The seat whose player is nearest to a point (horizontal distance).
    func nearestSeat(_ p: V3, _ g: Game) -> Int {
        guard active else { return 0 }
        var best = 0
        var bd = Float.greatestFiniteMagnitude
        for i in 0..<slots.count {
            let q = seatPlayer(i, g).pos
            let d = (q.x - p.x) * (q.x - p.x) + (q.z - p.z) * (q.z - p.z)
            if d < bd { bd = d; best = i }
        }
        return best
    }

    func nearestPlayerPos(_ p: V3, _ g: Game) -> V3 { seatPlayer(nearestSeat(p, g), g).pos }

    // Seat 0's view of the other player (the extra streaming centre).
    func otherPlayerPos(_ g: Game) -> V3? {
        guard active else { return nil }
        return seatPlayer(current == 0 ? 1 : 0, g).pos
    }

    // MARK: Joining and leaving

    func join(_ g: Game, controller: GCController?) {
        guard slots.count < Coop.maxSeats else { return }
        var s = parked ?? SeatState()
        parked = nil
        let p0 = g.player
        let right = V3(cosf(p0.yaw), 0, -sinf(p0.yaw))
        s.player.pos = g.settleSpawn(p0.pos + right * 1.5)
        s.player.yaw = p0.yaw
        s.player.pitch = 0
        s.player.flying = p0.flying && !g.survival
        s.player.vel = .zero
        s.player.airPeak = s.player.pos.y
        if !g.survival && s.inventory.main.slots.allSatisfy({ $0.isEmpty }) {
            let start = ["grass_block", "dirt", "stone", "cobblestone", "oak_planks", "oak_log", "glass", "torch", "crafting_table"]
            for (i, n) in start.enumerated() where Items.has(n) { s.inventory.main[i] = ItemStack(Items.id(n), 64) }
        }
        s.menu = nil
        slots.append(s)
        if let c = controller { pads[slots.count - 1] = c }
        lastDim = g.dim.dim
        g.onToast?("Player 2 joined: split screen")
    }

    // Player 2 leaves (their state is kept for this session in case they rejoin).
    func leave(_ g: Game) {
        guard active else { return }
        // Their open screen closes properly first: its cursor item and grid go back to their inventory (dropping the
        // menu lost them).
        withSeat(1, g) { if !(g.menu is PauseMenu) { g.closeMenu() } }     // (a pause menu holds nothing; closing it unpauses)
        switchTo(0, g)
        if var s = slots[1] {
            s.menu = nil
            parked = s
        }
        slots.removeLast()
        pads[1] = nil
        simulated[1] = nil
        g.world.extraCenter = nil
        if !g.paused && g.menu is PauseMenu { g.menu = nil }        // the shared pause ended with player 2's choice
        g.onToast?("Player 2 left")
    }

    var secondPadAvailable: Bool {
        if simulated[1] != nil { return true }
        let first = PadManager.shared.controller ?? GCController.current
        return GCController.controllers().contains { $0 !== first && $0.extendedGamepad != nil }
    }

    // A second controller joins with Menu (Start). Scanned four times a second while alone.
    func pollJoin(_ g: Game, _ dt: Float) {
        if let s = simulated[1], s.menu { if !active { join(g, controller: nil) }; return }
        guard !active else { return }
        joinScan -= dt
        guard joinScan <= 0 else { return }
        joinScan = 0.25
        let first = PadManager.shared.controller ?? GCController.current
        var others = 0
        for c in GCController.controllers() where c !== first {
            guard let gp = c.extendedGamepad else { continue }
            others += 1
            if gp.buttonMenu.isPressed { join(g, controller: c); return }
        }
        // A second controller just connected: say how to join (once per connection).
        if others > otherPads && first != nil && g.menu == nil { g.onToast?("Second controller: press its Menu button for split screen") }
        otherPads = others
    }

    // Seat i's controller this frame, with the button mapping applied (nil when it has none).
    func readSeatPad(_ i: Int) -> PadSnapshot? {
        if let s = simulated[i] { return PadMap.apply(s) }
        padCheck += 1
        // Still connected? (checked twice a second: listing the controllers allocates)
        if padCheck % 30 == 1 && (pads[i]?.extendedGamepad == nil || !GCController.controllers().contains(where: { $0 === pads[i] })) {
            // Lost (or never had) its pad: take any other connected one that seat 0 isn't using.
            let first = PadManager.shared.controller ?? GCController.current
            let taken = Array(pads.values)
            let pick = GCController.controllers().first { c in c !== first && c.extendedGamepad != nil && !taken.contains { $0 === c } }
            pads[i] = pick
        }
        guard let g = pads[i]?.extendedGamepad else { return nil }
        var p = PadSnapshot()
        p.lx = g.leftThumbstick.xAxis.value
        p.ly = g.leftThumbstick.yAxis.value
        p.rx = g.rightThumbstick.xAxis.value
        p.ry = g.rightThumbstick.yAxis.value
        p.lt = g.leftTrigger.value
        p.rt = g.rightTrigger.value
        p.a = g.buttonA.isPressed
        p.b = g.buttonB.isPressed
        p.x = g.buttonX.isPressed
        p.y = g.buttonY.isPressed
        p.lb = g.leftShoulder.isPressed
        p.rb = g.rightShoulder.isPressed
        p.l3 = g.leftThumbstickButton?.isPressed ?? false
        p.r3 = g.rightThumbstickButton?.isPressed ?? false
        p.menu = g.buttonMenu.isPressed
        p.view = g.buttonOptions?.isPressed ?? false
        p.up = g.dpad.up.isPressed
        p.down = g.dpad.down.isPressed
        p.left = g.dpad.left.isPressed
        p.right = g.dpad.right.isPressed
        if Settings.shared.southpaw { (p.lx, p.rx, p.ly, p.ry) = (p.rx, p.lx, p.ry, p.ly) }
        return PadMap.apply(p)
    }

    // Both players asleep (the night skips only then).
    func othersAsleep(_ g: Game) -> Bool {
        guard active else { return true }
        for i in 0..<slots.count where i != current { if let s = slots[i], s.sleeping < 2 { return false } }
        return true
    }

    func wakeOthers() {
        for i in 0..<slots.count where slots[i] != nil { slots[i]!.sleeping = 0 }
    }

    // A dimension change (portal, respawn, the Hollow's exit) takes every other player to the one who travelled.
    func followDimension(_ g: Game) {
        let at = g.player.pos
        let right = V3(cosf(g.player.yaw), 0, -sinf(g.player.yaw))
        let fwd = V3(-sinf(g.player.yaw), 0, -cosf(g.player.yaw))
        for i in 0..<slots.count where i != current {
            guard let p = slots[i]?.player else { continue }
            // Beside the traveller where the body fits (a fixed step to the right could be inside the portal frame or a
            // wall at the far end); on the traveller's own spot if nothing nearby is free (players don't collide).
            var spot = at
            let r: V3 = right * 1.2, f: V3 = fwd * 1.2, up = V3(0, 1, 0)
            let offs: [V3] = [r, -r, f, -f, r + up, up - r]
            for o in offs {
                let q: V3 = at + o
                let lo = V3(q.x - p.halfW, q.y, q.z - p.halfW), hi = V3(q.x + p.halfW, q.y + p.height, q.z + p.halfW)
                if !g.world.collides(lo, hi) { spot = q; break }
            }
            p.pos = spot
            p.vel = .zero
            p.airPeak = p.pos.y
            p.pendingFall = 0
            slots[i]!.ship = ShipSeat()
            slots[i]!.riding = nil
        }
        lastDim = g.dim.dim
    }

    // Player 2's things are saved with the world (WorldMeta extra "coop2") and wait for them to join again.
    struct Saved: Codable { var inventory: PlayerInventory.Saved; var health: Int; var hunger: Int; var xpLevel: Int; var xpPoints: Int }
    var savedSecond: Saved? {
        guard let s = active ? slots[1] : parked else { return nil }
        return Saved(inventory: s.inventory.saved, health: s.health, hunger: s.hunger, xpLevel: s.xpLevel, xpPoints: s.xpPoints)
    }
    func restoreSecond(_ v: Saved) {
        guard !active else { return }
        var s = SeatState()
        s.inventory.load(v.inventory)
        s.health = max(1, min(20, v.health))
        s.hunger = max(0, min(20, v.hunger))
        s.xpLevel = v.xpLevel
        s.xpPoints = v.xpPoints
        parked = s
    }

    // Where a sound at p is played for the single audio listener (player 1's ears): sounds nearer another player are
    // moved next to player 1 by the same offset, so each player hears what happens beside them.
    func heardAt(_ p: V3, _ g: Game) -> V3 {
        let i = nearestSeat(p, g)
        guard i != 0 else { return p }
        return seatPlayer(0, g).eye + (p - seatPlayer(i, g).eye)
    }

    // Split screen with the players close together: one shadow map centred between them serves both views (it covers
    // 64 blocks either side), so it isn't re-rendered for each view. nil when apart (each view centres its own).
    func shadowFocus(_ g: Game) -> V3? {
        guard active else { return nil }
        let a = seatPlayer(0, g).eye, b = seatPlayer(1, g).eye
        let d = b - a
        guard d.x * d.x + d.z * d.z < 40 * 40 && abs(d.y) < 32 else { return nil }
        return (a + b) * 0.5
    }

    // The other seats' bodies, drawn in each view.
    func writeOthers(_ g: Game, eye: V3, daylight: Float, into out: UnsafeMutablePointer<MobVert>, capacity: Int) -> Int {
        guard active else { return 0 }
        var n = 0
        let me = current
        for i in 0..<slots.count where i != me {
            withSeat(i, g) {
                n += writePlayerModel(g, eye: eye, daylight: daylight, into: out + n, capacity: capacity - n)
            }
        }
        return n
    }
}

extension Game {
    // Split-screen frame: each seat ticks in turn (seat 0 also runs the shared world), then seat 0 is live again.
    func coopTick(_ rawDt: Double) {
        if coop.lastDim == nil { coop.lastDim = dim.dim }
        for i in 0..<coop.seatCount {
            coop.switchTo(i, self)
            // One pause covers everyone: once it ends, every seat's pause menu closes.
            if !paused && menu is PauseMenu { menu = nil }
            tickSeat(rawDt)
            if dim.dim != coop.lastDim { coop.followDimension(self) }
        }
        coop.switchTo(0, self)
    }

    // A second seat's share of the frame: its own mobs, pickups, arrows, hazards and effects (the shared world ran in
    // seat 0's turn).
    func coopAdvance(_ dt: Double) {
        let f = Float(dt)
        mobs.update(f, game: self)
        drops.update(f, game: self)
        projectiles.update(f, game: self)
        portalTick(f)
        endPortalTick()                                   // they can step into a Hollow rift or gateway too
        hazardTick(f)
        effectTick(f)
        // Their own fishing bobber and held map (both ran only in seat 0's turn: player 2's bobber hung where it was
        // cast and never bit, their map never filled).
        bobberTick(f)
        mapTick()
        // Their gun: recoil, bloom and hit marker recover, and the rounds nearest them fly (Armory.update splits them
        // by seat; enemy rounds near player 2 could not hit them and their kick never settled).
        armsTick(f)
        // Torch smoke, dripping leaves, Emberdeep motes... round their own view (they only appeared round player 1).
        ambientParticles(f)
        emberMotes(f)
        if survival { timeSinceRest += f }
        if sleeping > 0 { sleeping += f; timeSinceRest = 0 }
    }

    // Whether the live seat updates the thing at p this frame (always alone).
    @inline(__always) func seatOwns(_ p: V3) -> Bool { !coop.active || coop.nearestSeat(p, self) == coop.current }

    // Swaps the per-player state kept outside Game (exchangeSeat calls this last).
    func exchangeSeatExtras(_ s: inout SeatState) {
        swap(&PadLook.shared, &s.padLook)
        swap(&WeaponWheel.shared, &s.wheel)
        swap(&MenuNav.shared, &s.menuNav)
        swap(&Turrets.shared, &s.turrets)
        swap(&CombatHUD.shared, &s.combatHUD)
        swap(&CraftingBookMenu.lastTab, &s.bookTab); swap(&CraftingBookMenu.showAll, &s.bookShowAll)
        swap(&CraftBook.flashItem, &s.bookFlashItem); swap(&CraftBook.flashAt, &s.bookFlashAt)
        s.gun.exchange(arms)
        s.pad.exchange()
        s.ship.exchange(world.ships)
    }
}

// Harness (--coop --cooptest): seats keep their own state, player 2's pad moves only player 2, chunks stream round a
// far-away player 2, mobs and blasts near player 2 belong to player 2, one pause covers both, and player 2 can leave.
enum CoopTest {
    static func run(_ g: Game) -> Int {
        var fails = 0
        var failed: [String] = []
        func check(_ ok: Bool, _ what: String) { print("\(ok ? "PASS" : "FAIL") coop: \(what)"); if !ok { fails += 1; failed.append(what) } }
        let c = g.coop
        check(c.active && c.seatCount == 2, "player 2 joined (2 seats)")
        let p1 = g.player
        var p2: Player?
        c.withSeat(1, g) { p2 = g.player }
        check(p2 != nil && p2 !== p1, "player 2 has a body of its own")
        check(simd_length((p2?.pos ?? V3(0, 0, 0)) - p1.pos) < 8, "player 2 starts beside player 1")
        check(g.player === p1 && c.current == 0, "player 1 is live again after a seat swap")
        // Per-player state.
        let h0 = g.health
        g.health = 13
        var h2 = 0
        c.withSeat(1, g) { h2 = g.health; g.health = 17 }
        var h2b = 0
        c.withSeat(1, g) { h2b = g.health; g.health = 20 }
        check(h2 == 20 && h2b == 17 && g.health == 13, "health is per player (player 1 \(g.health), player 2 \(h2) then \(h2b))")
        g.health = h0
        var inv2: PlayerInventory?
        c.withSeat(1, g) { inv2 = g.inventory }
        check(inv2 != nil && inv2 !== g.inventory, "inventories are separate")
        // Player 2's stick moves player 2 only.
        g.paused = false
        p1.flying = true; p1.vel = .zero
        let a1 = p1.pos
        p2?.flying = true
        let a2 = p2?.pos ?? .zero
        var s = PadSnapshot()
        s.ly = 1
        c.simulated[1] = s
        for _ in 0..<60 { g.tick(1.0 / 60) }
        c.simulated[1] = PadSnapshot()
        g.tick(1.0 / 60)
        let b2 = p2?.pos ?? .zero
        let moved2 = simd_length(V2(b2.x - a2.x, b2.z - a2.z)), moved1 = simd_length(V2(p1.pos.x - a1.x, p1.pos.z - a1.z))
        check(moved2 > 2 && moved1 < 0.5, String(format: "player 2's stick moves player 2 (%.1f blocks) and not player 1 (%.2f)", moved2, moved1))
        // Streaming round a far-away player 2.
        p2?.pos.x += 320
        p2?.vel = .zero
        g.tick(1.0 / 60)
        check(g.world.extraCenter != nil, "chunks stream round player 2 as well")
        let far = p2?.pos ?? .zero
        let t0 = Date()
        while !g.world.isLoaded(Int(floor(far.x)), Int(floor(far.z))) && Date().timeIntervalSince(t0) < 20 {
            p2?.pos = far; p2?.vel = .zero
            g.tick(1.0 / 60)
            usleep(4000)
        }
        check(g.world.isLoaded(Int(floor(far.x)), Int(floor(far.z))), String(format: "player 2's chunk loads 320 blocks from player 1 (%.1f s)", Date().timeIntervalSince(t0)))
        check(g.world.isLoaded(Int(floor(p1.pos.x)), Int(floor(p1.pos.z))), "player 1's chunks stay loaded")
        // Things beside player 2 are updated in player 2's turn.
        p2?.pos = far
        check(!g.seatOwns(far), "player 1's turn leaves what is beside player 2 alone")
        var owns2 = false
        c.withSeat(1, g) { owns2 = g.seatOwns(far) }
        check(owns2, "player 2's turn updates what is beside player 2")
        // A blast beside player 2 hurts player 2, not player 1 (player 2 on the ground there: flown 320 blocks at player 1's
        // height they were inside a hill and the blast had no line of sight, run 509).
        var spot = far
        spot.y = Float(g.world.topY(Int(floor(far.x)), Int(floor(far.z))) + 1)
        p2?.pos = spot; p2?.vel = .zero; p2?.flying = false
        g.survival = true
        let hp1 = g.health
        Explosion.explode(at: spot + V3(1.5, 0.6, 0), power: 2, game: g, breakBlocks: false)
        var hp2 = 20
        c.withSeat(1, g) { hp2 = g.health; g.health = 20; g.player.vel = .zero }
        check(hp2 < 20 && g.health == hp1, "a blast beside player 2 hurts player 2 (\(hp2)) and not player 1 (\(g.health))")
        // An enemy round fired at player 2 hits player 2 (rounds flew only in player 1's turn and only hit player 1).
        c.withSeat(1, g) { g.health = 20; g.lastHurtAt = -10 }
        // Straight down from over their head: player 2 stands on the column's top block, so the line is open sky (fired
        // across from the side, a hill or a trunk could stop it first).
        let above2: V3 = c.seatPlayer(1, g).pos + V3(0, 6, 0)
        g.arms.slugs.append(Slug(pos: above2, vel: V3(0, -60, 0), kind: .bullet, damage: 3, fromPlayer: false,
                                 shooter: nil, by: "a test", life: 2, gravity: 0))
        for _ in 0..<12 { g.tick(1.0 / 60) }
        var shot2 = 20
        c.withSeat(1, g) { shot2 = g.health; g.health = 20; g.player.vel = .zero }
        check(shot2 < 20 && g.arms.slugs.isEmpty, "an enemy round fired at player 2 hits player 2 (\(shot2))")
        // Conjurer fangs under player 2 bite player 2 (world hazards hurt only player 1 before).
        c.withSeat(1, g) { g.lastHurtAt = -10 }
        let hpBefore = g.health
        g.fangs.append(Fang(pos: c.seatPlayer(1, g).pos, delay: 0, owner: nil))
        for _ in 0..<3 { g.tick(1.0 / 60) }
        var bit2 = 20
        c.withSeat(1, g) { bit2 = g.health; g.health = 20; g.player.vel = .zero }
        check(bit2 < 20 && g.health == hpBefore, "conjurer fangs bite player 2 (\(bit2)), not player 1")
        // Player 1's ender pearl landing beside player 2 takes player 1 there and leaves player 2 alone (thrown items
        // flew in the turn of the player nearest them: player 2 was teleported).
        let p2at = c.seatPlayer(1, g).pos
        let p1home = p1.pos
        let pearl = Fireball(p2at + V3(1.5, 3, 0), V3(0, -20, 0), big: false, byPlayer: true)    // thrown in seat 0's turn
        pearl.kind = .pearl
        g.projectiles.fireballs.append(pearl)
        for _ in 0..<20 { g.tick(1.0 / 60) }
        let p2after = c.seatPlayer(1, g).pos
        check(simd_length(p1.pos - p2at) < 4 && simd_length(p2after - p2at) < 0.5,
              String(format: "player 1's pearl moves player 1 (%.0f blocks from player 2) and not player 2 (%.1f)", simd_length(p1.pos - p2at), simd_length(p2after - p2at)))
        p1.pos = p1home; p1.vel = .zero
        g.health = 20
        // A pressure plate under player 2 counts them (plates, tripwires and pistons saw only player 1).
        c.withSeat(1, g) { g.player.pos.y = floor(g.player.pos.y); g.player.vel = .zero }      // feet on the cell floor
        let p2feet = c.seatPlayer(1, g).pos
        let plate = IVec3(Int(floor(p2feet.x)), Int(floor(p2feet.y)), Int(floor(p2feet.z)))
        let pressing = g.entitiesOn(plate, items: false)
        check(pressing >= 1, "a pressure plate under player 2 counts them (\(pressing))")
        g.survival = false
        p1.vel = .zero
        // One pause for both.
        var m = PadSnapshot()
        m.menu = true
        c.simulated[1] = m
        g.tick(1.0 / 60)
        c.simulated[1] = PadSnapshot()
        g.tick(1.0 / 60)
        var menu2: Menu?
        c.withSeat(1, g) { menu2 = g.menu }
        check(g.paused && menu2 is PauseMenu, "player 2's Menu button pauses the game on player 2's half")
        g.paused = false
        g.tick(1.0 / 60)
        c.withSeat(1, g) { menu2 = g.menu }
        check(!g.paused && menu2 == nil && g.menu == nil, "resuming closes both pause menus")
        // Saved with the world.
        var marked = false
        c.withSeat(1, g) { g.inventory.main[20] = ItemStack(Items.id("stick"), 7); marked = true }
        let sv = c.savedSecond
        check(marked && sv?.inventory.main[20].count == 7 && sv?.health == 20, "player 2's things go into the world save")
        c.withSeat(1, g) { g.inventory.main[20] = .empty }
        // Leaving and rejoining.
        c.leave(g)
        check(!c.active && g.world.extraCenter == nil && g.player === p1, "player 2 leaves; player 1 plays on")
        c.simulated[1] = PadSnapshot()
        c.join(g, controller: nil)
        var back: Player?
        c.withSeat(1, g) { back = g.player }
        check(c.active && back === p2 && simd_length((back?.pos ?? .zero) - p1.pos) < 8, "player 2 rejoins beside player 1 with the same body")
        // The failures again last (the fast lane keeps only the end of a shot's output).
        print("cooptest: \(fails == 0 ? "PASS" : "\(fails) FAILED: " + failed.joined(separator: "; "))")
        return fails
    }
}
