import Foundation
import simd

// Townsfolk lines for the hour and the moment (backlog R20, Oct 13 evening playtest, after P148 was marked done).
// What was wrong: every spoken line comes from TownVoice.script, a fixed table of recorded takes (about 300 texts over
// eight voice groups, most contexts two to six lines), and the only things that picked a line were the context
// (greet, chatter, night...) and a rule that one voice never says the same take twice running. Nothing knew the hour
// beyond day/night, the weather, the player's gun, wounds, money, horse, standing or bounty, or a robbery or shooting
// in town, so a town quickly ran through its handful and repeated it. (Townsfolk.greeting's richer text lines were
// only the fallback for a voice with no take, which no townsperson has.)
//
// Now TownVoice.speak asks here first for greetings, chatter and night lines. A line is drawn from the pools that fit:
//   time of day   dawn, day, dusk, night
//   weather       rain, storm
//   the player    gun drawn, wanted here (or a known outlaw), hurt, rich (over $50), on horseback, honoured, disliked,
//                 in a cell, with a captured outlaw in tow
//   the town      a theft not cooled yet (robbery), gunfire in the last 90 s (shooting), a festival day
// and the speaker's role: sheriff, deputy (and both as the law), storekeeper, barkeep, butcher, doctor, gunsmith,
// tailor, stablehand, smith, banker (and all of them as keepers), farmer, elder, child, the town drunk (a nitwit),
// the preacher (a cleric), craftsfolk, miners, Capital citizens, prisoners, and everyone (any). Pressing matters
// (wanted, a drawn gun, hurt, a shooting...) win most of the time; otherwise about half of the lines are for the hour,
// the weather and the rest, and the other half stay recorded takes. A line said in town is kept out for the next 96
// lines (town-wide memory), so nothing comes round again soon. These lines are text (a caption with a murmur), counted
// as `TownVoice.written`, not as missing takes. "{name}" is the name the town knows you by, "{town}" the town's.
// All the text is original.
enum TownLines {
    static var on = true                  // (TownLawTests' voice checks turn it off: they count recorded takes)
    static var share: Float = 0.5         // the chance a fitting time/weather/standing line is said instead of a take
    static var urgentShare: Float = 0.85  // the same for a pressing matter

