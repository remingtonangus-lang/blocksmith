import Foundation

// Ledger 408 (Nov 20 evening playthrough, his own voice notes): a furnace broken while it burned gave nothing back (the
// lit state has no item), and a burning smoker or blast furnace gave no light. The smoker and the blast furnace get
// hidden lit twins like the furnace's; code that asks what a block is (job sites, opening, pistons) reads the plain key.
enum FurnaceGlow {
    static let oldDrop = ProcessInfo.processInfo.environment["BS_OLDFURNACEDROP"] == "1"
    static let oldGlow = ProcessInfo.processInfo.environment["BS_OLDBLASTGLOW"] == "1"
    static let twins = ["smoker", "blast_furnace"]

    // "lit_smoker" -> "smoker" (and lit_furnace -> furnace); any other key as it is.
    @inline(__always) static func unlit(_ k: String) -> String {
        guard k.hasPrefix("lit_") else { return k }
        let s = String(k.dropFirst(4))
        return s == "furnace" || twins.contains(s) ? s : k
    }

    // A smoker or blast furnace at p shows lit while it burns. True when p holds one (handled), so the caller skips
    // the furnace's own swap.
    @discardableResult
    static func follow(_ w: World, _ p: IVec3, burning: Bool) -> Bool {
        let b = w.block(p.x, p.y, p.z)
        let k = Blocks.key(Blocks.groupBase[Int(b)])
        let plain = unlit(k)
        guard twins.contains(plain) else { return false }
        guard !oldGlow, Blocks.has("lit_" + plain) else { return true }
        let want = burning ? "lit_" + plain : plain
        if k != want { w.setBlock(p.x, p.y, p.z, Blocks.id(want)) }
        return true
    }
}
