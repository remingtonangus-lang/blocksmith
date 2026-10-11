# Vehicles: build them or buy them? (P54 prototype)

Remington's Oct 11 evening note: "either craft a tank from a ludicrous amount of materials or build preset vehicles at
a special vehicle table; undecided, prototype one and note the trade-off".

## What exists now

- **Free build (already in the game):** place blocks round a Helm (wheels, engines, propellers, balloons, wings,
  turret rings, cannons) and use the Helm: the connected structure becomes a vehicle (Ships.swift). Anything goes, and it
  costs only the blocks you placed.
- **Preset (prototype, this PR):** the **Vehicle Works** block (recipe: 6 iron blocks, 2 engines and a crafting table).
  Use it with the bill of parts in your inventory and a **Field Tank** rolls out on the far side of the Works: an iron
  hull on eight wheels, two engines, a helm at the back and a turret with a cannon (VehicleWorks.swift). The bill is
  the "ludicrous" part: 96 iron ingots, 2 engines, 8 wheels, a turret ring, a cannon and a helm. Short of parts, it
  names what is missing. It needs an 11 x 14 clear yard.

## Trade-off

| | Free build at a Helm | Preset at the Vehicle Works |
|---|---|---|
| Effort | Long: design, place every block, fix what doesn't drive | One use once the parts are in hand |
| Cost | Only what you place (a cheap cart is cheap) | Fixed and high (about 2.5 stacks of iron with the parts) |
| Result | Anything; often unbalanced or broken (no wheels touching, too heavy for its engines) | Always drives, always balanced; looks designed |
| VR (Quest) | Hard: placing hundreds of blocks with controllers is slow | Easy: one interaction |
| Balance | Hard to tune (a 40-cannon fortress-tank is possible) | Easy: we set the armour, guns and price |
| Expansion | Nothing to add | Add more presets (scout car, truck, gunboat) at the same Works |

## Recommendation

Keep both. Make the Vehicle Works the main way for most players (and the only sensible one on the Quest), with a small
catalogue of presets that unlock as you progress, and keep the Helm for builders. If only one: the Works, because it
plays well in VR and can be balanced.

## Open for Remington

- Is the bill (96 iron and the parts) the right "ludicrous"? It is one constant (VehicleWorks.bill).
- Should presets need a blueprint item (looted from Capital citadels) before the Works offers them?
- The turret on the prototype is the ship system's turret ring; aiming it from the helm is the next step if the Works
  stays.
