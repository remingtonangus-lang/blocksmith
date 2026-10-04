import Foundation

// Blocks that make a structure move (Ships.swift): the helm assembles a connected structure into a
// free-moving ship and is where it is steered from; propellers push, engines power propellers and
// wheels, lift balloons hold an airship up, airfoils give lift and stability in flight, wheels carry
// land vehicles. Helm, propeller and wheel have four facing states (north, south, west, east = front
// toward -Z, +Z, -X, +X) with their models turned to match, so the generic facing placement works.
extension BlockRegistry {
    func registerShipBlocks() {
        // Rotates boxes (1/16 units, modelled with the front toward -Z) to facing f.
        func turned(_ boxes: [Box], _ f: Int) -> [Box] {
            boxes.map { b in
                func p(_ x: Int, _ z: Int) -> (Int, Int) {
                    switch f {
                    case 1: return (16 - x, 16 - z)
                    case 2: return (z, 16 - x)
                    case 3: return (16 - z, x)
                    default: return (x, z)
                    }
                }
                let a = p(Int(b.x0), Int(b.z0)), c = p(Int(b.x1), Int(b.z1))
                return Box(min(a.0, c.0), Int(b.y0), min(a.1, c.1), max(a.0, c.0), Int(b.y1), max(a.1, c.1), tex: b.tex)
            }
        }
        func facing4(_ d: BlockDef, _ boxes: [Box]) {
            for (k, dir) in ["north", "south", "west", "east"].enumerated() {
                var s = d
                s.name = k == 0 ? d.name : "\(d.name)[\(dir)]"
                s.group = d.name
                s.hidden = k != 0
                s.boxes = turned(boxes, k)
                add(s)
            }
        }
        func t6(_ n: String) -> [UInt16] { Array(repeating: Tex.id(n), count: 6) }

        // Helm: a pedestal with a spoked wheel on its front (the side that faces the pilot).
        var helm = BlockDef("ship_helm", "Ship Helm")
        helm.tex = ["ship_wood"]; helm.render = .model; helm.layer = .cutout; helm.opaque = false; helm.hardness = 2
        helm.tool = .axe; helm.sound = .wood; helm.skyStop = false
        let wood = t6("ship_wood"), dark = t6("ship_wood_dark"), brass = t6("ship_brass")
        facing4(helm, [
            Box(6, 0, 7, 10, 9, 11, tex: dark), Box(5, 0, 6, 11, 2, 12, tex: dark),
            Box(7, 9, 7, 9, 11, 9, tex: dark),                                                   // axle
            Box(5, 14, 5, 11, 15, 7, tex: wood), Box(5, 5, 5, 11, 6, 7, tex: wood),              // rim
            Box(3, 7, 5, 4, 13, 7, tex: wood), Box(12, 7, 5, 13, 13, 7, tex: wood),
            Box(4, 6, 5, 5, 7, 7, tex: wood), Box(11, 6, 5, 12, 7, 7, tex: wood),
            Box(4, 13, 5, 5, 14, 7, tex: wood), Box(11, 13, 5, 12, 14, 7, tex: wood),
            Box(7, 6, 6, 9, 14, 7, tex: dark), Box(4, 9, 6, 12, 11, 7, tex: dark),               // spokes
            Box(7, 9, 5, 9, 11, 6, tex: brass),                                                   // hub
            Box(7, 15, 5, 9, 16, 7, tex: wood), Box(1, 9, 5, 3, 11, 7, tex: wood), Box(13, 9, 5, 15, 11, 7, tex: wood),
        ])

        // Propeller: hub and two crossed blades on the front; it pushes the ship away from its front.
        var prop = BlockDef("ship_propeller", "Propeller")
        prop.tex = ["ship_brass"]; prop.render = .model; prop.layer = .cutout; prop.opaque = false; prop.hardness = 2.5
        prop.tool = .pickaxe; prop.sound = .stone; prop.skyStop = false
        let metal = t6("ship_metal"), blade = t6("ship_blade")
        facing4(prop, [
            Box(6, 6, 6, 10, 10, 16, tex: metal),                                                 // shaft housing
            Box(5, 5, 3, 11, 11, 6, tex: brass),                                                  // hub
            Box(7, 0, 2, 9, 16, 3, tex: blade), Box(0, 7, 2, 16, 9, 3, tex: blade),
        ])

        var engine = BlockDef("ship_engine", "Engine")
        engine.tex = ["ship_engine_side", "ship_engine_side", "ship_engine_top", "ship_metal", "ship_engine_side", "ship_engine_side"]
        engine.hardness = 3.5; engine.tool = .pickaxe; engine.requiresTool = true; engine.sound = .stone
        addFacing(engine, front: "ship_engine_front")

        var balloon = BlockDef("ship_balloon", "Lift Balloon")
        balloon.tex = ["ship_balloon"]; balloon.hardness = 0.8; balloon.tool = .shears; balloon.sound = .plant; balloon.flammable = true
        add(balloon)

        var wing = BlockDef("ship_wing", "Airfoil")
        wing.tex = ["ship_wing"]; wing.render = .model; wing.opaque = false; wing.hardness = 1.5; wing.tool = .axe; wing.sound = .wood
        wing.boxes = [Box(0, 6, 0, 16, 10, 16)]; wing.skyStop = true
        add(wing)

        // Turret ring: a bearing; what stands on it becomes a turret when the ship is assembled.
        var ring = BlockDef("ship_turret_ring", "Turret Ring")
        ring.tex = ["ship_ring_side", "ship_ring_side", "ship_ring_top", "ship_metal", "ship_ring_side", "ship_ring_side"]
        ring.hardness = 4; ring.tool = .pickaxe; ring.requiresTool = true; ring.sound = .stone; ring.resistance = 8
        add(ring)

        // Cannon: a carriage with a barrel; it fires out of the side opposite its front (away from whoever placed it).
        var cannon = BlockDef("ship_cannon", "Cannon")
        cannon.tex = ["ship_metal"]; cannon.render = .model; cannon.layer = .cutout; cannon.opaque = false; cannon.hardness = 4
        cannon.tool = .pickaxe; cannon.requiresTool = true; cannon.sound = .stone; cannon.skyStop = false; cannon.resistance = 8
        let barrel = t6("ship_barrel")
        let carriageBoxes = [Box(3, 0, 2, 13, 5, 12, tex: dark), Box(2, 0, 3, 3, 4, 7, tex: wood), Box(13, 0, 3, 14, 4, 7, tex: wood)]
        let barrelBoxes = [Box(5, 5, 1, 11, 11, 8, tex: barrel), Box(6, 6, 8, 10, 10, 16, tex: barrel), Box(5, 5, 14, 11, 11, 16, tex: barrel)]
        facing4(cannon, carriageBoxes + barrelBoxes)
        // Render-only halves of a cannon on a ship: the carriage stays put, the barrel is drawn raised to the guns'
        // elevation (ShipRenderer). Hidden: no items, never placed in the world.
        for (n, boxes) in [("ship_cannon_mount", carriageBoxes), ("ship_cannon_barrel", barrelBoxes)] {
            var part = cannon
            part.name = n
            for (k, dir) in ["north", "south", "west", "east"].enumerated() {
                var st = part
                st.name = k == 0 ? n : "\(n)[\(dir)]"
                st.group = n
                st.hidden = true
                st.boxes = turned(boxes, k)
                add(st)
            }
        }

        // Wheel: a disc rolling along the facing axis (north/south roll along Z, west/east along X).
        var wheel = BlockDef("ship_wheel", "Wheel")
        wheel.tex = ["ship_tyre"]; wheel.render = .model; wheel.opaque = false; wheel.hardness = 1.5; wheel.tool = .axe; wheel.sound = .wood
        wheel.skyStop = true
        let tyre = t6("ship_tyre")
        facing4(wheel, [
            Box(3, 4, 0, 13, 12, 16, tex: tyre), Box(3, 0, 4, 13, 16, 12, tex: tyre), Box(3, 2, 2, 13, 14, 14, tex: tyre),
            Box(2, 6, 6, 14, 10, 10, tex: metal),
        ])

        // Rotor head (helicopters, FlightModel.swift): mast, swashplate and hub with blade roots; on a flying ship
        // it turns and the blades are drawn to the rotor's full diameter from the render-only blade below.
        var rotor = BlockDef("ship_rotor", "Rotor Head")
        rotor.tex = ["ship_metal"]; rotor.render = .model; rotor.layer = .cutout; rotor.opaque = false; rotor.hardness = 3
        rotor.tool = .pickaxe; rotor.requiresTool = true; rotor.sound = .stone; rotor.skyStop = false
        let bladeT = t6("ship_blade"), frame = t6("capital_airframe")
        rotor.boxes = [Box(6, 0, 6, 10, 9, 10, tex: metal), Box(4, 8, 4, 12, 10, 12, tex: brass), Box(5, 10, 5, 11, 13, 11, tex: frame),
                       Box(0, 11, 7, 16, 12, 9, tex: bladeT), Box(7, 11, 0, 9, 12, 16, tex: bladeT)]
        add(rotor)
        var blade = BlockDef("ship_rotor_blade", "Rotor Blade")
        blade.tex = ["capital_airframe"]; blade.render = .model; blade.layer = .cutout; blade.opaque = false; blade.hidden = true
        blade.boxes = [Box(0, 7, 6, 16, 8, 10, tex: frame), Box(0, 7, 6, 1, 8, 10, tex: t6("ship_metal"))]
        add(blade)
        // Capital airframe: light white alloy panels for the Capital's aircraft (0.3 t a block: ShipParts.mass).
        var airframe = BlockDef("capital_airframe", "Capital Airframe")
        airframe.tex = ["capital_airframe"]; airframe.hardness = 2; airframe.tool = .pickaxe; airframe.sound = .stone
        add(airframe)
    }
}

