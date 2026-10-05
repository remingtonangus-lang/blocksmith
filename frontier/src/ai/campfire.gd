extends Node3D
## The camp's campfire as an interactable: cook meat if you carry any, sleep at night, otherwise put money in the
## camp ledger.
var camp: Node

func interact_prompt() -> String:
	if camp == null:
		return ""
	var has_meat := false
	if Game.state:
		for k in Game.state.inventory.keys():
			if str(k).begins_with("meat_") and int(Game.state.inventory[k]) > 0:
				has_meat = true
	var h: float = Game.sky.hours if Game.sky else 12.0
	if has_meat:
		return "Cook meat at the fire"
	if h > 19.0 or h < 5.0:
		return "Sleep until morning"
	return "Put $5 in the camp ledger"

func interact(_who: Node) -> void:
	var p := interact_prompt()
	if p.begins_with("Cook"):
		camp.cook()
	elif p.begins_with("Sleep"):
		camp.sleep()
	else:
		if not camp.contribute(5.0):
			Game.say("You haven't got five dollars to spare.", 3.0)
