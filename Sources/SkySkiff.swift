import Foundation
import simd

// The Sky Skiff (backlog A4): a ready-made flyer for players who don't want to build one. The kit is crafted from the
// ship parts (five lift balloons, a helm, an engine, two propellers) and used on open ground: a small airship inflates
// in front of the player, hovering a step off the ground: a plank deck with a rail, a mast under a rounded envelope,
// the helm and engine aft, three propellers at the stern. It is an ordinary vessel from then on (Ships.swift): take
// the helm to fly it (climb and sink on the balloons, propellers for way), build on it, break it up, and it saves with
// the world where it was left. Its 68 balloons lift 136 t, about 90 t more than it weighs: load the deck with iron and it can't hold
// height (weight matters, ShipPhysics).
enum SkySkiff {
    static let key = "sky_skiff_kit"
    static let name = "Sky Skiff"
    static let reach: Float = 9          // the deck's centre this far in front of the player
    static let room = 7                  // clear sky needed round that centre (blocks)

    // Bow -Z (the helm faces south), like every vessel blueprint.
    static func blueprint() -> Blueprint {
        let b = Blueprint()
        let planks = "spruce_planks", rail = "spruce_fence", post = "spruce_log"
        b.box(-2, 2, 0, 0, -4, 4, planks)
        for z in -4...4 { for x in -2...2 where abs(x) == 2 || abs(z) == 4 { b.set(x, 1, z, rail) } }
        for (x, z) in [(-2, -4), (2, -4), (-2, 4), (2, 4)] { b.box(x, x, 1, 3, z, z, post) }
        b.box(0, 0, 1, 4, -1, -1, post)                                   // the mast, up into the envelope
        // The envelope: an ellipsoid of lift balloons over the deck.
        for y in 4...8 { for z in -6...5 { for x in -3...3 {
            let ex = Float(x) / 2.2, ey = (Float(y) - 6) / 1.6, ez = (Float(z) + 0.5) / 4.4
            if ex * ex + ey * ey + ez * ez <= 1 { b.set(x, y, z, "ship_balloon") }
        } } }
        b.set(0, 1, 2, "ship_helm[south]")
        b.set(0, 1, 3, "ship_engine")
        for x in [-2, 0, 2] { b.set(x, 0, 5, "ship_propeller[south]") }
        b.clear(0, 1, 4)                                                  // a gap in the stern rail behind the engine
        return b
    }

    // Right-click with the kit: inflate a skiff in front of the player if there's open sky there.
    static func use(_ g: Game) -> Bool {
        let held = g.inventory.main[g.inventory.selected]
        guard !held.isEmpty, Items.has(SkySkiff.key), held.item == Items.id(SkySkiff.key) else { return false }
        guard let s = SkySkiff.deploy(g) else { return true }
        if g.survival {
            g.inventory.main[g.inventory.selected].count -= 1
            if g.inventory.main[g.inventory.selected].count <= 0 { g.inventory.main[g.inventory.selected] = .empty }
        }
        g.sfx(.engineStart, 0.8, at: s.pos)
        g.onToast?("The Sky Skiff inflates")
        return true
    }

    // Builds the skiff `reach` blocks in front of the player, bow the way they look (to the nearest quarter turn), its
    // keel a step over the highest ground under it. Nil (and a toast) when there's no room: under a roof, in a cave,
    // trees or walls in the way, or the ground not loaded.
    @discardableResult
    static func deploy(_ g: Game) -> Ship? {
        let w = g.world
        let quarter = (g.player.yaw / (.pi / 2)).rounded() * (.pi / 2)
        let fwd = V3(-sinf(quarter), 0, -cosf(quarter))
        let c = g.player.pos + fwd * reach
        let cx = Int(floor(c.x)), cz = Int(floor(c.z))
        var ground = Int.min
        for dz in -room...room { for dx in -room...room where dx * dx + dz * dz <= room * room {
            guard w.isLoaded(cx + dx, cz + dz) else { g.onToast?("No room for a Sky Skiff here"); return nil }
            ground = max(ground, w.topY(cx + dx, cz + dz))
        } }
        // The highest ground in reach is the keel's floor; anything over head height there is a roof, a tree or a hillside
        // (the skiff would come out on top of it), not open sky.
        guard ground <= Int(floor(g.player.pos.y)) + 3 else {
            g.onToast?("No open sky here")
            return nil
        }
        let s = w.ships.spawn(blueprint(), at: V3(c.x, Float(ground) + 6, c.z), yaw: quarter, name: name, role: "")
        s.role = nil
        s.pos.y += Float(ground) + 1.2 - s.toWorld(V3(0, s.localMin.y, 0)).y
        s.prevPos = s.pos
        s.updateBounds()
        s.hoverY = s.pos.y
        s.initialBlocks = s.blockCount
        return s
    }
}

extension Game {
    func skySkiffUse() -> Bool { SkySkiff.use(self) }
}

extension ItemRegistry {
    func registerSkySkiff() {
        guard !has(SkySkiff.key) else { return }
        var d = ItemDef(SkySkiff.key, "Sky Skiff Kit")
        d.sprite = Sprite(mask: "airship", base: 0x6A4A2A, extras: ["c": 0xE8DCC0, "d": 0xB89A6A, "e": 0x5A6066])
        d.maxStack = 1
        add(d)
    }
}