extension TextureGen {
    static func shipPainters(_ p: inout [String: Painter]) {
        // White alloy panels with grey seams and a rivet line.
        p["capital_airframe"] = { x, y in
            if x == 0 || y == 0 { return hex(0xBFC5CB) }
            if y == 8 && x % 3 == 1 { return hex(0xD3D8DC) }
            return hex(0xEFF1F3, 0.975 + 0.02 * r(x / 4, y / 4, 2711))
        }
        p["ship_wood"] = { x, y in
            let plank = y / 4
            let edge = y % 4 == 3 || (x + plank * 5) % 16 == 0
            return hex(0x9C6B3C, edge ? 0.7 : 0.9 + 0.15 * r(x / 3, y, 2601 + plank))
        }
        p["ship_wood_dark"] = { x, y in hex(0x5A3A1E, 0.85 + 0.2 * r(x, y / 2, 2602)) }
        p["ship_brass"] = { x, y in
            let shine = (x + y) % 7 == 0 ? 1.2 : 1.0
            return hex(0xC9A23A, Float(shine) * (0.85 + 0.15 * r(x, y, 2603)))
        }
        p["ship_metal"] = { x, y in
            let rivet = (x % 8 == 2 && y % 8 == 2)
            if rivet { return hex(0xB8BEC4) }
            if x % 8 == 0 || y % 8 == 0 { return hex(0x4C5258) }
            return hex(0x6E767E, 0.9 + 0.12 * r(x, y, 2604))
        }
        p["ship_blade"] = { x, y in hex(0xD9DDE0, 0.85 + 0.12 * r(x, y, 2605)) }
        p["ship_engine_side"] = { x, y in
            if y < 2 || y > 13 { return hex(0x3E4348) }
            if x % 4 == 0 { return hex(0x4C5258) }
            return hex(0x737B83, 0.9 + 0.12 * r(x, y, 2606))
        }
        p["ship_engine_top"] = { x, y in
            let dx = x - 8, dy = y - 8
            let d2 = dx * dx + dy * dy
            if d2 < 10 { return hex(0x2A2A2A) }                       // exhaust
            if d2 < 20 { return hex(0xC9A23A) }
            return hex(0x6E767E, 0.9 + 0.1 * r(x, y, 2607))
        }
        p["ship_engine_front"] = { x, y in
            if x < 2 || x > 13 || y < 2 || y > 13 { return hex(0x3E4348) }
            if y % 3 == 0 { return hex(0x1E2124) }                   // grille
            let glow = r(x, y / 3, 2608)
            return hex(0xE0752A, 0.7 + 0.4 * glow)
        }
        p["ship_balloon"] = { x, y in
            let seam = x % 8 == 0 || y % 8 == 0
            return hex(0xEDE3C8, seam ? 0.78 : 0.92 + 0.08 * r(x, y, 2609))
        }
        p["ship_wing"] = { x, y in
            if y % 8 == 0 { return hex(0x6E5434) }                   // ribs
            return hex(0xD8CDB0, 0.9 + 0.1 * r(x, y, 2610))
        }
        p["ship_ring_top"] = { x, y in
            let dx = Float(x) - 7.5, dy = Float(y) - 7.5
            let d = (dx * dx + dy * dy).squareRoot()
            if d > 5.5 && d < 7.5 { return hex(0xC9A23A, 0.8 + 0.2 * r(x, y, 2612)) }        // bearing race
            if d < 2 { return hex(0x2E3236) }
            return hex(0x6E767E, 0.9 + 0.1 * r(x, y, 2613))
        }
        p["ship_ring_side"] = { x, y in
            if y < 3 || y > 12 { return hex(0x4C5258) }
            if (x + y) % 4 == 0 { return hex(0xC9A23A, 0.85) }
            return hex(0x6E767E, 0.88 + 0.12 * r(x, y, 2614))
        }
        p["ship_barrel"] = { x, y in
            let band = y % 8 < 2
            return hex(band ? 0x3A3E42 : 0x55595E, 0.9 + 0.1 * r(x, y, 2615))
        }
        p["ship_tyre"] = { x, y in
            let tread = (x + y) % 4 == 0
            return hex(0x2B2B2D, tread ? 0.7 : 0.95 + 0.1 * r(x, y, 2611))
        }
    }
}

extension Recipes {
    static func shipRecipes() -> [Recipe?] {
        var r: [Recipe?] = []
        r.append(shaped(["SSS", "SPS", " P "], ["S": "stick", "P": "#planks"], "ship_helm"))
        r.append(shaped(["P P", " I ", "P P"], ["P": "#planks", "I": "iron_ingot"], "ship_propeller"))
        r.append(shaped(["III", "IFI", "CCC"], ["I": "iron_ingot", "F": "furnace", "C": "cobblestone"], "ship_engine"))
        r.append(shaped(["WWW", "WSW", "WWW"], ["W": "white_wool", "S": "string"], "ship_balloon", 4))
        r.append(shaped(["SSS", "PPP"], ["S": "stick", "P": "#planks"], "ship_wing", 4))
        r.append(shaped([" P ", "PIP", " P "], ["P": "#planks", "I": "iron_ingot"], "ship_wheel", 2))
        r.append(shaped(["III", "I I", "III"], ["I": "iron_ingot"], "ship_turret_ring"))
        r.append(shaped(["II ", "IGI", "PPP"], ["I": "iron_ingot", "G": "gunpowder", "P": "#planks"], "ship_cannon"))
        return r
    }
}
