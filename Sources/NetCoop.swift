import Foundation
import simd

// Two-player co-op over the network (backlog C14). One headset hosts its world; a friend's joins it over the local
// network (NetLink.swift: TCP plus a UDP beacon, so nobody types an address).
//
// Who owns what (host-authoritative world, guest-owned body):
//   the world     blocks, chests and other containers, mobs, time and weather live on the host. The guest's world is
//                 a mirror: every chunk comes from the host (World.remoteChunk), the host's block changes stream to it,
//                 its own changes go back (World.netEdit). Mobs are drawn from the host's snapshots ten times a
//                 second (smoothed); the guest's hits go to the host, which applies them.
//   the guest     moves, mines, builds, crafts, eats and keeps its own inventory and health on its own headset; on the
//                 host it is co-op seat 1 (Coop.swift, Coop.netSeat): mobs chase it and fight it, the host's world
//                 streams round it, and it is drawn as a player. What hurts that seat on the host (a zombie's blow, an
//                 arrow, a blast) is sent to the guest and lands there through its own armour and shield; loot from a
//                 mob the guest killed drops on the guest's side; what the seat picks up on the host is handed over.
//   both          see each other (PlayerModel), and a chest closed by either player sends its contents to the other.
// One guest at a time; the host's pause stops both. If the link drops, the guest returns to its own last world.
enum NetMsg {
    // host -> guest
    static let welcome: UInt8 = 1, chunk: UInt8 = 2, blocks: UInt8 = 3, mobs: UInt8 = 4, hostPose: UInt8 = 5, clock: UInt8 = 6
    static let hurt: UInt8 = 7, give: UInt8 = 8, toast: UInt8 = 9, drop: UInt8 = 10, refuse: UInt8 = 11, entity: UInt8 = 12
    // guest -> host
    static let hello: UInt8 = 101, pose: UInt8 = 102, wantChunk: UInt8 = 103, setBlocks: UInt8 = 104, hitMob: UInt8 = 105
    static let guestEntity: UInt8 = 106
    static let version: UInt16 = 1
}

// A player's pose as the other side draws it.
struct NetPose {
    var pos = V3(0, 0, 0), yaw: Float = 0, pitch: Float = 0, swing: Float = 0
    var sneaking = false, flying = false, alive = true
    var held = ""
    func write(_ o: inout NetOut) {
        o.v3(pos); o.f32(yaw); o.f32(pitch); o.f32(swing)
        o.u8((sneaking ? 1 : 0) | (flying ? 2 : 0) | (alive ? 4 : 0)); o.str(held)
    }
    static func read(_ r: inout NetIn) -> NetPose {
        var p = NetPose()
        p.pos = r.v3(); p.yaw = r.f32(); p.pitch = r.f32(); p.swing = r.f32()
        let f = r.u8()
        p.sneaking = f & 1 != 0; p.flying = f & 2 != 0; p.alive = f & 4 != 0
        p.held = r.str()
        return p
    }
    static func of(_ g: Game) -> NetPose {
        NetPose(pos: g.player.pos, yaw: g.player.yaw, pitch: g.player.pitch, swing: g.swing, sneaking: g.player.sneaking,
                flying: g.player.flying, alive: g.alive, held: g.held.isEmpty ? "" : Items.key(g.held.item))
    }
}

enum NetCoop {
    static var redirect: NetHost?          // while a mob the guest killed drops its loot (Mob deaths, ItemEntityManager.spawn)
    static var registry: UInt32 { UInt32(Blocks.count) &* 31 &+ UInt32(Items.count) }

