import Foundation
import simd

// The Meridian Navy (backlog A3): the frigates' faction, its super soldiers, their counters, and a captured frigate's
// radar. All names are Blocksmith's own (tools/coined-terms.txt keeps the reference series' words out).
//   Aegis Marines  the navy's heavies (Meridian soldierIronclad posts, and one in every boarding party): heavy plate
//                  (A2's Hannibal class) under a regenerating energy shield of 40 that soaks every hit. A hit makes it
//                  flare (a blue sheen), at zero it pops (a burst) and the plate takes the hits; 4 s after the last
//                  hit it recharges at 10 a second with a rising tone.
//   shield breakers the Pulse Charge (copper, redstone, a radar module; thrown) pops every shield within 5 blocks and
//                  holds it down 8 s; arc-gun beams do triple damage to a shield.
//   boarding       an AI Meridian frigate hunting the player within 60 blocks sends a boarding party in a launch (the
//                  troop-drop path, CapitalShips.callDropship): an Aegis Marine and two marines set down on dry ground
//                  by the player, never over open water; at most two parties a frigate, the count saved with its
//                  region (navyparties.json) so a reload does not hand it fresh ones.
//   Aegis Marines  stand a fifth taller than a trooper and move a third faster.
//   frigate radar  the pilot of a captured warship reads a radar: Greywall bases, Capital citadels and cities and
//                  enemy warships within 1,500 blocks, with bearings, marked on the map.
enum Navy {
    static let shieldMax: Float = 40
    static let rechargeDelay: Float = 4
    static let rechargeRate: Float = 10
    static let pulseRadius: Float = 5
    static let pulseLock: Float = 8
    static let radarRange: Float = 1500
    static let partyReach: Float = 60
    static let maxParties = 2
    static let pulseKey = "pulse_charge"
}

extension Mob {
    // An Aegis Marine: a Meridian heavy (it gets its shield and plate the first time it thinks).
    var isAegis: Bool { kind == .soldierIronclad && faction == Faction.meridian.rawValue }

    // Per AI update of a soldier (soldierAI): the shield's recharge and its flare / pop effects.
    func navyTick(_ dt: Float, _ g: Game) {
        if shieldMax == 0 {
            guard isAegis else { return }
            shieldMax = Navy.shieldMax; shield = Navy.shieldMax
            if troop <= 0 { setTroop(.hannibal, rearm: false) }
            scale = 1.2                                                  // T8: a fifth taller than a trooper
        }
        shieldLock = max(0, shieldLock - dt)
        shieldIdle += dt
        let body = pos + V3(0, height * 0.55, 0)
        if shieldFx == 1 {
            for _ in 0..<6 {
                let d = simd_normalize(V3(Rand.float(in: -1...1), Rand.float(in: -0.6...1), Rand.float(in: -1...1)) + V3(0, 0.01, 0))
                g.particles.add(Particle(pos: body + d * 0.7, vel: d * 0.6, life: 0.22, maxLife: 0.22, layer: Int(Tex.id("smoke")), uv0: V2(0, 0),
                                         uvSize: 1, size: 0.09, gravity: 0, color: V3(0.6, 1.6, 2.6), collide: false, glow: true))
            }
            g.sfx(.bulletImpact(.amethyst), 0.7, at: body)
        } else if shieldFx == 2 {
            for _ in 0..<24 {
                let d = simd_normalize(V3(Rand.float(in: -1...1), Rand.float(in: -1...1), Rand.float(in: -1...1)) + V3(0, 0.01, 0))
                g.particles.add(Particle(pos: body + d * 0.5, vel: d * 4, life: 0.35, maxLife: 0.35, layer: Int(Tex.id("smoke")), uv0: V2(0, 0),
                                         uvSize: 1, size: 0.1, gravity: 0, color: V3(0.8, 1.8, 3), collide: false, glow: true))
            }
            g.addFlash(at: body, color: V3(1.2, 2.4, 3.4), radius: 5, life: 0.15)
            g.sfx(.glassBreak, 1, at: body)
        }
        shieldFx = 0
        if shield < shieldMax && shieldIdle >= Navy.rechargeDelay && shieldLock <= 0 {
            if shield <= 0 { g.sfx(.click, 0.9, at: body); g.sfx(.beaconActivate, 0.5, at: body) }   // the recharge starts with a rising tone
            shield = min(shieldMax, shield + Navy.rechargeRate * dt)
        }
    }

