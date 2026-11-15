import Foundation

// Ledger 166 (Nov 15, a profile of the garrison's tick): every `Env.all[...]` builds the
// whole environment as a dictionary again (2.6 million instructions a read on the build machine), and the game has some
// 450 before/after switches that each read it the first time their code runs: the first blast, the first felled tree,
// the first soldier to fire each stalled the frame for one or more of them, and a table built with a read for every
// block state read it thousands of times. The environment is read once here. (A variable the game itself sets after
// launch, BLOCKSMITH_TEXRES, is still read from the process.)
enum Env {
    static let all: [String: String] = ProcessInfo.processInfo.environment
}
