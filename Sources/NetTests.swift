import Foundation
import Metal
import simd

// --net-only (questcheck): C14 Play Together over loopback. One process hosts its world and joins it as a guest
// (127.0.0.1): the welcome, chunks served from the host, a block edit each way and a mob snapshot.
enum NetTests {
    static func run(_ g: Game, device: MTLDevice, check: (Bool, String) -> Void) {
        let gold = Blocks.id("gold_block"), diamond = Blocks.id("diamond_block")
        guard let host = NetHost(g) else { check(false, "C14: host could not listen on \(NetSock.gamePort)"); return }
        g.netHost = host
        defer { host.stop(g); g.netHost = nil }
        // The guest connects on another thread while this one runs the host's frames.
        let lock = NSLock()
        var guest: NetGuest?, done = false
        Thread.detachNewThread {
            let gu = NetGuest(ip: "127.0.0.1", name: "Tester")
            let ok = gu?.waitWelcome(seconds: 6) ?? false
            lock.lock(); guest = ok ? gu : nil; done = true; lock.unlock()
        }
        func hostFrames(until stop: () -> Bool, seconds: Double) {
            let end = Date().addingTimeInterval(seconds)
            while Date() < end && !stop() { host.tick(g, 0.05); Thread.sleep(forTimeInterval: 0.01) }
        }
        hostFrames(until: { lock.lock(); defer { lock.unlock() }; return done }, seconds: 8)
        lock.lock(); let gu = guest; lock.unlock()
        check(gu != nil && host.joined && g.coop.netSeat == 1, "C14: the guest is welcomed and takes seat 1 on the host")
        guard let gu else { return }
        check(gu.seed == g.world.seed, "C14: the guest builds the host's seed (\(gu.seed))")
        // The guest's world: its chunks come from the host (loaded on a worker while the host keeps ticking).
        let gg = WorldRequest.guestGame(gu, device: device, renderDistance: 3)
        var loadedChunks = false
        Thread.detachNewThread {
            _ = gg.world.loadSync(center: gg.player.pos, radius: 1)
            lock.lock(); loadedChunks = true; lock.unlock()
        }
        hostFrames(until: { lock.lock(); defer { lock.unlock() }; return loadedChunks }, seconds: 30)
        let bx = Int(floor(gu.spawn.x)), bz = Int(floor(gu.spawn.z))
        var same = 0, total = 0
        for y in stride(from: 0, to: CH, by: 3) {
            total += 1
            if gg.world.rawBlock(bx, y, bz) == g.world.rawBlock(bx, y, bz) { same += 1 }
        }
        check(gu.chunksIn > 0 && same == total, "C14: \(gu.chunksIn) chunks arrive from the host; the spawn column matches (\(same)/\(total))")
        // A block the host places shows up for the guest, and one the guest places for the host.
        let top = g.world.topY(bx + 2, bz)
        g.world.setBlock(bx + 2, top + 1, bz, gold)
        let gtop = gg.world.topY(bx - 2, bz)
        gg.world.setBlock(bx - 2, gtop + 1, bz, diamond)
        let cow = Mob(.cow, at: V3(gu.spawn.x + 3, gu.spawn.y, gu.spawn.z))
        g.mobs.mobs.append(cow)
        defer { g.mobs.mobs.removeAll { $0 === cow } }
        for _ in 0..<30 {
            gu.tick(gg, 0.05)
            host.tick(g, 0.05)
            Thread.sleep(forTimeInterval: 0.01)
            gu.tick(gg, 0.05)
        }
        check(gg.world.rawBlock(bx + 2, top + 1, bz) == gold, "C14: the host's placed block reaches the guest")
        check(g.world.rawBlock(bx - 2, gtop + 1, bz) == diamond, "C14: the guest's placed block reaches the host")
        check(gg.mobs.mobs.contains { $0.kind == .cow && simd_length($0.pos - cow.pos) < 2 },
              "C14: the host's cow is mirrored on the guest (\(gg.mobs.mobs.count) mobs)")
        g.world.setBlock(bx + 2, top + 1, bz, AIR)
        gu.detach(gg); gu.clearMirrors(gg)
    }
}
