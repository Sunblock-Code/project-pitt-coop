extends Node
var session: Node
var report: Dictionary = {}

func run_host():
	await get_tree().create_timer(28.0).timeout
	var container = Node3D.new()
	container.name = "PoolStatusQA"
	get_tree().root.add_child(container)
	var fan = load("res://scenes/fan.tscn").instantiate()
	var machine = load("res://scenes/automatic_duck_workbench.tscn").instantiate()
	container.add_child(fan)
	get_tree().current_scene.add_child(machine)
	fan.global_position = Vector3(1002, 50, 1000)
	machine.global_position = Vector3(1000, 50, 1000)
	fan.freeze = true
	machine.set_process(false)
	machine.set_physics_process(false)
	get_node("/root/GameState").products.duck.auto_machine.level = 1
	session._scan_bodies()
	var original_peers = session.peers.keys()
	for stage in range(7):
		var on = stage % 2 == 1
		fan.is_active = on
		fan.update_fan_state()
		if on: machine.turn_on()
		else:
			machine.is_automated = true
			machine.turn_off()
		await get_tree().create_timer(0.8).timeout
		session._broadcast(["status_check", stage, fan.get_instance_id(), str(get_tree().current_scene.get_path_to(machine)), on, machine.object_name()])
		await get_tree().create_timer(0.5).timeout

	var ready = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/late-join-ready.txt"), FileAccess.WRITE)
	if ready:
		ready.store_string("off")
		ready.close()
	var deadline = Time.get_ticks_msec() + 45000
	while Time.get_ticks_msec() < deadline:
		for peer in session.peers:
			if peer not in original_peers and session.peers[peer].ready:
				await get_tree().create_timer(1.0).timeout
				session._send(peer, ["status_check", 100, fan.get_instance_id(), str(get_tree().current_scene.get_path_to(machine)), false, machine.object_name()])
				return
		await get_tree().create_timer(0.1).timeout

func check_guest(msg: Array):
	var stage: int = msg[1]
	var fan = session.replicas.get(msg[2])
	var machine = get_tree().current_scene.get_node_or_null(NodePath(msg[3]))
	var checks = {"spawned": is_instance_valid(fan) and is_instance_valid(machine)}
	if checks.spawned:
		checks.title_synced = machine.get_meta("coop_title", "") == msg[5]
		checks.effect_synced = fan.get_node("WindEffectMesh").visible == msg[4]
		if not msg[4]:
			var effect = fan.get_node("WindEffectMesh")
			# Reproduce a late ON animation packet after the reliable OFF update.
			session._apply_presentation([["@" + str(msg[2]) + "/WindEffectMesh", "part", [true, effect.transform, false, effect.rotation, 0.0]]])
			checks.stale_on_ignored = not effect.visible
		var audio = fan.get_node_or_null("FanBlowAudio3D")
		checks.audio_synced = audio != null and audio.playing == msg[4]
		session.guest.set_physics_process(false)
		session.guest.global_position = machine.global_position + Vector3(0, 0, 3)
		var aim = machine.global_position + Vector3.UP
		for shape in machine.find_children("*", "CollisionShape3D", true, false):
			if not shape.disabled and shape.get_parent() is StaticBody3D:
				aim = shape.global_position
				break
		session.guest.global_position = aim + Vector3(0, -1.65, 4.5)
		session.guest.camera.look_at(aim)
		await get_tree().create_timer(0.15).timeout
		checks.hud_title = session.interaction_hud.title.text == msg[5]
		if not checks.hud_title:
			var eye = session.guest.camera
			var hit = machine.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye.global_position, eye.global_position - eye.global_basis.z * 5.0, 0xFFFFFFFF))
			print("[STATUS QA] collider=", str(hit.collider.get_path()) if hit else "none", " layer=", machine.collision_layer, " aim=", aim, " camera=", eye.global_position, " intro=", session.pending_intro, " lobby=", session.lobby.visible)
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/status-" + str(stage) + ".png"))
	checks.passed = not checks.values().has(false)
	if stage == 100:
		var late_file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/late-join-test.json"), FileAccess.WRITE)
		if late_file: late_file.store_string(JSON.stringify(checks, "  "))
		return
	report[str(stage)] = checks
	if stage == 6:
		var all_passed = report.size() == 7
		for result in report.values(): all_passed = all_passed and result.passed
		report.passed = all_passed
		var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/status-test.json"), FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(report, "  "))
