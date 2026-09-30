import Foundation

// Painters for doors, trapdoors, ladders, paths, workstations and friends (original art).
extension TextureGen {
    static func buildingPainters(_ p: inout [String: Painter]) {
        let woods: [(String, UInt32)] = [("oak", 0xA2824E), ("spruce", 0x735531), ("birch", 0xC5B57A), ("jungle", 0xA07351),
                                         ("acacia", 0xAD5D32), ("dark_oak", 0x4F3218), ("mangrove", 0x773631), ("cherry", 0xE2B2AC),
                                         ("crimson", 0x6A344B), ("warped", 0x2B6963), ("iron", 0xD4D4D4)]
        for (i, w) in woods.enumerated() {
            let s = 520 + i * 6
            let c = w.1
            let iron = w.0 == "iron"
            // Door: frame, two panels on the bottom half, a window on the top half.
            p["\(w.0)_door_bottom"] = { x, y in
                if x < 2 || x > 13 || y > 13 { return hex(c, 0.75) }
                if (x == 7 || x == 8) || y == 6 || y == 7 { return hex(c, 0.7) }
                return hex(c, (iron ? 0.95 : 0.9) + 0.15 * r(x, y, s))
            }
            p["\(w.0)_door_top"] = { x, y in
                if x < 2 || x > 13 || y < 2 { return hex(c, 0.75) }
                if y < 9 && (x == 7 || x == 8) { return hex(c, 0.7) }
                if y < 9 { return iron ? hex(0x9A9A9A) : clear }
                if y == 9 { return hex(c, 0.7) }
                return hex(c, 0.9 + 0.15 * r(x, y, s + 1))
            }
            p["\(w.0)_trapdoor"] = { x, y in
                if x < 2 || x > 13 || y < 2 || y > 13 { return hex(c, 0.78) }
                if (x - 2) % 4 == 3 || (y - 2) % 4 == 3 { return hex(c, 0.72) }
                return iron ? hex(c, 0.9) : ((x + y) % 7 == 0 ? clear : hex(c, 0.9 + 0.15 * r(x, y, s + 2)))
            }
        }
        p["dirt_path_top"] = { x, y in hex(0x9A7F4A, 0.88 + 0.2 * r(x, y, 600)) }
        p["dirt_path_side"] = { x, y in y < 2 ? hex(0x9A7F4A, 0.9 + 0.15 * r(x, y, 601)) : hex(0x866043, 0.88 + 0.2 * r(x, y, 602)) }
        p["ladder"] = { x, y in
            if x == 2 || x == 3 || x == 12 || x == 13 { return hex(0x7A5A30, 0.9 + 0.15 * r(x, y, 603)) }
            if y % 4 == 1 && x > 3 && x < 12 { return hex(0x8A6A3A, 0.9 + 0.15 * r(x, y, 604)) }
            return clear
        }
        p["lantern"] = { x, y in
            if y < 3 || y > 13 || x < 3 || x > 12 { return hex(0x3A3A40) }
            return hex(0xF8C85A, 0.85 + 0.25 * r(x, y, 605))
        }
        p["bell"] = { x, y in hex(0xE8C040, 0.85 + 0.2 * r(x, y, 606) + (x < 4 ? -0.15 : 0)) }
        p["hay_block_side"] = { x, y in hex(y % 5 == 2 ? 0x7A4A1A : 0xC8A838, 0.85 + 0.25 * r(x, y / 2, 607)) }
        p["hay_block_top"] = { x, y in hex(0xB89A30, 0.8 + 0.3 * r(x, y, 608)) }
        p["composter_side"] = planks(0x8A6A3A, salt: 609)
        p["composter_compost"] = { x, y in hex(0x5A4A22, 0.75 + 0.35 * r(x, y, 611)) }
        p["composter_ready"] = { x, y in r(x, y, 612) < 0.25 ? hex(0xE8E4D0, 0.9 + 0.1 * r(x, y, 613)) : hex(0x5A4A22, 0.75 + 0.35 * r(x, y, 611)) }
        p["composter_top"] = { x, y in x < 2 || x > 13 || y < 2 || y > 13 ? hex(0x8A6A3A) : hex(0x4A3A1A, 0.8 + 0.3 * r(x, y, 610)) }
        p["barrel_side"] = { x, y in y == 2 || y == 13 ? hex(0x3A3A3A) : hex(0x7A5A30, (x % 4 == 0 ? 0.8 : 0.95) + 0.1 * r(x, y, 611)) }
        p["barrel_top"] = { x, y in abs(x - 7) < 3 && abs(y - 7) < 3 ? hex(0x4A3A20) : hex(0x8A6A3A, 0.9 + 0.15 * r(x, y, 612)) }
        p["barrel_bottom"] = planks(0x7A5A30, salt: 613)
        p["smoker_front"] = { x, y in
            if y < 4 { return hex(0x4A4A4A, 0.9 + 0.2 * r(x, y, 614)) }
            if x > 3 && x < 12 && y > 6 && y < 13 { return hex(0x1A1A1A) }
            return hex(0x6A5A4A, 0.85 + 0.25 * r(x, y, 615))
        }
        p["smoker_top"] = rock(0x5A5A5A, grain: 0.2, blotch: 0.1, salt: 616)
        p["blast_furnace_front"] = { x, y in
            if x > 3 && x < 12 && y > 6 && y < 13 { return hex(0x1A1A1A) }
            return hex(x % 5 == 0 ? 0x3A3A3E : 0x6A6A70, 0.9 + 0.2 * r(x, y, 617))
        }
        p["blast_furnace_top"] = rock(0x6A6A70, grain: 0.2, blotch: 0.1, salt: 618)
        p["cartography_table_side"] = { x, y in y < 3 ? hex(0x4F3218) : hex(0xC8B890, 0.9 + 0.15 * r(x, y, 619)) }
        p["cartography_table_top"] = { x, y in x < 1 || y < 1 ? hex(0x4F3218) : hex((x + y) % 5 == 0 ? 0x3A6AA8 : 0xE0D8B8, 0.9 + 0.1 * r(x, y, 620)) }
        p["fletching_table_side"] = { x, y in y < 3 ? hex(0xC5B57A) : hex((x + y) % 6 == 0 ? 0xE8E8E8 : 0xB0A070, 0.9 + 0.15 * r(x, y, 621)) }
        p["fletching_table_top"] = { x, y in hex(0xC8B88A, 0.9 + 0.15 * r(x, y, 622)) }
        p["smithing_table_side"] = { x, y in y < 4 ? hex(0x2A2A30) : hex(0x6A4A30, 0.9 + 0.15 * r(x, y, 623)) }
        p["smithing_table_top"] = { x, y in x < 2 || x > 13 || y < 2 || y > 13 ? hex(0x2A2A30) : hex(0x3A3A44, 0.9 + 0.15 * r(x, y, 624)) }
        p["loom_side"] = { x, y in y > 11 ? hex(0x9A7A4A) : ((x % 3 == 0) ? hex(0xE8E8E8) : hex(0xB08A5A, 0.9 + 0.15 * r(x, y, 625))) }
        p["loom_top"] = { x, y in hex(0xB08A5A, 0.9 + 0.15 * r(x, y, 626)) }
        p["stonecutter_side"] = { x, y in hex(0x7A7A7A, 0.9 + 0.15 * r(x, y, 627)) }
        p["stonecutter_top"] = { x, y in y == 7 || y == 8 ? hex(0xC8C8C8) : hex(0x8A8A8A, 0.9 + 0.15 * r(x, y, 628)) }
        p["grindstone"] = { x, y in hex(0x8E8E8E, 0.85 + 0.25 * r(x / 2, y / 2, 629)) }
        p["lectern_side"] = planks(0x9A7A4A, salt: 630)
        p["lectern_top"] = { x, y in x > 2 && x < 13 && y > 3 && y < 12 ? hex(0xE8E0C8) : hex(0x9A7A4A, 0.9 + 0.15 * r(x, y, 631)) }
        p["anvil"] = { x, y in hex(0x444448, 0.85 + 0.25 * r(x, y, 632)) }
        p["cauldron"] = { x, y in hex(0x3A3A3E, 0.85 + 0.25 * r(x, y, 633)) }
        p["flower_pot"] = { x, y in hex(0x7A3A22, 0.85 + 0.25 * r(x, y, 634)) }
        p["cut_sandstone"] = { x, y in y == 0 || y == 15 || y == 7 ? hex(0xC8BC88) : hex(0xDDD4A0, 0.94 + 0.1 * r(x, y, 635)) }
        p["chiseled_sandstone"] = { x, y in
            let dx = abs(Float(x) - 7.5), dy = abs(Float(y) - 7.5)
            if y < 2 || y > 13 { return hex(0xC8BC88) }
            if max(dx, dy) > 3.5 && max(dx, dy) < 4.5 { return hex(0xB8AC78) }
            return hex(0xDDD4A0, 0.94 + 0.1 * r(x, y, 636))
        }
        p["cut_red_sandstone"] = { x, y in y == 0 || y == 15 || y == 7 ? hex(0x9A4A18) : hex(0xBA6522, 0.94 + 0.1 * r(x, y, 637)) }
        p["blue_terracotta"] = rock(0x4A3B5B, grain: 0.1, blotch: 0.08, salt: 639)
        p["rail"] = { x, y in
            if x == 3 || x == 12 { return hex(0xA8A8A8, 0.9 + 0.1 * r(x, y, 640)) }
            if y % 4 == 1 && x > 1 && x < 14 { return hex(0x6A4A2A, 0.9 + 0.15 * r(x, y, 641)) }
            return clear
        }
        p["white_concrete"] = { x, y in hex(0xCFD5D6, 0.97 + 0.04 * r(x, y, 638)) }
    }
}
