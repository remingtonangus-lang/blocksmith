#!/usr/bin/env python3
# Writes docs/audio/sound-list.md: every sound event by its stable file name (mirrors SoundBank.allSounds and Snd.name
# in Sources/Sound.swift), with descriptions, LUFS from docs/status/audio_levels.md and the 40 WORST picks.
#   tools/soundlist.py . docs/audio/sound-list.md
# Update the tables here when Snd gains a case.
import re, sys, os

ROOT = sys.argv[1]
OUT = sys.argv[2]

# ---- levels from docs/status/audio_levels.md (synth take 0) ----
levels = {}
for line in open(os.path.join(ROOT, "docs/status/audio_levels.md")):
    m = re.match(r"\| ([^ |]+) \| (-?[\d.]+) \| (-?[\d.]+|nan) \|", line)
    if m and "/" not in m.group(1):
        try: levels[m.group(1)] = float(m.group(3))
        except ValueError: pass

MATS = ["stone", "dirt", "sand", "wood", "plant", "glass", "snow", "gravel", "metal", "wool", "slime", "mud", "bone", "amethyst", "soul", "sculk", "netherrack", "deepslate", "grass", "leaves"]

# material: (what it is in game, step, break, place, hit, fall, bullet impact)
MAT = {
 "stone": ("stone, cobble, bricks, ores", "hard boot heel on stone: a dry short tap with a little grit scuff, no ring, no thud", "rock cracking apart and chunks clattering down", "a heavy stone block set down firmly: dull knock, tiny grit settle", "pick tapping rock: a short bright chink, dry", "landing on rock: heavy body thud with a hard scuff", "a bullet smacking rock: sharp crack, chips and dust spray"),
 "deepslate": ("deepslate and dark deep rock", "a denser, lower version of stone: dull tap, no ring", "dense rock splitting: deeper crack, heavy chunks", "dense block set down: low knock", "pick on dense rock: low dull chink", "landing on deep rock: thud, low scuff", "bullet into dense rock: low crack and chips"),
 "netherrack": ("Emberdeep rock", "crumbly porous rock underfoot: a soft dry crunch, slightly hollow", "brittle rock crumbling to gravelly bits", "crumbly block set down: soft crunch", "pick on brittle rock: crumbly tick", "landing on crumbly rock: thud and crunch", "bullet into brittle rock: puff of crumbs"),
 "dirt": ("dirt, coarse dirt, farmland, paths", "boot on packed dry earth: a soft dry pat with a little crumb grit; NOT wet", "a clod of earth breaking: soft crumble and pattering crumbs", "a clod set down: soft pat", "shovel/hand into dry earth: short soft scuff", "landing on earth: dull body thump and dirt scuff", "bullet into earth: dull thup and a puff of dirt"),
 "grass": ("grass blocks", "boot on turf: soft dry pat plus a short blade swish/crunch of grass; NOT squelchy", "turf tearing: roots ripping, soil crumbling", "a sod set down: soft pat with a tiny rustle", "hand/shovel on turf: short soft scuff with blade crackle", "landing on turf: dull thump, grass crush", "bullet into turf: dull thup, soil spray"),
 "plant": ("flowers, crops, saplings, grass tufts", "pushing through stems: a short leafy swish", "a stem snapping with a soft leafy rustle", "a plant pressed into soil: soft rustle", "brushing a plant: tiny leafy tick", "landing in plants: thump with a leafy crush", "bullet through leaves: quick leafy rip"),
 "leaves": ("leaves of every tree", "walking on/through leaves: a crisp dry leaf crunch and rustle, no hiss/static", "a leaf clump tearing: crisp rustle with twigs snapping (P89)", "a leaf block set: soft rustle", "hitting leaves: short crisp rustle with a twig tick", "landing in leaves: soft thump with a big crisp rustle", "bullet through foliage: a quick crisp rip and twig snap"),
 "gravel": ("gravel", "boot on loose gravel: a clear dry crunch of many small stones grinding, no water character", "a gravel heap collapsing: pebbles pouring and clattering", "gravel dumped: pebble pour", "shovel into gravel: dry knock with pebble clicks (P118: must not sound like water)", "landing on gravel: thump with a big crunch", "bullet into gravel: crack and a spray of pebbles"),
 "sand": ("sand, red sand", "boot on dry sand: a soft muffled shush-crunch, fine grains", "sand slumping: a soft pour/hiss of grains", "sand set down: soft shush", "shovel into sand: soft gritty scuff", "landing on sand: soft thump and grain spray", "bullet into sand: soft thup and grain hiss"),
 "snow": ("snow, snow blocks, powder snow", "boot in dry snow: the squeaky compressed crunch of cold snow", "snow block crumbling: soft crunch and powder fall", "snow packed down: muffled crunch", "hitting snow: soft crunchy tick", "landing in snow: muffled thump with compressed crunch", "bullet into snow: soft puff"),
 "wood": ("planks, logs, doors, wooden objects", "boot on wooden boards: a hollow knock with a slight board give, short", "wood splintering: crack, fibres tearing, planks clattering", "a wooden block set: hollow knock", "axe/hand on wood: a short hollow tock", "landing on boards: thud with a hollow board boom", "bullet into wood: thock and splinters"),
 "metal": ("iron blocks, steel plating, anvils, rails", "boot on steel plate: a dull clank with a brief metallic ring (damped, not a bell)", "metal plates wrenched apart: clang and scraping", "a metal block set: solid clank", "pick on metal: a bright tink, short", "landing on steel deck: heavy clang-thud", "bullet on steel: a sharp ping/spang with a short whine"),
 "glass": ("glass, panes, ice-like glassy blocks", "boot on glass: a hard, slightly bright tap, faint ring", "glass shattering: crash and tinkling shards", "glass set down: light clink", "tapping glass: thin clink", "landing on glass: hard thud with a clink", "bullet through glass: crack and shard tinkle"),
 "wool": ("wool, carpet, beds", "boot on carpet: a muffled soft pad, almost silent", "fabric tearing softly", "wool dropped: soft pad", "hitting wool: soft muffled thup", "landing on wool: soft muffled thump", "bullet into cloth: soft thup"),
 "slime": ("slime blocks", "stepping on slime: a springy wet squelch", "a slime block popping apart: wet splat", "slime set: wet plop", "poking slime: small wet squish", "landing on slime: big bouncy squelch", "bullet into slime: wet splat"),
 "mud": ("mud", "boot sinking into mud: a thick wet squelch with suction on lift-off (this one SHOULD be wet)", "mud clod tearing: wet slop", "mud slapped down: wet slap", "shovel into mud: wet squelch", "landing in mud: heavy wet splat", "bullet into mud: wet thup"),
 "bone": ("bone blocks", "boot on bone: a dry hollow clack", "bone cracking: brittle snap and clatter", "bone block set: dry clack", "tapping bone: hollow clack", "landing on bone: thud and dry clack", "bullet into bone: crack and splinter"),
 "amethyst": ("amethyst / crystal blocks", "stepping on crystal: a hard tap with a soft glassy chime", "crystal breaking: crack and ringing chime shards", "crystal set: chime", "tapping crystal: a short pure chime", "landing on crystal: thud and chime", "bullet into crystal: crack and chime"),
 "soul": ("soul sand / soul soil (Ghost Valley)", "stepping on soul sand: a dry sandy shush with an eerie faint hollow moan", "soul sand slumping: dry pour with a breathy whisper", "soul sand set: soft shush", "hitting soul sand: dry gritty scuff", "landing on soul sand: soft thump, grain spray", "bullet into soul sand: soft thup"),
 "sculk": ("sculk (deep dark growth)", "stepping on sculk: a soft rubbery, slightly wet squish", "sculk tearing: fleshy rip", "sculk set: soft squish", "poking sculk: small rubbery tick", "landing on sculk: soft squishy thump", "bullet into sculk: wet thup"),
}

def mat_lines(m):
    lab, st, br, pl, hi, fa, im = MAT[m]
    return {
      f"step_{m}": f"Footstep on {lab} (player, mobs, other players). {st}.",
      f"break_{m}": f"A {m} block breaks. {br}.",
      f"place_{m}": f"A {m} block is placed. {pl}.",
      f"hit_{m}": f"Mining tick on {m} (repeats ~4/s while digging). {hi}; must not tire the ear.",
      f"fall_{m}": f"Landing on {m} after a fall. {fa}.",
      f"bullet_impact_{m}": f"A bullet hits {m}. {im}.",
    }

ARMOR = ["leather: soft leather creak and strap buckle", "chainmail: a jingle of rings", "iron: clanky plate clicks", "gold: soft bright metal clinks", "diamond: hard glassy clinks", "duskium (top-tier armour): heavy dark plate clunk"]
PROF = ["armorer", "butcher", "cartographer", "cleric", "farmer", "fisherman", "fletcher", "leatherworker", "librarian", "mason", "shepherd", "toolsmith", "weaponsmith"]
PROF_WORK = {
 "armorer": "blast furnace roar and hammer tap", "butcher": "cleaver chop on a smoker board", "cartographer": "pen scratch and paper rustle",
 "cleric": "brewing bubbles and a glass clink", "farmer": "compost scoop and shuffle", "fisherman": "barrel lid knock and splash",
 "fletcher": "feather fletching and wood whittle", "leatherworker": "cauldron stir and leather slap", "librarian": "lectern page flip",
 "mason": "chisel tapping stone", "shepherd": "loom shuttle clack", "toolsmith": "smithing table hammer clink", "weaponsmith": "grindstone sharpening scrape"}

