extends Node

var session: Node
var guest_pose = Transform3D.IDENTITY
var use_times: Dictionary = {}
var cooldowns: Dictionary = {}
var push = Vector3.ZERO
var remaining = 0.0
var last_targets: Array = []
var slippery_remaining = 0.0
var slide_friction = 0.1
var local_sweep_started = -10000
var sweep_fx_count = 0
var preview_bodies: Array = []
var preview_tick = 0.0

func _ready():
	process_physics_priority = -100

static func is_broom(node) -> bool:
	return is_instance_valid(node) and (node.is_in_group("broom") or bool(node.get_meta("coop_broom", false)) or node.scene_file_path.get_file().get_basename() in ["broom", "broom2"])

func equipped(peer: int) -> bool:
	if peer == 1:
		if not is_instance_valid(session.host_player): return false
		var eye = session.host_player.get_node_or_null("CameraPivot/MainCamera")
		return eye != null and is_broom(eye.get("equipped_item"))
	return session.held.has(peer) and session.held[peer].get("equipped", false) and is_instance_valid(instance_from_id(session.held[peer].id))

func sweep(peer: int):
	last_targets.clear()
	if session.role != "host" or not equipped(peer): return
	if Time.get_ticks_msec() < cooldowns.get(peer, 0): return
	var broom = session.host_player.get_node("CameraPivot/MainCamera").equipped_item if peer == 1 else instance_from_id(session.held[peer].id)
	if not is_broom(broom): return
	var eye: Transform3D = session.host_player.get_node("CameraPivot/MainCamera").global_transform if peer == 1 else session.peers[peer].camera
	if peer == 1:
		if broom.sweeping: return
		broom.interact()
	else:
		if not broom.coop_guest_sweep(eye): return
	cooldowns[peer] = Time.get_ticks_msec() + int((0.25 + broom.sweep_cooldown) * 1000.0)
	session._broadcast(["broom_sweep_fx", peer, broom.get_instance_id()])
	var candidates = {1: session.host_player.global_position}
	for id in session.peers:
		if session.peers[id].ready: candidates[id] = session.peers[id].pose.origin
	for victim in candidates:
		# Identity is checked before distance, so overlapping players cannot hit themselves.
		if victim == peer: continue
		var point: Vector3 = candidates[victim] + Vector3.UP * 0.9
		var offset = point - eye.origin
		if offset.length() > 3.0 or offset.length() < 0.01: continue
		if (-eye.basis.z).dot(offset.normalized()) < 0.65: continue
		var ray = PhysicsRayQueryParameters3D.create(eye.origin, point, 1)
		if peer == 1:
			ray.exclude = [session.host_player.get_rid(), session.host_player.get_node("CameraPivot/MainCamera").equipped_item.get_rid()]
		else: ray.exclude = [instance_from_id(session.held[peer].id).get_rid()]
		var obstruction = session.host_player.get_world_3d().direct_space_state.intersect_ray(ray)
		if obstruction and obstruction.collider != session.host_player: continue
		var sweep_direction: Vector3 = broom.global_basis.z if peer == 1 else -eye.basis.z
		var direction = Vector3(sweep_direction.x, 0, sweep_direction.z).normalized()
		if direction.is_zero_approx(): continue
		last_targets.append(victim)
		var impulse = direction * clampf(broom.sweep_strength * broom.sweep_impulse_multiplier, 0.0, 10.0)
		if victim == 1: receive(peer, impulse, broom.slide_duration, broom.slide_friction)
		else: session._send(victim, ["broom_push", peer, impulse, broom.slide_duration, broom.slide_friction])

func receive(attacker: int, velocity: Vector3, duration: float = 1.0, friction: float = 0.1):
	var own_id = 1 if session.role == "host" else session.net.get_unique_id()
	if attacker == own_id or not velocity.is_finite(): return
	push = Vector3(velocity.x, 0, velocity.z).limit_length(10.0)
	slippery_remaining = clampf(duration, 0.1, 3.0)
	slide_friction = clampf(friction, 0.0, 2.0)
	remaining = slippery_remaining + 0.5
	if session.test_mode and session.role == "guest":
		var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/broom-received.json"), FileAccess.WRITE)
		if file: file.store_string(JSON.stringify({"attacker": attacker, "recipient": own_id, "passed": attacker != own_id and push.length() <= 10.01 and slippery_remaining > 0.0}))

