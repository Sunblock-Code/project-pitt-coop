extends "res://coop/original_bottom_maw.gd"

func _on_body_entered(body):
	if body.get_meta("coop_corpse", false):
		if body.get_meta("consumed", false): return
		body.set_meta("consumed", true)
		var coop = get_node_or_null("/root/PittCoop")
		if coop and coop.role == "host":
			coop.press_corpses.consume(body)
			maw_effect("player", body.global_position)
		return
	super._on_body_entered(body)
