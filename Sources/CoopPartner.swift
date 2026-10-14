import Foundation
import simd

// D52: co-op partners (split screen, and Play Together over the network where noted).
//   gun seats   while your partner pilots a ship or vehicle you're aboard, stand at one of its turrets and it's yours:
//               it follows your view (the pilot's view no longer turns it) and attack fires its guns (cannonballs
//               from your pack in survival, as at the helm). Walk away and the pilot has it back.
//   pillion     use the horse your partner is riding to climb up behind them (split screen; over the network the
//               friend saddles their own mirrored mount as before). Sneak to slide off.
//   shared pay  a contract or a gang leader's bounty paid to one of you pays the other a share of half (over the
//               network it is sent across; on a split screen the wallet is already one).
//   downed      with a partner up and about, a blow that would kill you puts you down instead: 40 seconds on the
//               ground, slowed to a crawl and out of the fight. Your partner crouches beside you for three seconds
//               to get you up (8 health); nobody comes and you die as usual. Each blow taken while down takes 4 s
//               off the clock. Works over the network as well.
enum Partner {
    static let downTime: Double = 40
    static let reviveTime: Float = 3
    static let reviveReach: Float = 2.5
    static let gunReach: Float = 2.6
    static var downedUntil: [Int: Double] = [:]
    static var downCause: [Int: String] = [:]
    static var revivedPending = Set<Int>()
    static var reviving: [Int: Float] = [:]                 // progress on the partner being got up, by the reviver's seat
    static var gunner: [Int: Int] = [:]                     // seat -> the turret (ship id) it mans
    static var mannedAt: [Int: Double] = [:]                // turret ship id -> last frame a gunner held it
    static var pillion: [Int: Mob] = [:]
    static var downs = 0, revives = 0, gunShots = 0, shared = 0   // (harness)

    static func seat(_ g: Game) -> Int { g.coop.current }
    static func isDowned(_ g: Game) -> Bool { downedUntil[seat(g)] != nil }
    static func manned(_ g: Game, _ t: Ship) -> Bool { g.clock - (mannedAt[t.id] ?? -1e9) < 0.3 }

    // The other split-screen seat, when there is one.
    static func otherSeat(_ g: Game) -> Int? {
        guard g.coop.split, g.coop.seatCount > 1 else { return nil }
        return g.coop.current == 0 ? 1 : 0
    }

    // A partner up and about, who could come to you.
    static func partnerUp(_ g: Game) -> Bool {
        if let j = otherSeat(g) { return (g.coop.slots[j]?.alive ?? false) && downedUntil[j] == nil }
        if let h = g.netHost, h.joined { return h.pose.alive && !h.pose.downed }
        if let gu = g.netGuest, gu.connected, let hp = gu.hostPose { return hp.alive && !hp.downed }
        return false
    }

    // MARK: Downed

    // Game.hurt, a killing blow: down instead of dead when a partner can come. True when the death is put off.
    static func goDown(_ g: Game, _ cause: String) -> Bool {
        guard g.survival, !isDowned(g), partnerUp(g), g.dim.dim != .end || g.player.pos.y > 0 else { return false }
        let s = seat(g)
        downedUntil[s] = g.clock + downTime
        downCause[s] = cause
        g.health = 1
        if g.riding != nil { g.dismount() }
        downs += 1
        g.sfx(.hurt, 1)
        g.onToast?("You're down! Your partner can crouch beside you to get you up")
        return true
    }

    // Q2: a blow while you're down bleeds you out faster (4 s off the clock), and the void still takes you, so a downed
    // player isn't safe bait in the middle of a fight.
    static func hitWhileDown(_ g: Game, _ type: DamageType) {
        let s = seat(g)
        guard let until = downedUntil[s] else { return }
        if type == .void { downedUntil[s] = g.clock; return }
        downedUntil[s] = until - 4
    }