func _physics_process(delta):
	if remaining <= 0.0: return
	remaining = maxf(0.0, remaining - delta)
	slippery_remaining = maxf(0.0, slippery_remaining - delta)
	push = push.move_toward(Vector3.ZERO, (slide_friction * 20.0 if slippery_remaining > 0.0 else 20.0) * delta)
	if push.length_squared() < 0.0001: remaining = 0.0
	if session.role == "host" and is_instance_valid(session.host_player):
		# Let the original CharacterBody motion resolve walls and floors.
		session.host_player.velocity.x = push.x
		session.host_player.velocity.z = push.z

func equip_guest(peer: int, id):
	if session.held.has(peer) and session.held[peer].get("equipped", false):
		session.held[peer].equipped = false
		var body = instance_from_id(session.held[peer].id)
		if is_instance_valid(body):
			unequip_body(peer, body)
			body.collision_layer = session.held[peer].get("layer", 2)
			body.freeze = false
		session._send(peer, ["tool_equipped", false])
		return
	if int(get_node("/root/GameState").upgrades["equip"].level) <= 0:
		session._send(peer, ["notice", "Purchase the Equip upgrade first."])
		return
	if not id is int or not session.bodies.has(id) or not can_equip(instance_from_id(id)): return
	if not session.held.has(peer): session._action(peer, "grab", id)
	if not session.held.has(peer) or session.held[peer].id != id: return
	var body = instance_from_id(id)
	session.held[peer].equipped = true
	session.held[peer].layer = body.collision_layer
	var anchor = Camera3D.new()
	anchor.name = "GuestBroomAnchor"
	anchor.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().current_scene.add_child(anchor)
	anchor.global_transform = session.peers[peer].camera
	session.held[peer].anchor = anchor
	body.freeze = true
	body.equip(anchor)
	if is_broom(body):
		body.position = Vector3(0.4, -1.0, -1.5)
		body.rotation = Vector3(0, PI, 0)
		# A guest sweep preview belongs only on that guest screen.
		body.preview_enabled = false
	if session.remote_tools.is_remote(body):
		body.position = Vector3(0.3, -0.3, -0.5)
		body.rotation = Vector3(0, PI / 2.0, deg_to_rad(50))
	if body.is_in_group("fan"):
		body.position = Vector3(0, -1, -1)
		body.rotation = Vector3(0, PI / 2.0, 0)
	session._send(peer, ["equipped_pose", body.transform])
	session._send(peer, ["tool_equipped", true])

func unequip_body(peer: int, body):
	cooldowns.erase(peer)
	var hold = session.held.get(peer, {})
	var anchor = hold.get("anchor")
	if is_instance_valid(anchor):
		body.unequip(get_tree().current_scene, body.global_position)
		if is_broom(body): body.preview_enabled = true
		anchor.queue_free()
		hold.erase("anchor")

func sweep_fx(peer: int, id: int):
	sweep_fx_count += 1
	if peer == session.net.get_unique_id():
		local_sweep_started = Time.get_ticks_msec()
		if session.test_mode: capture_sweep.call_deferred()
	if session.replicas.has(id):
		var audio = session.replicas[id].get_node_or_null("SweepAudio3D")
		if audio is AudioStreamPlayer3D: audio.play()

func local_equipped_pose() -> Transform3D:
	if not is_broom(session.replicas.get(session.guest_held_id)): return guest_pose
	# Same 0.1 s sine-out stroke and 0.15 s sine-in-out return as broom.interact.
	var elapsed = (Time.get_ticks_msec() - local_sweep_started) / 1000.0
	var stroke = 0.0
	if elapsed >= 0.0 and elapsed <= 0.1: stroke = sin(elapsed / 0.1 * PI / 2.0)
	elif elapsed < 0.25: stroke = (1.0 + cos((elapsed - 0.1) / 0.15 * PI)) * 0.5
	return Transform3D(Basis.from_euler(guest_pose.basis.get_euler() + Vector3(deg_to_rad(-30.0 * stroke), 0, 0)), guest_pose.origin + Vector3(0, 0, -0.4 * stroke))

func rotate_held(peer: int, motion: Vector2):
	if not session.held.has(peer) or equipped(peer) or not session.peers.has(peer): return
	var body = instance_from_id(session.held[peer].id)
	if not is_instance_valid(body): return
	var mouse = motion.limit_length(100.0)
	var eye: Transform3D = session.peers[peer].camera
	body.global_rotate(eye.basis.y.normalized(), mouse.x * 0.01)
	body.global_rotate(eye.basis.x.normalized(), mouse.y * 0.01)
	body.angular_velocity = Vector3.ZERO

