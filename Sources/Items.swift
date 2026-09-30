import Foundation

// Items: everything that can sit in an inventory slot. Every placeable block has a block item
// (same name); tools, food and materials are registered below.
typealias ItemID = UInt16

struct FoodInfo { var hunger: Int; var saturation: Float }

struct ItemDef {
    var name: String
    var display: String
    var maxStack = 64
    var block: BlockID? = nil        // places this block state
    var tex: String? = nil           // sprite texture (nil for block items: drawn as a block icon)
    var food: FoodInfo? = nil
    var tool: ToolType = .none
    var tier = 0                     // 0 wood, 1 stone, 2 iron, 3 diamond, 4 netherite, 5 gold
    var durability = 0
    var attack: Float = 1
    init(_ name: String, _ display: String) { self.name = name; self.display = display }
}

final class ItemRegistry {
    private(set) var defs: [ItemDef] = []
    private var byName: [String: ItemID] = [:]
    private(set) var forBlock: [ItemID]    // indexed by block group base state; 0 = none

    var count: Int { defs.count }

    @discardableResult
    func add(_ d: ItemDef) -> ItemID {
        let i = ItemID(defs.count)
        precondition(byName[d.name] == nil, "duplicate item \(d.name)")
        byName[d.name] = i
        defs.append(d)
        if let t = d.tex { _ = Tex.id(t) }
        return i
    }

    func id(_ name: String) -> ItemID {
        guard let i = byName[name] else { fatalError("unknown item \(name)") }
        return i
    }
    func has(_ name: String) -> Bool { byName[name] != nil }
    func def(_ i: ItemID) -> ItemDef { defs[Int(i)] }
    func name(_ i: ItemID) -> String { Int(i) < defs.count ? defs[Int(i)].display : "?" }

    // Item that a given block state drops/picks as (its group's block item), or nil.
    func item(forBlock b: BlockID) -> ItemID? {
        let base = Int(Blocks.groupBase[Int(b)])
        let i = forBlock[base]
        return i == 0 ? nil : i
    }

    init() {
        forBlock = [ItemID](repeating: 0, count: Blocks.count)
        var air = ItemDef("air", "Air")
        air.maxStack = 0
        add(air)
        for b in 1..<Blocks.count where Int(Blocks.groupBase[b]) == b && !Blocks.hidden[b] {
            let bd = Blocks.def(BlockID(b))
            var d = ItemDef(bd.name, bd.display)
            d.block = BlockID(b)
            forBlock[b] = add(d)
        }
        func food(_ n: String, _ disp: String, _ h: Int, _ s: Float) {
            var d = ItemDef(n, disp)
            d.tex = n
            d.food = FoodInfo(hunger: h, saturation: s)
            add(d)
        }
        food("apple", "Apple", 4, 2.4)
    }
}

let Items = ItemRegistry()

enum ItemTextures {
    static func painters() -> [String: TextureGen.Painter] {
        let r = TextureGen.r
        var p: [String: TextureGen.Painter] = [:]
        p["apple"] = { x, y in
            if x == 8 && y >= 1 && y <= 4 { return TextureGen.hex(0x5A3D1F) }
            if y >= 1 && y <= 3 && x >= 9 && x <= 11 && (x - 9) == (3 - y) { return TextureGen.hex(0x4D9E33) }
            let dx = Float(x) - 7.5, dy = Float(y) - 9.5
            let d = (dx * dx + dy * dy * 1.1).squareRoot()
            if d < 5.8 {
                if dx < -1.5 && dy < -1.5 && d > 2.5 && d < 4.2 { return V4(1, 0.72, 0.68, 1) }
                return TextureGen.hex(0xD11F1A, 0.85 + 0.2 * (1 - d / 6) + 0.05 * r(x, y, 1))
            }
            return TextureGen.clear
        }
        return p
    }
}
