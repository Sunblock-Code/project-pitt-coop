extends CharacterBody3D

var footstep_stream: AudioStream
var footstep_bus: StringName = &"Master"
var surface_streams: Dictionary = {}
var footstep_audio: AudioStreamPlayer
var step_distance = 0.0
var walking_last_frame = false
var footsteps_played = 0
var qa_walk = false
var camera: Camera3D
var render_camera: Camera3D
var previous_position = Vector3.ZERO
var movement_sampled = false
var session: Node
var equip_qa_input = false
var craft_pressed = false
var craft_tick = 0.0
var rotate_motion = Vector2.ZERO
var rotate_tick = 0.0
var speed := 3.5
var jump_hold = 0.0
var jumping = false
var crouched = false
var shape_node: CollisionShape3D
var crouch_was_pressed = false
var crouch_toggled = false
var slide_time = 0.0
var slide_velocity = Vector3.ZERO

func _ready():
	footstep_audio = AudioStreamPlayer.new()
	footstep_audio.name = "GuestFootsteps"
	footstep_audio.stream = footstep_stream
	footstep_audio.bus = footstep_bus
	add_child(footstep_audio)
	collision_layer = 0
	collision_mask = 3
	var shape = CollisionShape3D.new()
	shape_node = shape
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	camera = Camera3D.new()
	camera.position.y = 1.65
	camera.fov = 80
	add_child(camera)
	# Keep the aim camera on the physics body; render between physics samples.
	render_camera = Camera3D.new()
	render_camera.name = "SmoothGuestCamera"
	add_child(render_camera)
	render_camera.top_level = true
	render_camera.fov = camera.fov
	render_camera.make_current()
	_update_render_camera()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _input(event):
	if session.emotes.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if session.test_mode and ("--equip-test" in OS.get_cmdline_user_args() or "--toggle-test" in OS.get_cmdline_user_args() or "--broom-guest-test" in OS.get_cmdline_user_args() or "--terminal-test" in OS.get_cmdline_user_args()) and not equip_qa_input: return
	# Release must cancel even when a GUI control consumes the mouse event.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		craft_pressed = false
		session._send(1, ["craft_stop"])
		session._send(1, ["pose", global_transform, camera.global_transform])
		if session.grab_settings.hold_to_grab: session._send(1, ["grab_release"])

func _unhandled_input(event):
	if session.test_mode and ("--equip-test" in OS.get_cmdline_user_args() or "--toggle-test" in OS.get_cmdline_user_args() or "--broom-guest-test" in OS.get_cmdline_user_args() or "--terminal-test" in OS.get_cmdline_user_args()) and not equip_qa_input: return
	if session.test_mode and event is InputEventMouseButton:
		print("[COOP] GUEST INPUT mouse=", Input.mouse_mode, " event=", event.button_index, " pressed=", event.pressed)
	if session.guest_settings.active(): return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not session.test_mode:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) and session.guest_held_id != 0 and not session.tool_equipped:
			rotate_motion += event.relative
			return
		var preferences = get_node("/root/MenuManager").settings.controls
		var sensitivity = float(preferences.mouse_sensitivity) * 0.004
		rotate_y(-event.relative.x * sensitivity * (-1.0 if preferences.invert_x else 1.0))
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * sensitivity * (-1.0 if preferences.invert_y else 1.0), -1.5, 1.5)
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not (session.test_mode and DisplayServer.get_name() == "headless"):
		return
	if event.is_action_pressed("rack") and not event.is_echo():
		session.guest_action("rack")
		return
	if session.guest_held_id != 0 and not session.tool_equipped:
		var command = ""
		if event is InputEventKey and event.pressed and not event.echo:
			if event.is_action_pressed("rotate"): command = "snap"
			elif event.is_action_pressed("reset"): command = "reset"
			elif event.is_action_pressed("action") and session.held_controls.guest_snap: command = "tier"
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP: command = "farther"
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: command = "nearer"
		if not command.is_empty():
			session._send(1, ["pose", global_transform, camera.global_transform])
			session._send(1, ["held_control", command])
			return
	if session.guest_held_id == 0 and not session.tool_equipped and event is InputEventMouseButton and event.pressed:
		var tuning = {MOUSE_BUTTON_WHEEL_UP: "tune_up", MOUSE_BUTTON_WHEEL_DOWN: "tune_down", MOUSE_BUTTON_RIGHT: "tune_cycle"}
		if tuning.has(event.button_index):
			session.guest_action(tuning[event.button_index])
			return
	if session.remote_tools.equipped_guest() and event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			session.guest_action("remote_next" if event.button_index == MOUSE_BUTTON_WHEEL_UP else "remote_previous")
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			session.guest_action("remote_all" if InputMap.has_action("remote_toggle_all") and Input.is_action_pressed("remote_toggle_all") else "grab")
			return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			craft_pressed = true
			craft_tick = 0.0
			session.guest_action("grab" if session.grab_settings.hold_to_grab else "grab_toggle")
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if session.tool_equipped:
				session._send(1, ["pose", global_transform, camera.global_transform])
				session._send(1, ["broom_sweep"])
			else: session.guest_action("throw")
	if event.is_action_pressed("equip") and not event.is_echo():
		session.guest_action("equip")
	elif event.is_action_pressed("interact") and not event.is_echo():
		session.guest_action("interact")

