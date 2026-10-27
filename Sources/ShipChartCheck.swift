import Foundation
import simd

// P472 (Oct 26 19:44, aboard a frigate: "I wasn't able to open the chest when I had a gun in my hand... Not sure what
// these map blocks are for, but they're not doing anything when I click on them"): `questcheck --shipchart` stands him
// by a Meridian frigate's chest and chart table with a rifle in hand and presses use on each.
enum ShipChartCheck {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        let w = g.world
        let home = g.player.pos
        g.paused = false; g.menu = nil
        g.player.flying = true
        let n0 = w.ships.list.count
        w.ships.spawnCapital("capfrigate", home: IVec3(Int(floor(home.x)), 0, Int(floor(home.z)) + 60), yaw: 0, region: nil, sync: true)
        guard let s = w.ships.list.dropFirst(n0).first(where: { $0.role == "capfrigate" }) else {
            check(false, "shipchart: the frigate spawns"); return
        }
        g.player.pos = s.pos + V3(0, 30, 0)
        _ = w.loadSync(center: s.pos, radius: 6)
        g.tick(1.0 / 72)
        var chest: IVec3?, chart: IVec3?
        let gr = s.grid
        for y in 0..<gr.sy { for z in 0..<gr.sz { for x in 0..<gr.sx {
            let key = Blocks.key(Blocks.groupBase[Int(gr.get(x, y, z))])
            if chest == nil && key.hasSuffix("chest") { chest = IVec3(x, y, z) }
            if chart == nil && Game.chartKeys.contains(key) { chart = IVec3(x, y, z) }
        } } }
        guard let cc = chest, let tc = chart else { check(false, "shipchart: the frigate has a chest (\(chest != nil)) and a chart table (\(chart != nil))"); return }
        var gun = ItemStack(Items.id("gun_rifle"), 1); gun.tag = 10
        g.inventory.held = gun
        // Stand 2 blocks off the cell on an open side, aim at its middle and press use.
        func use(_ c: IVec3) -> Bool {
            let mid = s.toWorld(V3(Float(c.x), Float(c.y), Float(c.z)) + 0.5)
            for k in 0..<4 {
                let off = [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)][k]
                let a = c + off, b = a + off
                guard gr.get(a.x, a.y, a.z) == AIR && gr.get(b.x, b.y, b.z) == AIR && gr.get(b.x, b.y + 1, b.z) == AIR else { continue }
                g.player.pos = s.toWorld(V3(Float(b.x) + 0.5, Float(b.y), Float(b.z) + 0.5))
                let eye = g.player.eye
                g.vrAim = (eye, simd_normalize(mid - eye))
                g.menu = nil
                let aimed = g.shipDoorAimed()
                let used = aimed && g.shipInteract(breakHeld: false, breakNow: false, useNow: true, sneak: false, dt: 1.0 / 72)
                g.vrAim = nil
                return used
            }
            return false
        }
        let opened = use(cc) && g.menu != nil
        check(opened, "shipchart: with a rifle in hand the use press opens the frigate's chest (menu \(g.menu.map { String(describing: type(of: $0)) } ?? "none"))")
        g.menu = nil
        var toast = ""
        let t0 = g.onToast
        g.onToast = { toast = $0 }
        let read = use(tc)
        g.onToast = t0
        print("shipchart: \(toast)")
        check(read && toast.contains("The helm") && toast.contains("engine room"), "shipchart: the chart table aboard reads out where the helm and the engine room are")
        // At her helm (P472 19:47, "the little guns on the frigate are not firing"): the press that charges the main gun
        // fires the point-defence guns too, and so does the next one while the main gun reloads.
        g.inventory.held = .empty
        guard let stand = g.helmStand(s), let st = w.ships.capState[s.id] else { check(false, "shipchart: the frigate has a helm"); return }
        g.player.pos = s.toWorld(stand)
        g.takeCommand(s)
        for _ in 0..<72 { g.tick(1.0 / 72) }
        st.mainGunCD = 0
        let pds = w.ships.turrets(of: s)
        func press() -> Int {
            let n = w.ships.shells.filter { $0.owner == s.id && $0.kind != 3 }.count
            _ = g.shipInteract(breakHeld: true, breakNow: true, useNow: false, sneak: false, dt: 1.0 / 72)
            return w.ships.shells.filter { $0.owner == s.id && $0.kind != 3 }.count - n
        }
        let first = press()
        let charging = st.gunCharge >= 0
        for _ in 0..<(3 * 72) { g.tick(1.0 / 72) }
        let second = press()
        check(w.ships.pilot === s && charging && first > 0 && second > 0,
              "shipchart: at the helm of \(pds.count) point-defence mounts the first press charges the main gun (\(charging)) and fires \(first) small guns, the next (main gun reloading) \(second)")
    }
}
