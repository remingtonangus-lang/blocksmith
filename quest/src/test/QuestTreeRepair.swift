import Foundation

// P447: the tidy of trees in land saved before P433 (Sources/TreeRepair.swift). Every current design pasted on its own
// must come through untouched (turned four ways, mirrored, its bole grown); the old designs P433 took out (twin birch,
// tall twin birch, kinked birch, leaning oak, the leaning swamp oak) must lose their second stem or kink, leaving no
// leaf joined to no log that was joined to one before.
//   questcheck --treerepair
enum QuestTreeRepair {
    static func run() -> Int32 {
        setvbuf(stdout, nil, _IOLBF, 0)
        var fails = 0
        func check(_ ok: Bool, _ what: String) { print("\(ok ? "ok  " : "FAIL") treerepair: \(what)"); if !ok { fails += 1 } }
        let H = 48
        func paste(_ s: TreeShape, log: BlockID, leaf: BlockID, turn: Int, mirror: Bool) -> [BlockID] {
            var b = [BlockID](repeating: AIR, count: CSQ * H)
            func put(_ p: IVec3, _ id: BlockID, over: Bool) {
                var x = p.x, z = p.z
                if mirror { x = -x }
                for _ in 0..<turn { (x, z) = (-z, x) }
                let wx = 7 + x, wy = 4 + p.y, wz = 7 + z
                guard wx >= 0 && wx < CS && wz >= 0 && wz < CS && wy >= 0 && wy < H else { return }
                let i = wx + wz * CS + wy * CSQ
                if over || b[i] == AIR { b[i] = id }
            }
            for p in s.logs { put(p, log, over: true) }
            for p in s.roots { put(p, log, over: true) }
            for p in s.leaves { put(p, leaf, over: false) }
            return b
        }
        var designs = 0, untouched = 0
        for (name, kind, set) in TreeShapes.all {
            let (log, leaf) = TreeShapes.materials(kind)
            for s in set { for turn in 0..<4 { for mirror in [false, true] {
                var b = paste(s, log: log, leaf: leaf, turn: turn, mirror: mirror)
                let before = b
                let n = TreeRepair.tidy(&b)
                designs += 1
                if n == 0 && b == before { untouched += 1 } else if turn == 0 && !mirror || n > 0 { print("treerepair: \(name) / \(s.name) turn \(turn)\(mirror ? " mirrored" : ""): \(n) blocks taken out") }
            } } }
        }
        check(untouched == designs, "every current design comes through untouched (\(untouched) of \(designs) pastes)")
        let oak = Blocks.id("oak_log"), birch = Blocks.id("birch_log"), oakLeaf = Blocks.id("oak_leaves"), birchLeaf = Blocks.id("birch_leaves")
        let old: [(TreeShape, BlockID, BlockID, String)] = [
            (TreeShapes.make("twin birch", 13, bole: 3) { d in
                d.trunk(8); d.trunk(5, x: 1, from: 1); d.crown(0, 7, 0, 1.7, 2.4); d.crown(1.5, 6, 0, 1.5, 1.8) }, birch, birchLeaf, "stem"),
            (TreeShapes.make("tall twin birch", 17, bole: 6) { d in
                d.trunk(12); d.trunk(9, z: 1, from: 1); d.crown(0, 11, 0, 1.7, 3.0); d.crown(0, 9, 1.5, 1.5, 2.2) }, birch, birchLeaf, "stem"),
            (TreeShapes.make("kinked birch", 14, bole: 3) { d in d.trunk(4); d.trunk(5, x: 1, from: 3); d.crown(1, 8, 0, 1.9, 2.4) }, birch, birchLeaf, "kink"),
            (TreeShapes.make("leaning oak", 4, bole: 3) { d in
                d.trunk(4); d.trunk(4, x: 1, from: 3)
                do { let t = d.limb(1, 4, 0, -1, 0.6, 2, rise: 1); d.crown(t + IVec3(0, 1, 0), 1.7, 1.3) }
                d.crown(1.5, 7, 0, 2.5, 2.0) }, oak, oakLeaf, "kink"),
            (TreeShapes.make("swamp oak, leaning", 82, bole: 2) { d in
                d.trunk(4); d.trunk(3, x: 1, from: 3); for (k, r) in [3, 3, 2, 1].enumerated() { d.disk(3 + k, 1, 0, r) } }, oak, oakLeaf, "kink"),
        ]
        for (s, log, leaf, want) in old { for turn in [0, 1] {
            var b = paste(s, log: log, leaf: leaf, turn: turn, mirror: false)
            let s0 = TreeRepair.stems, k0 = TreeRepair.kinks
            let logs0 = b.filter { $0 == log }.count, leaves0 = b.filter { $0 == leaf }.count
            // Loose leaves: joined to no log through other leaves (26 neighbours): a clump hanging in the air. The
            // repair may leave none that weren't loose before it ("make sure the leaves don't break off").
            func loose(_ b: [BlockID]) -> Int {
                var held = Set<Int>(), queue: [Int] = []
                for i in 0..<b.count where b[i] == log { held.insert(i); queue.append(i) }
                while let i = queue.popLast() {
                    let x = i % CS, z = (i / CS) % CS, y = i / CSQ
                    for dy in -1...1 { for dz in -1...1 { for dx in -1...1 {
                        let xx = x + dx, yy = y + dy, zz = z + dz
                        guard xx >= 0 && xx < CS && zz >= 0 && zz < CS && yy >= 0 && yy < H else { continue }
                        let j = xx + zz * CS + yy * CSQ
                        if b[j] == leaf && held.insert(j).inserted { queue.append(j) }
                    } } }
                }
                return (0..<b.count).filter { b[$0] == leaf && !held.contains($0) }.count
            }
            let loose0 = loose(b)
            let n = TreeRepair.tidy(&b)
            let logs1 = b.filter { $0 == log }.count, leaves1 = b.filter { $0 == leaf }.count
            let loose1 = loose(b)
            let got = TreeRepair.stems > s0 ? "stem" : (TreeRepair.kinks > k0 ? "kink" : "nothing")
            check(got == want && n > 0 && loose1 <= loose0,
                  "\(s.name) turned \(turn): \(got) taken out (logs \(logs0) -> \(logs1), leaves \(leaves0) -> \(leaves1), leaves joined to no log \(loose0) -> \(loose1))")
        } }
        print(fails == 0 ? "treerepair: all passed" : "treerepair: \(fails) failed")
        return fails == 0 ? 0 : 1
    }
}
