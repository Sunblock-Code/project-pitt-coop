extends "res://coop/original_input.gd"

func _ready():
	default_bindings["quick_save"] = KEY_F6
	super._ready()

func apply_bindings():
	# Migrate the base game's F5 quick-save binding; F5 now belongs to the view toggle.
	for action in current_bindings:
		if current_bindings[action] == KEY_F5:
			current_bindings[action] = KEY_F6 if action == "quick_save" else default_bindings.get(action, KEY_NONE)
	super.apply_bindings()
	if not InputMap.has_action("remote_toggle_all"): InputMap.add_action("remote_toggle_all")
	InputMap.action_erase_events("remote_toggle_all")
	for event in InputMap.action_get_events("sprint"):
		InputMap.action_add_event("remote_toggle_all", event.duplicate())

func can_bind(action: String, code: int) -> bool:
	if code == KEY_F5:
		return false
	return super.can_bind(action, code)
