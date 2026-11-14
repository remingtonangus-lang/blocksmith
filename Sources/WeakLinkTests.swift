import Foundation

// Ledger 128: `--weaklinktest`. Objects made and let go on this thread while three others read a link to them
// (LifeLink.object, WeakLink.swift). With BS_OLDWEAKLINK=1 the runtime stops the run inside a second: "deallocated
// with non-zero retain count 2".
enum WeakLinkTests {
    private final class Probe: LifeLinked {
        var n = 7
        lazy var lifeLink = LifeLink(self)
        deinit { n = 0 }
    }
    private final class Shared { let lock = NSLock(); var slot: LifeLink?; var stop = false; var alive = 0, gone = 0, wrong = 0, ended = 0 }
    static func run(cycles: Int = 400_000, check: (Bool, String) -> Void) {
        let sh = Shared()
        for i in 0..<3 {
            let t = Thread {
                var a = 0, b = 0, bad = 0
                while true {
                    sh.lock.lock(); let l = sh.slot, stop = sh.stop; sh.lock.unlock()
                    if stop { break }
                    guard let l else { continue }
                    for _ in 0..<16 {
                        if let o = l.object { a += 1; if unsafeDowncast(o, to: Probe.self).n != 7 { bad += 1 } } else { b += 1 }
                    }
                }
                sh.lock.lock(); sh.alive += a; sh.gone += b; sh.wrong += bad; sh.ended += 1; sh.lock.unlock()
            }
            t.name = "blocksmith.weaklinktest.\(i)"
            t.start()
        }
        for _ in 0..<cycles {
            let p = Probe()
            sh.lock.lock(); sh.slot = p.lifeLink; sh.lock.unlock()
            for _ in 0..<20 { if p.n != 7 { sh.lock.lock(); sh.wrong += 1; sh.lock.unlock() } }
        }
        sh.lock.lock(); sh.stop = true; sh.lock.unlock()
        while true { sh.lock.lock(); let e = sh.ended; sh.lock.unlock(); if e == 3 { break }; Thread.sleep(forTimeInterval: 0.01) }
        check(sh.wrong == 0, "weaklink: \(cycles) objects made and let go under three readers: \(sh.alive) reads found them alive, \(sh.gone) gone, \(sh.wrong) read a dead one")
    }
}
