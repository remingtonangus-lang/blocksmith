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

        // Ballast tank (C8): floods to dive and blows to surface; a hull with tanks under water is a submarine.
        // Rotten planks (P93, Wrecks.swift): what a raisable wreck's hull is made of where it gave way.
        var rot = BlockDef(Wrecks.rotten, "Rotten Planks")
        rot.tex = [Wrecks.rotten]; rot.hardness = 0.5; rot.tool = .axe; rot.sound = .wood; rot.flammable = true
        add(rot)
        var ballast = BlockDef("ship_ballast", "Ballast Tank")
        ballast.tex = ["ship_ballast_side", "ship_ballast_side", "ship_ballast_top", "ship_ballast_top", "ship_ballast_side", "ship_ballast_side"]
        ballast.hardness = 3; ballast.tool = .pickaxe; ballast.requiresTool = true; ballast.sound = .stone
        add(ballast)

        // Sea mine (C8): a horned iron ball; a player or a moving vessel close by sets it off.
        var mine = BlockDef("sea_mine", "Sea Mine")
        mine.tex = ["sea_mine"]; mine.render = .model; mine.opaque = false; mine.hardness = 2; mine.tool = .pickaxe; mine.sound = .stone
        mine.boxes = [Box(3, 3, 3, 13, 13, 13), Box(7, 13, 7, 9, 16, 9), Box(0, 7, 7, 3, 9, 9), Box(13, 7, 7, 16, 9, 9),
                      Box(7, 7, 0, 9, 9, 3), Box(7, 7, 13, 9, 9, 16), Box(7, 0, 7, 9, 3, 9)]
        add(mine)

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

        // P459 (Oct 25 16:10-16:11, "we need gun barrels. So if I wanna make my own gun, naval gun thing, then I need to
        // be able to do that"): a Gun Barrel, a steel tube laid along its facing. Set in a line on from a cannon's muzzle
        // (any number, the first five count) it lengthens that gun: each one adds 40 % to its shell's burst and 12 % to
        // its speed, the shell leaves from the last tube's end, and the gun reloads a little slower (Ship.cannonLength).
        var tube = BlockDef("ship_gun_barrel", "Gun Barrel")
        tube.tex = ["ship_barrel"]; tube.render = .model; tube.layer = .cutout; tube.opaque = false; tube.hardness = 4
        tube.tool = .pickaxe; tube.requiresTool = true; tube.sound = .stone; tube.skyStop = false; tube.resistance = 8
        facing4(tube, [Box(5, 5, 0, 11, 11, 16, tex: barrel), Box(4, 4, 7, 12, 12, 9, tex: dark)])

        // P477 (Oct 27 19:28-19:30: "Things should be hollow inside at least"; "Big, medium, and small gun barrels, and
        // then fit them into... all gun systems"; "Stop using the cannonball thing. Use the barrel system"): three bored
        // steel tubes, open end to end. Laid in line on from a cannon's muzzle the first one sets the gun's calibre
        // (Ship.cannonCalibre, CannonCalibre): small a quick-firing autocannon, medium a tank gun, large a naval gun,
        // each a long straight shot with a shell, not a lobbed ball; every further tube adds reach and punch.
        for (n, label, o, i) in [("gun_barrel_small", "Small Gun Barrel", 6, 7), ("gun_barrel_medium", "Medium Gun Barrel", 4, 6),
                                 ("gun_barrel_large", "Large Gun Barrel", 1, 4)] {
            var d = BlockDef(n, label)
            d.tex = ["ship_barrel"]; d.render = .model; d.layer = .cutout; d.opaque = false; d.hardness = 4 + Float(7 - i)
            d.tool = .pickaxe; d.requiresTool = true; d.sound = .stone; d.skyStop = false; d.resistance = 8 + Float(7 - i) * 2
            let e = 16 - o, j = 16 - i
            facing4(d, [Box(o, o, 0, e, i, 16, tex: barrel), Box(o, j, 0, e, e, 16, tex: barrel),
                        Box(o, i, 0, i, j, 16, tex: barrel), Box(j, i, 0, e, j, 16, tex: barrel)])
        }

        // H4: the Tidebreaker's breech, salvaged from a Meridian frigate's main gun (ShipManager.salvageMainGun). Set on
        // a ship of your own, it gives the helm the main gun, firing out of the side opposite its front like a cannon.
        var breech = BlockDef("tidebreaker_breech", "Tidebreaker Breech")
        breech.tex = ["ship_metal"]; breech.render = .model; breech.layer = .cutout; breech.opaque = false; breech.hardness = 6
        breech.tool = .pickaxe; breech.requiresTool = true; breech.sound = .stone; breech.skyStop = false; breech.resistance = 12
        breech.emit = 7
        facing4(breech, [Box(1, 0, 1, 15, 6, 15, tex: t6("ship_metal")), Box(3, 6, 4, 13, 14, 16, tex: barrel),
                         Box(2, 7, 7, 14, 13, 9, tex: brass), Box(2, 7, 12, 14, 13, 14, tex: brass), Box(5, 8, 0, 11, 12, 4, tex: barrel)])

        // Wheel: a disc rolling along the facing axis (north/south roll along Z, west/east along X).
        var wheel = BlockDef("ship_wheel", "Wheel")
        wheel.tex = ["ship_tyre"]; wheel.render = .model; wheel.opaque = false; wheel.hardness = 1.5; wheel.tool = .axe; wheel.sound = .wood
        wheel.skyStop = true
        let tyre = t6("ship_tyre")
        facing4(wheel, [
            Box(3, 4, 0, 13, 12, 16, tex: tyre), Box(3, 0, 4, 13, 16, 12, tex: tyre), Box(3, 2, 2, 13, 14, 14, tex: tyre),
            Box(2, 6, 6, 14, 10, 10, tex: metal),
        ])
        // P507 (Nov 1 12:40:10, a traders' camp's covered wagon on log stumps: "This is supposed to be a carriage. Make
        // it an actual carriage"): a cart wheel, wooden, spoked, iron-hubbed; to a vehicle's physics a wheel like any.
        var cart = BlockDef("cart_wheel", "Cart Wheel")
        cart.tex = ["spruce_planks"]; cart.render = .model; cart.opaque = false; cart.hardness = 1; cart.tool = .axe; cart.sound = .wood
        let rim = t6("spruce_planks"), spoke = t6("stripped_spruce_log"), hub = t6("ship_metal")
        facing4(cart, [
            Box(6, 0, 4, 10, 2, 12, tex: rim), Box(6, 14, 4, 10, 16, 12, tex: rim), Box(6, 4, 0, 10, 12, 2, tex: rim), Box(6, 4, 14, 10, 12, 16, tex: rim),
            Box(6, 2, 2, 10, 4, 4, tex: rim), Box(6, 2, 12, 10, 4, 14, tex: rim), Box(6, 12, 2, 10, 14, 4, tex: rim), Box(6, 12, 12, 10, 14, 14, tex: rim),
            Box(7, 2, 7, 9, 14, 9, tex: spoke), Box(7, 7, 2, 9, 9, 14, tex: spoke),
            Box(4, 6, 6, 12, 10, 10, tex: hub),
        ])
        // P477 (Oct 27 19:27, the Works' tank: "This thing's tracks go in circles as if they were a wheel"): a track
        // link, a wheel to the physics (it carries and drives the hull) that is drawn with the hull, not spun. A run of
        // them makes a tank's track; the cleats show on every face.
        var track = BlockDef("ship_track", "Track Link")
        track.tex = ["ship_track"]; track.hardness = 3; track.tool = .pickaxe; track.sound = .metal; track.resistance = 10
        add(track)

        // Rotor head (helicopters, FlightModel.swift): mast, swashplate and hub with blade roots; on a flying ship
        // it turns and the blades are drawn to the rotor's full diameter from the render-only blade below.
        var rotor = BlockDef("ship_rotor", "Rotor Head")
        rotor.tex = ["ship_metal"]; rotor.render = .model; rotor.layer = .cutout; rotor.opaque = false; rotor.hardness = 3
        rotor.tool = .pickaxe; rotor.requiresTool = true; rotor.sound = .stone; rotor.skyStop = false
        let bladeT = t6("ship_blade"), frame = t6("capital_airframe")
        rotor.boxes = [Box(6, 0, 6, 10, 9, 10, tex: metal), Box(4, 8, 4, 12, 10, 12, tex: brass), Box(5, 10, 5, 11, 13, 11, tex: frame),
                       Box(0, 11, 7, 16, 12, 9, tex: bladeT), Box(7, 11, 0, 9, 12, 16, tex: bladeT)]
        add(rotor)
        var rotorBlade = BlockDef("ship_rotor_blade", "Rotor Blade")
        rotorBlade.tex = ["capital_airframe"]; rotorBlade.render = .model; rotorBlade.layer = .cutout; rotorBlade.opaque = false; rotorBlade.hidden = true
        rotorBlade.boxes = [Box(0, 7, 6, 16, 8, 10, tex: frame), Box(0, 7, 6, 1, 8, 10, tex: t6("ship_metal"))]
        add(rotorBlade)
        // Capital airframe: light white alloy panels for the Capital's aircraft (0.3 t a block: ShipParts.mass).
        var airframe = BlockDef("capital_airframe", "Capital Airframe")
        airframe.tex = ["capital_airframe"]; airframe.hardness = 2; airframe.tool = .pickaxe; airframe.sound = .stone
        add(airframe)
        // Capital airfoil: a wing panel (an airfoil to the flight model, like the wooden one) in the white alloy.
        var cwing = BlockDef("capital_wing", "Capital Airfoil")
        cwing.tex = ["capital_wing"]; cwing.render = .model; cwing.opaque = false; cwing.hardness = 2; cwing.tool = .pickaxe; cwing.sound = .stone
        cwing.boxes = [Box(0, 6, 0, 16, 10, 16)]; cwing.skyStop = true
        add(cwing)
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
        // White wing skin with grey panel lines along the span and a grey leading edge.
        p["capital_wing"] = { x, y in
            if y == 0 { return hex(0xA9B0B7) }
            if y == 8 || x == 0 { return hex(0xC9CED3) }
            return hex(0xF1F3F5, 0.975 + 0.02 * r(x / 4, y / 4, 2714))
        }
        p["ship_wood"] = { x, y in
            let plank = y / 4
            let edge = y % 4 == 3 || (x + plank * 5) % 16 == 0
            return hex(0x9C6B3C, edge ? 0.7 : 0.9 + 0.15 * r(x / 3, y, 2601 + plank))
        }
        p["ship_wood_dark"] = { x, y in hex(0x5A3A1E, 0.85 + 0.2 * r(x, y / 2, 2602)) }
        p[Wrecks.rotten] = { x, y in
            let plank = y / 4, edge = y % 4 == 3 || (x + plank * 5) % 16 == 0
            let moss = r(x / 2, y / 2, 2631) > 0.72, hole = r(x, y, 2632) > 0.93
            if hole { return hex(0x1E1A14) }
            return moss ? hex(0x4E5A2C, 0.8 + 0.2 * r(x, y, 2633)) : hex(0x5E4A34, edge ? 0.6 : 0.75 + 0.2 * r(x / 3, y, 2634 + plank))
        }
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
        p["ship_ballast_side"] = { x, y in
            if x == 0 || x == 15 || y == 0 || y == 15 { return hex(0x2E3338) }
            if y == 5 || y == 10 { return hex(0x4A5056) }                // bands
            if (x == 3 || x == 12) && y % 3 == 1 { return hex(0x8A9096) }  // rivets
            return hex(0x5E676E, 0.9 + 0.1 * r(x, y, 2620))
        }
        p["ship_ballast_top"] = { x, y in
            let dx = x - 8, dy = y - 8
            if dx * dx + dy * dy < 10 { return hex(0xA8823A, dx * dx + dy * dy < 4 ? 0.7 : 1) }   // the valve wheel
            return hex(0x535B62, 0.9 + 0.1 * r(x, y, 2621))
        }
        p["sea_mine"] = { x, y in
            let rust = r(x, y, 2622)
            if (x + y) % 9 == 0 { return hex(0x6A3E22, 0.8 + 0.3 * rust) }
            return hex(0x3A3F44, 0.8 + 0.25 * rust)
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
        p["ship_track"] = { x, y in
            if x % 8 < 2 { return hex(0x1E2022, 0.9 + 0.1 * r(x, y, 2616)) }                     // the cleats
            if y < 2 || y > 13 { return hex(0x3A3E42) }                                       // the link edges
            return hex(0x2C2F33, 0.88 + 0.12 * r(x, y, 2617))
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
        // P269 (Oct 14 19:25, eight wool a balloon was "insane"): three wool over a string or a piece of leather make two.
        r.append(shaped(["WWW", " S "], ["W": "white_wool", "S": "string"], "ship_balloon", 2))
        r.append(shaped(["WWW", " L "], ["W": "white_wool", "L": "leather"], "ship_balloon", 2))
        r.append(shaped(["SSS", "PPP"], ["S": "stick", "P": "#planks"], "ship_wing", 4))
        r.append(shaped(["PIP", " I ", " I "], ["P": "ship_propeller", "I": "iron_ingot"], "ship_rotor"))                   // P263: the other way to fly
        r.append(shaped([" P ", "PIP", " P "], ["P": "#planks", "I": "iron_ingot"], "ship_wheel", 2))
        r.append(shaped(["III", "I I", "III"], ["I": "iron_ingot"], "ship_turret_ring"))
        r.append(shaped(["II ", "IGI", "PPP"], ["I": "iron_ingot", "G": "gunpowder", "P": "#planks"], "ship_cannon"))
        r.append(shapeless(["iron_ingot", "gunpowder"], Wrecks.cannonball, 4))                                              // P93
        r.append(shaped(["SSS"], ["S": "steel_ingot"], "ship_gun_barrel", 2))                                                 // P459
        r.append(shaped(["III"], ["I": "iron_ingot"], "ship_gun_barrel", 1))
        r.append(shaped(["S", "S"], ["S": "steel_ingot"], "gun_barrel_small", 2))                                           // P477
        r.append(shaped(["SSS", "S S"], ["S": "steel_ingot"], "gun_barrel_medium", 2))
        r.append(shaped(["SSS", "S S", "SSS"], ["S": "steel_ingot"], "gun_barrel_large", 1))
        r.append(shapeless(["ship_wheel", "iron_ingot", "iron_ingot"], "ship_track", 4))
        r.append(shaped([" S ", "SIS", " S "], ["S": "stick", "I": "iron_nugget"], "cart_wheel", 2))
        // P459 (Oct 25 16:10, "Do we have like barrels and stuff? ... If I wanna make like a plane or something"): the
        // Capital's aircraft parts can be made: four steel ingots make four sheets of light white airframe, three
        // sheets make three airfoils, and a black dye turns one into the Ashguard's dark fighter airfoil.
        r.append(shaped(["SS", "SS"], ["S": "steel_ingot"], "capital_airframe", 4))
        r.append(shaped(["AAA"], ["A": "capital_airframe"], "capital_wing", 3))
        r.append(shapeless(["capital_wing", "black_dye"], "fighter_wing"))
        r.append(shaped(["BBB", "ECE", "BBB"], ["B": "iron_block", "E": "ship_engine", "C": "crafting_table"], VehicleWorks.key))   // P54
        r.append(shaped(["BBB", "BHB", "PEP"], ["B": "ship_balloon", "H": "ship_helm", "P": "ship_propeller", "E": "ship_engine"], SkySkiff.key))   // A4
        r.append(shaped(["  I", " S ", "S  "], ["I": "iron_ingot", "S": "string"], GrappleLine.key))      // C7
        r.append(shaped(["IGI", "I I", "IBI"], ["I": "iron_ingot", "G": "glass", "B": "bucket"], "ship_ballast", 2))       // C8
        r.append(shaped([" I ", "ITI", " I "], ["I": "iron_ingot", "T": "tnt"], Submarine.mineKey))       // C8
        r.append(shaped(["IGI", "HEP", "BBB"], ["I": "iron_ingot", "G": "glass", "H": "ship_helm", "E": "ship_engine", "P": "ship_propeller", "B": "ship_ballast"], Submarine.kitKey))   // C8
        return r
    }
}