    // Every frame for the live seat (Game.tick).
    static func tick(_ g: Game, _ dt: Float) {
        let s = seat(g)
        // Got up by the partner.
        if revivedPending.remove(s) != nil, downedUntil[s] != nil {
            downedUntil[s] = nil; downCause[s] = nil
            g.health = max(g.health, 8)
            revives += 1
            g.sfx(.levelUp, 0.6)
            g.onToast?("Your partner gets you back on your feet")
        }
        if let until = downedUntil[s] {
            if !g.alive || !g.survival { downedUntil[s] = nil }
            else if g.clock > until || !partnerUpOrComing(g) {
                downedUntil[s] = nil
                let c = downCause.removeValue(forKey: s) ?? "bled out"
                g.health = 0
                g.die(c)
            } else {
                g.health = max(1, min(g.health, 1))
                g.player.vel.x *= 0.2; g.player.vel.z *= 0.2
                g.player.sprinting = false
                if Int(g.clock * 2) != Int((g.clock - Double(dt)) * 2) { g.applyEffect(.slowness, amp: 5, seconds: 1.2) }
            }
        }
        reviveTick(g, s, dt)
        pillionTick(g, s)
    }

    // A downed player's partner left or died: no one is coming.
    static func partnerUpOrComing(_ g: Game) -> Bool {
        if let j = otherSeat(g) { return g.coop.slots[j]?.alive ?? false }
        if let h = g.netHost { return h.joined && h.pose.alive }
        if let gu = g.netGuest { return gu.connected && (gu.hostPose?.alive ?? false) }
        return false
    }

    // Crouching beside a downed partner gets them up.
    static func reviveTick(_ g: Game, _ s: Int, _ dt: Float) {
        guard g.alive, !isDowned(g) else { reviving[s] = nil; return }
        var at: V3?, send: (() -> Void)?
        if let j = otherSeat(g), downedUntil[j] != nil {
            at = g.coop.seatPlayer(j, g).pos
            send = { revivedPending.insert(j) }
        } else if let h = g.netHost, h.joined, h.pose.downed {
            at = h.pose.pos
            send = { h.link?.send(NetMsg.revive, []) }
        } else if let gu = g.netGuest, gu.connected, let hp = gu.hostPose, hp.downed {
            at = hp.pos
            send = { gu.link.send(NetMsg.reviveHost, []) }
        }
        guard let p = at, g.player.sneaking, simd_length(p - g.player.pos) < reviveReach else {
            reviving[s] = max(0, (reviving[s] ?? 0) - dt); return
        }
        let v = (reviving[s] ?? 0) + dt
        reviving[s] = v
        if v >= reviveTime {
            reviving[s] = nil
            send?()
            g.onToast?("You get your partner up")
        }
    }

    // Renderer.buildHUD: the downed countdown, or the revive in hand.
    static func bar(_ g: Game) -> (String, Float, V4)? {
        let s = seat(g)
        if let until = downedUntil[s] {
            return ("Down: your partner can get you up", Float(max(0, until - g.clock) / downTime), V4(0.85, 0.2, 0.15, 1))
        }
        if let v = reviving[s], v > 0 { return ("Getting your partner up", v / reviveTime, V4(0.3, 0.85, 0.4, 1)) }
        if let j = otherSeat(g), let until = downedUntil[j] {
            return ("Your partner is down: crouch beside them", Float(max(0, until - g.clock) / downTime), V4(0.95, 0.6, 0.2, 1))
        }
        if let h = g.netHost, h.joined, h.pose.downed { return ("\(h.guestName) is down: crouch beside them", 1, V4(0.95, 0.6, 0.2, 1)) }
        if let gu = g.netGuest, gu.connected, gu.hostPose?.downed == true { return ("Your friend is down: crouch beside them", 1, V4(0.95, 0.6, 0.2, 1)) }
        return nil
    }

    // MARK: Pillion

    // Game.useItemOnMob: climb up behind the partner on their horse.
    static func mountBehind(_ g: Game, _ m: Mob) -> Bool {
        guard let j = otherSeat(g), g.coop.slots[j]?.riding === m, pillion[seat(g)] == nil, m.health > 0 else { return false }
        if g.riding != nil { g.dismount() }
        pillion[seat(g)] = m
        g.sfx(.armorEquip(0), 0.5, at: m.pos)
        g.onToast?("Riding behind your partner. Sneak to slide off")
        return true
    }