GUN = {
 0: ("Donnerkeil Service Rifle (gun_rifle)", "a punchy, mid-heavy assault-rifle crack with a short outdoor slap and a casing tinkle; must work in rapid auto fire"),
 1: ("Hummel Machine Gun (gun_smg, retired)", "a short, bright, light SMG report; fast auto"),
 2: ("Brecher Shotgun", "a big wide 12-gauge boom with a low thump, then a pump-action rack"),
 3: ("Fernblick Rifle and Longwatch Rifle (sniper)", "a supersonic snap with a heavy deep boom and a long rolling tail, then the bolt worked"),
 4: ("Himmelsturm Launcher (rockets)", "an ignition thump then a hissing whoosh of the rocket leaving the tube"),
 5: ("Blitzlanze Arc Gun (energy beam)", "a capacitor whine rising, a crackling electric discharge, a zappy tail; sci-fi but physical"),
 6: ("generic soldier reload", "magazine out, magazine in, charging handle: brisk mechanical clicks"),
 7: ("dry fire (empty trigger)", "a hollow trigger/hammer click, dry and close"),
 8: ("ricochet", "a spark tick then a whining bullet glide away"),
 9: ("deck gun / naval gun / tank main gun", "a huge cannon boom, a chest-pressure thump and a long rolling echo tail"),
 10: ("Steelhold base alarm", "a two-tone klaxon sweep, twice, over loudspeakers"),
 11: ("soldier radio call", "a radio squelch, a short burst of band-limited speech, squelch out"),
 12: ("turret traverse whine", "a servo motor whine as a gun mount turns"),
 13: ("Falke Pistol, Sechser Revolver, Wren Pistol, Breaker Revolver (sidearms)", "a sharp, light pistol crack with a quick slide/hammer cycle"),
}
ASH = {16: ("Kessel Bolt Rifle", "a heavy full-power rifle crack, long rolling tail, then the bolt worked"),
       17: ("Hagel Machine Pistol (retired)", "a low, round, slow-cycling pistol-calibre pop"),
       18: ("Sturmwind Carbine and Slatefall Carbine", "a hard mid crack between a rifle and a machine pistol"),
       19: ("Kettensturm Machine Gun (Ashsaw) and Slate Repeater", "a very short, dry, ripping crack; at its rate the shots run together into a tearing buzz")}
EXTRA_GUN = {14: ("magazine seated", "a magazine seating with a firm thunk and the bolt slamming home (bright double clack); must read clearly (R7)"),
             15: ("last round fired", "a hollow metallic ping as the bolt locks open")}
RELOAD = {0: "rifle: mag release, mag out, new mag in, charging handle", 1: "machine gun: mag out/in, bolt slap", 2: "shotgun: three shells thumbed in, then the pump",
          3: "sniper: bolt up/back, round in, bolt forward/down", 4: "launcher: heavy tube latch, rocket slides in, power-up chirp", 5: "arc gun: cell ejected, new cell in, capacitor charge whine",
          13: "pistol/revolver: mag out/in and slide release (revolver: gate, rounds, gate)", 16: "Kessel: bolt open, five rounds from a stripper clip, clip flicked away, bolt closed",
          17: "machine pistol: mag swap and bolt", 18: "carbine: mag swap and charging handle", 19: "Ashsaw: feed cover up, belt laid in, cover slammed, bolt charged"}
BARK = {"alert": "spotted you: a sharp shouted warning", "attack": "a battle cry / order to fire", "reload": "calling a reload", "grenade": "shouting a grenade warning",
        "hurt": "a pained grunt or shout", "death": "a dying cry, cut short", "idle": "idle patrol chatter or a mutter", "retreat": "calling a fallback"}
RANK = ["Recruit (young, nervous voice)", "Trooper (seasoned, firm voice)", "Marksman (calm, clipped voice)", "Ironclad (big armoured heavy, deep muffled voice through a helmet)"]
RANK_STEP = ["light boots on hard ground", "combat boots with webbing rattle", "soft careful boots", "heavy armoured boots with plate clank"]
HOOF = {"stone": "a horseshoe on stone or brick: a sharp hard clop with a metallic edge, clear (P49: on capital brick it sounds cheap today)",
        "wood": "a hoof on wooden boards: a hollow knock", "earth": "a hoof on dirt or turf: a dull soft thud with a little crumb",
        "sand": "a hoof in sand: a muffled soft thud with grain spray", "snow": "a hoof in snow: a muffled compressed crunch", "water": "a hoof in shallow water: a splash"}

# Mob display names and voice character.
MOB = [
 ("cow", "Cow", "a low, relaxed bovine moo"), ("sheep", "Sheep", "a nasal sheep bleat"), ("chicken", "Chicken", "chicken clucks and a short cackle"),
 ("pig", "Pig", "pig grunts and snorts"), ("zombie", "Zombie", "a slow guttural undead groan"), ("skeleton", "Skeleton", "dry bone rattles and clacks, no voice"),
 ("creeper", "Powderwight", "a quiet dry rustle/hiss (it is mostly silent until it fuses)"), ("spider", "Spider", "a dry chittering hiss and clicking mandibles"),
 ("enderman", "Voidwalker", "a deep, warped, reversed-sounding vocal warble"), ("slime", "Slime", "wet bouncy squishes"),
 ("zombified_piglin", "Undead Boarling", "a rotten wet pig-like groan"), ("piglin", "Boarling", "snuffly pig-man grunts and mutters"),
 ("ghast", "Wailer", "a huge floating creature's mournful high wail, echoing"), ("blaze", "Cinderwisp", "a crackling fiery breath and metallic rattle"),
 ("magma_cube", "Lava Blob", "hot heavy squelches"), ("wither_skeleton", "Blight Skeleton", "heavier, lower bone rattles"), ("hoglin", "Tusker", "a big boar's deep grunts and snorts"),
 ("piglin_brute", "Boarling Brute", "a big angry pig-man growl"), ("strider", "Magmastrider", "a squeaky, chirping trill"),
 ("ender_dragon", "Hollow Wyrm", "a vast dragon roar"), ("silverfish", "Silverfish", "tiny dry insect clicks"), ("shulker", "Shellsentry", "a shell lid clack with a soft creature peep"),
 ("villager", "Townsperson", "a short wordless murmur 'hmm' (no real words)"), ("iron_golem", "Iron Golem", "a heavy metallic creak and rumble"),
 ("husk", "Dust Zombie", "a dry, raspier zombie groan"), ("stray", "Frost Skeleton", "brittle icy bone rattles"), ("drowned", "Sunken", "a gurgling, waterlogged groan"),
 ("cave_spider", "Cave Spider", "a smaller, higher chittering hiss"), ("witch", "Witch", "a nasal cackle/murmur"), ("pillager", "Marauder", "a gruff wordless grunt/murmur"),
 ("vindicator", "Brigand", "an aggressive gruff mutter"), ("minecart", "Minecart", "(silent)"), ("wither", "Blight", "a multi-headed hollow, howling groan"),
 ("snow_golem", "Snow Golem", "a soft snowy crunch and a hollow pumpkin knock"), ("evoker", "Conjurer", "a scheming low murmur"), ("vex", "Hexling", "a tiny high spectral chitter"),
 ("ravager", "Siegebeast", "a huge beast's growl and snort"), ("zombie_villager", "Zombie Townsperson", "a groan with a murmuring villager tone"),
 ("rabbit", "Rabbit", "tiny sniffs and squeaks"), ("fox", "Fox", "a fox's yips and screech"), ("wolf", "Wolf", "a dog-like pant and bark"),
 ("cat", "Cat", "a domestic cat's meow"), ("ocelot", "Ocelot", "a wild cat's short meow"), ("horse", "Horse", "a real horse's whinny, snort and blow (key animal: the player rides it constantly)"),
 ("donkey", "Donkey", "a donkey's hee-haw bray"), ("mule", "Mule", "a mule's bray-whinny mix"), ("llama", "Llama", "a llama's soft hum and snort"),
 ("trader_llama", "Trader Llama", "a llama's soft hum and snort"), ("camel", "Camel", "a camel's grumbling groan"), ("goat", "Goat", "a goat's bleat (higher, harsher than sheep)"),
 ("panda", "Panda", "a panda's bleaty grunt"), ("polar_bear", "Polar Bear", "a bear's grunt and growl"), ("turtle", "Turtle", "a quiet shuffle and soft creak"),
 ("frog", "Frog", "a frog's croak"), ("tadpole", "Tadpole", "tiny bubbly wiggle"), ("armadillo", "Armadillo", "a small sniffing grunt"),
 ("sniffer", "Snuffler", "a big ancient beast's deep sniff and snort"), ("mooshroom", "Mushroom Cow", "a moo like the cow, slightly earthier"), ("bee", "Bee", "a bee's buzz"),
 ("parrot", "Parrot", "a parrot squawk and chirp"), ("bat", "Bat", "high bat squeaks and wing flutter"), ("allay", "Fetchling", "a little spirit's sweet humming trill"),
 ("axolotl", "Axolotl", "a soft squeaky chirp under water"), ("squid", "Squid", "soft watery squelch and bubbles"), ("glow_squid", "Glow Squid", "soft watery squelch, a bit brighter"),
 ("dolphin", "Dolphin", "dolphin clicks and whistles"), ("cod", "Cod", "a fish flop and bubbles"), ("salmon", "Salmon", "a fish flop and bubbles"),
 ("tropical_fish", "Tropical Fish", "a small flop and bubbles"), ("pufferfish", "Pufferfish", "a puff-up inflate and bubbles"),
 ("wandering_trader", "Wandering Trader", "a traveller's wordless murmur"), ("skeleton_horse", "Skeleton Horse", "a hollow, rattly ghostly whinny"),
 ("phantom", "Nightwing", "a screeching swooping cry"), ("guardian", "Spikefish", "a watery grunt and laser-eye hum"), ("elder_guardian", "Elder Spikefish", "a deeper, bigger watery groan"),
 ("endermite", "Voidmite", "tiny clicky insect scratches"), ("warden", "Deep Stalker", "a monstrous deep growl and chest rumble"), ("breeze", "Gustling", "a whirling wind creature's whoosh"),
 ("bogged", "Mire Skeleton", "damp, mossy bone rattles"), ("zoglin", "Rot Tusker", "a rotten boar's snarl"), ("boat", "Boat", "(silent)"), ("armor_stand", "Armor Stand", "(silent)"),
 ("creaking", "Barkwraith", "a living tree's creaking wood groan"), ("zombie_horse", "Zombie Horse", "a rotten, gurgling whinny"), ("illusioner", "Mirage Caster", "a sly magical murmur"),
 ("happy_ghast", "Cloudwailer", "a gentle, cooing big-creature trill"), ("parched", "Sunscorched Skeleton", "dry sun-baked bone rattles"), ("camel_husk", "Dust Camel", "a dry undead camel groan"),
 ("nautilus", "Nautilus", "a soft shell knock and bubbles"), ("zombie_nautilus", "Sunken Nautilus", "a rotten bubbling knock"),
 ("soldier_recruit", "Steelhold Recruit", "a young soldier's grunt (speech barks are the soldier_* files)"), ("soldier_trooper", "Steelhold Trooper", "a soldier's grunt"),
 ("soldier_marksman", "Steelhold Marksman", "a soldier's grunt"), ("soldier_ironclad", "Steelhold Ironclad", "a big armoured soldier's deep grunt through a helmet"),
 ("deck_gun", "Deck Gun", "a mounted gun's mechanical clank/servo (no voice)"), ("copper_golem", "Copper Golem", "small copper clicks and a tinny chirp"),
 ("soldier_officer", "Capital Officer", "an officer's grunt"), ("soldier_crew", "Vehicle Crew", "a crewman's grunt"),
 ("ash_tank", "Ashguard Tank", "a tank's diesel engine and track squeal"), ("ash_halftrack", "Ashguard Halftrack", "a halftrack's engine and track clank"),
 ("ash_artillery", "Ashguard Artillery", "an artillery piece's mechanical clank"), ("ash_truck", "Ashguard Truck", "a truck engine"),
 ("ash_marshal", "Ash Marshal", "a hard commander's grunt"), ("ash_behemoth", "Ash Behemoth (super-heavy tank)", "a massive tank engine and grinding tracks"),
 ("ash_chancellor", "Ash Chancellor", "a cold commanding voice grunt"), ("brand_squire", "Brand Squire (hell knight)", "a knight's grunt through a visor"),
 ("brand_knight", "Brand Knight", "a heavy knight's grunt through a visor"), ("brand_champion", "Brand Champion", "a brutal armoured growl"),
 ("brand_commander", "Brand Commander", "a demonic commanding roar"), ("searwing", "Searwing", "a fiery bird-like screech"), ("scorchling", "Scorchling", "a tiny fiery squeak"),
 ("slagthrower", "Slagthrower", "a molten heavy rumble"),
]
SILENT = {"minecart", "boat", "armor_stand", "end_crystal"}
# end_crystal is in MobKind too (silent); listed for completeness only.
HOSTILE_FRIENDLY = {}
MOBSOUND = {"ambient": "idle call", "hurt": "hurt", "death": "death"}
def mob_desc(name, voice, s):
    if s == "ambient": return f"{name} idle call, every few seconds nearby: {voice}."
    if s == "hurt": return f"{name} is hit: a short sharp pained version of its voice ({voice}), 0.2-0.6 s."
    return f"{name} dies: a longer falling cry of its voice ({voice}), then silence; 0.5-2 s."

