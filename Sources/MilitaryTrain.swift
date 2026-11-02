import Foundation
import simd

// P510 (Nov 1 20:24, by a Greywall troop train: "It would be nice if I could go through each compartment and kill some
// of the guys and then drive the weaponized train and use its gun to blow shit up"): a troop train could only be
// stopped or shot at, and then its soldiers piled out beside it. Now it can be taken from inside, car by car:
//   Boarding   used, a troop car takes him aboard: he stands in its aisle between the firing slits and rides with it.
//              The car's four soldiers turn on him where they sit; while he is aboard none of the train's troops get
//              off (he fights them in their own compartments). Used again from one car, the next is boarded.
//   The cab    the armoured engine can't be taken while a soldier still rides the train ("N soldiers still hold the
//              train"). Once they are down it is his: used, he takes the regulator and drives it (Trains' cab
//              controls), and the guard car's gun no longer fires on him.
//   The gun    on a train he has taken, the guard car is used to work its gun: he stands at the turret behind the
//              breech, the turret follows his view, and the trigger fires a high-explosive shell (a field gun's, half
//              a deck gun's blast) every 1.5 s. Sneak leaves it.
enum MilitaryTrain {
    static func isTroopTrain(_ tr: Trains.Train) -> Bool { tr.kind == .troop && !tr.track.armoured && !tr.layout.isEmpty }

    // He rides one of its cars (or works its gun).
    static func aboard(_ g: Game, _ tr: Trains.Train) -> Bool {
        if let r = g.riding, tr.cars.contains(where: { $0 === r }) { return true }
        if let c = TrainGun.shared.car, tr.cars.contains(where: { $0 === c }) { return true }
        return false
    }
    static func holding(_ tr: Trains.Train) -> [Mob] { tr.troops.filter { $0.mount != nil && $0.health > 0 } }

    static func use(_ g: Game, _ tr: Trains.Train, _ m: Mob) -> Bool {
        guard isTroopTrain(tr), Trains.isBig(m) else { return false }
        switch m.variant {
        case Trains.troopCar:
            if g.riding === m { return false }
            board(g, m)
            let here = tr.troops.filter { $0.mount === m && $0.health > 0 }.count
            g.onToast?(here > 0 ? "Aboard the troop car: \(here) soldiers in it" : "Aboard the troop car")
            return true
        case Trains.armouredLoco:
            let left = holding(tr).count
            if left > 0 && !tr.taken {
                g.onToast?(left == 1 ? "A soldier still holds the train" : "\(left) soldiers still hold the train")
                return true
            }
            if !tr.taken {
                tr.taken = true
                g.onToast?("The train is yours: forward opens the regulator")
            }
            if g.riding === m { return false }
            board(g, m)
            return true
        case Trains.gunCar:
            guard m.health > 0 else { g.onToast?("The guard car's gun is wrecked"); return true }
            guard tr.taken else {
                let left = holding(tr).count
                g.onToast?(left > 0 ? "\(left) soldiers still hold the train" : "Take the engine first")
                return true
            }
            if g.riding != nil { g.dismount() }
            TrainGun.shared.man(g, m)
            return true
        default:
            return false
        }
    }

    static func board(_ g: Game, _ m: Mob) {
        if TrainGun.shared.car != nil { TrainGun.shared.leave(g) }
        if g.riding != nil { g.dismount() }
        g.riding = m
        g.player.pos = Trains.seat(m)
        g.player.vel = .zero
        g.sfx(.armorEquip(0), 0.5, at: m.pos)
        boarded += 1
    }
    static var boarded = 0                       // (checks)
}

// The guard car's gun worked by him (a taken troop train).
final class TrainGun {
    static let shared = TrainGun()
    weak var car: Mob?
    var reload: Float = 0
    private(set) var shots = 0
    static let reloadTime: Float = 1.5
    static let speed: Float = 90, gravity: Float = 9, power: Float = 2.6

    func man(_ g: Game, _ m: Mob) {
        car = m
        reload = 0.5
        g.player.yaw = m.yaw + m.jobTimer
        g.player.flying = false
        g.sfx(.place(.stone), 0.8, at: m.pos)
        g.onToast?("On the guard car's gun")
    }
    func leave(_ g: Game) {
        guard let m = car else { return }
        car = nil
        // Down beside the car, on the ground.
        let right = V3(cosf(m.yaw), 0, -sinf(m.yaw))
        g.player.pos = g.world.freeSpawn(m.pos + right * 2.8)
        g.player.vel = .zero
        g.player.airPeak = g.player.pos.y
    }

    static func muzzle(_ m: Mob) -> V3 { m.pos + V3(0, 3.45, 0) }
    // The turret's forward (the car's yaw plus the turret's own, kept in jobTimer as the AI's gun does) and his pitch.
    static func aim(_ m: Mob, pitch: Float) -> V3 {
        let yaw = m.yaw + m.jobTimer
        return V3(-sinf(yaw) * cosf(pitch), sinf(pitch), -cosf(yaw) * cosf(pitch))
    }

    // Per frame while on the gun (Game.tick, before movement): true = the gun has the controls this frame.
    func tick(_ g: Game, _ p: PadSnapshot, _ q: PadSnapshot, sneak: Bool, dt: Float) -> Bool {
        guard let m = car else { return false }
        guard m.health > 0, g.alive, Trains.carOf[ObjectIdentifier(m)] != nil, g.mobs.mobs.contains(where: { $0 === m }) else {
            car = nil
            return false
        }
        if sneak { leave(g); return false }
        // The turret follows his view at a field gun's traverse.
        var d = (g.player.yaw - m.yaw) - m.jobTimer
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        m.jobTimer += max(-2.2 * dt, min(2.2 * dt, d))
        g.player.pitch = max(-0.35, min(0.7, g.player.pitch))
        // He stands behind the breech on the car's roof, carried with it.
        let yaw = m.yaw + m.jobTimer
        let back = V3(sinf(yaw), 0, cosf(yaw))
        g.player.pos = TrainGun.muzzle(m) + back * 1.6 + V3(0, -0.9, 0)
        g.player.vel = .zero
        g.player.onGround = true
        reload -= dt
        let fire = g.input.leftClicked || (p.rt > 0.5 && q.rt <= 0.5)
        if fire && reload <= 0 { shoot(g, m) } else if fire { g.sfx(.click, 0.4) }
        g.target = nil
        g.mining = nil
        return true
    }

    func shoot(_ g: Game, _ m: Mob) {
        reload = TrainGun.reloadTime
        let fwd = TrainGun.aim(m, pitch: g.player.pitch)
        let at = TrainGun.muzzle(m) + fwd * 2.2
        var s = Slug(pos: at, vel: Guns.scatter(fwd, 0.003) * TrainGun.speed + m.vel, kind: .shell, damage: 0, fromPlayer: true,
                     shooter: ObjectIdentifier(m), by: "Player", life: 10, gravity: TrainGun.gravity)
        HeavyTurret.arm(&s)
        s.power = TrainGun.power
        g.arms.spawn(s)
        HeavyTurret.flash(g, at, fwd, smoke: 6)
        g.sfx(.gun(9), 1.6, at: at)
        g.baseNoise(at: at, kind: .cannon)
        PadManager.shared.rumble(0.7, 0.25, sharpness: 0.3)
        g.player.pitch += 0.02
        shots += 1
    }
}
