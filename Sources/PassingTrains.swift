import Foundation
import simd

// Ledger 238 (bloom of ledger 230, which gives a lone town a line of its own with one station): a line's train runs
// its own line's track out and back, and a line of one station is a straight of a hundred-odd cells past the town, so
// its train would have shuttled the length of the platform and back, passing each end at speed and turning there.
// Such a line's train runs a long window instead: the stretch of open country before it, the link in, the line, the
// link on and the next stretch (the row is one unbroken track in these worlds). It comes in from far off, stands at
// the station, runs on out of sight, and comes back the other way later. Boarded, it runs on as any through train.
// BS_OLDSTUBTRAIN=1: the line's own track, as it would have been.
extension Trains {
    static let oldStubTrain = Env.all["BS_OLDSTUBTRAIN"] == "1"
    static func passes(_ l: Railways.Line, gen: WorldGen) -> Bool {
        !oldStubTrain && Railways.sparseWorld(gen) && !l.wild && !Railways.isLink(l.id) && l.stations.count == 1
    }
    static func passingTrack(_ l: Railways.Line, gen: WorldGen, wait: Bool) -> Track? {
        guard passes(l, gen: gen) else { return nil }
        let (row, st) = Railways.rowStretch(l.id)
        // (ledger 360: a railway may end at this town; then the window is the line and the side that runs on)
        var parts: [Railways.Line] = [l]
        if let (a, lkIn) = Railways.incoming(gen, row, st, wait: wait) { parts = [a, lkIn] + parts }
        if let lkOut = Railways.link(gen, row: row, stretch: st, wait: wait), let b = Railways.linkTarget(gen, lkOut, wait: wait) { parts += [lkOut, b] }
        guard parts.count >= 3, Railways.shoreRule(gen) || parts.count == 5 else { return nil }
        let cells = parts.flatMap { $0.cells }
        // (joined cell to cell, or it is no track to run)
        for i in 1..<cells.count where abs(cells[i].x - cells[i - 1].x) + abs(cells[i].z - cells[i - 1].z) != 1 { return nil }
        let heights: [Float]? = parts.allSatisfy { $0.heights != nil } ? parts.flatMap { $0.heights! } : nil
        var stops: [Int] = [], names: [String] = [], off = 0
        for p in parts {
            for s in p.stations { stops.append(off + s.index); names.append(s.name + " Station") }
            off += p.cells.count
        }
        let whole = Railways.Line(id: 0, name: l.name, cells: cells, stations: [], heights: heights)
        let shapes = cells.indices.map { whole.shape($0) }
        let t = Track(id: l.id, name: l.name, cells: cells, slopes: shapes.map { (2...5).contains($0) }, stops: stops, stopNames: names,
                      armoured: false, dim: .overworld, heights: heights, openEnds: true)
        t.shapes = shapes
        t.parts = parts
        t.source = l.cells.count
        return t
    }
}
