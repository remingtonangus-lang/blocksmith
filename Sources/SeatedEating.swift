import Foundation

// P435 (Oct 24 16:00, "should be able to eat when I'm in a car or in a tank"): at the controls of a vehicle his hands
// are on the controls (Game.held is empty), so the food on his hotbar couldn't be eaten. Now, seated in an Ashguard
// vehicle, at a deck gun, or at the helm of a ship whose left trigger has no other job (an armed one, whose trigger
// fires its guns, or a dropship), holding use eats or drinks the food selected on the hotbar, as on foot (1.6 s, the
// chewing, then the meal); the vehicle keeps its pace while he eats.
extension Game {
    func seatedEatTick(_ p: PadSnapshot, _ dt: Float) {
        guard handsOnControls, survival else { return }
        var use = input.rightDown
        if p.lt > 0.5 {
            if let s = world.ships.pilot {
                if VehicleControls.armed(self, s) || VehicleControls.kind(s) == .vtol { use = true }
            } else {
                use = true                                   // a tank, half-track, truck or field gun, or a deck gun
            }
        }
        let h = inventory.held
        let hk = Items.key(h.item)
        let always = ["golden_apple", "enchanted_golden_apple", "chorus_fruit", "suspicious_stew"].contains { hk.hasPrefix($0) }
        guard use, let f = h.def.food, !h.def.drink, hunger < 20 || always else {
            if !use { eatProgress = 0 }
            return
        }
        eatProgress += dt
        if Int(eatProgress * 5) != Int((eatProgress - dt) * 5) {
            sfx(hk.hasSuffix("_stew") || hk.hasSuffix("_soup") ? .drink : .eat, 0.5)
        }
        guard eatProgress >= 1.61 else { return }
        eatProgress = 0
        eat(f, h.def.display)
        foodEffects(hk)
        var left = h
        left.count -= 1
        inventory.held = left.count > 0 ? left : .empty
        if hk == "mushroom_stew" || hk == "beetroot_soup" || hk == "rabbit_stew" || hk.hasPrefix("suspicious_stew") {
            let bowl = ItemStack(Items.id("bowl"), 1)
            if inventory.held.isEmpty { inventory.held = bowl } else { let rest = inventory.add(bowl); if !rest.isEmpty { dropItem(rest) } }
        }
    }
}