    // (roles, key, lines). Roles: one role, or a group (law, keeper, folk, any).
    static let table: [(String, String, [String])] = [
        // MARK: Everyone
        ("any", "dawn", ["Up with the roosters, are you?", "Coffee's not even boiled yet.", "Mornin'. Sun's just clearing the ridge.",
                         "Early bird gets the worm, they say.", "Cold one this morning. It'll warm up.", "First light's the best light.",
                         "You're about early, {name}.", "Dew's still on the grass."]),
        ("any", "day", ["Fine day for it.", "Afternoon, {name}.", "Hot out. Find some shade.", "Town's busy today.",
                        "Day's half gone already.", "Good to see a face I know.", "Mind the wagons on the main street.",
                        "Nice and quiet in {town} today."]),
        ("any", "dusk", ["Sun's going down. Lamps'll be lit soon.", "Evening, {name}.", "Pretty sky tonight.",
                         "Day's about done.", "Supper time, near enough.", "Coyotes will start up any minute.",
                         "Best find a roof before dark.", "Look at that sunset. Never gets old."]),
        ("any", "night", ["Late to be wandering.", "Can't sleep either?", "Quiet as a church out here.",
                          "Mind your step. The street's dark.", "Things move around out there at night.", "Stars are thick tonight.",
                          "You'll catch a chill, out this late.", "Hush now. Folks are sleeping."]),
        ("any", "rain", ["Wet enough for you?", "Rain's coming down sideways.", "Mud to the ankles out here.",
                         "Good for the wells, at least.", "Get under the boardwalk, friend.", "My boots'll never dry.",
                         "Smells good, the rain.", "Roof's leaking again, I'd wager."]),
        ("any", "storm", ["Hear that thunder? Get inside!", "Lightning hit the old cottonwood last year.", "Storm's right on top of us.",
                          "Horses hate this weather.", "Stay off the high ground in this.", "Wind's fit to take the roofs off."]),
        ("any", "wanted", ["There's paper out on you. I've seen it.", "Folks say you're wanted here.", "Price on your head, they say.",
                           "I don't want any trouble from you.", "The sheriff's looking for you, you know.", "You've got some nerve, walking in here.",
                           "Pay what you owe and we'll all sleep easier.", "Your face is on the board by the jail."]),
        // D21: reactions to his looks and deeds.
        ("any", "bloody", ["You're covered in blood. Is any of it yours?", "Lord, look at the state of you.", "Wash up before you come in here.",
                           "Been butchering, have you?", "That's a lot of blood on one coat.", "Don't come near me like that."]),
        ("any", "killer", ["You killed a man out there. I can see it on you.", "Stay back. I heard the shots.", "Murderer. Everyone knows.",
                           "Folks saw what you did.", "There's a man's blood on your sleeve.", "I've got nothing you want. Please."]),
        ("any", "armoured", ["Plate and steel in a quiet town? Expecting a war?", "You clank when you walk, you know.",
                             "That armour's seen some fighting.", "Must be heavy, all that iron.", "Who are you fixing to fight?"]),
        ("any", "masked", ["Why the mask, stranger?", "Take that rag off your face.", "Nobody honest hides their face.",
                           "I don't like talking to a mask.", "Sheriff! There's a masked man here!"]),
        ("law", "masked", ["Lower that bandana. Now.", "Masked men get shot in this town.", "Show me your face, or move along."]),
        ("law", "bloody", ["Whose blood is that?", "You'd better have a good story for that blood.", "Don't make me ask twice: what happened?"]),
        ("child", "bloody", ["Are you hurt? There's blood everywhere!", "Ewww!"]),
        ("any", "gunDrawn", ["Easy with that iron.", "Put that thing away, will you?", "No call for a gun in the street.",
                             "Holster it, friend. This is a quiet town.", "That's how folks get hurt.", "Point that at the ground, at least.",
                             "Law says guns stay holstered in town.", "You're making people nervous."]),
        ("any", "rich", ["You look like you've done well for yourself.", "Heavy purse you've got there.", "Money's burning a hole in your pocket, I'd guess.",
                         "Careful flashing that much money.", "Struck it rich, did you?", "The bank would be glad of that money."]),
        ("any", "hurt", ["You're bleeding, friend.", "Go see the doctor, you look awful.", "What happened to you?",
                         "Sit down before you fall down.", "You've been in a scrap, haven't you?", "Somebody get this one some water.",
                         "You're white as a sheet.", "Doc's office is up the street. Go."]),
        ("any", "robbery", ["Somebody's been helping themselves around here.", "Lock your doors, they're saying.", "There's a thief in town.",
                            "The sheriff's asking questions all over.", "Folks are jumpy after what happened.", "Watch your pockets today."]),
        ("any", "shooting", ["Did you hear those shots?", "Who's shooting in the middle of town?", "Get down, there's shooting!",
                             "That was gunfire, plain as day.", "Somebody's going to get killed.", "Shots, close by. Stay low.",
                             "The sheriff will want to know who fired.", "My ears are still ringing."]),
        ("any", "festival", ["Happy fair day!", "Have you tried the pies? Best in the county.", "Fireworks tonight over the square!",
                             "Everybody's in town for the fair.", "Prices are down for the festival.", "There's music at the bell later.",
                             "Best day of the season.", "Wear your good hat, it's a festival."]),
        ("any", "horseback", ["Fine horse you've got.", "Mind you don't trample the flowers.", "Tie that horse up by the trough.",
                              "Nice and easy through town, now.", "That's a good-looking animal.", "Your horse looks thirsty.",
                              "Slow down, there's children about.", "Walk him, don't run him, in town."]),
        ("any", "honourHigh", ["It's {name}! Good to see you.", "Folks speak well of you around here.", "You're always welcome in {town}.",
                               "Heard what you did. Much obliged.", "There goes a decent soul.", "My door's open to you, {name}.",
                               "Town's lucky to have friends like you.", "Proud to shake your hand."]),
        ("any", "honourLow", ["Keep moving.", "I've heard things about you.", "Don't come any closer.",
                              "We don't need your kind here.", "Watch yourself in this town.", "Hmph. You again."]),
        ("any", "jailed", ["Heard there's somebody in the cells.", "The jail's got a guest today.", "Somebody's doing time.",
                           "Serves them right, I expect."]),
        ("any", "prisoner", ["You brought him in alive? That takes nerve.", "Look at that, an outlaw in irons.", "The jail's the place for that one.",
                             "Well done. He had it coming."]),

        // MARK: The law (sheriff and deputies)
        ("law", "dawn", ["Up all night keeping watch. Coffee's earned.", "Morning rounds. Everything's quiet.", "Sun's up. Night was peaceful.",
                         "First patrol of the day.", "Mornin'. No trouble overnight, I hope."]),
        ("law", "day", ["Keep it civil and we'll get on fine.", "I'm watching the street. Always.", "Quiet towns don't happen by accident.",
                        "If you see trouble, come find me.", "Business is my business when it's crooked.", "Walk on, citizen. All's well."]),
        ("law", "dusk", ["Lamps are going on. Time for the evening round.", "Saloon gets rowdy about now. I'll be close.",
                         "Evening. Head home before the trouble starts.", "Getting dark. Eyes open.", "Last light. Folks get bold after this."]),
        ("law", "night", ["I'm on watch. Go on home.", "What brings you out at this hour?", "Nothing good happens after midnight.",
                          "Night patrol. Keep moving.", "Streets are empty. I like 'em that way.", "If you can't sleep, try the church steps. Quieter."]),
        ("law", "rain", ["Rain keeps the troublemakers indoors.", "Wet patrol. Part of the job.", "Mud shows every footprint. Handy, that.",
                         "Even outlaws don't ride in this."]),
        ("law", "storm", ["Get indoors till this passes.", "Storm like this, I've got fallen fences to look at.", "Keep off the street till it blows over."]),
        ("law", "wanted", ["You know there's paper on you.", "Come with me quiet and it goes easier.", "Pay what's owed, or you'll see the inside of my jail.",
                           "I could take you in right now.", "Don't make me chase you.", "Turn yourself in. The cell's not so bad.",
                           "Talk to me before this gets worse.", "Every lawman for miles knows your face."]),
        ("law", "gunDrawn", ["Holster that. Now.", "You draw in my town, you'd better have a reason.", "I won't ask twice. Put it away.",
                             "That iron stays in leather on these streets.", "Lower it, slow.", "Some folks pull a gun once. Some never get the chance again.",
                             "You want a cell for the night?", "Put it up, or I'll put you up."]),
        ("law", "rich", ["Keep that money out of sight. Thieves have eyes.", "Bank's safer than your pockets.", "Flush, are we? Spend it honest."]),
        ("law", "hurt", ["Who did that to you? I'll want a name.", "Get to the doctor. That's an order.", "You look like you lost a fight with a bear.",
                         "If someone in town did that, I'll hear about it."]),
        ("law", "robbery", ["Somebody stole in my town. I'll find them.", "Seen anybody suspicious?", "Thief's still close. I can feel it.",
                            "I'll have whoever did it in irons by sundown.", "Keep your eyes open. Report anything odd.", "Robbery in broad daylight. Bold."]),
        ("law", "shooting", ["Who fired those shots?", "Stay back. I'll handle this.", "Nobody shoots in my town without answering for it.",
                             "Clear the street!", "Did you see who it was?", "Everybody calm down. Let me look."]),
        ("law", "festival", ["Fair day. Plenty of pockets to pick. I'm watching.", "Enjoy the fair. Keep it friendly.",
                             "Fireworks tonight. Keep the guns quiet.", "Busiest day of the season for me."]),
        ("law", "horseback", ["Walk that horse through town.", "No galloping on the main street.", "Tie him up at the rail and stay a while.",
                              "Good horse. Keep him off the boardwalk."]),
        ("law", "honourHigh", ["Good to see you, {name}. Wish everybody was like you.", "If you ever want a deputy's star, ask.",
                               "You've done this town a service.", "I sleep better knowing you're about.", "Glad you're on our side, {name}."]),
        ("law", "honourLow", ["I'm keeping an eye on you.", "One step out of line.", "I know your sort.", "Don't give me a reason.",
                              "You'll find my jail's got room."]),
        ("law", "jailed", ["Sit tight. Your time'll pass.", "Pay the fine and you walk. Simple as that.", "Nobody's broke out of my jail yet.",
                           "Meals come twice a day. Don't complain.", "You've got time to think on it now.", "Keep your hands off those bars.",
                           "Rest easy. Nobody'll bother you in there.", "Behave and the door opens soon enough."]),
        ("law", "prisoner", ["You brought him in breathing. That's rare.", "I'll take it from here.", "There's a cell waiting for him.",
                             "Good work. He'll stand trial.", "Keep him moving. Cells are this way."]),
        ("sheriff", "day", ["This badge doesn't polish itself.", "Twenty years and still nobody's taken this town.", "My town, my rules. Fair rules.",
                            "Folks pay taxes for quiet streets. They get 'em."]),
        ("sheriff", "night", ["I don't sleep much. Somebody has to watch.", "The night shift's mine. Always has been.", "Go home, {name}. I've got the town."]),
        ("sheriff", "wanted", ["I've been waiting for you to show your face.", "My jail's got your name on a cell.", "Last chance to come in easy.",
                               "I've brought in worse than you."]),
        ("sheriff", "jailed", ["You'll do your time and walk out a better soul. Or not.", "Talk to me when you want to pay up.", "Comfortable? Good."]),
        ("deputy", "day", ["The sheriff's got me walking the whole town today.", "Deputy work's mostly walking.", "I'll be sheriff someday. You watch."]),
        ("deputy", "night", ["Long night. Long, quiet night.", "Can't wait for my relief.", "Owls are the only company I get out here."]),

        // MARK: Keepers (every shop counter and the banker)
        ("keeper", "dawn", ["Just opening up. Give me a minute.", "Morning! First customer gets my best smile.", "Sweeping the boardwalk. Come in soon.",
                            "Early riser. I like that in a customer."]),
        ("keeper", "day", ["Business is good today.", "Come in, come in. Have a look.", "Cash only. No credit, no trades.",
                           "Everything's priced fair. Ask anyone.", "Stock came in on the wagon."]),
        ("keeper", "dusk", ["Closing soon. Get what you need.", "Last customers of the day.", "Counting the till, then home.",
                            "Come back in the morning if you miss me."]),
        ("keeper", "night", ["We're shut. Sorry, friend.", "Nobody's buying at this hour.", "Come back when the sign says open."]),
        ("keeper", "rain", ["Come in out of the wet.", "Rain's bad for business.", "Shake off before you come in, please.",
                            "Folks stay home in weather like this."]),
        ("keeper", "storm", ["Shutters are up. Storm's a bad one.", "If the roof holds, I'll be open tomorrow."]),
        ("keeper", "wanted", ["Can't sell to you while there's paper out.", "Square things with the sheriff first.",
                              "I'd lose my license serving you.", "Don't make a scene in my place."]),
        ("keeper", "gunDrawn", ["No guns in my place!", "Put that down before you break something.", "Take what you want, just put it away!",
                                "You'll scare off my customers.", "I've got a cash box, not a fortune."]),
        ("keeper", "rich", ["Now there's a customer with money!", "For you, the good stock from the back.", "Spend some of that here, why don't you?",
                            "I've got just the thing for a person of means.", "Big spender coming through!", "Money talks, and I'm listening."]),
        ("keeper", "hurt", ["You're bleeding on my floor.", "Doctor first, shopping second.", "Sit down a minute. You look rough."]),
        ("keeper", "robbery", ["I'm counting my stock twice today.", "Somebody got robbed. Could've been me.", "Keeping the till locked today.",
                               "If I catch the thief, he'll wish the sheriff got him first.", "I've got a shotgun under this counter. Just saying."]),
        ("keeper", "shooting", ["Get away from the window!", "Shooting's bad for business.", "I'm locking the door till that stops."]),
        ("keeper", "festival", ["Fair prices for the fair!", "Festival sale. Ten off.", "Busiest day of the season. Line up!",
                                "Everybody's buying today.", "Get it before it's gone. Fair day only."]),
        ("keeper", "horseback", ["Hitch your horse out front.", "No horses in the shop, please.", "Leave him at the rail. He'll keep."]),
        ("keeper", "honourHigh", ["My favorite customer!", "For you, the best I've got.", "Always glad when you come by, {name}.",
                                  "A good name's worth more than gold. Yours is solid."]),
        ("keeper", "honourLow", ["Cash up front. All of it.", "I'm watching your hands.", "Make it quick.", "Don't touch what you're not buying."]),
        ("storekeeper", "day", ["Flour, salt, lamp oil, rope. The usual?", "I can order anything from the city. Takes a month.",
                                "Got fresh seed in for the spring planting.", "Emeralds? I'll change those for dollars."]),
        ("storekeeper", "rich", ["You could buy out the whole store.", "Tell you what, I'll throw in a box of matches."]),
        ("barkeep", "dawn", ["Bar's not open. Coffee is, though.", "Mopping up after last night. Mind the puddles."]),
        ("barkeep", "day", ["What'll it be?", "Sarsaparilla's cold, if you're not drinking.", "Pull up a stool. Rest your feet.",
                            "Stew's on. Best in town, they tell me."]),
        ("barkeep", "dusk", ["Here comes the evening crowd.", "Piano player's tuning up.", "Cards start at sundown.", "Grab a table before they're gone."]),
        ("barkeep", "night", ["Last call was an hour ago.", "One more and then you're out.", "You don't have to go home, but you can't stay here.",
                              "I've heard every story twice tonight.", "Lock up's soon. Drink up."]),
        ("barkeep", "rain", ["Rain brings 'em in. Good for business.", "Dry off by the stove."]),
        ("barkeep", "gunDrawn", ["Guns go on the hook by the door.", "Not in my saloon, friend.", "Last fella who drew in here left through the window."]),
        ("barkeep", "festival", ["Fair day! Every glass is full.", "Busiest night of the season.", "Music, dancing, and the good stuff."]),
        ("barkeep", "hurt", ["Here, a clean rag. Press it on there.", "Whiskey's good for the wound, not for the belly."]),
        ("butcher", "day", ["Fresh cuts this morning.", "Hams are curing out back.", "Bring me pelts in winter. They fetch more."]),
        ("butcher", "gunDrawn", ["I've got a cleaver and I know how to use it.", "Put that away. You're near my knives."]),
        ("doctor", "day", ["Wash your hands. Saves more lives than I do.", "Office hours till sundown.", "Bandages and tonics, fair prices."]),
        ("doctor", "hurt", ["Sit. Let me look at that.", "That needs stitching. Come inside.", "You've lost a fair bit of blood.",
                            "Lucky it missed the bone.", "Hold still. This'll sting.", "Who patched you up last? They did a poor job."]),
        ("doctor", "shooting", ["Gunfire means work for me.", "Bring any wounded straight here.", "I hope nobody's hit."]),
        ("gunsmith", "day", ["Clean your gun every day and it'll never fail you.", "I can make that iron shoot straighter.",
                             "Rounds in stock. Shells too.", "A dirty barrel's a dangerous barrel."]),
        ("gunsmith", "gunDrawn", ["Let me see that piece. Nice balance.", "Mind where that's pointed in a gun shop.",
                                  "That one needs oiling. I can tell from here.", "Holster it and hand it here. I'll look it over."]),
        ("gunsmith", "rich", ["With that money I could build you something special.", "Upgrades aren't cheap, but they're worth it."]),
        ("tailor", "day", ["A good coat lasts twenty years.", "Let me take your measurements.", "New cloth came in from the east."]),
        ("tailor", "rain", ["Wool coat keeps you dry. Mostly.", "You'll ruin that hat in this weather."]),
        ("tailor", "rich", ["A person of means needs a proper suit.", "Silk lining, perhaps?"]),
        ("stablehand", "day", ["Horses fed and watered.", "Need a shoe looked at?", "I'll board your horse for a fair price."]),
        ("stablehand", "horseback", ["That horse needs a rest. Let me take him.", "Good teeth on that one.", "He's been ridden hard. Water him.",
                                     "Nice gait. Somebody trained him right.", "I'll brush him down if you like."]),
        ("stablehand", "rain", ["Horses are spooked by the thunder.", "Stalls are dry, at least."]),
        ("smith", "dawn", ["Forge takes an hour to heat. Started early."]),
        ("smith", "day", ["Hammer's been going since sunup.", "Bring me iron, I'll make you something.", "Hot work. Stand back from the forge."]),
        ("banker", "day", ["Your money's safer in the vault than in your boot.", "Savings earn a little every day.",
                           "Emeralds changed for dollars, right at the teller.", "Ledgers balance to the penny."]),
        ("banker", "rich", ["Have you considered a savings account?", "That's a tidy sum. Let us keep it safe.",
                            "Interest every day. Hard to beat.", "The vault has room for that and more."]),
        ("banker", "robbery", ["The vault's never been cracked. Never.", "Extra guard on the vault tonight.", "If they come for the bank, they'll regret it.",
                               "I keep the combination in my head. Nowhere else."]),
        ("banker", "gunDrawn", ["Please, this is a bank!", "There's nothing in the drawer worth dying for.", "Don't. The vault's on a timer."]),
        ("banker", "wanted", ["The bank doesn't serve wanted men.", "Settle with the law, then we'll talk money."]),

        // MARK: Townsfolk
        ("folk", "dawn", ["Off to work before the heat.", "Rooster got me up again.", "Morning. Water's cold in the trough.", "Early start for everybody today."]),
        ("folk", "day", ["Got a fence to fix and no nails.", "My sister's coming in on the stage.", "Somebody's selling puppies by the well.",
                         "Heard the mill wheel's broken again.", "Fixing the porch today. Third time this year.", "Wagon wheel came off on the north road."]),
        ("folk", "dusk", ["Heading home for supper.", "Long day. Feet are sore.", "Chores done. Time to sit.", "Wife's got beans on."]),
        ("folk", "night", ["Couldn't sleep. Too hot.", "Walking off supper.", "Heard a noise. Probably nothing.", "Lantern's low. Better get home."]),
        ("folk", "rain", ["My cellar's flooding.", "Laundry's ruined.", "Roads will be soup tomorrow.", "Good day to stay in and mend things."]),
        ("folk", "wanted", ["I didn't see you. I didn't see nothing.", "Please, I've got children.", "The sheriff's looking for you.",
                            "Just keep walking, mister."]),
        ("folk", "gunDrawn", ["Mister, I'm unarmed.", "I'm just going home!", "Whatever it is, I didn't do it.", "Easy now, easy."]),
        ("folk", "rich", ["Must be nice to have money.", "Buy a round at the saloon, then!", "Could you spare a dollar for the church roof?"]),
        ("folk", "hurt", ["Lord, look at you.", "Lean on me. Doc's this way.", "You need a doctor, quick."]),
        ("folk", "robbery", ["Somebody took my neighbor's chickens.", "We never used to lock doors here.", "Who'd steal from us? We've got nothing."]),
        ("folk", "shooting", ["Get inside, get inside!", "Was that a gunshot?", "Kids! Away from the windows!", "Not again."]),
        ("folk", "festival", ["Going to the dance later?", "I entered my pie in the contest.", "Kids are wild for the fireworks.", "Best fair in years."]),
        ("folk", "horseback", ["Can I pet him?", "Wish I had a horse like that.", "Careful, the street's slick."]),
        ("folk", "honourHigh", ["Folks are still talking about you.", "You're a credit to the territory.", "Would you sit for supper with us sometime?"]),
        ("folk", "honourLow", ["Mother warned me about your kind.", "I'll be on my way.", "Please don't make trouble."]),
        ("farmer", "dawn", ["Cows don't milk themselves.", "Up before the sun, like always.", "Got to beat the heat to the field.",
                            "Fields look good in the morning light."]),
        ("farmer", "day", ["Weeds grow faster than the corn.", "Fence is down on the east side again.", "Hoeing till my back gives out.",
                           "Crows ate half my seed.", "Hay's drying nice in this sun."]),
        ("farmer", "dusk", ["Bringing the animals in.", "Barn door's sticking again.", "Long day in the dirt."]),
        ("farmer", "night", ["Coyotes after my hens again.", "Up checking on a sick calf."]),
        ("farmer", "rain", ["Finally! The fields needed this.", "Rain's worth more than gold right now.", "Ground'll be soft for plowing.",
                            "Too much and it'll rot the roots.", "Thank the heavens for the rain."]),
        ("farmer", "storm", ["Hail will flatten the wheat.", "Got to get the cattle in!", "Lightning spooked the mule clean through the fence."]),
        ("farmer", "horseback", ["Keep that horse out of my rows.", "Good plow horse, that one'd be."]),
        ("farmer", "festival", ["Brought my best pumpkin for the judging.", "Harvest's in. Time to celebrate."]),
        ("elder", "dawn", ["Old bones wake early.", "Seen a lot of sunrises. Never tired of them.", "My mornings start with a walk. Doctor's orders."]),
        ("elder", "day", ["In my day, this street was a cattle trail.", "Sit with me a while. My stories are free.",
                          "Young folks rush too much.", "I remember when the first wagon came through."]),
        ("elder", "dusk", ["Evenings are for the porch.", "Sun sets the same as it did sixty years ago.", "My knees say rain tomorrow."]),
        ("elder", "night", ["Can't sleep much, at my age.", "Nights were darker before the lamps.", "Off with you, youngster. It's late."]),
        ("elder", "rain", ["Told you it'd rain. Knees never lie.", "We had a flood in '49. Washed the church away.", "Rain's a blessing. Mostly."]),
        ("elder", "gunDrawn", ["I've seen what those do. Put it away.", "Guns solve one problem and make three more.", "Young fool. Holster that."]),
        ("elder", "wanted", ["Your mother'd be ashamed.", "It's never too late to turn yourself in."]),
        ("elder", "shooting", ["Just like the bad old days.", "I buried friends after shooting like that."]),
        ("elder", "festival", ["Fairs were bigger in my day.", "I'll dance one dance. Just one."]),
        ("child", "dawn", ["I'm up first! I win!", "Ma made biscuits!", "I fed the chickens already!"]),
        ("child", "day", ["Wanna play marbles?", "I can whistle with my fingers!", "Teacher says I'm smart.", "I caught a lizard. Look!",
                          "Is it true you fought a bear?", "Bet I can run to the well faster than you."]),
        ("child", "dusk", ["Ma's calling me for supper.", "Just five more minutes!", "Fireflies are out!"]),
        ("child", "night", ["I'm not scared of the dark. Much.", "Pa says there's wolves out there.", "Don't tell Ma I'm out."]),
        ("child", "rain", ["Puddles! Watch me jump!", "I'm making mud pies.", "I'm soaked and I don't even care!"]),
        ("child", "storm", ["The thunder's so loud!", "I'm hiding under the bed till it stops."]),
        ("child", "gunDrawn", ["Whoa! Is it loaded?", "Can I hold it? Please?", "Pa says never touch a gun.", "Bang bang! Ha!"]),
        ("child", "horseback", ["Can I ride him? Please please please?", "What's his name?", "He's so tall!", "I'm gonna have a horse someday."]),
        ("child", "wanted", ["You're on the poster! Are you a bandit?", "Ma says you're dangerous.", "I'm gonna tell the sheriff!"]),
        ("child", "hurt", ["Does it hurt a lot?", "You need a bandage!", "Ew, blood!"]),
        ("child", "shooting", ["Was that a gun?!", "I'm scared!", "Hide!"]),
        ("child", "festival", ["Fireworks tonight!", "I won a ribbon!", "I ate three pies!", "Can we stay up late?"]),
        ("child", "rich", ["Are you rich? Can I have a penny?", "Buy me candy?"]),
        ("child", "honourHigh", ["You're my hero!", "When I grow up I'm gonna be just like you!", "Everybody says you're the best!"]),
        ("child", "jailed", ["Did you go to jail? What's it like?", "My friend says the jail has rats."]),
        ("child", "prisoner", ["You caught a real outlaw!", "Is he gonna get hanged?"]),
        ("drunk", "dawn", ["Is it morning already? Who did that?", "Sun's too bright. Too bright!", "Where's my hat? I had a hat."]),
        ("drunk", "day", ["I'm not drunk, I'm resting.", "Spare a nickel for a thirsty man?", "I used to be a gold miner, you know.",
                          "The ground keeps moving on me.", "Shh. The barkeep's looking for me."]),
        ("drunk", "dusk", ["Ah, my favorite time of day. Saloon time.", "Here's to the sunset. And the next glass.", "Evening, friend! Old friend! Who are you?"]),
        ("drunk", "night", ["Who moved the street?", "I'll sleep right here. It's comfortable.", "Sing with me! No? Your loss.",
                            "The moon's following me again.", "One more, then home. Maybe."]),
        ("drunk", "rain", ["Free bath! Ha!", "The sky's crying 'cause the saloon's closed."]),
        ("drunk", "gunDrawn", ["Whoa, which one of you is pointing that?", "Shoot the bottle, not me!", "I give up! What'd I do?"]),
        ("drunk", "rich", ["You're my best friend now.", "Buy me one? Just one?", "You look like a man who buys rounds."]),
        ("drunk", "wanted", ["You're famous! Your face is everywhere!", "I won't tell. I can't remember anything anyway."]),
        ("drunk", "festival", ["Fair day means free punch!", "Dance with me! Anybody!", "Best festival ever. I think."]),
        ("drunk", "horseback", ["Your horse has two heads. No, wait.", "Can he carry me home?"]),
        ("drunk", "hurt", ["You look worse than me. That's saying something.", "Here, have a swig. For the pain."]),
        ("preacher", "dawn", ["Morning prayers are the sweetest.", "A new day, a fresh start.", "Bless you this morning, traveler."]),
        ("preacher", "day", ["Service on Sunday. All are welcome.", "The church roof needs mending. Donations help.",
                             "Love thy neighbor. Even the difficult ones.", "Have you made your peace today?", "Be kind. It's free."]),
        ("preacher", "dusk", ["Evening vespers soon.", "Rest your soul as the sun sets.", "The day's work is done. Give thanks."]),
        ("preacher", "night", ["The darkness passes. It always does.", "Trouble sleeping? Pray on it.", "Even at night, the church door's open."]),
        ("preacher", "rain", ["Rain is a blessing on the land.", "The heavens water the fields."]),
        ("preacher", "storm", ["Shelter in the church if you need it.", "Fear not the thunder."]),
        ("preacher", "wanted", ["It's never too late to make things right.", "Turn yourself in, child. Ease your burden.", "Confession's good for the soul."]),
        ("preacher", "gunDrawn", ["Violence begets violence.", "Lay down that weapon, friend.", "Blessed are the peacemakers."]),
        ("preacher", "hurt", ["Come, let me tend to you.", "Bless you, you're wounded.", "The doctor's near. I'll walk you."]),
        ("preacher", "robbery", ["Thou shalt not steal, the book says.", "I'll pray for the thief. And lock the poor box."]),
        ("preacher", "shooting", ["Lord, let no one be hurt.", "Stop this madness!"]),
        ("preacher", "festival", ["The harvest is a gift. Celebrate it.", "Joy is holy too.", "Even I'll dance today."]),
        ("preacher", "honourHigh", ["Your good deeds are known, {name}.", "Bless you for what you've done.", "Walk in grace, friend."]),
        ("preacher", "honourLow", ["There's still time to change your ways.", "I'll pray for you.", "Redemption's a long road. Start walking."]),
        ("craftsman", "day", ["Measure twice, cut once.", "Good tools make good work.", "I've got an order to finish by Friday.", "Hand me that, would you? Thanks."]),
        ("miner", "dawn", ["First shift's going down.", "Lamp's full. Pick's sharp. Let's go."]),
        ("miner", "day", ["Mind the gas down there.", "Found a good seam last week.", "Dust gets in everything.", "Company store prices are robbery."]),
        ("miner", "night", ["Night shift. Same dark either way.", "Can't tell day from night down below.", "Rest while you can."]),
        ("miner", "rain", ["Shaft floods when it rains like this.", "Pumps'll be working overtime."]),
        ("miner", "gunDrawn", ["No guns near the shaft! One spark and we're gone!", "Put that down. There's powder about."]),
        ("citizen", "day", ["The gardens are lovely this time of year.", "Trams run every quarter hour.", "Have you seen the new monument?",
                            "Everything's orderly here. Just how we like it."]),
        ("citizen", "night", ["Curfew's soon.", "The patrols keep us safe at night."]),
        ("citizen", "rain", ["The drains keep the streets dry here.", "Umbrella weather."]),
        ("citizen", "gunDrawn", ["Guards! A gun!", "Please put that away. This is a civilized city.", "The soldiers will see you."]),

        // MARK: Prisoners (outlaws brought in alive)
        ("prisoner", "dawn", ["Another day in this box.", "Sun's up. Still here."]),
        ("prisoner", "day", ["Let me out of here!", "You'll regret this.", "My gang will come for me.", "I want a lawyer.", "These beans taste like boot leather."]),
        ("prisoner", "dusk", ["Another day gone.", "I can see the sunset through the bars. Pretty."]),
        ("prisoner", "night", ["Can't sleep on this plank.", "Rats in here. Big ones.", "Psst. Got a file?", "Someday I'll be out."]),
        ("prisoner", "rain", ["The roof leaks right on my bunk.", "Cold and wet. Lovely."]),
        ("prisoner", "wanted", ["Join me in here, why don't you?", "Ha. They'll get you too."]),
        ("prisoner", "jailed", ["Welcome to the neighborhood.", "Nice cell. Better than mine."]),
    ]

