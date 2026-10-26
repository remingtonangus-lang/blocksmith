import Foundation

// Town sizes (backlog C13). A town laid out on ground no save had generated before sizes (StructureCache.legacyC13)
// is a hamlet, a village, a town, a large town or a city, picked by its position; each size is about 3.5 times rarer
// than the one below (`questcheck --sizes-only` draws the histogram over 50 seeds). Bigger places get:
//   streets   longer streets and more of them (Village.layout scales every street and caps the side streets)
//   shops     a hamlet keeps a general store; a village three shops, a town five, large towns and cities all eight
//   law       a hamlet has only its sheriff (no office, no bank); a village one deputy, a town two, a large town
//             three, a city four, each with the sheriff's office and the bank
//   mine      from a town up (MiningTowns.swift)
//   railway   a line passing a village or bigger gives it a station; a hamlet gets only a halt (a short platform
//             and a name board, Railways.plan)
// The size shows on the welcome signs ("(Large Town)") and is kept on the start (StructureStart.info["size"]).
enum TownSize: Int, CaseIterable { case hamlet, village, town, largeTown, city }

enum TownSizes {
    static var on = true                   // (the host checks turn sizes off so their fixture towns stay as they were)
    static let names = ["Hamlet", "Village", "Town", "Large Town", "City"]
    static let ratio: Float = 3.5

    struct Spec {
        let length: Float      // street length scale
        let branch: Float      // side street chance scale
        let firstRoads: Int    // the plan's own streets kept
        let extraRoads: Int    // street cap over the old one
        let minLots: Int
        let shops: Int
        let deputies: Int
        let office: Bool
        let bank: Bool
        let mine: Bool
    }
    static let spec: [Spec] = [
        Spec(length: 0.5, branch: 0, firstRoads: 2, extraRoads: -10, minLots: 3, shops: 1, deputies: 0, office: false, bank: false, mine: false),
        Spec(length: 0.75, branch: 0.6, firstRoads: 4, extraRoads: -4, minLots: 6, shops: 3, deputies: 1, office: true, bank: true, mine: false),
        Spec(length: 1.0, branch: 1.0, firstRoads: 6, extraRoads: 0, minLots: 6, shops: 5, deputies: 2, office: true, bank: true, mine: true),
        Spec(length: 1.25, branch: 1.3, firstRoads: 6, extraRoads: 4, minLots: 6, shops: 8, deputies: 3, office: true, bank: true, mine: true),
        Spec(length: 1.5, branch: 1.6, firstRoads: 6, extraRoads: 8, minLots: 6, shops: 8, deputies: 4, office: true, bank: true, mine: true),
    ]

    // P466 (Remington, Oct 25 20:00, Iron Hollow: "These villages are just too small"): on ground no save had generated
    // before P466 (StructureCache.legacyP466) the two small sizes, seven places in ten, are laid out bigger: a hamlet
    // gets three streets at 0.8 of a town's length (was two at half), a village five at 0.9 with most of a town's
    // side streets (was four at 0.75): about 5 and 8 lots (were 4 and 6; a town has 8). The law, shops and mines stay
    // as each size has them, and whether a place is built at all is the old plan's say (Village.layout's caller).
    static let biggerSpec: [Spec] = [
        Spec(length: 0.8, branch: 0.5, firstRoads: 3, extraRoads: -8, minLots: 3, shops: 1, deputies: 0, office: false, bank: false, mine: false),
        Spec(length: 0.9, branch: 0.8, firstRoads: 5, extraRoads: -3, minLots: 6, shops: 3, deputies: 1, office: true, bank: true, mine: false),
    ] + spec[2...]

    // The size of a town at (ox, oz): weights 1, 1/3.5, 1/3.5^2... (71.6%, 20.5%, 5.8%, 1.7%, 0.5%).
    static func size(_ ox: Int, _ oz: Int, seed: UInt64) -> TownSize {
        let weights = (0..<5).map { powf(1 / ratio, Float($0)) }
        let total = weights.reduce(0, +)
        let u = Float(hash3(ox, 1913, oz, UInt32(truncatingIfNeeded: seed ^ (seed >> 29))) % 1_000_000) / 1_000_000 * total
        var acc: Float = 0
        for (k, wt) in weights.enumerated() { acc += wt; if u < acc { return TownSize(rawValue: k)! } }
        return .city
    }

    // The size of the town a start is (nil: laid out before sizes).
    static func of(_ s: StructureStart) -> TownSize? { s.info["size"].flatMap { TownSize(rawValue: $0) } }
}
