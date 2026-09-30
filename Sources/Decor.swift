import Foundation
import simd

// Signs (editable, text drawn in the world), item frames (+ glow), paintings (reference motives and
// sizes, original art) and armor stands.
enum Paintings {
    // name, width, height (blocks)
    static let motives: [(String, Int, Int)] = [
        ("kebab", 1, 1), ("aztec", 1, 1), ("alban", 1, 1), ("aztec2", 1, 1), ("bomb", 1, 1), ("plant", 1, 1), ("wasteland", 1, 1),
        ("meditative", 1, 1), ("pool", 2, 1), ("courbet", 2, 1), ("sea", 2, 1), ("sunset", 2, 1), ("creebet", 2, 1),
        ("wanderer", 1, 2), ("graham", 1, 2), ("prairie_ride", 1, 2), ("match", 2, 2), ("bust", 2, 2), ("stage", 2, 2), ("void", 2, 2),
        ("skull_and_roses", 2, 2), ("wither", 2, 2), ("earth", 2, 2), ("wind", 2, 2), ("water", 2, 2), ("fire", 2, 2), ("baroque", 2, 2),
        ("humble", 2, 2), ("fighters", 4, 2), ("changing", 4, 2), ("finding", 4, 2), ("lowmist", 4, 2), ("passage", 4, 2),
        ("skeleton", 4, 3), ("donkey_kong", 4, 3), ("pointer", 4, 4), ("pigscene", 4, 4), ("burning_skull", 4, 4), ("orb", 4, 4),
        ("unpacked", 4, 4),
    ]
}

extension BlockRegistry {
    func registerDecorBlocks() {
        // Signs: 4 standing facings (0-3) + 4 wall facings (4-7), per wood.
        for wood in BlockRegistry.doorWoods {
            let disp = BlockRegistry.woodName(wood)
            for st in 0..<8 {
                let f = st % 4
                var d = BlockDef(st == 0 ? "\(wood)_sign" : "\(wood)_sign[\(st)]", "\(disp) Sign")
                d.group = "\(wood)_sign"; d.hidden = st != 0; d.shape = "sign"
                d.tex = ["\(wood)_planks"]; d.render = .model; d.opaque = false; d.collide = false; d.hardness = 1; d.tool = .axe; d.sound = .wood
                d.skyStop = false
                let ns = f < 2
                if st < 4 {
                    d.boxes = [ns ? Box(0, 7, 7, 16, 15, 9) : Box(7, 7, 0, 9, 15, 16), Box(7, 0, 7, 9, 7, 9, tex: [UInt16](repeating: Tex.id(wood == "crimson" || wood == "warped" ? "\(wood)_stem" : "\(wood)_log"), count: 6))]
                } else {
                    d.boxes = [[Box(0, 4, 14, 16, 12, 16), Box(0, 4, 0, 16, 12, 2), Box(14, 4, 0, 16, 12, 16), Box(0, 4, 0, 2, 12, 16)][f]]
                }
                add(d)
            }
        }
        // Hanging signs: 4 ceiling facings (0-3, chains up) + 4 wall facings (4-7, hung from a bar).
        for wood in BlockRegistry.doorWoods {
            let disp = BlockRegistry.woodName(wood)
            for st in 0..<8 {
                let f = st % 4, ns = f < 2
                var d = BlockDef(st == 0 ? "\(wood)_hanging_sign" : "\(wood)_hanging_sign[\(st)]", "\(disp) Hanging Sign")
                d.group = "\(wood)_hanging_sign"; d.hidden = st != 0; d.shape = "hsign"
                d.tex = ["\(wood)_planks"]; d.render = .model; d.opaque = false; d.collide = false; d.hardness = 1; d.tool = .axe; d.sound = .wood
                d.skyStop = false
                let board = ns ? Box(1, 0, 7, 15, 10, 9) : Box(7, 0, 1, 9, 10, 15)
                let chain = [UInt16](repeating: Tex.id("chain"), count: 6)
                if st < 4 {
                    d.boxes = [board, ns ? Box(3, 10, 7, 4, 16, 9) : Box(7, 10, 3, 9, 16, 4), ns ? Box(12, 10, 7, 13, 16, 9) : Box(7, 10, 12, 9, 16, 13)]
                    d.boxes[1].tex = chain; d.boxes[2].tex = chain
                } else {
                    d.boxes = [board, ns ? Box(0, 14, 6, 16, 16, 10) : Box(6, 14, 0, 10, 16, 16)]
                }
                add(d)
            }
        }
        // Item frames: 4 wall facings + floor + ceiling.
        for (n, disp) in [("item_frame", "Item Frame"), ("glow_item_frame", "Glow Item Frame")] {
            for st in 0..<6 {
                var d = BlockDef(st == 0 ? n : "\(n)[\(st)]", disp)
                d.group = n; d.hidden = st != 0; d.shape = "frame"
                d.tex = [n]; d.render = .model; d.layer = .cutout; d.opaque = false; d.collide = false; d.hardness = 0; d.sound = .wood; d.skyStop = false
                d.emit = n == "glow_item_frame" ? 0 : 0
                d.boxes = [[Box(2, 2, 15, 14, 14, 16), Box(2, 2, 0, 14, 14, 1), Box(15, 2, 2, 16, 14, 14), Box(0, 2, 2, 1, 14, 14),
                            Box(2, 0, 2, 14, 1, 14), Box(2, 15, 2, 14, 16, 14)][st]]
                add(d)
            }
        }
        // Painting anchor: 4 facings; the picture itself is drawn from the block entity.
        for st in 0..<4 {
            var d = BlockDef(st == 0 ? "painting" : "painting[\(st)]", "Painting")
            d.group = "painting"; d.hidden = st != 0; d.shape = "painting"
            d.tex = ["painting_back"]; d.render = .model; d.opaque = false; d.collide = false; d.hardness = 0; d.sound = .wood; d.skyStop = false
            d.boxes = [[Box(0, 0, 15, 16, 16, 16), Box(0, 0, 0, 16, 16, 1), Box(15, 0, 0, 16, 16, 16), Box(0, 0, 0, 1, 16, 16)][st]]
            add(d)
        }
        for (m, _, _) in Paintings.motives { _ = Tex.id("painting_\(m)") }
    }
}

