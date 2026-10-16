import Foundation
import simd

// Emberdeep portals: obsidian frames (interior 2x3 up to 21x21) lit with flint and steel, travel after
// standing inside (4 s in survival), coordinates scaled 1:8, the nearest existing portal is reused
// (128 blocks in the Surface, 16 in the Emberdeep), otherwise a new one is built.
extension Game {
    // Tries to light a portal whose interior contains `p`. Returns true on success.
    func tryLightPortal(at p: IVec3) -> Bool {
        let w = world
        for axisX in [true, false] {
            let dx = axisX ? 1 : 0, dz = axisX ? 0 : 1
            func isAirish(_ q: IVec3) -> Bool { let b = w.block(q.x, q.y, q.z); return b == AIR || b == FIRE }
            func isObs(_ q: IVec3) -> Bool { w.block(q.x, q.y, q.z) == OBSIDIAN }
            // Bottom of the interior.
            var b = p
            var n = 0
            while isAirish(IVec3(b.x, b.y - 1, b.z)) && n < 21 { b.y -= 1; n += 1 }
            guard isObs(IVec3(b.x, b.y - 1, b.z)) else { continue }
            // Left edge.
            n = 0
            while isAirish(IVec3(b.x - dx, b.y, b.z - dz)) && n < 21 { b.x -= dx; b.z -= dz; n += 1 }
            guard isObs(IVec3(b.x - dx, b.y, b.z - dz)) else { continue }
            var width = 0
            while isAirish(IVec3(b.x + dx * width, b.y, b.z + dz * width)) && width < 22 { width += 1 }
            var height = 0
            while isAirish(IVec3(b.x, b.y + height, b.z)) && height < 22 { height += 1 }
            guard width >= 2 && width <= 21 && height >= 3 && height <= 21 else { continue }
            var ok = true
            for i in 0..<width where ok {
                ok = isObs(IVec3(b.x + dx * i, b.y - 1, b.z + dz * i)) && isObs(IVec3(b.x + dx * i, b.y + height, b.z + dz * i))
                for j in 0..<height where ok { ok = isAirish(IVec3(b.x + dx * i, b.y + j, b.z + dz * i)) }
            }
            for j in 0..<height where ok {
                ok = isObs(IVec3(b.x - dx, b.y + j, b.z - dz)) && isObs(IVec3(b.x + dx * width, b.y + j, b.z + dz * width))
            }
            guard ok else { continue }
            let portal = axisX ? PORTAL_X : PORTAL_Z
            for i in 0..<width { for j in 0..<height { w.setBlockAsync(b.x + dx * i, b.y + j, b.z + dz * i, portal) } }
            w.setBlock(b.x, b.y, b.z, portal)
            w.portals.insert(b)
            sfx(.portalTrigger, 1, at: V3(Float(b.x), Float(b.y), Float(b.z)))
            return true
        }
        return false
    }

    // Removes portal blocks connected to `p` (frame broken).
    func breakPortal(near p: IVec3) {
        let w = world
        var stack = [p]
        var seen = Set<IVec3>()
        var n = 0
        while let q = stack.popLast(), n < 2000 {
            for d in [IVec3(1, 0, 0), IVec3(-1, 0, 0), IVec3(0, 1, 0), IVec3(0, -1, 0), IVec3(0, 0, 1), IVec3(0, 0, -1)] {
                let r = q + d
                if seen.contains(r) { continue }
                seen.insert(r)
                let b = w.block(r.x, r.y, r.z)
                if b == PORTAL_X || b == PORTAL_Z {
                    w.setBlockAsync(r.x, r.y, r.z, AIR)
                    w.portals.remove(r)
                    stack.append(r)
                    n += 1
                }
            }
        }
    }

    func isInPortal() -> Bool {
        let p = player.pos
        for y in [p.y + 0.2, p.y + 1.2] {
            let b = world.block(Int(floor(p.x)), Int(floor(y)), Int(floor(p.z)))
            if b == PORTAL_X || b == PORTAL_Z { return true }
        }
        return false
    }

    // Called every frame: counts time in a portal and travels.
    func portalTick(_ dt: Float) {
        if portalCooldown > 0 { portalCooldown -= dt }
        guard isInPortal() else { portalTime = 0; return }
        if portalCooldown > 0 { return }
        portalTime += dt
        if portalTime >= (survival ? 4 : 0.2) {
            portalTime = 0
            portalCooldown = 3
            travelThroughPortal()
        }
    }

