extends Node
var session: Node
func run(broom, peer):
	var report = {"directions": [], "recovered_after_killed_tween": false, "re_equipped": false, "self_ignored": true}
	var duck = load("res://scenes/duck.tscn").instantiate()
	get_tree().current_scene.add_child(duck)
	duck.gravity_scale = 0
	duck.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	duck.linear_damp = 0
	for angle in [Vector2(0, 0), Vector2(90, 0), Vector2(180, 0), Vector2(-90, 0), Vector2(45, 75), Vector2(-45, -75)]:
		await get_tree().create_timer(0.75).timeout
		var eye = Transform3D(Basis.from_euler(Vector3(deg_to_rad(angle.y), deg_to_rad(angle.x), 0)), Vector3(1000, 50, 1000))
		broom.get_parent().global_transform = eye
		broom.transform = broom.COOP_REST
		duck.global_position = broom.sweep_area.get_child(0).global_position
		duck.linear_velocity = Vector3.ZERO
		await get_tree().physics_frame
		await get_tree().physics_frame
		var started = broom.coop_guest_sweep(eye)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var forward = -eye.basis.z.normalized()
		var valid = started and broom.coop_hits.has(duck.get_instance_id()) and duck.linear_velocity.normalized().dot(forward) > 0.99
		report.directions.append({"yaw": angle.x, "pitch": angle.y, "passed": valid})
		# Interrupt the animation after every shot; the next shot must recover.
		if is_instance_valid(broom._sweep_tween): broom._sweep_tween.kill()
	await get_tree().create_timer(0.75).timeout
	report.recovered_after_killed_tween = broom.coop_guest_sweep(session.peers[peer].camera)
	var saved_pose = session.peers[peer].camera
	session.broom_players.unequip_body(peer, broom)
	var anchor = Camera3D.new()
	get_tree().current_scene.add_child(anchor)
	anchor.global_transform = saved_pose
	broom.equip(anchor)
	broom.freeze = true
	report.re_equipped = broom.coop_guest_sweep(saved_pose)
	session.held[peer].anchor = anchor
	var before = session.broom_players.push
	session.broom_players.receive(1, Vector3(9, 0, 0))
	report.self_ignored = before == session.broom_players.push
	report.passed = report.recovered_after_killed_tween and report.re_equipped and report.self_ignored
	for result in report.directions: report.passed = report.passed and result.passed
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/broom-stress.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	duck.queue_free()
