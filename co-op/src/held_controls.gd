extends Node

var session: Node
var guest_snap = false
var guest_tier = 0
var test_state: Dictionary = {}
var grid_panel: Control
var grid_label: Label
var ghost: MeshInstance3D
var ghost_id = 0
var preview: Array = []
var local_distance = 2.5
var snap_math: Node3D
var predicted_frames = 0
var cached_tier = -1

func _ready():
	process_priority = 100

func copy_grid_ui(world: Node):
	snap_math = load("res://coop/snap_preview_math.gd").new()
	add_child(snap_math)
	for name in ["RotationModePanelIndicator", "rotation_step_label"]:
		var original = world.find_child(name, true, false)
		if original is Control:
			var copy = original.duplicate(0)
			copy.set_script(null)
			copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
			copy.hide()
			session.hud.add_child(copy)
			if name == "rotation_step_label":
				grid_label = copy
				grid_label.add_theme_font_override("font", load("res://assets/PublicPixel-rv0pA.ttf"))
				grid_label.add_theme_font_size_override("font_size", original.get_theme_font_size("font_size"))
			else: grid_panel = copy

func _process(_delta):
	if session.role != "guest" or not is_instance_valid(grid_label): return
	var shown = guest_snap and session.guest_held_id != 0 and not session.panel.visible and not session.lobby.visible and not session.character_editor.visible and not session.guest_terminal.active() and not session.guest_settings.active() and not session.tool_equipped
	grid_label.visible = shown
	if is_instance_valid(grid_panel): grid_panel.visible = shown
	if not shown:
		if is_instance_valid(ghost): ghost.hide()
		return
	grid_label.text = tr("SNAP_MODE_LABEL").format({"grid": ["1", "0.5", "0.25"][guest_tier], "rot": ["45", "22.5", "15"][guest_tier]})
	if not session.replicas.has(session.guest_held_id):
		if is_instance_valid(ghost): ghost.hide()
		return
	var body = session.replicas[session.guest_held_id]
	snap_math.POSITION_SNAP = [1.0, 0.5, 0.25][guest_tier]
	snap_math.ROTATION_SNAP = [45.0, 22.5, 15.0][guest_tier]
	snap_math.SNAP_POINT_RADIUS = [1.1, 0.55, 0.2][guest_tier]
	snap_math.player_controller = session.guest
	if ghost_id != session.guest_held_id or cached_tier != guest_tier:
		snap_math._placement_box_shape = null
		cached_tier = guest_tier
	var eye: Transform3D = session.guest.render_camera.global_transform
	var result = snap_math._compute_snap(body, eye.origin - eye.basis.z * local_distance)
	var basis = result.basis if result.has_basis else snap_math._quantized_basis(body.global_basis)
	preview = [session.guest_held_id, result.position, basis, result.valid]
	predicted_frames += 1
	if ghost_id != preview[0] or not is_instance_valid(ghost):
		if is_instance_valid(ghost): ghost.queue_free()
		ghost = null
		ghost = MeshInstance3D.new()
		var material = StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.no_depth_test = true
		material.disable_receive_shadows = true
		get_tree().current_scene.add_child(ghost)
		preload("res://coop/grid_ghost.gd").populate(ghost, body, material)
		ghost_id = preview[0]
	if not is_instance_valid(ghost): return
	ghost.global_transform = Transform3D(preview[2], preview[1])
	var alpha = 0.5 if body.global_position.distance_to(preview[1]) < 0.1 else 0.3
	ghost.material_override.albedo_color = Color(0, 1, 0, alpha) if preview[3] else Color(1, 0.1, 0.1, alpha + 0.1)
	ghost.show()


func command(peer: int, action: String):
	if not session.held.has(peer) or session.broom_players.equipped(peer): return
	var hold = session.held[peer]
	var body = instance_from_id(hold.id)
	if not is_instance_valid(body): return
	var upgrades = get_node("/root/GameState").upgrades
	match action:
		"snap":
			if int(upgrades.snap_grid.level) <= 0: return
			hold.snap = not hold.get("snap", false)
			if hold.snap: native_snap(body, hold, body.global_position, true)
		"tier":
			if not hold.get("snap", false): return
			hold.tier = (hold.get("tier", 0) + 1) % 3
			native_snap(body, hold, body.global_position, true)
		"reset":
			if int(upgrades.reset_rotation.level) <= 0: return
			var eye: Transform3D = session.peers[peer].camera
			var forward = -eye.basis.z
			forward.y = 0
			if forward.length_squared() < 0.001: forward = Vector3.FORWARD
			var facing = Basis.looking_at(forward.normalized(), Vector3.UP)
			var basis = facing
			if body.has_method("get_reset_basis"): basis *= body.get_reset_basis()
			var now = Time.get_ticks_msec()
			var flat = now - hold.get("reset_time", -100000) <= 200
			hold.reset_time = -100000 if flat else now
			if flat: basis = Basis(facing.x, -PI / 2.0) * basis
			body.global_basis = basis
			body.angular_velocity = Vector3.ZERO
			if hold.get("snap", false): native_snap(body, hold, body.global_position, true)
		"farther", "nearer":
			if int(upgrades.reset_rotation.level) <= 0: return
			hold.distance = clampf(hold.get("distance", 2.5) + (0.15 if action == "farther" else -0.15), 1.5, 3.5)
		_: return
	if session.test_mode and "--held-controls-test" in OS.get_cmdline_user_args():
		session._send(peer, ["held_test", {"basis": body.global_basis, "distance": hold.get("distance", 2.5), "snap": hold.get("snap", false), "tier": hold.get("tier", 0)}])
	session._send(peer, ["held_mode", hold.get("snap", false), hold.get("tier", 0), hold.get("distance", 2.5)])

