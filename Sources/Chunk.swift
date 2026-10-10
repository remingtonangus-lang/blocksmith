import Foundation
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

// Counts section invalidations (main thread): World.update skips its scheduling scan while nothing changed.
enum MeshEpoch {
    static var value = 0
}

// One 16x16x16 slice of a chunk's mesh.
final class Section {
    var opaqueBuf: MeshSlice?
    var opaqueQuads = 0
    var solidQuads = 0          // leading opaque quads drawn without alpha test
    var transBuf: MeshSlice?
    var transQuads = 0
    var version = 0 {           // bumped when the section (or light around it) changes
        didSet {
            MeshEpoch.value &+= 1
            guard let o = owner else { return }
            o.dirty = true
            o.noteStale(was: oldValue != meshedVersion, now: version != meshedVersion)
        }
    }
    weak var owner: Chunk?      // marked dirty with each bump (World.update re-checks only dirty chunks)
    var meshedVersion = -1 { didSet { owner?.noteStale(was: oldValue != version, now: meshedVersion != version) } }
    var vis: UInt64 = ~0         // face connectivity (cave culling)
    var leafy = true             // its mesh has faces between leaf blocks (SectionMesh.leafy)
    var needsMesh: Bool { meshedVersion != version }
    var empty: Bool { opaqueQuads == 0 && transQuads == 0 }
}

// A chunk's blocks (index x + z*16 + y*256) stored only up to the highest section holding anything but
// air: reads above it return AIR, writes grow it. Most of a 384-high column is sky, so this roughly halves
// block memory at large render distances. `data` is copy-on-write like any array.
struct BlockStore {
    private(set) var data: [BlockID]
    static let section = CSQ * 16
    // Bit per 16-high section that may hold a light-emitting block (all set = unknown). The mesher skips the
    // block-light pass when no section around the one it meshes has one (most of the surface).
    var emitMask: UInt32 = ~0

    // Exact emitter mask of a full block array (chunk workers).
    static func emitMask(of blocks: [BlockID]) -> UInt32 {
        let emit = Blocks.emit
        var m: UInt32 = 0
        var i = 0
        while i < blocks.count {
            if emit[Int(blocks[i])] > 0 {
                let sec = i / section
                m |= 1 << UInt32(sec)
                i = (sec + 1) * section          // the rest of this section can't add anything
                continue
            }
            i += 1
        }
        return m
    }

    init(_ full: [BlockID]) {
        var top = min(full.count, CSQ * CH)
        while top > 0 && full[top - 1] == AIR { top -= 1 }
        let keep = (top + BlockStore.section - 1) / BlockStore.section * BlockStore.section
        data = keep >= full.count ? full : Array(full[0..<keep])
        // Whole sections only (the mesher copies stored rows a section at a time): a short input is padded with air.
        if data.count < keep { data.append(contentsOf: repeatElement(AIR, count: keep - data.count)) }
    }

    var count: Int { CSQ * CH }             // logical size
    var storedCount: Int { data.count }     // everything at or above this index is AIR

    @inline(__always) subscript(i: Int) -> BlockID {
        get { UInt(bitPattern: i) < UInt(data.count) ? data[i] : AIR }      // a negative index reads as air too
        set {
            guard i >= 0 && i < CSQ * CH else { return }
            if i >= data.count {
                if newValue == AIR { return }
                let need = min(CSQ * CH, (i / BlockStore.section + 1) * BlockStore.section)
                data.append(contentsOf: repeatElement(AIR, count: need - data.count))
            }
            data[i] = newValue
            if Blocks.emit[Int(newValue)] > 0 { emitMask |= 1 << UInt32(i / BlockStore.section) }
        }
    }

    // Full-height copy (saving, tree growth scratch).
    func full() -> [BlockID] {
        if data.count >= CSQ * CH { return data }
        var out = data
        out.append(contentsOf: repeatElement(AIR, count: CSQ * CH - data.count))
        return out
    }