    static func pillionTick(_ g: Game, _ s: Int) {
        guard let m = pillion[s] else { return }
        let partnerOn = otherSeat(g).map { g.coop.slots[$0]?.riding === m } ?? false
        if !partnerOn || m.health <= 0 || g.player.sneaking || !g.alive || g.riding != nil || isDowned(g) {
            pillion[s] = nil
            g.player.pos = g.world.freeSpawn(m.pos - m.forward * 1.2)
            g.player.vel = .zero
            return
        }
        g.player.pos = m.pos + V3(0, 1.0, 0) - m.forward * 0.55
        g.player.vel = m.vel
        g.player.onGround = true
        g.player.airPeak = g.player.pos.y
    }

    // MARK: Gun seats

    // Game.shipInteract, while not at a helm: man the turret you stand at when your partner (or anyone) pilots.
    static func gunSeatTick(_ g: Game, breakNow: Bool, breakHeld: Bool) -> Bool {
        let s = seat(g)
        let ships = g.world.ships
        guard ships.pilot == nil, let deck = ships.aboard?.root, deck.piloted, g.alive, !isDowned(g) else { gunner[s] = nil; return false }
        let p = g.player.pos
        let tur = ships.turrets(of: deck).filter { !$0.cannons.isEmpty }
        let t = tur.min { simd_length($0.toWorld($0.pivot) - p) < simd_length($1.toWorld($1.pivot) - p) }
        guard let t, simd_length(V2(t.toWorld(t.pivot).x - p.x, t.toWorld(t.pivot).z - p.z)) < gunReach else {
            if gunner[s] != nil { gunner[s] = nil; g.onToast?("You leave the gun") }
            return false
        }
        if gunner[s] != t.id {
            gunner[s] = t.id
            g.onToast?("Gun seat: the turret follows your view, attack fires it")
        }
        mannedAt[t.id] = g.clock
        var rel = g.player.yaw - deck.yaw
        while rel > .pi { rel -= 2 * .pi }
        while rel < -.pi { rel += 2 * .pi }
        t.aimAt = nil
        t.aimYaw = rel
        t.gunPitch = max(-0.2, min(0.6, g.player.pitch + 0.05))
        if breakNow {
            let ready = t.reload <= 0 ? t.cannons.count : 0
            let balls = g.survival && deck.role == nil ? Wrecks.cannonballs(g) : Int.max
            if ready > 0 && balls < ready {
                g.onToast?(balls == 0 ? "No cannonballs in your pack for the gun" : "\(ready) barrels, \(balls) cannonball\(balls == 1 ? "" : "s"): one each")
            } else if ready > 0 {
                let fired = ships.fire(t, pitch: t.gunPitch, game: g)
                if fired > 0 {
                    g.swing = 1
                    gunShots += 1
                    if g.survival && deck.role == nil { Wrecks.useCannonballs(g, fired) }
                }
            }
        }
        return breakNow || breakHeld
    }

    // MARK: Shared pay

    // Contracts.pay and GangLeaders.settle: the partner's share.
    static func sharePay(_ g: Game, _ cents: Int, _ what: String) {
        let cut = cents / 2
        guard cut > 0 else { return }
        if let h = g.netHost, h.joined {
            var o = NetOut(); o.i32(cut); o.str(what)
            h.link?.send(NetMsg.share, o.b)
            shared += 1
        } else if let gu = g.netGuest, gu.connected {
            var o = NetOut(); o.i32(cut); o.str(what)
            gu.link.send(NetMsg.shareHost, o.b)
            shared += 1
        }
    }

    // NetHost.handle / NetGuest.apply: revive and shared pay from the other headset.
    static func netMessage(_ g: Game, _ type: UInt8, _ r: inout NetIn) {
        switch type {
        case NetMsg.revive, NetMsg.reviveHost:
            revivedPending.insert(0)
        case NetMsg.share, NetMsg.shareHost:
            let cut = r.i32(), what = r.str()
            guard r.ok, cut > 0 else { return }
            g.money += cut
            g.sfx(.villagerTrade, 0.6)
            g.onToast?("Your partner's \(what): your share is \(Money.format(cut))")
        default: break
        }
    }
}
