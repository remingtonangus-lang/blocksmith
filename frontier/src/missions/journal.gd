extends RefCounted
## Ruth's journal: one entry per finished mission (story and Strangers), written in her voice, with sentences that
## follow what she actually did (story flags), and a small ink sketch drawn in code for each (Sketch, below: a few
## primitives — hills, buildings, figures, horses, cattle, trees, fire, rain, a comet — jittered like a pen line).
## Shown by the journal menu (src/ui/menus.gd open_journal).
##
## Entry: {"t": base text, "if": [[flag, value, sentence], ...], "sk": sketch}. A sentence is added when the flag
## matches: a bool/string/int equals, null = unset or false, "*" = set at all, "<n" / ">=n" = numeric compare.

const ENTRIES := {
	# ---------------------------------------------------------------- chapter 1
	"c1_rider": {"t": "Rode into Bitter Spring at sundown. A newsboy was selling the syndicate's land offer at a nickel a copy, which is about what the land is worth to anybody but them. Stabled the mare. She looked at the town the way I did.", "sk": "town"},
	"c1_drover": {"t": "Two syndicate men were finishing off a drover by the river at Willow Bend. I finished them instead. The drover is Hap Lindqvist: large, Swedish, and grateful in a way that makes me tired. Made camp.", "sk": "camp"},
	"c1_inquiries": {"t": "Asked questions in Bitter Spring. The saloon had a card cheat, the sheriff had a warning, and the churchyard had a fresh grave with nobody's name on it. Three answers, none of them to what I asked.", "sk": "grave"},
	"c1_greer": {"t": "Tobias Greer sold me the Shales' whereabouts and then sold them mine. Rode into the ambush he'd arranged.",
		"if": [["spared_greer_kid", true, "One of them lived. I let him go so Cutter Shale would hear my name from somebody who'd seen me use it."],
			["spared_greer_kid", null, "None of them rode home. Greer will have to find new customers."]], "sk": "post"},
	"c1_fire": {"t": "They came for the camp at night with torches. Hap held, the horses nearly didn't, and a boy nobody invited ran them clear. Billy Pruitt. Fourteen, he says. I decided to stay, which I hadn't decided before.", "sk": "fire"},
	# ---------------------------------------------------------------- chapter 2
	"c2_lantern": {"t": "Port Linden. Walked in on two men taking a sledge to Augustus Fenn's press.",
		"if": [["lantern_talked", true, "I talked them out of it. They looked disappointed."], ["lantern_talked", false, "They drew. Fenn's floor wants scrubbing."],
			["ruth_in_print", true, "Fenn asked to print my name and I let him. I may regret it."], ["ruth_in_print", false, "Fenn asked to print my name. I told him no."],
			["*", "*", "He named the man behind the syndicate: Lucius Pell, a lawyer who never raises his voice."]], "sk": "press"},
	"c2_cards": {"t": "Cards at the Corinthian with Pell's clerk, old Merrow, and Del Arceneaux, who cheats better than the house.",
		"if": [["cheat_caught", true, "The dealer was stacking the deck for the clerk. I said so out loud."], ["cheat_caught", false, "The dealer was stacking the deck and I let it pass. I am not proud of that."],
			["returned_stakes", true, "Gave every man back his stake."], ["returned_stakes", false, "Kept the table money. Del approved, which ought to worry me."],
			["*", "*", "Del rides with us now. Count your money."]], "sk": "cards"},
	"c2_thornwood": {"t": "Billy led me into the Thornwood camp he ran from. Heard the paymaster say Thursday's silver at the Exchange is bait, and Pell means to be surprised by it.",
		"if": [["paid_billy", true, "They said Billy owed them. I paid, and we fought anyway."], ["paid_billy", false, "They said Billy owed them. I didn't pay. We fought."]], "sk": "pines"},
	"c2_exchange": {"t": "Thursday night, the Linden Exchange. No silver in the vault, only forged deeds, one signed by a man two days after his funeral.",
		"if": [["bank_quiet", true, "Got past the watchman without hurting him."], ["took_satchel", true, "I took the bait money. Pell will make me pay for it twice."],
			["took_satchel", false, "Left the bait money where it lay."], ["*", "*", "The deputies were waiting. We left in a hurry."]], "sk": "vault"},
	"c2_terms": {"t": "My face is on a poster on Fenn's door, drawn from the old show bills. They gave me a better hat than I ever owned.",
		"if": [["deeds_kept", true, "Pell offered to withdraw the bounty for the deeds. I kept them. Fenn will print."],
			["deeds_kept", false, "Pell offered to withdraw the bounty for the deeds. I gave them up. Fenn's story is dead, and something else with it."]], "sk": "poster"},
	# ---------------------------------------------------------------- chapter 3
	"c3_ranch": {"t": "Rode south to tell Ingrid Halvorsen her south section is in Pell's deeds. Cutter Shale's men were pulling down her windmill when I got there.",
		"if": [["mill_warned", true, "Warned them off. Two ran."], ["mill_warned", false, "I drew on Kett. That settled the windmill question."],
			["ingrid_pays", true, "She'll pay a dollar a head on delivery."], ["ingrid_pays", false, "I asked nothing for the drive. Ingrid looked at me as if I'd lost a tooth."]], "sk": "windmill"},
	"c3_doc": {"t": "Shale's riders broke a little girl's leg at Mesquite Wells. The only doctor in forty miles was drunk at Fausto's.",
		"if": [["doc_sober", true, "I kept the bottle from him. His hands shook, and he set it anyway."], ["doc_sober", false, "He had his one drink. His hands stopped shaking."],
			["ines_leg_clean", false, "Inés will walk with a hitch."], ["*", "*", "Cornelius Abernathy rides with us now. He says it's temporary. They all say that."]], "sk": "cantina"},
	"c3_drive": {"t": "Drove Ingrid's cattle through the Breaks to the Ybarra well.",
		"if": [["drive_route", "narrows", "We took the Narrows. Rustlers on the rim, and a stampede in the rocks."], ["drive_route", "mesa", "Went round by the mesa. Dry lightning at night, and a stampede in the dark."],
			["*", "*", "Billy rode swing and will mention it until spring."]], "sk": "cattle"},
	"c3_rights": {"t": "Cutter Shale rode into the Ybarra yard with a Water Board order he'd had printed himself.",
		"if": [["drew_on_cutter", true, "I drew on him with children in the yard. He got away. Rosa hasn't forgiven me."], ["drew_on_cutter", false, "I let him ride. There were children in the yard."],
			["well_fouled", true, "His men fouled the well that night."], ["well_fouled", false, "His men came for the well that night. It's still sweet."]], "sk": "well"},
	"c3_fork": {"t": "Night ride up the Dry Fork with Del to Cutter's line camp.",
		"if": [["cutter_fate", "jailed", "Cutter is in Mabry's cell, and Mabry is ashamed enough now to keep him there."],
			["cutter_fate", "dead", "Cutter Shale is dead. That's two names off Tom's list. It doesn't feel like two."],
			["*", "*", "It rained when we got home. The first in four months. Hap stood in it with his hat off."]], "sk": "rain"},
	# ---------------------------------------------------------------- chapter 4
	"c4_coldwater": {"t": "First snow on the Kestrel. Coldwater is a strike camp, and the company pays in scrip. Met Joseph Kehoe, who'd read about me in Fenn's paper and didn't seem to hold it against me.",
		"if": [["stood_with_miners", true, "When the company guards came for the strike kitchen, I stood with the miners."], ["stood_with_miners", false, "I kept out of sight and followed Asa Shale. Heard about Thursday's powder."]], "sk": "mountains"},
	"c4_mine": {"t": "Thursday noon at the Kestrel mine they lit the powder on four men in Number Two.",
		"if": [["miners_saved", ">=4", "We dug. All four came out breathing."], ["miners_saved", "<4", "Not all of them came out. Tommy Rees is under the timber."],
			["fuse_proof", true, "I rode down the man who lit it. He'll say who paid him, in court or otherwise."]], "sk": "mine"},
	"c4_pass": {"t": "Joseph took me straight up the face of the Kestrel in a snowstorm, and then the mountain came down.",
		"if": [["left_joseph", false, "Dug Joseph out. He said nothing. He doesn't need to."], ["left_joseph", true, "I left Joseph in the snow and went after the tracks. He dug himself out. I owe him that, and more."]], "sk": "snow"},
	"c4_asa": {"t": "Line shack under the ridge. Asa Shale is nineteen, and he cried when he told me about Harlan's Siding.",
		"if": [["spared_asa", true, "I sent him west under another name. Joseph said it was the hardest shot I didn't take."], ["asa_killed", true, "I killed him. Joseph has not spoken since."]], "sk": "shack"},
	"c4_strike": {"t": "They came down with torches for the strike kitchen.",
		"if": [["kitchen_burned", false, "We held it."], ["kitchen_burned", true, "It burned anyway."],
			["strike_terms", "signed", "Garrity signed the miners' terms with my pistol in his ear. It won't hold in any court."],
			["strike_terms", "inspector", "Garrity and his letter went to the territorial inspector. Slow, and lawful, and theirs."],
			["*", "*", "Joseph rides with us now. Home to Willow Bend in the snow."]], "sk": "office"},
	# ---------------------------------------------------------------- chapter 5
	"c5_plan": {"t": "Fenn brought word: Thursday's westbound carries the syndicate payroll and Pell's own ledger. We argued about doing it the way Tom's train was done.",
		"if": [["train_rules", "ledger", "My rules: the ledger only, and nobody fires first."], ["train_rules", "all", "My rules: everything in the safe."],
			["hap_comes", true, "Hap will hold the horses."], ["hap_comes", false, "Hap keeps the camp."]], "sk": "rails"},
	"c5_train": {"t": "Kessler's Tank. I rode down the express and jumped for the car. A messenger stood in the door, the way Tom did.",
		"if": [["messenger_killed", false, "I talked him down. He'll go home tonight."], ["messenger_killed", true, "I shot him. I have been trying not to think about it, and failing."],
			["payroll_taken", true, "We took the payroll with the ledger."], ["hap_wounded", true, "Pell's men were in the caboose. They hit Hap."]], "sk": "train"},
	"c5_owe": {"t": "What we owe.",
		"if": [["hap_alive", true, "Hap lived. Doc says the ball will stay where it is, like most of Hap's opinions."], ["hap_alive", false, "Hap is dead. There's nobody to sing the hymns badly."],
			["ledger_to_fenn", true, "The ledger went to Fenn and the payroll back where it came from."], ["ledger_to_fenn", false, "We kept it all."],
			["del_left", true, "Del left in the night. She took less than she could have."], ["joseph_left", true, "Joseph rode north. He didn't say goodbye, which is how he says it."]], "sk": "lamp"},
	# ---------------------------------------------------------------- chapter 6
	"c6_warrants": {"t": "Eben rode on Willow Bend at dawn with Pell's warrants.",
		"if": [["asa_warned", true, "Asa came back first to warn us. The boy I let go."], ["camp_held", true, "We held the camp."], ["camp_stand", false, "We scattered and drew them off."],
			["*", "*", "Eben named the place: San Lazaro."]], "sk": "camp"},
	"c6_eben": {"t": "San Lazaro, at dusk. Eben Shale in a roofless chapel with his Bible.",
		"if": [["eben_fate", "jailed", "I shot the gun out of his hand and took him in alive. Tom would have liked that, I think. I'm less sure I do."],
			["eben_fate", "dead", "He drew and I was faster. That's the end of the list."],
			["eben_fate", "executed", "I killed him on his knees. Ashby offered me his men. I haven't answered."]], "sk": "chapel"},
	"c6_ink": {"t": "Port Linden, the morning after.",
		"if": [["pell_fate", "arrested", "Fenn printed the ledger. I watched the marshal walk Pell out of his own office, still reaching for his hat."],
			["pell_fate", "untouched", "Pell stood on the depot platform without a mark on him."], ["pell_fate", "robbed", "We robbed Pell's own office. Doc said what everyone was thinking."],
			["watch_set", true, "I set Tom's watch. It's twenty past four in Port Linden, and it was time."]], "sk": "depot"},
	"c6_spring": {"t": "Spring, 1900. The snow is off and the creeks run. I rode the country and looked at what's left. More than I expected. Less than I wanted. About right, Tom would say.", "sk": "spring"},
	# ---------------------------------------------------------------- Strangers
	"s_carriage": {"t": "A man named Pettigrew built a carriage that runs on steam and opinions. It ran off without him on the Greer road. I caught it, found the brake, and kept my eyebrows.",
		"if": [["invested_pettigrew", true, "Bought a share in the Pettigrew Motor Company for twenty dollars. I expect it to be worth exactly that, in kindling."],
			["invested_pettigrew", false, "He asked me to invest. I declined. He'll remember me, he says. So will the henhouses."]], "sk": "carriage"},
	"s_herd": {"t": "Clementine Voss lost eight head the morning she buried her husband. They didn't wander. Walt's partner, Lyman Gage, drove them off to sell before the syndicate took the place.",
		"if": [["spared_partner", true, "I walked him back to face her. She kept him on to work it off. She is a better Christian than me, or a softer fool, and I'm not sure there's a difference."],
			["spared_partner", false, "I settled it with a gun. She has her cattle. She doesn't feel better. I told her most people don't."]], "sk": "cattle"},
	"s_photo": {"t": "A lady photographer wanted me on a ledge over Thornwood Creek with a cougar. The cat obliged. The plate was for a dime novel: Miss Ruthie Rides Again.",
		"if": [["posed_for_novel", true, "I let her print it. Somewhere in Chicago a man is drawing my hat wrong."], ["posed_for_novel", false, "I broke the plate. Miss Ruthie stays in Kansas, where I buried her."]], "sk": "cougar"},
	"s_skulls": {"t": "Dr. Horatio Bundy reads the bumps on your head in the Mesquite Wells plaza and the cards in a mirror ring.",
		"if": [["bundy_caught_at_table", true, "Caught the ring at the table."], ["took_cut", false, "He paid Ramon Ortiz back and walked west. Mr. Ortiz's boy will be a farmer."],
			["took_cut", true, "I took half his purse. Doc would call it commerce. Mr. Ortiz called it something else, in Spanish."]], "sk": "skull"},
	"s_comet": {"t": "Silas Wren watched the sky from a rock in the Kestrel for nineteen years, waiting on a comet nobody believed in. I caught his supper and carried his lens.",
		"if": [["stayed_for_comet", true, "I stayed. It came at a quarter past two, low over the ridge, and he went with it. I watched it all the way down for him."],
			["stayed_for_comet", false, "I rode on before the cold. I hope it came. I think it did."]], "sk": "comet"},
	"s_detective": {"t": "Hollis Crane, detective, asked me to get him past the railroad bulls to the ford. At the ford were his friends, the bounty hunters. He was the bait, and I was the fish.",
		"if": [["protected_crane", true, "I let him go back to Chicago owing me a favour. He says he pays his debts. We'll see."], ["protected_crane", false, "I walked him to Mabry. He'll be out by supper."]], "sk": "ford"},
	"s_newsboy": {"t": "Pip Callahan sells the Lantern and owed a man named Rourke for a hundred papers that died in the rain. I rode a bundle to Greer's for him.",
		"if": [["pip_bundle_in_time", true, "Made the four o'clock stage with two minutes to spare."], ["pip_bundle_in_time", false, "Late. The agent paid half."],
			["paid_pip_debt", true, "Paid the rest of the boy's debt and made Rourke count it in front of him."], ["paid_pip_debt", false, "Told Rourke the debt was forgiven. He disagreed, briefly."],
			["*", "*", "Pip sweeps Fenn's press room now. Real wages. He says I'll be on page one when he's editor."]], "sk": "newspaper"},
	"s_pledge": {"t": "Hannah Bright came to Coldwater with a hatchet for the Silver Dollar. The saloon belongs to her husband, Jack, who walked out on her eleven years ago.",
		"if": [["smashed_barrels", true, "I handed her a hatchet. Eleven years of rye went into the mud. Jack watched it go like a funeral."],
			["smashed_barrels", false, "I made her put the hatchet down and say what she came to say. She'd forgotten. There was coffee."]], "sk": "barrels"},
	"s_surveyor": {"t": "Followed a lost man's boot tracks in circles across the Breaks. Linus Aldridge, surveyor. His stakes weren't for a railroad. They were for the syndicate's water line to the deep wells, on no map at all.",
		"if": [["surveyor_quiet", true, "Got his field book out of the slot canyon without being seen."], ["field_book_to_fenn", true, "The book went to Fenn."],
			["field_book_to_fenn", false, "The railroad paid thirty dollars to have the book back. I didn't read all of it. I read enough."]], "sk": "canyon"},
	"s_marvel": {"t": "A medicine show at the Thornwood camp, glass balls in the air, and a barker who knew Miss Ruthie when she was sixteen. Cassius Mulvey. He calls himself Marvel now and sells laudanum as an elixir.",
		"if": [["outshot_pearl", true, "Outshot his lovely assistant. It was easy. That has always been the trouble."],
			["exposed_marvel", true, "I told the loggers what was in the bottles. They poured it in the creek."], ["exposed_marvel", false, "I let him pack up and go, for the old days. I'm not sure that was a kindness to anyone."]], "sk": "medicine"},
	# ---------------------------------------------------------------- the Outfit's own
	"p_hap": {"t": "Rode out with Hap to the draw where his crew is buried. The syndicate has fenced the dead.",
		"if": [["hap_crew", "wire", "I cut the wire. The riders objected. Hap said the words over three men who can see the whole sky now."],
			["hap_crew", "sang", "Hap sang to them through the fence. Badly, and in Swedish. The riders took their hats off before the end."]], "sk": "grave"},
	"p_del": {"t": "Orrin Tate holds Del's marker, and Del meant to take the night boat. I walked her to the pier.",
		"if": [["del_marker", "paid", "I paid the forty dollars. Del says now she can't leave; she'd be in my debt. She has a strange idea of what makes people stay."],
			["del_marker", "ticket", "I gave her a paid ticket and let her choose. She stayed, and Tate's men drew. She has a strange idea of what makes people stay."]], "sk": "ford"},
	"p_doc": {"t": "A letter of forgiveness came for Doc from Philadelphia, fourteen years late. Then a wagon went over on a teamster at the wells.",
		"if": [["doc_teamster_legs", 2, "We were in time. Doc's hands didn't shake once. He made me say I noticed."], ["doc_teamster_legs", 1, "We were late. The man lost a leg, and lived."],
			["doc_letter", "answered", "I told him to answer it. He's writing to introduce her to the doctor."], ["doc_letter", "burned", "I told him to burn it. He did, and kept a little of the ash."]], "sk": "well"},
	"p_billy": {"t": "Billy's colt was in Amos Pike's corral at Thornwood. We went for him on a moonless night.",
		"if": [["billy_colt", "paid", "I left fifteen dollars under a stone on the gatepost, so the boy owns his horse clean."],
			["billy_colt", "taken", "I said take him; they owe the boy three years of wages. Billy cheered. He'll do it the same way when he's grown. That's what worries me."]], "sk": "pines"},
	"p_joseph": {"t": "A cavalry captain wanted Joseph to find a family that left the agency for the winter hunting ground. Joseph found them first, on the north fork. They were cold, and we gave them meat.",
		"if": [["joseph_trail", "false", "I lied to the captain for him. South canyon. Joseph thanked me, and then didn't say anything for a day."],
			["joseph_trail", "refused", "I let Joseph answer the captain himself. He said his piece. He'd waited nine years to say it."]], "sk": "snow"},
}

