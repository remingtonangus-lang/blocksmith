import Metal

let CS = 16          // chunk width/depth
let CH = 192         // world height
let CSQ = CS * CS
let SEA = 62

struct ChunkKey: Hashable {
    let x: Int
    let z: Int
}

final class Chunk {
    let cx: Int
    let cz: Int
    var blocks: [UInt8]           // index = x + z*16 + y*256
    var modified = false
    var meshVersion = 0
    var meshedVersion = -1
    var meshInFlight = false
    var opaqueBuf: MTLBuffer?
    var opaqueQuads = 0
    var waterBuf: MTLBuffer?
    var waterQuads = 0
    var minY: Float = 0
    var maxY: Float = 0

    init(cx: Int, cz: Int, blocks: [UInt8]) {
        self.cx = cx
        self.cz = cz
        self.blocks = blocks
    }

    @inline(__always) static func index(_ x: Int, _ y: Int, _ z: Int) -> Int { x + z * CS + y * CSQ }
    var needsMesh: Bool { meshedVersion != meshVersion }
}