    // Same underlying storage: nothing was written since the copy was taken.
    func sameStorage(_ o: BlockStore) -> Bool {
        if data.isEmpty && o.data.isEmpty { return true }
        return data.withUnsafeBufferPointer { a in o.data.withUnsafeBufferPointer { b in a.baseAddress == b.baseAddress } }
    }
}

final class Chunk {
    let cx: Int
    let cz: Int
    var blocks: BlockStore         // index = x + z*16 + y*256
    // Per-section light (sky << 4 | block, index x + z*16 + (y&15)*256) from the mesher; nil until meshed
    // (then World.lightAt falls back to the heightmap). Uniform sections share Mesher.dark / Mesher.fullSky.
    var light = [[UInt8]?](repeating: nil, count: NSEC)
    var height: [Int16]            // highest sky-stopping block per column (-1 = none)
    var tint: [UInt32]             // 256 grass, 256 foliage, 256 water colours (RGBA8)
    var tintBuf: MeshSlice?          // tint table on the GPU (carved from the mesh slabs)
    var sections: [Section]
    // Highest section that has geometry or isn't meshed yet (everything above is meshed open air). Kept by
    // World.apply so the renderer's culling walk can stop above the terrain without scanning the sky.
    var topSec = NSEC - 1
    func updateTopSec() {
        var t = NSEC - 1
        while t > 0 && sections[t].empty && sections[t].meshedVersion != -1 { t -= 1 }
        topSec = t
    }
    var modified = false
    // The block array as last saved or loaded. Any write to `blocks` copies it (copy-on-write), so
    // "same storage" means nothing changed since then and the save can be skipped.
    var savedBlocks: BlockStore?
    var needsSave: Bool {
        guard modified else { return false }
        guard let s = savedBlocks else { return true }
        return !s.sameStorage(blocks)
    }
    var meshInFlight = false
    var meshedOnce = false
    var drawnMark: UInt32 = 0
    var dirty = false {            // a section's version changed since World.update last looked at this chunk
        didSet { if dirty && !oldValue { world?.dirtyChunks.append(self) } }
    }
    var lod = 0                    // 0 full detail, 1 far (flat light, merged faces, no small decorations), 2 mid ("fast" leaves)
    weak var world: World?         // the world it is installed in (its dirty list; set by World.install)

    // Live Chunk objects, for the smoke test's memory line (an unloaded chunk should be freed: memory grew ~20 MB/s
    // while the smoke test flew, runs 605-634). Chunks die on worker threads too, hence the lock.
    static let aliveLock = NSLock()
    private(set) static var alive = 0
    deinit { Chunk.aliveLock.lock(); Chunk.alive -= 1; Chunk.aliveLock.unlock() }

    init(cx: Int, cz: Int, blocks: [BlockID], height: [Int16], tint: [UInt32]) {
        Chunk.aliveLock.lock(); Chunk.alive += 1; Chunk.aliveLock.unlock()
        self.cx = cx
        self.cz = cz
        self.blocks = BlockStore(blocks)
        self.height = height
        self.tint = tint
        sections = (0..<NSEC).map { _ in Section() }
        for s in sections { s.owner = self }
        staleSections = NSEC                         // every section starts unmeshed (version 0, meshedVersion -1)
    }

    @inline(__always) static func index(_ x: Int, _ y: Int, _ z: Int) -> Int { x + z * CS + y * CSQ }
    // Sections whose mesh is out of date, kept by the sections as their versions change: needsMesh was a walk over all
    // 24 sections, asked of every loaded chunk on each scheduling scan (World.update profile).
    private(set) var staleSections = 0
    @inline(__always) func noteStale(was: Bool, now: Bool) { if was != now { staleSections += now ? 1 : -1 } }
    var needsMesh: Bool { staleSections > 0 }

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
        var y = min(CH, blocks.storedCount / CSQ) - 1
        while y >= 0 && !skyT[Int(blocks[c + y * CSQ])] { y -= 1 }
        height[c] = Int16(y)
    }
}