    // Chunks and their containers on the wire: the save format (block names in a palette, lzfse) and JSON entities.
    static func encodeChunk(_ blocks: [BlockID], _ ents: [(IVec3, BlockEntity)]) -> [UInt8] {
        var o = NetOut()
        o.bytes(SaveManager.encodeBlocks(blocks) ?? [])
        o.u16(UInt16(min(ents.count, 65535)))
        for (p, be) in ents.prefix(65535) {
            o.i32(p.x); o.i32(p.y); o.i32(p.z)
            o.bytes((try? JSONEncoder().encode(be)).map { [UInt8]($0) } ?? [])
        }
        return o.b
    }
    static func decodeChunk(_ r: inout NetIn) -> ([BlockID], [(IVec3, BlockEntity)])? {
        guard let blocks = SaveManager.decodeBlocks(r.bytes()) else { return nil }
        var ents: [(IVec3, BlockEntity)] = []
        let n = Int(r.u16())
        for _ in 0..<n {
            let p = IVec3(r.i32(), r.i32(), r.i32())
            if let be = try? JSONDecoder().decode(BlockEntity.self, from: Data(r.bytes())) { ents.append((p, be)) }
        }
        return (blocks, ents)
    }
    static func encodeEntity(_ p: IVec3, _ be: BlockEntity?) -> [UInt8] {
        var o = NetOut()
        o.i32(p.x); o.i32(p.y); o.i32(p.z)
        o.bytes(be.flatMap { try? JSONEncoder().encode($0) }.map { [UInt8]($0) } ?? [])
        return o.b
    }
    static func applyEntity(_ g: Game, _ r: inout NetIn) {
        let p = IVec3(r.i32(), r.i32(), r.i32())
        let d = r.bytes()
        if d.isEmpty { g.world.blockEntities[p] = nil; return }
        if let be = try? JSONDecoder().decode(BlockEntity.self, from: Data(d)) { g.world.blockEntities[p] = be }
    }
    static func stackData(_ s: ItemStack) -> [UInt8] { (try? JSONEncoder().encode(s)).map { [UInt8]($0) } ?? [] }
    static func stack(_ d: [UInt8]) -> ItemStack? { try? JSONDecoder().decode(ItemStack.self, from: Data(d)) }

    // The block entities a menu shows (closing it sends them to the other player).
    static func entities(of menu: Menu, in w: World) -> [(IVec3, BlockEntity)] {
        var cs: [ObjectIdentifier] = []
        for s in menu.slots where !s.isPlayerInv { if let c = s.container { cs.append(ObjectIdentifier(c)) } }
        guard !cs.isEmpty else { return [] }
        let want = Set(cs)
        return w.blockEntities.filter { want.contains(ObjectIdentifier($0.value.container)) }.map { ($0.key, $0.value) }
    }
    static func menuClosed(_ g: Game, _ menu: Menu) {
        guard g.netHost?.link != nil || g.netGuest != nil else { return }
        for (p, be) in entities(of: menu, in: g.world) {
            let d = encodeEntity(p, be)
            g.netHost?.link?.send(NetMsg.entity, d)
            g.netGuest?.link.send(NetMsg.guestEntity, d)
        }
    }

    // The other player's body: drawn with the player model at their pose.
    static func writeRemote(_ g: Game, eye: V3, daylight: Float, into out: UnsafeMutablePointer<MobVert>, capacity: Int) -> Int {
        guard let gu = g.netGuest, gu.connected, let p = gu.hostPose, p.alive else { return 0 }
        let swing = g.swing
        let body = Player()
        body.pos = p.pos; body.yaw = p.yaw; body.pitch = p.pitch; body.sneaking = p.sneaking; body.flying = p.flying
        var n = 0
        g.swing = p.swing
        g.withStandIn(body) { n = writePlayerModel(g, eye: eye, daylight: daylight, into: out, capacity: capacity) }
        g.swing = swing
        return n
    }

    // A status line for the pause menu.
    static func status(_ g: Game) -> String {
        if let h = g.netHost { return h.link != nil ? "Hosting co-op: \(h.guestName) is in your world" : "Hosting co-op: waiting for a friend to join" }
        if let gu = g.netGuest { return gu.connected ? "In \(gu.worldName) (co-op)" : "Co-op: connecting" }
        return ""
    }
}

