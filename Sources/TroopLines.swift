import Foundation
import simd

// P468 (Oct 25 20:05-21:09: "a thousand different lines... amongst all other lines any characters could have, that way a
// person who plays the game a bunch doesn't keep hearing the same lines over and over"; voiced, not captions). The sides
// that had little or nothing to say: the Capital's troops, Hannibal troopers, Greywall's garrisons, Boreal Station crews,
// the Ashguard in the Ash Vault, Marauders, Brigands and the crews of the big vessels. Voiced like the townsfolk
// (tools/townvoice_gen.py reads this table too; TownVoice.takes holds the takes).
//
// His question (21:05): would he ever hear the everyday lines of sides that fight him on sight? Yes, by design: an
// everyday line ("idle", "night", "guard") is only said by a soldier or outlaw who hasn't noticed him, while he is within
// earshot (TroopVoice.overhear): sneaking into a base, watching a camp from the brush, standing among a garrison that
// tolerates him, riding aboard a friendly vessel. The fighting lines (spot, fight, search, lost, hurt, flee...) are what
// he hears once they have.
//
// All text is original (the repo is public): no other game's names, characters or catchphrases.
enum TroopVoice {
    enum Ctx: String, CaseIterable { case idle, night, atPost = "guard", spot, fight, search, lost, breach, reload, hurt, flee, surrender, taunt, dying }

    // Voice key -> speech model voice (TownVoice.voices holds them all: the same table feeds the generator).
    static let voices: [String: (String, Double)] = [
        "capital": ("Adam", 1), "hannibal": ("Brian", 1), "officer": ("Eric", 1), "greywall": ("Chris", 1),
        "boreal": ("River", 1), "ash": ("Will", 1), "marauder": ("Roger", 1), "brigand": ("Bill", 1), "crew": ("Eric", 1),
    ]
    // Line group -> its voices (one each: every line is voiced once).
    static let groups: [String: [String]] = [
        "capital": ["capital"], "hannibal": ["hannibal"], "officer": ["officer"], "greywall": ["greywall"], "boreal": ["boreal"],
        "ash": ["ash"], "marauder": ["marauder"], "brigand": ["brigand"], "crew": ["crew"],
    ]

