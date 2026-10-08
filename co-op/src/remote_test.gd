extends Node
var session: Node
func aim_point(body):
	for shape in body.get_children():
		if shape is CollisionShape3D and shape.shape and not shape.disabled: return shape.global_transform * shape.shape.get_debug_mesh().get_aabb().get_center()
	return body.global_position

func run_host():
	await get_tree().create_timer(28.0).timeout
	var state = get_node("/root/GameState")
	state.upgrades.equip.level = 1
	state.remote_max_channels = 2
	state.init_remote_channels()
	var magnet = load("res://scenes/magnet.tscn").instantiate()
	get_tree().current_scene.add_child(magnet)
	magnet.global_position = Vector3(24, 7, 10)
	magnet.freeze = true
	magnet.set_physics_process(false)
	var remote = load("res://scenes/remote.tscn").instantiate()
	get_tree().current_scene.add_child(remote)
	remote.global_position = Vector3(24, 7, 12)
	remote.freeze = true
	await get_tree().create_timer(0.3).timeout
	var aim = aim_point(magnet)
	var camera = session.host_player.get_node("CameraPivot/MainCamera")
	session.host_player.set_physics_process(false)
	camera.global_position = aim + Vector3(0, 0, 2)
	camera.look_at(aim)
	remote.equip(camera)
	camera.equipped_item = remote
	camera.update_equipped_item_properties()
	await get_tree().create_timer(0.2).timeout
	camera._do_interact()
	var report = {"host_link": remote.is_tool_linked(magnet)}
	remote.remote_lmb_pressed()
	report.host_off = not magnet.is_active
	remote.remote_lmb_pressed()
	report.host_on = magnet.is_active
	remote.try_link_tool(magnet)
	camera.equipped_item = null
	remote.unequip(get_tree().current_scene, Vector3(24, 7, 12))
	remote.freeze = true
	await get_tree().create_timer(0.2).timeout
	var remote_aim = aim_point(remote)
	session._scan_bodies()
	await get_tree().create_timer(0.5).timeout
	var peer = session.peers.keys()[0]
	session._send(peer, ["remote_qa", "equip", remote_aim + Vector3(0, -1.65, 1.5), remote_aim])
	await get_tree().create_timer(2.5).timeout
	report.guest_equipped = session.broom_players.equipped(peer)
	session._send(peer, ["remote_qa", "use", aim + Vector3(0, -1.65, 2), aim, remote.get_instance_id()])
	await get_tree().create_timer(1.0).timeout
	report.guest_link = remote.is_tool_linked(magnet)
	await get_tree().create_timer(0.8).timeout
	report.guest_off = not magnet.is_active
	await get_tree().create_timer(0.8).timeout
	report.guest_on = magnet.is_active
	report.all_channels_off_seen = false
	for sample in range(30):
		await get_tree().create_timer(0.1).timeout
		if not state.remote_channel_states[0] and not state.remote_channel_states[1]: report.all_channels_off_seen = true
	report.all_channels_on = state.remote_channel_states[0] and state.remote_channel_states[1]
	report.guest_unlinked = not remote.is_tool_linked(magnet)
	report.passed = not report.values().has(false)
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/remote-host.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))

func mouse(button):
	var event = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	session.guest._unhandled_input(event)

func run_guest(msg):
	if msg[1] == "equip":
		session.guest.set_physics_process(false)
		session.guest.global_position = msg[2]
		session.guest.camera.look_at(msg[3])
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		await get_tree().create_timer(1.0).timeout
		session.broom_players.equip_key()
	elif msg[1] == "use":
		session.guest.global_position = msg[2]
		session.guest.camera.look_at(msg[3])
		await get_tree().create_timer(0.4).timeout
		session.broom_players.toggle_key()
		await get_tree().create_timer(0.8).timeout
		mouse(MOUSE_BUTTON_LEFT)
		await get_tree().create_timer(0.8).timeout
		mouse(MOUSE_BUTTON_LEFT)
		await get_tree().create_timer(0.6).timeout
		var report = {"state": session.remote_tools.guest_states.get(msg[4])}
		var remote = session.replicas[msg[4]]
		var label = remote.get_node_or_null("ScreenViewport/ScreenUI/VBoxContainer/CountLabel")
		report.screen = label is Label and label.text.begins_with("LNK 1/")
		report.hint = session.interaction_hud.controls.text.contains("1 linked")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/remote-guest.png"))
		mouse(MOUSE_BUTTON_WHEEL_UP)
		await get_tree().create_timer(0.4).timeout
		report.channel_next = session.remote_tools.guest_states[msg[4]][1] == 1
		mouse(MOUSE_BUTTON_WHEEL_DOWN)
		await get_tree().create_timer(0.4).timeout
		report.channel_previous = session.remote_tools.guest_states[msg[4]][1] == 0
		Input.action_press("remote_toggle_all")
		mouse(MOUSE_BUTTON_LEFT)
		Input.action_release("remote_toggle_all")
		await get_tree().create_timer(0.4).timeout
		report.all_off = not session.remote_tools.guest_states[msg[4]][2]
		Input.action_press("remote_toggle_all")
		mouse(MOUSE_BUTTON_LEFT)
		Input.action_release("remote_toggle_all")
		await get_tree().create_timer(0.4).timeout
		report.all_on = session.remote_tools.guest_states[msg[4]][2]
		session.broom_players.toggle_key()
		report.passed = report.screen and report.hint and report.channel_next and report.channel_previous and report.all_off and report.all_on
		var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/remote-guest.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(report, "  "))
