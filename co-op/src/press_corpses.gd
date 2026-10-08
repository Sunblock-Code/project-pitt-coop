extends Node
var session: Node
const SCENE = "res://coop/corpse.tscn"
const Corpse = preload("res://coop/corpse.gd")

func inside(press: Node, feet: Vector3) -> bool:
	var shape = press.detection_collision
	if not shape.shape is BoxShape3D: return false
	var point: Vector3 = shape.global_transform.affine_inverse() * (feet + Vector3(0, 0.85, 0))
	var half: Vector3 = shape.shape.size / 2 + Vector3(0.25, 0.8, 0.25)
	return absf(point.x) <= half.x and absf(point.y) <= half.y and absf(point.z) <= half.z

func spawn_corpse(appearance: Dictionary, position: Vector3, yaw: float) -> RigidBody3D:
	var body = load(SCENE).instantiate()
	body.set_meta("corpse_profile", appearance.duplicate(true))
	body.position = get_tree().current_scene.to_local(position + Vector3(0, 0.2, 0))
	body.rotation.y = yaw
	get_tree().current_scene.add_child(body)
	return body

func crush(press: Node):
	var victims: Array = []
	var local = session.host_player
	if is_instance_valid(local) and inside(press, local.global_position):
		victims.append(session.profile.duplicate(true))
		var camera = local.get_node("CameraPivot/MainCamera")
		camera.release_held_object()
		local.respawn_safe()
	for peer in session.peers:
		var data: Dictionary = session.peers[peer]
		if not data.ready or not data.pose_time or not inside(press, data.pose.origin): continue
		victims.append(session.profiles.get(peer, session.Avatar.defaults()).duplicate(true))
		session._release(peer, false)
		session._end_craft(peer)
		var destination = local._find_clear_spot(Vector3(0, 6, 18))
		data.pose.origin = destination
		session._send(peer, ["press_respawn", destination])
	# The corpse belongs to the press, never the respawn destination.
	for i in victims.size():
		var offset = Vector3.ZERO if victims.size() == 1 else Vector3(-0.7 if i % 2 == 0 else 0.7,0,-1.45 if i < 2 else 1.45)
		if victims.size() == 2: offset.z = -1.45 if i == 0 else 1.45
		var center: Vector3 = press.to_global(offset)
		var query = PhysicsRayQueryParameters3D.create(center+Vector3.UP*0.5,center-Vector3.UP*1.0,press.collision_layer | 1)
		query.exclude = [local.get_rid()]
		var hit = press.get_world_3d().direct_space_state.intersect_ray(query)
		var bed_y = hit.position.y if not hit.is_empty() else center.y
		var body = spawn_corpse(victims[i],Vector3(center.x,bed_y-0.075,center.z),press.global_rotation.y)
		body.freeze = true
		body.set_meta("press_settling",true)
		settle_after_press(body,press.press_duration*0.6+0.1)
	session._scan_bodies()

func settle_after_press(body: RigidBody3D, seconds: float):
	await get_tree().create_timer(seconds).timeout
	if not is_instance_valid(body) or not body.get_meta("press_settling",false): return
	body.remove_meta("press_settling")
	body.freeze = false
	body.sleeping = false

func respawn_guest(position: Vector3):
	var guest = session.guest
	guest.global_position = position
	guest.velocity = Vector3.ZERO
	guest.slide_velocity = Vector3.ZERO
	guest.slide_time = 0.0
	guest.crouched = false
	guest.crouch_toggled = false
	guest.previous_position = position
	guest.movement_sampled = false
	guest.craft_pressed = false
	session.broom_players.push = Vector3.ZERO
	session.info.text = "FLATTENED! Your former self is worth $1."

func consume(body: RigidBody3D):
	# Only the host runs the maw. Mark paid before signals can re-enter.
	if body.get_meta("corpse_paid", false): return
	body.set_meta("corpse_paid", true)
	for peer in session.held.keys():
		if session.held[peer].id == body.get_instance_id(): session._release(peer, false)
	var camera = session.host_player.get_node("CameraPivot/MainCamera")
	if camera.picked_object == body: camera.release_held_object()
	get_node("/root/GameState").add_money(1)
	body.hide()
	body.collision_layer = 0
	body.queue_free()