    // (group, context, lines). Plain string literals only (the generator parses this table).
    static let script: [(String, String, [String])] = [
        // MARK: The Capital's troops
        ("capital", "idle", ["Stand straight, eyes forward, think about lunch. That's guard duty.", "Third inspection this week. They'll polish the paint off.",
                             "My boots were issued in spring. They still haven't forgiven me.", "Sergeant says the parade's on. Sergeant says a lot of things.",
                             "If the tram's late again I'm walking the wall. Faster anyway.", "Mess hall's doing the grey stew. Every day is grey stew day.",
                             "Wrote my sister. Told her it's all marble and banners. It's mostly stairs.", "They painted the gate again. Same colour. Different number.",
                             "You hear the drill hall echo? That's my knees.", "Two more years and I get a desk. A desk with a chair.",
                             "Who keeps leaving oil rags in the stairwell?", "I volunteered for the tower. I'd like to un-volunteer.",
                             "The new rifles shoot straighter. The new boots don't walk straighter.", "Somebody fed the pigeons on the battlements. Now they think they live here.",
                             "Watch rotation's posted. I'm on nights. Again.", "I miss the farm. The cows never asked for my papers.",
                             "Officer's got a new hat. We're all supposed to notice the hat.", "Quiet shift. Don't say it out loud.",
                             "Some fool sneezed during the anthem. They're still looking for him.", "Lamp oil ration's down a third. Polishing by moonlight, then."]),
        ("capital", "night", ["Night watch. The stars don't salute, at least.", "Cold up here. Wall's colder.", "Lamps out on the east side. Again.",
                              "If I fall asleep on the wall, the wall can report me.", "Somewhere a bed has my name on it.", "Quiet night. I hate quiet nights."]),
        ("capital", "guard", ["Papers, please. And keep your hands where I can see them.", "No weapons drawn inside the walls, citizen.",
                              "Move along. Nothing to see but me.", "Gate closes at dusk. Don't be on the wrong side of it.",
                              "State your business with the Capital.", "Keep to the main road. Side streets are for residents.",
                              "Holster that weapon inside the walls, citizen. I won't ask twice.", "Show your pass at the inner gate."]),
        ("capital", "spot", ["Intruder! Inside the wall!", "There! By the steps! Open fire!", "Contact! Sound the bell!", "Halt! You're not cleared for this sector!",
                             "Armed stranger, west side! Get him!", "Hold it right there! Down on the ground!", "We've got a runner! Cut him off!",
                             "Alarm! Alarm! Shooter on the grounds!", "Movement in the garden! That's no gardener!", "He's here! Wake the barracks!"]),
        ("capital", "fight", ["Contact on the east wall! Get the gun crew up!", "Keep him pinned! Don't let him reach the tower!", "Covering! Move up!",
                              "Push left! Push left!", "Short bursts! Make them count!", "He's behind the planter! Flush him out!",
                              "For the Capital! Forward!", "Hold the stairs! Nobody gets past the landing!", "Grenade! Get down!",
                              "Pour it on! He can't hide forever!", "Somebody get eyes on the roof!", "Stay in cover, you idiot!",
                              "Reload behind the pillar, I've got you!", "He's quick! Lead your shots!", "Fall in on me! Line up!"]),
        ("capital", "search", ["Check the halls. Every door.", "Spread out. He can't have gone far.", "Look behind the crates. Look under them too.",
                               "Two by two. Nobody wanders off alone.", "I heard boots on the stairs. Up, now.", "Check the gardens. He likes cover.",
                               "Search the barracks. Wake whoever's sleeping.", "He's in here somewhere. I can feel it."]),
        ("capital", "lost", ["Lost him. He was right here.", "Gone. Like smoke.", "Stand down... but keep your eyes open.", "Report it. Somebody's getting a lecture.",
                             "Probably a rat with a rifle. Back to posts.", "We'll find him. Or he'll find us."]),
        ("capital", "breach", ["That was the wall! Somebody's inside!", "Breach! Breach on the lower level!", "They've blown the door! Positions!",
                               "Something just came through the stone! Move!", "Wall's open! Get everyone down here!"]),
        ("capital", "reload", ["Reloading!", "Changing mags, cover me!", "Empty! Cover!", "Last clip! Somebody bring rounds!", "Hold on, hold on, I'm dry!"]),
        ("capital", "hurt", ["I'm hit! Leg's gone numb. Keep firing!", "Ah! He got my arm!", "Medic! Medic!", "I'm bleeding! Somebody!",
                             "Just a scratch! Just a big scratch!", "Argh! That one went through!"]),
        ("capital", "flee", ["Fall back! Fall back to the hall!", "Too hot! Pull back!", "I'm not dying on these steps! Back!", "Get to the barracks! Regroup!"]),
        ("capital", "surrender", ["All right! All right! I yield!", "Don't shoot! I've got a family!", "I'm done! I'm done! Let me go!"]),
        ("capital", "taunt", ["You picked the wrong wall to climb.", "The whole garrison's coming. Hope you brought friends.", "Nobody storms the Capital and walks home."]),
        ("capital", "dying", ["Tell my mother... I kept my boots clean.", "Not... on the stairs...", "Should've... taken the desk..."]),

        // MARK: Hannibal troopers (heavy plate, heavy guns, few words)
        ("hannibal", "idle", ["Heavy plate. Heavy gun. Light conversation.", "They give me the big gun because I don't drop it.",
                              "Twelve stone of armour and they still send me up the stairs.", "The plate's warm in summer. Very warm.",
                              "Recruits keep asking if it hurts. Only when I laugh.", "I polish it every night. It's good company."]),
        ("hannibal", "spot", ["Found one.", "There you are.", "Stay right there. I'm slow, but I arrive.", "Contact. Bringing the big one."]),
        ("hannibal", "fight", ["Send them all. I'll wait.", "Keep walking at me. I dare you.", "Is that all you've got?", "Suppressing. Go round him.",
                               "Spinning up. Get behind me.", "Stand still and this goes quicker."]),
        ("hannibal", "taunt", ["Your rounds bounce off me. Try harder.", "That tickled.", "Plate's dented. You're not.", "Bring something bigger."]),
        ("hannibal", "hurt", ["Hm. That one I felt.", "Plate's cracked. Doesn't matter.", "Lucky shot. Try again."]),
        ("hannibal", "dying", ["Heavy... plate...", "Huh. Didn't think... you'd manage it."]),

        // MARK: Officers (any side's)
        ("officer", "idle", ["Rotation reports by sundown, not by sunrise.", "If the quartermaster asks, the crates were always there.",
                             "Command wants it done yesterday. Command can come up and do it.", "Keep the men busy. Busy men don't think.",
                             "I signed for two hundred rounds. I count a hundred and ninety.", "The map says this wall is finished. The map is optimistic."]),
        ("officer", "spot", ["Contact! All squads, converge!", "Enemy inside the perimeter! Weapons free!", "There! Take him alive if you can. Dead if you can't."]),
        ("officer", "fight", ["Flank him! Second squad, right side!", "Hold your positions! Nobody runs!", "Get that gun turned around!",
                              "Suppress and advance! Move!", "Pin him and close in!"]),
        ("officer", "search", ["Sweep it room by room.", "Seal the exits. Then we take our time.", "Every man to his post. He has to come past someone."]),
        ("officer", "lost", ["Double the watch. He'll be back.", "Find him or find a new uniform.", "Somebody missed something. I'll find out who."]),
        ("officer", "flee", ["Withdraw! Regroup at the gate!", "Everyone back to the keep!"]),

        // MARK: Greywall Command
        ("greywall", "idle", ["Generator's coughing again. If it dies on my shift, it's your fault.", "Ration tins say beef. I've seen beef. That isn't beef.",
                              "Radio's been nothing but static since Tuesday.", "Whoever stacked those sandbags has never met a sandbag.",
                              "Third week on this post. Starting to name the crows.", "They promised us leave by the harvest. Which harvest, they didn't say.",
                              "Card game tonight. Bring your own matches to bet.", "Wind keeps getting into the bunker. Wind and sand.",
                              "Supply truck's late. Supply truck's always late.", "I'd kill for a hot bath. Well. Not kill. Strongly consider.",
                              "Corporal swears the base is haunted. Corporal also drinks.", "Lamp in the comms room flickers. Nobody fixes anything here.",
                              "Did you hear that? No? Good. Me neither.", "My mum thinks I'm a clerk. Let's keep it that way.",
                              "Who took my tin cup? It had a dent. I liked the dent.", "Coffee's out. Morale's out with it.",
                              "Saw a fox at the wire this morning. Prettiest thing out here.", "If the command post calls, I'm on patrol. I'm always on patrol."]),
        ("greywall", "night", ["Keep the lamp low. Snipers love a lamp.", "Cold night. Colder in the bunker.", "Can't sleep. Generator hums like a hornet.",
                               "Watch the ridge. That's where they'd come from.", "Night shift's the worst shift. Every shift's the worst shift.",
                               "Stars out here are something. Shame about everything else."]),
        ("greywall", "guard", ["This is a Greywall post. Turn around.", "No closer. Not without a pass.", "Keep moving, traveller. Nothing here for you.",
                               "You've got business with Command? Then you've got papers.", "Stay off the wire. It bites."]),
        ("greywall", "spot", ["Contact at the wire!", "Stranger inside the fence! Light him up!", "There! By the bunker!", "Wake the base! We've got one!",
                              "Hey! You! Hands where I can see them!", "Movement on the ridge! It's him!", "Got eyes on an intruder! North side!",
                              "Armed man in the yard! Fire, fire!"]),
        ("greywall", "fight", ["Keep his head down!", "Covering fire! Go, go!", "Get to the guns!", "He's at the stairs! Cut him off!",
                               "Flank him through the comms room!", "Throw one in there and see who jumps!", "Don't bunch up! Spread out!",
                               "Hold the corridor! He comes through, he dies!", "He's in the hall! Pin him!", "Somebody get on the radio!",
                               "Move up! I've got your back!", "Stay low, he's a good shot!"]),
        ("greywall", "search", ["Check the halls. Check under the stairs. Check everything twice.", "Room by room. Nobody goes alone.",
                                "Check the vault. Check the armoury.", "Look for tracks in the sand.", "Lamps up. He hides in the dark.",
                                "He's still in the base. I'd bet my boots on it.", "Get a squad on the roof. The rest of you, with me."]),
        ("greywall", "lost", ["Lost him. He was right here. Spread out.", "Gone. Where the devil did he go?", "Back to posts. Stay sharp.",
                              "Probably ran for the hills. Probably.", "Tell Command we had a visitor. They'll love that."]),
        ("greywall", "breach", ["That was the wall. Someone's inside. Room by room, go!", "Wall's down on the east side!", "Explosion in the bunker! Move!",
                                "Somebody just blew a hole in us!"]),
        ("greywall", "reload", ["Reloading!", "Mag out! Cover!", "I'm empty!", "Swapping! Watch the door!"]),
        ("greywall", "hurt", ["Argh! I'm hit!", "Took one in the shoulder!", "Medic! Anyone!", "Get him off me!", "That stings like the devil!"]),
        ("greywall", "flee", ["Pull back! Pull back to the bunker!", "He's too good! Get out!", "Run for the trucks!"]),
        ("greywall", "surrender", ["All right! All right, I'm going! Don't shoot!", "I give up! I just work the radio!", "Don't shoot! I'm out of this!"]),
        ("greywall", "taunt", ["You'll never get past the bunker.", "Command will send everything. You know that, right?", "Nice try. The vault's still shut."]),
        ("greywall", "dying", ["Should've... stayed a clerk...", "Tell them... the generator...", "Cold... it's cold..."]),

        // MARK: Boreal Station crews
        ("boreal", "idle", ["Sixty days on this ice and the coffee still tastes like the tin it came in.", "Supply sled's late. If it's not here by dark we start rationing jokes.",
                            "Uplink's been fine all week. Which means it's planning something.", "Someone left the hatch open. Again. The snow came in to say hello.",
                            "My beard has icicles. My eyebrows have icicles.", "The generator's the warmest thing on this station. I talk to it.",
                            "Chess with the radio operator. He cheats. I let him.", "Saw lights over the ridge last night. Probably nothing. Probably.",
                            "Six weeks to rotation. Not that I'm counting. Forty-one days.", "The rail line's the only thing that comes on time out here.",
                            "Who ate the last tin of peaches? I'm conducting an investigation.", "Ice on the dish again. Somebody grab the broom."]),
        ("boreal", "night", ["Lights stay on all night. You'd think that'd help me sleep.", "Wind's howling. Sounds like it's got a grudge.",
                             "Keep the stove going. If it dies, we die.", "Night on the ice. Black as a boot."]),
        ("boreal", "spot", ["Contact on the ramp!", "Intruder at the station! Sound it!", "Someone's at the bulkheads!", "There! On the ice!", "Alarm! Get everyone up!"]),
        ("boreal", "fight", ["Into the trucks! Cover the road!", "Hold the stairwell!", "Seal the bulkheads behind you!", "Pin him in the hall!",
                             "Protect the uplink!", "Cover the generator! If he gets there we're done!", "Go, go! Down the stairs!"]),
        ("boreal", "search", ["Check the generator hall.", "Check the control room. Twice.", "He came down the stairwell. Follow the snow.", "Look in the lockers."]),
        ("boreal", "lost", ["Gone into the snow. We'll never track him in this.", "Lost him. Close the hatches.", "He'll freeze out there. Probably."]),
        ("boreal", "hurt", ["I'm hit! Ah, it's cold!", "Took one! Help!", "Get me to the medical bay!"]),
        ("boreal", "flee", ["Back down the stairs!", "Into the bunker! Seal it!"]),

        // MARK: The Ashguard (the Ash Vault: eleven years under the ground)
        ("ash", "idle", ["The Marshal says the surface is lost. He's never been up to check.", "Lamp four is out again. We've written to Cinderhold. Twice.",
                         "Eleven years since anyone saw the sky. I don't remember what blue looks like.", "Ash in the soup. Ash in the bread. Ash in my boots.",
                         "My grandfather told me about rain. I think he made it up.", "The fans hum all day. You stop hearing them. Then they stop and you panic.",
                         "Slagford's got the good mushrooms. Cinderhold's got the good gossip.", "They say the Chancellor never sleeps. I believe it.",
                         "We patch the tanks with the tanks. Not many tanks left.", "Breathing filter's clogged again. Bang it on the wall. There.",
                         "Lava's quiet today. I don't trust it when it's quiet.", "I traded my ration for a book. Best trade I ever made.",
                         "The old roads go up. Nobody walks them anymore.", "Someone painted a sun on the bunker wall. Looks nice. Looks wrong."]),
        ("ash", "night", ["Night, day. Down here they're the same colour.", "Lamps are dimmed. That's how we know it's night.",
                          "Lava glow through the slits. Better than a candle."]),
        ("ash", "spot", ["Eleven years since anyone saw the sky. You've come from it, haven't you?", "A stranger! From above!", "Up there! On the ridge!",
                         "Intruder in the vault! Signal the line!", "Who goes there? Halt!", "Surface man! Get him!"]),
        ("ash", "fight", ["Hold the line! For the Vault!", "Through the smoke! He's there!", "Call in the guns!", "Keep him out of the trenches!",
                          "Get to the wire! Don't let him past!", "Mortar team! Mark him!", "Pin him in the ash!"]),
        ("ash", "search", ["Check the trenches.", "Follow the prints in the ash.", "Check the bunker. Then the next one.", "He's somewhere in the smoke."]),
        ("ash", "lost", ["Gone into the haze.", "Lost him in the ash. Report to Cinderhold.", "The vault swallows people. Maybe it swallowed him."]),
        ("ash", "hurt", ["I'm hit! Ah!", "My filter! He broke my filter!", "Medic to the line!"]),
        ("ash", "flee", ["Back to the bunker!", "Fall back to the Ember Line!"]),
        ("ash", "surrender", ["Don't shoot! Take me up there! Show me the sky!", "I yield! I'm tired of the dark!"]),
        ("ash", "dying", ["Is it... blue? Up there?", "Tell Cinderhold... lamp four..."]),

        // MARK: Marauders (the watchtowers' raiders)
        ("marauder", "idle", ["Burn the barn, keep the pig. Never the other way round.", "Tower's leaking again. Raiding pays. Roofing doesn't.",
                              "Boss wants more loot. Boss always wants more loot.", "I nicked a hat in the last village. Fits nice.",
                              "Who's on lookout? Not me. Never me.", "If the Capital comes, I was never here.", "Whose turn is it to cook? Not yours. Never again yours.",
                              "Bet you a boot I can hit that crow.", "One more good raid and I'm buying a horse. A real one, not a stolen one."]),
        ("marauder", "spot", ["Fresh meat on the road, lads! Take the boots first!", "There's one! Get him!", "Look at that gear! It's mine!", "Wake up! We've got a visitor!",
                              "Easy pickings! Surround him!"]),
        ("marauder", "fight", ["Shoot him! Shoot him!", "Fill him with bolts!", "Around the side!", "He's tougher than he looks!", "Don't let him reach the tower!"]),
        ("marauder", "taunt", ["Nice armour. It'll look better on me.", "Run home! Leave the boots!", "You'll make a fine sign for the tower!", "I've seen scarecrows fight harder."]),
        ("marauder", "hurt", ["Ow! He bit me! With a sword!", "Argh! My arm!", "Lucky! That was lucky!"]),
        ("marauder", "flee", ["Not worth it! Not worth it! Back to the tower!", "Run! He's mad!", "I didn't sign up for this!"]),

        // MARK: Brigands (the Roost's axes)
        ("brigand", "idle", ["Sharpened my axe. Sharpened it again. Nothing else to do.", "Boss counts the gold twice a day. I count it once, quieter.",
                             "This Roost has more rats than brigands.", "Rained in the hall. Through the roof. On my supper.", "Somebody stole my stolen boots.",
                             "Quiet in the woods. Too quiet for honest folk. Lucky we're not honest."]),
        ("brigand", "spot", ["Toll road, friend. Pay in coin or pay in blood. We take both.", "Hey! Intruder! Axes up!", "Fresh one! Grab him!", "You lost, traveller?"]),
        ("brigand", "fight", ["Chop him down!", "Surround him!", "Swing low! Take his legs!", "Don't let him get to the stairs!"]),
        ("brigand", "taunt", ["That's it? My horse bites harder.", "Come closer. I don't bite. The axe does.", "Run, little rabbit!"]),
        ("brigand", "hurt", ["Ow! You'll pay for that!", "Argh! Cut me, did you?", "That'll scar!"]),
        ("brigand", "flee", ["Run! Run for the woods!", "Every man for himself!"]),
        ("brigand", "dying", ["Tell the boss... tell him I kept the gold.", "Shoulda... been a farmer..."]),

        // MARK: Crews (frigates, crawlers, carriages, gun posts)
        ("crew", "idle", ["Engines one and two holding. Three's making that noise again.", "Tread's caught a tree again. Just drive. The tree loses.",
                          "Somebody tell the cook the deck isn't a frying pan.", "Captain wants the brass polished. The brass is fine. The captain is bored.",
                          "Altitude steady. Coffee steady. Morale... steady enough.", "Wind's on the starboard quarter. Hold her.",
                          "Watch your feet on the gangway, the rail's loose.", "Loader keeps humming the same song. All day. Same song.",
                          "Shell racks are full. Let's keep them that way."]),
        ("crew", "fight", ["Target's in range, captain. Say the word.", "Reloading the big gun! Thirty seconds, hold them off!", "Hull breach on the lower deck! Seal the hatches!",
                           "Bring her about! Guns to bear!", "Fire! Fire!", "Ammunition up! Now!", "Hard to port! Hard to port!", "Engine room, more power!"]),
        ("crew", "hurt", ["We're hit! Damage report!", "Fire in the engine room!", "I'm hurt! Somebody take my station!"]),
        ("crew", "flee", ["Abandon the gun! Get below!", "She's going down! Off, off!"]),
        // MARK: Second rounds (more of what each side says most)
        ("capital", "idle", ["They moved the mess hall bell. Half the barracks missed breakfast.", "The quartermaster counts bullets like they're his children.",
                             "Saw the Chancellor's carriage go past. Didn't wave. Neither did I.", "If they double the watch again, we'll be guarding each other.",
                             "Painted my helmet. Got told off. Painted it back.", "There's a cat in the armoury. Nobody admits to feeding it.",
                             "Rumour is there's a bonus at year's end. Rumour is a liar.", "My bunkmate snores like a deck gun.",
                             "They issued us new manuals. Same as the old manuals, thicker.", "Drill at dawn, drill at noon, drill in my sleep.",
                             "I'd swap a week's pay for one quiet Sunday.", "Somebody wrote a poem on the latrine wall. It's quite good."]),
        ("capital", "fight", ["Keep the pressure on!", "Watch the left flank!", "He's reloading! Push!", "Get down, get down!", "Eyes on the doorway!",
                              "Cover the courtyard!", "Hit him from both sides!", "Don't stop shooting!"]),
        ("capital", "search", ["Stay sharp. He's got to be close.", "Check the stairwell. Then check it again.", "Somebody saw him by the fountain."]),
        ("greywall", "idle", ["The rations have a date stamped on them. I won't say which year.", "Truck needs a new tyre. Truck needs a new truck.",
                              "If I hear that radio jingle one more time I'll eat the radio.", "Found a scorpion in my boot. Named him Corporal.",
                              "Command sent a memo about morale. It was four pages.", "The sandbags have sand in them. That's about the only thing that works here.",
                              "Somebody's growing tomatoes behind the bunker. Good on them.", "My letters home take a month. My mum's replies take two.",
                              "They say the vault's got gold in it. They say a lot.", "I've cleaned this rifle so often it's thinner than when I got it."]),
        ("greywall", "fight", ["Grenade out!", "He's on the roof!", "Through the window! He's at the window!", "Fall back to the next room!",
                               "Watch your crossfire!", "Get the heavy gun on him!"]),
        ("greywall", "spot", ["Visitor at the fence! Not a friendly one!", "Sound off! Intruder, west bunker!"]),
        ("boreal", "idle", ["They sent us a crate of oranges. Froze solid. Still the best day this month.", "Wrote a song about the snow. It's short. It's mostly swearing.",
                            "The cook says it's stew. The thermometer says it's ice.", "Rail crew says the line's buried again. Shovels out.",
                            "Saw a polar fox. It looked at me like I owed it money.", "My socks have been wet for three weeks.",
                            "The radio picked up music last night. Somewhere it's warm.", "I've counted every rivet in the control room. Twice."]),
        ("boreal", "fight", ["Watch the ice, it's slick!", "Keep him off the ramp!", "Get behind the truck!", "Hold here! Hold!"]),
        ("ash", "idle", ["They found another tunnel. It goes down. They always go down.", "The lamp oil smells like burned hair. You get used to it.",
                         "Someone hums a surface song. Nobody knows the words anymore.", "The boiler boys say the pipes are singing. That's never good.",
                         "Cinderhold's market had a real apple. One. People queued.", "My boots melted a little on the slag road. Again.",
                         "We used to dream about leaving. Now we dream about sleeping.", "The Marshal inspects the trenches at night. Nobody knows when he sleeps."]),
        ("ash", "fight", ["Mark him! Mark him for the guns!", "Hold the trench!", "Up and over! Push!", "Keep your mask on, keep firing!"]),
        ("marauder", "idle", ["Last village had nothing but turnips. Turnips!", "I traded a stolen horse for a stolen saddle. Even trade.",
                              "Boss says we're moving camp. Boss always says that.", "If the sheriff shows, I'm visiting my aunt.", "My feet hurt. Raiding is mostly walking.",
                              "Who drank the last of the good stuff? I'll find out."]),
        ("marauder", "fight", ["Pin him down!", "Over there! By the rocks!", "Get the horses!", "Drop him and we split his purse!"]),
        ("marauder", "spot", ["Rider on the trail! Make him pay!", "Look sharp! Company!"]),
        ("brigand", "idle", ["Somebody sang in the hall last night. Somebody should stop.", "My axe has a name. I won't tell you.", "Roost leaks worse than a sieve.",
                             "Boss wants the ledger tidy. Brigands with ledgers. What's the world coming to?"]),
        ("brigand", "fight", ["Hack at him!", "Get round the back!", "Keep him in the corner!"]),
        ("brigand", "spot", ["Stranger at the gate! Grab your axes!", "Somebody's poking round the Roost!"]),
        ("crew", "idle", ["Pressure gauge is in the red. It's always in the red.", "Somebody tell the gunner the shell racks aren't a bench.",
                          "The engine sings when she's happy. She's not singing.", "Navigator swears he knows where we are. Navigator swears a lot.",
                          "Hull plates rattle at full speed. Like a tin of nails.", "Ten more hours on this shift and I'll be part of the deck."]),
        ("crew", "fight", ["Brace for impact!", "Turret, swing left!", "Loading! Loading!", "Keep her steady for the shot!", "We've got him in the sights!"]),
        ("officer", "idle", ["Discipline's slipping. I'll tighten it.", "Report from the east road is late. Find out why.", "If the men grumble, they're fine. If they're quiet, worry."]),
        ("officer", "fight", ["Covering fire, then move!", "Get a grenade on that position!", "You two, flank left. Now!"]),
        ("hannibal", "idle", ["They built the stairs for lighter men.", "I asked for a smaller gun once. They laughed."]),
        ("hannibal", "fight", ["I'll walk through you.", "Keep shooting. I'll keep coming."]),
    ]

