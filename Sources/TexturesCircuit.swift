import Foundation

// Painters for sparkstone components (original art).
extension TextureGen {
    static func redstonePainters(_ p: inout [String: Painter]) {
        for pw in 0..<16 {
            // Copper wire brightens from bright copper (0xB8683A) to glowing copper-orange (0xFFA860) at 15.
            let k = Float(pw) / 15
            p["redstone_dust_\(pw)"] = { x, y in
                // (P408: solid twisted copper, bright even unpowered: dust holes read as soil on the grass)
                let n: Float = ((x + y) % 4 == 3 ? 0.55 : (x + y) % 4 == 1 ? 1.15 : 0.9) + 0.1 * r(x, y, 701)
                let cr: Float = (0xB8 + (0xFF - 0xB8) * k) / 255, cg: Float = (0x68 + (0xA8 - 0x68) * k) / 255
                let cb: Float = (0x3A + (0x60 - 0x3A) * k) / 255
                return V4(min(1, cr * n), min(1, cg * n), min(1, cb * n), 1)
            }
        }
        func torch(_ lit: Bool) -> Painter {
            { x, y in
                guard x == 7 || x == 8 else { return clear }
                if y >= 4 && y <= 7 {   // copper coil head
                    let band = y % 2 == 0
                    return lit ? hex(band ? 0xFFC080 : 0xF08A40) : hex(band ? 0x7A4A2C : 0x5E3420)
                }
                if y >= 8 { return hex(0x6B4F2C, 0.85 + 0.2 * r(x, y, 702)) }
                return clear
            }
        }
        p["redstone_torch"] = torch(true)
        p["redstone_torch_off"] = torch(false)
        p["redstone_block"] = { x, y in
            // Copper battery: copper casing, dark cell window, bright coil terminal.
            if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x6A3A22) }
            if x >= 6 && x <= 9 && y <= 2 { return hex(0xFFC080) }
            if x >= 3 && x <= 12 && y >= 4 && y <= 12 {
                if x == 3 || x == 12 || y == 4 || y == 12 { return hex(0x3A2014) }
                return y % 2 == 0 ? hex(0xFFA860) : hex(0xC8683A)
            }
            return hex(0xB8693E, 0.9 + 0.2 * r(x, y, 704))
        }
        func lamp(_ on: Bool) -> Painter {
            { x, y in
                let frame = x % 5 == 0 || y % 5 == 0
                if frame { return hex(on ? 0x8A5A2A : 0x4A2A1A) }
                return on ? hex(0xFFE8C8, 0.9 + 0.15 * r(x, y, 705)) : hex(0x6A3A22, 0.85 + 0.2 * r(x, y, 706))
            }
        }
        p["redstone_lamp"] = lamp(false)
        p["redstone_lamp_on"] = lamp(true)
        p["lever"] = { x, y in hex(0x7A5A30, 0.85 + 0.2 * r(x, y, 707)) }
        func diode(_ on: Bool, comparator: Bool) -> Painter {
            { x, y in
                // Smooth stone slab with a copper trace down the middle.
                let trace = (x == 7 || x == 8) || (comparator && (y == 4 || y == 11) && x > 2 && x < 13)
                if trace { return on ? hex(0xFFA860) : hex(0x5E3420) }
                if x == 0 || y == 0 || x == 15 || y == 15 { return hex(0x8A8A8A) }
                return hex(0xA8A8A8, 0.94 + 0.08 * r(x, y, 708))
            }
        }
        p["repeater"] = diode(false, comparator: false)
        p["repeater_on"] = diode(true, comparator: false)
        p["comparator"] = diode(false, comparator: true)
        p["comparator_on"] = diode(true, comparator: true)
        let cob = p["cobblestone"]
        // The observer's face (P110: "needs a new look"): a round glass lens in a copper ring, bolts in the corners.
        p["observer_front"] = { x, y in
            let dx = Float(x) - 7.5, dy = Float(y) - 7.5
            let d = (dx * dx + dy * dy).squareRoot()
            if d < 3.2 { return (x == 6 && y == 6) || (x == 6 && y == 5) ? hex(0xBFE6F0) : hex(d < 1.6 ? 0x0E1A22 : 0x1E3A4A) }
            if d < 4.6 { return hex(0xB87333, 0.85 + 0.25 * r(x, y, 713)) }
            if d < 5.4 { return hex(0x262628) }
            if (x == 2 || x == 13) && (y == 2 || y == 13) { return hex(0xC8884A) }
            return hex(0x4A4A4C, 0.85 + 0.2 * r(x, y, 709))
        }
        p["observer_back"] = { x, y in
            if abs(x - 7) <= 1 && abs(y - 7) <= 1 { return hex(0x3A1A18) }
            return hex(0x5A5A5A, 0.85 + 0.2 * r(x, y, 710))
        }
        p["observer_back_on"] = { x, y in
            if abs(x - 7) <= 1 && abs(y - 7) <= 1 { return hex(0xF82A1A) }
            return hex(0x5A5A5A, 0.85 + 0.2 * r(x, y, 710))
        }
        p["observer_side"] = { x, y in
            if y == 7 || y == 8 { return x % 4 == 1 ? hex(0x6A3A1A) : hex(y == 7 ? 0xC8884A : 0x9A5A2A) }
            return hex(0x4A4A4C, 0.85 + 0.2 * r(x, y, 711))
        }
        p["observer_top"] = { x, y in (x == 7 || x == 8) && y > 3 ? hex(0x9A2A1A) : hex(0x5A5A5A, 0.85 + 0.2 * r(x, y, 712)) }
        // P463: the signal's way, lens to output, on the faces between them (TexturesHD has the full look).
        for (way, name) in ["up", "down", "left", "right"].enumerated() {
            p["observer_arrow_" + name] = { x, y in
                let ax = way == 0 ? x : way == 1 ? 15 - x : way == 2 ? y : 15 - y
                let ay = way == 0 ? y : way == 1 ? 15 - y : way == 2 ? x : 15 - x
                let off = abs(Float(ax) - 7.5)
                if (ax == 7 || ax == 8) && ay > 5 && ay < 13 || ay >= 2 && ay <= 5 && off < Float(ay - 1) * 1.25 { return hex(0xC0301C) }
                return hex(0xA2B2BC, 0.9 + 0.12 * r(x, y, 712))
            }
        }
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
        // P442: the machines' casing (dark stone in a riveted copper frame; a hatch on top) and the piston's steel rod.
        func casing(_ hatch: Bool) -> Painter {
            { x, y in
                let e = min(min(x, y), min(15 - x, 15 - y))
                if e == 0 { return hex(0xB87333, y == 0 ? 1.15 : (y == 15 ? 0.75 : 0.95)) }
                if (x == 2 || x == 13) && (y == 2 || y == 13) { return hex(0xC8884A) }
                let m: Float = max(abs(Float(x) - 7.5), abs(Float(y) - 7.5))
                if hatch && m > 3 && m < 4 { return hex(0x2A2A2C) }
                if hatch && (y == 7 || y == 8) && x >= 6 && x <= 9 { return hex(0xB87333, y == 7 ? 1.15 : 0.85) }
                return hex(0x5C5C60, 0.85 + 0.2 * r(x, y, 719))
            }
        }
        p["machine_casing"] = casing(false)
        p["machine_casing_top"] = casing(true)
        p["piston_rod"] = { x, y in hex(0xA8AAAE, 0.85 + 0.15 * Float(x % 4) / 3) }
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
        // Rails (drawn running north-south; the mesher rotates them).
        func rail(_ tie: UInt32, _ railC: UInt32, _ mid: UInt32?) -> Painter {
            { x, y in
                if x == 3 || x == 12 { return hex(railC, 0.9 + 0.1 * r(x, y, 724)) }
                if let m = mid, (x == 7 || x == 8) { return hex(m) }
                if y % 4 == 1 && x > 1 && x < 14 { return hex(tie, 0.9 + 0.15 * r(x, y, 725)) }
                return clear
            }
        }
        p["powered_rail"] = rail(0x6A4A2A, 0xE8C040, 0x5A1410)
        p["powered_rail_on"] = rail(0x6A4A2A, 0xE8C040, 0xF8301A)
        p["detector_rail"] = rail(0x6A4A2A, 0xA8A8A8, 0x5A1410)
        p["detector_rail_on"] = rail(0x6A4A2A, 0xA8A8A8, 0xF8301A)
        p["activator_rail"] = rail(0x7A2A1A, 0xA8A8A8, 0x5A1410)
        p["activator_rail_on"] = rail(0x7A2A1A, 0xA8A8A8, 0xF8301A)
        p["rail_corner"] = { x, y in
            // Quarter circles joining the south and east edges.
            let dx = Float(16 - x) - 0.5, dy = Float(16 - y) - 0.5
            let d = (dx * dx + dy * dy).squareRoot()
            if abs(d - 4) < 0.8 || abs(d - 13) < 0.8 { return hex(0xA8A8A8, 0.9 + 0.1 * r(x, y, 726)) }
            let ang = atan2f(dy, dx)
            if d > 2 && d < 15 && Int(ang * 8) % 2 == 0 && Int(d) % 5 == 1 { return hex(0x6A4A2A) }
            return clear
        }
    }
}
