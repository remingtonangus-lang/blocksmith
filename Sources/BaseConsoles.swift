import Foundation
import simd

// P422 (Remington, Oct 23 21:13: "all these freaking consoles here. It'd be nice if they... did different things"):
// inside a base (a Capital citadel or a Greywall Command fortress) each command console (or Greywall terminal) has one of five jobs, fixed
// by where it stands, and says which when used:
//   locator  the base locator he used (the radio net where the base has one, else the radar picture of the sites
//            and patrols, FactionGear.consoleUse);
//   map      the base and the land round it drawn onto the world map, which opens on it;
//   alarm    the base's alarm stood down (lamps out, the klaxon quiet); a soldier who sees you sounds it again;
//   doors    every door in the base opened, or shut if most stand open;
//   cameras  the guards inside the walls, with their bearings and distance, on the radar readout for 30 s.
// A console outside any base stays the locator.
enum BaseConsoles {
    enum Job: Int, CaseIterable {
        case locator, map, alarm, doors, cameras
        var name: String { ["Base Locator", "Base Map", "Alarm Control", "Door Control", "Security Cameras"][rawValue] }
    }
    static var camerasAt: IVec3?                    // the console whose cameras show on the readout
    static let reach = 72                           // doors and guards this far from the console (blocks)

    static func job(_ p: IVec3) -> Job {
        let h = (p.x &* 73_856_093) ^ (p.y &* 19_349_663) ^ (p.z &* 83_492_791)
        return Job(rawValue: (h & 0x7fff_ffff) % Job.allCases.count) ?? .locator
    }
}

extension Game {
    // The base a console stands in: a citadel record's key or a Greywall site's key.
    func consoleBase(_ p: IVec3) -> (capital: String?, greywall: String?) {
        let q = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)
        if let r = bases.records.values.first(where: { $0.inside(q) }) { return (r.key, nil) }
        if let (k, _) = bases.greywall.sites.first(where: { Greywall.inside($0.value, q) }) { return (nil, k) }
        return (nil, nil)
    }

    // Use on a command console: true when a base console did its own job (the locator falls through to the radio net
    // and the radar picture as before).
    func baseConsoleUse(_ p: IVec3) -> Bool {
        let k = Blocks.key(Blocks.groupBase[Int(world.materialAt(p.x, p.y, p.z))])
        guard k == "command_console" || k == "greywall_terminal" else { return false }
        let base = consoleBase(p)
        guard base.capital != nil || base.greywall != nil else { return false }
        let job = BaseConsoles.job(p)
        let at = V3(Float(p.x) + 0.5, Float(p.y) + 0.5, Float(p.z) + 0.5)
        switch job {
        case .locator:
            return false
        case .map:
            let fog = MapFog.shared
            for dz in stride(from: -192, through: 192, by: 96) { for dx in stride(from: -192, through: 192, by: 96) {
                fog.reveal(around: at + V3(Float(dx), 0, Float(dz)))
            } }
            sfx(.click, 0.8, at: at)
            onToast?("\(job.name): the base and the land round it are on your map")
            openMenu(MapMenu(game: self))
        case .alarm:
            var stood = false
            if let k = base.capital, var r = bases.records[k], r.alert != .calm {
                r.alert = .calm; r.calm = 0
                bases.records[k] = r; stood = true
            }
            if let k = base.greywall, var s = bases.greywall.sites[k], s.on {
                s.on = false; s.quiet = 0
                greywallLamps(&s, lit: false)
                bases.greywall.sites[k] = s; stood = true
            }
            if stood { AlarmWaves.plans[base.capital ?? base.greywall ?? ""] = nil }
            sfx(.click, 0.8, at: at)
            onToast?(stood ? "\(job.name): alarm stood down (a guard who sees you will sound it again)" : "\(job.name): no alarm sounding")
        case .doors:
            let n = consoleDoors(p)
            onToast?(n.count == 0 ? "\(job.name): no doors in reach" : "\(job.name): \(n.count) door\(n.count == 1 ? "" : "s") \(n.opened ? "opened" : "shut")")
        case .cameras:
            BaseConsoles.camerasAt = p
            consoleRadarUntil = clock + 30
            Game.radarCache.time = -1
            sfx(.click, 0.8, at: at)
            onToast?("\(job.name): the guards inside the walls on your radar for 30 s")
        }
        return true
    }

    // Opens every door within reach of the console (both halves, as a hand would), or shuts them when most stand open.
    func consoleDoors(_ p: IVec3) -> (count: Int, opened: Bool) {
        var doors: [IVec3] = [], open = 0
        let r = BaseConsoles.reach
        for x in (p.x - r)...(p.x + r) { for z in (p.z - r)...(p.z + r) where world.isLoaded(x, z) {
            for y in max(0, p.y - 16)...min(CH - 1, p.y + 16) {
                let b = world.block(x, y, z)
                guard Blocks.shape[Int(b)] == "door" else { continue }
                let st = Int(b - Blocks.groupBase[Int(b)])
                guard st & 8 == 0 else { continue }                 // (the lower half; toggleOpenable swings both)
                // (a locked vault or comms bulkhead stays to its keycard: D35, BaseSecurity)
                if let lk = BaseSecurity.lockedDoor(self, IVec3(x, y, z)), !bases.greywall.taken.contains(lk) { continue }
                doors.append(IVec3(x, y, z))
                if st & 4 != 0 { open += 1 }
            }
        } }
        let opening = open * 2 < doors.count
        for d in doors {
            let st = Int(world.block(d.x, d.y, d.z) - Blocks.groupBase[Int(world.block(d.x, d.y, d.z))])
            if (st & 4 != 0) != opening { toggleOpenable(d) }
        }
        return (doors.count, opening)
    }

    // The cameras' picture: the guards within reach of the console, nearest first.
    func consoleCameraContacts() -> [RadarContact] {
        guard let c = BaseConsoles.camerasAt else { return [] }
        let at = V3(Float(c.x) + 0.5, Float(c.y), Float(c.z) + 0.5), r = Float(BaseConsoles.reach)
        let guards = mobs.mobs.filter { $0.kind.steelhold && $0.kind != .deckGun && $0.health > 0 && simd_length($0.pos - at) < r }
        let near = guards.sorted { simd_length($0.pos - player.pos) < simd_length($1.pos - player.pos) }
        var out = near.prefix(8).map { RadarContact(name: "Guard", kind: "garrison", x: Int($0.pos.x), z: Int($0.pos.z)) }
        if out.isEmpty { out.append(RadarContact(name: "No guards in sight", kind: "garrison", x: c.x, z: c.z)) }
        else if guards.count > out.count { out.append(RadarContact(name: "and \(guards.count - out.count) more", kind: "garrison", x: c.x, z: c.z)) }
        return out
    }
}
