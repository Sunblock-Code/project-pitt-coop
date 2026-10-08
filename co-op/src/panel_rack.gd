extends Node

var session: Node
var count = 0
var capacity = 0
var last_action: Dictionary = {}

func stack(peer: int) -> Array:
	var state = get_node("/root/GameState")
	if peer == 1: return state.panel_stack
	var inventories: Dictionary = state.get_meta("coop_panel_racks", {})
	var key: String = session.peers[peer].get("storage_id", str(peer))
	if not inventories.has(key): inventories[key] = []
	state.set_meta("coop_panel_racks", inventories)
	return inventories[key]

func sync_peer(peer: int):
	var state = get_node("/root/GameState")
	var value = [stack(peer).size(), state.panel_rack_capacity()]
	if session.peers[peer].get("rack_state", []) != value:
		session._send(peer, ["rack_state", value[0], value[1]])
		session.peers[peer].rack_state = value

func hint(target) -> String:
	if capacity <= 0 or session.tool_equipped: return ""
	var key = get_node("/root/InputManager").get_action_key_name("rack")
	var panel = is_instance_valid(target) and str(target.get_meta("coop_pool_id", "")).begins_with("tool_panel")
	if panel and count < capacity:
		return tr("CTRL_PANEL_COLLECT").replace("{key}", key) + " (%d/%d)" % [count, capacity]
	if session.guest_held_id == 0 and count > 0:
		return tr("CTRL_PANEL_WITHDRAW").replace("{key}", key) + " (%d/%d)" % [count, capacity]
	return "Rack %d/%d" % [count, capacity] if count > 0 else ""

func action(peer: int, id):
	var now = Time.get_ticks_msec()
	if now - last_action.get(peer, -1000) < 200: return
	last_action[peer] = now
	var state = get_node("/root/GameState")
	if state.panel_rack_capacity() <= 0 or session.broom_players.equipped(peer): return
	var personal = stack(peer)
	var camera = session.host_player.get_node("CameraPivot/MainCamera")
	var body = instance_from_id(id) if id is int and session.bodies.has(id) else null
	if not camera._is_rackable(body) and session.held.has(peer):
		body = instance_from_id(session.held[peer].id)
	if camera._is_rackable(body):
		if camera.picked_object == body or camera.equipped_item == body: return
		for owner in session.held:
			if owner != peer and session.held[owner].id == body.get_instance_id(): return
		var eye: Transform3D = session.peers[peer].camera
		if eye.origin.distance_to(body.global_position) > 5.0: return
		var query = PhysicsRayQueryParameters3D.create(eye.origin, body.global_position, 1)
		var hit = body.get_world_3d().direct_space_state.intersect_ray(query)
		if hit and hit.collider != body: return
		if personal.size() >= state.panel_rack_capacity():
			session._send(peer, ["notice", "Panel rack is full."])
			return
		var pool = get_node("/root/ObjectPoolManager")
		var pool_id: String = pool.get_active_pool_id(body)
		if pool_id.is_empty(): return
		# Restore the guest carry before recycling the panel.
		# Do not call drop/place: a deferred placement would mutate a pooled object.
		if session.held.has(peer) and session.held[peer].id == body.get_instance_id():
			var hold = session.held[peer]
			body.gravity_scale = hold.gravity
			body.lock_rotation = hold.lock
			body.contact_monitor = hold.monitor
			body.max_contacts_reported = hold.contacts
			session.held.erase(peer)
			session._send(peer, ["held_item", 0])
			session._send(peer, ["held_mode", false, 0, 2.5])
			session._send(peer, ["sticky_ready", false])
		personal.append(pool_id)
		camera._release_from_piston(body)
		if body.has_method("unplace"): body.unplace()
		pool.recycle(body)
		session._scan_bodies()
	else:
		withdraw(peer)
	for other in session.peers:
		if session.peers[other].ready: sync_peer(other)

func withdraw(peer: int):
	if session.held.has(peer): return
	var state = get_node("/root/GameState")
	var personal = stack(peer)
	if personal.is_empty(): return
	var pool_id: String = personal.pop_back()
	var eye: Transform3D = session.peers[peer].camera
	var body = get_node("/root/ObjectPoolManager").spawn(pool_id, eye.origin - eye.basis.z * 2.0)
	if not body is RigidBody3D:
		personal.append(pool_id)
		return
	# Publish the replica before transferring the carry; the host owns both.
	session._scan_bodies()
	session._begin_guest_carry(peer, body)

