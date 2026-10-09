import Foundation

// LAYOUT PRESETS (Mac gamepads). "Halo" (the Mac default) follows Halo Infinite's default controller layout:
//   A jump, B crouch (sneak; tap toggles with Sneak: Toggle), X reload / pick block, Y tap = switch weapon (back to
//   the previously selected hotbar slot, like Halo's two-weapon swap), Y hold = inventory, L3 sprint, R3 melee,
//   LT aim / use / place, RT fire / break, Menu pause, View camera / map (hold).
//   LB/RB stay hotbar left/right (RB hold = weapon wheel): Halo puts grenade/equipment there, but this game carries
//   nine slots, so the bumpers are the only fast way through them; grenades are hotbar items anyway.
// "Classic" is the older layout: Y opens the inventory at once and nothing switches weapons. Both share the same
// button permutation below (custom remaps sit on top of either). The Quest has no presets: halo is always false there,
// so its Touch-controller mapping is unchanged. Switch in Options > Controller > Button Mapping > Layout.
// Controller button remapping (Options > Controller > Button Mapping). The game reads "logical" buttons
// (A = jump/select, B = sneak/back...); this table says which physical button drives each one. Remapping is
// applied as the pad is read, so gameplay and menus both follow it, and prompts show the physical button.
// The Menu button and the analog triggers/sticks are fixed.
enum PadMap {
    static let names = ["A", "B", "X", "Y", "LB", "RB", "L3", "R3", "View", "D-pad Up", "D-pad Down", "D-pad Left", "D-pad Right"]
    // What each logical button does (gameplay / menus / guns / vehicles); remapping moves all of them together.
    static var actions: [String] { ["Jump / Select", "Sneak / Back / Leave", "Pick Block / Reload", halo ? "Switch Weapon / Inventory (hold)" : "Inventory / Quick Move", "Hotbar Left / Descend",
                          "Hotbar Right / Weapon Wheel", "Sprint", "Melee", "Camera / World Map (hold)", "Fly", "Drop", "Commands", "Swap Off Hand"] }
    static let glyphs: [Glyph] = [.a, .b, .x, .y, .lb, .rb, .l3, .r3, .view, .dup, .ddown, .dleft, .dright]
    static var count: Int { names.count }

    // map[logical] = physical
    static var map: [Int] = {
        if let a = UserDefaults.standard.array(forKey: "padMap") as? [Int], a.count == names.count,
           Set(a) == Set(0..<names.count) { return a }
        return Array(0..<names.count)
    }()
    static var isDefault: Bool { map == Array(0..<count) }

    // Halo layout on (Y tap = switch weapon, Y hold = inventory). Saved as "padLayout"; with nothing saved a Mac
    // that already has a custom map keeps the Classic behaviour it was set up with, anything else gets Halo.
    #if os(macOS)
    static var halo: Bool = {
        if let s = UserDefaults.standard.string(forKey: "padLayout") { return s == "halo" }
        return UserDefaults.standard.array(forKey: "padMap") == nil
    }() { didSet { UserDefaults.standard.set(halo ? "halo" : "classic", forKey: "padLayout") } }
    #else
    static var halo = false
    #endif
    static var layoutName: String { halo ? "Halo" : "Classic" }

    static func save() { UserDefaults.standard.set(map, forKey: "padMap") }
    static func reset() {
        map = Array(0..<count); UserDefaults.standard.removeObject(forKey: "padMap")
        #if os(macOS)
        halo = true
        #endif
    }

    // Logical `i` now uses physical `phys`; whichever logical had `phys` takes over the old one (a swap).
    static func assign(_ i: Int, _ phys: Int) {
        guard i >= 0, i < count, phys >= 0, phys < count else { return }
        if let j = map.firstIndex(of: phys) { map[j] = map[i] }
        map[i] = phys
        save()
    }

    static func get(_ p: PadSnapshot, _ i: Int) -> Bool {
        switch i {
        case 0: return p.a
        case 1: return p.b
        case 2: return p.x
        case 3: return p.y
        case 4: return p.lb
        case 5: return p.rb
        case 6: return p.l3
        case 7: return p.r3
        case 8: return p.view
        case 9: return p.up
        case 10: return p.down
        case 11: return p.left
        default: return p.right
        }
    }
    static func set(_ p: inout PadSnapshot, _ i: Int, _ v: Bool) {
        switch i {
        case 0: p.a = v
        case 1: p.b = v
        case 2: p.x = v
        case 3: p.y = v
        case 4: p.lb = v
        case 5: p.rb = v
        case 6: p.l3 = v
        case 7: p.r3 = v
        case 8: p.view = v
        case 9: p.up = v
        case 10: p.down = v
        case 11: p.left = v
        default: p.right = v
        }
    }

    static func apply(_ raw: PadSnapshot) -> PadSnapshot {
        if isDefault { return raw }
        var p = raw
        for i in 0..<count { set(&p, i, get(raw, map[i])) }
        return p
    }

    // The badge to show for a logical button.
    static func glyph(_ g: Glyph) -> Glyph {
        guard !isDefault, let i = glyphs.firstIndex(of: g) else { return g }
        return glyphs[map[i]]
    }

    // First physical button that went down between two raw snapshots.
    static func newlyPressed(_ p: PadSnapshot, _ q: PadSnapshot) -> Int? {
        (0..<count).first { get(p, $0) && !get(q, $0) }
    }
}
