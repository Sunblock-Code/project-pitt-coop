extends Node
# Mirror presentation only; progression, spawning and saves remain host-owned.
var session: Node
var sources: Array = []
var world_id = 0
var sounds: Dictionary = {}
var last_state: Dictionary = {}
var report: Dictionary = {}
var noise = FastNoiseLite.new()
var shake_intensity = 0.0
var shake_left = 0.0
var shake_time = 0.0
var finished_phase = 0
var shake_count = 0

func _ready():
	get_node("/root/GameProgression").phase_changed.connect(func(phase): finished_phase = phase)

func shake(intensity: float, duration: float):
	shake_count += 1
	shake_intensity = intensity * float(get_node("/root/MenuManager").settings.gameplay.screen_shake)
	shake_left = duration
	shake_time = 0.0

func _process(delta: float):
	if session.role != "guest" or not is_instance_valid(session.guest): return
	var camera = session.guest.render_camera
	if shake_left > 0.0:
		shake_left -= delta
		shake_time += delta
		camera.h_offset = noise.get_noise_2d(shake_time, 0) * shake_intensity
		camera.v_offset = noise.get_noise_2d(0, shake_time) * shake_intensity
		shake_intensity = maxf(shake_intensity - 0.5 * delta, 0)
	else:
		camera.h_offset = 0
		camera.v_offset = 0

func snapshot() -> Dictionary:
	var world = get_tree().current_scene
	if world_id != world.get_instance_id():
		world_id = world.get_instance_id()
		sources.clear()
		for node in world.find_children("*", "Node3D", true, false):
			if node.get_script() and node.get_script().resource_path.get_file() in ["hole.gd", "hole.gdc"]:
				for part in node.find_children("*", "Node3D", true, false):
					if part is CSGCylinder3D: sources.append([part, "radius"])
					if part is CollisionShape3D and part.get_parent() is StaticBody3D: sources.append([part, "transform"])
			if node is SpotLight3D and node.is_in_group("maw_light"): sources.append([node, "spot_angle"])
			if node.is_in_group("maw_visual"): sources.append([node, "transform"])
	var rows: Array = []
	for source in sources:
		if is_instance_valid(source[0]): rows.append([str(world.get_path_to(source[0])), source[1], source[0].get(source[1])])
	var audio: Array = []
	for root_name in ["GameProgression", "MusicManager"]:
		for player in get_node("/root/" + root_name).get_children():
			if player is AudioStreamPlayer and player.stream and player.playing:
				audio.append([str(player.get_instance_id()), player.stream.resource_path, player.bus, player.volume_db, player.pitch_scale])
	var pp = get_node("/root/PostProcessManager")
	var pixel_height = get_viewport().size.y * get_viewport().scaling_3d_scale
	if DisplayServer.get_name() == "headless" or get_viewport().size.y < 32: pixel_height = 360.0
	var pixels = {"height": pixel_height, "strength": pp.pixelation_strength, "dither": pp.dither_intensity, "colors": pp.color_levels}
	return {"phase": get_node("/root/GameProgression").current_phase, "rows": rows, "audio": audio, "psx": pp.psx_enabled, "pixels": pixels}

func sync_host():
	var state = snapshot()
	for peer in session.peers:
		if not session.peers[peer].ready: continue
		if session.peers[peer].get("phase_state", {}) != state:
			session._send(peer, ["phase_state", state])
			session.peers[peer].phase_state = state.duplicate(true)

func apply_state(state: Dictionary):
	if last_state.is_empty(): get_node("/root/MusicManager").player.stop()
	if state.has("psx") and (last_state.is_empty() or last_state.get("psx") != state.psx):
		get_node("/root/PostProcessManager").apply_psx_toggle(state.psx)
	if state.has("pixels") and is_instance_valid(session.guest_postfx):
		session.guest_postfx.match_host(state.pixels, state.psx)
	last_state = state
	get_node("/root/GameProgression").current_phase = state.phase
	var world = get_tree().current_scene
	for row in state.rows:
		var node = world.get_node_or_null(NodePath(row[0]))
		if node and node.get(row[1]) != row[2]: node.set(row[1], row[2])
	var active: Dictionary = {}
	for row in state.audio:
		active[row[0]] = true
		if not sounds.has(row[0]):
			var stream = load(row[1]) if not str(row[1]).is_empty() else null
			if not stream is AudioStream: continue
			var player = AudioStreamPlayer.new()
			player.stream = stream
			player.bus = row[2]
			add_child(player)
			player.volume_db = row[3]
			player.pitch_scale = row[4]
			player.play()
			sounds[row[0]] = player
		else:
			if sounds[row[0]].stream.resource_path != row[1]:
				sounds[row[0]].stream = load(row[1])
				sounds[row[0]].play()
			sounds[row[0]].volume_db = row[3]
			sounds[row[0]].pitch_scale = row[4]
	for key in sounds.keys():
		if not active.has(key):
			sounds[key].queue_free()
			sounds.erase(key)

