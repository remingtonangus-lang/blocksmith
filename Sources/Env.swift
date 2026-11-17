import Foundation

// Ledger 166 (Nov 15, a profile of the garrison's tick): every `Env.all[...]` builds the
// whole environment as a dictionary again (2.6 million instructions a read on the build machine), and the game has some
// 450 before/after switches that each read it the first time their code runs: the first blast, the first felled tree,
// the first soldier to fire each stalled the frame for one or more of them, and a table built with a read for every
// block state read it thousands of times. The environment is read once here. (A variable the game itself sets after
// launch, BLOCKSMITH_TEXRES, is still read from the process.)
enum Env {
    static let all: [String: String] = {
        var e = ProcessInfo.processInfo.environment
        #if os(Android)
        // Ledger 284 (store review, the headset gate): the headset app has no environment to set, so its before/after
        // switches could only be tried by building again. The debug properties debug.sunderfall.env, env2 and env3
        // ("BS_A=1;BS_B=0", set with `adb shell setprop`; a property holds at most 91 characters) are merged in at
        // launch: a switch is A/B tested on the real headset with a restart. Unset (every player's headset: debug.*
        // properties take adb), nothing changes.
        var set: [String] = []
        for p in ["debug.sunderfall.env", "debug.sunderfall.env2", "debug.sunderfall.env3"] {
            for pair in androidProperty(p).split(separator: ";") {
                let kv = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard kv.count == 2, !kv[0].isEmpty else { continue }
                e[kv[0]] = kv[1]; set.append("\(kv[0])=\(kv[1])")
            }
        }
        if !set.isEmpty { print("env: from debug properties: " + set.joined(separator: " ")) }
        #endif
        return e
    }()

    #if os(Android)
    // An Android system property's value ("" when unset).
    static func androidProperty(_ name: String) -> String {
        var buf = [CChar](repeating: 0, count: 96)
        let n = name.withCString { envSystemPropertyGet($0, &buf) }
        return n > 0 ? String(cString: buf) : ""
    }
    #endif
}

#if os(Android)
@_silgen_name("__system_property_get") private func envSystemPropertyGet(_ name: UnsafePointer<CChar>, _ value: UnsafeMutablePointer<CChar>) -> Int32
#endif
