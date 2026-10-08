extends Node
var session: Node
var guest_report = {}
func run_host():
	await get_tree().create_timer(28.0).timeout
	var peer = session.peers.keys()[0]
	get_node("/root/GameState").upgrades.equip.level = 1
	var broom_scene = "res://scenes/broom2.tscn" if "--big-broom-test" in OS.get_cmdline_user_args() else "res://scenes/broom.tscn"
	var broom = load(broom_scene).instantiate()
	var authored_strength = broom.sweep_strength
	var authored_multiplier = broom.sweep_impulse_multiplier
	get_tree().current_scene.add_child(broom)
	broom.global_position = Vector3(24, 7, 10)
	broom.freeze = true
	var origin = broom.global_position + Vector3(0, -0.5, 2)
	session.peers[peer].pose.origin = origin
	session._scan_bodies()
	await get_tree().create_timer(1.0).timeout
	session._send(peer, ["broom_guest_qa", "equip", origin, broom.global_position])
	await get_tree().create_timer(2.2).timeout
	var report = {"equipped": session.broom_players.equipped(peer)}
	if not report.equipped:
		print("[BROOM QA] EQUIP FAILED")
		return
	var area = broom.get_node("SweepArea")
	var shape = area.get_child(0)
	print("[BROOM QA] sweep shape=", shape.shape, " pos=", shape.global_position, " broom=", broom.global_transform)
	var duck = load("res://scenes/duck.tscn").instantiate()
	get_tree().current_scene.add_child(duck)
	duck.global_position = shape.global_position
	duck.gravity_scale = 0
	duck.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	duck.linear_damp = 0
	var outside = load("res://scenes/duck.tscn").instantiate()
	get_tree().current_scene.add_child(outside)
	outside.global_position = duck.global_position + Vector3(20, 0, 0)
	outside.gravity_scale = 0
	session._scan_bodies()
	await get_tree().create_timer(1.0).timeout
	report.native_area_detects_duck = area.get_overlapping_bodies().has(duck)
	report.forward = broom.global_basis.z.normalized().dot(-session.peers[peer].camera.basis.z.normalized()) > 0.99
	report.host_preview_disabled = not broom.preview_enabled
	session._send(peer, ["broom_guest_qa", "sweep", duck.get_instance_id(), outside.get_instance_id()])
	await get_tree().create_timer(1.8).timeout
	report.duck_moves_forward = duck.linear_velocity.dot(-session.peers[peer].camera.basis.z) > 0.5
	report.outside_unchanged = outside.linear_velocity.length() < 0.05
	report.used = session.broom_players.cooldowns.has(peer)
	report.native_strength_preserved = broom.sweep_strength == authored_strength and broom.sweep_impulse_multiplier == authored_multiplier
	report.original_scene_preserved = broom.scene_file_path == broom_scene
	report.passed = not report.values().has(false)
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/broom-guest-host.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	var stress = load("res://coop/broom_stress.gd").new()
	stress.session = session
	add_child(stress)
	await stress.run(broom, peer)
	session._send(peer, ["broom_guest_qa", "unequip"])

func run_guest(msg):
	if msg[1] == "equip":
		session.guest.set_physics_process(false)
		session.guest.global_position = msg[2]
		session.guest.camera.look_at(msg[3])
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		await get_tree().create_timer(1.0).timeout
		session.broom_players.equip_key()
	elif msg[1] == "sweep":
		await get_tree().create_timer(0.7).timeout
		var helper = session.broom_players
		guest_report.preview = helper.preview_bodies.has(session.replicas.get(msg[2]))
		guest_report.outside_not_highlighted = not helper.preview_bodies.has(session.replicas.get(msg[3]))
		guest_report.forward = (session.guest.camera.global_basis * helper.local_equipped_pose().basis).z.dot(-session.guest.camera.global_basis.z) > 0.99
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/broom-preview.png"))
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = true
		session.guest.equip_qa_input = true
		session.guest._unhandled_input(event)
		session.guest.equip_qa_input = false
		await get_tree().create_timer(0.2).timeout
		guest_report.sweep_received = helper.sweep_fx_count > 0
	elif msg[1] == "unequip":
		session.broom_players.equip_key()
		await get_tree().create_timer(0.5).timeout
		guest_report.preview_cleared = session.broom_players.preview_bodies.is_empty()
		guest_report.passed = not guest_report.values().has(false)
		var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/broom-guest-client.json"), FileAccess.WRITE)
		file.store_string(JSON.stringify(guest_report, "  "))