func _process(_delta):
	if session.role != "host" or not equipped(1): return
	var label = get_tree().current_scene.find_child("controls_label", true, false)
	if label is Label and not label.text.contains("Sweep / Slide players"):
		label.text += " | [RMB] Sweep / Slide players"

func run_checks():
	await get_tree().create_timer(15.0).timeout
	if session.peers.is_empty(): return
	var peer = session.peers.keys()[0]
	var body = load("res://scenes/broom.tscn").instantiate()
	get_tree().current_scene.add_child(body)
	body.freeze = true
	var id = body.get_instance_id()
	session.bodies[id] = body.scene_file_path
	get_node("/root/GameState").upgrades["equip"].level = 1
	session.host_player.set_physics_process(false)
	session.host_player.global_position = Vector3(0, 6, 18)
	body.global_position = Vector3(0, 6.8, 19)
	session.peers[peer].pose = Transform3D(Basis.IDENTITY, Vector3(0, 6, 20))
	var eye = Transform3D(Basis.IDENTITY, Vector3(0, 7.65, 20)).looking_at(Vector3(0, 6.9, 18))
	session.peers[peer].camera = eye
	session.peers[peer].pose_time = Time.get_ticks_msec()
	session.peers[peer].action_time = 0
	equip_guest(peer, id)
	var did_equip = equipped(peer)
	await get_tree().create_timer(0.5).timeout
	session.peers[peer].pose = Transform3D(Basis.IDENTITY, Vector3(0, 6, 20))
	session.peers[peer].camera = eye
	var rest_pose = body.transform
	await sweep(peer)
	var guest_hits_host_only = last_targets == [1] and remaining > 0.0
	await sweep(peer)
	var cooldown_ok = last_targets.is_empty()
	var before = push
	receive(1, Vector3(7, 0, 0))
	var self_ignored = push == before
	var slide_start = session.host_player.global_position
	session.host_player.set_physics_process(true)
	var native_sweep_started = body.sweeping and is_instance_valid(body._sweep_tween)
	await get_tree().create_timer(0.08).timeout
	var animation_moved = not body.transform.is_equal_approx(rest_pose)
	await get_tree().create_timer(0.22).timeout
	var animation_returned = body.transform.is_equal_approx(rest_pose)
	var slide_delta = session.host_player.global_position - slide_start
	var host_slid = Vector2(slide_delta.x, slide_delta.z).length() > 0.15
	session.host_player.set_physics_process(false)
	session.host_player.global_position = Vector3(0, 6, 18)
	var sliding_like_ducks = remaining > 0.0 and slippery_remaining > 0.5 and push.length() > 3.5
	equip_guest(peer, id)
	cooldowns.clear()
	await sweep(peer)
	var unequipped_blocked = last_targets.is_empty() and not equipped(peer)
	var rotation_before = body.global_basis
	rotate_held(peer, Vector2(25, 15))
	var rotation_works = not body.global_basis.is_equal_approx(rotation_before)
	rotation_before = body.global_basis
	rotate_held(peer + 1, Vector2(25, 15))
	var other_owner_blocked = body.global_basis.is_equal_approx(rotation_before)
	var host_camera = session.host_player.get_node("CameraPivot/MainCamera")
	host_camera.equipped_item = body
	body.freeze = true
	body.equip(host_camera)
	session.peers[peer].pose = Transform3D(Basis.IDENTITY, Vector3(0, 6, 20))
	host_camera.look_at(Vector3(0, 6.9, 20))
	cooldowns.clear()
	sweep(1)
	var host_hits_guest_only = last_targets == [peer]
	await get_tree().create_timer(0.7).timeout
	session.peers[peer].pose.origin = Vector3(0, 6, 30)
	cooldowns.clear()
	sweep(1)
	var range_blocked = last_targets.is_empty()
	host_camera.equipped_item = null
	body.unequip(get_tree().current_scene, body.global_position)
	var report = {"native_sweep_started": native_sweep_started, "animation_moved": animation_moved, "animation_returned": animation_returned, "duck_like_slide": sliding_like_ducks, "host_moved": host_slid, "equipped": did_equip, "guest_hits_host_only": guest_hits_host_only, "host_hits_guest_only": host_hits_guest_only, "cooldown": cooldown_ok, "self_ignored": self_ignored, "unequipped_blocked": unequipped_blocked, "rotation": rotation_works, "other_owner_blocked": other_owner_blocked, "range_blocked": range_blocked}
	report.passed = host_slid and native_sweep_started and animation_moved and animation_returned and sliding_like_ducks and did_equip and guest_hits_host_only and host_hits_guest_only and cooldown_ok and self_ignored and unequipped_blocked and rotation_works and other_owner_blocked and range_blocked
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/broom-test.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))
	session._release(peer, false)
	session.host_player.set_physics_process(true)

