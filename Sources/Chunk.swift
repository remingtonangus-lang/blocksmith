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
    var farSkip = 0             // P375 (GroundMerge): far, the first farSkip opaque quads give way to the farExtra
    var farExtra = 0            //   merged quads stored after the opaque ones in the same buffer
    var farCut = 0              // P384: far, the first farCut cutout quads (the leaf blobs' two shells) are left out too
    var farTail = 0             // P384: the last farTail cutout quads are drawn far only (things laid on the ground)
    var detailFarSkip = 0       // P384: far, the first detailFarSkip detail quads give way to the detailFarExtra stored
    var detailFarExtra = 0      //   after the detail ones in the same buffer
    var transBuf: MeshSlice?
    var transQuads = 0
    var detailBuf: MeshSlice?   // realistic world: round shapes (DetailMesh, 16-byte vertices), solid quads first
    var detailQuads = 0
    var detailSolid = 0
    var naturalCubes = 0                        // P338 step 2: natural ground meshed as cubes (field worlds; must be 0)
    var solidFull = false                       // P376 step 5: every cell opaque (an occluder)
    var groundQuads = 0, blobQuads = 0          // P283: of the opaque quads, the smooth ground's and the leaf blobs'
    var kinds = SIMD16<Int32>()                 // P384 step 1: quads by kind (MeshKind; not kept in the disk cache)
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
    var empty: Bool { opaqueQuads == 0 && transQuads == 0 && detailQuads == 0 }
}

// A chunk's blocks (index x + z*16 + y*256) stored only up to the highest section holding anything but
// air: reads above it return AIR, writes grow it. Most of a 384-high column is sky, so this roughly halves
// block memory at large render distances. `data` is copy-on-write like any array.
struct BlockStore {
    private(set) var data: [BlockID]
    // Field worlds (FieldTerrain.swift): the natural terrain is not in `data` at all. It is a density field, one sample per
    // cell centre in 1/32 block (> 0 inside the ground), and the ground's material per sample (FieldMat), stored like
    // `data` only up to the highest section the ground reaches. Empty in block worlds. `data` holds what is not terrain
    // (built blocks, plants, trees, fluids), and AIR wherever the ground is; reads merge the two (a cell inside the ground
    // reads as its material), so the game's block queries see the ground the field describes.
    private(set) var fd: [Int8] = []
    private(set) var fm: [UInt8] = []
    var isField: Bool { !fd.isEmpty }
    // P377 step 1: two samples per block where the ground has been edited (digging, blasts, building), per 16-high
    // section (key: section index): 32^3 samples at the half-block cells' centres (section-local (i + 0.5) / 2, index
    // FineField.index), in fd's units. A section without one is fd alone (untouched land is unchanged). FineField.swift.
    var fine: [Int: [Int8]] = [:]
    static let section = CSQ * 16
    // P338 step 2: reads of a field world's ground as a cell of its material (the block grid), counted while the debug
    // overlay shows them (PerfOverlay). Must read 0 where only the field's surface should be met.
    static var countReads = false
    static var groundReads = 0
    // Harness (questcheck --notespots --trace): who reads them (every 64th read's callers, tallied).
    static var traceReads = false
    static var readers: [String: Int] = [:]
    static func noteReader() {
        let st = Thread.callStackSymbols
        let key = st.dropFirst(2).prefix(5).map { l -> String in
            let parts = l.split(separator: " ").map(String.init)
            return parts.first(where: { $0.hasPrefix("$s") || $0.hasPrefix("_$s") }) ?? (parts.count > 3 ? parts[3] : l)
        }.joined(separator: " < ")
        readers[key, default: 0] += 1
    }
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

    init(_ full: [BlockID], field: FieldData) {
        self.init(full)
        guard !field.fd.isEmpty else { return }
        var top = min(field.fd.count, CSQ * CH)
        while top > 0 && field.fd[top - 1] <= 0 { top -= 1 }
        let keep = max(BlockStore.section, (top + BlockStore.section - 1) / BlockStore.section * BlockStore.section)
        fd = Array(field.fd.prefix(keep)); fm = Array(field.fm.prefix(keep)); fine = field.fine
        if fd.count < keep {
            fd.append(contentsOf: repeatElement(FieldTerrain.outside, count: keep - fd.count))
            fm.append(contentsOf: repeatElement(0, count: keep - fm.count))
        }
    }

    var count: Int { CSQ * CH }             // logical size
    var storedCount: Int { max(data.count, fd.count) }     // everything at or above this index is AIR
    var storedBytes: (blocks: Int, field: Int) { (data.capacity * 2, fd.capacity + fm.capacity) }   // (P374 perfscenes)