func run_test():
	await get_tree().create_timer(27.0).timeout
	var progression = get_node("/root/GameProgression")
	progression.current_phase = 1
	get_tree().get_first_node_in_group("light1").show()
	progression.change_phase(2)
	await get_tree().create_timer(3.0).timeout
	_send_check("blackout")
	await get_tree().create_timer(12.0).timeout
	_send_check("message")
	await get_tree().create_timer(3.0).timeout
	for node in get_tree().current_scene.find_children("*", "Node3D", true, false):
		if "target_radius" in node:
			node.target_radius = 3.0
	await get_tree().create_timer(5.0).timeout
	_send_check("growth")
	var marker = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/late-ready.txt"), FileAccess.WRITE)
	if marker:
		marker.store_string("ready")
		marker.close()
	var peers_before = session.peers.keys()
	for attempt in range(200):
		await get_tree().create_timer(0.2).timeout
		for peer in session.peers:
			if peer not in peers_before and session.peers[peer].ready:
				await get_tree().create_timer(2.0).timeout
				_send_check("late")
				return

func _send_check(stage: String):
	var world = get_tree().current_scene
	var lights: Array = []
	for light in world.find_children("*", "Light3D", true, false):
		if light.is_in_group("room_lights") or light.is_in_group("maw_light") or light.get_parent().is_in_group("alarm_lights"):
			lights.append([str(world.get_path_to(light)), light.is_visible_in_tree(), light.light_color])
	var label = get_tree().get_first_node_in_group("HUD").get_node("DeathLabel")
	session._broadcast(["phase_check", stage, snapshot(), lights, label.text, label.visible, label.modulate.a])

func check_guest(msg: Array):
	var checks = {"phase": last_state.get("phase") == 2, "geometry": true, "lights": true, "audio": last_state.get("audio") == msg[2].audio}
	checks.geometry_present = msg[2].rows.size() >= 14
	checks.lights_present = not msg[3].is_empty()
	if msg[1] != "late": checks.shake = shake_count > 0
	if msg[1] == "message": checks.message_visible = msg[5] and msg[6] > 0.1 and not str(msg[4]).is_empty()
	var world = get_tree().current_scene
	for row in msg[2].rows:
		var node = world.get_node_or_null(NodePath(row[0]))
		if not node:
			checks.geometry = false
			print("[PHASE QA] missing geometry ", row[0])
		elif row[2] is float:
			if absf(node.get(row[1]) - row[2]) > 0.08:
				checks.geometry = false
				print("[PHASE QA] geometry ", row)
		elif row[2] is Transform3D:
			# Host growth continues between the 10 Hz state sample and this probe.
			var actual: Transform3D = node.get(row[1])
			if actual.origin.distance_to(row[2].origin) > 0.02 or not actual.basis.is_equal_approx(row[2].basis):
				checks.geometry = false
				print("[PHASE QA] transform ", row[0], " error=", actual.origin.distance_to(row[2].origin))
		if row[1] == "radius" and msg[1] in ["growth", "late"]: checks.enlarged = float(row[2]) > 2.5
	for row in msg[3]:
		var node = world.get_node_or_null(NodePath(row[0]))
		if not node or node.is_visible_in_tree() != row[1] or node.light_color != row[2]:
			checks.lights = false
			print("[PHASE QA] light ", row, " actual=", [node.is_visible_in_tree(), node.light_color] if node else [])
	var label = session.shared_labels.DeathLabel
	checks.text = label.text == msg[4] and label.visible == msg[5]
	checks.audio_players = sounds.size() == msg[2].audio.size()
	checks.passed = not checks.values().has(false)
	report[msg[1]] = checks
	if DisplayServer.get_name() != "headless":
		session.guest.set_physics_process(false)
		session.guest.global_position = Vector3(8, 4, 8)
		session.guest.camera.look_at(Vector3(0, 0, 0))
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/phase-" + msg[1] + ".png"))
		if msg[1] == "growth":
			session.guest.camera.look_at(Vector3(0, 94, 0))
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/phase-ceiling.png"))
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/phase-test.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))
