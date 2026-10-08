import Foundation

// Sparkstone components. State layouts (offset from the group's first state):
//   sparkstone_wire:   power (16)
//   sparkstone_torch:  0 standing lit, 1 standing off, 2+f wall lit, 6+f wall off (f = side the torch faces)
//   lever / buttons: facing + attach*4 + on*12           attach 0 floor, 1 wall, 2 ceiling  (24)
//   pressure plates: pressed (2); weighted plates: power (16)
//   repeater:        facing + (delay-1)*4 + powered*16 + locked*32   (64)
//   comparator:      facing + subtract*4 + powered*8      (16)
//   observer:        dir6 + powered*6                     (12)
//   piston:          dir6 + extended*6                    (12)   piston_head: dir6 + sticky*6 (12)
//   dispenser/dropper: dir6 + triggered*6                 (12)
//   hopper:          out (0 down, 1 north, 2 south, 3 west, 4 east) + locked*5  (10)
//   note_block:      note (25)
//   daylight_detector: power + inverted*16                (32)
//   target:          power (16)
// dir6: 0 down, 1 up, 2 north(-Z), 3 south(+Z), 4 west(-X), 5 east(+X). facing (4): 0 north, 1 south, 2 west, 3 east.
extension BlockRegistry {
    static let dir6 = [IVec3(0, -1, 0), IVec3(0, 1, 0), IVec3(0, 0, -1), IVec3(0, 0, 1), IVec3(-1, 0, 0), IVec3(1, 0, 0)]
    static let buttonWoods = ["oak", "spruce", "birch", "jungle", "acacia", "dark_oak", "mangrove", "cherry", "crimson", "warped", "pale_oak"]

    // Face index (+X -X +Y -Y +Z -Z) of a dir6.
    static func faceOf(_ d: Int) -> Int { [3, 2, 5, 4, 1, 0][d] }

    // A 6-way facing cube: `front` on the facing side, `back` opposite, `side` elsewhere (tops use `side` too).
    static func facedTex(_ d: Int, front: String, back: String, side: String, top: String? = nil) -> [String] {
        var t = [String](repeating: side, count: 6)
        if let tp = top, d >= 2 { t[2] = tp; t[3] = tp }
        let opposite = [1, 0, 3, 2, 5, 4][d]
        t[faceOf(d)] = front
        t[faceOf(opposite)] = back
        return t
    }

    // The slab of a block between distance a and b (1/16) from one of its 6 sides.
    static func slab6(_ d: Int, from a: Int, to b: Int) -> Box {
        switch d {
        case 0: return Box(0, a, 0, 16, b, 16)
        case 1: return Box(0, 16 - b, 0, 16, 16 - a, 16)
        case 2: return Box(0, 0, a, 16, 16, b)
        case 3: return Box(0, 0, 16 - b, 16, 16, 16 - a)
        case 4: return Box(a, 0, 0, b, 16, 16)
        default: return Box(16 - b, 0, 0, 16 - a, 16, 16)
        }
    }

    // Small attached part (button/lever base) on floor, wall (facing f: part sits on the side opposite f) or ceiling.
    static func attached(_ attach: Int, _ f: Int, w: Int, h: Int, d: Int) -> Box {
        let a = (16 - w) / 2, b = (16 + w) / 2, c = (16 - h) / 2, e = (16 + h) / 2
        switch attach {
        case 0: return (f <= 1) ? Box(a, 0, c, b, d, e) : Box(c, 0, a, e, d, b)
        case 2: return (f <= 1) ? Box(a, 16 - d, c, b, 16, e) : Box(c, 16 - d, a, e, 16, b)
        default:
            switch f {
            case 0: return Box(a, c, 16 - d, b, e, 16)     // faces north, mounted on the block to the south
            case 1: return Box(a, c, 0, b, e, d)
            case 2: return Box(16 - d, c, a, 16, e, b)
            default: return Box(0, c, a, d, e, b)
            }
        }
    }

