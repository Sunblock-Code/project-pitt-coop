extends "res://coop/original_press.gd"
var coop_crushed = false

func start_pressing():
	if not is_pressing: coop_crushed = false
	super.start_pressing()

func process_crushed_items():
	if coop_crushed: return
	coop_crushed = true
	var coop = get_node_or_null("/root/PittCoop")
	if coop and coop.role == "host":
		coop.press_corpses.crush(self)
		# Multiplayer respawns both local and remote victims above.
		is_player_in = false
	super.process_crushed_items()