func _physics_process(delta):
	previous_position = global_position
	movement_sampled = true
	var upgrades = get_node("/root/GameState").upgrades
	var sprint_level = int(upgrades.sprint.level)
	var jump_level = int(upgrades.jump.level)
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	var axis = Vector2.ZERO
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Physical keys are independent of the host's customized input actions.
		axis = Input.get_vector("left", "right", "up", "down")
		if Input.is_action_pressed("jump") and is_on_floor() and jump_level > 0:
			velocity.y = 3.75 * (1.0 + (jump_level - 1) / 2.5)
			jumping = true
			jump_hold = 0.0
	if qa_walk: axis = Vector2(1, 0)
	if jumping:
		if Input.is_action_pressed("jump") and velocity.y > 0 and jump_hold < 0.25:
			velocity.y += 10.0 * delta
			jump_hold += delta
		else:
			jumping = false
	var crouch_pressed = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed("crouch")
	var toggle_crouch = bool(get_node("/root/MenuManager").settings.gameplay.crouch_toggle)
	if crouch_pressed and not crouch_was_pressed and int(upgrades.crouch.level) > 0:
		crouch_toggled = not crouched
	if not toggle_crouch: crouch_toggled = false
	if crouch_pressed and not crouch_was_pressed and is_on_floor() and sprint_level > 0 and int(upgrades.slide.level) > 0 and Input.is_action_pressed("sprint"):
		slide_time = 0.6
		slide_velocity = -global_basis.z * 10.0 * (1.0 + 0.25 * int(upgrades.slide.level))
	crouch_was_pressed = crouch_pressed
	slide_time = maxf(0.0, slide_time - delta)
	var wants_crouch = (int(upgrades.crouch.level) > 0 and (crouch_toggled if toggle_crouch else crouch_pressed)) or slide_time > 0
	if crouched and not wants_crouch:
		var standing = CapsuleShape3D.new()
		standing.radius = 0.3
		standing.height = 1.8
		var probe = PhysicsShapeQueryParameters3D.new()
		probe.shape = standing
		probe.transform = Transform3D(global_basis, global_position + Vector3(0, 0.92, 0))
		probe.collision_mask = collision_mask
		probe.exclude = [get_rid()]
		wants_crouch = not get_world_3d().direct_space_state.intersect_shape(probe, 1).is_empty()
	crouched = wants_crouch
	shape_node.shape.height = 0.95 if crouched else 1.8
	shape_node.position.y = shape_node.shape.height * 0.5
	camera.position.y = 0.8 if crouched else 1.65
	var direction = global_basis * Vector3(axis.x, 0, axis.y)
	var pace = speed * (1.0 + sprint_level * 0.2) * (1.6 if sprint_level > 0 and Input.is_action_pressed("sprint") else 1.0)
	if crouched: pace *= 0.5
	velocity.x = direction.x * pace
	velocity.z = direction.z * pace
	if slide_time > 0:
		velocity.x = slide_velocity.x
		velocity.z = slide_velocity.z
	if session.broom_players.remaining > 0.0:
		velocity.x = session.broom_players.push.x
		velocity.z = session.broom_players.push.z
	var grounded_before = is_on_floor()
	move_and_slide()
	_update_footsteps(previous_position, grounded_before, sprint_level > 0 and Input.is_action_pressed("sprint"))
	if global_position.y < -150:
		global_position = session.spawn_position

