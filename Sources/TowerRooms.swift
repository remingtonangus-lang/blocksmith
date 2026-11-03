import Foundation

// P510 (Nov 1 evening, in a citadel side tower: the rooms "more decorative", "ammo racks"): the side towers' storeys
// were one empty ring each, the same five times over. Each storey is now its own room: a guard post at the plaza, a
// signals room (cabinets, consoles, the map table), a bunk room, an armoury with ammo racks and a gunsmith's bench, and
// a mess with tables and chairs; the top floor stays the gun room. New ground gets them from CapitalBase.build; in his
// World the lift's retrofit furnishes a storey that is still empty.
//
// Local plan (x across, z north to south, the tower's middle at 0, 0; inside to five out): kept clear are the corridor
// through the middle (z -1...1: the plaza door, the skyway, the top walkway), the ladder up the north (x 0, z -5...-2),
// the lift south of the middle (x -4...-1, z 1...4, its button at -1, 0) and the ceiling lights. Rooms use the north
// corners (x 1...5 and -5...-1, z -5...-2) and the south east (x 0...5, z 2...5).
enum TowerRooms {
    enum Kind: Int, CaseIterable { case guardPost, signals, bunks, armoury, mess }
    static var furnished = 0                                   // (checks)

    // `cell(x, y, z, b)`: x, z local, y absolute; b nil reads, else writes and returns it. `y` is the floor stood on + 1.
    static func furnish(_ kind: Kind, _ y: Int, onlyIfEmpty: Bool = false, cell: (Int, Int, Int, BlockID?) -> BlockID) {
        func g(_ n: String) -> BlockID? { Blocks.has(n) ? Blocks.id(n) : nil }
        if onlyIfEmpty {
            // Anything stood on this storey outside the corridor, ladder and lift: he or the citadel furnished it.
            for z in -5...5 { for x in -5...5 where abs(z) > 1 && !(x == 0 && z < 0) && !(x >= -4 && x <= -1 && z >= 1 && z <= 4) {
                guard CapitalBase.rounded(x, z, 5.6) else { continue }
                if cell(x, y, z, nil) != AIR { return }
            } }
        }
        func put(_ x: Int, _ dy: Int, _ z: Int, _ b: BlockID?) {
            guard let b, cell(x, y + dy, z, nil) == AIR else { return }
            _ = cell(x, y + dy, z, b)
        }
        func stack(_ x: Int, _ z: Int, _ b: BlockID?, _ h: Int) { for k in 0..<h { put(x, k, z, b) } }
        // A table: a post with a pressure plate on it.
        let post = g("oak_fence"), plate = g("oak_pressure_plate")
        func table(_ x: Int, _ z: Int) { put(x, 0, z, post); put(x, 1, z, plate) }
        // Chairs face the way named; north is the plain name.
        func chair(_ x: Int, _ z: Int, _ face: String) { put(x, 0, z, g(face == "north" ? "oak_chair" : "oak_chair[\(face)]")) }
        // A bed: head toward -z (state 1) or +z (state 0), foot first.
        func bed(_ x: Int, _ zFoot: Int, _ zHead: Int, _ colour: String) {
            guard let f = g("\(colour)_bed"), let h = g("\(colour)_bed_head") else { return }
            let s = BlockID(zHead < zFoot ? 1 : 0)
            put(x, 0, zFoot, f + s); put(x, 0, zHead, h + s)
        }
        let barrel = g("barrel"), cab = g("data_cabinet"), console = g("command_console"), term = g("greywall_terminal")
        let crate = g("ammo_crate"), ash = g("ash_crate") ?? g("ammo_crate"), shelf = g("bookshelf"), pot = g("flower_pot")
        switch kind {
        case .guardPost:
            // A duty desk (console, chair) and the log cabinets; a table for the watch with two chairs; stores.
            put(-3, 0, -4, console); put(-2, 0, -4, console); chair(-3, -3, "north")
            stack(-5, -4, cab, 2); stack(-5, -3, cab, 2)
            table(3, -3); chair(2, -3, "east"); chair(4, -3, "west")
            stack(5, -4, crate, 2); put(4, 0, -5, barrel)
            put(5, 0, 2, barrel); put(5, 0, 3, barrel); put(5, 1, 2, pot); stack(5, 4, ash, 2); put(3, 0, 5, barrel)
        case .signals:
            // Two banks of consoles with their chairs, cabinets along the walls, and the map table.
            put(2, 0, -4, console); put(3, 0, -4, console); chair(2, -3, "north"); chair(3, -3, "north")
            for z in -4...(-2) { stack(5, z, cab, 2) }
            put(-3, 0, -4, term); put(-2, 0, -4, term); chair(-3, -3, "north"); chair(-2, -3, "north")
            for z in -4...(-2) { stack(-5, z, cab, 2) }
            put(2, 0, 3, g("greywall_map_table") ?? console); put(3, 0, 3, g("greywall_map_table") ?? console)
            for z in 2...4 { stack(5, z, cab, 2) }
        case .bunks:
            // Bunks heads to the walls, a locker at each.
            for x in [-4, -2, 2, 4] { bed(x, -4, -5, x < 0 ? "light_gray" : "white") }
            put(-4, 0, -3, barrel); put(4, 0, -3, barrel); put(-5, 0, -2, barrel); put(5, 0, -2, barrel)
            for x in [2, 4] { bed(x, 4, 5, "light_blue") }
            put(5, 0, 2, barrel); put(5, 0, 3, barrel); put(5, 1, 3, pot)
        case .armoury:
            // Ammo racks two high along the walls, a gunsmith's bench and an anvil.
            for z in -4...(-2) { stack(5, z, crate, 2) }
            stack(4, -5, crate, 2); stack(3, -5, crate, 1)
            put(2, 0, -4, g(GunsmithBench.key)); put(3, 0, -3, g("anvil"))
            for z in -4...(-2) { stack(-5, z, ash, 2) }
            stack(-4, -5, ash, 2); stack(-3, -5, ash, 1); put(-3, 0, -3, g("anvil"))
            for z in 2...4 { stack(5, z, crate, 2) }
            stack(4, 5, crate, 2); stack(3, 5, crate, 1)
        case .mess:
            // A long table and chairs either side; a second table; shelves and stores.
            for x in 2...4 { table(x, -3); chair(x, -4, "south"); chair(x, -2, "north") }
            stack(-5, -4, shelf, 2); stack(-5, -3, shelf, 2); put(-4, 0, -5, barrel); put(-3, 0, -5, barrel); put(-3, 1, -5, pot)
            for x in 2...3 { table(x, 3); chair(x, 4, "north"); chair(x, 2, "south") }
            chair(4, 3, "west"); put(5, 0, 2, barrel); stack(5, 4, shelf, 2)
        }
        furnished += 1
    }
}