    // (role or group|key) -> lines.
    static let pools: [String: [String]] = {
        var d: [String: [String]] = [:]
        for (r, k, lines) in table { d["\(r)|\(k)", default: []] += lines }
        return d
    }()
    static var count: Int { Set(table.flatMap { $0.2 }).count }
    static let all: Set<String> = Set(table.flatMap { $0.2 })

    // The speaker's role (for the pools) and the pools that speak for it, most specific first.
    static func role(_ m: Mob) -> String {
        let v = m.villager
        if m.baby || v?.role == "child" { return "child" }
        switch v?.role ?? "worker" {
        case "sheriff": return "sheriff"
        case "deputy": return "deputy"
        case "banker": return "banker"
        case "prisoner": return "prisoner"
        case "miner": return "miner"
        case "citizen": return "citizen"
        case "farmer": return "farmer"
        case "elder": return "elder"
        case "shopkeeper":
            switch v?.shopKind {
            case .general?: return "storekeeper"
            case .saloon?: return "barkeep"
            case .butcher?: return "butcher"
            case .doctor?: return "doctor"
            case .gunsmith?: return "gunsmith"
            case .tailor?: return "tailor"
            case .stable?: return "stablehand"
            case .blacksmith?: return "smith"
            default: return "storekeeper"
            }
        case "craftsman": return v?.profession == "cleric" ? "preacher" : (v?.profession == "farmer" ? "farmer" : "craftsman")
        default: return v?.profession == "nitwit" ? "drunk" : (v?.profession == "cleric" ? "preacher" : "folk")
        }
    }
    static func groups(_ role: String) -> [String] {
        switch role {
        case "sheriff", "deputy": return [role, "law", "any"]
        case "storekeeper", "barkeep", "butcher", "doctor", "gunsmith", "tailor", "stablehand", "smith", "banker": return [role, "keeper", "any"]
        case "child", "prisoner": return [role]
        case "drunk", "preacher", "citizen": return [role, "any"]
        default: return [role, "folk", "any"]
        }
    }