## The entry's text for the flags as they stand.
static func text_for(id: String, flags: Dictionary) -> String:
	var e: Dictionary = ENTRIES.get(id, {})
	if e.is_empty():
		return ""
	var out: String = e.t
	for c in e.get("if", []):
		if _match(flags, str(c[0]), c[1]):
			out += " " + str(c[2])
	return out

static func _match(flags: Dictionary, key: String, want) -> bool:
	if key == "*":
		return true
	var has := flags.has(key)
	var v = flags.get(key)
	if want == null:
		return not has or v == false or v == null
	if not has:
		return false
	if typeof(want) == TYPE_STRING:
		var w: String = want
		if w == "*":
			return true
		if w.begins_with(">="):
			return float(v) >= float(w.substr(2))
		if w.begins_with("<"):
			return float(v) < float(w.substr(1))
		return str(v) == w
	if typeof(want) == TYPE_BOOL:
		return bool(v) == want
	return v == want

static func sketch_for(id: String) -> String:
	return str(ENTRIES.get(id, {}).get("sk", "hills"))

## Every entry has text and a sketch kind the drawer knows (journal self-test; bots).
static func selftest(mission_ids: Array) -> Dictionary:
	var missing := []
	for id in mission_ids:
		if not ENTRIES.has(id):
			missing.append(id)
		elif not SKETCHES.has(sketch_for(id)):
			missing.append("%s (sketch %s)" % [id, sketch_for(id)])
	return {"ok": missing.is_empty(), "missing": missing}