func capture_sweep():
	await get_tree().create_timer(0.08).timeout
	var pose = local_equipped_pose()
	var folder = OS.get_executable_path().get_base_dir().path_join("../logs/")
	var file = FileAccess.open(folder + "broom-animation-guest.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"passed": pose.origin.z < -1.2, "stroke_z": pose.origin.z, "events": sweep_fx_count}))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(folder + "broom-sweep-guest.png")

static func can_equip(body) -> bool:
	return is_instance_valid(body) and (is_broom(body) or body.is_in_group("fan") or body.is_in_group("remote")) and body.is_in_group("equipable") and body.has_method("equip") and body.has_method("unequip")

func use_equipped(peer: int):
	if not equipped(peer): return
	var body = instance_from_id(session.held[peer].id)
	if is_broom(body):
		sweep(peer)
		return
	var now = Time.get_ticks_msec()
	if now - use_times.get(peer, -1000) < 150: return
	use_times[peer] = now
	if body.has_method("interact"): body.interact()

func run_equip_host_checks():
	await get_tree().create_timer(28.0).timeout
	if session.peers.is_empty(): return
	var peer = session.peers.keys()[0]
	get_node("/root/GameState").upgrades.equip.level = 1
	var reports = {}
	for kind in ["fan", "broom"]:
		var body = load("res://scenes/" + kind + ".tscn").instantiate()
		get_tree().current_scene.add_child(body)
		body.global_position = Vector3(0, 7, 18)
		body.freeze = true
		session._scan_bodies()
		var previous = body.is_active if kind == "fan" else false
		session._send(peer, ["equip_test_target", body.get_instance_id(), kind])
		await get_tree().create_timer(1.8).timeout
		var report = {"equipped": equipped(peer) and body.is_equipped, "collision_disabled": body.collision_layer == 0}
		await get_tree().create_timer(0.6).timeout
		report.stays_equipped_after_release = equipped(peer) and body.is_equipped
		await get_tree().create_timer(0.7).timeout
		report.used = body.is_active != previous if kind == "fan" else cooldowns.has(peer)
		await get_tree().create_timer(1.2).timeout
		report.unequipped = not equipped(peer) and not body.is_equipped and not body.freeze and body.collision_layer != 0
		report.passed = report.equipped and report.collision_disabled and report.stays_equipped_after_release and report.used and report.unequipped
		reports[kind] = report
		if session.held.has(peer): session._release(peer, false)
		body.queue_free()
		await get_tree().create_timer(0.5).timeout
	reports.passed = reports.fan.passed and reports.broom.passed
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/equip-test.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(reports, "  "))
	var pickup_test = load("res://coop/fan_pickup_test.gd").new()
	pickup_test.session = session
	add_child(pickup_test)
	await pickup_test.run(peer)
	pickup_test.queue_free()

func equip_key():
	var event = InputEventKey.new()
	event.physical_keycode = KEY_E
	event.pressed = true
	session.guest.equip_qa_input = true
	session.guest._unhandled_input(event)
	session.guest.equip_qa_input = false

func run_equip_guest_checks(id: int, kind: String):
	await get_tree().create_timer(0.3).timeout
	if not session.replicas.has(id): return
	session.guest.set_physics_process(false)
	var target = session.replicas[id].global_position
	session.guest.global_position = target + Vector3(0, -0.5, 2)
	session.guest.camera.look_at(target)
	session.pending_intro = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().create_timer(0.7).timeout
	equip_key()
	await get_tree().create_timer(0.8).timeout
	var release = InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	session.guest.equip_qa_input = true
	session.guest._input(release)
	session.guest.equip_qa_input = false
	await get_tree().create_timer(0.7).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/equipped-" + kind + ".png"))
	var use = InputEventMouseButton.new()
	use.button_index = MOUSE_BUTTON_LEFT if kind == "fan" else MOUSE_BUTTON_RIGHT
	use.pressed = true
	session.guest.equip_qa_input = true
	session.guest._unhandled_input(use)
	session.guest.equip_qa_input = false
	await get_tree().create_timer(0.4).timeout
	session.guest.equip_qa_input = true
	session.guest._input(release)
	session.guest.equip_qa_input = false
	await get_tree().create_timer(0.4).timeout
	equip_key()