func press_rack():
	var event = InputEventKey.new()
	event.physical_keycode = KEY_V
	event.keycode = KEY_V
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)

func run_guest_checks():
	var report = {"initially_held": session.guest_held_id != 0}
	press_rack()
	await get_tree().create_timer(1.0).timeout
	report.stored = count == 1 and session.guest_held_id == 0
	report.withdraw_hint = hint(null).contains(get_node("/root/InputManager").get_action_key_name("rack"))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/rack-ui.png"))
	press_rack()
	await get_tree().create_timer(1.0).timeout
	report.withdrawn = count == 0 and session.guest_held_id != 0
	press_rack()
	await get_tree().create_timer(1.0).timeout
	report.stored_again = count == 1 and session.guest_held_id == 0
	report.passed = report.initially_held and report.stored and report.withdraw_hint and report.withdrawn and report.stored_again
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/rack-test.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))
	session._send(1, ["rack_checks"])

func run_host_checks(peer: int):
	var state = get_node("/root/GameState")
	var pool = get_node("/root/ObjectPoolManager")
	var camera = session.host_player.get_node("CameraPivot/MainCamera")
	var host_stack = state.panel_stack.duplicate()
	var personal = stack(peer)
	var saved_stack = personal.duplicate()
	var saved_level = state.upgrades.panel_rack.level
	var eye: Transform3D = session.peers[peer].camera
	var body = pool.spawn("tool_panel", eye.origin - eye.basis.z * 2.0)
	body.freeze = true
	session._scan_bodies()
	var id = body.get_instance_id()
	var report = {}
	var host_item = camera.picked_object
	camera.picked_object = body
	last_action.erase(peer)
	action(peer, id)
	report.host_held_protected = body.visible and personal == saved_stack
	camera.picked_object = host_item
	session.held[-30] = {"id": id}
	last_action.erase(peer)
	action(peer, id)
	report.other_guest_protected = body.visible and personal == saved_stack
	session.held.erase(-30)
	state.upgrades.panel_rack.level = 0
	last_action.erase(peer)
	action(peer, id)
	report.upgrade_required = body.visible and personal == saved_stack
	state.upgrades.panel_rack.level = saved_level
	while personal.size() < state.panel_rack_capacity(): personal.append("tool_panel")
	last_action.erase(peer)
	action(peer, id)
	report.capacity_enforced = body.visible and personal.size() == state.panel_rack_capacity()
	personal.assign(saved_stack)
	body.global_position += Vector3(100, 0, 0)
	last_action.erase(peer)
	action(peer, id)
	report.distance_enforced = body.visible and personal == saved_stack
	body.global_position = eye.origin - eye.basis.z * 2.0
	last_action.erase(peer)
	action(peer, id)
	report.loose_store = not body.visible and personal.size() == saved_stack.size() + 1
	report.host_unchanged = state.panel_stack == host_stack
	var identity: String = session.peers[peer].storage_id
	session.peers[-31] = {"storage_id": "test-other-player"}
	report.other_guest_empty = stack(-31).is_empty()
	stack(-31).append("tool_panel")
	report.other_guest_separate = personal.size() == saved_stack.size() + 1 and stack(-31).size() == 1
	session.peers[-32] = {"storage_id": identity}
	report.reconnect_retains = stack(-32) == personal
	var saves = get_node("/root/SaveManager")
	var snapshot: Dictionary = saves._save_game_state()
	var expected = personal.duplicate()
	personal.clear()
	saves._load_game_state(snapshot)
	report.save_restores = stack(peer) == expected and stack(-31).size() == 1 and state.panel_stack == host_stack
	snapshot.erase("coop_panel_racks")
	saves._load_game_state(snapshot)
	report.old_save_safe = stack(peer).is_empty() and state.panel_stack == host_stack
	stack(peer).append("tool_panel")
	state.reset_all()
	report.new_game_clears = state.get_meta("coop_panel_racks", {}).is_empty()
	session.peers.erase(-31)
	session.peers.erase(-32)
	report.passed = true
	for result in report.values():
		if result == false: report.passed = false
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/rack-host-test.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))