ONE = {
 # Player
 "splash": ("players", "Player or mob falls into water", "a body plunging into water: a full splash with spray and bubbles"),
 "swim": ("players", "Swimming stroke", "an arm stroke through water: a soft slosh"),
 "land": ("players", "Generic landing (no material)", "a body landing: dull heavy thump"),
 "hurt": ("players", "Player takes damage", "a short male/neutral pained grunt over a body impact (needs real voice; 3+ takes)"),
 "hurtFall": ("players", "Player takes fall damage", "a hard landing crunch plus a pained grunt"),
 "hurtDrown": ("players", "Player drowning damage", "a choked gurgle with bubbles"),
 "hurtFire": ("players", "Player burning damage", "a sharp pained hiss of breath with fire crackle"),
 "playerDeath": ("players", "Player dies", "a final pained cry and a body collapsing to the ground"),
 "eat": ("players", "Eating food", "three chewy bites/crunches"),
 "burp": ("players", "After finishing a meal", "a short burp"),
 "drink": ("players", "Drinking a potion/milk", "gulping swallows"),
 "pickup": ("players", "Item picked up", "a soft short 'pop' (game-y, keep subtle and pleasant)"),
 "dig": ("players", "Generic dig scuff", "a short soft dig scuff"),
 "attack": ("players", "Melee hit lands", "a weapon swing whoosh into a meaty body hit"),
 "attackSweep": ("players", "Sweeping sword attack", "a wide sword whoosh"),
 "attackCrit": ("players", "Critical melee hit", "a harder, sharper body hit with a slight metallic ring"),
 "attackKnockback": ("players", "Knockback hit", "a heavy shove-hit thud"),
 "attackWeak": ("players", "Weak/uncharged hit", "a light swish and soft tap"),
 "shieldBlock": ("players", "Shield blocks a hit", "a wooden shield struck: solid knock with a metal rim ring"),
 "shieldBreak": ("players", "Shield breaks", "a wooden shield splintering"),
 "itemBreak": ("players", "A tool wears out and breaks", "a small snap and a metal tink"),
 "bucketFill": ("players", "Bucket filled with water", "water glugging into a metal bucket"),
 "bucketEmpty": ("players", "Bucket emptied of water", "water pouring out and splashing"),
 "bucketFillLava": ("players", "Bucket filled with lava", "thick molten lava glooping into a bucket"),
 "bucketEmptyLava": ("players", "Bucket emptied of lava", "heavy molten pour with a hiss"),
 "fishCast": ("players", "Fishing rod cast", "a rod whip and line whizz"),
 "fishSplash": ("players", "Fish bites the bobber", "a small splash of the bobber pulled under"),
 "fishReel": ("players", "Reeling in", "line ratchet and a small splash out of the water"),
 "xp": ("players", "Experience orb collected", "a small bright pleasant chime (game-y)"),
 "levelUp": ("players", "Level up", "a short rising rewarding chime arpeggio"),
 "totem": ("players", "Totem of undying saves you", "a magical rising shimmer and swell"),
 "gasp": ("players", "Surfacing for air after being underwater", "a sharp in-breath gasp"),
 "throwItem": ("players", "Throwing an item", "a short throw whoosh"),
 "pearlThrow": ("players", "Throwing a void pearl", "a whoosh with a faint rising magic tone"),
 "potionThrow": ("players", "Throwing a splash potion", "a whoosh with a glass bottle clink"),
 "potionSplash": ("players", "Splash potion shatters", "a glass bottle smashing with a liquid splash"),
 "snowballHit": ("players", "Snowball hits", "a soft snowy puff/thup"),
 "eggCrack": ("players", "Thrown egg breaks", "an eggshell crack and splat"),
 "bowDraw": ("players", "Drawing a bow", "string stretch and bow-limb creak"),
 "bow": ("players", "Bow released", "a string twang and arrow whoosh"),
 "arrowHit": ("players", "Arrow hits something", "an arrow thunk into a target"),
 "crossbowLoad": ("players", "Loading a crossbow", "a crank/ratchet and the string clicking into the latch"),
 "crossbowShoot": ("players", "Crossbow fired", "a hard mechanical twang and bolt whoosh"),
 "tridentThrow": ("players", "Trident thrown", "a heavy spear whoosh"),
 "tridentHit": ("players", "Trident hits", "a heavy metal spear impact with ring"),
 "tridentReturn": ("players", "Loyal trident returns", "a whooshing magical return"),
 "riptide": ("players", "Riptide launch", "a big rushing water surge"),
 "windCharge": ("players", "Wind charge bursts", "a sudden air blast whump"),
 "shearsSnip": ("players", "Shears used", "a metal scissor snip"),
 "ignite": ("players", "Flint and steel lights a fire", "a flint strike scrape and a small fire catching (whoomph)"),
 "spyglass": ("players", "Spyglass raised", "a brass telescope sliding/extending click"),
 "goatHorn": ("players", "Goat horn blown", "a long, low, haunting horn call"),
 "plantBrush": ("players", "Walking through tall plants and bushes", "a leafy swish of stems against legs"),
 "meleeWindUp": ("hostile", "Enemy winds up a melee attack (telegraph)", "a drawn breath and the scrape of a weapon going back"),
 "parryClang": ("players", "Parry: weapon blocks weapon", "steel on steel: a bright clang"),
 "bowCreak": ("players", "Bow held drawn", "a slow wooden limb groan"),
 "bowNock": ("players", "Arrow nocked", "a small click of the arrow on the string"),
 # UI
 "click": ("ui", "Menu button press", "a short soft UI click, neutral and pleasant"),
 "open": ("ui", "Menu/inventory opens", "a soft UI whoosh-click"),
 "uiHover": ("ui", "Pointer moves over a button", "a very short faint tick"),
 "uiBack": ("ui", "Menu back/close", "a soft lower click"),
 "toast": ("ui", "Notification/advancement toast", "a short friendly two-note chime"),
 # Doors etc
 "doorOpen": ("blocks", "Wooden door opens", "a wooden door: latch click and a short hinge creak"),
 "doorClose": ("blocks", "Wooden door closes", "a wooden door shutting: knock into the frame and latch"),
 "ironDoorOpen": ("blocks", "Iron door opens", "a heavy iron door grinding open"),
 "ironDoorClose": ("blocks", "Iron door closes", "a heavy iron door clanging shut"),
 "trapdoorOpen": ("blocks", "Wooden trapdoor opens", "a light wooden hatch flipping open"),
 "trapdoorClose": ("blocks", "Wooden trapdoor closes", "a wooden hatch slapping shut"),
 "ironTrapdoorOpen": ("blocks", "Iron trapdoor opens", "a metal hatch opening with a clank"),
 "ironTrapdoorClose": ("blocks", "Iron trapdoor closes", "a metal hatch clanging shut"),
 "gateOpen": ("blocks", "Fence gate opens", "a wooden gate creak and latch"),
 "gateClose": ("blocks", "Fence gate closes", "a wooden gate knocking shut"),
 "chestOpen": ("blocks", "Chest opens", "a wooden chest lid creaking open"),
 "chestClose": ("blocks", "Chest closes", "a wooden chest lid thumping shut"),
 "enderChestOpen": ("blocks", "Void chest opens", "a heavy stone lid with a magical shimmer"),
 "enderChestClose": ("blocks", "Void chest closes", "a heavy stone lid closing with a shimmer"),
 "barrelOpen": ("blocks", "Barrel opens", "a wooden barrel lid knock"),
 "barrelClose": ("blocks", "Barrel closes", "a wooden barrel lid set down"),
 "shulkerOpen": ("blocks", "Shell box opens", "a shell lid sliding open"),
 "shulkerClose": ("blocks", "Shell box closes", "a shell lid sliding shut"),
 "pistonExtend": ("blocks", "Piston pushes", "a mechanical push: whoosh of air and a stone shove"),
 "pistonContract": ("blocks", "Piston retracts", "a mechanical pull back with a clack"),
 "lever": ("blocks", "Lever switched", "a stiff mechanical click"),
 "buttonWood": ("blocks", "Wooden button pressed", "a soft wooden click"),
 "buttonStone": ("blocks", "Stone button pressed", "a hard stone click"),
 "plateOn": ("blocks", "Pressure plate pressed", "a soft plate click down"),
 "plateOff": ("blocks", "Pressure plate released", "a soft plate click up"),
 "dispense": ("blocks", "Dispenser/dropper fires", "a mechanical clack and launch"),
 "dispenseFail": ("blocks", "Dispenser empty", "two dry empty clicks"),
 "tripwire": ("blocks", "Tripwire triggered", "a taut string twang/click"),
 "fizz": ("blocks", "Water meets lava / fire put out", "a steam hiss"),
 "anvil": ("blocks", "Anvil used", "a hammer strike on an anvil: bright ringing clang"),
 "anvilLand": ("blocks", "Falling anvil lands", "a heavy iron mass hitting ground: clang-thud"),
 "anvilBreak": ("blocks", "Anvil breaks", "cracking iron and falling pieces"),
 "enchant": ("blocks", "Item enchanted", "a magical sparkly shimmer"),
 "brew": ("blocks", "Brewing stand finishes", "bubbling glass and a fizz"),
 "grindstone": ("blocks", "Grindstone used", "a stone wheel grinding metal: scrape and sparks"),
 "smithing": ("blocks", "Smithing table upgrade", "metal hammer taps on a workbench"),
 "pageTurn": ("blocks", "Book page turned", "a paper page flip"),
 "composterFill": ("blocks", "Composter filled", "organic matter dropped into a wooden bin"),
 "composterReady": ("blocks", "Composter ready", "a soft rustle and a small pop"),
 "itemFrameAdd": ("blocks", "Item put in frame", "a light wooden frame tap"),
 "itemFrameRemove": ("blocks", "Item taken from frame", "a light wooden frame knock"),
 "itemFrameRotate": ("blocks", "Item in frame rotated", "a tiny click"),
 "paintingPlace": ("blocks", "Painting hung", "a canvas bump on the wall"),
 "paintingBreak": ("blocks", "Painting knocked off", "canvas and frame clatter"),
 "honeySlide": ("blocks", "Sliding down honey", "a sticky slow slide"),
 "amethystChime": ("blocks", "Crystal chimes when touched", "soft random crystal chimes"),
 "waxOn": ("blocks", "Waxing copper", "a waxy rub"),
 "waxOff": ("blocks", "Scraping wax off", "a scraping rub"),
 "scrape": ("blocks", "Scraping oxidation off copper", "an axe scraping metal"),
 "bulbOn": ("blocks", "Copper bulb turns on", "an electric click and hum-on"),
 "bulbOff": ("blocks", "Copper bulb turns off", "an electric click-off"),
 "crafterCraft": ("blocks", "Auto-crafter crafts", "mechanical clatter and a pop"),
 "crafterFail": ("blocks", "Auto-crafter fails", "two dull clicks"),
 "vaultOpen": ("blocks", "Vault opens", "a heavy metal mechanism unlocking"),
 "vaultEject": ("blocks", "Vault ejects loot", "a metallic pop and item spit"),
 "vaultReject": ("blocks", "Vault rejects a key", "a dull refusal clunk"),
 "spawnerSpawn": ("blocks", "Spawner spawns a mob", "a fiery whoosh/puff"),
 "potBreak": ("blocks", "Decorated pot shatters", "ceramic pot smashing"),
 "potInsert": ("blocks", "Item put in pot", "an item clinking into a ceramic pot"),
 "bundleInsert": ("blocks", "Item put in bundle", "a leather pouch rustle"),
 "bundleRemove": ("blocks", "Item taken from bundle", "a leather pouch rustle out"),
 "bedEnter": ("blocks", "Getting into bed", "a body settling on a mattress and blanket rustle"),
 "candleOut": ("blocks", "Candle blown out", "a short soft blow"),
 "lanternHang": ("blocks", "Lantern placed", "a metal lantern clink on a chain"),
 "respawnAnchorCharge": ("blocks", "Respawn anchor charged", "a deep magical power-up hum"),
 "respawnAnchorSet": ("blocks", "Respawn point set at an anchor", "a magical resonant chime"),
 "sculkClick": ("blocks", "Sculk sensor triggers", "a fleshy organic click"),
 "sculkShriek": ("blocks", "Sculk shrieker shrieks", "an eerie piercing organic shriek"),
 "sculkBloom": ("blocks", "Sculk catalyst blooms", "a soft organic bloom pulse"),
 "sculkSpread": ("blocks", "Sculk spreads", "a soft fleshy squelch spreading"),
 "bell": ("blocks", "Village bell rung", "a bronze bell strike, clear and long"),
 "bellResonate": ("blocks", "Bell resonates (raid nearby)", "a long humming bell resonance"),
 "tntFuse": ("blocks", "TNT fuse lit", "a sizzling burning fuse"),
 "explode": ("blocks", "TNT / Powderwight explosion", "a big close explosion: sharp crack, heavy boom, debris"),
 "glassBreak": ("blocks", "Glass shatters", "a pane shattering"),
 "iceCrack": ("blocks", "Ice cracks", "ice splitting with sharp crackles"),
 "portalTravel": ("blocks", "Travelling through an Emberdeep portal", "a rising, swirling warp whoosh"),
 "portalTrigger": ("blocks", "Standing in a portal (about to travel)", "a swelling warp hum"),
 "endPortalOpen": ("blocks", "Hollow gate opens", "a huge deep rumble and rising magical chord"),
 "endPortalFrame": ("blocks", "Eye placed in a Hollow gate frame", "a stone thunk with a magical ring"),
 "beaconActivate": ("blocks", "Beacon powers on", "a rising magical power-up chord"),
 "beaconPower": ("blocks", "Beacon power chosen", "a short bright magical chime"),
 "beaconDeactivate": ("blocks", "Beacon powers off", "a falling power-down tone"),
 "fireExtinguish": ("blocks", "Fire put out", "a hiss of steam"),
 "lavaPop": ("ambient", "Lava pops near you", "a thick molten bubble bursting"),
 "boatPaddle": ("players", "Paddling a boat", "an oar dipping into water"),
 "railClick": ("blocks", "Rail switches", "a metal rail click"),
 # Mob specials
 "creeperHiss": ("hostile", "Powderwight about to explode (key warning)", "a building, threatening fuse hiss"),
 "fireball": ("hostile", "Fireball launched", "a roaring fiery whoosh"),
 "evokerCast": ("hostile", "Conjurer casting a spell", "a magical incantation shimmer"),
 "fangs": ("hostile", "Conjurer fangs snap out of the ground", "jaw-like bone snaps"),
 "raidHorn": ("hostile", "Raid begins", "a deep ominous war horn"),
 "mobVoidwalker": ("hostile", "Voidwalker stare/scream (legacy name; renders the Voidwalker idle)", "a deep warped vocal warble"),
 "teleport": ("hostile", "Voidwalker/void pearl teleport", "a warpy whoosh-pop"),
 "dragonGrowl": ("hostile", "Hollow Wyrm growl", "a vast dragon growl, carries far"),
 "dragonFlap": ("hostile", "Hollow Wyrm wing beat", "huge leathery wing whoomph"),
 "dragonShoot": ("hostile", "Hollow Wyrm spits acid", "a hissing launch"),
 "dragonDeath": ("hostile", "Hollow Wyrm dies", "a long dying roar rising into light"),
 "crystalBreak": ("hostile", "Hollow Crystal destroyed", "a crystal explosion"),
 "witherSpawn": ("hostile", "Blight summoned", "a huge charging boom and howl"),
 "witherShoot": ("hostile", "Blight fires a skull", "a hollow skull launch"),
 "witherDeath": ("hostile", "Blight dies", "a long ghostly death howl and boom"),
 "wardenHeartbeat": ("hostile", "Deep Stalker heartbeat", "a deep slow heartbeat thump"),
 "wardenRoar": ("hostile", "Deep Stalker roars", "a monstrous roar"),
 "wardenSonicCharge": ("hostile", "Deep Stalker charges its sonic attack", "a rising deep inhale/charge hum"),
 "wardenSonicBoom": ("hostile", "Deep Stalker sonic boom", "a concussive sonic blast"),
 "wardenEmerge": ("hostile", "Deep Stalker emerges", "earth and sculk heaving, a deep groan"),
 "wardenDig": ("hostile", "Deep Stalker digs back down", "earth churning"),
 "wardenSniff": ("hostile", "Deep Stalker sniffs", "a big wet sniff"),
 "elderCurse": ("hostile", "Elder Spikefish curse", "a ghostly underwater wail"),
 "guardianLaser": ("hostile", "Spikefish laser charge", "a rising electric beam whine"),
 "villagerYes": ("friendly", "Townsperson agrees / trade ok", "a pleased short murmur (wordless 'mm-hm')"),
 "villagerNo": ("friendly", "Townsperson refuses", "a displeased short murmur ('mm-mm')"),
 "villagerTrade": ("friendly", "Trade done", "a satisfied murmur"),
 "villagerCelebrate": ("friendly", "Townsfolk celebrate after a raid", "happy cheering murmurs"),
 "zombieBreakDoor": ("hostile", "Zombie bashing a door", "a heavy thump on a wooden door with splintering"),
 "zombieInfect": ("hostile", "Zombie infects a townsperson", "a groan and a sick gurgle"),
 "zombieCure": ("friendly", "Zombie townsperson cured", "a magical sizzle and a relieved sigh"),
 "phantomSwoop": ("hostile", "Nightwing swoops", "a screeching dive whoosh"),
 "beeSting": ("hostile", "Bee stings", "a tiny sharp buzz-sting"),
 "beePollinate": ("friendly", "Bee pollinating", "a contented buzzing loop-let"),
 "allayItem": ("friendly", "Fetchling picks/gives an item", "a sweet little chime"),
 "foxSniff": ("friendly", "Fox sniffs", "a small sniff"),
 "catPurr": ("friendly", "Cat purrs", "a soft purr"),
 "wolfPant": ("friendly", "Wolf pants", "dog panting"),
 "parrotMimic": ("friendly", "Parrot imitates a mob", "a squawky imitation"),
 "dolphinJump": ("friendly", "Dolphin leaps", "a splash and a click"),
 "turtleEggCrack": ("friendly", "Turtle egg cracks", "a small shell crack"),
 "frogTongue": ("friendly", "Frog eats", "a sticky tongue flick"),
 "goatRam": ("friendly", "Goat rams", "a hard head-butt thud"),
 "breezeShoot": ("hostile", "Gustling fires a wind charge", "a whirling air shot"),
 "fireworkLaunch": ("blocks", "Firework launched", "a whistling rocket climbing"),
 "fireworkBlast": ("blocks", "Firework bursts", "a crisp airburst pop"),
 "fireworkBlastLarge": ("blocks", "Large firework bursts", "a big booming airburst"),
 "fireworkTwinkle": ("blocks", "Firework crackle stars", "crackling sparkles"),
 # Weather & ambience one-shots
 "birdCall": ("ambient", "Bird call in forests/plains (day)", "a real songbird phrase (varied species per biome; 6 takes)"),
 "owlHoot": ("ambient", "Owl at night in forests", "a distant owl hoot, two or three notes"),
 "dryGrassRustle": ("ambient", "Wind through dry grass (badlands, savanna)", "a dry grass rustle gust"),
 "heartCreak": ("ambient", "Creaking heart in the pale woods", "an old wood creak with a deep pulse"),
 "caveAmbience": ("ambient", "Cave mood sting", "an eerie low cave rumble/moan, distant and reverberant"),
 "caveDrip": ("ambient", "Water drip in caves", "a single echoing water drip"),
 "caveWind": ("ambient", "Cave draught", "a low breathy wind through a tunnel"),
 "netherMood": ("ambient", "Emberdeep mood sting", "a distant hellish moan and rumble"),
 "underwaterMood": ("ambient", "Underwater mood sting", "a muffled deep whale-like moan"),
 "thunder": ("weather", "Thunder (near)", "a close thunderclap: sharp crack then long rumble"),
 "lightning": ("weather", "Lightning strike", "a very close electrical crack and boom"),
 "windGust": ("weather", "Wind gust", "a passing gust of wind (wind is praised: keep the character)"),
 "thunderFar": ("weather", "Distant thunder", "a far rolling thunder rumble"),
 "iceCreak": ("ambient", "Frozen lakes/tundra", "ice creaking and groaning under pressure"),
 "rockfall": ("ambient", "Mountain rockfall", "stones tumbling down a slope"),
 "volcanoRumble": ("ambient", "Volcano eruption", "a huge deep eruption boom, heard from very far"),
 # Weapons/war
 "bulletWhizz": ("players", "A bullet passes close to you", "a supersonic crack/whizz by the ear"),
 "bulletFlesh": ("players", "A bullet hits a body", "a meaty thwack"),
 "grenadeBounce": ("players", "Grenade bounces", "a metal can clunk on the ground"),
 "rocketFlightLoop": ("players", "Rocket in flight (loop)", "a rocket motor's hissing roar"),
 "shellFlightLoop": ("players", "Heavy shell overhead (loop)", "a tearing whistling whoosh"),
 "shellIncoming": ("players", "Incoming artillery shell", "a falling whistle before impact"),
 "ashSiren": ("hostile", "Ash Vault alarm siren", "a hand-cranked air-raid siren wail, rising and falling"),
 "explodeSmall": ("blocks", "Grenade / small explosion", "a sharp grenade bang with debris"),
 "explodeLarge": ("blocks", "Big explosion (shells, vehicles)", "a massive blast with a long rolling tail"),
 "debrisRain": ("blocks", "Debris pattering down after a blast", "dirt and stones raining down"),
 # Vehicles and ships
 "engineIdleLoop": ("blocks", "Ship/vehicle engine idle (loop; cross-faded with full by throttle)", "a steady low marine/diesel engine idle"),
 "engineFullLoop": ("blocks", "Ship/vehicle engine at full throttle (loop)", "the same engine working hard: louder, higher, rougher"),
 "propSlowLoop": ("blocks", "Propeller at low speed (loop)", "a slow propeller thrum"),
 "propFastLoop": ("blocks", "Propeller at high speed (loop)", "a fast propeller buzz-roar"),
 "airshipWindLoop": ("blocks", "Wind over an airship deck (loop)", "rushing wind with rigging hum"),
 "wheelRollLoop": ("blocks", "Land vehicle wheels rolling (loop)", "tyres/wheels rolling over ground with rattle"),
 "hullWaterLoop": ("blocks", "Water along a moving hull (loop)", "water rushing and slapping along a hull"),
 "wingRushLoop": ("blocks", "Aircraft wing rush (loop)", "fast air tearing over wings"),
 "frigateDroneLoop": ("blocks", "Capital frigate overhead (loop)", "a vast deep engine drone, heard from far"),
 "carriageTreadLoop": ("blocks", "Ironstride Siege Carriage treads (loop)", "heavy tank treads squealing and clanking"),
 "hullCreak": ("blocks", "Ship hull creaks", "wooden hull timbers creaking"),
 "shipCollide": ("blocks", "Ship bumps something", "a hull knock"),
 "shipCollideHard": ("blocks", "Ship crashes", "a heavy hull crash with splintering"),
 "shipSplash": ("blocks", "Ship hits water", "a big hull splash"),
 "helmTake": ("blocks", "Taking the helm", "a wooden wheel grab and creak"),
 "engineStart": ("blocks", "Engine starts", "an engine cranking and catching"),
 "trainWhistle": ("blocks", "Steam train whistle", "a classic steam whistle"),
 "steamChuff": ("blocks", "Steam train chuff", "a steam locomotive chuff"),
 "shipCannon": ("blocks", "Ship cannon fires", "a black-powder cannon boom with a hull shudder"),
 "turretTraverseLoop": ("blocks", "Turret turning (loop)", "a geared turret ring rumble with servo whine"),
 "mainGunCharge": ("blocks", "Tidebreaker main gun charging", "a huge capacitor/charging rise, 3 s"),
 "mainGunFire": ("blocks", "Tidebreaker main gun fires", "an enormous blast heard across the map"),
 "mainGunRumble": ("blocks", "Tidebreaker aftermath rumble", "a long rolling echo across terrain"),
}
LOOPS = {
 "fireLoop": ("ambient", "Fire burning (loop)", "a wood fire crackling and roaring softly"),
 "furnaceLoop": ("ambient", "Lit furnace (loop)", "a contained fire with a low roar"),
 "campfireLoop": ("ambient", "Campfire (loop)", "a cosy campfire crackle and pop"),
 "lavaLoop": ("ambient", "Lava nearby (loop)", "a thick bubbling, rumbling molten pool"),
 "waterLoop": ("ambient", "Flowing water nearby (loop)", "a small stream trickling over stones"),
 "portalLoop": ("ambient", "Emberdeep portal (loop)", "a swirling magical whoosh hum"),
 "beaconLoop": ("ambient", "Active beacon (loop)", "a soft magical power hum"),
 "minecartLoop": ("players", "Riding a minecart (loop)", "iron wheels rolling over rail joints"),
 "elytraLoop": ("players", "Gliding (loop)", "wind rushing past at speed"),
 "underwaterLoop": ("players", "Head under water (loop)", "a muffled underwater pressure hum with distant bubbles"),
 "rain": ("weather", "Rain outdoors (loop)", "steady rain on the ground and foliage"),
 "rainRoof": ("weather", "Rain heard under a roof (loop)", "rain drumming on a roof above"),
 "respawnAnchorLoop": ("ambient", "Charged respawn anchor (loop)", "a low magical thrum"),
 "spawnerLoop": ("ambient", "Monster spawner (loop)", "a small fiery whirl"),
 "netherWastesLoop": ("ambient", "Emberdeep Wastes biome (loop)", "a hot hollow wind and deep drone"),
 "soulValleyLoop": ("ambient", "Ghost Valley biome (loop)", "a ghostly moaning wind"),
 "crimsonLoop": ("ambient", "Rustcap Forest biome (loop)", "a thick low drone with organic bubbles"),
 "warpedLoop": ("ambient", "Tealcap Forest biome (loop)", "an alien hum with glassy bubbles"),
 "basaltLoop": ("ambient", "Basalt Deltas biome (loop)", "a harsh wind with crackling rock"),
 "ashVaultLoop": ("ambient", "The Ash Vault (loop)", "a hot wind under a huge roof, a low engine drone"),
 "endLoop": ("ambient", "The Hollow (loop)", "a vast empty void drone"),
 "deepDarkLoop": ("ambient", "Deep Dark (loop)", "a near-silent deep oppressive rumble"),
 "lushLoop": ("ambient", "Lush caves (loop)", "a soft damp cave air with drips"),
 "dripstoneLoop": ("ambient", "Dripstone caves (loop)", "cave air with echoing drips"),
 "cricketsLoop": ("ambient", "Night in grassland/forest (loop)", "real crickets at night"),
 "oceanLoop": ("ambient", "Ocean/beach (loop)", "waves breaking on a shore"),
 "swampLoop": ("ambient", "Swamp at night (loop)", "frogs croaking with insects"),
 "windLoop": ("ambient", "Open-air wind (loop)", "steady wind (praised: keep the character)"),
 "jungleLoop": ("ambient", "Jungle (loop)", "dense jungle insects and distant birds"),
 "fireflyLoop": ("ambient", "Meadow at night with fireflies (loop)", "a soft magical night shimmer"),
 "hiveLoop": ("ambient", "Beehive/nest (loop)", "many bees buzzing inside wood"),
 "stationHumLoop": ("ambient", "Boreal Station bunker (loop)", "mains hum and fluorescent buzz"),
 "riverLoop": ("ambient", "River (loop)", "a wide river flowing"),
 "waterfallLoop": ("ambient", "Waterfall (loop)", "a falling water roar"),
 "mountainWindLoop": ("ambient", "Mountain peak wind (loop)", "high cold wind whistling over rock"),
 "tundraWindLoop": ("ambient", "Tundra wind (loop)", "a cold flat wind"),
 "rainLeavesLoop": ("weather", "Rain on forest leaves (loop)", "rain pattering on leaves"),
 "snowWindLoop": ("weather", "Snowstorm (loop)", "blizzard wind with blowing snow"),
 "swampInsectsLoop": ("ambient", "Swamp by day (loop)", "buzzing insects and water"),
}