    // The voice a soldier, an outlaw or a crewman speaks with, or nil for anyone else.
    static func voice(_ m: Mob, _ g: Game) -> String? {
        switch m.kind {
        case .pillager: return "marauder"
        case .vindicator: return "brigand"
        case .soldierCrew: return "crew"
        default: break
        }
        guard Soldier.rank(m.kind) != nil, !m.kind.ashVehicle, !m.hired, m.posse != Director.posse, m.posse != Prisoners.posse else { return nil }
        if m.posse == Marauders.posse { return "marauder" }
        if m.posse == 1 || m.posse == 2 { return "brigand" }          // (a wanted outlaw and his gang)
        if m.kind == .soldierOfficer { return "officer" }
        if m.troop == Int8(TroopClass.hannibal.rawValue) { return "hannibal" }
        if m.factionValue == .ashguard { return "ash" }
        if m.factionValue == .greywall { return "greywall" }
        if g.stationOp(near: m.pos) != nil { return "boreal" }
        return "capital"
    }

    // Takes for TownVoice (voice key, context, text), every line in its group's voices.
    static var takeRows: [(String, String, String)] {
        var out: [(String, String, String)] = []
        for (grp, c, lines) in script { for v in groups[grp] ?? [] { for t in lines { out.append((v, c, t)) } } }
        return out
    }
    // voice -> context -> take ids (into TownVoice.takes).
    static let index: [String: [String: [Int]]] = {
        var d: [String: [String: [Int]]] = [:]
        for (i, t) in TownVoice.takes.enumerated() where t.troop != nil { d[t.voice, default: [:]][t.troop!, default: []].append(i) }
        return d
    }()

