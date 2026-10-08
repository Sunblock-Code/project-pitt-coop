extends Node
var session: Node
func run_host():
	await get_tree().create_timer(28.0).timeout
	var magnet = load("res://scenes/magnet.tscn").instantiate()
	get_tree().current_scene.add_child(magnet)
	magnet.global_position = Vector3(24, 7, 10)
	magnet.freeze = true
	magnet.set_physics_process(false)
	var aim = magnet.global_position + Vector3(0, 0.3, 0)
	var eye = aim + Vector3(0, 0, 2.2)
	await get_tree().create_timer(0.3).timeout
	print("[DUCK QA] collision layer=", magnet.collision_layer, " mask=", magnet.collision_mask)
	for part in magnet.get_children():
		if part is CollisionShape3D and part.shape and not part.disabled:
			var bounds = part.shape.get_debug_mesh().get_aabb()
			aim = part.global_transform * bounds.get_center()
			eye = aim + Vector3(0, 0, 2.2)
			print("[DUCK QA] aim=", aim, " bounds=", bounds)
			break
	var light = OmniLight3D.new()
	get_tree().current_scene.add_child(light)
	light.global_position = eye + Vector3.UP
	light.light_energy = 4.0
	light.omni_range = 10.0
	var duck = load("res://scenes/duck.tscn").instantiate()
	get_tree().current_scene.add_child(duck)
	duck.global_position = eye.lerp(aim, 0.5) + Vector3(0, -0.1, 0)
	duck.freeze = true
	session._scan_bodies()
	var camera = session.host_player.get_node("CameraPivot/MainCamera")
	session.host_player.set_physics_process(false)
	camera.global_position = eye
	camera.look_at(aim)
	await get_tree().create_timer(0.4).timeout
	var ray = camera.interact_ray
	ray.force_raycast_update()
	var report = {"host_blocked_before": ray.get_collider() == duck}
	await toggle()
	ray.force_raycast_update()
	report.host_enabled = session.duck_pass.enabled
	report.host_reaches_magnet = ray.get_collider() == magnet
	await toggle()
	ray.force_raycast_update()
	report.host_restored = ray.get_collider() == duck
	var peer = session.peers.keys()[0]
	session._send(peer, ["duck_pass_qa", eye - Vector3.UP * 1.65, aim, duck.get_instance_id(), magnet.get_instance_id()])
	await get_tree().create_timer(2.5).timeout
	report.guest_toggled_on = magnet.is_active
	report.host_stays_off = not session.duck_pass.enabled and session.duck_pass.rids(1).is_empty()
	report.guest_filter_on = not session.duck_pass.rids(peer).is_empty()
	await get_tree().create_timer(1.2).timeout
	report.guest_grabbed = session.held.has(peer) and session.held[peer].id == magnet.get_instance_id()
	await get_tree().create_timer(1.5).timeout
	report.guest_toggled_off = not magnet.is_active
	report.guest_filter_restored = session.duck_pass.rids(peer).is_empty()
	report.physics_unchanged = duck.collision_layer != 0
	report.passed = not report.values().has(false)
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/duck-pass-host.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))

func toggle():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var event = InputEventKey.new()
	event.physical_keycode = KEY_M
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = InputEventKey.new()
	event.physical_keycode = KEY_M
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame

func run_guest(msg):
	session.guest.set_physics_process(false)
	session.guest.global_position = msg[1]
	session.guest.camera.look_at(msg[2])
	await get_tree().create_timer(1.0).timeout
	var duck = session.replicas[msg[3]]
	var report = {"off_initially": not session.duck_pass.enabled}
	await toggle()
	await get_tree().create_timer(0.3).timeout
	report.enabled = session.duck_pass.enabled
	report.hidden = true
	for mesh in duck.find_children("*", "GeometryInstance3D", true, false): report.hidden = report.hidden and mesh.layers == 0
	report.target = session.interaction_hud.target == session.replicas[msg[4]]
	session.guest_action("interact")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/duck-pass.png"))
	await get_tree().create_timer(1.3).timeout
	session.guest_action("grab")
	await get_tree().create_timer(1.0).timeout
	session.guest_action("interact")
	await get_tree().create_timer(0.3).timeout
	session._send(1, ["grab_release"])
	await toggle()
	await get_tree().create_timer(0.2).timeout
	report.restored = not session.duck_pass.enabled
	for mesh in duck.find_children("*", "GeometryInstance3D", true, false): report.restored = report.restored and mesh.layers != 0
	report.log_button = false
	for button in session.panel.find_children("*", "Button", true, false):
		if button.text == "Open session log": report.log_button = true
	report.log_path = session._session_log_path()
	report.log_exists = FileAccess.file_exists(report.log_path)
	report.passed = not report.values().has(false)
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/duck-pass-guest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
