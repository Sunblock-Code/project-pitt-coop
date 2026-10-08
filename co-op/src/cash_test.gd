extends Node
var session: Node
var holding = false

func _process(_delta):
	if holding and session.role == "guest":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		session.guest.craft_pressed = true

func run_host():
	await get_tree().create_timer(28.0).timeout
	var pool = get_node("/root/ObjectPoolManager")
	pool._create_pool("cash_register", {"scene": load("res://scenes/cash_register.tscn"), "initial": 0, "max": 12})
	var machine = load("res://scenes/manual_cash_workbench.tscn").instantiate()
	get_tree().current_scene.add_child(machine)
	machine.global_position = Vector3(24, 0, 10)
	var aim = machine.global_position + Vector3.UP
	for shape in machine.find_children("*", "CollisionShape3D", true, false):
		if not shape.disabled and shape.get_parent() == machine:
			aim = shape.global_position
			break
	var origin = aim + Vector3(0, -1.65, 3)
	await get_tree().physics_frame
	# Stand by the outer edge: surface is in reach, distant model origin is not.
	for direction in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		var eye = aim + direction * 6.0
		var hit = machine.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye, eye - direction * 5.0, 0xFFFFFFFF))
		if hit and (hit.collider == machine or machine.is_ancestor_of(hit.collider)) and eye.distance_to(machine.global_position) > 5.0:
			origin = eye - Vector3.UP * 1.65
			break
	print("[CASH QA] origin distance=", (origin + Vector3.UP * 1.65).distance_to(machine.global_position), " aim=", aim)
	for peer in session.peers: session.peers[peer].pose.origin = origin
	await get_tree().create_timer(1.0).timeout
	session._broadcast(["cash_qa", str(machine.name), origin, aim])
	await get_tree().create_timer(8.0).timeout
	var produced = 0
	for body in session.indexed_bodies.values():
		if is_instance_valid(body) and body.is_visible_in_tree() and "pool_id" in body and str(body.pool_id).begins_with("cash_register"): produced += 1
	var active = not session.craft_holds.is_empty()
	session._broadcast(["cash_qa_stop"])
	await get_tree().create_timer(1.0).timeout
	var report = {"produced": produced, "held": active, "released": session.craft_holds.is_empty() and not machine.is_crafting}
	report.distant_origin_case = (origin + Vector3.UP * 1.65).distance_to(machine.global_position) > 5.0
	report.range_enforced = true
	for peer in session.peers:
		var saved: Transform3D = session.peers[peer].camera
		var distant = saved
		distant.origin += distant.basis.z * 20.0
		session.peers[peer].camera = distant
		report.range_enforced = report.range_enforced and not session._aims_at_control(peer, machine)
		session.peers[peer].camera = saved
	report.passed = produced >= 1 and active and report.released and report.distant_origin_case and report.range_enforced
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/cash-test.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))

func run_guest(msg: Array):
	session.guest.set_physics_process(false)
	session.guest.global_position = msg[2]
	session.guest.camera.look_at(msg[3])
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().create_timer(0.3).timeout
	var camera = session.guest.camera
	var hit = session.guest.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 8.0, 0xFFFFFFFF))
	print("[CASH QA] aim hit=", str(hit.collider.get_path()) if hit else "none", " expected=", msg[1])
	holding = true
	session._test_grab_button(true)
	await get_tree().create_timer(2.0).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/cash-crafting.png"))

func stop():
	holding = false
	session._test_grab_button(false)
