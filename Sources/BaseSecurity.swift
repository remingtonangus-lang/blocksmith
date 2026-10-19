import Foundation
import simd

// D35: keycards, locked doors and security cameras in Greywall bases.
//   locked doors  the keep's vault, comms room and (a command fortress) the stair door to the command level are
//                 locked bulkheads: they only open with a Greywall keycard in your pack (not used up), or once the
//                 base is yours. Breaking through the wall still works: it's slow, and loud.
//   keycards      every Greywall officer carries one (dropped on his death), and the command chests hold one.
//   cameras       security cameras watch the keep's entrance and its corridor (bases first generated with them):
//                 one that sees you (14 blocks in its cone, 7 when you sneak, a clear line of sight) sounds the base's
//                 alarm as a gunshot would. A round through one breaks it, like a pane of glass.
enum BaseSecurity {
    static let card = "greywall_keycard"
    static let camera = "security_camera"
    static var cardTold = false
    static var spotted = 0                                 // (harness)
    static var lastSpot: Double = -100

    // The base and whether p is one of its locked doors (either half).
    static func lockedDoor(_ g: Game, _ p: IVec3) -> String? {
        guard g.dim.dim == .overworld, let sc = g.world.gen.structures,
              let s = sc.nearestIfReady(Greywall.kind, x: p.x, z: p.z) else { return nil }
        let (cx, cz) = Greywall.centre(s)
        let t = Greywall.Tier.of(s), S = Greywall.yardY(s)
        var spots: [IVec3] = Greywall.rooms(t).filter { $0.use == "vault" || $0.use == "comms" }.map { IVec3(cx + $0.door.0, S + 1, cz + $0.door.1) }
        if t.rawValue >= 3 { spots.append(IVec3(cx, S - 5, cz + t.keepC - 3)) }
        guard spots.contains(where: { $0.x == p.x && $0.z == p.z && (p.y == $0.y || p.y == $0.y + 1) }) else { return nil }
        return "greywall:\(cx),\(cz)"
    }

    // Game.openBlock: true when the door stays shut.
    static func refuse(_ g: Game, _ p: IVec3) -> Bool {
        guard Blocks.key(Blocks.groupBase[Int(g.world.materialAt(p.x, p.y, p.z))]) == "bulkhead_door", g.survival,
              let key = lockedDoor(g, p), !g.bases.greywall.taken.contains(key) else { return false }
        if Items.has(card) && g.inventory.main.countOf(Items.id(card)) > 0 {
            if !cardTold { cardTold = true; g.onToast?("Keycard accepted") }
            return false
        }
        g.sfx(.villagerNo, 0.4, at: V3(Float(p.x) + 0.5, Float(p.y) + 1, Float(p.z) + 0.5))
        g.onToast?("Locked")
        return true
    }

    // Before greywallAlarmTick, once a second: cameras that see a player raise a noise there.
    static func tick(_ g: Game, _ b: BaseWatch) {
        guard g.survival, Blocks.has(camera) else { return }
        let cam = Blocks.groupBase[Int(Blocks.id(camera))]
        let looks = [V3(0, 0, -1), V3(0, 0, 1), V3(-1, 0, 0), V3(1, 0, 0)]
        let eye = g.player.eye
        let range: Float = g.player.sneaking ? 7 : 14
        for (key, site) in b.greywall.sites where !b.greywall.taken.contains(key) && !site.on {
            for c in site.cameras where g.world.isLoaded(c.x, c.z) {
                let id = g.world.block(c.x, c.y, c.z)
                guard Blocks.groupBase[Int(id)] == cam else { continue }
                let o = V3(Float(c.x) + 0.5, Float(c.y) + 0.4, Float(c.z) + 0.5)
                let d = eye - o
                let dist = simd_length(d)
                guard dist < range, dist > 0.5, simd_dot(d / dist, looks[Int(id - cam) & 3]) > 0.35,
                      g.world.canSee(o + looks[Int(id - cam) & 3] * 0.45, eye) else { continue }
                if b.noises.count < 48 { b.noises.append(BaseNoise(pos: g.player.pos, kind: .gunshot, power: 0.6, hostile: true)) }
                spotted += 1
                if g.clock - lastSpot > 20 { lastSpot = g.clock; g.onToast?("A security camera has spotted you!") }
                g.sfx(.click, 1, at: o)
                break
            }
        }
    }
}

extension ItemRegistry {
    func registerKeycard() {
        guard !has(BaseSecurity.card) else { return }
        var d = ItemDef(BaseSecurity.card, "Greywall Keycard")
        d.sprite = Sprite(mask: "paper", base: 0x5E6670, extras: [:])
        d.maxStack = 1
        add(d)
    }
}

extension BlockRegistry {
    func registerSecurityCamera() {
        guard !has(BaseSecurity.camera) else { return }
        var d = BlockDef(BaseSecurity.camera, "Security Camera")
        d.tex = ["security_camera_side"]; d.render = .model; d.layer = .cutout; d.opaque = false; d.skyStop = false
        d.collide = false; d.noCollideBoxes = true; d.hardness = 1.5; d.sound = .metal
        // A housing out from the wall (the wall behind it: +z, -z, +x, -x), the lens toward the room.
        let boxes: [[Box]] = [[Box(6, 9, 6, 10, 13, 16)], [Box(6, 9, 0, 10, 13, 10)], [Box(6, 9, 6, 16, 13, 10)], [Box(0, 9, 6, 10, 13, 10)]]
        addFacing(d, front: "security_camera_side", boxesFor: { k in boxes[k] })
    }
}

extension TextureGen {
    static func securityCameraPainters(_ p: inout [String: Painter]) {
        p["security_camera_side"] = { x, y in
            let cx = Float(x) - 7.5, cy = Float(y) - 7.5
            if cx * cx + cy * cy < 5 { return hex(0x101418) }
            if cx * cx + cy * cy < 9 { return hex(0x3A5A78) }
            if x == 12 && y == 3 { return hex(0xE02A20) }                       // the tally light
            return hex(0xB8BCC2, 0.9 + 0.1 * r(x, y, 7711))
        }
    }
}
