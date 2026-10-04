import Foundation
import simd
import Metal
import CVulkan

// Ships, airships and vehicles (Sources/Ships*.swift) on the Quest: the Mac ShipRenderer's draw logic over the shared
// ShipMesh sections — hulls with their pose, wheels rolled about their axles, cannon barrels raised to the guns'
// elevation, propellers spinning, translucent parts after the water, the target outline, and the depth-only mask that
// keeps the sea surface out of hulls.
final class ShipDraw {
    let scene: SceneRenderer
    private var propMeshes: [BlockID: ShipMesh.Sec] = [:]
    private var cannonParts: [BlockID: (BlockID, BlockID)] = [:]
    private var maskScratch: [SimpleVert] = []
    private(set) var drawCalls = 0

    init(scene: SceneRenderer) { self.scene = scene }

    private func model(_ s: Ship, eye: V3) -> float4x4 {
        translationMatrix(s.pos - eye) * float4x4(s.rot) * translationMatrix(-s.com)
    }

    private func secs(_ built: [(Int, SectionMesh, V3)]) -> [ShipMesh.Sec] {
        var out: [ShipMesh.Sec] = []
        for (_, m, origin) in built where !m.opaque.isEmpty {
            var sec = ShipMesh.Sec(origin: origin)
            sec.opaque = m.opaque.withUnsafeBytes { MeshArena.shared.alloc(scene.device, $0) }
            sec.opaqueQuads = m.opaque.count / 8
            sec.solidQuads = m.solidQuads
            out.append(sec)
        }
        return out
    }

    private func wheelMeshes(_ s: Ship) -> [[ShipMesh.Sec]] {
        if s.mesh.wheelGen != s.wheelGen {
            s.mesh.wheelSecs = s.wheelParts.map { p in
                secs(ShipMesh.build(sx: p.size.x, sy: p.size.y, sz: p.size.z, blocks: p.blocks, only: nil, spinning: false))
            }
            s.mesh.wheelGen = s.wheelGen
        }
        return s.mesh.wheelSecs
    }

    private func cannonHalves(_ b: BlockID) -> (BlockID, BlockID) {
        if let p = cannonParts[b] { return p }
        let name = Blocks.key(b)
        let suffix = name.hasPrefix("ship_cannon") ? String(name.dropFirst("ship_cannon".count)) : ""
        let p = (Blocks.id("ship_cannon_mount" + suffix), Blocks.id("ship_cannon_barrel" + suffix))
        cannonParts[b] = p
        return p
    }

    private func propMesh(_ b: BlockID) -> ShipMesh.Sec? {
        if let m = propMeshes[b] { return m }
        guard let sec = secs(ShipMesh.build(sx: 1, sy: 1, sz: 1, blocks: [b], only: nil, spinning: false)).first else { return nil }
        propMeshes[b] = sec
        return sec
    }

    static func sectionVisible(_ s: Ship, _ sec: ShipMesh.Sec, _ frustum: Frustum) -> Bool {
        let c = s.toWorld(sec.origin + V3(8, 8, 8))
        let r = V3(repeating: 14)
        return frustum.visible(min: c - r, max: c + r)
    }

    // Capital ships keep a long haze instead of the terrain's fog wall (seen from far away).
    private func fog(_ s: Ship, _ u: FrameUniforms) -> V4 {
        let capital = s.root.kinematic && u.params.w < 0.5 && u.params.x > 40
        return capital ? V4(max(u.fogColor.w, 240), max(u.params.x, 950), 0, 0) : V4(0, 0, 0, 0)
    }