// MARK: Host

final class NetHost {
    private var listenFD: Int32 = -1
    private var beaconFD: Int32 = -1
    private let lock = NSLock()
    private var pendingFD: Int32 = -1
    private var running = true
    private(set) var link: NetLink?
    private(set) var guestName = "Your friend"
    private(set) var joined = false
    var pose = NetPose()
    private var edits: [(Int, Int, Int, BlockID)] = []
    private var chunkQueue: [ChunkKey] = []
    private var chunkJobs = 0
    private let chunkLock = NSLock()
    private var chunkReady: [(ChunkKey, [UInt8])] = []
    private var mobIDs: [ObjectIdentifier: UInt32] = [:]
    private var nextMob: UInt32 = 1
    private var poseT: Float = 0, mobT: Float = 0, clockT: Float = 0, beaconT: Float = 0
    private(set) var sentChunks = 0, sentMobs = 0
    var redirectDrops = false

    init?(_ g: Game) {
        guard let fd = NetSock.listen(port: NetSock.gamePort) else { return nil }
        listenFD = fd
        beaconFD = NetSock.beaconSocket() ?? -1
        let t = Thread { [weak self] in self?.acceptLoop() }
        t.name = "blocksmith.net.accept"; t.stackSize = 1 << 20
        t.start()
        g.world.netEdit = { [weak self] x, y, z, id in self?.edits.append((x, y, z, id)) }
    }

    private func acceptLoop() {
        while true {
            lock.lock(); let go = running; lock.unlock()
            guard go else { break }
            guard let c = NetSock.accept(listenFD) else { continue }
            lock.lock()
            if pendingFD < 0 && link == nil { pendingFD = c; lock.unlock() } else { lock.unlock(); NetSock.close(c) }
        }
    }

    func stop(_ g: Game) {
        lock.lock(); running = false; lock.unlock()
        link?.close()
        NetSock.close(listenFD)
        if beaconFD >= 0 { NetSock.close(beaconFD) }
        g.world.netEdit = nil
        if joined { dropGuest(g, why: nil) }
    }

    private func dropGuest(_ g: Game, why: String?) {
        if joined, let s = g.coop.netSeat, s < g.coop.seatCount { g.coop.leave(g) }
        g.coop.netSeat = nil
        joined = false
        link?.close()
        link = nil
        mobIDs = [:]
        g.world.extraCenter = nil
        if let w = why { g.onToast?(w) }
    }

