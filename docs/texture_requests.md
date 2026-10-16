# Texture requests for Gemini (website), in priority order

Upload each image as `assets/gemini/<texture_name>.png` on `claude/blocksmith-playtest`. The names below are the
game's texture names exactly. Each file replaces that one texture (one block face). Upload in batches; Claude Code
imports whatever has arrived on its next push. The import runs `tools/teximport.py`: it crops the image square,
checks for a 2x2 repeat, flattens large-scale brightness, locks the mean colour, downsamples to 128 px and fixes the
seams. Claude Code then compares each texture side by side with the procedural one before it is used.

## Rules for every image
- Square, straight-on and orthographic: one flat face seen head-on. No perspective, no 3D block, no border, frame or
  text. One tile only, seamless on all four edges.
- 1024 px or larger. The importer downsamples to 128 px.
- Block-scale features: the main elements (stones, planks, bricks, clumps) number about 4-12 across the tile, never
  hundreds. At 128 px a feature must still read.
- Uniform density: no large light or dark patches, no vignette. One soft light from the top-left as gentle relief,
  with no cast shadows.
- The style is stylised realism with a hand-painted feel and a natural earthy palette (`docs/textures/STYLE_GUIDE.md`).
  Use the same reference image in every prompt, so the set matches.
- Original art only: no logos and nothing copied from another game.
- The Mode column says how the importer treats the image:
  - **plain:** used as painted.
  - **tint:** any green is fine. It is turned into greyscale and tinted per biome in game.
  - **overlay:** the green grass fringe is tinted per biome; the rest stays as painted.
  - **cutout:** paint on a solid pure magenta `#FF00FF` background. The magenta becomes transparent, so leave gaps
    in leaves.

## Tier 1: what fills most of every view
| # | texture name | face | mode | what it should show |
|---|---|---|---|---|
| 1 | `grass_block_top` | top of grass blocks | tint | short dense lawn grass from directly above; blades about a tenth of the tile |
| 2 | `grass_block_side` | sides of grass blocks | overlay | brown soil with a ragged band of grass hanging over the top edge (about 3/16 of the tile) |
| 3 | `dirt` | dirt; also the bottom of grass blocks | plain | brown soil, soft clods (about a sixth of the tile) and a few small pebbles |
| 4 | `stone` | stone | plain | grey natural stone, fine mineral grain, soft mottling, a few faint hairline cracks |
| 5 | `oak_leaves` | oak leaves (all faces) | cutout + tint | a dense clump of small leaves on magenta, with about 20 % gaps |
| 6 | `oak_log` | bark side of oak logs | plain | vertical bark plates split by deep fissures, 5-7 plates across |
| 7 | `oak_log_top` | cut end of oak logs | plain | cross-section: bark ring at the edge, about 6 growth rings, darker heart |
| 8 | `sand` | sand | plain | fine pale sand with about 5 gentle wind ripples |
| 9 | `cobblestone` | cobblestone | plain | 6-10 large rounded grey stones set in dark mortar |
| 10 | `oak_planks` | oak planks | plain | 4 horizontal planks with grain, a few knots and thin dark seams |
| 11 | `gravel` | gravel | plain | packed grey and brown pebbles, 10-15 across |
| 12 | `deepslate` | deeprock (deep stone) | plain | dark blue-grey layered rock with horizontal strata |