extension TextureGen {
    static func decorPainters(_ p: inout [String: Painter]) {
        p["item_frame"] = { x, y in (x < 2 || y < 2 || x > 13 || y > 13) ? hex(0x8A6A40, 0.9 + 0.1 * r(x, y, 990)) : hex(0x9A6A4A, 0.7) }
        p["glow_item_frame"] = { x, y in (x < 2 || y < 2 || x > 13 || y > 13) ? hex(0x6AD8C8, 0.9 + 0.1 * r(x, y, 991)) : hex(0x3A8A7A, 0.7) }
        p["painting_back"] = { x, y in hex(0x9A7A4A, 0.85 + 0.15 * r(x, y, 992)) }
        // Original abstract pictures: each motive gets its own palette and composition.
        for (i, (m, w, h)) in Paintings.motives.enumerated() {
            let palette: [UInt32] = [[0x3A6AA8, 0xE8C040, 0x2A2A2A, 0xD85A3A], [0x6AA84A, 0xF0E8C0, 0x3A2A1A, 0xA83A3A],
                                     [0x2A4A6A, 0x8AC8E8, 0xF0F0F0, 0x3A3A5A], [0xA86A3A, 0xE8A040, 0x5A3A2A, 0xF0D8A0]][i % 4]
            let aspect = Float(w) / Float(h)
            p["painting_\(m)"] = { x, y in
                if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x6A4A2A) }
                let fx = (Float(x) - 7.5) * aspect, fy = Float(y) - 7.5
                let a = atan2f(fy, fx) * Float(2 + i % 5), d = (fx * fx + fy * fy).squareRoot()
                let band = Int(d / Float(2 + i % 3) + sinf(a) * 1.5 + Float(i)) & 3
                let k = r(x, y, 993 + i) < 0.1 ? (band + 1) & 3 : band
                return hex(palette[k], 0.9 + 0.1 * r(x / 2, y / 2, 1000 + i))
            }
        }
    }
}

