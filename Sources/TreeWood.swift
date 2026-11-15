import Foundation

// Nov 15 (Remington, Nov 14 evening: "No procedural anything... we're gonna have 100 preset trees"; "I break a stump,
// that tree model falls over and the log itself is its own shape. It doesn't break pieces off it. I get the logs in
// inventory"; a log post he set down "got a stump"): a tree's wood is its own block, apart from the logs he builds with.
//  - Every tree the generator or a sapling grows is made of `tree_<wood>_log` (TreeWriter.tree). It looks, sounds and
//    drops as the log does; it has no place in the creative list.
//  - Only tree wood is drawn as a tree (ShapeTrunks: tapered trunk, root flare, limbs). A plain log is timber wherever
//    it stands: a post, a beam, never a stump or a bough, whatever is beside it.
//  - A tree is whole or gone: a blow to any of its wood brings the whole tree down as one body in the shape it stood
//    with (Game.fellWhole), stump and all.
// BS_OLDTREEWOOD=1: before (trees of plain logs, told from timber by what stood round them).
enum TreeWood {
    static var on = ProcessInfo.processInfo.environment["BS_OLDTREEWOOD"] != "1"
    static let prefix = "tree_"
    // (checks of the rules before: trees of plain logs for as long as `body` runs, worlds made in it included)
    static func asBefore(_ body: () -> Void) { let o = on; on = false; body(); on = o }
    // The woods that grow as trees (Woods.all's "log" ones).
    static var woods: [String] { Woods.all.filter { $0.2 == "log" }.map { $0.0 } }
    // A log state -> its tree twin (the same axis); anything else -> itself.
    static let twin: [BlockID] = (0..<Blocks.count).map { i in
        let b = BlockID(i)
        let base = Blocks.groupBase[i]
        let k = Blocks.key(base)
        guard k.hasSuffix("_log"), !k.hasPrefix(prefix), !k.hasPrefix("stripped_"), Blocks.has(prefix + k) else { return b }
        return Blocks.id(prefix + k) + (b - base)
    }
    // The wood a planted tree is made of (a structure's own trees: a town planter, an isle's oaks).
    static func of(_ log: BlockID) -> BlockID { on ? twin[Int(log)] : log }
    // Tree wood (every axis state).
    static let isTree: [Bool] = (0..<Blocks.count).map { i in
        let k = Blocks.key(Blocks.groupBase[i])
        return k.hasPrefix(prefix) && k.hasSuffix("_log")
    }
    // Tree wood -> the plain log (what it drops, what a blow leaves in his hand).
    static let plain: [BlockID] = (0..<Blocks.count).map { i in
        let b = BlockID(i)
        guard isTree[i] else { return b }
        let base = Blocks.groupBase[i]
        return Blocks.id(String(Blocks.key(base).dropFirst(prefix.count))) + (b - base)
    }
}

extension BlockRegistry {
    func registerTreeWood() {
        for w in TreeWood.woods where has("\(w)_log") {
            let n = "\(TreeWood.prefix)\(w)_log"
            let side = "\(w)_log", top = "\(w)_log_top", r = side + "@r"
            for (i, sfx) in ["", "[x]", "[z]"].enumerated() {
                var d = BlockDef(n + sfx, "\(BlockRegistry.woodName(w)) Log")
                d.group = n; d.hidden = true
                switch i {
                case 1: d.tex = [top, top, r, r, r, r]
                case 2: d.tex = [r, r, side, side, top, top]
                default: d.tex = [side, side, top, top, side, side]
                }
                d.hardness = 2; d.tool = .axe; d.sound = .wood
                add(d)
            }
        }
    }
}
