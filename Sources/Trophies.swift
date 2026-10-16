import Foundation
import simd

// Trophy room and museum (backlog O6). The great things you bring home count as trophies when you put them on show
// within 16 blocks of one of your places (your home, a Greywall base you took, a camp you freed):
//   pelts     each legendary beast's pelt and its trophy part (Hunting.legends)
//   bosses    the Wyrm Head, the Wyrm Egg, the Blight Star, and every legendary weapon or armour piece (C10)
//   flags     a captured Greywall Flag (taking a base hands you its flag; it hangs as a block)
// On show means in an item frame, worn or held by an armour stand, or placed as a block (flags, the egg, the head).
// The first time each goes on show: a toast and a little honour. With three or more on show your room is a museum:
// each in-game day visitors pay $2 a trophy, collected when you are home (a toast). Sneak-use an item frame to open the
// trophy ledger (every trophy, on show or not). Saved with the world extras ("trophies").
enum Trophies {
    struct Def { let key: String; let name: String; let kind: String }
    static let all: [Def] = {
        var out: [Def] = []
        for l in Hunting.legends {
            out.append(Def(key: l.pelt, name: l.peltName, kind: "Legendary pelt"))
            out.append(Def(key: l.trophy, name: l.trophyName, kind: "Legendary trophy"))
        }
        out.append(Def(key: "dragon_head", name: "Wyrm Head", kind: "Boss trophy"))
        out.append(Def(key: "dragon_egg", name: "Wyrm Egg", kind: "Boss trophy"))
        out.append(Def(key: "nether_star", name: "Brand Star", kind: "Boss trophy"))
        for d in Legendaries.all { out.append(Def(key: "legend:" + d.key, name: d.name, kind: "Legendary arms")) }
        out.append(Def(key: "greywall_flag", name: "Captured Greywall Flag", kind: "Captured flag"))
        return out
    }()
    static let blockKeys: Set<String> = ["dragon_head", "dragon_egg", "greywall_flag"]
    static let room: Float = 16
    static let museumAt = 3
    static let admission = 200          // cents per trophy per day

    static var shown: Set<String> = []  // trophies that have been on show
    static var onShow: Set<String> = [] // on show now (the last scan, in memory)
    static var paidDay = -1
    static var lastScan: Double = -100

    static func key(_ s: ItemStack) -> String? {
        guard !s.isEmpty else { return nil }
        if let l = s.legend, Legendaries.def(l) != nil { return "legend:" + l }
        let k = Items.key(s.item)
        return all.contains { $0.key == k } ? k : nil
    }

    static func encode() -> String { "\(paidDay)|" + shown.sorted().joined(separator: ",") }
    static func decode(_ s: String) {
        let p = s.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        paidDay = p.first.flatMap { Int($0) } ?? -1
        shown = p.count > 1 ? Set(p[1].split(separator: ",").map(String.init)) : []
        onShow = []; lastScan = -100
    }
}

extension Game {
    func trophyRooms() -> [V3] { raidPlaces().filter { !$0.1.isEmpty && ["your home", "your base", "your camp"].contains($0.1) }.map { $0.0 } }

    // What is on show within the room of c.
    func trophiesShown(near c: V3) -> Set<String> {
        var out = Set<String>()
        let r = Trophies.room
        for (p, be) in world.blockEntities where be.kind == .frame {
            guard simd_length(V3(Float(p.x), Float(p.y), Float(p.z)) - c) < r, let k = Trophies.key(be.container[0]) else { continue }
            out.insert(k)
        }
        for m in mobs.mobs where m.kind == .armorStand && simd_length(m.pos - c) < r {
            for s in m.equip ?? [] { if let k = Trophies.key(s) { out.insert(k) } }
        }
        let ids = Trophies.blockKeys.filter { Blocks.has($0) }.map { (Blocks.groupBase[Int(Blocks.id($0))], $0) }
        let cx = Int(floor(c.x)), cy = Int(floor(c.y)), cz = Int(floor(c.z)), ri = Int(r)
        for z in (cz - ri)...(cz + ri) { for x in (cx - ri)...(cx + ri) where world.isLoaded(x, z) {
            for y in max(1, cy - 8)...min(CH - 2, cy + 12) {
                let b = world.block(x, y, z)
                guard b != AIR else { continue }
                let g = Blocks.groupBase[Int(b)]
                for (id, k) in ids where g == id { out.insert(k) }
            }
        } }
        return out
    }

    // Every 5 s from the HUD tick: new trophies on show, and the museum's takings.
    func trophiesTick(force: Bool = false) {
        guard dim.dim == .overworld, force || clock - Trophies.lastScan >= 5 else { return }
        Trophies.lastScan = clock
        guard let c = trophyRooms().first(where: { simd_length($0 - player.pos) < Trophies.room + 8 }) else { return }
        let now = trophiesShown(near: c)
        Trophies.onShow = now
        for k in now.subtracting(Trophies.shown).sorted() {
            Trophies.shown.insert(k)
            let name = Trophies.all.first { $0.key == k }?.name ?? k
            onToast?("Trophy on show: \(name) (\(Trophies.shown.count) of \(Trophies.all.count))")
            Honour.earn(self, 0.5, source: "trophy", "a trophy on show")
        }
        let day = Int(time / DAY_LENGTH)
        if now.count >= Trophies.museumAt && day > Trophies.paidDay {
            if Trophies.paidDay >= 0 {
                let pay = Trophies.admission * now.count
                money += pay
                onToast?("Museum visitors paid \(Money.format(pay)) to see your \(now.count) trophies")
            } else {
                onToast?("Your trophy room is a museum now: visitors will pay to see it")
            }
            Trophies.paidDay = day
        }
    }

    func openTrophyLedger() {
        trophiesTick(force: true)
        openMenu(TrophyLedgerMenu(game: self))
    }
}

final class TrophyLedgerMenu: ListMenu {
    init(game g: Game) {
        super.init("Trophy Room", game: g)
        subtitle = "\(Trophies.onShow.count) on show, \(Trophies.shown.count) of \(Trophies.all.count) ever shown"
        say(Trophies.onShow.count >= Trophies.museumAt ? "Visitors pay \(Money.format(Trophies.admission)) a trophy each day." :
            "Put \(Trophies.museumAt) trophies on show at home to open a museum.", good: true)
    }
    override var rows: [Row] {
        corner = "Wallet " + Money.format(game.money)
        return Trophies.all.map { d in
            let on = Trophies.onShow.contains(d.key), was = Trophies.shown.contains(d.key)
            return Row(name: d.name, detail: d.kind, value: on ? "On show" : (was ? "Stored" : "Missing"), enabled: true, good: on)
        }
    }
    override func pressed(_ i: Int) {}
}