    private func drawSec(_ sl: SceneRenderer.Slot, _ sec: ShipMesh.Sec, _ m: float4x4, _ sky: Float, _ fog: V4, _ pass: Int) {
        guard let buf = sec.opaque, sec.opaqueQuads > 0 else { return }
        let total = min(sec.opaqueQuads, SceneRenderer.maxQuads), solid = min(sec.solidQuads, total)
        let first = pass == 0 ? 0 : solid, count = pass == 0 ? solid : total - solid
        if count <= 0 { return }
        scene.pushShip(sl, model: m, origin: V4(sec.origin, sky), fog: fog)
        scene.drawQuads(sl, buf, first: first, count: count)
        drawCalls += 1
    }

    func drawOpaque(_ sl: SceneRenderer.Slot, ships: ShipManager, eye: V3, u: FrameUniforms, frustum: Frustum) {
        drawCalls = 0
        if ships.isEmpty && ships.ghosts.isEmpty { return }
        func draw(_ s: Ship, _ pass: Int) {
            if s.mesh.released || !frustum.visible(min: s.worldMin, max: s.worldMax) { return }
            let f = fog(s, u)
            let m = model(s, eye: eye)
            let perSection = s.mesh.sections.count > 48
            for sec in s.mesh.sections.values {
                if perSection && !ShipDraw.sectionVisible(s, sec, frustum) { continue }
                drawSec(sl, sec, m, s.skyLight, f, pass)
            }
            if !s.wheelParts.isEmpty {
                let meshes = wheelMeshes(s)
                let axle = simd_normalize(simd_cross(s.fwd, V3(0, 1, 0)) + V3(1e-6, 0, 0))
                for (i, p) in s.wheelParts.enumerated() where i < meshes.count {
                    let roll = float4x4(simd_quatf(angle: -s.rollDist / max(0.5, p.radius), axis: axle))
                    let lo = V3(Float(p.lo.x), Float(p.lo.y), Float(p.lo.z))
                    let wmodel: float4x4 = m * translationMatrix(p.center) * roll * translationMatrix(lo - p.center)
                    for sec in meshes[i] { drawSec(sl, sec, wmodel, s.skyLight, f, pass) }
                }
            }
            for (c, d) in s.cannons {
                let (mountB, barrelB) = cannonHalves(s.grid.get(Int(floor(c.x)), Int(floor(c.y)), Int(floor(c.z))))
                let raise = float4x4(simd_quatf(angle: s.gunPitch, axis: simd_normalize(simd_cross(d, V3(0, 1, 0)))))
                let half = V3(0.5, 0.5, 0.5)
                let mountM: float4x4 = m * translationMatrix(c - half)
                let barrelM: float4x4 = m * translationMatrix(c) * raise * translationMatrix(-half)
                if let pm = propMesh(mountB) { drawSec(sl, pm, mountM, s.skyLight, f, pass) }
                if let pm = propMesh(barrelB) { drawSec(sl, pm, barrelM, s.skyLight, f, pass) }
            }
            for (c, d) in s.props {
                let b = s.grid.get(Int(floor(c.x)), Int(floor(c.y)), Int(floor(c.z)))
                guard let pm = propMesh(b) else { continue }
                let spin = float4x4(simd_quatf(angle: s.propSpin, axis: d))
                let pmodel: float4x4 = m * translationMatrix(c) * spin * translationMatrix(V3(-0.5, -0.5, -0.5))
                drawSec(sl, pm, pmodel, s.skyLight, f, pass)
            }
        }
        for pass in 0..<2 {
            vkCmdBindPipeline(sl.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, scene.pipe(pass == 0 ? "shipSolid" : "shipCut"))
            for s in ships.list { draw(s, pass) }
            for g in ships.ghosts { draw(g.0, pass) }
        }
    }