# Reuse the game's original placement calculations. Save and restore its scratch
# fields synchronously so a guest cannot change the host's snap settings/cache.
func native_snap(body: RigidBody3D, hold: Dictionary, desired: Vector3, rotate_only: bool = false) -> Dictionary:
	var camera = session.host_player.get_node("CameraPivot/MainCamera")
	var fields = ["POSITION_SNAP", "ROTATION_SNAP", "SNAP_POINT_RADIUS", "_placement_box_shape", "_placement_box_center"]
	var saved = {}
	for field in fields: saved[field] = camera.get(field)
	var tier = hold.get("tier", 0)
	camera.POSITION_SNAP = [1.0, 0.5, 0.25][tier]
	camera.ROTATION_SNAP = [45.0, 22.5, 15.0][tier]
	camera.SNAP_POINT_RADIUS = [1.1, 0.55, 0.2][tier]
	if hold.get("bounds_tier", -1) != tier:
		hold.erase("bounds_shape")
		hold.bounds_tier = tier
	camera._placement_box_shape = hold.get("bounds_shape")
	camera._placement_box_center = hold.get("bounds_center", Vector3.ZERO)
	var result = {}
	if rotate_only: camera.snap_rotation_to_grid(body)
	else:
		result = camera._compute_snap(body, desired)
		result.grid_position = camera.snap_to_grid_with_bounds(body, desired, camera.POSITION_SNAP)
	hold.bounds_shape = camera._placement_box_shape
	hold.bounds_center = camera._placement_box_center
	for field in fields: camera.set(field, saved[field])
	return result

func target(peer: int, body: RigidBody3D, desired: Vector3) -> Vector3:
	var hold = session.held[peer]
	if not hold.get("snap", false): return desired
	var result = native_snap(body, hold, desired)
	hold.snap_result = result
	# As on the host, corner alignment belongs to the ghost until release.
	# Applying it to the held body here feeds network rotation back into snap.
	return result.grid_position

func place(peer: int, body: RigidBody3D) -> bool:
	var hold = session.held[peer]
	if not hold.get("snap", false): return false
	var eye: Transform3D = session.peers[peer].camera
	var result = native_snap(body, hold, eye.origin - eye.basis.z * hold.get("distance", 2.5))
	if not result.valid: return false
	body.global_position = result.position
	if result.has_basis: body.global_basis = result.basis
	else: native_snap(body, hold, body.global_position, true)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	if not result.snap.is_empty() and body.has_method("force_place"):
		body.force_place()
		return true
	return false

func run_guest_checks():
	var hud = session.interaction_hud
	await get_tree().create_timer(0.2).timeout
	var text = hud.controls.text
	var distance_before = local_distance
	var report = {"horizontal": not text.contains("\n"), "text": text, "all_controls": true, "font": hud.controls.get_theme_font("font").resource_path, "font_size": hud.controls.get_theme_font_size("font_size"), "fits_width": hud.controls.position.x >= 0 and hud.controls.position.x + hud.controls.size.x * hud.controls.scale.x <= get_viewport().get_visible_rect().size.x}
	for hint in ["Release LMB", "RMB", "[R]", "MMB", "[G]", "Distance"]:
		report.all_controls = report.all_controls and text.contains(hint)
	var folder = OS.get_executable_path().get_base_dir().path_join("../logs/")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(folder + "held-controls.png")
	for command_name in ["farther", "reset", "snap", "tier", "snap"]:
		test_state = {}
		var event: InputEvent
		if command_name == "farther":
			event = InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_WHEEL_UP
		else:
			event = InputEventKey.new()
			event.physical_keycode = KEY_G if command_name == "reset" else KEY_Q if command_name == "tier" else KEY_R
			event.keycode = event.physical_keycode
		event.pressed = true
		Input.parse_input_event(event)
		await get_tree().process_frame
		event = event.duplicate()
		event.pressed = false
		Input.parse_input_event(event)
		await get_tree().create_timer(0.4).timeout
		if command_name == "farther": report.distance_works = test_state.get("distance", 0.0) > distance_before
		elif command_name == "reset":
			var forward = -session.guest.camera.global_basis.z
			forward.y = 0
			var expected = Basis.looking_at(forward.normalized(), Vector3.UP)
			report.reset_works = test_state.has("basis") and test_state.basis.is_equal_approx(expected)
		elif command_name == "tier": report.tier_works = test_state.get("tier", -1) == 1 and guest_snap
		elif not report.has("snap_on"):
			report.snap_on = test_state.get("snap", false) and guest_snap
			report.grid_visible = is_instance_valid(grid_label) and grid_label.visible and is_instance_valid(grid_panel) and grid_panel.visible
			report.preview_visible = is_instance_valid(ghost) and ghost.visible
			report.grid_text = grid_label.text if is_instance_valid(grid_label) else "missing"
			var before_frames = predicted_frames
			var before_position = ghost.global_position
			var saved_rotation = session.guest.camera.rotation
			session.guest.camera.rotation.y += 0.65
			await get_tree().create_timer(0.1).timeout
			report.local_preview_moves = ghost.global_position.distance_to(before_position) > 0.5 and predicted_frames > before_frames
			session.guest.camera.rotation = saved_rotation
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(folder + "guest-grid.png")
		else: report.snap_off = not test_state.get("snap", true) and not guest_snap
	report.passed = report.local_preview_moves and report.grid_visible and report.preview_visible and report.horizontal and report.all_controls and report.fits_width and report.distance_works and report.reset_works and report.tier_works and report.snap_on and report.snap_off
	var file = FileAccess.open(folder + "held-controls.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))
