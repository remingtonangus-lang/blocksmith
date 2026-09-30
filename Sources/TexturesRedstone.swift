import Foundation

// Painters for redstone components (original art).
extension TextureGen {
    static func redstonePainters(_ p: inout [String: Painter]) {
        for pw in 0..<16 {
            // Dust brightens from dark red (0) to vivid red (15).
            let k = Float(pw) / 15
            p["redstone_dust_\(pw)"] = { x, y in
                if r(x, y, 700) < 0.12 { return clear }
                let v = 0.3 + 0.7 * k
                return V4(v * (0.85 + 0.2 * r(x, y, 701)), v * 0.08 + 0.02, 0.02, 1)
            }
        }
        func torch(_ lit: Bool) -> Painter {
            { x, y in
                guard x == 7 || x == 8 else { return clear }
                if y == 6 || y == 7 { return lit ? hex(y == 6 ? 0xFF6A5A : 0xE8201A) : hex(0x5A1A14) }
                if y >= 8 { return hex(0x6B4F2C, 0.85 + 0.2 * r(x, y, 702)) }
                return clear
            }
        }
        p["redstone_torch"] = torch(true)
        p["redstone_torch_off"] = torch(false)
        p["redstone_block"] = { x, y in
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x7A0A06) }
            return hex(r(x / 2, y / 2, 703) < 0.3 ? 0xC81A10 : 0xA8120A, 0.9 + 0.2 * r(x, y, 704))
        }
        func lamp(_ on: Bool) -> Painter {
            { x, y in
                let frame = x % 5 == 0 || y % 5 == 0
                if frame { return hex(on ? 0x8A5A2A : 0x4A2A1A) }
                return on ? hex(0xF8D080, 0.9 + 0.15 * r(x, y, 705)) : hex(0x6A3A22, 0.85 + 0.2 * r(x, y, 706))
            }
        }
        p["redstone_lamp"] = lamp(false)
        p["redstone_lamp_on"] = lamp(true)
        p["lever"] = { x, y in hex(0x7A5A30, 0.85 + 0.2 * r(x, y, 707)) }
        func diode(_ on: Bool, comparator: Bool) -> Painter {
            { x, y in
                // Smooth stone slab with a red trace down the middle.
                let trace = (x == 7 || x == 8) || (comparator && (y == 4 || y == 11) && x > 2 && x < 13)
                if trace { return on ? hex(0xE81A10) : hex(0x5A1410) }
                if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x8A8A8A) }
                return hex(0xA8A8A8, 0.94 + 0.08 * r(x, y, 708))
            }
        }
        p["repeater"] = diode(false, comparator: false)
        p["repeater_on"] = diode(true, comparator: false)
        p["comparator"] = diode(false, comparator: true)
        p["comparator_on"] = diode(true, comparator: true)
        let cob = p["cobblestone"]
        p["observer_front"] = { x, y in
            if (y == 5 || y == 10) && x > 1 && x < 14 { return hex(0x2A2A2A) }
            if (x == 3 || x == 12) && y > 4 && y < 11 { return hex(0x2A2A2A) }
            return hex(0x5A5A5A, 0.85 + 0.2 * r(x, y, 709))
        }
        p["observer_back"] = { x, y in
            if abs(x - 7) <= 1 && abs(y - 7) <= 1 { return hex(0x3A1A18) }
            return hex(0x5A5A5A, 0.85 + 0.2 * r(x, y, 710))
        }
        p["observer_back_on"] = { x, y in
            if abs(x - 7) <= 1 && abs(y - 7) <= 1 { return hex(0xF82A1A) }
            return hex(0x5A5A5A, 0.85 + 0.2 * r(x, y, 710))
        }
        p["observer_side"] = { x, y in (y == 7 || y == 8) ? hex(0x7A7A7A) : hex(0x5A5A5A, 0.85 + 0.2 * r(x, y, 711)) }
        p["observer_top"] = { x, y in (x == 7 || x == 8) && y > 3 ? hex(0x9A2A1A) : hex(0x5A5A5A, 0.85 + 0.2 * r(x, y, 712)) }
        let planksC: UInt32 = 0xA2824E
        p["piston_top"] = { x, y in
            if x < 2 || x > 13 || y < 2 || y > 13 { return hex(0x8A8A8A, 0.9 + 0.1 * r(x, y, 713)) }
            return hex(planksC, 0.9 + 0.15 * r(x, y, 714))
        }
        p["piston_top_sticky"] = { x, y in
            if x < 2 || x > 13 || y < 2 || y > 13 { return hex(0x8A8A8A, 0.9 + 0.1 * r(x, y, 713)) }
            if x > 3 && x < 12 && y > 3 && y < 12 { return hex(0x6AB85A, 0.85 + 0.25 * r(x, y, 715)) }
            return hex(planksC, 0.9 + 0.15 * r(x, y, 714))
        }
        p["piston_side"] = { x, y in
            if y < 4 { return hex(planksC, 0.9 + 0.15 * r(x, y, 716)) }
            if (x == 7 || x == 8) && y < 12 { return hex(0xB8B8B8) }
            return cob?(x, y) ?? hex(0x7A7A7A)
        }
        p["piston_bottom"] = { x, y in cob?(x, y) ?? hex(0x7A7A7A) }
        p["piston_inner"] = { x, y in
            if abs(x - 7) <= 2 && abs(y - 7) <= 2 { return hex(0xB8B8B8) }
            return cob?(x, y) ?? hex(0x7A7A7A)
        }
        p["slime_block"] = { x, y in
            let edge = x == 0 || y == 0 || x == 15 || y == 15
            let core = x > 3 && x < 12 && y > 3 && y < 12
            return V4(0.45, 0.8, 0.4, edge ? 0.95 : (core ? 0.85 : 0.6))
        }
        p["honey_block"] = { x, y in
            let edge = x == 0 || y == 0 || x == 15 || y == 15
            return V4(0.95, 0.65, 0.15, edge ? 0.95 : 0.7)
        }
        func dispenserFront(_ vertical: Bool, dropper: Bool) -> Painter {
            { x, y in
                let dx = abs(Float(x) - 7.5), dy = abs(Float(y) - 7.5)
                if dropper ? (dx < 2.5 && dy < 2.5) : (dx * dx + dy * dy < 12) { return hex(0x1A1A1A) }
                if !vertical && dy < 1 && dx < 5 && !dropper { return hex(0x2A2A2A) }
                return cob?(x, y) ?? hex(0x7A7A7A)
            }
        }
        p["dispenser_front"] = dispenserFront(false, dropper: false)
        p["dispenser_front_vertical"] = dispenserFront(true, dropper: false)
        p["dropper_front"] = dispenserFront(false, dropper: true)
        p["dropper_front_vertical"] = dispenserFront(true, dropper: true)
        p["hopper_outside"] = { x, y in hex(0x3A3A3E, 0.85 + 0.25 * r(x, y, 717)) }
        p["hopper_top"] = { x, y in x < 2 || x > 13 || y < 2 || y > 13 ? hex(0x4A4A4E) : hex(0x1E1E22, 0.9 + 0.1 * r(x, y, 718)) }
        p["note_block"] = { x, y in
            let bar = x > 4 && x < 11 && (y == 4 || y == 5)
            let stems = (x == 10 || x == 5) && y > 4 && y < 12
            if bar || stems { return hex(0x2A1A10) }
            return hex(0x6A4A2E, 0.88 + 0.2 * r(x, y, 719))
        }
        p["daylight_detector_side"] = planks(0x9A7A4A, salt: 720)
        p["daylight_detector_top"] = { x, y in
            let frame = x == 0 || y == 0 || x == 15 || y == 15
            if frame || x == 7 || y == 7 { return hex(0x9A7A4A) }
            return hex(0xC8C8D8, 0.85 + 0.2 * r(x, y, 721))
        }
        p["daylight_detector_inverted_top"] = { x, y in
            let frame = x == 0 || y == 0 || x == 15 || y == 15
            if frame || x == 7 || y == 7 { return hex(0x9A7A4A) }
            return hex(0x3A4A6A, 0.85 + 0.2 * r(x, y, 722))
        }
        p["target_top"] = { x, y in
            let dx = Float(x) - 7.5, dy = Float(y) - 7.5
            let d = Int((dx * dx + dy * dy).squareRoot())
            let c: UInt32 = d % 4 < 2 ? 0xE8E0D0 : 0xC82A1E
            return hex(c, 0.92 + 0.1 * r(x, y, 723))
        }
        p["target_side"] = p["target_top"]
    }
}