    // Once a frame on the game thread, before the seats tick.
    func tick(_ g: Game, _ dt: Float) {
        beaconT -= dt
        if beaconT <= 0 && link == nil && beaconFD >= 0 {
            beaconT = 1
            NetSock.beacon(beaconFD, "BSMITH \(NetSock.gamePort) \(g.save?.dir.lastPathComponent ?? "World")")
        }
        lock.lock()
        if pendingFD >= 0 && link == nil { link = NetLink(fd: pendingFD); pendingFD = -1 }
        lock.unlock()
        guard let l = link else { return }
        for (type, body) in l.poll() { handle(g, type, body) }
        if l.closed { dropGuest(g, why: "\(guestName) left your world"); return }
        guard joined else { return }
        // Chunks the guest asked for: loaded ones now, the rest generated (or read from disk) on a worker.
        var budget = 6
        while budget > 0 && !chunkQueue.isEmpty && l.queuedBytes < 4 << 20 {
            let k = chunkQueue.removeFirst()
            budget -= 1
            if let c = g.world.chunks[k] {
                let ents = g.world.blockEntities.filter { floorDiv($0.key.x, CS) == k.x && floorDiv($0.key.z, CS) == k.z }.map { ($0.key, $0.value) }
                sendChunk(k, NetCoop.encodeChunk(c.blocks.full(), ents))
            } else {
                chunkLock.lock(); chunkJobs += 1; chunkLock.unlock()
                let w = g.world
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    let (blocks, ents) = w.produceForNet(k)
                    let d = NetCoop.encodeChunk(blocks, ents)
                    guard let self else { return }
                    self.chunkLock.lock(); self.chunkReady.append((k, d)); self.chunkJobs -= 1; self.chunkLock.unlock()
                }
            }
        }
        chunkLock.lock(); let ready = chunkReady; chunkReady.removeAll(); chunkLock.unlock()
        for (k, d) in ready { sendChunk(k, d) }
        // The world's changes (this frame's, all of them: the guest's own came in quietly and aren't here).
        if !edits.isEmpty {
            var o = NetOut()
            o.u32(UInt32(edits.count))
            for (x, y, z, id) in edits { o.i32(x); o.i32(y); o.i32(z); o.u16(id) }
            l.send(NetMsg.blocks, o.b)
            edits.removeAll(keepingCapacity: true)
        }
        poseT -= dt; mobT -= dt; clockT -= dt
        if poseT <= 0 {
            poseT = 0.05
            var o = NetOut()
            NetPose.of(g).write(&o)
            l.send(NetMsg.hostPose, o.b)
        }
        if mobT <= 0 { mobT = 0.1; sendMobs(g, l) }
        if clockT <= 0 {
            clockT = 1
            var o = NetOut()
            o.f64(g.time); o.f32(g.weather.rain); o.f32(g.weather.thunder); o.bool(g.paused)
            l.send(NetMsg.clock, o.b)
        }
    }

    private func sendChunk(_ k: ChunkKey, _ d: [UInt8]) {
        var o = NetOut()
        o.i32(k.x); o.i32(k.z)
        o.b += d
        link?.send(NetMsg.chunk, o.b)
        sentChunks += 1
    }

    func mobID(_ m: Mob) -> UInt32 {
        let k = ObjectIdentifier(m)
        if let id = mobIDs[k] { return id }
        let id = nextMob
        nextMob &+= 1
        mobIDs[k] = id
        return id
    }

    // Every mob within 112 blocks of the guest: id, kind, pose and what the model needs.
    private func sendMobs(_ g: Game, _ l: NetLink) {
        let c = pose.pos
        var o = NetOut()
        var list: [Mob] = []
        for m in g.mobs.mobs where m.health > 0 {
            let d = m.pos - c
            if d.x * d.x + d.z * d.z < 112 * 112 { list.append(m) }
        }
        o.u16(UInt16(min(list.count, 1000)))
        for m in list.prefix(1000) {
            o.u32(mobID(m))
            o.str(m.kind.key)
            o.v3(m.pos); o.f32(m.yaw); o.f32(m.headYaw); o.f32(m.headPitch)
            o.i32(m.health); o.i32(m.variant)
            o.u8((m.baby ? 1 : 0) | (m.saddled ? 2 : 0) | (m.owner == true ? 4 : 0) | (m.fire > 0 ? 8 : 0) | (m.aggro ? 16 : 0))
            o.f32(m.scale)
            o.i32(m.faction)
            o.str(m.customName ?? "")
        }
        l.send(NetMsg.mobs, o.b)
        sentMobs += 1
        if mobIDs.count > 4 * max(64, g.mobs.mobs.count) {           // forget the long dead
            let live = Set(g.mobs.mobs.map { ObjectIdentifier($0) })
            mobIDs = mobIDs.filter { live.contains($0.key) }
        }
    }

    private func handle(_ g: Game, _ type: UInt8, _ body: [UInt8]) {
        var r = NetIn(body)
        switch type {
        case NetMsg.hello:
            let v = r.u16(), reg = r.u32()
            let name = r.str()
            guard v == NetMsg.version, reg == NetCoop.registry else {
                var o = NetOut(); o.str("That headset runs a different Blocksmith version: update both to play together")
                link?.send(NetMsg.refuse, o.b)
                link?.close()
                return
            }
            guestName = name.isEmpty ? "Your friend" : name
            // Seat 1: a co-op seat whose body is driven from the network (Coop.netSeat).
            if g.coop.active { g.coop.leave(g) }
            g.coop.netSeat = 1
            g.coop.join(g, controller: nil)
            joined = true
            let spawn = g.coop.seatPlayer(1, g).pos
            pose.pos = spawn
            var o = NetOut()
            o.u64(g.world.seed); o.bool(g.survival); o.u8(UInt8(g.difficulty)); o.bool(g.smoothTerrain)
            o.f64(g.time); o.v3(spawn); o.str(g.save?.dir.lastPathComponent ?? "World")
            link?.send(NetMsg.welcome, o.b)
            g.onToast?("\(guestName) joined your world")
        case NetMsg.pose:
            pose = NetPose.read(&r)
        case NetMsg.wantChunk:
            let k = ChunkKey(x: r.i32(), z: r.i32())
            if !chunkQueue.contains(k) { chunkQueue.append(k) }
        case NetMsg.setBlocks:
            let n = Int(r.u32())
            World.netQuiet = true
            for _ in 0..<n {
                let x = r.i32(), y = r.i32(), z = r.i32(), id = r.u16()
                guard r.ok, Int(id) < Blocks.count, g.world.isLoaded(x, z) else { continue }
                let old = g.world.block(x, y, z)
                g.world.setBlock(x, y, z, id)
                if old != id && id == AIR { g.world.blockEntities[IVec3(x, y, z)] = nil }
            }
            World.netQuiet = false
        case NetMsg.hitMob:
            let id = r.u32(), dmg = r.i32(), src = r.v3(), knock = r.f32()
            guard let s = g.coop.netSeat, let m = g.mobs.mobs.first(where: { mobIDs[ObjectIdentifier($0)] == id }), m.health > 0 else { return }
            g.coop.withSeat(s, g) {
                m.killedByPlayer = true
                m.playerHurtAt = g.clock
                m.netHitAt = g.clock
                m.hit(from: src, damage: dmg, knockback: knock, iframes: true)
            }
        case NetMsg.guestEntity:
            NetCoop.applyEntity(g, &r)
        default: break
        }
    }

    // Seat 1's frame on the host (Game.tickSeat): its body where the guest's headset says, then its share of the world.
    func seatTick(_ g: Game, _ dt: Double) {
        let p = g.player
        let was = p.pos
        p.pos = pose.pos; p.yaw = pose.yaw; p.pitch = pose.pitch
        p.sneaking = pose.sneaking; p.flying = pose.flying
        p.vel = (pose.pos - was) / Float(max(dt, 0.001))
        g.swing = pose.swing
        g.alive = pose.alive
        g.health = 20
        if !g.paused { g.coopAdvance(dt) }
        // What the seat picked up goes to the guest's own inventory.
        for i in 0..<g.inventory.main.count where !g.inventory.main[i].isEmpty {
            var o = NetOut(); o.bytes(NetCoop.stackData(g.inventory.main[i]))
            link?.send(NetMsg.give, o.b)
            g.inventory.main[i] = .empty
        }
    }

    // A hit on seat 1 (Game.hurtPlayer / damage): the guest's headset takes it.
    func hurt(_ amount: Int, from src: V3, cause: String, knockback: Float, type: DamageType) {
        var o = NetOut()
        o.i32(amount); o.v3(src); o.str(cause); o.f32(knockback); o.u8(type.netCode)
        link?.send(NetMsg.hurt, o.b)
    }

    // Loot of a mob the guest killed: it lands on the guest's side.
    func drop(_ s: ItemStack, at p: V3) {
        var o = NetOut(); o.bytes(NetCoop.stackData(s)); o.v3(p)
        link?.send(NetMsg.drop, o.b)
    }

    func toast(_ t: String) { var o = NetOut(); o.str(t); link?.send(NetMsg.toast, o.b) }
}

