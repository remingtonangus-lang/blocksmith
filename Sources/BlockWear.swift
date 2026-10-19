import Foundation
import simd

// P305 (Oct 15 12:10, again 19:06-19:08: "bullets should damage blocks", "rounds still don't damage blocks; breaking a
// wall is slow for futuristic weapons"). Rounds wear the blocks they strike, by calibre:
//   weak first  glass and panes go at the first round, leaves at one or two, wool, plants and soft ground at two or
//               three rifle rounds, planks and logs at five or six, stone and brick at a dozen, metal blocks at a
//               magazine; obsidian, armoured and steel blocks, bedrock and anything holding a block entity (chests,
//               furnaces, signs) never.
//   through     a round that breaks a weak block (glass, leaves, panes, wool) goes on through it with what it has left.
//   arc bolts   the arc gun's bolt burns three times as hard and bores on into the block behind.
//   enemy fire  soldiers' rounds wear blocks too (at 60 %), so a wall the player hides behind is shot away.
// Wear heals after two minutes untouched. Quest-safe: at most 4 blocks are shot out a frame (more wear waits for the
// next hit) and at most 768 worn blocks are remembered.
enum BlockWear {
    struct Mark { var dealt: Float; var id: BlockID; var at: Double }
    static var marks: [IVec3: Mark] = [:]
    static let perFrame = 4, maxMarks = 768
    static let heal: Double = 120
    static let enemyShare: Float = 0.6, arcShare: Float = 3
    static var frameAt: Double = -1, brokeThisFrame = 0
    static var shotOut = 0, throughShots = 0     // (counters)

    // Rounds it takes to wear the block away (as damage points); .infinity: rounds never break it.
    static func hp(_ id: BlockID) -> Float {
        let i = Int(id)
        guard i > 0 && i < Blocks.hardness.count else { return .infinity }
        let h = Blocks.hardness[i]
        if h < 0 || !Blocks.collide[i] || Blocks.fluidKind[i] != 0 { return .infinity }
        if Blocks.resistance[i] >= 600 { return .infinity }                       // obsidian, reinforced, steel
        let key = Blocks.key(Blocks.groupBase[i])
        if key.hasPrefix("armored") || key.hasPrefix("tinted") || key.contains("steel") || key.contains("bedrock") { return .infinity }
        if key.hasSuffix("glass") || key.hasSuffix("glass_pane") || key.hasSuffix("_pane") { return 0.5 }
        if CapitalBase.isLeaf(id) { return 2 }
        switch Blocks.def(id).sound {
        case .glass: return 0.5
        case .leaves, .plant, .grass: return 2
        case .wool, .snow, .slime: return 8
        case .dirt, .sand, .gravel, .mud: return 8 + 8 * h
        case .wood: return 14 + 5 * h
        case .metal: return 40 + 20 * h
        default: return 30 + 16 * min(h, 10)
        }
    }
    // A round passes on through what it broke (glass, leaves, panes, wool).
    static func passable(_ id: BlockID) -> Bool { hp(id) <= 8 }

    // Between a and b only blocks rounds can wear away, at most n of them, and at least one (P305 b: a soldier shoots
    // through it). Quarter-block steps; a soldier only asks with a shot ready.
    static func thinCover(_ w: World, _ a: V3, _ b: V3, max n: Int) -> Bool {
        let d = b - a
        let len = simd_length(d)
        guard len > 0.3 && len < 64 else { return false }
        let steps = Int(len / 0.25) + 1
        var count = 0
        var last = IVec3(Int.min, 0, 0)
        for i in 1..<steps {
            let p = a + d * (Float(i) / Float(steps))
            let c = IVec3(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)))
            if c == last { continue }
            last = c
            // P377 step 2: in a field world the drawn ground is never thin cover (a shot doesn't go through a hill);
            // what can be is what was built.
            if w.fieldTerrain && w.fieldDensity(at: p) > 0 { return false }
            let id = w.builtBlock(c.x, c.y, c.z)
            guard Blocks.collide[Int(id)] && Blocks.fluidKind[Int(id)] == 0 else { continue }
            guard hp(id).isFinite && w.blockEntities[c] == nil else { return false }
            count += 1
            if count > n { return false }
        }
        return count > 0
    }

    static func heals(now: Double) {
        if marks.count > maxMarks / 2 { marks = marks.filter { now - $0.value.at < heal } }
        if marks.count > maxMarks {
            let keep = marks.sorted { $0.value.at > $1.value.at }.prefix(maxMarks / 2)
            marks = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
    }
}

extension Game {
    // A round of `damage` struck block b: wears it, and shoots it out once worn through. Returns what the round has left
    // when it broke the block (0 when it stopped in it).
    @discardableResult
    func wearBlock(_ b: IVec3, damage: Float, at: V3, fromPlayer: Bool, arc: Bool = false) -> Float {
        let w = world
        let id = w.materialAt(b.x, b.y, b.z)                // (what it's made of: ground wears as its rock)
        let hp = BlockWear.hp(id)
        guard hp.isFinite, w.blockEntities[b] == nil else { return 0 }
        let scale = (fromPlayer ? 1 : BlockWear.enemyShare) * (arc ? BlockWear.arcShare : 1)
        let dmg = damage * scale
        guard dmg > 0 else { return 0 }
        if clock != BlockWear.frameAt { BlockWear.frameAt = clock; BlockWear.brokeThisFrame = 0 }
        var m = BlockWear.marks[b] ?? BlockWear.Mark(dealt: 0, id: id, at: clock)
        if m.id != id || clock - m.at > BlockWear.heal { m = BlockWear.Mark(dealt: 0, id: id, at: clock) }
        m.dealt += dmg
        m.at = clock
        guard m.dealt >= hp else {
            BlockWear.marks[b] = m
            if BlockWear.marks.count > BlockWear.maxMarks { BlockWear.heals(now: clock) }
            // Worn past half: more grit comes off it.
            if m.dealt > hp * 0.5 { particles.dust(id, at: at, count: 4, spread: 0.12) }
            return 0
        }
        guard BlockWear.brokeThisFrame < BlockWear.perFrame else {
            m.dealt = hp - 0.01; BlockWear.marks[b] = m        // (shot out by the next round)
            return 0
        }
        BlockWear.brokeThisFrame += 1
        BlockWear.marks[b] = nil
        BlockWear.shotOut += 1
        let c = V3(Float(b.x) + 0.5, Float(b.y) + 0.5, Float(b.z) + 0.5)
        w.setBlock(b.x, b.y, b.z, AIR)
        particles.blockBreak(id, at: b)
        let mat = Blocks.def(id).sound
        sfx(mat == .glass ? .glassBreak : .breakBlock(mat), 0.85, at: c)
        return BlockWear.passable(id) ? max(0, m.dealt - hp) / scale : 0
    }
}
