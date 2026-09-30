import Metal

let CS = 16          // chunk width/depth
let CH = 384         // world height (internal y 0...383 = displayed y -64...319)
let YOFF = 64        // displayed y = internal y - YOFF
let CSQ = CS * CS
let NSEC = CH / 16   // vertical 16^3 sections per chunk
let SEA = 62 + YOFF

struct ChunkKey: Hashable {
    let x: Int
    let z: Int
}

// One 16x16x16 slice of a chunk's mesh.
final class Section {
    var opaqueBuf: MTLBuffer?
    var opaqueQuads = 0
    var transBuf: MTLBuffer?
    var transQuads = 0
    var version = 0          // bumped when the section (or light around it) changes
    var meshedVersion = -1
    var vis: UInt64 = ~0         // face connectivity (cave culling)
    var needsMesh: Bool { meshedVersion != version }
    var empty: Bool { opaqueQuads == 0 && transQuads == 0 }
}

final class Chunk {
    let cx: Int
    let cz: Int
    var blocks: [BlockID]          // index = x + z*16 + y*256
    var light: [UInt8]             // sky << 4 | block, filled in by the mesher per section
    var lightValid = [Bool](repeating: false, count: NSEC)
    var height: [Int16]            // highest sky-stopping block per column (-1 = none)
    var tint: [UInt32]             // 256 grass, 256 foliage, 256 water colours (RGBA8)
    var tintBuf: MTLBuffer?
    var sections: [Section]
    var modified = false
    var meshInFlight = false
    var meshedOnce = false
    var drawnMark: UInt32 = 0
    var lod = 0                    // 0 full detail, 1 far (flat light, merged faces, no small decorations)

    init(cx: Int, cz: Int, blocks: [BlockID], height: [Int16], tint: [UInt32]) {
        self.cx = cx
        self.cz = cz
        self.blocks = blocks
        self.height = height
        self.tint = tint
        light = [UInt8](repeating: 0, count: CSQ * CH)
        sections = (0..<NSEC).map { _ in Section() }
    }

    @inline(__always) static func index(_ x: Int, _ y: Int, _ z: Int) -> Int { x + z * CS + y * CSQ }
    var needsMesh: Bool { sections.contains { $0.needsMesh } }

    static func computeHeights(_ b: [BlockID]) -> [Int16] {
        let skyT = Blocks.sky
        var h = [Int16](repeating: -1, count: CSQ)
        for c in 0..<CSQ {
            var y = CH - 1
            while y >= 0 && !skyT[Int(b[c + y * CSQ])] { y -= 1 }
            h[c] = Int16(y)
        }
        return h
    }

    func recomputeHeight(_ x: Int, _ z: Int) {
        let skyT = Blocks.sky
        let c = x + z * CS
        var y = CH - 1
        while y >= 0 && !skyT[Int(blocks[c + y * CSQ])] { y -= 1 }
        height[c] = Int16(y)
    }
}