    // The built layer only (no ground): saves, the mesher's cube pass.
    @inline(__always) func raw(_ i: Int) -> BlockID { UInt(bitPattern: i) < UInt(data.count) ? data[i] : AIR }
    // The ground's density at cell i (1/32 block, > 0 inside); outside everywhere in block worlds.
    @inline(__always) func density(_ i: Int) -> Int8 { UInt(bitPattern: i) < UInt(fd.count) ? fd[i] : FieldTerrain.outside }
    @inline(__always) func material(_ i: Int) -> UInt8 { UInt(bitPattern: i) < UInt(fm.count) ? fm[i] : 0 }
    // Cell i is inside the ground (field worlds).
    @inline(__always) func ground(_ i: Int) -> Bool { UInt(bitPattern: i) < UInt(fd.count) && fd[i] > 0 }

    // What cell i is made of (the built block, else the ground's material where the cell is inside the ground): the same
    // answer as the subscript, read from the two layers for the material rules (World.materialAt) and an edit's
    // before-and-after (World.setBlock), so it is not a ground cell read (P377 step 2).
    @inline(__always) func materialCell(_ i: Int) -> BlockID {
        let b = UInt(bitPattern: i) < UInt(data.count) ? data[i] : AIR
        guard b == AIR, UInt(bitPattern: i) < UInt(fd.count), fd[i] > 0 else { return b }
        return FieldMat.blocks[Int(fm[i])]
    }

    static var keepGround = false            // P363: World.setFluid (main thread)
    @inline(__always) subscript(i: Int) -> BlockID {
        get {
            let b = UInt(bitPattern: i) < UInt(data.count) ? data[i] : AIR      // a negative index reads as air too
            if b != AIR || fd.isEmpty { return b }
            guard UInt(bitPattern: i) < UInt(fd.count) && fd[i] > 0 else { return AIR }
            if BlockStore.countReads { BlockStore.groundReads &+= 1; if BlockStore.traceReads && BlockStore.groundReads & 63 == 1 { BlockStore.noteReader() } }
            return FieldMat.blocks[Int(fm[i])]
        }
        set {
            guard i >= 0 && i < CSQ * CH else { return }
            // Field worlds: natural ground written to a cell becomes ground in the field (a cell-sized solid), anything else
            // written into the ground opens the cell first. (World.setBlock rounds the shape round the cell afterwards.)
            if !fd.isEmpty {
                let m = FieldMat.index[Int(newValue)]
                if m != 0 {
                    if Blocks.emit[Int(newValue)] > 0 { emitMask |= 1 << UInt32(i / BlockStore.section) }
                    // (Ground turned into other ground, grass creeping onto dirt or dying back, keeps its shape: it filled
                    // the cell out to a full block, a little bump in the slope wherever the grass went.)
                    setDensity(i, ground(i) ? density(i) : max(density(i), FieldTerrain.cellIn), material: m)
                    if i < data.count && data[i] != AIR { data[i] = AIR }
                    return
                }
                // (A fluid running onto shallow ground, or draining off it, leaves the ground as it is: World.setFluid.)
                if ground(i) && !(BlockStore.keepGround && (newValue == AIR || Blocks.fluidKind[Int(newValue)] != 0)) {
                    setDensity(i, FieldTerrain.cellOut, material: nil)
                }
            }
            if i >= data.count {
                if newValue == AIR { return }
                let need = min(CSQ * CH, (i / BlockStore.section + 1) * BlockStore.section)
                data.append(contentsOf: repeatElement(AIR, count: need - data.count))
            }
            data[i] = newValue
            if Blocks.emit[Int(newValue)] > 0 { emitMask |= 1 << UInt32(i / BlockStore.section) }
        }
    }

    // Writes the field at cell i (field worlds), growing the stored part when the ground rises past it. A nil material
    // keeps the cell's own.
    // `follow` (P377 step 1): the cell's eight fine samples, where its section has them, move with it (World.fieldSphere
    // writes them itself).
    mutating func setDensity(_ i: Int, _ d: Int8, material m: UInt8?, follow: Bool = true) {
        guard !fd.isEmpty, i >= 0 && i < CSQ * CH else { return }
        if i >= fd.count {
            if d <= 0 { return }
            let need = min(CSQ * CH, (i / BlockStore.section + 1) * BlockStore.section)
            fd.append(contentsOf: repeatElement(FieldTerrain.outside, count: need - fd.count))
            fm.append(contentsOf: repeatElement(0, count: need - fm.count))
        }
        if follow && !fine.isEmpty && fd[i] != d { FineField.follow(&fine, i, from: fd[i], to: d) }
        fd[i] = d
        if let m { fm[i] = m }
    }

    // Full-height copy of what the cells read as (tree growth scratch, the co-op wire).
    func full() -> [BlockID] {
        if fd.isEmpty {
            if data.count >= CSQ * CH { return data }
            var out = data
            out.append(contentsOf: repeatElement(AIR, count: CSQ * CH - data.count))
            return out
        }
        return [BlockID](unsafeUninitializedCapacity: CSQ * CH) { out, n in
            let mats = FieldMat.blocks
            for i in 0..<(CSQ * CH) {
                let b = i < data.count ? data[i] : AIR
                out[i] = b != AIR || i >= fd.count || fd[i] <= 0 ? b : mats[Int(fm[i])]
            }
            n = CSQ * CH
        }
    }