    func travelThroughPortal() {
        let from = dim.dim
        guard from != .end && from != .deep else { return }   // gates lit in the Deep lead nowhere
        let to: Dim = from == .overworld ? .nether : .overworld
        let scale: Float = to == .nether ? 1.0 / 8 : 8
        var target = V3(floor(player.pos.x * scale) + 0.5, 0, floor(player.pos.z * scale) + 0.5)
        target.x = simd_clamp(target.x, -29_999_000, 29_999_000)
        target.z = simd_clamp(target.z, -29_999_000, 29_999_000)
        // Load the destination around the target first.
        changeDimension(to: to, at: V3(target.x, Float(YOFF + 70), target.z))
        let w = world
        let range: Float = to == .nether ? 16 : 128
        var best: IVec3?
        var bestD = Float.greatestFiniteMagnitude
        for p in w.portals {
            let d = simd_length(V2(Float(p.x) - target.x, Float(p.z) - target.z))
            if d <= range && d < bestD {
                let b = w.block(p.x, p.y, p.z)
                if b == PORTAL_X || b == PORTAL_Z || !w.isLoaded(p.x, p.z) { best = p; bestD = d }
            }
        }
        if best == nil { best = buildPortal(near: IVec3(Int(floor(target.x)), 0, Int(floor(target.z)))) }
        if let b = best {
            _ = w.loadSync(center: V3(Float(b.x), Float(b.y), Float(b.z)), radius: 2)
            player.pos = V3(Float(b.x) + 0.5, Float(b.y), Float(b.z) + 0.5)
            player.vel = .zero
            player.airPeak = player.pos.y
        }
        sfx(.portalTravel, 0.8)
    }

    // Builds a 4x5 obsidian frame with a lit 2x3 portal near `c`; returns the interior bottom-left cell.
    func buildPortal(near c: IVec3) -> IVec3 {
        let w = world
        let nether = dim.dim == .nether
        let minY = nether ? YOFF + 32 : YOFF + 1, maxY = nether ? YOFF + 118 : CH - 10
        // Look for a spot with solid ground and 4x4x3 of air above.
        var found: IVec3?
        search: for r in 0...16 {
            for dz in -r...r {
                for dx in -r...r where abs(dx) == r || abs(dz) == r {
                    let x = c.x + dx, z = c.z + dz
                    var y = nether ? maxY : min(maxY, w.topY(x, z) + 1)
                    while y > minY {
                        if Blocks.opaque[Int(w.block(x, y - 1, z))] && !Blocks.isLiquid(w.block(x, y - 1, z)) {
                            var ok = true
                            for ix in -1...2 where ok { for iy in 0..<4 where ok { for iz in -1...1 where ok {
                                let b = w.block(x + ix, y + iy, z + iz)
                                ok = b == AIR || Blocks.replaceable[Int(b)] && !Blocks.isLiquid(b)
                            } } }
                            if ok { found = IVec3(x, y, z); break search }
                        }
                        y -= 1
                    }
                }
            }
        }
        let base = found ?? IVec3(c.x, nether ? YOFF + 70 : max(w.topY(c.x, c.z) + 1, SEA + 1), c.z)
        // Frame (x-axis): interior x 0...1, y 0...2.
        for ix in -1...2 {
            for iy in -1...3 {
                for iz in -1...1 {
                    let edge = ix == -1 || ix == 2 || iy == -1 || iy == 3
                    let p = IVec3(base.x + ix, base.y + iy, base.z + iz)
                    if iz == 0 {
                        w.setBlockAsync(p.x, p.y, p.z, edge ? OBSIDIAN : PORTAL_X)
                    } else if iy == -1 {
                        if !Blocks.opaque[Int(w.block(p.x, p.y, p.z))] { w.setBlockAsync(p.x, p.y, p.z, OBSIDIAN) }  // ledge
                    } else if iy >= 0 && iy < 3 {
                        w.setBlockAsync(p.x, p.y, p.z, AIR)
                    }
                }
            }
        }
        w.setBlock(base.x, base.y, base.z, PORTAL_X)
        w.portals.insert(base)
        return base
    }
}