    // A hit on a shielded mob (Mob.hit): the shield soaks it; what's left after a pop goes through. Returns the damage
    // still to apply (0: all soaked).
    func shieldHit(_ damage: Int) -> Int {
        guard shieldMax > 0, damage > 0 else { return damage }
        shieldIdle = 0
        guard shield > 0 else { return damage }
        let d = Float(damage)
        if d < shield { shield -= d; shieldFx = max(shieldFx, 1); return 0 }
        let over = Int(d - shield)
        shield = 0; shieldFx = 2
        return over
    }
}

extension Game {
    // A Pulse Charge bursts: every shield within 5 blocks pops and stays down 8 s.
    func pulseBurst(at p: V3) {
        for m in mobs.mobs where m.shieldMax > 0 && simd_length(m.pos + V3(0, 1, 0) - p) < Navy.pulseRadius {
            if m.shield > 0 { m.shieldFx = 2 }
            m.shield = 0; m.shieldLock = Navy.pulseLock; m.shieldIdle = 0
        }
        for _ in 0..<30 {
            let a = Rand.float(in: 0..<(2 * .pi))
            particles.add(Particle(pos: p, vel: V3(cosf(a), Rand.float(in: -0.2...0.4), sinf(a)) * 9, life: 0.4, maxLife: 0.4, layer: Int(Tex.id("smoke")),
                                   uv0: V2(0, 0), uvSize: 1, size: 0.12, gravity: 0, color: V3(0.7, 1.6, 3), collide: false, glow: true))
        }
        addFlash(at: p, color: V3(1.5, 2.6, 4), radius: 9, life: 0.25)
        sfx(.glassBreak, 1.2, at: p)
    }

    // Right-click with a Pulse Charge: thrown like a grenade, it bursts on its fuse or where it lands.
    func pulseChargeUse() -> Bool {
        let held = inventory.main[inventory.selected]
        guard !held.isEmpty, Items.has(Navy.pulseKey), held.item == Items.id(Navy.pulseKey) else { return false }
        let dir = player.look
        var s = Slug(pos: player.eye + dir * 0.5, vel: dir * 16 + V3(0, 3, 0), kind: .grenade, damage: 0, fromPlayer: true,
                     shooter: nil, by: "a Pulse Charge", life: 1.6, gravity: 20)
        s.pulse = true
        arms.spawn(s)
        if survival { inventory.main[inventory.selected].count -= 1; if inventory.main[inventory.selected].count <= 0 { inventory.main[inventory.selected] = .empty } }
        sfx(.grenadeBounce, 0.6, at: player.eye)
        return true
    }

    // A captured warship's pilot reads a radar.
    var frigateRadar: Bool {
        guard let s = world.ships.pilot, s.captured, s.isFlyingCapital || s.role == "crawler" else { return false }
        return true
    }

