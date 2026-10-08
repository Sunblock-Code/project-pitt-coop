extends Node
var session: Node
var report: Dictionary = {}

func _ready():
	run.call_deferred()

func save_report():
	report.passed = not report.values().has(false)
	FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/corpse-" + session.role + ".json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("[CORPSE QA] ", report)

func run():
	await get_tree().create_timer(12).timeout
	if session.role != "host": return
	var peer = session.peers.keys()[0]
	var press = load("res://scenes/press.tscn").instantiate()
	get_tree().current_scene.add_child(press)
	press.global_position = Vector3(9, 0.01, 21)
	for shape in press.find_children("*","CollisionShape3D",true,false):
		print("[PRESS COLLIDER] ",shape.name," transform=",shape.global_transform," type=",shape.shape," shapeowner=",shape.get_parent().name)
	print("[PRESS GEOMETRY] origin=",press.global_position," area=",press.detection_collision.global_transform," size=",press.detection_collision.shape.size," plate=",press.press_mesh.position)
	var center = press.detection_collision.global_position - Vector3(0, 0.85, 0)
	session.host_player.set_physics_process(true)
	session.host_player.teleport_to(center + Vector3(0.25, 0, 0))
	session._send(peer, ["corpse_qa", "place", center - Vector3(0.25, 0, 0)])
	await get_tree().create_timer(1).timeout
	report.guest_in_press = session.press_corpses.inside(press, session.peers[peer].pose.origin)
	print("[PRESS START] host=",session.host_player.global_position," guest=",session.peers[peer].pose.origin)
	press.press_duration = 6.0
	press.start_pressing()
	await get_tree().create_timer(2.7).timeout
	var corpses: Array = []
	for body in session.indexed_bodies.values():
		if body.get_meta("coop_corpse", false): corpses.append(body)
	report.two_corpses = corpses.size() == 2
	report.host_respawned = session.host_player.global_position.distance_to(center) > 3
	await get_tree().create_timer(0.5).timeout
	report.guest_respawned = session.peers[peer].pose.origin.distance_to(center) > 3
	await get_tree().create_timer(3.2).timeout
	for body in corpses: print("[CORPSE REST] ",body.global_position," layers=",body.collision_layer," mask=",body.collision_mask)
	print("[HOST PICK MASK] ",session.host_player.get_node("CameraPivot/MainCamera/InteractRay").collision_mask)
	if corpses.size() != 2:
		save_report()
		return
	report.stays_on_press_bed = corpses.all(func(body): return absf(body.global_position.x-press.global_position.x)<1.5 and absf(body.global_position.z-press.global_position.z)<3.5 and body.global_position.y>press.global_position.y-0.1 and body.global_position.y<press.global_position.y+0.5)
	var eye = session.host_player.get_node("CameraPivot/MainCamera")
	session.host_player.set_physics_process(false)
	eye.set_process(false)
	eye.set_physics_process(false)
	eye.global_position = Vector3(corpses[0].global_position.x,press.global_position.y+1.4,press.global_position.z-3.55)
	eye.look_at(corpses[0].global_position)
	var ray = eye.interact_ray
	await get_tree().physics_frame
	ray.force_raycast_update()
	print("[CORPSE PICK] hit=",ray.get_collider()," target=",ray.target_position," from=",ray.global_position," to=",corpses[0].global_position)
	report.host_ray_targets_corpse = ray.get_collider() == corpses[0]
	Input.action_press("lMouse")
	eye.pick_object()
	report.host_real_pickup = eye.picked_object == corpses[0]
	eye.drop_object(true)
	Input.action_release("lMouse")
	session.peers[peer].pose_time = 0
	var ids = corpses.map(func(body): return body.get_instance_id())
	session._scan_bodies()
	session._send(peer, ["corpse_qa", "inspect", ids, corpses[1].global_position])
	await get_tree().create_timer(2).timeout
	report.guest_can_carry = session.held.has(peer) and session.held[peer].id == corpses[1].get_instance_id()
	session._release(peer, true)
	report.guest_can_throw = not session.held.has(peer)
	var maw = get_tree().current_scene.find_children("*", "Area3D", true, false).filter(func(node): return node.has_method("_free_recycle_cube"))[0]
	var game = get_node("/root/GameState")
	var before = game.money.to_float()
	# Trigger the same signal as a physical throw into the hole.
	maw.body_entered.emit(corpses[0])
	maw.body_entered.emit(corpses[0])
	report.one_dollar_once = game.money.to_float() == before + 1
	maw.body_entered.emit(corpses[1])
	report.two_dollars_total = game.money.to_float() == before + 2
	await get_tree().process_frame
	report.models_deleted = not is_instance_valid(corpses[0]) and not is_instance_valid(corpses[1])
	var mouth_shape = maw.find_children("*", "CollisionShape3D", true, false)[0]
	var physical = session.press_corpses.spawn_corpse(session.profile, mouth_shape.global_position - Vector3(0, 0.2, 0), 0)
	physical.gravity_scale = 0
	await get_tree().create_timer(0.6).timeout
	report.physical_hole_entry = not is_instance_valid(physical) and game.money.to_float() == before + 3
	session._scan_bodies()
	session._send(peer, ["corpse_qa", "removed", ids, game.format_big_number(game.money)])
	save_report()

func guest_check(msg):
	if msg[1] == "place":
		session.guest.set_physics_process(true)
		session.guest.global_position = msg[2]
	elif msg[1] == "inspect":
		await get_tree().create_timer(0.5).timeout
		report.two_replicas = msg[2].all(func(id): return session.replicas.has(id))
		report.flat_visuals = msg[2].all(func(id): return session.replicas[id].has_node("FlatCharacter"))
		for id in msg[2]:
			var body = session.replicas[id]
			report.grabbable = body.get_meta("coop_grabbable", false)
		session.guest.set_physics_process(false)
		session.guest.global_position = msg[3] + Vector3(0, 1.3, 3.5)
		session.guest.camera.look_at(msg[3])
		var light = OmniLight3D.new()
		session.add_child(light)
		light.global_position = msg[3] + Vector3(0, 3, 0)
		light.omni_range = 12
		light.light_energy = 4
		await get_tree().create_timer(0.3).timeout
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/corpses.png"))
		session.guest_action("grab")
	elif msg[1] == "removed":
		await get_tree().create_timer(1.5).timeout
		report.replicas_deleted = msg[2].all(func(id): return not session.replicas.has(id))
		report.shared_money = session.progress_menu.state.get("money", "") == msg[3]
		save_report()