// MARK: Guest

final class NetGuest {
    let link: NetLink
    private(set) var connected = false
    private(set) var refused: String?
    private(set) var seed: UInt64 = 0
    private(set) var survival = true, difficulty = 2, smooth = false
    private(set) var time: Double = 0
    private(set) var spawn = V3(0, 100, 0)
    private(set) var worldName = "a friend's world"
    var hostPose: NetPose?
    private let cacheLock = NSCondition()
    private var cache: [ChunkKey: ([BlockID], [(IVec3, BlockEntity)])] = [:]
    private var asked: Set<ChunkKey> = []
    private var edits: [(Int, Int, Int, BlockID)] = []
    private struct Mirror { let mob: Mob; var to: V3; var yaw: Float; var seen: Double }
    private var mirrors: [UInt32: Mirror] = [:]
    private var poseT: Float = 0
    private(set) var chunksIn = 0

    // Connects and says hello; the welcome arrives through `waitWelcome` (the loading thread).
    init?(ip: String, name: String) {
        guard let fd = NetSock.connect(ip, port: NetSock.gamePort) else { return nil }
        link = NetLink(fd: fd)
        var o = NetOut()
        o.u16(NetMsg.version); o.u32(NetCoop.registry); o.str(name)
        link.send(NetMsg.hello, o.b)
    }