    // The frigate radar's contacts: bases and warships within 1,500 blocks.
    func frigateContacts() -> [RadarContact] {
        var out: [RadarContact] = []
        guard dim.dim == .overworld, let sc = world.gen.structures else { return out }
        let p = V2(player.pos.x, player.pos.z)
        for (k, n, spacing) in [(Greywall.kind, "Greywall base", Greywall.spacing), ("military_base", "Capital Citadel", 0), ("capital_city", "Capital City", 0)] {
            guard let type = sc.types.first(where: { $0.name == k }) else { continue }
            let span = (spacing > 0 ? spacing : type.spacing) * CS
            let r = Int(Navy.radarRange) / span + 1
            let rx0 = floorDiv(Int(p.x), span), rz0 = floorDiv(Int(p.y), span)
            for rz in (rz0 - r)...(rz0 + r) { for rx in (rx0 - r)...(rx0 + r) {
                guard let s = sc.start(type, regionX: rx, regionZ: rz) else { continue }
                let c = V2(Float(s.min.x + s.max.x) / 2, Float(s.min.z + s.max.z) / 2)
                guard simd_length(c - p) <= Navy.radarRange else { continue }
                let name = k == Greywall.kind ? Greywall.Tier.of(s).name : n
                out.append(RadarContact(name: name, kind: k, x: Int(c.x), z: Int(c.y)))
            } }
        }
        let names = ["capfrigate": "Meridian Frigate", "warfrigate": "Stormwarden Frigate", "crawler": "Ironback Crawler"]
        for s in world.ships.list where s.parent == nil && !s.wrecked && !s.captured {
            guard let r = s.role, let n = names[r], simd_length(V2(s.pos.x, s.pos.z) - p) <= Navy.radarRange else { continue }
            out.append(RadarContact(name: n, kind: "vessel_" + r, x: Int(s.pos.x), z: Int(s.pos.z)))
        }
        out.sort { simd_length(V2(Float($0.x), Float($0.z)) - p) < simd_length(V2(Float($1.x), Float($1.z)) - p) }
        return Array(out.prefix(8))
    }

    // The bases a frigate radar picks up go on the map (the warships it shows move on and are not marked).
    func markRadarSites(_ cs: [RadarContact]) {
        for c in cs where !c.kind.hasPrefix("vessel_") {
            MapCache.shared.discover(self, kind: c.kind, x: c.x, z: c.z, name: c.kind == Greywall.kind ? c.name : nil)
        }
    }
}

extension ShipManager {
    // An AI Meridian frigate hunting the player lowers a boarding party down its winch line (at most two a frigate).
    func boardingParty(_ s: Ship, _ st: CapitalState, _ dt: Float, _ g: Game) {
        guard s.role == "capfrigate", !s.wrecked, !s.captured, st.parties < Navy.maxParties, let t = st.target, t.player, g.survival else { return }
        st.partyCD -= dt
        guard st.partyCD <= 0 else { return }
        let top = FrigateBoarding.anchor(s)
        let pp = g.player.pos
        guard simd_length(V2(pp.x - top.x, pp.z - top.z)) < Navy.partyReach, pp.y < top.y else { return }
        // A landing spot on dry ground a few blocks from the player (never open water: the launch would set its marines
        // down in the sea).
        var spot: V3?
        for k in 0..<8 {
            let a = Float(k) * .pi / 4, r: Float = 6
            let x = pp.x + cosf(a) * r, z = pp.z + sinf(a) * r
            let ix = Int(floor(x)), iz = Int(floor(z))
            guard world.isLoaded(ix, iz) else { continue }
            let y = world.topY(ix, iz)
            guard y > 0, !Blocks.isLiquid(world.block(ix, y, iz)), !Blocks.isLiquid(world.block(ix, y + 1, iz)) else { continue }
            spot = V3(x, Float(y + 1), z); break
        }
        guard let land = spot else { st.partyCD = 3; return }
        st.partyCD = 30
        st.parties += 1
        if let r = st.region { navyParties[r] = st.parties }
        callDropship(faction: .meridian, from: top + V3(0, 2, 0), to: land, game: g, troops: 3)
        g.onToast?("A Meridian launch is bringing a boarding party!")
    }
}

extension ItemRegistry {
    func registerNavyItems() {
        if !has(Navy.pulseKey) {
            var d = ItemDef(Navy.pulseKey, "Pulse Charge")
            d.sprite = Sprite(mask: "module", base: 0x2A3A4A, extras: ["c": 0x6AC8FF, "d": 0xE0F4FF])
            d.maxStack = 8
            add(d)
        }
    }
}
