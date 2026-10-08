extends Node
var session: Node
func obstacle(pos: Vector3) -> RigidBody3D:
	var body = RigidBody3D.new()
	body.freeze = true
	body.collision_layer = 2
	body.collision_mask = 0
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(1,3,3)
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = pos
	return body
func blocked(player) -> bool:
	return player.test_move(Transform3D(Basis.IDENTITY,Vector3(100,100,100)),Vector3(3,0,0))
func save_report(name: String, report: Dictionary):
	report.passed = not report.values().has(false)
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/collision-"+name+".json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"  "))
func run():
	await get_tree().create_timer(10).timeout
	var body = obstacle(Vector3(102,101,100))
	await get_tree().physics_frame
	var player = session.host_player
	var original_duck = load("res://scenes/duck.tscn").instantiate()
	body.collision_layer = original_duck.collision_layer
	print("[COLLISION QA] host mask=",player.collision_mask," native item layer=",body.collision_layer)
	original_duck.free()
	await get_tree().physics_frame
	var report = {"host_default_blocks":blocked(player)}
	session.item_collision.set_disabled(true,true)
	session.item_collision.track(body)
	await get_tree().physics_frame
	report.host_disabled_passes = not blocked(player)
	session.item_collision.set_disabled(false,true)
	await get_tree().physics_frame
	report.host_restored = blocked(player)
	report.guests_independent = not session.item_collision.guests_disabled
	save_report("host",report)
	if DisplayServer.get_name() != "headless":
		session.lobby.hide()
		session._toggle_panel()
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/collision-menu.png"))
	body.queue_free()
	session._broadcast(["collision_qa"])
	await get_tree().create_timer(3).timeout
	session.item_collision.set_disabled(true,false)
	await get_tree().create_timer(3).timeout
	session.item_collision.set_disabled(false,false)
func guest_run():
	var body = obstacle(Vector3(102,101,100))
	await get_tree().physics_frame
	var report = {"guest_default_blocks":blocked(session.guest),"default_mask":session.guest.collision_mask == 3}
	session.replicas[-62] = body
	session.guest_held_id = -62
	session.item_collision.update_held()
	await get_tree().physics_frame
	report.own_held_passes = not blocked(session.guest)
	session.guest_held_id = 0
	session.item_collision.update_held()
	await get_tree().physics_frame
	report.dropped_blocks = blocked(session.guest)
	await get_tree().create_timer(3.5).timeout
	report.remote_disable = session.guest.collision_mask == 1 and not blocked(session.guest)
	await get_tree().create_timer(3).timeout
	report.remote_restore = session.guest.collision_mask == 3 and blocked(session.guest)
	session.replicas.erase(-62)
	body.queue_free()
	save_report("guest",report)
