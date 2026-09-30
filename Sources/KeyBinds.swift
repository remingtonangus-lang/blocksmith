import Foundation

// Rebindable keyboard controls (Options > Keyboard & Mouse > Key Bindings). Shift (sneak) and Ctrl (sprint)
// stay on the modifier keys; everything else maps an action to a macOS virtual key code, saved in UserDefaults.
enum KeyBinds {
    enum Action: String, CaseIterable {
        case forward, back, left, right, jump, inventory, drop, fly, offhand, chat, camera, advancements
        var title: String {
            switch self {
            case .forward: return "Walk Forward"
            case .back: return "Walk Backward"
            case .left: return "Strafe Left"
            case .right: return "Strafe Right"
            case .jump: return "Jump"
            case .inventory: return "Inventory"
            case .drop: return "Drop Item"
            case .fly: return "Toggle Flying"
            case .offhand: return "Swap Off Hand"
            case .chat: return "Commands"
            case .camera: return "Camera View"
            case .advancements: return "Advancements"
            }
        }
        var defaultKey: UInt16 {
            switch self {
            case .forward: return Key.w
            case .back: return Key.s
            case .left: return Key.a
            case .right: return Key.d
            case .jump: return Key.space
            case .inventory: return Key.e
            case .drop: return Key.q
            case .fly: return Key.f
            case .offhand: return Key.r
            case .chat: return Key.t
            case .camera: return Key.f5
            case .advancements: return 37      // L
            }
        }
    }

    private static var cache: [Action: UInt16] = {
        var c: [Action: UInt16] = [:]
        for a in Action.allCases {
            if let v = UserDefaults.standard.object(forKey: "key." + a.rawValue) as? Int, v >= 0, v < 256 { c[a] = UInt16(v) } else { c[a] = a.defaultKey }
        }
        return c
    }()

    static func key(_ a: Action) -> UInt16 { cache[a] ?? a.defaultKey }

    static func set(_ a: Action, _ k: UInt16) {
        // A key does one thing: whoever had it before gets this action's old key.
        if let other = Action.allCases.first(where: { $0 != a && key($0) == k }) {
            cache[other] = key(a)
            UserDefaults.standard.set(Int(key(a)), forKey: "key." + other.rawValue)
        }
        cache[a] = k
        UserDefaults.standard.set(Int(k), forKey: "key." + a.rawValue)
    }

    static func reset() {
        for a in Action.allCases {
            cache[a] = a.defaultKey
            UserDefaults.standard.removeObject(forKey: "key." + a.rawValue)
        }
    }

    // Keys that can't be bound (menus, typing, debug keys).
    static let reserved: Set<UInt16> = [Key.esc, Key.enter, Key.f1, Key.f2, Key.f3, 51 /* delete */]

    static func name(_ k: UInt16) -> String {
        let names: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Enter", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
            43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
            96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12", 118: "F4", 120: "F2", 122: "F1",
            115: "Home", 116: "PgUp", 117: "Del", 119: "End", 121: "PgDn", 123: "Left", 124: "Right", 125: "Down", 126: "Up",
            82: "Num0", 83: "Num1", 84: "Num2", 85: "Num3", 86: "Num4", 87: "Num5", 88: "Num6", 89: "Num7", 91: "Num8", 92: "Num9",
        ]
        return names[k] ?? "Key \(k)"
    }
}