    // What fits right now: pressing matters first, then the hour, the weather and the rest.
    static func situation(_ g: Game, _ m: Mob) -> (urgent: [String], soft: [String]) {
        var urgent: [String] = [], soft: [String] = []
        let town = TownLaw.town(of: m, g)
        if g.survival {
            if Jail.term != nil { urgent.append("jailed") }
            else if Honour.bounty(town) > 0 || Honour.outlawKnown(g) { urgent.append("wanted") }
            if TownLaw.state.prisoner != nil { urgent.append("prisoner") }
            if g.health <= 8 { urgent.append("hurt") }
        }
        if Guns.index(g.held.item) != nil { urgent.append("gunDrawn") }
        if let s = TownLaw.lastShot, g.clock - s.clock < 90, simd_length(s.at - m.pos) < 80 { urgent.append("shooting") }
        else if TownLaw.heat(town) > 0 { urgent.append("robbery") }
        let f = g.dayFraction
        soft.append(f >= 0.95 || f < 0.07 ? "dawn" : (f < 0.42 ? "day" : (f < 0.56 ? "dusk" : "night")))
        // (P478: as it falls where they stand: no rain over a desert or a savanna, snow in the cold, so no rain talk there)
        let wet = g.precipitation(Int(floor(m.pos.x)), Int(floor(m.pos.y)), Int(floor(m.pos.z))) == 1
        if wet && g.weather.thunder > 0.3 { soft.append("storm") } else if wet && g.weather.rain > 0.3 { soft.append("rain") }
        if let r = g.riding, r.kind == .horse || r.gaited { soft.append("horseback") }
        if g.money >= 5000 { soft.append("rich") }
        // D21: how he looks and what he has just done (Deeds.swift).
        if Deeds.bloody(g) { urgent.append(Deeds.killedPerson(g) ? "killer" : "bloody") }
        if Deeds.armoured(g) { soft.append("armoured") }
        if Deeds.masked(g) { urgent.append("masked") }
        if Seasons.festival { soft.append("festival") }
        if g.survival {
            if Honour.value >= Honour.respected { soft.append("honourHigh") }
            else if Honour.value <= Honour.disreputable { soft.append("honourLow") }
        }
        return (urgent, soft)
    }