    func registerCircuitBlocks() {
        func state(_ n: String, _ group: String, _ disp: String, _ first: Bool) -> BlockDef {
            var d = BlockDef(n, disp)
            d.group = group; d.hidden = !first
            return d
        }
        // Dust.
        for p in 0..<16 {
            var d = state(p == 0 ? "redstone_wire" : "redstone_wire[\(p)]", "redstone_wire", "Copper Wire", p == 0)
            d.tex = ["redstone_dust_\(p)"]; d.render = .wire; d.layer = .cutout; d.opaque = false; d.collide = false
            d.hardness = 0; d.sound = .stone; d.skyStop = false; d.boxes = [Box(0, 0, 0, 16, 1, 16)]; d.hidden = true
            add(d)
        }
        // Torches.
        for k in 0..<10 {
            let lit = k == 0 || (k >= 2 && k < 6)
            var d = state(k == 0 ? "redstone_torch" : "redstone_torch[\(k)]", "redstone_torch", "Copper Signal Torch", k == 0)
            d.tex = [lit ? "redstone_torch" : "redstone_torch_off"]; d.render = .model; d.layer = .cutout; d.opaque = false
            d.collide = false; d.emit = lit ? 7 : 0; d.hardness = 0; d.sound = .wood; d.skyStop = false
            if k < 2 { d.boxes = [Box(7, 0, 7, 9, 10, 9)] }
            else {
                let f = (k - 2) % 4
                d.boxes = [[Box(7, 3, 12, 9, 13, 14), Box(7, 3, 2, 9, 13, 4), Box(12, 3, 7, 14, 13, 9), Box(2, 3, 7, 4, 13, 9)][f]]
            }
            add(d)
        }
        for lit in [false, true] {
            var d = state(lit ? "redstone_lamp[lit]" : "redstone_lamp", "redstone_lamp", "Copper Lamp", !lit)
            d.tex = [lit ? "redstone_lamp_on" : "redstone_lamp"]; d.emit = lit ? 15 : 0; d.hardness = 0.3; d.sound = .glass
            add(d)
        }
        // Lever and buttons.
        func switchBlock(_ n: String, _ disp: String, tex: String, lever: Bool) {
            for on in [false, true] { for attach in 0..<3 { for f in 0..<4 {
                let k = f + attach * 4 + (on ? 12 : 0)
                var d = state(k == 0 ? n : "\(n)[\(k)]", n, disp, k == 0)
                d.tex = [tex]; d.render = .model; d.layer = .cutout; d.opaque = false; d.collide = false; d.hardness = 0.5
                d.sound = lever ? .wood : .stone; d.skyStop = false; d.shape = lever ? "lever" : "button"
                if lever {
                    let base = BlockRegistry.attached(attach, f, w: 6, h: 8, d: 3)
                    var handle: Box
                    switch attach {
                    case 0: handle = on ? Box(7, 3, 5, 9, 10, 7) : Box(7, 3, 9, 9, 10, 11)
                    case 2: handle = on ? Box(7, 6, 5, 9, 13, 7) : Box(7, 6, 9, 9, 13, 11)
                    default:
                        let ys = on ? (4, 10) : (6, 12)
                        handle = [Box(7, ys.0, 9, 9, ys.1, 14), Box(7, ys.0, 2, 9, ys.1, 7), Box(9, ys.0, 7, 14, ys.1, 9), Box(2, ys.0, 7, 7, ys.1, 9)][f]
                    }
                    handle.tex = Array(repeating: Tex.id("lever"), count: 6)
                    var b2 = base; b2.tex = Array(repeating: Tex.id("cobblestone"), count: 6)
                    d.boxes = [b2, handle]
                } else {
                    d.boxes = [BlockRegistry.attached(attach, f, w: 6, h: 4, d: on ? 1 : 2)]
                }
                add(d)
            } } }
        }
        switchBlock("lever", "Lever", tex: "lever", lever: true)
        switchBlock("stone_button", "Stone Button", tex: "stone", lever: false)
        switchBlock("polished_blackstone_button", "Polished Onyxstone Button", tex: "polished_blackstone", lever: false)
        for w in BlockRegistry.buttonWoods {
            switchBlock("\(w)_button", "\(BlockRegistry.woodName(w)) Button", tex: "\(w)_planks", lever: false)
        }
        // Pressure plates.
        func plate(_ n: String, _ disp: String, tex: String, levels: Int, wood: Bool) {
            for k in 0..<levels {
                var d = state(k == 0 ? n : "\(n)[\(k)]", n, disp, k == 0)
                d.tex = [tex]; d.render = .model; d.opaque = false; d.collide = false; d.hardness = 0.5; d.skyStop = false
                d.sound = wood ? .wood : .stone; d.tool = wood ? .axe : .pickaxe; d.shape = "plate"
                d.boxes = [Box(1, 0, 1, 15, k > 0 ? 1 : 1, 15)]
                if k == 0 { d.boxes = [Box(1, 0, 1, 15, 1, 15)] }
                add(d)
            }
        }
        for w in BlockRegistry.buttonWoods {
            plate("\(w)_pressure_plate", "\(BlockRegistry.woodName(w)) Pressure Plate", tex: "\(w)_planks", levels: 2, wood: true)
        }
        plate("stone_pressure_plate", "Stone Pressure Plate", tex: "stone", levels: 2, wood: false)
        plate("polished_blackstone_pressure_plate", "Polished Onyxstone Pressure Plate", tex: "polished_blackstone", levels: 2, wood: false)
        plate("light_weighted_pressure_plate", "Light Weighted Pressure Plate", tex: "gold_block", levels: 16, wood: false)
        plate("heavy_weighted_pressure_plate", "Heavy Weighted Pressure Plate", tex: "iron_block", levels: 16, wood: false)
        // Repeater and comparator.
        for locked in [false, true] { for powered in [false, true] { for delay in 0..<4 { for f in 0..<4 {
            let k = f + delay * 4 + (powered ? 16 : 0) + (locked ? 32 : 0)
            var d = state(k == 0 ? "repeater" : "repeater[\(k)]", "repeater", "Copper Repeater", k == 0)
            d.tex = [powered ? "repeater_on" : "repeater", powered ? "repeater_on" : "repeater", powered ? "repeater_on" : "repeater", "smooth_stone", powered ? "repeater_on" : "repeater", powered ? "repeater_on" : "repeater"]
            d.render = .model; d.opaque = false; d.hardness = 0; d.sound = .stone; d.skyStop = false; d.shape = "repeater"
            let torchTex = Array(repeating: Tex.id(powered ? "redstone_torch" : "redstone_torch_off"), count: 6)
            let slab = Box(0, 0, 0, 16, 2, 16)
            // Output (front) torch fixed, input torch moves with the delay.
            let along = [(0, -1), (0, 1), (-1, 0), (1, 0)][f]
            let frontC = 8 + along.0 * 5, frontZ = 8 + along.1 * 5
            let backOff = -1 + delay * 2
            let backC = 8 - along.0 * backOff, backZ = 8 - along.1 * backOff
            var t1 = Box(frontC - 1, 2, frontZ - 1, frontC + 1, 7, frontZ + 1); t1.tex = torchTex
            var t2: Box
            if locked {
                t2 = f <= 1 ? Box(2, 2, backZ - 1, 14, 4, backZ + 1) : Box(backC - 1, 2, 2, backC + 1, 4, 14)
                t2.tex = Array(repeating: Tex.id("bedrock"), count: 6)
            } else { t2 = Box(backC - 1, 2, backZ - 1, backC + 1, 7, backZ + 1); t2.tex = torchTex }
            d.boxes = [slab, t1, t2]; d.emit = 0; d.hidden = k != 0
            add(d)
        } } } }
        for powered in [false, true] { for sub in [false, true] { for f in 0..<4 {
            let k = f + (sub ? 4 : 0) + (powered ? 8 : 0)
            var d = state(k == 0 ? "comparator" : "comparator[\(k)]", "comparator", "Copper Comparator", k == 0)
            d.tex = [powered ? "comparator_on" : "comparator", powered ? "comparator_on" : "comparator", powered ? "comparator_on" : "comparator", "smooth_stone", powered ? "comparator_on" : "comparator", powered ? "comparator_on" : "comparator"]
            d.render = .model; d.opaque = false; d.hardness = 0; d.sound = .stone; d.skyStop = false; d.shape = "comparator"
            let along = [(0, -1), (0, 1), (-1, 0), (1, 0)][f]
            let torch = Array(repeating: Tex.id(powered ? "redstone_torch" : "redstone_torch_off"), count: 6)
            var front = Box(8 + along.0 * 5 - 1, 2, 8 + along.1 * 5 - 1, 8 + along.0 * 5 + 1, sub ? 6 : 4, 8 + along.1 * 5 + 1); front.tex = torch
            let side = (along.1, along.0)
            var b1 = Box(8 - along.0 * 4 + side.0 * 4 - 1, 2, 8 - along.1 * 4 + side.1 * 4 - 1, 8 - along.0 * 4 + side.0 * 4 + 1, 7, 8 - along.1 * 4 + side.1 * 4 + 1); b1.tex = torch
            var b2 = Box(8 - along.0 * 4 - side.0 * 4 - 1, 2, 8 - along.1 * 4 - side.1 * 4 - 1, 8 - along.0 * 4 - side.0 * 4 + 1, 7, 8 - along.1 * 4 - side.1 * 4 + 1); b2.tex = torch
            d.boxes = [Box(0, 0, 0, 16, 2, 16), front, b1, b2]
            add(d)
        } } }
        // Observer.
        for powered in [false, true] { for dd in 0..<6 {
            let k = dd + (powered ? 6 : 0)
            var d = state(k == 0 ? "observer" : "observer[\(k)]", "observer", "Observer", k == 0)
            d.tex = BlockRegistry.facedTex(dd, front: "observer_front", back: powered ? "observer_back_on" : "observer_back", side: "observer_side", top: "observer_top")
            d.hardness = 3; d.tool = .pickaxe; d.requiresTool = true; d.shape = "observer"
            add(d)
        } }
        // Pistons and heads.
        for sticky in [false, true] {
            let n = sticky ? "sticky_piston" : "piston"
            for ext in [false, true] { for dd in 0..<6 {
                let k = dd + (ext ? 6 : 0)
                var d = state(k == 0 ? n : "\(n)[\(k)]", n, sticky ? "Sticky Piston" : "Piston", k == 0)
                d.tex = BlockRegistry.facedTex(dd, front: ext ? "piston_inner" : (sticky ? "piston_top_sticky" : "piston_top"), back: "piston_bottom", side: "piston_side")
                d.hardness = 1.5; d.tool = .pickaxe; d.shape = "piston"
                if ext { d.render = .model; d.opaque = false; d.boxes = [BlockRegistry.slab6([1, 0, 3, 2, 5, 4][dd], from: 0, to: 12)] }
                add(d)
            } }
        }
        for sticky in [false, true] { for dd in 0..<6 {
            let k = dd + (sticky ? 6 : 0)
            var d = state(k == 0 ? "piston_head" : "piston_head[\(k)]", "piston_head", "Piston Head", k == 0)
            d.tex = BlockRegistry.facedTex(dd, front: sticky ? "piston_top_sticky" : "piston_top", back: "piston_top", side: "piston_side")
            d.render = .model; d.opaque = false; d.hardness = 1.5; d.tool = .pickaxe; d.hidden = true; d.skyStop = false
            let plate = BlockRegistry.slab6(dd, from: 0, to: 4)
            let arm: Box
            switch dd {
            case 0: arm = Box(6, 4, 6, 10, 16, 10)
            case 1: arm = Box(6, 0, 6, 10, 12, 10)
            case 2: arm = Box(6, 6, 4, 10, 10, 16)
            case 3: arm = Box(6, 6, 0, 10, 10, 12)
            case 4: arm = Box(4, 6, 6, 16, 10, 10)
            default: arm = Box(0, 6, 6, 12, 10, 10)
            }
            var a2 = arm; a2.tex = Array(repeating: Tex.id("piston_side"), count: 6)
            d.boxes = [plate, a2]
            add(d)
        } }
        var slime = BlockDef("slime_block", "Slime Block")
        slime.tex = ["slime_block"]; slime.layer = .translucent; slime.opaque = false; slime.hardness = 0; slime.sound = .plant; slime.cullSame = true
        add(slime)
        var honey = BlockDef("honey_block", "Honey Block")
        honey.tex = ["honey_block"]; honey.layer = .translucent; honey.opaque = false; honey.hardness = 0; honey.sound = .plant; honey.cullSame = true
        add(honey)
        // Dispenser, dropper.
        for n in ["dispenser", "dropper"] {
            for trig in [false, true] { for dd in 0..<6 {
                let k = dd + (trig ? 6 : 0)
                var d = state(k == 0 ? n : "\(n)[\(k)]", n, n.capitalized, k == 0)
                d.tex = BlockRegistry.facedTex(dd, front: dd <= 1 ? "\(n)_front_vertical" : "\(n)_front", back: "furnace_side", side: "furnace_side", top: "furnace_top")
                d.hardness = 3.5; d.tool = .pickaxe; d.requiresTool = true; d.shape = "dispenser"
                add(d)
            } }
        }
        // Hopper.
        for locked in [false, true] { for out in 0..<5 {
            let k = out + (locked ? 5 : 0)
            var d = state(k == 0 ? "hopper" : "hopper[\(k)]", "hopper", "Hopper", k == 0)
            d.tex = ["hopper_outside", "hopper_outside", "hopper_top", "hopper_outside", "hopper_outside", "hopper_outside"]
            d.render = .model; d.opaque = false; d.hardness = 3; d.tool = .pickaxe; d.requiresTool = true; d.shape = "hopper"; d.skyStop = false
            var boxes = [Box(0, 10, 0, 16, 11, 16), Box(0, 11, 0, 2, 16, 16), Box(14, 11, 0, 16, 16, 16), Box(2, 11, 0, 14, 16, 2), Box(2, 11, 14, 14, 16, 16),
                         Box(4, 4, 4, 12, 10, 12)]
            boxes.append([Box(6, 0, 6, 10, 4, 10), Box(6, 4, 0, 10, 8, 4), Box(6, 4, 12, 10, 8, 16), Box(0, 4, 6, 4, 8, 10), Box(12, 4, 6, 16, 8, 10)][out])
            d.boxes = boxes
            add(d)
        } }
        // Note block, daylight detector, target.
        for note in 0..<25 {
            var d = state(note == 0 ? "note_block" : "note_block[\(note)]", "note_block", "Note Block", note == 0)
            d.tex = ["note_block"]; d.hardness = 0.8; d.tool = .axe; d.sound = .wood; d.shape = "note_block"
            add(d)
        }
        for inv in [false, true] { for p in 0..<16 {
            let k = p + (inv ? 16 : 0)
            var d = state(k == 0 ? "daylight_detector" : "daylight_detector[\(k)]", "daylight_detector", "Daylight Detector", k == 0)
            d.tex = ["daylight_detector_side", "daylight_detector_side", inv ? "daylight_detector_inverted_top" : "daylight_detector_top", "oak_planks", "daylight_detector_side", "daylight_detector_side"]
            d.render = .model; d.opaque = false; d.boxes = [Box(0, 0, 0, 16, 6, 16)]; d.hardness = 0.2; d.tool = .axe; d.sound = .wood
            d.shape = "daylight"; d.skyStop = false
            add(d)
        } }
        // Rails. Shapes: 0 N-S, 1 E-W, 2-5 ascending east/west/north/south, 6-9 curves SE, SW, NW, NE.
        for shape in 0..<10 {
            var d = state(shape == 0 ? "rail" : "rail[\(shape)]", "rail", "Rail", shape == 0)
            d.tex = [shape >= 6 ? "rail_corner" : "rail"]; d.render = .rail; d.layer = .cutout; d.opaque = false; d.collide = false
            d.boxes = [Box(0, 0, 0, 16, 2, 16)]; d.hardness = 0.7; d.tool = .pickaxe; d.sound = .stone; d.skyStop = false; d.shape = "rail"
            add(d)
        }
        for n in ["powered_rail", "detector_rail", "activator_rail"] {
            for on in [false, true] { for shape in 0..<6 {
                let k = shape + (on ? 6 : 0)
                var d = state(k == 0 ? n : "\(n)[\(k)]", n, n.split(separator: "_").map { $0.capitalized }.joined(separator: " "), k == 0)
                d.tex = [on ? "\(n)_on" : n]; d.render = .rail; d.layer = .cutout; d.opaque = false; d.collide = false
                d.boxes = [Box(0, 0, 0, 16, 2, 16)]; d.hardness = 0.7; d.tool = .pickaxe; d.sound = .stone; d.skyStop = false; d.shape = "rail"
                d.emit = n == "powered_rail" && on ? 0 : 0
                add(d)
            } }
        }
        for p in 0..<16 {
            var d = state(p == 0 ? "target" : "target[\(p)]", "target", "Target", p == 0)
            d.tex = ["target_side", "target_side", "target_top", "target_top", "target_side", "target_side"]; d.hardness = 0.5; d.tool = .hoe; d.sound = .plant
            add(d)
        }
    }
}