WORST = {
 "step_grass": "owner: footsteps sound like walking through mud (P14, R19); the synth thud + resonated grit still reads wet on the Quest",
 "step_dirt": "same mud complaint (P14, R19): no real crumb texture",
 "step_stone": "resonated contact pulse rings like a tuned block, not a boot on rock",
 "step_gravel": "gravel like water (P118): resonated grains are tiny water drops",
 "hit_gravel": "owner: hitting gravel sounds like punching water (P118)",
 "step_leaves": "band-limited noise swish: reads as static, not crisp leaves",
 "break_leaves": "owner: the leaf-breaking sound sounds wrong (P89); still a noise swish",
 "hit_leaves": "noise rustle repeats 4x/s while cutting: static",
 "step_sand": "filtered noise grains: a hiss, not a sand crunch",
 "step_snow": "missing the squeaky compressed-snow crunch",
 "step_wood": "boxy resonator knock with no board give",
 "hoof_stone": "owner: hooves on capital brick sound cheap (P49)",
 "hoof_earth": "the most-heard horse sound; a noise thud, part of the 'one-cylinder' gallop (R13)",
 "hoof_wood": "a resonator knock; cheap next to the stone and earth fixes",
 "mob_horse_ambient": "formant-synth whinny; the horse is the core companion and it sounds electronic",
 "mob_horse_hurt": "formant squeal; needs a real pained horse",
 "gun_0": "Donnerkeil rifle crack is noise bursts; guns are the main combat feel ('fix the weapons')",
 "gun_13": "one synth crack shared by four sidearms (Falke, Sechser, Wren, Breaker)",
 "gun_2": "Brecher shotgun: noise blast without real low-end weight",
 "gun_3": "Fernblick/Longwatch sniper: synthetic tail, no real supersonic snap",
 "gun_18": "Sturmwind/Slatefall carbine: noise crack",
 "gun_reload_0": "noise-click reload; R7 asks for a clear audible magazine click",
 "gun_14": "magazine-seated cue is the key reload feedback (R7) and is synthesized",
 "bullet_impact_stone": "the most-heard impact; a filtered burst, no chips or dust",
 "bulletFlesh": "noise thwack, not a meaty hit",
 "soldier_1_alert": "formant gibberish where a shouted line should be (all soldier_* barks share this problem)",
 "soldier_1_hurt": "formant grunt, robotic",
 "villagerYes": "formant 'hum' reads as a synth buzz",
 "mob_zombie_ambient": "formant groan; the most common hostile voice",
 "hurt": "player pain grunt is formant synthesis; heard constantly",
 "playerDeath": "synth grunt + noise thud",
 "doorOpen": "creak is a saw-wave pitch sweep: sounds like a synth chirp, not a hinge",
 "chestOpen": "saw-wave 'creak' sweep again",
 "rain": "white-noise rain; the commonest weather loop",
 "waterLoop": "bubble synthesis, sounds like a fish tank",
 "splash": "low-passed noise burst, no real water body",
 "fireLoop": "crackle noise with no flame body",
 "explode": "noise-burst explosion without a real low-end punch or debris",
 "engineIdleLoop": "oscillator engine, buzzy and static",
 "birdCall": "synthesized chirps; obviously fake in every forest",
}
assert len(WORST) == 40, len(WORST)