    // Town-wide memory of what was said (newest last), so a line doesn't come round again for a long while.
    static let memory = 96
    private static var recent: [String] = []
    private static var recentSet = Set<String>()
    static func remember(_ t: String) {
        recent.append(t); recentSet.insert(t)
        if recent.count > memory { recentSet.remove(recent.removeFirst()) }
    }
    static func forget() { recent = []; recentSet = [] }

    // A line for this speaker now, or nil (say a recorded take instead).
    static func line(_ g: Game, _ m: Mob, _ ctx: TownVoice.Ctx) -> String? {
        guard on, ctx == .greet || ctx == .chatter || ctx == .night else { return nil }
        let (urgent, soft) = situation(g, m)
        let keys: [String]
        if !urgent.isEmpty && Rand.float(in: 0..<1) < urgentShare { keys = urgent }
        else if Rand.float(in: 0..<1) < share { keys = soft }
        else { return nil }
        let r = role(m)
        var cands: [String] = []
        for k in keys { for grp in groups(r) { for t in pools["\(grp)|\(k)"] ?? [] where !recentSet.contains(t) && LineTruth.fits(g, m, t) { cands.append(t) } } }
        guard let t = cands.randomElement() else { return nil }
        remember(t)
        lastSaid = fill(t, g, m)
        return lastSaid
    }
    // TownVoice.play: a line written here (captioned, with a murmur), not a recorded take gone missing.
    private static var lastSaid = ""
    static func spoken(_ t: String) -> Bool { t == lastSaid || all.contains(t) }

    static func fill(_ t: String, _ g: Game, _ m: Mob) -> String {
        guard t.contains("{") else { return t }
        return t.replacingOccurrences(of: "{name}", with: TownBoard.playerName)
            .replacingOccurrences(of: "{town}", with: TownLaw.town(of: m, g))
    }

    // One of a few lines (the jail's own words), never the one said last.
    private static var lastPick = ""
    static func pick(_ lines: [String]) -> String {
        var t = lines.randomElement() ?? ""
        if t == lastPick && lines.count > 1 { t = lines[(lines.firstIndex(of: t)! + 1) % lines.count] }
        lastPick = t
        lastSaid = t
        return t
    }
}