extension Game {
    // After placing a sign, open the editor.
    func openSignEditor(_ p: IVec3) {
        let be = world.blockEntities[p] ?? BlockEntity(.sign)
        world.blockEntities[p] = be
        openMenu(SignMenu(game: self, entity: be))
    }

    // Item frames: right-click puts the held item in (or rotates it); punching takes it out.
    func useItemFrame(_ p: IVec3) -> Bool {
        let be = world.blockEntities[p] ?? BlockEntity(.frame)
        world.blockEntities[p] = be
        if be.container[0].isEmpty {
            guard !held.isEmpty else { return true }
            be.container[0] = held.with(count: 1)
            consumeHeld()
        } else {
            be.delay = Float((Int(be.delay) + 1) % 8)          // rotation in 45° steps
            sfx(.itemFrameRotate, 0.6)
        }
        return true
    }

    // Paintings pick a random motive that fits the wall space (reference behaviour).
    func placePainting(at p: IVec3, facing f: Int) {
        let right = [IVec3(-1, 0, 0), IVec3(1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)][f]
        let back = [IVec3(0, 0, 1), IVec3(0, 0, -1), IVec3(1, 0, 0), IVec3(-1, 0, 0)][f]
        var fits: [Int] = []
        for (i, m) in Paintings.motives.enumerated() {
            var ok = true
            for dy in 0..<m.2 { for dx in 0..<m.1 {
                let q = p + IVec3(right.x * dx, dy, right.z * dx)
                let wall = q + back
                if !(world.block(q.x, q.y, q.z) == AIR || q == p) || !Blocks.opaque[Int(world.block(wall.x, wall.y, wall.z))] { ok = false }
            } }
            if ok { fits.append(i) }
        }
        guard let best = fits.map({ Paintings.motives[$0].1 * Paintings.motives[$0].2 }).max() else { return }
        let pick = fits.filter { Paintings.motives[$0].1 * Paintings.motives[$0].2 == best }.randomElement()!
        world.setBlock(p.x, p.y, p.z, Blocks.id("painting") + BlockID(f))
        let be = BlockEntity(.painting)
        be.mob = Paintings.motives[pick].0
        world.blockEntities[p] = be
    }

