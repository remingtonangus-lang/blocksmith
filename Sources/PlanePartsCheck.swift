import Foundation

// P459's check (questcheck --planeparts): the Capital's aircraft parts can be crafted from steel, and the grids that
// make them make nothing else (a 2 x 2 of steel is the airframe, a row of steel is still two gun barrels).
enum PlanePartsCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        func id(_ k: String) -> ItemID { Items.id(k) }
        func craft(_ rows: [[String]]) -> (String, Int) {
            var grid = [ItemID](repeating: 0, count: 9)
            for (y, row) in rows.enumerated() { for (x, k) in row.enumerated() where !k.isEmpty { grid[x + y * 3] = id(k) } }
            guard let r = Recipes.match(grid, 3, 3) else { return ("nothing", 0) }
            return (Items.key(r.result.item), r.result.count)
        }
        let s = "steel_ingot", a = "capital_airframe"
        let frame = craft([[s, s], [s, s]])
        check(frame == ("capital_airframe", 4), "planeparts: four steel ingots make \(frame.1) \(frame.0) (want 4 capital_airframe)")
        let wing = craft([[a, a, a]])
        check(wing == ("capital_wing", 3), "planeparts: three airframe sheets make \(wing.1) \(wing.0) (want 3 capital_wing)")
        let dark = craft([["capital_wing", "black_dye"]])
        check(dark == ("fighter_wing", 1), "planeparts: an airfoil and black dye make \(dark.1) \(dark.0) (want fighter_wing)")
        let tube = craft([[s, s, s]])
        check(tube == ("ship_gun_barrel", 2), "planeparts: a row of steel still makes \(tube.1) \(tube.0)")
        let lift = [a, "capital_wing", "fighter_wing"].map { ShipParts.kinds[Int(Blocks.id($0))] == .wing }
        check(lift == [false, true, true], "planeparts: both airfoils lift a hull, the airframe is plain panel \(lift)")
    }
}