    // MARK: Saying them

    static var lastLine: Double = -100            // the last troop line anywhere (one at a time, a gap between)
    static var lastIdle: Double = -100            // the last overheard everyday line
    private static var lastTake: [String: Int] = [:]
    static var said = 0, overheard = 0            // (checks)

    // A line for the context in this mob's voice (never the same take twice running for a voice), spoken at its mouth.
    // `gap`: seconds since the last troop line anywhere before another may start. Nil (and nothing used up) when there is
    // no recorded take for it: the caller's synthesized bark plays as before. Spec Ops keep quiet but for pain.
    @discardableResult
    static func say(_ g: Game, _ m: Mob, _ ctx: Ctx, gap: Double = 3.5, chance: Float = 1) -> String? {
        guard m.health > 0 || ctx == .dying, g.clock - lastLine >= gap,
              m.troopClass != .specOps || ctx == .hurt || ctx == .dying,
              let vk = voice(m, g), var ids = index[vk]?[ctx.rawValue], !ids.isEmpty,
              simd_length(m.pos - g.player.pos) < 40 else { return nil }
        ids = ids.filter { TownVoice.clip(TownVoice.takes[$0].key) != nil }
        guard !ids.isEmpty, chance >= 1 || Rand.float(in: 0..<1) < chance else { return nil }
        if ids.count > 1, let last = lastTake[vk] { ids.removeAll { $0 == last } }
        let id = ids[Rand.int(in: 0...(ids.count - 1))]
        lastTake[vk] = id
        lastLine = g.clock
        said += 1
        let t = TownVoice.takes[id]
        TownVoice.captions[id] = "\(m.customName ?? m.spec.name): \(t.text)"
        g.sfx(.voice(id), 1, at: m.eye)
        return t.text
    }