# ------------------------------------------------------------------ sketches
## Each sketch is a list of primitives in a 1 x 0.6 frame (x right, y down; ground near y = 0.45).
const SKETCHES := {
	"hills": [["ground"], ["hills", 0.0], ["sun", 0.8, 0.12]],
	"town": [["ground"], ["hills", 0.3], ["bldg", 0.18, 0.16, 0.2, 1], ["bldg", 0.36, 0.14, 0.15, 0], ["bldg", 0.52, 0.18, 0.24, 1], ["sun", 0.85, 0.3], ["rider", 0.78]],
	"camp": [["ground"], ["hills", 0.6], ["tent", 0.25], ["tent", 0.42], ["fire", 0.62], ["figure", 0.7], ["tree", 0.88, 0.3]],
	"grave": [["ground"], ["hills", 0.1], ["cross", 0.45], ["mound", 0.45], ["cross", 0.62], ["tree", 0.2, 0.32], ["moon", 0.8, 0.12]],
	"post": [["ground"], ["hills", 0.2], ["bldg", 0.35, 0.3, 0.17, 0], ["horse", 0.72], ["figure", 0.18]],
	"fire": [["ground"], ["tent", 0.3], ["fire", 0.32], ["fire", 0.5], ["horse", 0.75], ["moon", 0.85, 0.1]],
	"press": [["ground"], ["bldg", 0.3, 0.4, 0.3, 0], ["press", 0.5], ["figure", 0.2]],
	"cards": [["table"], ["cards"], ["lamp_hang", 0.5]],
	"pines": [["ground"], ["pine", 0.15, 0.35], ["pine", 0.28, 0.3], ["pine", 0.62, 0.4], ["pine", 0.8, 0.33], ["figure", 0.42], ["figure", 0.5]],
	"vault": [["vault"], ["figure", 0.25]],
	"poster": [["poster"]],
	"windmill": [["ground"], ["hills", 0.4], ["windmill", 0.35], ["fence"], ["rider", 0.72]],
	"cantina": [["ground"], ["adobe", 0.4], ["bottle", 0.78], ["sun", 0.15, 0.14]],
	"cattle": [["ground"], ["hills", 0.5], ["cow", 0.22], ["cow", 0.38], ["cow", 0.52], ["cow", 0.31], ["rider", 0.8]],
	"well": [["ground"], ["adobe", 0.25], ["well", 0.62], ["figure", 0.78]],
	"rain": [["ground"], ["tent", 0.3], ["figure", 0.6], ["rain"]],
	"mountains": [["ground"], ["peaks"], ["snow"], ["bldg", 0.3, 0.12, 0.12, 1], ["bldg", 0.45, 0.1, 0.1, 0]],
	"mine": [["ground"], ["peaks"], ["headframe", 0.4], ["figure", 0.62]],
	"snow": [["peaks"], ["snow"], ["figure", 0.45], ["figure", 0.53]],
	"shack": [["ground"], ["peaks"], ["bldg", 0.42, 0.18, 0.13, 1], ["snow"]],
	"office": [["ground"], ["bldg", 0.25, 0.3, 0.25, 0], ["fire", 0.7], ["figure", 0.6]],
	"rails": [["ground"], ["rails"], ["sun", 0.8, 0.2], ["figure", 0.3], ["figure", 0.38]],
	"train": [["ground"], ["rails"], ["loco", 0.5], ["rider", 0.25]],
	"lamp": [["table"], ["lamp", 0.5]],
	"chapel": [["ground"], ["chapel", 0.45], ["moon", 0.82, 0.12], ["figure", 0.2]],
	"depot": [["ground"], ["rails"], ["bldg", 0.4, 0.4, 0.18, 1], ["figure", 0.25]],
	"spring": [["ground"], ["hills", 0.7], ["tree", 0.2, 0.33], ["tree", 0.32, 0.25], ["river"], ["rider", 0.7], ["sun", 0.85, 0.12]],
	"carriage": [["ground"], ["hills", 0.2], ["locomobile", 0.5], ["rider", 0.2]],
	"cougar": [["cliff"], ["cougar", 0.45], ["figure", 0.78], ["camera", 0.9]],
	"skull": [["skull", 0.35], ["cards_small", 0.7]],
	"comet": [["peaks"], ["comet"], ["figure", 0.5], ["stars"]],
	"ford": [["ground"], ["river"], ["reeds"], ["figure", 0.4], ["figure", 0.62], ["figure", 0.7]],
	"newspaper": [["newspaper"]],
	"barrels": [["ground"], ["barrel", 0.3], ["barrel", 0.44], ["barrel", 0.58], ["figure", 0.78]],
	"canyon": [["canyon"], ["tripod", 0.5], ["figure", 0.3]],
	"medicine": [["ground"], ["medwagon", 0.4], ["glass"], ["figure", 0.78]],
}