    // Text on signs, framed items and paintings (entity pass).
    func writeDecor(_ wr: inout EntityWriter, eye: V3) {
        let range: Float = 48
        for (p, be) in world.blockEntities where be.kind == .sign || be.kind == .frame || be.kind == .painting {
            let c = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)
            guard simd_length(c - eye) < range else { continue }
            let b = world.block(p.x, p.y, p.z)
            let st = Int(b - Blocks.groupBase[Int(b)])
            let l = world.lightAt(p.x, p.y, p.z)
            let light = max(0.2, max(Float(l.sky) / 15 * daylight, Float(l.block) / 15))
            switch be.kind {
            case .sign:
                let f = st % 4
                // Face normal (toward the reader) and the text's right vector.
                let n = [V3(0, 0, -1), V3(0, 0, 1), V3(-1, 0, 0), V3(1, 0, 0)][f]
                let hanging = Blocks.shape[Int(b)] == "hsign"
                // Hanging signs: text on both faces of the board (lower part of the block).
                let side: V3 = V3(-n.z, 0, n.x)
                let low: V3 = c + V3(0, -0.22, 0)
                let nOff: V3 = n * 0.07
                var faces: [(V3, V3, Float)] = []
                if hanging {
                    faces.append((low + nOff, side * -1, Float(1.0 / 115)))
                    faces.append((low - nOff, side, Float(1.0 / 115)))
                } else {
                    let ctr: V3 = st < 4 ? c + V3(0, 0.22, 0) + nOff : c - n * 0.37
                    faces.append((ctr, side * -1, Float(1.0 / 90)))
                }
                for (center, right, s) in faces {
                for (li, line) in be.lines.enumerated() where !line.isEmpty {
                    let wpx = Float(Font.width(line))
                    var x = -wpx / 2
                    let y = Float(1 - li) * 10 + 2
                    for u in line.unicodeScalars {
                        let code = Int(u.value)
                        let adv = Float(Font.advance(code))
                        if code > 32 && code < 127 {
                            let gw = Float(Font.glyphs[code - 32][0])
                            let o = center - eye + right * (x * s) + V3(0, (y - 7) * s, 0)
                            let a = o, bb = o + right * (gw * s), cc = bb + V3(0, 7 * s, 0), d = a + V3(0, 7 * s, 0)
                            wr.quad([a, bb, cc, d], [V2(0, 7 / 16), V2(gw / 16, 7 / 16), V2(gw / 16, 0), V2(0, 0)], Font.layerBase + code - 32,
                                    V4(0.05 * light, 0.05 * light, 0.05 * light, 1))
                        }
                        x += adv
                    }
                }
                }
            case .frame:
                let item = be.container[0]
                guard !item.isEmpty else { continue }
                let n = [V3(0, 0, -1), V3(0, 0, 1), V3(-1, 0, 0), V3(1, 0, 0), V3(0, 1, 0), V3(0, -1, 0)][min(st, 5)]
                let pos = c - n * (st < 4 ? 0.42 : 0.42) - eye
                var right = st < 4 ? V3(-n.z, 0, n.x) * -1 : V3(1, 0, 0)
                var up = st < 4 ? V3(0, 1, 0) : V3(0, 0, -1)
                let ang = be.delay * .pi / 4
                (right, up) = (right * cosf(ang) + up * sinf(ang), up * cosf(ang) - right * sinf(ang))
                let glow = Blocks.key(Blocks.groupBase[Int(b)]) == "glow_item_frame"
                if let layer = Items.texLayer(item.item) { wr.sprite(center: pos, half: 0.3, right: right, up: up, layer: layer, light: glow ? 1 : light) }
                else if let bl = item.def.block { wr.cube(center: pos, half: 0.18, yaw: 0, block: bl, light: glow ? 1 : light) }
            default:
                guard let m = Paintings.motives.first(where: { $0.0 == be.mob }) else { continue }
                let f = st % 4
                let n = [V3(0, 0, -1), V3(0, 0, 1), V3(-1, 0, 0), V3(1, 0, 0)][f]
                let right = [V3(-1, 0, 0), V3(1, 0, 0), V3(0, 0, 1), V3(0, 0, -1)][f]
                // Anchor is the bottom-left cell; the picture spans w x h cells.
                let base = V3(Float(p.x) + 0.5, Float(p.y), Float(p.z) + 0.5) - n * 0.44 - right * 0.5
                let a = base - eye, bR = right * Float(m.1), up = V3(0, Float(m.2), 0)
                wr.quad([a, a + bR, a + bR + up, a + up], [V2(0, 1), V2(1, 1), V2(1, 0), V2(0, 0)], Int(Tex.id("painting_\(m.0)")),
                        V4(light, light, light, 1))
            }
        }
    }
}

final class SignMenu: Menu {
    let be: BlockEntity
    var line = 0
    init(game: Game, entity: BlockEntity) {
        be = entity
        super.init("Edit Sign Message", game: game)
        height = 110
        showInventoryLabel = false
        let done = MenuSlot(64, 88, nil, 0, .button(0))
        done.w = 48; done.h = 14
        slots.append(done)
    }
    override var capturesText: Bool { true }
    override func buttonPressed(_ i: Int) { game.closeMenu() }
    override func typed(_ s: String) {
        while be.lines.count < 4 { be.lines.append("") }
        for c in s {
            if c == "\u{8}" { if !be.lines[line].isEmpty { be.lines[line].removeLast() } else if line > 0 { line -= 1 } }
            else if Font.width(be.lines[line] + String(c)) <= 90 { be.lines[line].append(c) }
        }
    }
    override func tick() {
        if game.input.tapped(Key.enter) || game.input.tapped(Key.arrowDown) { line = min(3, line + 1) }
        if game.input.tapped(Key.arrowUp) { line = max(0, line - 1) }
    }
}
