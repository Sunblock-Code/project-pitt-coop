extends Node
var session: Node
var enabled = false
var m_down = false
var ducks: Dictionary = {}
var exclusions: Array[RID] = []
var ray: RayCast3D
var cleanup_tick = 0.0
var indicator: Label

func _input(event):
	if not event is InputEventKey or event.physical_keycode != KEY_M: return
	if not event.pressed:
		m_down = false
		return
	if event.echo or m_down: return
	m_down = true
	_press_m()

func _press_m():
	if session.role not in ["host", "guest"]: return
	if session.role == "host" and not session.world_ready: return
	if session.role == "guest" and (not is_instance_valid(session.guest) or session.pending_intro): return
	if session.panel.visible or session.lobby.visible or session.character_editor.visible or session.guest_settings.active() or session.guest_terminal.active(): return
	if get_node("/root/MenuManager").current_menu != null: return
	set_enabled(not enabled)
	get_viewport().set_input_as_handled()

func set_enabled(value: bool):
	enabled = value
	for entry in ducks.values(): _appearance(entry)
	if is_instance_valid(ray):
		for entry in ducks.values():
			if is_instance_valid(entry.body):
				if enabled: ray.add_exception(entry.body)
				else: ray.remove_exception(entry.body)
		ray.force_raycast_update()
	if session.role == "guest": session._send(1, ["duck_pass", enabled])
	if not is_instance_valid(indicator) and is_instance_valid(session.hud):
		indicator = Label.new()
		indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
		indicator.position = Vector2(16, 42)
		indicator.add_theme_font_size_override("font_size", 18)
		indicator.add_theme_color_override("font_shadow_color", Color.BLACK)
		indicator.add_theme_constant_override("shadow_offset_x", 2)
		indicator.add_theme_constant_override("shadow_offset_y", 2)
		session.hud.add_child(indicator)
	if is_instance_valid(indicator):
		indicator.text = "[M] Ducks hidden / clicks pass through"
		indicator.visible = enabled

func track(body):
	var kind = str(body.get("pool_id")) if body.get_script() else str(body.get_meta("coop_pool_id", ""))
	if not (kind.begins_with("duck") or kind.begins_with("flat_duck")): return
	var id = body.get_instance_id()
	if ducks.has(id): return
	var meshes = []
	for mesh in body.find_children("*", "GeometryInstance3D", true, false): meshes.append([mesh, mesh.layers])
	var entry = {"body": body, "meshes": meshes, "rid": body.get_rid()}
	ducks[id] = entry
	exclusions.append(entry.rid)
	_appearance(entry)
	if enabled and is_instance_valid(ray): ray.add_exception(body)

func _appearance(entry):
	for pair in entry.meshes:
		if is_instance_valid(pair[0]): pair[0].layers = 0 if enabled else pair[1]

func rids(peer: int = 0) -> Array[RID]:
	var active = enabled if peer == 0 or peer == 1 else bool(session.peers.get(peer, {}).get("duck_pass", false))
	var empty: Array[RID] = []
	return exclusions if active else empty

func _process(delta):
	var pressed = Input.is_physical_key_pressed(KEY_M)
	if pressed and not m_down:
		m_down = true
		_press_m()
	elif not pressed: m_down = false
	if session.role == "host" and is_instance_valid(session.host_player):
		var camera = session.host_player.get_node_or_null("CameraPivot/MainCamera")
		var next = camera.get("interact_ray") if camera else null
		if next != ray:
			ray = next
			if enabled: set_enabled(true)
	cleanup_tick += delta
	if cleanup_tick < 0.5: return
	cleanup_tick = 0.0
	for id in ducks.keys():
		if not is_instance_valid(ducks[id].body):
			exclusions.erase(ducks[id].rid)
			ducks.erase(id)