class Sketch extends Control:
	## One journal sketch: ink on the page, a pen line that wobbles a little, hatching for shade.
	var kind := "hills"
	var seed_value := 1
	var ink := Color(0.16, 0.11, 0.08, 0.92)
	var _rng := RandomNumberGenerator.new()
	var _r := Rect2()

	func _init() -> void:
		custom_minimum_size = Vector2(420, 250)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_kind(k: String, s: int) -> void:
		kind = k
		seed_value = s
		queue_redraw()

	func _p(x: float, y: float) -> Vector2:
		return _r.position + Vector2(x * _r.size.x, y / 0.6 * _r.size.y)

	## A hand line: a few wobbling segments.
	func _line(a: Vector2, b: Vector2, w := 1.6) -> void:
		var n := maxi(2, int(a.distance_to(b) / 18.0))
		var prev := a
		var nrm := (b - a).orthogonal().normalized()
		for i in range(1, n + 1):
			var q := a.lerp(b, float(i) / n)
			if i < n:
				q += nrm * _rng.randf_range(-1.1, 1.1)
			draw_line(prev, q, ink, w, true)
			prev = q

	func _ln(x0: float, y0: float, x1: float, y1: float, w := 1.6) -> void:
		_line(_p(x0, y0), _p(x1, y1), w)

	func _poly(pts: Array, closed := true, w := 1.6) -> void:
		for i in pts.size() - (0 if closed else 1):
			_ln(pts[i][0], pts[i][1], pts[(i + 1) % pts.size()][0], pts[(i + 1) % pts.size()][1], w)

	func _circle(x: float, y: float, r: float, w := 1.4) -> void:
		var c := _p(x, y)
		var rr := r * _r.size.x
		var prev := c + Vector2(rr, 0)
		for i in range(1, 25):
			var a := TAU * i / 24.0
			var q := c + Vector2(cos(a), sin(a)) * rr * _rng.randf_range(0.96, 1.04)
			draw_line(prev, q, ink, w, true)
			prev = q

	func _hatch(x0: float, y0: float, x1: float, y1: float, step := 0.018) -> void:
		# parallel strokes at 45 degrees (in frame units), clipped to the box
		var h := y1 - y0
		var c := x0 - h
		while c < x1:
			# stroke from (c, y1) to (c + h, y0); clip x to [x0, x1]
			var ta := clampf((x0 - c) / h, 0.0, 1.0)
			var tb := clampf((x1 - c) / h, 0.0, 1.0)
			if tb > ta:
				_ln(c + h * ta, y1 - h * ta, c + h * tb, y1 - h * tb, 0.8)
			c += step

	func _draw() -> void:
		_rng.seed = seed_value
		_r = Rect2(Vector2(10, 8), size - Vector2(20, 16))
		# a ruled frame like a pasted-in card
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color(1.0, 0.98, 0.9, 0.35), true)
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), Color(ink, 0.6), false, 1.5)
		draw_rect(Rect2(Vector2(6, 6), size - Vector2(12, 12)), Color(ink, 0.3), false, 1.0)
		for prim in SKETCHES.get(kind, SKETCHES.hills):
			_prim(prim)

	func _prim(pr: Array) -> void:
		var k: String = pr[0]
		var x: float = float(pr[1]) if pr.size() > 1 else 0.5
		match k:
			"ground":
				_ln(0.0, 0.45, 1.0, 0.45)
				for i in 14:
					var gx := _rng.randf()
					_ln(gx, 0.47 + _rng.randf() * 0.1, gx + 0.03, 0.47 + _rng.randf() * 0.1, 0.7)
			"hills":
				var pts := []
				for i in 9:
					pts.append([i / 8.0, 0.3 + 0.08 * sin(i * 1.7 + x * 6.0) + 0.03 * _rng.randf()])
				_poly(pts, false, 1.2)
			"peaks":
				_poly([[0.0, 0.42], [0.18, 0.16], [0.3, 0.3], [0.48, 0.06], [0.66, 0.28], [0.8, 0.14], [1.0, 0.36]], false, 1.6)
				# shade the far flank of the big peak with short strokes falling from the ridge line
				for i in 8:
					var t := (i + 1) / 9.0
					var rx := 0.48 + t * 0.18
					var ry := 0.06 + t * 0.22
					_ln(rx - 0.01, ry + 0.012, rx - 0.035, ry + 0.07 * (1.0 - t * 0.5), 0.8)
				_ln(0.44, 0.1, 0.48, 0.06, 1.2)
				_ln(0.48, 0.06, 0.52, 0.11, 1.2)
			"sun":
				_circle(x, float(pr[2]), 0.035)
				for i in 8:
					var a := TAU * i / 8.0
					_ln(x + cos(a) * 0.05, pr[2] + sin(a) * 0.05, x + cos(a) * 0.075, pr[2] + sin(a) * 0.075, 1.0)
			"moon":
				_circle(x, float(pr[2]), 0.03)
				_circle(x + 0.015, float(pr[2]) - 0.006, 0.026, 0.8)
			"stars":
				for i in 18:
					var sx := _rng.randf()
					var sy := _rng.randf() * 0.2
					_ln(sx - 0.004, sy, sx + 0.004, sy, 1.0)
					_ln(sx, sy - 0.006, sx, sy + 0.006, 1.0)
			"bldg":
				var w: float = pr[2]
				var h: float = pr[3]
				_poly([[x, 0.45], [x, 0.45 - h], [x + w, 0.45 - h], [x + w, 0.45]], false)
				if int(pr[4]) == 1:
					_ln(x - 0.01, 0.45 - h, x + w * 0.5, 0.45 - h - 0.07)
					_ln(x + w * 0.5, 0.45 - h - 0.07, x + w + 0.01, 0.45 - h)
				else:
					_ln(x, 0.45 - h - 0.04, x + w, 0.45 - h - 0.04)
					_ln(x, 0.45 - h - 0.04, x, 0.45 - h)
					_ln(x + w, 0.45 - h - 0.04, x + w, 0.45 - h)
				_poly([[x + w * 0.4, 0.45], [x + w * 0.4, 0.45 - h * 0.45], [x + w * 0.6, 0.45 - h * 0.45], [x + w * 0.6, 0.45]], false, 1.2)
				_hatch(x + w * 0.75, 0.45 - h * 0.7, x + w * 0.92, 0.45 - h * 0.45)
			"adobe":
				_poly([[x - 0.18, 0.45], [x - 0.18, 0.27], [x + 0.18, 0.27], [x + 0.18, 0.45]], false)
				for i in 5:
					_circle(x - 0.15 + i * 0.075, 0.285, 0.006, 1.0)
				_poly([[x - 0.03, 0.45], [x - 0.03, 0.36], [x + 0.03, 0.36], [x + 0.03, 0.45]], false, 1.2)
				_hatch(x + 0.08, 0.33, x + 0.15, 0.4)
			"tent":
				_poly([[x - 0.08, 0.45], [x, 0.32], [x + 0.08, 0.45]], false)
				_ln(x, 0.32, x + 0.02, 0.45, 1.0)
			"fire":
				_ln(x - 0.03, 0.45, x + 0.03, 0.43)
				_ln(x - 0.03, 0.43, x + 0.03, 0.45)
				for i in 4:
					var fx := x - 0.02 + i * 0.013
					_poly([[fx - 0.008, 0.43], [fx + _rng.randf_range(-0.01, 0.01), 0.37 - _rng.randf() * 0.03], [fx + 0.008, 0.43]], false, 1.1)
			"figure":
				_circle(x, 0.31, 0.009)
				_ln(x, 0.325, x, 0.39)
				_ln(x, 0.39, x - 0.012, 0.45)
				_ln(x, 0.39, x + 0.012, 0.45)
				_ln(x, 0.34, x - 0.015, 0.37)
				_ln(x, 0.34, x + 0.015, 0.37)
				_ln(x - 0.017, 0.3, x + 0.017, 0.3, 1.4)         # hat brim
			"horse":
				_horse(x, 0.45)
			"rider":
				_horse(x, 0.45)
				_circle(x - 0.005, 0.27, 0.008)
				_ln(x - 0.005, 0.285, x - 0.002, 0.33)
				_ln(x - 0.002, 0.33, x + 0.015, 0.36)
				_ln(x - 0.02, 0.262, x + 0.01, 0.262, 1.3)
			"cow":
				_poly([[x - 0.045, 0.37], [x + 0.04, 0.37], [x + 0.045, 0.4], [x - 0.045, 0.4]])
				_ln(x + 0.04, 0.37, x + 0.065, 0.375)
				_ln(x + 0.065, 0.375, x + 0.06, 0.395)
				_ln(x + 0.058, 0.372, x + 0.075, 0.36, 1.0)
				for lx in [-0.035, -0.02, 0.02, 0.035]:
					_ln(x + lx, 0.4, x + lx, 0.44, 1.2)
			"tree":
				var h: float = pr[2]
				_ln(x, 0.45, x, 0.45 - h * 0.5, 2.0)
				_circle(x, 0.45 - h * 0.7, h * 0.22)
				_circle(x - 0.03, 0.45 - h * 0.6, h * 0.15, 1.0)
			"pine":
				var h2: float = pr[2]
				_ln(x, 0.45, x, 0.45 - h2, 1.4)
				for i in 5:
					var yy := 0.45 - h2 * (0.2 + i * 0.17)
					var ww := 0.05 * (1.0 - i * 0.18)
					_ln(x - ww, yy + 0.02, x, yy - 0.03, 1.2)
					_ln(x + ww, yy + 0.02, x, yy - 0.03, 1.2)
			"cross":
				_ln(x, 0.45, x, 0.35, 2.0)
				_ln(x - 0.025, 0.37, x + 0.025, 0.37, 2.0)
			"mound":
				_poly([[x - 0.06, 0.45], [x - 0.03, 0.43], [x + 0.03, 0.43], [x + 0.06, 0.45]], false, 1.2)
			"windmill":
				_ln(x - 0.03, 0.45, x, 0.18)
				_ln(x + 0.03, 0.45, x, 0.18)
				_ln(x - 0.02, 0.36, x + 0.02, 0.36, 1.0)
				for i in 8:
					var a := TAU * i / 8.0
					_ln(x, 0.17, x + cos(a) * 0.05, 0.17 + sin(a) * 0.05, 1.0)
				_ln(x, 0.17, x + 0.08, 0.15, 1.2)
			"fence":
				_ln(0.05, 0.41, 0.6, 0.41, 1.0)
				for i in 8:
					_ln(0.05 + i * 0.078, 0.45, 0.05 + i * 0.078, 0.39, 1.4)
			"well":
				_poly([[x - 0.05, 0.45], [x - 0.05, 0.4], [x + 0.05, 0.4], [x + 0.05, 0.45]], false)
				_ln(x - 0.045, 0.4, x - 0.045, 0.31)
				_ln(x + 0.045, 0.4, x + 0.045, 0.31)
				_ln(x - 0.06, 0.31, x + 0.06, 0.31, 2.0)
				_ln(x, 0.31, x, 0.37, 1.0)
			"rain":
				for i in 40:
					var rx := _rng.randf()
					var ry := _rng.randf() * 0.4
					_ln(rx, ry, rx - 0.01, ry + 0.04, 0.8)
			"snow":
				for i in 40:
					_circle(_rng.randf(), _rng.randf() * 0.42, 0.002, 1.0)
			"headframe":
				_ln(x - 0.06, 0.45, x, 0.15)
				_ln(x + 0.06, 0.45, x, 0.15)
				_ln(x, 0.15, x + 0.12, 0.45)
				_circle(x, 0.16, 0.02)
				_ln(x - 0.04, 0.35, x + 0.04, 0.35, 1.0)
				_ln(x - 0.025, 0.27, x + 0.025, 0.27, 1.0)
			"rails":
				_ln(0.0, 0.43, 1.0, 0.43, 1.4)
				_ln(0.0, 0.45, 1.0, 0.45, 1.4)
				for i in 30:
					_ln(i / 30.0, 0.425, i / 30.0 - 0.006, 0.455, 0.9)
			"loco":
				_poly([[x - 0.2, 0.42], [x - 0.2, 0.33], [x + 0.06, 0.33], [x + 0.06, 0.42]], false)
				_poly([[x + 0.06, 0.42], [x + 0.06, 0.25], [x + 0.16, 0.25], [x + 0.16, 0.42]], false)
				_ln(x - 0.14, 0.33, x - 0.14, 0.25, 2.0)
				_ln(x - 0.165, 0.25, x - 0.115, 0.25, 2.0)
				_ln(x - 0.2, 0.42, x - 0.26, 0.45)
				for wx in [-0.15, -0.07, 0.02, 0.11]:
					_circle(x + wx, 0.415, 0.017)
				for i in 4:
					_circle(x - 0.13 - i * 0.02, 0.2 - i * 0.03, 0.012 + i * 0.006, 1.0)
			"lamp":
				_poly([[x - 0.02, 0.32], [x - 0.03, 0.22], [x + 0.03, 0.22], [x + 0.02, 0.32]])
				_circle(x, 0.335, 0.02)
				for i in 8:
					var a := TAU * i / 8.0
					_ln(x + cos(a) * 0.06, 0.26 + sin(a) * 0.06, x + cos(a) * 0.09, 0.26 + sin(a) * 0.09, 0.8)
			"lamp_hang":
				_ln(x, 0.0, x, 0.08, 1.0)
				_poly([[x - 0.04, 0.12], [x, 0.08], [x + 0.04, 0.12]], false)
			"table":
				_ln(0.1, 0.38, 0.9, 0.38, 2.0)
				_ln(0.15, 0.38, 0.15, 0.55)
				_ln(0.85, 0.38, 0.85, 0.55)
				_hatch(0.1, 0.39, 0.9, 0.42, 0.012)
			"cards":
				for i in 5:
					var cx := 0.32 + i * 0.07
					_poly([[cx, 0.37], [cx + 0.01, 0.22], [cx + 0.07, 0.225], [cx + 0.06, 0.37]])
				_circle(0.3, 0.33, 0.015)
				_circle(0.72, 0.34, 0.015)
				_circle(0.74, 0.32, 0.015)
			"cards_small":
				for i in 3:
					var cx := x + i * 0.05
					_poly([[cx, 0.42], [cx + 0.01, 0.3], [cx + 0.05, 0.305], [cx + 0.04, 0.42]])
			"vault":
				_poly([[0.45, 0.45], [0.45, 0.1], [0.85, 0.1], [0.85, 0.45]])
				_circle(0.65, 0.27, 0.11)
				_circle(0.65, 0.27, 0.025)
				for i in 6:
					var a := TAU * i / 6.0
					_ln(0.65, 0.27, 0.65 + cos(a) * 0.06, 0.27 + sin(a) * 0.06, 1.0)
				_poly([[0.5, 0.45], [0.53, 0.41], [0.6, 0.41], [0.6, 0.45]], false, 1.0)
			"poster":
				_poly([[0.3, 0.02], [0.7, 0.02], [0.7, 0.58], [0.3, 0.58]])
				_ln(0.36, 0.07, 0.64, 0.07, 3.0)
				_circle(0.5, 0.24, 0.07)
				_ln(0.4, 0.17, 0.6, 0.17, 2.0)
				_ln(0.44, 0.17, 0.46, 0.12)
				_ln(0.46, 0.12, 0.54, 0.12)
				_ln(0.54, 0.12, 0.56, 0.17)
				_ln(0.47, 0.22, 0.48, 0.25, 1.0)
				_ln(0.36, 0.42, 0.64, 0.42, 3.0)
				_ln(0.4, 0.48, 0.6, 0.48, 1.2)
				_ln(0.4, 0.52, 0.6, 0.52, 1.2)
			"press":
				_poly([[x - 0.08, 0.45], [x - 0.08, 0.3], [x + 0.08, 0.3], [x + 0.08, 0.45]], false)
				_circle(x + 0.1, 0.32, 0.03)
				_ln(x - 0.06, 0.36, x + 0.06, 0.36, 2.0)
			"chapel":
				_poly([[x - 0.15, 0.45], [x - 0.15, 0.22], [x - 0.05, 0.22], [x - 0.05, 0.12], [x + 0.05, 0.12], [x + 0.05, 0.22], [x + 0.15, 0.22], [x + 0.15, 0.45]], false)
				_ln(x, 0.08, x, 0.12, 1.4)
				_ln(x - 0.012, 0.095, x + 0.012, 0.095, 1.4)
				_poly([[x - 0.03, 0.45], [x - 0.03, 0.33], [x, 0.3], [x + 0.03, 0.33], [x + 0.03, 0.45]], false)
				_hatch(x + 0.06, 0.25, x + 0.14, 0.44)
			"river":
				_ln(0.0, 0.5, 0.4, 0.48, 1.2)
				_ln(0.4, 0.48, 1.0, 0.52, 1.2)
				_ln(0.0, 0.56, 0.5, 0.54, 1.2)
				_ln(0.5, 0.54, 1.0, 0.58, 1.2)
				for i in 8:
					var wx := 0.1 + i * 0.1
					_ln(wx, 0.53, wx + 0.03, 0.525, 0.8)
			"reeds":
				for i in 16:
					var rx := 0.05 + _rng.randf() * 0.3
					_ln(rx, 0.48, rx + _rng.randf_range(-0.01, 0.01), 0.38, 0.9)
			"locomobile":
				_poly([[x - 0.12, 0.38], [x + 0.06, 0.38], [x + 0.06, 0.33], [x - 0.12, 0.33]])
				_ln(x + 0.1, 0.38, x + 0.1, 0.24, 2.4)
				_ln(x + 0.1, 0.24, x + 0.1, 0.12, 1.2)
				_circle(x - 0.09, 0.415, 0.03)
				_circle(x + 0.07, 0.405, 0.045)
				_ln(x - 0.06, 0.33, x - 0.04, 0.27, 1.2)
				for i in 5:
					_circle(x + 0.1 + i * 0.03, 0.1 - i * 0.02, 0.012 + i * 0.007, 1.0)
				_ln(x - 0.3, 0.36, x - 0.17, 0.36, 0.8)
				_ln(x - 0.3, 0.4, x - 0.15, 0.4, 0.8)
			"cliff":
				_poly([[0.0, 0.3], [0.35, 0.28], [0.6, 0.3], [0.65, 0.58]], false)
				_hatch(0.45, 0.32, 0.62, 0.56)
				_ln(0.6, 0.3, 1.0, 0.32)
			"cougar":
				_poly([[x - 0.08, 0.24], [x + 0.06, 0.22], [x + 0.08, 0.26], [x - 0.06, 0.28]])
				_circle(x + 0.09, 0.22, 0.018)
				_ln(x - 0.08, 0.25, x - 0.15, 0.22, 1.2)
				_ln(x - 0.15, 0.22, x - 0.16, 0.25, 1.2)
				for lx in [-0.06, -0.04, 0.04, 0.06]:
					_ln(x + lx, 0.27, x + lx + 0.01, 0.3, 1.2)
			"camera":
				_poly([[x - 0.03, 0.3], [x + 0.03, 0.3], [x + 0.03, 0.35], [x - 0.03, 0.35]])
				_ln(x - 0.03, 0.325, x - 0.05, 0.325, 2.0)
				_ln(x, 0.35, x - 0.03, 0.45)
				_ln(x, 0.35, x + 0.03, 0.45)
				_ln(x, 0.35, x, 0.45)
			"skull":
				_circle(x, 0.26, 0.12)
				for i in 4:
					var a := -2.4 + i * 0.5
					_ln(x + cos(a) * 0.06, 0.26 + sin(a) * 0.12, x + cos(a) * 0.1, 0.26 + sin(a) * 0.18, 0.8)
				_ln(x - 0.08, 0.2, x + 0.08, 0.2, 0.8)
				_ln(x, 0.08, x, 0.2, 0.8)
				_ln(x - 0.08, 0.3, x + 0.08, 0.3, 0.8)
				_ln(x - 0.06, 0.48, x + 0.06, 0.48, 1.4)
			"comet":
				_circle(0.72, 0.1, 0.012)
				for i in 6:
					_ln(0.72, 0.1, 0.35 + i * 0.02, 0.02 + i * 0.03, 0.8)
			"newspaper":
				_poly([[0.22, 0.04], [0.78, 0.04], [0.78, 0.56], [0.22, 0.56]])
				_ln(0.28, 0.1, 0.72, 0.1, 3.4)
				_ln(0.25, 0.15, 0.75, 0.15, 0.8)
				for c in 3:
					for i in 9:
						var lx := 0.26 + c * 0.17
						_ln(lx, 0.2 + i * 0.038, lx + 0.14, 0.2 + i * 0.038, 0.8)
				_poly([[0.43, 0.2], [0.57, 0.2], [0.57, 0.33], [0.43, 0.33]], true, 1.0)
			"barrel":
				_poly([[x - 0.04, 0.45], [x - 0.05, 0.38], [x - 0.04, 0.31], [x + 0.04, 0.31], [x + 0.05, 0.38], [x + 0.04, 0.45]])
				_ln(x - 0.048, 0.35, x + 0.048, 0.35, 1.0)
				_ln(x - 0.048, 0.41, x + 0.048, 0.41, 1.0)
			"canyon":
				_poly([[0.0, 0.05], [0.12, 0.2], [0.2, 0.45], [0.24, 0.58]], false)
				_poly([[1.0, 0.08], [0.85, 0.22], [0.78, 0.45], [0.74, 0.58]], false)
				_hatch(0.0, 0.2, 0.15, 0.56)
				_hatch(0.85, 0.24, 1.0, 0.56)
				_ln(0.2, 0.47, 0.78, 0.47, 1.0)
			"tripod":
				_ln(x, 0.32, x - 0.03, 0.47)
				_ln(x, 0.32, x + 0.03, 0.47)
				_ln(x, 0.32, x + 0.005, 0.47)
				_poly([[x - 0.025, 0.3], [x + 0.03, 0.3], [x + 0.03, 0.32], [x - 0.025, 0.32]])
			"medwagon":
				_poly([[x - 0.15, 0.4], [x - 0.15, 0.24], [x + 0.12, 0.24], [x + 0.12, 0.4]])
				_ln(x - 0.17, 0.24, x - 0.015, 0.19)
				_ln(x - 0.015, 0.19, x + 0.14, 0.24)
				_ln(x - 0.11, 0.3, x + 0.08, 0.3, 2.4)
				_circle(x - 0.1, 0.42, 0.03)
				_circle(x + 0.08, 0.42, 0.03)
			"glass":
				for i in 5:
					_circle(0.55 + i * 0.07, 0.08 + 0.05 * sin(i * 1.3), 0.008, 1.0)
			"bottle":
				_poly([[x - 0.02, 0.45], [x - 0.02, 0.36], [x - 0.008, 0.33], [x - 0.008, 0.29], [x + 0.008, 0.29], [x + 0.008, 0.33], [x + 0.02, 0.36], [x + 0.02, 0.45]])

	func _horse(x: float, gy: float) -> void:
		_poly([[x - 0.05, gy - 0.1], [x + 0.04, gy - 0.1], [x + 0.045, gy - 0.07], [x - 0.05, gy - 0.07]])
		_ln(x + 0.04, gy - 0.1, x + 0.065, gy - 0.15, 1.4)
		_ln(x + 0.065, gy - 0.15, x + 0.085, gy - 0.135, 1.4)
		_ln(x + 0.085, gy - 0.135, x + 0.055, gy - 0.1, 1.2)
		_ln(x - 0.05, gy - 0.095, x - 0.07, gy - 0.06, 1.2)
		for lx in [-0.042, -0.03, 0.028, 0.04]:
			_ln(x + lx, gy - 0.07, x + lx + _rng.randf_range(-0.006, 0.006), gy, 1.2)