def lvl(n):
    return f" [{levels[n]:.0f} LUFS]" if n in levels else ""

REPEAT_PREFIX = ("step_", "hit_", "hoof_", "soldier_step_", "bullet_impact_", "gun_", "break_", "place_", "fall_")

lines_out = []
seen = set()
counts = {}
def item(name, cat, event, desc):
    assert name not in seen, name
    seen.add(name)
    desc = desc.rstrip(".")
    w = f" **WORST** ({WORST[name]})" if name in WORST else ""
    takes = ""
    if name.startswith(("step_", "hit_", "hoof_", "soldier_step_", "bullet_impact_")) or name in ("bulletFlesh", "attack", "attackWeak", "attackCrit", "hurt") or re.match(r"gun_(\d+)$", name) and int(name[4:]) not in (6, 7, 10, 11, 12, 14, 15):
        takes = " Record 3-5 takes."
    return f"- `{name}` ({cat}){lvl(name)}: {event}. {desc[0].upper() + desc[1:]}.{takes}{w}"

sections = []
def section(title, intro, items):
    sections.append((title, intro, items))

# Footsteps
section("Footsteps", "Your own steps play dry at your feet; other players' and mobs' steps play in the world. Every surface below repeats constantly: record 3-5 takes each (heel + toe roll in one take, 0.15-0.35 s).",
        [item(f"step_{m}", "players", MAT[m][0], MAT[m][1]) for m in MATS] +
        [item(f"soldier_step_{r}", "hostile", f"Steelhold soldier footstep, {RANK[r].split(' (')[0]}", RANK_STEP[r]) for r in range(4)])