    // An everyday line from someone who hasn't noticed him, while he is within earshot (14 blocks, a clear line or very
    // close): what he hears sneaking up on a base or a camp, or standing among a garrison that tolerates him (who has a
    // word for him at arm's length). True when a line was said.
    @discardableResult
    static func overhear(_ g: Game, _ m: Mob) -> Bool {
        guard g.clock - lastIdle > 22, g.clock - lastLine > 6, !m.aggro, m.health > 0 else { return false }
        let d = simd_length(m.pos - g.player.pos)
        guard d < 14, d < 4 || g.world.canSee(m.eye, g.player.eye) else { return false }
        let f = g.dayFraction
        let night = f > 0.56 && f < 0.95
        var ctxs: [Ctx] = [.idle]
        if night && Rand.float(in: 0..<1) < 0.4 { ctxs.insert(.night, at: 0) }
        if d < 6 && Soldier.rank(m.kind) != nil && g.repAllied(m) && Rand.float(in: 0..<1) < 0.5 { ctxs.insert(.atPost, at: 0) }
        for c in ctxs where say(g, m, c, gap: 6) != nil { lastIdle = g.clock; overheard += 1; return true }
        return false
    }

    // Hostile mobs on the mob AI (Marauders, Brigands): a call when their timer comes round. True when a line was said.
    static func outlawCall(_ g: Game, _ m: Mob) -> Bool {
        guard m.kind == .pillager || m.kind == .vindicator else { return false }
        let d = simd_length(m.pos - g.player.pos)
        if g.survival && g.alive && d < 18 && g.world.canSee(m.eye, g.player.eye) {
            let r = Rand.float(in: 0..<1)
            return say(g, m, r < 0.3 ? .spot : (r < 0.6 ? .taunt : .fight), gap: 5) != nil
        }
        return overhear(g, m)
    }
}

extension Mob {
    // P468: a spoken line in place of the synthesized bark when it has a recorded take.
    func barkLine(_ g: Game, _ ctx: TroopVoice.Ctx, _ snd: Snd, _ v: Float, chance: Float = 1) {
        if TroopVoice.say(g, self, ctx, chance: chance) == nil { shout(g, snd, v, at: eye) }
    }
}
