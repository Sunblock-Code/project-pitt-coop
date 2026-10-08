extends Node
var session: Node
var report = {}

func _ready(): run.call_deferred()

func save_report():
	report.passed = not report.values().has(false)
	FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/fuse-" + session.role + ".json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("[FUSE QA] ", report)

func run():
	await get_tree().create_timer(10).timeout
	if session.role != "host": return
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_size(Vector2i(1920, 1080))
		await get_tree().process_frame
		await get_tree().process_frame
		get_node("/root/PostProcessManager").apply_render_scale()
		get_node("/root/PostProcessManager").set_dither_intensity(0.6)
	var logic = get_tree().get_first_node_in_group("gate_shutters")
	var fuses = get_tree().get_nodes_in_group("fuse")
	var peer = session.peers.keys()[0]
	report.three_fuses_available = fuses.size() >= 3
	if fuses.size() < 3:
		save_report()
		return
	var slots = []
	for slot in logic.fuse_slots:
		print("[FUSE SLOT] ",slot.global_transform," mask=",slot.collision_mask)
		for shape in slot.get_children():
			if shape is CollisionShape3D: print("[FUSE SHAPE] ",shape.global_transform," ",shape.shape," size=",shape.shape.size)
	for i in range(3):
		var body = fuses[i]
		var destination = logic.fuse_slots[i].global_position
		body.freeze = true
		body.global_position = destination - Vector3(0.8,0,0)
		session.peers[peer].pose_time = 0
		session._send(peer, ["fuse_qa", "place", body.global_position])
		await get_tree().create_timer(1.0).timeout
		print("[FUSE PICKUP] groups=", body.get_groups(), " body=", body.global_position, " camera=", session.peers[peer].camera.origin)
		session._scan_bodies()
		session._action(peer, "grab", body.get_instance_id())
		report["can_grab_%d" % i] = session.held.has(peer)
		if i == 0:
			session._release(peer,false)
			var eye = session.host_player.get_node("CameraPivot/MainCamera")
			session.host_player.set_physics_process(false)
			eye.set_process(false)
			eye.set_physics_process(false)
			eye.global_position = destination-Vector3(3.3,0,0)
			eye.look_at(destination)
			Input.action_press("lMouse")
			eye._begin_carry(body)
			var facing = eye.global_transform
			eye.rotate_y(PI)
			report.wrong_aim_rejected = not session.fuse_sync.try_insert(1)
			eye.global_transform = facing
			var input = InputEventAction.new()
			input.action = "interact"
			input.pressed = true
			eye._input(input)
			Input.action_release("lMouse")
			report.host_insert_key = body.get_meta("slotted",false) and eye.picked_object == null
		elif i == 1:
			session._send(peer,["fuse_qa","insert"])
			await get_tree().create_timer(1.0).timeout
			report.guest_insert_key = body.get_meta("slotted",false)
		else:
			session.peers[peer].pose_time = 0
			session._send(peer, ["fuse_qa", "place", destination])
		await get_tree().create_timer(1.0).timeout
		print("[FUSE APPROACH] ",body.global_position," target=",destination," id=",body.fuse_id," held=",session.held.has(peer))
		await get_tree().create_timer(1.0).timeout
		report["slot_%d" % i] = logic.is_slot_filled(i) and body.freeze and body.get_meta("slotted", false)
		report["released_%d" % i] = not session.held.has(peer)
		slots.append(body.get_instance_id())
	await get_tree().create_timer(logic.gate.retract_distance / logic.gate.retract_speed + 1.5).timeout
	report.gate_open = logic.gate.is_solved and logic.gate.barrier.collision_layer == 0
	session.fuse_sync.sync_host()
	var world = get_tree().current_scene
	var panels = logic.gate.barrier_panels.map(func(node): return [str(world.get_path_to(node)), node.transform])
	session._send(peer, ["fuse_qa", "check", slots, panels, str(world.get_path_to(logic.gate.barrier)), logic.indicator_lights.map(func(node): return str(world.get_path_to(node)))])
	save_report()

func guest_check(msg):
	if msg[1] == "place":
		session.guest.set_physics_process(false)
		session.guest.global_position = msg[2] + Vector3(-2.5, -1.65, 0)
		session.guest.rotation = Vector3.ZERO
		session.guest.camera.look_at(msg[2])
	elif msg[1] == "insert":
		await get_tree().create_timer(0.25).timeout
		report.insert_hint = session.interaction_hud.controls.text.contains("Insert fuse into socket")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/fuse-insert-hint.png"))
		session.guest_action("interact")
	elif msg[1] == "check":
		await get_tree().create_timer(0.5).timeout
		var world = get_tree().current_scene
		report.fuses_ungrabbable = msg[2].all(func(id): return session.replicas.has(id) and session.replicas[id].collision_layer == 0 and not session.replicas[id].get_meta("coop_grabbable", true))
		report.no_stuck_grip = session.guest_held_id == 0
		report.gate_panels_match = msg[3].all(func(row): return world.get_node(row[0]).transform.is_equal_approx(row[1]))
		report.gate_passable = world.get_node(msg[4]).collision_layer == 0
		report.green_indicators = msg[5].all(func(path): return world.get_node(path).get_active_material(0).emission == Color.GREEN)
		var id = msg[2][0]
		var old = session.replicas[id]
		var scene = old.scene_file_path
		var pose = old.global_transform
		session.replicas.erase(id)
		old.queue_free()
		session._spawn_replica(id, scene, pose, 2)
		report.slotted_replica_late_spawn = session.replicas[id].collision_layer == 0
		save_report()