section("Horses", "Hoof falls by ground type (HorseLife), then the horse family voices. The gallop plays four hoof falls per stride: record 4-5 takes per surface, each a single hoof.",
        [item(f"hoof_{s}", "friendly", f"A hoof fall on {s}", HOOF[s]) for s in ["stone", "wood", "earth", "sand", "snow", "water"]] +
        [item(f"mob_{k}_{s}", "friendly", f"{n} {MOBSOUND[s]}", mob_desc(n, v, s)) for k, n, v in MOB if k in ("horse", "donkey", "mule", "skeleton_horse", "zombie_horse") for s in ["ambient", "hurt", "death"]] +
        [item("baby_horse_ambient", "friendly", "Foal idle call", "a foal's higher, lighter whinny")])
# Blocks
blk = []
for m in MATS:
    d = mat_lines(m)
    for ev in ("break", "place", "hit", "fall"):
        n = f"{ev}_{m}"
        blk.append(item(n, "blocks" if ev != "fall" else "players", d[n].split(". ")[0], ". ".join(d[n].split(". ")[1:]).rstrip(".")))
section("Blocks by material", "Break, place, mining tick and landing per material (SoundMat). The block's in-game name is what the material covers.", blk)
# Guns
g = []
for k in list(range(0, 14)):
    nm, ds = GUN[k]
    g.append(item(f"gun_{k}", "players", nm, ds))
