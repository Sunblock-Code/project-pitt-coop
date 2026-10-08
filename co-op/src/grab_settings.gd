extends Node
var hold_to_grab = true

func _ready():
	var cfg = ConfigFile.new()
	if cfg.load("user://pitt_controls.cfg") == OK:
		hold_to_grab = bool(cfg.get_value("controls", "hold_to_grab", true))

func set_hold(value: bool):
	if hold_to_grab == value: return
	hold_to_grab = value
	var cfg = ConfigFile.new()
	cfg.set_value("controls", "hold_to_grab", value)
	cfg.save("user://pitt_controls.cfg")
	var session = get_parent()
	if session.role == "guest" and is_instance_valid(session.guest):
		session.guest.craft_pressed = false
		session._send(1, ["craft_stop"])
		session._send(1, ["grab_release"])
	elif session.role == "host" and is_instance_valid(session.host_player):
		var camera = session.host_player.get_node("CameraPivot/MainCamera")
		if camera.picked_object != null: camera.drop_object(true)
