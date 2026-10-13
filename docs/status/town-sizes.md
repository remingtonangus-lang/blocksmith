# Town sizes (C13)

Code: `Sources/TownSizes.swift`. Hooks are in `Village.layout`, `Railways.plan` and `MiningTowns`.
Check: `questcheck --sizes-only` (`Sources/TownSizesTests.swift`). It draws a histogram over 50 seeds.

A town laid out on ground no save had generated before sizes is given one of five sizes. The guard is
`StructureCache.legacyC13`, saved as `structure-guard-c13.txt`. The size is picked from the town's position, and each
size is 3.5 times rarer than the one below:

| size       | weight | streets (length) | shops | deputies | office and bank | mine |
|------------|-------:|------------------|------:|---------:|-----------------|------|
| hamlet     | 71.6%  | two, x0.5        | 1     | 0        | no              | no   |
| village    | 20.5%  | four, x0.75      | 3     | 1        | yes             | no   |
| town       | 5.8%   | as before        | 5     | 2        | yes             | yes  |
| large town | 1.7%   | x1.25, more side streets | 8 | 3     | yes             | yes  |
| city       | 0.5%   | x1.5, many side streets  | 8 | 4     | yes             | yes  |

- **Railways.** A line passing a village or bigger gives it a station. A hamlet gets only a halt: a short platform and a name board, with no station house.
- **Signs.** The welcome signs show the size, for example "(Large Town)".
- **Saved size.** The start keeps its size and counts in `StructureStart.info` (`size`, `lots`, `shops`, `deputies`,
  `office`).
- **Village reach.** The village structure's reach went from 6 to 8 chunks, so the longest city streets are not cut off.
- **Host checks.** These turn sizes off (`TownSizes.on = false` in the questcheck main), so their fixture towns stay as
  they were.
