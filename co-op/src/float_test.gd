extends Node
var session: Node
func run():
	await get_tree().create_timer(10).timeout
	var report = {}
	var peer = session.peers.keys()[0]
	var eye = session.host_player.get_node("CameraPivot/MainCamera")
	get_node("/root/GameState").upgrades.equip.level = 1
	for kind in ["sponge","broom","broom2"]:
		var body = load("res://scenes/"+kind+".tscn").instantiate()
		get_tree().current_scene.add_child(body)
		body.global_position = Vector3(30,20,30)
		var gravity = body.gravity_scale
		session._scan_bodies()
		session._begin_guest_carry(peer,body)
		eye._begin_carry(body)
		report[kind+"_guest_owner_protected"] = session.held.has(peer) and eye.picked_object != body
		session._release(peer,false)
		report[kind+"_guest_restores_gravity"] = body.gravity_scale == gravity and not body.has_meta("_held_gravity_scale")
		eye._begin_carry(body)
		session._begin_guest_carry(peer,body)
		report[kind+"_host_owner_protected"] = eye.picked_object == body and not session.held.has(peer)
		eye.drop_object(true)
		report[kind+"_host_restores_gravity"] = body.gravity_scale == gravity
		if kind != "sponge":
			session._begin_guest_carry(peer,body)
			session.broom_players.equip_guest(peer,body.get_instance_id())
			session._release(peer,false)
			report[kind+"_equip_release"] = not body.freeze and not body.is_equipped and body.gravity_scale == gravity
		body.global_position = Vector3(30,20,30)
		body.linear_velocity = Vector3.ZERO
		body.sleeping = false
		session._scan_bodies()
		session._broadcast(["float_qa",body.get_instance_id(),kind])
		await get_tree().create_timer(1).timeout
		report[kind+"_falls"] = body.global_position.y < 19.0
		body.queue_free()
	report.passed = not report.values().has(false)
	FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/float-host.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
func guest_check(id: int, kind: String):
	await get_tree().create_timer(0.2).timeout
	if not session.replicas.has(id): return
	var body = session.replicas[id]
	var start = body.global_position.y
	await get_tree().create_timer(0.5).timeout
	var report = {"replica_falls":is_instance_valid(body) and body.global_position.y < start-0.3}
	FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/float-guest-"+kind+".json"),FileAccess.WRITE).store_string(JSON.stringify(report))