    // Blocks until the host's welcome (or a refusal / timeout). Chunks that arrive meanwhile are kept.
    func waitWelcome(seconds: Double) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end && !link.closed {
            pump()
            if connected || refused != nil { return connected }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return connected
    }

    // Chunk messages are taken off the queue as they come (World workers wait on them); the rest wait for the frame.
    private var held: [(UInt8, [UInt8])] = []
    private let routeLock = NSLock()           // poll + route from the frame and from world workers waiting on chunks
    private func route(_ type: UInt8, _ body: [UInt8]) {
        var r = NetIn(body)
        switch type {
        case NetMsg.welcome:
            seed = r.u64(); survival = r.bool(); difficulty = Int(r.u8()); smooth = r.bool()
            time = r.f64(); spawn = r.v3(); worldName = r.str()
            connected = true
        case NetMsg.refuse:
            refused = r.str()
            link.close()
        case NetMsg.chunk:
            let k = ChunkKey(x: r.i32(), z: r.i32())
            guard let c = NetCoop.decodeChunk(&r) else { return }
            cacheLock.lock(); cache[k] = c; chunksIn += 1; cacheLock.broadcast(); cacheLock.unlock()
        default:
            held.append((type, body))
        }
    }

    // World.remoteChunk (worker threads): ask once, then wait for it (up to 8 s; a lost link falls back to the seed).
    func chunk(_ k: ChunkKey) -> ([BlockID], [(IVec3, BlockEntity)])? {
        cacheLock.lock()
        if !asked.contains(k) {
            asked.insert(k)
            var o = NetOut(); o.i32(k.x); o.i32(k.z)
            link.send(NetMsg.wantChunk, o.b)
        }
        let end = Date().addingTimeInterval(8)
        while cache[k] == nil && !link.closed && Date() < end {
            cacheLock.unlock()
            pump()                                   // nobody else may be draining (the loading thread's loadSync)
            cacheLock.lock()
            if cache[k] == nil { _ = cacheLock.wait(until: min(end, Date().addingTimeInterval(0.02))) }
        }
        let c = cache.removeValue(forKey: k)
        asked.remove(k)
        cacheLock.unlock()
        // (Chunks also arrive while the frame thread is busy elsewhere: drain the socket here too.)
        return c
    }

    // Drains the link from a worker (the loading thread waits on chunks before the first frame).
    func pump() {
        routeLock.lock(); defer { routeLock.unlock() }
        for (type, body) in link.poll() { route(type, body) }
    }

