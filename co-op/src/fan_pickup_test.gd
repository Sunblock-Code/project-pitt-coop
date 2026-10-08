extends Node

var session: Node

func run(peer: int):
	var reports = {}
	for kind in ["fan", "fan2", "fan_3"]:
		var body = load("res://scenes/" + kind + ".tscn").instantiate()
		get_tree().current_scene.add_child(body)
		body.global_position = Vector3(0, 150, 20)
		body.freeze = true
		await get_tree().physics_frame
		await get_tree().physics_frame
		session._scan_bodies()
		var center: Vector3 = body.global_position
		var direction = Vector3.FORWARD
		var space = body.get_world_3d().direct_space_state
		var hit = {}
		for shape in body.get_children():
			if not shape is CollisionShape3D or shape.disabled: continue
			center = shape.global_position
			for axis in [Vector3.BACK, Vector3.RIGHT, Vector3.UP]:
				var probe = PhysicsRayQueryParameters3D.create(center + axis * 12, center - axis * 2)
				hit = space.intersect_ray(probe)
				if not hit.is_empty() and hit.collider == body:
					direction = axis
					break
			if not hit.is_empty() and hit.collider == body: break
		var report = {"surface_found": not hit.is_empty() and hit.collider == body}
		if report.surface_found:
			var origin: Vector3 = hit.position + direction * 4.99
			var eye = Transform3D(Basis.looking_at(center - origin, Vector3.RIGHT if direction == Vector3.UP else Vector3.UP), origin)
			session.peers[peer].camera = eye
			session.peers[peer].action_time = Time.get_ticks_msec()
			report.old_center_check_rejected = origin.distance_to(body.global_position) > 5.0
			session._action(peer, "grab", body.get_instance_id())
			report.surface_pickup = session.held.has(peer)
			if session.held.has(peer): session._release(peer, false)
			await get_tree().process_frame
			body.global_position = Vector3(0, 150, 20)
			body.freeze = true
			body.linear_velocity = Vector3.ZERO
			body.set_meta("piston_rider", 0)
			body.set_meta("piston_rider_freeze_mode", body.freeze_mode)
			var near = Transform3D(Basis.looking_at(center - (center + Vector3(0, 0, 2))), center + Vector3(0, 0, 2))
			session.peers[peer].camera = near
			session.peers[peer].action_time = Time.get_ticks_msec()
			session._action(peer, "grab", body.get_instance_id())
			report.immediate_repickup = session.held.has(peer)
			report.piston_detached = not body.has_meta("piston_rider") and not body.freeze
			if session.held.has(peer): session._release(peer, false)
			await get_tree().process_frame
			body.global_position = Vector3(0, 150, 20)
			body.freeze = true
			var wall = StaticBody3D.new()
			var wall_shape = CollisionShape3D.new()
			var box = BoxShape3D.new()
			box.size = Vector3(20, 20, 0.2)
			wall_shape.shape = box
			wall.add_child(wall_shape)
			get_tree().current_scene.add_child(wall)
			wall.global_position = hit.position + direction * 1.5
			wall.basis = Basis.looking_at(-direction, Vector3.RIGHT if direction == Vector3.UP else Vector3.UP)
			await get_tree().physics_frame
			await get_tree().physics_frame
			session.peers[peer].camera = eye
			session._action(peer, "grab", body.get_instance_id())
			report.wall_blocks_pickup = not session.held.has(peer)
			wall.queue_free()
		var passed = true
		for value in report.values():
			if value == false: passed = false
		report.passed = passed
		reports[kind] = report
		if session.held.has(peer): session._release(peer, false)
		body.queue_free()
		await get_tree().process_frame
	reports.passed = reports.fan.passed and reports.fan2.passed and reports.fan_3.passed
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/fan-pickup-test.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(reports, "  "))