for k in (16, 17, 18, 19):
    nm, ds = ASH[k]
    g.append(item(f"gun_{k}", "players", nm, ds))
section("Guns: shots and gun mechanics", "gun_<n> is the Snd.gun slot (Guns.swift GunSpec.sound). Shots repeat in auto fire: 3-5 takes each, close-mic'd dry; the engine adds distance and reverb. gun_14 and gun_15 are rendered on demand (not in the prewarm list) but are real events.", g + [item(f"gun_{k}", "players", EXTRA_GUN[k][0], EXTRA_GUN[k][1]) for k in (14, 15)])
r = []
for k in [0, 1, 2, 3, 4, 5, 13, 16, 17, 18, 19]:
    r.append(item(f"gun_reload_{k}", "players", f"Reload, {(GUN.get(k) or ASH.get(k))[0]}", RELOAD[k]))
section("Reloads", "Full reload sequences, timed to the reload animation (0.4-2.5 s).", r)
d = []
for k in [0, 1, 2, 3, 4, 5, 13, 16, 17, 18, 19, 9]:
    nm = (GUN.get(k) or ASH.get(k))[0]
    d.append(item(f"gun_distant_{k}", "players", f"Distant shot, {nm} (heard 50-220 blocks away)", "the same weapon far off: a low thump/boom with a long outdoor echo, no crack"))
section("Distant gunfire", "Played instead of the close shot beyond ~48 blocks.", d)
section("Bullets, explosions and war", "", [item(n, *ONE[n]) for n in ["bulletWhizz", "bulletFlesh", "grenadeBounce", "rocketFlightLoop", "shellFlightLoop", "shellIncoming", "ashSiren", "explodeSmall", "explodeLarge", "debrisRain"]] +
        [item(f"bullet_impact_{m}", "players", f"Bullet impact on {m}", MAT[m][6]) for m in MATS])
sb = []
for rk in range(4):
    for b in ["alert", "attack", "reload", "grenade", "hurt", "death", "idle", "retreat"]:
        sb.append(item(f"soldier_{rk}_{b}", "hostile", f"Steelhold {RANK[rk].split(' (')[0]}: {b}", f"{BARK[b]}; voice: {RANK[rk].split('(')[1].rstrip(')')}; original lines, no real-army slogans"))
section("Soldier voices (Steelhold barks)", "Spoken barks per rank. 3-4 different lines per bark (idle 4).", sb)
# Player
pl = ["splash", "swim", "land", "hurt", "hurtFall", "hurtDrown", "hurtFire", "playerDeath", "eat", "burp", "drink", "pickup", "dig", "attack", "attackSweep", "attackCrit", "attackKnockback", "attackWeak", "shieldBlock", "shieldBreak", "itemBreak",
      "bucketFill", "bucketEmpty", "bucketFillLava", "bucketEmptyLava", "fishCast", "fishSplash", "fishReel", "xp", "levelUp", "totem", "gasp", "throwItem", "pearlThrow", "potionThrow", "potionSplash", "snowballHit", "eggCrack", "bowDraw", "bow", "arrowHit", "crossbowLoad", "crossbowShoot",
      "tridentThrow", "tridentHit", "tridentReturn", "riptide", "windCharge", "shearsSnip", "ignite", "spyglass", "goatHorn", "plantBrush", "meleeWindUp", "parryClang", "bowCreak", "bowNock", "boatPaddle"]
section("Player actions and combat", "", [item(n, *ONE[n]) for n in pl] + [item(f"armor_equip_{t}", "players", "Armour put on", ARMOR[t]) for t in range(6)])
section("Interface", "Never spatialized; keep them short, soft and dry.", [item(n, *ONE[n]) for n in ["click", "open", "uiHover", "uiBack", "toast"]])
mech = ["doorOpen", "doorClose", "ironDoorOpen", "ironDoorClose", "trapdoorOpen", "trapdoorClose", "ironTrapdoorOpen", "ironTrapdoorClose", "gateOpen", "gateClose",
        "chestOpen", "chestClose", "enderChestOpen", "enderChestClose", "barrelOpen", "barrelClose", "shulkerOpen", "shulkerClose",
        "pistonExtend", "pistonContract", "lever", "buttonWood", "buttonStone", "plateOn", "plateOff", "dispense", "dispenseFail", "tripwire", "fizz",
        "anvil", "anvilLand", "anvilBreak", "enchant", "brew", "grindstone", "smithing", "pageTurn", "composterFill", "composterReady",
        "itemFrameAdd", "itemFrameRemove", "itemFrameRotate", "paintingPlace", "paintingBreak", "honeySlide", "amethystChime",
        "waxOn", "waxOff", "scrape", "bulbOn", "bulbOff", "crafterCraft", "crafterFail", "vaultOpen", "vaultEject", "vaultReject", "spawnerSpawn",
        "potBreak", "potInsert", "bundleInsert", "bundleRemove", "bedEnter", "candleOut", "lanternHang", "respawnAnchorCharge", "respawnAnchorSet",
        "sculkClick", "sculkShriek", "sculkBloom", "sculkSpread", "bell", "bellResonate", "tntFuse", "explode", "glassBreak", "iceCrack",
        "portalTravel", "portalTrigger", "endPortalOpen", "endPortalFrame", "beaconActivate", "beaconPower", "beaconDeactivate", "fireExtinguish", "railClick",
        "fireworkLaunch", "fireworkBlast", "fireworkBlastLarge", "fireworkTwinkle"]
section("Doors, containers, mechanisms and workblocks", "", [item(n, *ONE[n]) for n in mech])
section("Water and lava", "Water events live in several groups; collected here. (splash, swim, bucket*, fish*, boatPaddle, riptide are listed above under player actions.)",
        [item(n, *LOOPS[n]) for n in ["waterLoop", "riverLoop", "waterfallLoop", "oceanLoop", "underwaterLoop", "lavaLoop"]] + [item(n, *ONE[n]) for n in ["lavaPop", "underwaterMood"]])
section("Weather", "", [item(n, *LOOPS[n]) for n in ["rain", "rainRoof", "rainLeavesLoop", "snowWindLoop"]] + [item(n, *ONE[n]) for n in ["thunder", "thunderFar", "lightning", "windGust"]])
ships = ["engineIdleLoop", "engineFullLoop", "propSlowLoop", "propFastLoop", "airshipWindLoop", "wheelRollLoop", "hullWaterLoop", "wingRushLoop", "frigateDroneLoop", "carriageTreadLoop",
         "hullCreak", "shipCollide", "shipCollideHard", "shipSplash", "helmTake", "engineStart", "trainWhistle", "steamChuff", "shipCannon", "turretTraverseLoop", "mainGunCharge", "mainGunFire", "mainGunRumble"]
section("Vehicles, ships and airships", "Loops must be seamless (the engine loops the whole file). Idle and full engine layers are cross-faded by throttle, so record them from the same engine.",
        [item(n, *(LOOPS.get(n) or ONE[n])) for n in ships] + [item(n, *LOOPS[n]) for n in ["minecartLoop", "elytraLoop"]])