    func attach(_ g: Game) {
        g.world.remoteChunk = { [weak self] k in
            guard let self else { return nil }
            self.pump()
            return self.chunk(k)
        }
        g.world.netEdit = { [weak self] x, y, z, id in self?.edits.append((x, y, z, id)) }
        Mob.netHit = { [weak self] m, src, dmg, knock in self?.hit(m, src, dmg, knock) ?? false }
    }

    func detach(_ g: Game) {
        g.world.remoteChunk = nil
        g.world.netEdit = nil
        Mob.netHit = nil
        link.close()
    }

    private func hit(_ m: Mob, _ src: V3, _ dmg: Int, _ knock: Float) -> Bool {
        guard let id = mirrors.first(where: { $0.value.mob === m })?.key else { return false }
        var o = NetOut(); o.u32(id); o.i32(dmg); o.v3(src); o.f32(knock)
        link.send(NetMsg.hitMob, o.b)
        m.hurt = 0.4                     // the flash now; the health comes back with the next snapshot
        return true
    }

    // Once a frame (Game.tick): the host's news in, this player's pose and edits out, mobs smoothed.
    func tick(_ g: Game, _ dt: Float) {
        pump()
        routeLock.lock()
        let batch = held
        held.removeAll()
        routeLock.unlock()
        for (type, body) in batch { apply(g, type, body) }
        if link.closed {
            connected = false
            g.onToast?("Lost the link to the host")
            g.appAction?("netleave")
            return
        }
        poseT -= dt
        if poseT <= 0 {
            poseT = 0.05
            var o = NetOut()
            NetPose.of(g).write(&o)
            link.send(NetMsg.pose, o.b)
        }
        if !edits.isEmpty {
            var o = NetOut()
            o.u32(UInt32(edits.count))
            for (x, y, z, id) in edits { o.i32(x); o.i32(y); o.i32(z); o.u16(id) }
            link.send(NetMsg.setBlocks, o.b)
            edits.removeAll(keepingCapacity: true)
        }
        // Mobs glide to their last reported place (a snapshot every 0.1 s).
        let k = min(1, dt * 12)
        for (_, mi) in mirrors {
            let m = mi.mob
            let before = m.pos
            m.pos += (mi.to - m.pos) * k
            m.yaw += wrapAngle(mi.yaw - m.yaw) * k
            let sp = simd_length(V2(m.pos.x - before.x, m.pos.z - before.z)) / max(dt, 0.001)
            m.walkAmount += (min(1, sp / max(0.5, m.spec.speed)) - m.walkAmount) * min(1, dt * 8)
            m.walkPhase += sp * dt * 2.2
            m.animT += dt
            m.hurt = max(0, m.hurt - dt)
        }
    }