var toggle_report: Dictionary = {}
var toggle_body: RigidBody3D

func run_toggle_host():
	await get_tree().create_timer(28.0).timeout
	if session.peers.is_empty(): return
	get_node("/root/GameState").upgrades.equip.level = 1
	toggle_body = load("res://scenes/fan.tscn").instantiate()
	get_tree().current_scene.add_child(toggle_body)
	toggle_body.global_position = Vector3(0, 7, 18)
	toggle_body.freeze = true
	toggle_body.is_active = true
	toggle_body.update_fan_state()
	session._scan_bodies()
	session._send(session.peers.keys()[0], ["toggle_test_target", toggle_body.get_instance_id()])

func record_toggle_check(peer: int, msg: Array):
	if not is_instance_valid(toggle_body): return
	var stage: String = msg[1]
	var valid = toggle_body.is_active == msg[2]
	if stage.begins_with("held_"): valid = valid and session.held.has(peer) and not equipped(peer)
	if stage.begins_with("equipped_"): valid = valid and equipped(peer)
	toggle_report[stage] = valid
	if stage == "equipped_on":
		toggle_report.passed = toggle_report.size() == 6 and not toggle_report.values().has(false)
		var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/toggle-test.json"), FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(toggle_report, "  "))

func toggle_key():
	var event = InputEventKey.new()
	event.physical_keycode = KEY_F
	event.pressed = true
	session.guest.equip_qa_input = true
	session.guest._unhandled_input(event)
	session.guest.equip_qa_input = false

func run_toggle_guest(id: int):
	await get_tree().create_timer(0.3).timeout
	if not session.replicas.has(id): return
	session.guest.set_physics_process(false)
	var target = session.replicas[id].global_position
	session.guest.global_position = target + Vector3(0, -0.5, 2)
	session.guest.camera.look_at(target)
	session.pending_intro = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().create_timer(0.8).timeout
	for mode in ["placed", "held", "equipped"]:
		if mode == "held":
			var event = InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = true
			session.guest.equip_qa_input = true
			session.guest._unhandled_input(event)
			session.guest.equip_qa_input = false
			await get_tree().create_timer(0.5).timeout
		elif mode == "equipped":
			equip_key()
			await get_tree().create_timer(0.5).timeout
		for enabled in [false, true]:
			toggle_key()
			await get_tree().create_timer(0.4).timeout
			session._send(1, ["toggle_check", mode + ("_on" if enabled else "_off"), enabled])
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/toggle-" + mode + ".png"))

func update_guest_preview(delta):
	preview_tick -= delta
	if preview_tick > 0.0: return
	preview_tick = 0.05
	var current: Array = []
	var broom = session.replicas.get(session.guest_held_id)
	if session.tool_equipped and is_broom(broom) and Time.get_ticks_msec() - local_sweep_started > 650:
		var area = broom.get_node_or_null("SweepArea")
		if area:
			for shape in area.get_children():
				if not shape is CollisionShape3D or shape.disabled or not shape.shape: continue
				var query = PhysicsShapeQueryParameters3D.new()
				query.shape = shape.shape
				query.transform = shape.global_transform
				query.collision_mask = 2
				query.exclude = [broom.get_rid()]
				for hit in broom.get_world_3d().direct_space_state.intersect_shape(query, 256):
					var body = hit.collider
					if body is RigidBody3D and not body.get_meta("coop_placed", false) and not current.has(body): current.append(body)
	for body in preview_bodies:
		if is_instance_valid(body) and not current.has(body):
			for child in body.find_children("*", "MeshInstance3D", true, false):
				if child.has_meta("coop_outline"): child.hide()
	for body in current:
		for child in body.find_children("*", "MeshInstance3D", true, false):
			if child.has_meta("coop_outline"):
				child.show()
				if child.material_override is StandardMaterial3D: child.material_override.albedo_color = Color.WHITE
	preview_bodies = current