func _process(delta):
	rotate_tick += delta
	if rotate_tick >= 0.033 and not rotate_motion.is_zero_approx():
		session._send(1, ["rotate_held", rotate_motion.limit_length(100.0)])
		rotate_motion = Vector2.ZERO
		rotate_tick = 0.0
	_update_render_camera()
	if session.tool_equipped and session.replicas.has(session.guest_held_id):
		var broom = session.replicas[session.guest_held_id]
		broom.collision_layer = 0
		broom.global_transform = render_camera.global_transform * session.broom_players.local_equipped_pose()
	session.broom_players.update_guest_preview(delta)
	if not craft_pressed: return
	if session.guest_terminal.active() or session.panel.visible or session.character_editor.visible or session.pending_intro or (Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not (session.test_mode and DisplayServer.get_name() == "headless")):
		craft_pressed = false
		session._send(1, ["craft_stop"])
		session._send(1, ["pose", global_transform, camera.global_transform])
		session._send(1, ["grab_release"])
		return
	craft_tick += delta
	if craft_tick >= 0.15:
		craft_tick = 0.0
		session.guest_action("craft_hold")

func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and craft_pressed and not session.test_mode:
		craft_pressed = false
		session._send(1, ["craft_stop"])
		session._send(1, ["pose", global_transform, camera.global_transform])
		session._send(1, ["grab_release"])

func _update_render_camera():
	if not is_instance_valid(render_camera): return
	var origin = global_position
	if movement_sampled and previous_position.distance_to(global_position) < 2.0:
		origin = previous_position.lerp(global_position, Engine.get_physics_interpolation_fraction())
	# Mouse look uses the latest input, with no smoothing delay on rotation.
	render_camera.global_transform = Transform3D(camera.global_basis, origin + global_basis * camera.position)
	camera.fov = float(get_node("/root/PostProcessManager").fov_value)
	render_camera.fov = camera.fov

func _update_footsteps(before: Vector3, grounded_before: bool, sprinting: bool):
	var distance = Vector2(global_position.x - before.x, global_position.z - before.z).length()
	var walking = is_on_floor() and distance > 0.001 and distance < 1.0 and slide_time <= 0.0
	if is_on_floor() and not grounded_before:
		_play_footstep(sprinting)
	elif walking and not walking_last_frame:
		_play_footstep(sprinting)
	if walking:
		step_distance += distance
		var stride = 2.0 * (1.3 if crouched else 0.8 if sprinting else 1.0)
		if step_distance >= stride:
			_play_footstep(sprinting)
			step_distance = fmod(step_distance, stride)
	else:
		step_distance = 0.0
	walking_last_frame = walking

func _play_footstep(sprinting: bool):
	var stream = footstep_stream
	var query = PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.25, global_position - Vector3.UP * 0.4, collision_mask)
	query.exclude = [get_rid()]
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	if hit:
		var surface = hit.collider.get_meta("coop_footstep_surface", "")
		stream = surface_streams.get(surface, stream)
	if stream == null: return
	footstep_audio.stream = stream
	footstep_audio.pitch_scale = randf_range(0.9, 1.1)
	footstep_audio.volume_db = -10.0 if crouched else 0.0 if sprinting else -5.0
	footstep_audio.play()
	footsteps_played += 1