    // Full-height copy of the built layer alone (saving).
    func rawFull() -> [BlockID] {
        if data.count >= CSQ * CH { return data }
        var out = data
        out.append(contentsOf: repeatElement(AIR, count: CSQ * CH - data.count))
        return out
    }

    // The field as stored (saving).
    var field: FieldData { FieldData(fd: fd, fm: fm, fine: fine) }

    // Same underlying storage: nothing was written since the copy was taken.
    func sameStorage(_ o: BlockStore) -> Bool {
        func same<T>(_ a: [T], _ b: [T]) -> Bool {
            if a.isEmpty && b.isEmpty { return true }
            return a.withUnsafeBufferPointer { x in b.withUnsafeBufferPointer { y in x.baseAddress == y.baseAddress && x.count == y.count } }
        }
        return same(data, o.data) && same(fd, o.fd) && same(fm, o.fm)
    }
}

final class Chunk {
    let cx: Int
    let cz: Int
    var blocks: BlockStore {       // index = x + z*16 + y*256
        didSet { unsaved = true; blocksVersion &+= 1 }
    }
    private(set) var blocksVersion = 0
    // P339 (horizon culling, SceneRenderer.horizonCull): the y under which every column of the chunk is solid for 16
    // cells (ground or opaque blocks; leaves and water don't count), so a sight line crossing the chunk between that y
    // and 16 below is stopped. -1: some column has no such band. Cached until the blocks change.
    private var occTop = -1, occKey = -1
    var occluderTop: Int {
        if hollow { return hollowOcc }
        if occKey == blocksVersion { return occTop }
        occKey = blocksVersion
        let opq = Blocks.opaque
        var h = Int.max
        for col in 0..<CSQ {
            var y = min(CH - 1, Int(height[col])), run = 0, top = -1
            while y >= 0 {
                let i = col + y * CSQ
                if blocks.ground(i) || opq[Int(blocks.raw(i))] { run += 1; if run == 16 { top = y + 16; break } } else { run = 0 }
                y -= 1
            }
            if top < 0 { occTop = -1; return -1 }
            h = min(h, top)
        }
        // Every column must be solid across the shared band [h-16, h), not just across its own run.
        for col in 0..<CSQ {
            for y in (h - 16)..<h {
                let i = col + y * CSQ
                if !(blocks.ground(i) || opq[Int(blocks.raw(i))]) { occTop = -1; return -1 }
            }
        }
        occTop = h
        return h
    }
    // Per-section light (sky << 4 | block, index x + z*16 + (y&15)*256) from the mesher; nil until meshed
    // (then World.lightAt falls back to the heightmap). Uniform sections share Mesher.dark / Mesher.fullSky.
    var light = [[UInt8]?](repeating: nil, count: NSEC)
    var height: [Int16] {          // highest sky-stopping block per column (-1 = none)
        didSet { heightMax = Int(height.max() ?? -1) }
    }
    // P374: the highest of them (the random ticks' top; they scanned all 256 columns of every chunk in reach each tick).
    private(set) var heightMax = -1
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
    var hollow = false             // P376: a shell, its blocks, field and light dropped past the active distance (ChunkShells)
    var hollowOcc = -1             //   its horizon-culling band, kept from before
    var cacheDropped = false       //   its disk mesh cache file dropped since it loaded (edited)
    var fieldEdits: [Int32: UInt16] = [:]     // PG1: bounds on the terrain field per cell (TerrainField.swift)
    var fieldDirty = false                    // ...changed since last saved
    // P374: written since it was last saved or loaded. (It kept the arrays as last saved and compared storage: the
    // first write after each save copied the chunk's blocks and field, so every chunk a random tick, a flow or an edit
    // touched between autosaves held two copies of them, up to the whole loaded area's block memory again.)
    private(set) var unsaved = true
    func markSaved() { unsaved = false }
    var needsSave: Bool { modified && unsaved }
    var heldCopyBytes: Int { 0 }                 // (perfscenes: what kept save copies cost; none now)
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

    var borderSeeds: [Int] = []                      // P380 (2): small pieces at the side, checked once the neighbours exist
    init(cx: Int, cz: Int, blocks: [BlockID], height: [Int16], tint: [UInt32], field: FieldData? = nil) {
        Chunk.aliveLock.lock(); Chunk.alive += 1; Chunk.aliveLock.unlock()
        self.cx = cx
        self.cz = cz
        self.blocks = field.map { BlockStore(blocks, field: $0) } ?? BlockStore(blocks)
        self.height = height
        heightMax = Int(height.max() ?? -1)
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
        while y >= 0 && !skyT[Int(blocks.materialCell(c + y * CSQ))] { y -= 1 }      // (the material: not a ground cell read)
        height[c] = Int16(y)          // (didSet keeps heightMax)
    }
}