## Tier 2: the common biomes and building blocks
| # | texture name | face | mode | what it should show |
|---|---|---|---|---|
| 13 | `spruce_log` | spruce log side | plain | dark reddish-brown scaly bark |
| 14 | `spruce_log_top` | spruce log end | plain | dark rings, reddish heart |
| 15 | `spruce_leaves` | spruce leaves | cutout + tint | dense short needles on magenta |
| 16 | `spruce_planks` | spruce planks | plain | 4 dark brown planks |
| 17 | `birch_log` | birch log side | plain | white bark with black horizontal marks and lenticels |
| 18 | `birch_log_top` | birch log end | plain | pale rings with a thin white bark ring |
| 19 | `birch_leaves` | birch leaves | cutout + tint | small round leaves on magenta |
| 20 | `birch_planks` | birch planks | plain | 4 pale cream planks |
| 21 | `sandstone` | sandstone side | plain | layered pale sandstone with 3-4 horizontal bands |
| 22 | `sandstone_top` | sandstone top | plain | smooth pale sandstone, faint speckle |
| 23 | `andesite` | andesite | plain | mid-grey speckled igneous rock |
| 24 | `diorite` | diorite | plain | white rock with black and grey flecks |
| 25 | `granite` | granite | plain | pinkish-red rock with grey and white grains |
| 26 | `stone_bricks` | stone bricks | plain | 4 courses of large grey bricks (2 across), thin mortar |
| 27 | `bricks` | bricks | plain | red clay bricks in light grey mortar, running bond, 4 courses |
| 28 | `snow` | snow | plain | soft white snow with faint blue shading and sparkle |
| 29 | `ice` | ice | plain | translucent-looking pale blue ice with internal cracks |
| 30 | `clay` | clay | plain | smooth blue-grey clay, faint smears |
| 31 | `coarse_dirt` | coarse dirt | plain | dry brown soil with many small stones |
| 32 | `mossy_cobblestone` | mossy cobblestone | plain | cobblestone (as #9) with moss in the cracks and on some stones |

## Tier 3: ores, deep and dry places
| # | texture name | face | mode | what it should show |
|---|---|---|---|---|
| 33 | `coal_ore` | coal ore | plain | stone (as #4) with 4-6 black coal clusters |
| 34 | `iron_ore` | iron ore | plain | stone with 4-6 beige-orange mineral clusters |
| 35 | `copper_ore` | copper ore | plain | stone with orange and green-tinged copper clusters |
| 36 | `gold_ore` | gold ore | plain | stone with bright yellow gold flecks |
| 37 | `redstone_ore` | sparkstone ore | plain | stone with red crystalline clusters |
| 38 | `lapis_ore` | lapis ore | plain | stone with deep blue clusters |
| 39 | `diamond_ore` | diamond ore | plain | stone with pale cyan crystal clusters |
| 40 | `emerald_ore` | emerald ore | plain | stone with small green crystals |
| 41 | `tuff` | tuff | plain | grey-green volcanic ash rock, porous |
| 42 | `calcite` | calcite | plain | white crystalline rock, soft facets |
| 43 | `dripstone_block` | dripstone block | plain | brown banded rock with vertical drip streaks |
| 44 | `moss_block` | moss block | plain | thick soft green moss |
| 45 | `red_sand` | red sand | plain | orange-red sand with ripples |
| 46 | `terracotta` | terracotta | plain | smooth fired orange-brown clay, faint mottling |
| 47 | `mud` | mud | plain | wet dark brown mud with a slight sheen |
| 48 | `podzol_top` | podzol top | plain | forest floor of brown needles and small twigs |

## Tier 4: the other worlds and the remaining woods
| # | texture name | face | mode | what it should show |
|---|---|---|---|---|
| 49 | `netherrack` | Emberdeep rock | plain | dark red porous rock with fleshy texture |
| 50 | `soul_sand` | soul sand | plain | dark brown sand with faint face-like hollows (keep them subtle and original) |
| 51 | `basalt_side` | basalt side | plain | dark grey vertical columns |
| 52 | `blackstone` | blackstone | plain | near-black rough stone with subtle grey grain |
| 53 | `end_stone` | Hollow stone | plain | pale yellow porous stone |
| 54 | `obsidian` | obsidian | plain | glossy black-purple volcanic glass with purple sheen |
| 55 | `dark_oak_log` | dark oak log side | plain | very dark brown rugged bark |
| 56 | `dark_oak_log_top` | dark oak log end | plain | dark rings |
| 57 | `dark_oak_planks` | dark oak planks | plain | 4 chocolate-brown planks |
| 58 | `dark_oak_leaves` | dark oak leaves | cutout + tint | dense dark leaves on magenta |
| 59 | `jungle_log` | jungle log side | plain | brown bark with green-grey lichen patches |
| 60 | `jungle_planks` | jungle planks | plain | 4 pinkish-brown planks |
| 61 | `jungle_leaves` | jungle leaves | cutout + tint | large broad leaves on magenta |
| 62 | `acacia_log` | acacia log side | plain | grey bark with orange showing through cracks |
| 63 | `acacia_planks` | acacia planks | plain | 4 orange planks |
| 64 | `acacia_leaves` | acacia leaves | cutout + tint | small leaves in flat sprays on magenta |
| 65 | `smooth_stone` | smooth stone | plain | flat polished grey stone with a faint border |
| 66 | `bookshelf` | bookshelf side | plain | 2 shelves of book spines in muted colours (no lettering) |

Not wanted from Gemini: water and lava (animated in the shader), glass (procedural), and any item or mob texture.