    // Target outline on a ship and the depth-only water mask over each hull's enclosed air (before the world's water).
    func drawBeforeWater(_ sl: SceneRenderer.Slot, ships: ShipManager, world: World, eye: V3, frustum: Frustum) {
        if ships.isEmpty { return }
        if let t = ships.target {
            let s = t.ship
            let b = s.grid.get(t.cell.x, t.cell.y, t.cell.z)
            var verts: [SimpleVert] = []
            let o = V3(Float(t.cell.x), Float(t.cell.y), Float(t.cell.z))
            let edges = [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7]
            let col = V4(0, 0, 0, 0.7)
            for (bmn, bmx) in world.selectionBoxes(b) {
                let a = o + bmn - V3(repeating: 0.003), c = o + bmx + V3(repeating: 0.003)
                let cs = [V3(a.x, a.y, a.z), V3(c.x, a.y, a.z), V3(c.x, a.y, c.z), V3(a.x, a.y, c.z),
                          V3(a.x, c.y, a.z), V3(c.x, c.y, a.z), V3(c.x, c.y, c.z), V3(a.x, c.y, c.z)]
                for i in edges { verts.append(SimpleVert(pos: V4(s.toWorld(cs[i]) - eye, 1), color: col)) }
            }
            if let off = scene.push(sl, verts) { scene.drawScratch(sl, "lines", offset: off, count: verts.count) }
        }
        maskScratch.removeAll(keepingCapacity: true)
        var rd = ShipBlockReader(world)
        for s in ships.list where !s.mesh.released && frustum.visible(min: s.worldMin, max: s.worldMax) {
            guard let top = rd.waterTop(s.pos) ?? rd.waterTop(s.pos - V3(0, 2, 0)) else { continue }
            let plane = top + (eye.y > top ? 0.01 : -0.01)
            let r = simd_float3x3(s.rot)
            let ry = V3(r[0][1], r[1][1], r[2][1])
            if abs(ry.y) < 0.3 { continue }
            let g = s.grid
            func ly(_ x: Float, _ z: Float) -> Float {
                s.com.y + (plane - s.pos.y - ry.x * (x - s.com.x) - ry.z * (z - s.com.z)) / ry.y
            }
            for z in 0..<g.sz {
                for x in 0..<g.sx {
                    let yc = ly(Float(x) + 0.5, Float(z) + 0.5)
                    if !s.dry(x, Int(floor(yc)), z) { continue }
                    let fx = Float(x), fz = Float(z)
                    let w0 = V4(s.toWorld(V3(fx, ly(fx, fz), fz)) - eye, 1)
                    let w1 = V4(s.toWorld(V3(fx + 1, ly(fx + 1, fz), fz)) - eye, 1)
                    let w2 = V4(s.toWorld(V3(fx + 1, ly(fx + 1, fz + 1), fz + 1)) - eye, 1)
                    let w3 = V4(s.toWorld(V3(fx, ly(fx, fz + 1), fz + 1)) - eye, 1)
                    let none = V4(0, 0, 0, 0)
                    for w in [w0, w1, w2, w0, w2, w3] { maskScratch.append(SimpleVert(pos: w, color: none)) }
                }
            }
        }
        if let off = scene.push(sl, maskScratch) { scene.drawScratch(sl, "shipMask", offset: off, count: maskScratch.count) }
    }

    func drawTranslucent(_ sl: SceneRenderer.Slot, ships: ShipManager, eye: V3, u: FrameUniforms, frustum: Frustum) {
        if ships.isEmpty { return }
        var bound = false
        for s in ships.list where frustum.visible(min: s.worldMin, max: s.worldMax) {
            let m = model(s, eye: eye)
            let f = fog(s, u)
            let perSection = s.mesh.sections.count > 48
            for sec in s.mesh.sections.values {
                guard let buf = sec.trans, sec.transQuads > 0 else { continue }
                if perSection && !ShipDraw.sectionVisible(s, sec, frustum) { continue }
                if !bound { vkCmdBindPipeline(sl.cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, scene.pipe("shipTrans")); bound = true }
                scene.pushShip(sl, model: m, origin: V4(sec.origin, s.skyLight), fog: f)
                scene.drawQuads(sl, buf, first: 0, count: min(sec.transQuads, SceneRenderer.maxQuads))
                drawCalls += 1
            }
        }
    }
}
