extends "res://coop/original_game_state.gd"

func reset_all():
	super.reset_all()
	set_meta("coop_panel_racks", {})
