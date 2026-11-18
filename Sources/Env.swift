import Foundation

// Ledger 166 (Nov 15, a profile of the garrison's tick): every `Env.all[...]` builds the
// whole environment as a dictionary again (2.6 million instructions a read on the build machine), and the game has some
// 450 before/after switches that each read it the first time their code runs: the first blast, the first felled tree,
// the first soldier to fire each stalled the frame for one or more of them, and a table built with a read for every
// block state read it thousands of times. The environment is read once here. (A variable the game itself sets after
// launch, BLOCKSMITH_TEXRES, is still read from the process.)
enum Env {
    static var all: [String: String] = load()
    // Ledger 291 (Nov 18, his Nov 17 evening playtest: a route left set by the gate ran on a launch he made, and moved
    // him about for 7 minutes): the debug properties count only for the launch the headset gate made (AndroidMain
    // checks its stamp: set within 15 minutes, used once). Not allowed, `all` is the process environment alone.
    static var propsAllowed = true
    static func load() -> [String: String] {
        var e = ProcessInfo.processInfo.environment
        #if os(Android)
        // Ledger 284 (store review, the headset gate): the headset app has no environment to set, so its before/after
        // switches could only be tried by building again. The debug properties debug.sunderfall.env, env2 ... env6
        // ("BS_A=1;BS_B=0", set with `adb shell setprop`; a property holds at most 91 characters) are merged in at
        // launch: a switch is A/B tested on the real headset with a restart. A long list goes over several properties
        // with "+=" (QUEST_SKIP=sky,clouds in one, QUEST_SKIP+=far,trans in the next: joined with a comma); env4-env6 too. Unset (every player's headset: debug.*
        // properties take adb), nothing changes.
        var set: [String] = []
        let props = ["debug.sunderfall.env"] + (2...6).map { "debug.sunderfall.env\($0)" }
        for p in propsAllowed ? props : [] {
            for pair in androidProperty(p).split(separator: ";") {
                let kv = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard kv.count == 2, !kv[0].isEmpty else { continue }
                if kv[0].hasSuffix("+") {
                    let k = String(kv[0].dropLast())
                    e[k] = (e[k].map { $0 + "," } ?? "") + kv[1]; set.append("\(k)+=\(kv[1])")
                } else { e[kv[0]] = kv[1]; set.append("\(kv[0])=\(kv[1])") }
            }
        }
        if !set.isEmpty { print("env: from debug properties: " + set.joined(separator: " ")) }
        #endif
        return e
    }

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
