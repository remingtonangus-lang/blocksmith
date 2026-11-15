import Foundation
import simd

// Checks for the Nov 14 evening playtest's fixes (Opus lane) that need no world of their own (questcheck suite).
enum Nov14EveningChecks {
    static func run(_ g: Game, _ check: (Bool, String) -> Void) {
        townSeats(check)
    }

    // 21:17, Elk Hollow's sheriff's office: "This chair's not facing the right way". Every town seat asked for with its
    // back toward a local direction is a chair (not a bench) whose back slats stand on that side, for every lot facing
    // and every wood.
    static func townSeats(_ check: (Bool, String) -> Void) {
        var wrong: [String] = [], tried = 0
        let worldDir = [V2(0, -1), V2(0, 1), V2(-1, 0), V2(1, 0)]       // 0 north, 1 south, 2 west, 3 east
        for style in [Village.Style.plains, .desert, .savanna, .taiga, .snowy] {
            let m = Village.mats(style)
            for face in 0..<4 { for local in 0..<4 {
                let l = Village.Lot(kind: .office, ax: 0, az: 0, face: face, w: 7, d: 6, y: 0, seed: 1, job: "")
                let id = Village.LB(l: l).seat(m, "chair", back: local)
                tried += 1
                let key = Blocks.key(Blocks.groupBase[Int(id)])
                guard key.hasSuffix("_chair") else { wrong.append("\(style) face \(face) back \(local): \(Blocks.name(id))"); continue }
                // The back slats: the boxes above the seat (y 10...16), their middle against the block's middle.
                let back = Blocks.boxes[Int(id)].filter { $0.y0 >= 10 }
                guard !back.isEmpty else { wrong.append("\(key): no back"); continue }
                var c = V2(0, 0)
                for b in back { c += V2(Float(Int(b.x0) + Int(b.x1)) / 2 - 8, Float(Int(b.z0) + Int(b.z1)) / 2 - 8) }
                c /= Float(back.count)
                let want = worldDir[Village.dir(l, local)]
                if simd_dot(simd_normalize(c), want) < 0.9 { wrong.append("\(style) face \(face) back \(local): slats toward \(c)") }
            } }
        }
        check(wrong.isEmpty && tried == 80,
              "Nov 14 chair: every town chair (5 woods x 4 lot facings x 4 sides) is a chair with its back where it was asked for (\(wrong.count) wrong of \(tried)\(wrong.isEmpty ? "" : ": " + wrong.prefix(3).joined(separator: "; ")))")
    }
}
