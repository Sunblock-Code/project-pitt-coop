extends "res://coop/original_save_manager.gd"

func _save_game_state() -> Dictionary:
	var state = super._save_game_state()
	state["coop_panel_racks"] = get_node("/root/GameState").get_meta("coop_panel_racks", {}).duplicate(true)
	return state

func _load_game_state(state: Dictionary):
	super._load_game_state(state)
	var inventories: Dictionary = {}
	var saved = state.get("coop_panel_racks", {})
	if saved is Dictionary:
		for key in saved:
			if not key is String or not saved[key] is Array: continue
			var entries: Array = []
			for entry in saved[key]:
				if entry is String and entry.begins_with("tool_panel"): entries.append(entry)
			inventories[key] = entries
	get_node("/root/GameState").set_meta("coop_panel_racks", inventories)