amb_loops = ["fireLoop", "furnaceLoop", "campfireLoop", "portalLoop", "beaconLoop", "respawnAnchorLoop", "spawnerLoop", "netherWastesLoop", "soulValleyLoop", "crimsonLoop", "warpedLoop",
             "basaltLoop", "ashVaultLoop", "endLoop", "deepDarkLoop", "lushLoop", "dripstoneLoop", "cricketsLoop", "swampLoop", "windLoop", "jungleLoop", "fireflyLoop", "hiveLoop", "stationHumLoop",
             "mountainWindLoop", "tundraWindLoop", "swampInsectsLoop"]
amb_one = ["birdCall", "owlHoot", "dryGrassRustle", "heartCreak", "caveAmbience", "caveDrip", "caveWind", "netherMood", "iceCreak", "rockfall", "volcanoRumble"]
section("Ambience beds and stings", "Beds are seamless loops (2-9 s today; real beds can be 20-60 s); stings are one-shots dropped at random over the beds. See the biome table below for which plays where.",
        [item(n, *LOOPS[n]) for n in amb_loops] + [item(n, *ONE[n]) for n in amb_one])
specials = ["creeperHiss", "fireball", "evokerCast", "fangs", "raidHorn", "mobVoidwalker", "teleport", "dragonGrowl", "dragonFlap", "dragonShoot", "dragonDeath", "crystalBreak", "witherSpawn", "witherShoot", "witherDeath",
            "wardenHeartbeat", "wardenRoar", "wardenSonicCharge", "wardenSonicBoom", "wardenEmerge", "wardenDig", "wardenSniff", "elderCurse", "guardianLaser", "zombieBreakDoor", "zombieInfect", "phantomSwoop", "beeSting", "breezeShoot",
            "villagerYes", "villagerNo", "villagerTrade", "villagerCelebrate", "zombieCure", "beePollinate", "allayItem", "foxSniff", "catPurr", "wolfPant", "parrotMimic", "dolphinJump", "turtleEggCrack", "frogTongue", "goatRam"]
section("Mob specials, bosses and townsfolk", "", [item(n, *ONE[n]) for n in specials] +
        [item(f"villager_work_{i}", "friendly", f"Townsperson working at a {p} workstation", PROF_WORK[p]) for i, p in enumerate(PROF)])
mobl = []
for k, n, v in MOB:
    if k in SILENT or k in ("horse", "donkey", "mule", "skeleton_horse", "zombie_horse"): continue
    for s in ["ambient", "hurt", "death"]:
        cat = "hostile" if k not in ("cow", "sheep", "chicken", "pig", "villager", "iron_golem", "snow_golem", "strider", "rabbit", "fox", "wolf", "cat", "ocelot", "llama", "trader_llama", "camel", "goat", "panda", "polar_bear", "turtle", "frog", "tadpole", "armadillo", "sniffer", "mooshroom", "bee", "parrot", "bat", "allay", "axolotl", "squid", "glow_squid", "dolphin", "cod", "salmon", "tropical_fish", "pufferfish", "wandering_trader", "copper_golem", "happy_ghast", "camel_husk", "nautilus") else "friendly"
        mobl.append(item(f"mob_{k}_{s}", cat, f"{n} {MOBSOUND[s]}", mob_desc(n, v, s)))
for k in ["cow", "pig", "sheep", "chicken", "villager", "wolf", "cat", "fox", "goat"]:
    n = [x for x in MOB if x[0] == k][0]
    mobl.append(item(f"baby_{k}_ambient", "friendly", f"Young {n[1].lower()} idle call", f"the same voice higher and lighter ({n[2]})"))
section("Every mob: idle, hurt, death", "One file set per mob kind (MobKind key = the stable save key, not the display name). Silent kinds (minecart, boat, armor stand, hollow crystal) have none. Two takes for idle and hurt.", mobl)

# Note blocks
notes = ["harp", "bass drum", "snare", "hat (clicks)", "bass", "flute", "bell", "guitar", "chime", "xylophone", "iron xylophone", "cow bell", "didgeridoo", "bit", "banjo", "pling"]
nb = [f"- `note_<instrument>_<pitch>` (blocks): note blocks, made on demand for instrument 0-{len(notes)-1} ({', '.join(f'{i} {x}' for i, x in enumerate(notes))}) and pitch 0-24 (12 = the instrument's base note). An override can be given per exact pitch (`note_0_12.wav`); there is no automatic repitching of one sample across the range yet."]
section("Note blocks", "", nb)

# Biome table
BIOMES = [("Forest (day)", "windLoop", "birdCall"), ("Forest (night)", "cricketsLoop", "owlHoot"), ("Jungle", "jungleLoop", "birdCall"), ("Swamp (day)", "swampInsectsLoop + swampLoop", ""),
 ("Swamp (night)", "swampLoop + cricketsLoop", ""), ("Beach / ocean", "oceanLoop + windLoop", ""), ("Meadow (night)", "cricketsLoop + fireflyLoop", "owlHoot"), ("Badlands", "windLoop", "dryGrassRustle"),
 ("Pale / ashen grove", "windLoop", "heartCreak, owlHoot"), ("Apiary / flower fields", "hiveLoop + windLoop", "birdCall, beePollinate"), ("Mountains", "mountainWindLoop", "rockfall, windGust"),
 ("Tundra / frozen", "tundraWindLoop", "iceCreak"), ("Snowstorm", "snowWindLoop + tundraWindLoop", ""), ("Rain (any)", "rain + rainRoof under cover", "thunder"), ("Rainforest in rain", "rain + rainLeavesLoop", "thunderFar"),
 ("Rivers and waterfalls", "riverLoop / waterfallLoop", "birdCall"), ("Caves", "dripstoneLoop + waterLoop", "caveAmbience, caveDrip, caveWind"), ("Lush caves", "lushLoop", "caveDrip"), ("Deep Dark", "deepDarkLoop", "wardenHeartbeat"),
 ("Underwater", "underwaterLoop", "underwaterMood"), ("Lava lakes", "lavaLoop + fireLoop", "lavaPop"), ("Emberdeep Wastes", "netherWastesLoop + lavaLoop", "netherMood"), ("Ghost Valley", "soulValleyLoop", "netherMood"),
 ("Rustcap Forest", "crimsonLoop", ""), ("Tealcap Forest", "warpedLoop", ""), ("Basalt Deltas", "basaltLoop", ""), ("The Hollow", "endLoop", "teleport"), ("Ash Vault", "ashVaultLoop", "ashSiren, shellIncoming"),
 ("Boreal Station", "stationHumLoop", ""), ("Volcano regions", "(biome bed)", "volcanoRumble")]
bt = ["| Biome / place | Beds (loops) | Stings |", "|---|---|---|"] + [f"| {a} | {b} | {c} |" for a, b, c in BIOMES]

total = sum(1 for s in sections for l in s[2] if l.startswith("- `") and "<" not in l.split("`")[1])
worst_lines = [f"{i+1}. `{n}`: {why}" for i, (n, why) in enumerate(WORST.items())]
missing = [n for n in WORST if n not in seen]
assert not missing, missing

hdr = f"""# Blocksmith sound list

Every sound event in the game, by its stable file name. Today all of them are synthesized in code (Sources/SoundSynth.swift,
SoundFoley.swift, SoundMobs.swift, WeaponAudio.swift, VehicleAudio.swift, TerrainAudio.swift, HorseLife.swift). A recording
dropped in `Resources/Sounds/real/<name>.wav` (variants `<name>_1.wav` ... `<name>_5.wav`) replaces the synthesized sound with
that name on the Mac and the Quest; see `Resources/Sounds/real/README.md`. The names are `Snd.name` (Sources/Sound.swift) and
never change: they are the contract between the code and the recordings.

Each line: `file name` (volume category) [level of today's synthesized take, LUFS, from docs/status/audio_levels.md; a
recording is normalised to this level] event, then what a good recording sounds like. **WORST** marks the 40 weakest
synthesized sounds (judged from the synthesis code and Remington's playtest complaints in docs/roadmap/backlog.md): replace
those first. All recordings must be original or properly licensed (no other game's sounds).

{total} named sounds (+ note blocks on demand, + {len([n for n in levels if n.startswith('voice_')])} recorded townsfolk voice takes `voice_<n>`, already real recordings from Resources/voices.bin).
Generated from the code on 2026-10-14 (mirrors SoundBank.allSounds); regenerate with tools/soundlist.py when Snd gains a case.

## The 40 worst synthesized sounds (record these first)

""" + "\n".join(worst_lines) + "\n"

body = []
for title, intro, its in sections:
    body.append(f"\n## {title}\n")
    if intro: body.append(intro + "\n")
    body.extend(its)
body.append("\n## Ambience per biome\n\nWhich beds and stings make up each place (the soundscapes `Blocksmith --sounds` mixes in scapes/). Wind is the one sound the owner praised: keep its character.\n")
body += bt
body.append("\n## Not file-driven\n\n- Music (Music.swift, procedural score) and the player's own music folder (CustomMusic.swift) are separate from this list.\n- Legacy names `mobCow`, `mobZombie`, ... are aliases: they use the `mob_<key>_ambient` file.\n- `voice_<n>` townsfolk lines come from Resources/voices.bin (already recorded).\n")
open(OUT, "w").write(hdr + "\n".join(body) + "\n")
print("wrote", OUT, total, "sounds")