    private func apply(_ g: Game, _ type: UInt8, _ body: [UInt8]) {
        var r = NetIn(body)
        switch type {
        case NetMsg.blocks:
            let n = Int(r.u32())
            World.netQuiet = true
            for _ in 0..<n {
                let x = r.i32(), y = r.i32(), z = r.i32(), id = r.u16()
                guard r.ok, Int(id) < Blocks.count else { continue }
                g.world.setBlock(x, y, z, id)
            }
            World.netQuiet = false
        case NetMsg.mobs:
            let n = Int(r.u16())
            var seen = Set<UInt32>()
            for _ in 0..<n {
                let id = r.u32(), key = r.str()
                let pos = r.v3(), yaw = r.f32(), hy = r.f32(), hp = r.f32()
                let health = r.i32(), variant = r.i32()
                let f = r.u8()
                let scale = r.f32(), faction = r.i32()
                let name = r.str()
                guard r.ok else { break }
                seen.insert(id)
                var mi: Mirror
                if let e = mirrors[id] { mi = e } else {
                    guard let kind = MobKind.named(key) else { continue }
                    let m = Mob(kind, at: pos)
                    m.persistent = true
                    g.mobs.mobs.append(m)
                    mi = Mirror(mob: m, to: pos, yaw: yaw, seen: g.clock)
                }
                let m = mi.mob
                mi.to = pos; mi.yaw = yaw; mi.seen = g.clock
                m.headYaw = hy; m.headPitch = hp
                if health < m.health { m.hurt = 0.4 }
                m.health = max(1, health)
                m.variant = variant
                m.baby = f & 1 != 0; m.saddled = f & 2 != 0; m.owner = f & 4 != 0 ? true : nil
                m.fire = f & 8 != 0 ? 1 : 0; m.aggro = f & 16 != 0
                m.scale = scale; m.faction = faction
                m.customName = name.isEmpty ? nil : name
                mirrors[id] = mi
            }
            // Gone from the snapshot: dead or out of range on the host.
            for (id, mi) in mirrors where !seen.contains(id) {
                mi.mob.health = -2000
                mirrors[id] = nil
            }
            g.mobs.mobs.removeAll { $0.health == -2000 }
        case NetMsg.hostPose:
            hostPose = NetPose.read(&r)
        case NetMsg.clock:
            let t = r.f64(), rain = r.f32(), thunder = r.f32()
            if abs(g.time - t) > 2 { g.time = t } else { g.time += (t - g.time) * 0.5 }
            g.weather.rain = rain; g.weather.thunder = thunder
            g.weather.raining = rain > 0.2; g.weather.thundering = thunder > 0.2
        case NetMsg.hurt:
            let amount = r.i32(), src = r.v3(), cause = r.str(), knock = r.f32(), t = DamageType.from(net: r.u8())
            g.hurtPlayer(amount, from: src, cause: cause, knockback: knock, type: t)
        case NetMsg.give:
            if let s = NetCoop.stack(r.bytes()) {
                let rest = g.inventory.add(s)
                if !rest.isEmpty { g.drops.spawn(rest, at: g.player.pos + V3(0, 0.5, 0), delay: 0) }
                g.sfx(.pickup, 0.4, at: g.player.pos)
            }
        case NetMsg.drop:
            if let s = NetCoop.stack(r.bytes()) { g.drops.spawn(s, at: r.v3()) }
        case NetMsg.toast:
            g.onToast?(r.str())
        case NetMsg.entity:
            NetCoop.applyEntity(g, &r)
        default: break
        }
    }

    // Leaving: the mirrors go with the link.
    func clearMirrors(_ g: Game) {
        for (_, mi) in mirrors { mi.mob.health = -2000 }
        mirrors = [:]
        g.mobs.mobs.removeAll { $0.health == -2000 }
    }
}

extension DamageType {
    var netCode: UInt8 {
        switch self {
        case .projectile: return 1
        case .explosion: return 2
        case .fire: return 3
        default: return 0
        }
    }
    static func from(net c: UInt8) -> DamageType { c == 1 ? .projectile : (c == 2 ? .explosion : (c == 3 ? .fire : .generic)) }
}

extension Game {
    // The guest's frame on its own headset: the world it sees is the host's, so nothing here moves it (no mobs, fluids,
    // fire, random ticks, spawning, sieges): only this player's own effects, sounds and particles, and its drops.
    func netGuestAdvance(_ dt: Double) {
        let f = Float(dt)
        drops.update(f, game: self)
        projectiles.update(f, game: self)
        armsTick(f)
        particles.update(f, world)
        ambientParticles(f)
        emberMotes(f)
        updateFlashes(f)
        shake = max(0, shake - f * 1.3)
        effectTick(f)
        xpOrbTick(f)
        bobberTick(f)
        mapTick()
        musicTick(f)
        audioAmbientTick(f)
        world.rainLevel = wetWorld ? weather.rain : 0
        if survival { timeSinceRest += f }
        time += dt
        if !world.pendingMobs.isEmpty { world.pendingMobs.removeAll() }   // the host's mobs arrive as mirrors
    }
}
