extends Node
## LAN co-op alpha. Host owns gameplay; guests receive script-free replicas.

const PROTOCOL = "pitt-coop-1.0.8-alpha67"
const Avatar = preload("res://coop/avatar.gd")
const CharacterMenu = preload("res://coop/character_menu.gd")
const ThirdPerson = preload("res://coop/third_person.gd")
const PORT = 27808
const MAX_GUESTS = 3
const TOOL_SCENES = ["fan", "fan2", "fan_3", "magnet", "magnet2", "piston", "piston2", "piston3", "cannon", "cannon2", "gravity_inverter", "spring_pad", "spring_pad2"]
var net: ENetMultiplayerPeer
var role = "offline"
var peers: Dictionary = {}
var bodies: Dictionary = {}
var replicas: Dictionary = {}
var avatars: Dictionary = {}
var known: Dictionary = {}
var held: Dictionary = {}
var guest_held_id = 0
var tool_equipped = false
var sticky_ready = false
var connection_health: Node
var transform_sent: Dictionary = {}
var fixture_sent: Dictionary = {}
var full_sync_at = 0
var machine_full_at = 0
var broom_players: Node
var status_test: Node
var crouch_test: Node
var broom_guest_test: Node
var scheduler_test: Node
var cash_test: Node
var slide_test: Node
var phase_sync: Node
var holding_colors: Node
var item_collision: Node
var trading_sync: Node
var tube_rescue: Node
var grab_settings: Node
var guest_settings: Node
var guest_terminal: Node
var progress_menu: Node
var emotes: Control
var press_corpses: Node
var corpse_test: Node
var fuse_sync: Node
var fuse_test: Node
var guest_postfx: Node
var panel_rack: Node
var duck_pass_test: Node
var magnets_test: Node
var remote_test: Node
var remote_tools: Node
var duck_pass: Node
var panel_highlights: Node
var held_controls: Node
var interaction_hud: Node
var host_player: Node3D
var guest: CharacterBody3D
var spawn_position = Vector3(0, 6, 18)
var tick = 0.0
var scan_tick = 0.0
var hud: CanvasLayer
var panel: PanelContainer
var status: Label
var address: LineEdit
var info: Label
var world_ready = false
var elapsed = 0.0
var test_mode = false
var test_action_sent = false
var test_id = 0
var received_states = 0
var allowed_scenes: Dictionary = {}
var fixtures: Array = []
var visual_mode = false
var test_grab_confirmed = false
var test_grab_count = 0
var test_drop_confirmed = false
var test_throw_confirmed = false
var world_instance = 0
var profile = Avatar.defaults()
var profile_path = "user://pitt_character.cfg"
var storage_id = ""
var profiles: Dictionary = {}
var character_editor: Control
var home_buttons: VBoxContainer
var local_body: Node3D
var local_avatar: Node3D
var view_rig: Node3D
var editor_body_mode = Node.PROCESS_MODE_INHERIT
var editor_body: Node
var character_test = false
var character_test_started = false
var character_test_toggle_count = 0
var entry_clock = 0.0
var lobby: PanelContainer
var lobby_roster: Label
var lobby_note: Label
var lobby_start: Button
var lobby_ready: Button
var lobby_is_ready = false
var lobby_starting = false
var lobby_test = false
var lobby_test_started = false
var elevator_waiting = false
var intro_released = false
var intro_node: Node3D
var spawn_yaw = 0.0
var pending_intro = false
var intro_local_time = 0.0
var lobby_members: Array = []
var guest_fade: ColorRect
var presentation_known: Dictionary = {}
var world_actions: Dictionary = {}
var shared_labels: Dictionary = {}
var guest_money: Label
var presentation_tick = 0.0
var shared_upgrades: Dictionary = {}
var seen_intro = false
var guest_notice: Label
var notice_until = 0
# Scene membership is tracked once; polling never recursively searches the world.
var indexed_bodies: Dictionary = {}
var active_control_bodies: Dictionary = {}
var topology_dirty = true
var presentation_sources: Array = []
var priority_presentation_sources: Array = []
var presentation_cursor = 0
var fixture_paths: Dictionary = {}
var motion_targets: Dictionary = {}
var part_motion: Dictionary = {}
var machine_clock_offset = INF
const MACHINE_BUFFER_SECONDS = 0.12
var machine_motion_sources: Array = []
var machine_motion_sent: Dictionary = {}
var qa_part_samples = 0
var qa_part_frames = 0
var qa_jitter_packets = 0
var craft_holds: Dictionary = {}
var craft_starts = 0
var craft_hud: Control
var host_interact_ray: RayCast3D
var perf_enabled = false
var perf_scopes: Dictionary = {}
var priority_tick = 0.0
var nearby_audio_sources: Array = []
var spatial_audio_sources: Array = []
var audio_cells: Dictionary = {}
var slow_fixtures: Array = []
var slow_fixture_cursor = 0
var spatial_tick = 0.0
var static_presentation_sources: Array = []
var static_index_world = 0
var perf_samples: Array = []
var perf_clock = 0.0

func _ready():
	var identity = ConfigFile.new()
	identity.load("user://pitt_player_identity.cfg")
	storage_id = str(identity.get_value("player", "storage_id", ""))
	if storage_id.length() != 32:
		storage_id = Crypto.new().generate_random_bytes(16).hex_encode()
		identity.set_value("player", "storage_id", storage_id)
		identity.save("user://pitt_player_identity.cfg")
	fuse_sync = load("res://coop/fuse_sync.gd").new()
	fuse_sync.session = self
	add_child(fuse_sync)
	if "--fuse-test" in OS.get_cmdline_user_args():
		fuse_test = load("res://coop/fuse_test.gd").new()
		fuse_test.session = self
		add_child(fuse_test)
	press_corpses = load("res://coop/press_corpses.gd").new()
	press_corpses.session = self
	add_child(press_corpses)
	allowed_scenes["res://coop/corpse.tscn"] = true
	if "--corpse-test" in OS.get_cmdline_user_args():
		corpse_test = load("res://coop/corpse_test.gd").new()
		corpse_test.session = self
		add_child(corpse_test)
	if "--magnets-test" in OS.get_cmdline_user_args():
		magnets_test = load("res://coop/magnets_test.gd").new()
		magnets_test.session = self
		add_child(magnets_test)
	if "--remote-test" in OS.get_cmdline_user_args():
		remote_test = load("res://coop/remote_test.gd").new()
		remote_test.session = self
		add_child(remote_test)
	remote_tools = load("res://coop/remote_tools.gd").new()
	remote_tools.session = self
	add_child(remote_tools)
	if "--log-menu-test" in OS.get_cmdline_user_args(): _test_log_menu.call_deferred()
	if "--duck-pass-test" in OS.get_cmdline_user_args():
		duck_pass_test = load("res://coop/duck_pass_test.gd").new()
		duck_pass_test.session = self
		add_child(duck_pass_test)
	duck_pass = load("res://coop/duck_pass.gd").new()
	duck_pass.session = self
	add_child(duck_pass)
	panel_highlights = load("res://coop/panel_highlights.gd").new()
	panel_highlights.session = self
	add_child(panel_highlights)
	if "--slide-test" in OS.get_cmdline_user_args():
		slide_test = load("res://coop/slide_test.gd").new()
		slide_test.session = self
		add_child(slide_test)
	if "--broom-guest-test" in OS.get_cmdline_user_args():
		broom_guest_test = load("res://coop/broom_guest_test.gd").new()
		broom_guest_test.session = self
		add_child(broom_guest_test)
	if "--scheduler-test" in OS.get_cmdline_user_args():
		scheduler_test = load("res://coop/scheduler_test.gd").new()
		scheduler_test.session = self
		add_child(scheduler_test)
	if "--cash-test" in OS.get_cmdline_user_args():
		cash_test = load("res://coop/cash_test.gd").new()
		cash_test.session = self
		add_child(cash_test)
	if "--crouch-test" in OS.get_cmdline_user_args():
		crouch_test = load("res://coop/crouch_test.gd").new()
		crouch_test.session = self
		add_child(crouch_test)
	phase_sync = load("res://coop/phase_sync.gd").new()
	phase_sync.session = self
	add_child(phase_sync)
	if "--status-test" in OS.get_cmdline_user_args():
		status_test = load("res://coop/status_test.gd").new()
		status_test.session = self
		add_child(status_test)
	connection_health = load("res://coop/connection_health.gd").new()
	var sticky_controls = load("res://coop/sticky_controls.gd").new()
	sticky_controls.name = "StickyControls"
	sticky_controls.session = self
	add_child(sticky_controls)
	connection_health.session = self
	add_child(connection_health)
	holding_colors = load("res://coop/holding_colors.gd").new()
	holding_colors.session = self
	add_child(holding_colors)
	item_collision = load("res://coop/item_collision.gd").new()
	item_collision.session = self
	add_child(item_collision)
	trading_sync = load("res://coop/trading_sync.gd").new()
	trading_sync.session = self
	add_child(trading_sync)
	tube_rescue = load("res://coop/tube_rescue.gd").new()
	tube_rescue.session = self
	add_child(tube_rescue)
	grab_settings = load("res://coop/grab_settings.gd").new()
	add_child(grab_settings)
	guest_settings = load("res://coop/guest_settings.gd").new()
	guest_settings.session = self
	add_child(guest_settings)
	progress_menu = load("res://coop/progress_menu.gd").new()
	progress_menu.session = self
	add_child(progress_menu)
	guest_terminal = load("res://coop/guest_terminal.gd").new()
	guest_terminal.session = self
	add_child(guest_terminal)
	panel_rack = load("res://coop/panel_rack.gd").new()
	panel_rack.session = self
	add_child(panel_rack)
	held_controls = load("res://coop/held_controls.gd").new()
	held_controls.session = self
	add_child(held_controls)
	broom_players = load("res://coop/broom_players.gd").new()
	broom_players.session = self
	add_child(broom_players)
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_track_node)
	get_tree().node_removed.connect(_untrack_node)
	for node in get_tree().root.find_children("*", "RigidBody3D", true, false):
		indexed_bodies[node.get_instance_id()] = node
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile-path="):
			profile_path = arg.trim_prefix("--profile-path=")
	_load_profile()
	_build_ui()
	_build_character_ui()
	_build_lobby()
	craft_hud = load("res://coop/craft_hud.gd").new()
	craft_hud.session = self
	hud.add_child(craft_hud)
	var directory = DirAccess.open("res://scenes")
	if directory:
		for file in directory.get_files():
			if file.ends_with(".tscn.remap"):
				allowed_scenes["res://scenes/" + file.trim_suffix(".remap")] = true
	print("[COOP] Loaded ", PROTOCOL)
	var args = OS.get_cmdline_user_args()
	perf_enabled = "--perf-test" in args
	test_mode = "--coop-test" in args
	visual_mode = "--coop-visual" in args
	character_test = "--character-test" in args
	lobby_test = "--lobby-test" in args
	if "--lobby-ui-test" in args: _lobby_ui_checks.call_deferred()
	for arg in args:
		if arg.begins_with("--coop-port="):
			# Local QA can use an alternate port without interrupting a live session.
			set_meta("test_port", clampi(int(arg.trim_prefix("--coop-port=")), 1024, 65535))
	if visual_mode:
		_force_test_window.call_deferred()
	if "--coop-host" in args:
		_start_host.call_deferred()
	for arg in args:
		if arg.begins_with("--coop-join="):
			address.text = arg.trim_prefix("--coop-join=")
			_start_guest.call_deferred()

func _force_test_window():
	await get_tree().create_timer(6.0).timeout
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1100, 800))
	DisplayServer.window_set_position(Vector2i(80, 100) if role == "host" else Vector2i(1250, 100))
	DisplayServer.window_set_title("P.I.T.T. CO-OP " + role.to_upper())

func _build_ui():
	hud = CanvasLayer.new()
	hud.layer = 120
	add_child(hud)
	emotes = load("res://coop/emote_wheel.gd").new()
	emotes.session = self
	hud.add_child(emotes)
	status = Label.new()
	status.text = "P.I.T.T. CO-OP 04 | F8: menu | F5: view"
	status.position = Vector2(18, 12)
	status.add_theme_font_size_override("font_size", 20)
	status.add_theme_color_override("font_shadow_color", Color.BLACK)
	status.add_theme_constant_override("shadow_offset_x", 2)
	status.add_theme_constant_override("shadow_offset_y", 2)
	hud.add_child(status)
	panel = PanelContainer.new()
	panel.position = Vector2(25, 55)
	panel.custom_minimum_size = Vector2(520, 0)
	hud.add_child(panel)
	var margin = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var title = Label.new()
	title.text = "P.I.T.T. / CO-OP ALPHA"
	title.add_theme_font_size_override("font_size", 28)
	box.add_child(title)
	info = Label.new()
	info.text = "Host a lobby and wait for friends to join.\nEveryone readies up, then the host starts New Game.\nUp to 4 players. Uses UDP port 27808.\nMod saves are separate from single-player."
	box.add_child(info)
	address = LineEdit.new()
	address.placeholder_text = "Host LAN IP (example: 192.168.1.10)"
	address.text = "127.0.0.1"
	box.add_child(address)
	for spec in [["Host co-op", _start_host], ["Join host", _start_guest], ["Character", _open_character], ["Progress / next unlocks", progress_menu.open], ["Open session log", _open_session_log], ["Turn all magnets OFF", _request_magnets_off], ["Unstick items inside spawn tube", tube_rescue.request], ["Close (F8)", _toggle_panel], ["Disconnect and quit", _quit_session]]:
		var button = Button.new()
		button.text = spec[0]
		button.pressed.connect(spec[1])
		box.add_child(button)
	guest_terminal.add_restriction_control(box)
	item_collision.add_controls(box)
	panel.hide()

func _input(event):
	if progress_menu.handle_input(event) or emotes.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.physical_keycode == KEY_M:
		duck_pass._input(event)
		return
	if role == "host" and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not panel.visible and not lobby.visible and not character_editor.visible:
		broom_players.sweep(1)
	if event is InputEventKey and event.pressed and not event.echo:
		if character_editor.visible:
			if event.physical_keycode in [KEY_ESCAPE, KEY_F8]:
				_close_character()
				get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_ESCAPE and (lobby.visible or panel.visible):
			lobby.hide()
			panel.hide()
			_update_menu_mouse()
			get_viewport().set_input_as_handled()
		elif role == "guest" and event.physical_keycode == KEY_ESCAPE and not guest_terminal.active():
			if not guest_settings.active():
				guest_settings.open()
				get_viewport().set_input_as_handled()
		elif guest_settings.active():
			return
		elif event.physical_keycode == KEY_F8:
			_toggle_panel()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_F5 and not panel.visible:
			_toggle_view()
			get_viewport().set_input_as_handled()

func _update_menu_mouse():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if progress_menu.active() or emotes.visible or guest_settings.active() or panel.visible or lobby.visible or character_editor.visible or guest_terminal.active() or not is_instance_valid(local_body) else Input.MOUSE_MODE_CAPTURED

func _hide_lobby():
	lobby.hide()
	_update_menu_mouse()

func _toggle_panel():
	guest_terminal.refresh_restriction_controls()
	item_collision.refresh()
	if lobby.visible:
		_hide_lobby()
	elif panel.visible:
		panel.hide()
		_update_menu_mouse()
	elif role in ["host", "waiting", "connecting"] and not world_ready and not is_instance_valid(local_body):
		_show_lobby()
	else:
		panel.show()
		_update_menu_mouse()

func _start_host():
	if role != "offline":
		return
	net = ENetMultiplayerPeer.new()
	var error = net.create_server(get_meta("test_port", PORT), MAX_GUESTS, 3)
	if error != OK:
		status.text = "Cannot host: " + error_string(error)
		return
	role = "host"
	guest_terminal.set_restricted(false)
	net.peer_connected.connect(_peer_connected)
	net.peer_disconnected.connect(_peer_disconnected)
	panel.hide()
	status.text = "HOST | Lobby open | UDP 27808"
	_show_lobby()
	_publish_lobby()
	print("[COOP] HOST listening ", get_meta("test_port", PORT))
	if (test_mode or visual_mode) and not lobby_test:
		_test_load_world.call_deferred()

func _test_load_world():
	await get_tree().create_timer(3.0).timeout
	get_tree().change_scene_to_file("res://scenes/world.tscn")

func _start_guest():
	if role != "offline":
		return
	net = ENetMultiplayerPeer.new()
	var error = net.create_client(address.text.strip_edges(), get_meta("test_port", PORT), 3)
	if error != OK:
		status.text = "Cannot join: " + error_string(error)
		return
	role = "connecting"
	_show_lobby()
	elapsed = 0.0
	panel.hide()
	status.text = "Connecting to " + address.text + "..."
	print("[COOP] CONNECTING ", address.text)

func _peer_connected(id):
	connection_health.configure(id)
	if lobby_starting and not intro_released:
		_send(id, ["error", "The crew is boarding. Try joining again after the elevator arrives."])
		return
	peers[id] = {"ready": false, "hello": false, "pose": Transform3D.IDENTITY, "camera": Transform3D.IDENTITY, "action_time": 0, "joined": Time.get_ticks_msec(), "pose_time": 0}
	known[id] = {}
	presentation_known[id] = {}
	print("[COOP] PEER connected ", id)

func _peer_disconnected(id):
	connection_health.record("peer_disconnected", id)
	_end_craft(id)
	_release(id, false)
	peers.erase(id)
	known.erase(id)
	presentation_known.erase(id)
	profiles.erase(id)
	_remove_avatar(id)
	_broadcast(["leave", id])
	_publish_lobby()
	print("[COOP] PEER disconnected ", id)

func _send(id: int, message: Array, reliable = true):
	if net == null or net.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	net.set_target_peer(id)
	net.transfer_channel = 0 if reliable else 1
	net.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	net.put_packet(var_to_bytes(message))

func _broadcast(message: Array, reliable = true):
	for id in peers:
		if peers[id].ready:
			_send(id, message, reliable)

func _process(delta):
	_smooth_motion(delta)
	_update_character(delta)
	_update_lobby()
	if is_instance_valid(guest_notice): guest_notice.visible = Time.get_ticks_msec() < notice_until
	if net == null:
		return
	elapsed += delta
	if test_mode and "--soak-test" in OS.get_cmdline_user_args() and role == "guest" and elapsed > 35.0 and elapsed < 43.0: return
	net.poll()
	if role == "connecting":
		if net.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			connection_health.configure(1)
			role = "waiting"
			_send(1, ["hello", PROTOCOL, profile, storage_id])
			status.text = "Connected. Waiting for the host's world..."
		elif elapsed > 12:
			_fail("Connection timed out. Check the IP and UDP port 27808.")
			return
	if role in ["waiting", "loading", "guest"] and net.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_fail("Host disconnected. Quit and relaunch to reconnect.")
		return
	var budget = 0
	while net.get_available_packet_count() > 0 and budget < 500:
		var sender = net.get_packet_peer()
		var packet = net.get_packet()
		budget += 1
		if packet.size() > 262144:
			continue
		var message = bytes_to_var(packet)
		if message is Array and message.size() > 0 and message[0] is String:
			_receive(sender, message)
	tick += delta
	scan_tick += delta
	presentation_tick += delta
	priority_tick += delta
	spatial_tick += delta
	if role == "host":
		var start_usec = Time.get_ticks_usec() if perf_enabled else 0
		_host_update(delta)
		if perf_enabled and world_ready:
			perf_samples.append(Time.get_ticks_usec() - start_usec)
			perf_clock += delta
			if perf_clock >= 10.0:
				perf_samples.sort()
				var total = 0.0
				for sample in perf_samples: total += sample
				print("[PERF] host_sync_us mean=", total / perf_samples.size(), " p99=", perf_samples[int(perf_samples.size() * 0.99)], " max=", perf_samples.back(), " bodies=", bodies.size())
				print("[PERF] scopes_us=", perf_scopes, " sources=", presentation_sources.size(), " priority=", priority_presentation_sources.size(), " motion=", machine_motion_sources.size())
				perf_scopes.clear()
				perf_samples.clear()
				perf_clock = 0.0
	elif role == "guest" and is_instance_valid(guest):
		if tick >= 0.05:
			tick = 0.0
			_send(1, ["pose", guest.global_transform, guest.camera.global_transform, _is_sliding(guest)], false)
		if test_mode and "--settings-test" not in OS.get_cmdline_user_args() and "--equip-test" not in OS.get_cmdline_user_args() and "--terminal-test" not in OS.get_cmdline_user_args() and "--sync-test" not in OS.get_cmdline_user_args() and not test_action_sent and test_id != 0 and replicas.has(test_id):
			test_action_sent = true
			_test_grab.call_deferred()
	if character_test and not character_test_started and is_instance_valid(local_body) and not elevator_waiting and not pending_intro:
		character_test_started = true
		_character_checks.call_deferred()
	if test_mode and elapsed > (180 if "--soak-test" in OS.get_cmdline_user_args() else 110 if "--sync-test" in OS.get_cmdline_user_args() or "--status-test" in OS.get_cmdline_user_args() or "--phase-test" in OS.get_cmdline_user_args() else 55) and not visual_mode:
		if "--soak-test" in OS.get_cmdline_user_args():
			var soak_file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/soak-" + role + ".json"), FileAccess.WRITE)
			if soak_file: soak_file.store_string(JSON.stringify({"seconds": elapsed, "connected": net.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, "states": received_states, "peers": peers.size()}))
		print("[COOP] TEST SUMMARY role=", role, " peers=", peers.size(), " replicas=", replicas.size(), " states=", received_states, " grabbed=", test_grab_confirmed, " threw=", test_throw_confirmed)
		get_tree().quit()

func _receive(sender: int, msg: Array):
	connection_health.last_received[sender] = Time.get_ticks_msec()
	if role == "host":
		if not peers.has(sender):
			return
		match msg[0]:
			"hello":
				if msg.size() != 4 or msg[1] != PROTOCOL or not msg[2] is Dictionary or not msg[3] is String or msg[3].length() != 32:
					_send(sender, ["error", "Mod versions do not match."])
					return
				for other in peers:
					if other != sender and peers[other].get("storage_id", "") == msg[3]:
						_send(sender, ["error", "This player profile is already connected."])
						return
				peers[sender].storage_id = msg[3]
				peers[sender].hello = true
				profiles[sender] = Avatar.sanitize(msg[2])
				_publish_lobby()
			"lobby_ready":
				if msg.size() == 2 and msg[1] is bool and peers[sender].hello and not lobby_starting:
					peers[sender].lobby_ready = msg[1]
					_publish_lobby()
			"profile":
				if msg.size() == 2 and msg[1] is Dictionary and peers[sender].hello:
					profiles[sender] = Avatar.sanitize(msg[1])
					_refresh_avatar_profile(sender)
					_broadcast_profiles()
			"ready":
				if peers[sender].hello and world_ready:
					peers[sender].ready = true
					holding_colors.publish(sender)
					_send(sender, ["item_collision", item_collision.guests_disabled])
					for arc_id in trading_sync.host_arcs: trading_sync.publish(sender,arc_id,trading_sync.host_arcs[arc_id])
					if peers[sender].get("invited_intro", false) and intro_released and is_instance_valid(intro_node):
						var intro_path = str(get_tree().current_scene.get_path_to(intro_node))
						_send(sender, ["elevator", "ride", intro_path])
						if intro_node.get("doors_open"): _send(sender, ["elevator", "open", intro_path])
					_broadcast_profiles()
					_send(sender, ["interaction_style", preload("res://coop/interaction_hud.gd").read_style(get_tree().current_scene)])
					print("[COOP] GUEST READY ", sender)
			"clear_spawn_tube":
				if msg.size() == 1 and peers[sender].ready: tube_rescue.clear_tube()
			"magnets_off":
				if msg.size() == 1 and peers[sender].ready: _turn_all_magnets_off()
			"duck_pass":
				if msg.size() == 2 and msg[1] is bool: peers[sender].duck_pass = msg[1]
			"pose":
				if msg.size() in [3, 4] and peers[sender].ready and msg[1] is Transform3D and msg[2] is Transform3D:
					var pose: Transform3D = msg[1]
					var camera: Transform3D = msg[2]
					if not pose.is_finite() or not camera.is_finite() or camera.origin.distance_to(pose.origin) > 3.0:
						return
					var now = Time.get_ticks_msec()
					var seconds = minf(float(now - peers[sender].pose_time) / 1000.0, 2.0)
					if peers[sender].pose_time > 0 and pose.origin.distance_to(peers[sender].pose.origin) > 45.0 * seconds + 3.0:
						return
					peers[sender].pose = pose
					peers[sender].camera = camera
					peers[sender].pose_time = now
					_avatar(sender, pose)
					avatars[sender].crouched = camera.origin.y - pose.origin.y < 1.2
					if msg.size() == 4 and msg[3] is bool: peers[sender].sliding = msg[3]
					avatars[sender].sliding = bool(peers[sender].get("sliding", false))
			"grab_qa_reset":
				if test_mode and "--settings-test" in OS.get_cmdline_user_args():
					var body = instance_from_id(test_id)
					body.global_position = Vector3(0,7,18)
					body.linear_velocity = Vector3.ZERO
					body.angular_velocity = Vector3.ZERO
					body.freeze = true
			"grab_mode_checks":
				if test_mode and "--settings-test" in OS.get_cmdline_user_args():
					var grab_test = load("res://coop/grab_mode_test.gd").new()
					grab_test.session = self
					add_child(grab_test)
					grab_test.host_checks()
					grab_test.queue_free()
			"qa_tap_check":
				if test_mode:
					var machine = world_actions.get(msg[1])
					var passed = machine != null and not machine.get("is_crafting") and not craft_holds.has(sender)
					var result = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/tap-test.json"), FileAccess.WRITE)
					if result: result.store_string(JSON.stringify({"passed": passed}))
			"emote_request":
				if msg.size() == 2 and msg[1] is int: emotes.request(sender, msg[1])
			"terminal_buy":
				if msg.size() == 3 and msg[1] is int and msg[2] is int: guest_terminal.buy(sender, msg[1], msg[2])
			"terminal_leave":
				guest_terminal.viewers.erase(sender)
			"held_control":
				if msg.size() == 2 and msg[1] is String: held_controls.command(sender, msg[1])
			"rotate_held":
				if msg.size() == 2 and msg[1] is Vector2 and msg[1].is_finite(): broom_players.rotate_held(sender, msg[1])
			"broom_sweep":
				if peers[sender].ready: broom_players.sweep(sender)
			"toggle_check":
				if test_mode and "--toggle-test" in OS.get_cmdline_user_args(): broom_players.record_toggle_check(sender, msg)
			"rack_checks":
				if test_mode and "--rack-test" in OS.get_cmdline_user_args(): panel_rack.run_host_checks(sender)
			"grab_release":
				if held.has(sender) and not broom_players.equipped(sender): _release(sender, false)
			"craft_stop":
				_end_craft(sender)
			"action":
				if msg.size() == 3 and msg[1] is String and (msg[2] is int or msg[2] is String):
					_action(sender, msg[1], msg[2])
	else:
		if sender != 1:
			return
		match msg[0]:
			"shared_scene":
				if msg.size() == 4 and role == "guest":
					_spawn_shared_scene(msg[1], msg[2], msg[3])
			"phase_state":
				if role == "guest": phase_sync.apply_state(msg[1])
			"slide_qa":
				if test_mode and is_instance_valid(slide_test): slide_test.receive(msg[1])
			"panel_outline_qa":
				if test_mode and "--panel-outline-test" in OS.get_cmdline_user_args(): panel_highlights.test_guest(msg[1])
			"duck_pass_qa":
				if test_mode and is_instance_valid(duck_pass_test): duck_pass_test.run_guest(msg)
			"broom_guest_qa":
				if test_mode and is_instance_valid(broom_guest_test): broom_guest_test.run_guest(msg)
			"scheduler_qa":
				if test_mode and is_instance_valid(scheduler_test): scheduler_test.run_guest(msg)
			"cash_qa":
				if test_mode and is_instance_valid(cash_test): cash_test.run_guest(msg)
			"cash_qa_stop":
				if test_mode and is_instance_valid(cash_test): cash_test.stop()
			"crouch_qa":
				if test_mode and is_instance_valid(crouch_test): crouch_test.receive(msg[1])
			"phase_shake":
				if role == "guest": phase_sync.shake(msg[1], msg[2])
			"phase_check":
				if test_mode and "--phase-test" in OS.get_cmdline_user_args(): phase_sync.check_guest(msg)
			"qa_control":
				if test_mode and "--sync-test" in OS.get_cmdline_user_args():
					_run_sync_guest_checks.call_deferred(msg[1], msg[2], msg[3])
			"craft_activity":
				if msg.size() == 3 and role == "guest": craft_hud.set_activity(msg[1], float(msg[2]))
			"emote_qa", "emote_gallery":
				if test_mode and "--emotes-test" in OS.get_cmdline_user_args():
					var check = get_node_or_null("EmoteQA")
					if check == null:
						check = load("res://coop/emote_test.gd").new()
						check.name = "EmoteQA"
						check.session = self
						add_child(check)
					if msg[0] == "emote_qa": check.receive(msg[1])
					else: check.gallery()
			"float_qa":
				if test_mode and "--float-test" in OS.get_cmdline_user_args():
					var check = load("res://coop/float_test.gd").new()
					check.session = self
					add_child(check)
					check.guest_check(msg[1],msg[2])
			"collision_qa":
				if test_mode and "--collision-test" in OS.get_cmdline_user_args():
					var check = load("res://coop/collision_test.gd").new()
					check.session = self
					add_child(check)
					check.guest_run()
			"holding_qa":
				if test_mode and "--holding-test" in OS.get_cmdline_user_args():
					var check = load("res://coop/holding_test.gd").new()
					check.session = self
					add_child(check)
					check.guest_check(msg[1],msg[2])
			"holding_colors":
				if msg.size() == 2 and msg[1] is Dictionary: holding_colors.owners = msg[1]
			"item_collision":
				if msg.size() == 2 and msg[1] is bool: item_collision.receive(msg[1])
			"trading_arc":
				if msg.size() == 3 and msg[1] is int and msg[2] is Dictionary: trading_sync.receive(msg[1],msg[2])
			"machine_motion":
				if msg.size() == 2 and role == "guest":
					if test_mode and "--jitter-test" in OS.get_cmdline_user_args():
						var delay = [0.0, 0.08, 0.02, 0.06][qa_jitter_packets % 4]
						qa_jitter_packets += 1
						get_tree().create_timer(delay).timeout.connect(_apply_presentation.bind(msg[1]))
					else:
						_apply_presentation(msg[1])
			"presentation":
				if msg.size() == 2 and role == "guest":
					_apply_presentation(msg[1])
			"upgrades":
				if msg.size() == 2 and msg[1] is Dictionary:
					shared_upgrades = msg[1].duplicate(true)
					var state = get_node("/root/GameState")
					for key in shared_upgrades:
						if state.upgrades.has(key):
							state.upgrades[key].level = shared_upgrades[key][0]
							state.upgrades[key].enabled = shared_upgrades[key][1]
			"lobby":
				if msg.size() == 3 and msg[1] is Array and msg[1].size() <= 4 and msg[2] is bool:
					lobby_members = msg[1]
					lobby_starting = msg[2]
					_render_lobby()
			"elevator":
				if msg.size() == 3 and role == "guest":
					_guest_elevator_event(msg[1], msg[2])
			"profiles":
				if msg.size() == 2 and msg[1] is Dictionary and msg[1].size() <= MAX_GUESTS + 1:
					for id in msg[1]:
						if id is int and msg[1][id] is Dictionary:
							profiles[id] = Avatar.sanitize(msg[1][id])
							_refresh_avatar_profile(id)
			"world":
				if msg.size() == 5 and role == "waiting":
					spawn_yaw = msg[3]
					pending_intro = msg[4]
					lobby.visible = pending_intro
					spawn_position = msg[1]
					test_id = msg[2]
					role = "loading"
					_build_guest_world.call_deferred()
			"held_test":
				if test_mode and msg.size() == 2 and msg[1] is Dictionary: held_controls.test_state = msg[1]
			"qa_terminal":
				if test_mode and msg.size() == 3: guest_terminal.run_guest_checks(msg[1], msg[2])
			"progress_state":
				if msg.size() == 2 and msg[1] is Dictionary: progress_menu.receive(msg[1])
			"emote_play":
				if msg.size() == 3 and msg[1] is int and msg[2] is int: emotes.play(msg[1], msg[2])
			"terminal_open":
				guest_terminal.accept_catalog = true
			"terminal_catalog":
				if msg.size() == 6 and msg[1] is int and msg[2] is Array and msg[3] is String and msg[4] is bool and msg[5] is Array: guest_terminal.receive(msg[1], msg[2], msg[3], msg[4], msg[5])
			"terminal_result":
				if msg.size() == 2 and msg[1] is String and guest_terminal.active(): guest_terminal.message.text = msg[1]
			"terminal_close":
				guest_terminal.close(false)
			"snap_preview":
				if msg.size() == 5 and msg[1] is int and msg[2] is Vector3 and msg[3] is Basis and msg[4] is bool: held_controls.preview = msg.slice(1)
			"rack_state":
				panel_rack.count = int(msg[1])
				panel_rack.capacity = int(msg[2])
			"held_mode":
				if msg.size() == 4 and msg[1] is bool and msg[2] is int:
					held_controls.local_distance = float(msg[3])
					held_controls.guest_snap = msg[1]
					held_controls.guest_tier = msg[2]
			"sticky_ready":
				if msg.size() == 2 and msg[1] is bool: sticky_ready = msg[1]
			"status_check":
				if test_mode and is_instance_valid(status_test): status_test.check_guest(msg)
			"toggle_test_target":
				if test_mode and "--toggle-test" in OS.get_cmdline_user_args(): broom_players.run_toggle_guest(msg[1])
			"equip_test_target":
				if test_mode and "--equip-test" in OS.get_cmdline_user_args(): broom_players.run_equip_guest_checks(msg[1], msg[2])
			"trading_qa":
				if test_mode and "--trading-test" in OS.get_cmdline_user_args():
					var check = load("res://coop/trading_test.gd").new()
					check.session = self
					add_child(check)
					check.guest_check(msg[1],msg[2],msg[3])
			"tube_qa":
				if test_mode and "--tube-test" in OS.get_cmdline_user_args():
					var tube_test = load("res://coop/tube_test.gd").new()
					tube_test.session = self
					add_child(tube_test)
					tube_test.guest_check(msg[1],msg[2])
			"magnets_qa":
				if test_mode and is_instance_valid(magnets_test): magnets_test.run_guest(msg[1])
			"remote_qa":
				if test_mode and is_instance_valid(remote_test): remote_test.run_guest(msg)
			"remote_state":
				if msg.size() == 2 and msg[1] is Array: remote_tools.receive(msg[1])
			"equipped_pose":
				if msg.size() == 2 and msg[1] is Transform3D: broom_players.guest_pose = msg[1]
			"tool_equipped":
				if msg.size() == 2 and msg[1] is bool:
					var was_equipped = tool_equipped
					tool_equipped = msg[1]
					if was_equipped and not tool_equipped and not guest.craft_pressed and grab_settings.hold_to_grab: _send(1, ["grab_release"])
					if replicas.has(guest_held_id): replicas[guest_held_id].collision_layer = 0 if tool_equipped else 2
			"broom_push":
				if msg.size() == 5 and msg[1] is int and msg[2] is Vector3 and (msg[3] is float or msg[3] is int) and (msg[4] is float or msg[4] is int): broom_players.receive(msg[1], msg[2], msg[3], msg[4])
			"broom_sweep_fx":
				if msg.size() == 3 and msg[1] is int and msg[2] is int: broom_players.sweep_fx(msg[1], msg[2])
			"interaction_style":
				if msg.size() == 2 and msg[1] is Dictionary and is_instance_valid(interaction_hud): interaction_hud.apply_style(msg[1])
			"held_item":
				if msg.size() == 2 and msg[1] is int:
					guest_held_id = msg[1]
					item_collision.update_held()
			"spawn":
				if msg.size() in [5, 6] and role == "guest":
					_spawn_replica(msg[1], msg[2], msg[3], msg[4], msg[5] if msg.size() == 6 else {})
			"press_respawn":
				if msg.size() == 2 and msg[1] is Vector3: press_corpses.respawn_guest(msg[1])
			"fuse_state":
				if msg.size() == 2 and msg[1] is Array: fuse_sync.receive(msg[1])
			"fuse_qa":
				if test_mode and is_instance_valid(fuse_test): fuse_test.guest_check(msg)
			"corpse_qa":
				if test_mode and is_instance_valid(corpse_test): corpse_test.guest_check(msg)
			"remove":
				if msg.size() == 2:
					for id in msg[1]:
						trading_sync.arcs.erase(id)
						if replicas.has(id):
							replicas[id].queue_free()
							replicas.erase(id)
			"state":
				if msg.size() == 2:
					received_states += 1
					for row in msg[1]:
						if replicas.has(row[0]):
							_queue_motion(replicas[row[0]], row[1])
			"fixtures":
				if msg.size() == 2 and role == "guest":
					for row in msg[1]:
						var fixture = get_tree().current_scene.get_node_or_null(NodePath(row[0]))
						if fixture is Node3D:
							_queue_motion(fixture, row[1])
							fixture.visible = row[2]
			"players":
				if msg.size() == 6:
					for id in msg[1]:
						if id != net.get_unique_id():
							_avatar(id, msg[1][id])
							avatars[id].crouched = bool(msg[4].get(id, false))
							avatars[id].sliding = bool(msg[5].get(id, false))
					status.text = "CO-OP | Players: %d | F8: menu | F5: view" % msg[1].size()
					if is_instance_valid(guest_money):
						guest_money.text = str(msg[3])
						guest_money.show()
			"leave":
				if msg.size() == 2:
					_remove_avatar(msg[1])
			"notice":
				if msg.size() == 2:
					info.text = msg[1]
					var routine = msg[1] in ["Grabbed shared object.", "Dropped shared object.", "Threw shared object."] or str(msg[1]).begins_with("Activated ")
					if is_instance_valid(guest_notice) and not routine:
						guest_notice.text = str(msg[1])
						notice_until = Time.get_ticks_msec() + 3500
					if msg[1] == "Grabbed shared object.": test_grab_count += 1
					test_drop_confirmed = test_drop_confirmed or msg[1] == "Dropped shared object."
					test_grab_confirmed = test_grab_confirmed or msg[1] == "Grabbed shared object."
					test_throw_confirmed = test_throw_confirmed or msg[1] == "Threw shared object."
					print("[COOP] ", msg[1])
			"error":
				_fail(str(msg[1]))

func _host_update(delta):
	if world_ready and (not is_instance_valid(host_player) or get_tree().current_scene == null or get_tree().current_scene.get_instance_id() != world_instance):
		_broadcast(["error", "Host left or reloaded the world. Relaunch to join again."])
		world_ready = false
		bodies.clear()
		for id in peers.keys():
			net.disconnect_peer(id)
		return
	if not is_instance_valid(host_player):
		host_player = get_tree().get_first_node_in_group("player")
		if host_player == null:
			for node in get_tree().root.find_children("*", "CharacterBody3D", true, false):
				if not is_ancestor_of(node):
					host_player = node
					break
		if host_player != null:
			world_ready = true
			world_instance = get_tree().current_scene.get_instance_id()
			print("[COOP] HOST WORLD READY ", host_player.get_path())
			if test_mode:
				_make_test_body()
	if not world_ready or not is_instance_valid(host_player):
		return
	for id in peers:
		if peers[id].hello and not peers[id].has("invited"):
			peers[id].invited = true
			var arrival = _guest_spawn(id)
			peers[id].pose = Transform3D(Basis(Vector3.UP, host_player.global_rotation.y), arrival)
			peers[id].invited_intro = elevator_waiting and not intro_released
			_send(id, ["world", arrival, test_id, host_player.global_rotation.y, peers[id].invited_intro])
	_update_craft_holds()
	for id in held.keys():
		var body = instance_from_id(held[id].id)
		if not is_instance_valid(body) or not peers.has(id):
			held.erase(id)
			continue
		var can_stick = _can_stick(body)
		if held[id].get("sticky_ready", null) != can_stick:
			held[id].sticky_ready = can_stick
			_send(id, ["sticky_ready", can_stick])
		var cam: Transform3D = peers[id].camera
		var target = cam.origin - cam.basis.z * held[id].get("distance", 2.5)
		if held[id].get("equipped", false):
			if is_instance_valid(held[id].get("anchor")): held[id].anchor.global_transform = cam
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
			continue
		target = held_controls.target(id, body, target)
		body.linear_velocity = ((target - body.global_position) * 12.0).limit_length(25.0)
		body.angular_velocity *= maxf(0, 1 - delta * 8)
		body.sleeping = false
	var has_ready_peer = false
	for id in peers:
		if peers[id].ready:
			has_ready_peer = true
			break
	if not has_ready_peer:
		_publish_craft_activity()
		return
	if scan_tick >= 0.5:
		scan_tick = 0.0
		_scan_bodies()
	if presentation_tick >= 0.1 or presentation_cursor > 0:
		if presentation_cursor == 0: presentation_tick = 0.0
		_sync_presentation()
	if tick < 0.05:
		return
	tick = 0.0
	_publish_craft_activity()
	_sync_machine_motion()
	var transforms = {1: _body_visual_pose(host_player)}
	var crouches = {1: _is_crouched(host_player)}
	var slides = {1: _is_sliding(host_player)}
	for id in peers:
		if peers[id].ready:
			transforms[id] = peers[id].pose
			crouches[id] = peers[id].camera.origin.y - peers[id].pose.origin.y < 1.2
			slides[id] = bool(peers[id].get("sliding", false))
	var money = str(get_node("/root/GameState").money.to_plain_string())
	var game_hud = get_tree().get_first_node_in_group("HUD")
	var money_label = game_hud.get_node_or_null("Money") if game_hud else null
	var money_text = money_label.text if money_label is Label else money + "$"
	_broadcast(["players", transforms, money, money_text, crouches, slides], false)
	status.text = "HOST | Players: %d / 4 | F8: menu | F5: view" % transforms.size()
	var batch: Array = []
	var full_sync = Time.get_ticks_msec() >= full_sync_at
	if full_sync: full_sync_at = Time.get_ticks_msec() + 1000
	for stale in transform_sent.keys():
		if not bodies.has(stale): transform_sent.erase(stale)
	for id in bodies:
		var body = instance_from_id(id)
		if is_instance_valid(body) and body.is_inside_tree():
			# Spread stationary-body refreshes across the second instead of
			# resending the whole duck pile in one host frame.
			if id % 20 == (Time.get_ticks_msec() / 50) % 20 or transform_sent.get(id) != body.global_transform:
				transform_sent[id] = body.global_transform
				batch.append([id, body.global_transform])
		if batch.size() == 8:
			_broadcast(["state", batch], false)
			batch = []
	if not batch.is_empty():
		_broadcast(["state", batch], false)
	batch = []
	# Mine blocks never animate their transforms. Refresh a bounded portion
	# alongside moving fixtures instead of querying the whole mine at 20 Hz.
	var slow_end = mini(slow_fixture_cursor + 32, slow_fixtures.size())
	var fixture_slice = fixtures + slow_fixtures.slice(slow_fixture_cursor, slow_end)
	slow_fixture_cursor = 0 if slow_end == slow_fixtures.size() else slow_end
	for fixture in fixture_slice:
		if is_instance_valid(fixture) and fixture.is_inside_tree():
			var row = [fixture_paths[fixture.get_instance_id()], fixture.global_transform, fixture.visible]
			if full_sync or fixture_sent.get(row[0]) != row:
				fixture_sent[row[0]] = row
				batch.append(row)
		if batch.size() == 8:
			_broadcast(["fixtures", batch], false)
			batch = []
	if not batch.is_empty():
		_broadcast(["fixtures", batch], false)

func _dynamic_branch(node: Node) -> bool:
	var ancestor = node
	while ancestor != null:
		if ancestor is RigidBody3D or ancestor == self or ancestor == host_player: return true
		ancestor = ancestor.get_parent()
	return false

func _track_node(node: Node):
	if node is RigidBody3D:
		indexed_bodies[node.get_instance_id()] = node
	if node is Node3D and not _dynamic_branch(node):
		topology_dirty = true

func _untrack_node(node: Node):
	indexed_bodies.erase(node.get_instance_id())
	if node is Node3D and not _dynamic_branch(node):
		topology_dirty = true

func _rebuild_sync_index():
	var scope_start = Time.get_ticks_usec() if perf_enabled else 0
	var world = get_tree().current_scene
	var rebuild_static = topology_dirty or static_index_world != world.get_instance_id()
	topology_dirty = false
	presentation_sources = []
	machine_motion_sources.clear()
	machine_motion_sent.clear()
	presentation_cursor = 0
	if rebuild_static:
		static_index_world = world.get_instance_id()
		world_actions.clear()
		fixtures.clear()
		slow_fixtures.clear()
		slow_fixture_cursor = 0
		fixture_paths.clear()
		var visibility_sources: Dictionary = {}
		# One traversal when scene membership changes, instead of ten per second.
		for node in world.find_children("*", "Node3D", true, false):
			if node == host_player or host_player.is_ancestor_of(node): continue
			# Dynamic bodies are replicated by ID below. Their pooled descendants
			# have no corresponding static guest path and must not enter this index.
			var ancestor: Node = node
			var dynamic = false
			while ancestor != null and ancestor != world:
				if ancestor is RigidBody3D:
					dynamic = true
					break
				ancestor = ancestor.get_parent()
			if dynamic: continue
			var path = str(world.get_path_to(node))
			if _is_control(node): world_actions[path] = node
			if not node is RigidBody3D and (node.get_script() != null or (is_instance_valid(intro_node) and intro_node.is_ancestor_of(node))):
				if node.is_in_group("minable"): slow_fixtures.append(node)
				else: fixtures.append(node)
				fixture_paths[node.get_instance_id()] = path
			if node is Light3D or node is AudioStreamPlayer3D:
				var parent = node.get_parent()
				while parent is Node3D and parent != world:
					visibility_sources[str(world.get_path_to(parent))] = parent
					parent = parent.get_parent()
				presentation_sources.append([path, "light" if node is Light3D else "audio", node])
		for path in visibility_sources:
			presentation_sources.append([path, "visible", visibility_sources[path]])
		static_presentation_sources = presentation_sources.duplicate()
	else:
		presentation_sources = static_presentation_sources.duplicate()
	var control_roots: Dictionary = {}
	for root in world_actions.values(): control_roots[root.get_instance_id()] = root
	for root in world.get_children():
		if root is Node3D and _is_machine_scene(root): control_roots[root.get_instance_id()] = root
	for group in ["vertical_gate", "gate_shutters"]:
		for gate in get_tree().get_nodes_in_group(group): control_roots[gate.get_instance_id()] = gate
	# Purchased/pool objects and equipped tools may live outside World.
	for id in indexed_bodies:
		var body = indexed_bodies[id]
		if is_instance_valid(body) and body.is_inside_tree() and body.is_visible_in_tree(): control_roots[id] = body
	for root in control_roots.values():
		var machine_root = _is_machine_scene(root)
		var root_path = "@" + str(root.get_instance_id()) + "/." if root is RigidBody3D else str(world.get_path_to(root))
		if _is_control(root) and root.has_method("object_name"): presentation_sources.append([root_path, "tool", root])
		for part in root.find_children("*", "Node3D", true, false):
			if not machine_root and not root.is_in_group("vertical_gate") and not root.is_in_group("gate_shutters") and not (part is Light3D or part is AudioStreamPlayer3D or part is GPUParticles3D): continue
			var path = "@" + str(root.get_instance_id()) + "/" + str(root.get_path_to(part)) if root is RigidBody3D else str(world.get_path_to(part))
			var kind = "light" if part is Light3D else "audio" if part is AudioStreamPlayer3D else "label3d" if part is Label3D else "particles" if part is GPUParticles3D else "part"
			presentation_sources.append([path, kind, part])
			if kind == "part" and not part is CollisionShape3D:
				machine_motion_sources.append([path, root, part])

	# A nested control and its parent can both describe the same part.
	# Keep one authoritative descriptor per path, as the old state map did.
	var unique_sources: Dictionary = {}
	for source in presentation_sources:
		if source[1] == "visible" and (source[2] is Light3D or source[2] is AudioStreamPlayer3D): continue
		unique_sources[source[0]] = source
	presentation_sources = unique_sources.values()
	# Thousands of mining-block sounds and visibility nodes used to run in
	# every priority pass. Keep their background refresh bounded; nearby
	# sounds get the fast path and visibility changes are queued immediately.
	spatial_audio_sources = presentation_sources.filter(func(source): return source[1] == "audio" and str(source[0]).begins_with("MiningRoom/"))
	priority_presentation_sources = presentation_sources.filter(func(source): return not str(source[0]).begins_with("MiningRoom/") and not (source[1] == "audio" and source[2].get_parent().has_method("_sleep_changed")) and (source[1] in ["tool", "audio", "light", "visible", "label3d"] or source[2].name in ["WindEffectMesh", "MagnetEffect"]))
	for source in presentation_sources:
		if source[1] == "visible":
			var callback = _visibility_changed.bind(source)
			if not source[2].visibility_changed.is_connected(callback): source[2].visibility_changed.connect(callback)
	audio_cells.clear()
	for source in spatial_audio_sources:
		var cell = Vector3i((source[2].global_position / 40.0).floor())
		if not audio_cells.has(cell): audio_cells[cell] = []
		audio_cells[cell].append(source)
	spatial_tick = 1.0
	if perf_enabled: perf_scopes["_rebuild_sync_index"] = perf_scopes.get("_rebuild_sync_index", 0) + Time.get_ticks_usec() - scope_start


func _visibility_changed(source: Array):
	if not is_instance_valid(source[2]): return
	_broadcast(["presentation", [[source[0], "visible", [source[2].visible]]]])
	for peer in presentation_known: presentation_known[peer].erase(source[0])

func publish_body_audio(body: Node3D, player: AudioStreamPlayer3D):
	# Impact events avoid polling every silent duck sound ten times a second.
	var id = body.get_instance_id()
	var path = "@" + str(id) + "/" + str(body.get_path_to(player))
	var values = [player.visible, true, player.volume_db, player.pitch_scale]
	for peer in peers:
		if not peers[peer].ready or not known.get(peer, {}).has(id): continue
		presentation_known[peer][path] = [path, "audio", values.duplicate()]
		_send(peer, ["presentation", [[path, "audio", values + [player.get_playback_position()]]]])

func _refresh_nearby_audio():
	nearby_audio_sources.clear()
	var listeners: Array = [host_player.global_position]
	for peer in peers:
		if peers[peer].ready: listeners.append(peers[peer].pose.origin)
	var visited: Dictionary = {}
	for position in listeners:
		var center = Vector3i((position / 40.0).floor())
		for x in range(-1, 2):
			for y in range(-1, 2):
				for z in range(-1, 2):
					for source in audio_cells.get(center + Vector3i(x, y, z), []):
						if visited.has(source[0]) or not is_instance_valid(source[2]): continue
						if source[2].global_position.distance_squared_to(position) <= 1600.0:
							visited[source[0]] = true
							nearby_audio_sources.append(source)


func _scan_bodies():
	var scope_start = Time.get_ticks_usec() if perf_enabled else 0
	var current: Dictionary = {}
	var controls_current: Dictionary = {}
	for id in indexed_bodies:
		var body = indexed_bodies[id]
		if not is_instance_valid(body) or not body.is_inside_tree() or not body.is_visible_in_tree() or body.scene_file_path.is_empty() or is_ancestor_of(body):
			continue
		current[id] = body.scene_file_path
		item_collision.track(body)
		panel_highlights.track(body)
		duck_pass.track(body)
		remote_tools.track(body)
		if _is_control(body): controls_current[id] = true
	if topology_dirty or current != bodies or controls_current != active_control_bodies: _rebuild_sync_index()
	active_control_bodies = controls_current
	bodies = current
	for peer in peers:
		if not peers[peer].ready:
			continue
		_send_shared_scenes(peer)
		var removed: Array = []
		for id in known[peer]:
			if not current.has(id):
				removed.append(id)
		if not removed.is_empty():
			_send(peer, ["remove", removed])
			for id in removed:
				known[peer].erase(id)
			var removed_ids = {}
			for id in removed: removed_ids[id] = true
			# Clear recycled-body presentation once per removal batch, rather
			# than scanning the entire warehouse for every newly spawned duck.
			for path in presentation_known.get(peer, {}).keys():
				if str(path).begins_with("@") and removed_ids.has(int(str(path).get_slice("/", 0).trim_prefix("@"))):
					presentation_known[peer].erase(path)
		for id in current:
			if not known[peer].has(id):
				var body = instance_from_id(id)
				_send(peer, ["spawn", id, current[id], body.global_transform, body.collision_layer, body.get_meta("corpse_profile", {})])
				known[peer][id] = true
	if perf_enabled: perf_scopes["_scan_bodies"] = perf_scopes.get("_scan_bodies", 0) + Time.get_ticks_usec() - scope_start


func _build_guest_world():
	# Stop local simulation, autosaves and game input before creating any replicas.
	get_tree().paused = false
	for node in get_tree().root.get_children():
		if node != self:
			node.process_mode = Node.PROCESS_MODE_DISABLED
	# The loading screen can leave the adaptive performance monitor at 30 Hz.
	# Guests disable that monitor along with host simulation, so restore 60 Hz.
	Engine.physics_ticks_per_second = 60
	get_node("/root/SaveManager").save_locked = true
	get_node("/root/SaveManager").autosave_enabled = false
	var old = get_tree().current_scene
	if old:
		get_tree().root.remove_child(old)
		old.queue_free()
	var world = load("res://scenes/world.tscn").instantiate()
	var original_player = world.find_child("PlayerController", true, false)
	var footstep_source = original_player.get_node_or_null("FootstepAudio3D") if original_player else null
	var footstep_stream = footstep_source.stream if footstep_source else null
	var footstep_bus = footstep_source.bus if footstep_source else &"Master"
	var surface_streams = original_player.get("surface_footsteps").duplicate() if original_player else {}
	for surface_node in world.find_children("*", "CollisionObject3D", true, false):
		for surface_group in surface_streams:
			if surface_node.is_in_group(surface_group):
				surface_node.set_meta("coop_footstep_surface", surface_group)
				break
	var postfx = load("res://coop/guest_postfx.gd").new()
	guest_postfx = postfx
	postfx.session = self
	postfx.copy_effects(world)
	_copy_shared_labels(world)
	held_controls.copy_grid_ui(world)
	guest_terminal.copy_native_ui(world)
	var interaction = load("res://coop/interaction_hud.gd").new()
	interaction_hud = interaction
	interaction.session = self
	interaction.copy_labels(world)
	add_child(interaction)
	for node in world.find_children("*", "Node3D", true, false):
		if _is_control(node):
			node.set_meta("coop_control", str(world.get_path_to(node)))
	_strip(world, true)
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	guest = load("res://coop/guest.gd").new()
	guest.session = self
	guest.footstep_stream = footstep_stream
	guest.footstep_bus = footstep_bus
	guest.surface_streams = surface_streams
	guest.name = "GuestPlayer"
	add_child(guest)
	guest.global_position = spawn_position
	guest.rotation.y = spawn_yaw
	add_child(postfx)
	guest.set_physics_process(not pending_intro)
	if pending_intro:
		guest_fade = ColorRect.new()
		guest_fade.color = Color.BLACK
		guest_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		guest_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(guest_fade)
		hud.move_child(guest_fade, 0)
	role = "guest"
	guest_settings.initialize()
	if test_mode and "--load-test" in OS.get_cmdline_user_args(): _guest_load_check.call_deferred()
	_send(1, ["ready"])
	info.text = "Guest controls: WASD / mouse / Space / Shift\nHold LMB: carry / release: drop | RMB: throw\nE: equip fan/broom | F: interact | F8: menu\nTerminal purchases and upgrades are shared. Host saves."
	print("[COOP] GUEST WORLD READY")

func _strip(node: Node, static_world = false):
	if node.is_in_group("fuse"): node.set_meta("coop_fuse", true)
	var snap_placable = node.is_in_group("placable")
	# Replicas wait for the reliable host visibility snapshot before showing wind.
	if node.name == "WindEffectMesh" and node is Node3D: node.hide()
	if broom_players.is_broom(node): node.set_meta("coop_broom", true)
	if broom_players.can_equip(node): node.set_meta("coop_equipable", true)
	if node.has_method("scroll_tune_up"): node.set_meta("coop_tunable", true)
	if node.has_method("interact") and node is RigidBody3D: node.set_meta("coop_interact_tool", true)
	if node.is_in_group("product"): node.set_meta("coop_snap_product", true)
	if node.is_in_group("slick_merge_body"): node.set_meta("coop_snap_merged", true)
	if "pool_id" in node: node.set_meta("coop_pool_id", node.get("pool_id"))
	preload("res://coop/interaction_hud.gd").preserve_outlines(node)
	if node.has_method("object_name"):
		node.set_meta("coop_title", str(node.call("object_name")))
		node.set_meta("coop_grabbable", node.is_in_group("draggable"))
		node.set_meta("coop_placeable", node.has_method("place"))
		node.set_meta("coop_manual", node.is_in_group("workbench"))
		node.set_meta("coop_toggle", node.is_in_group("automated_workbench"))
		node.set_meta("coop_usable", _is_control(node))
	if node is Node3D and (node.has_meta("coop_outline") or str(node.name).to_lower().begins_with("outline")):
		node.set_meta("coop_outline", true)
		node.hide()
		if node is MeshInstance3D and node.material_override:
			node.material_override = node.material_override.duplicate()
			if node.material_override is StandardMaterial3D: node.material_override.albedo_color = Color.WHITE
	for group in node.get_groups():
		node.remove_from_group(group)
	if snap_placable: node.add_to_group("coop_snap_placable")
	for child in node.get_children():
		if child is SubViewport and remote_tools.is_remote(node):
			remote_tools.preserve_screen(child)
			continue
		if child is GPUParticles3D:
			child.set_script(null)
			child.emitting = false
			continue
		if child is AudioStreamPlayer3D:
			child.set_script(null)
			child.autoplay = false
			child.stop()
			continue
		if (static_world and (child is RigidBody3D or child is CharacterBody3D)) or child is CanvasLayer or child is Control or child is Camera3D or child is AudioStreamPlayer or child is AudioStreamPlayer3D or child is Timer or child is AnimationPlayer or child is GPUParticles3D:
			node.remove_child(child)
			child.free()
		else:
			_strip(child, static_world)
	# Child labels can call their parent terminal while preserving metadata.
	node.set_script(null)
	if node is RigidBody3D:
		node.freeze = true
		node.collision_layer = 2
		node.collision_mask = 0
	if node is Area3D:
		node.monitoring = false
		node.monitorable = false
	if node is Joint3D:
		node.node_a = NodePath()
		node.node_b = NodePath()

func _spawn_replica(id: int, scene: String, pose: Transform3D, _collision: int, corpse_profile: Dictionary = {}):
	if replicas.has(id) or not allowed_scenes.has(scene):
		return
	var packed = load(scene)
	if not packed is PackedScene:
		return
	var body = packed.instantiate()
	_strip(body)
	if not body is Node3D:
		body.free()
		return
	body.set_meta("coop_id", id)
	add_child(body)
	body.global_transform = pose
	if scene == "res://coop/corpse.tscn": press_corpses.Corpse.build_visual(body, corpse_profile)
	replicas[id] = body
	if id == guest_held_id: item_collision.update_held()
	if body.get_meta("coop_fuse", false): fuse_sync.receive(fuse_sync.last_state)
	duck_pass.track(body)
	remote_tools.apply_screen(id)

func guest_action(action: String):
	if test_mode: print("[COOP] CLICK action=", action, " panel=", panel.visible, " intro=", pending_intro)
	if role != "guest" or guest_settings.active() or panel.visible or character_editor.visible or guest_terminal.active() or pending_intro:
		return
	var cam = view_rig.camera if is_instance_valid(view_rig) and view_rig.active else guest.camera
	var query = PhysicsRayQueryParameters3D.create(cam.global_position, cam.global_position - cam.global_basis.z * 8.0, 0xFFFFFFFF)
	query.exclude = duck_pass.rids()
	var hit = guest.get_world_3d().direct_space_state.intersect_ray(query)
	var id = 0
	if hit:
		var target = hit.collider
		while target and target != get_tree().current_scene:
			if target.has_meta("coop_id"):
				id = target.get_meta("coop_id")
				break
			if target.has_meta("coop_control"):
				id = target.get_meta("coop_control")
				break
			target = target.get_parent()
	if action in ["interact", "equip"] and guest_held_id != 0: id = guest_held_id
	# Reliable pose precedes the click so the host validates the current aim.
	_send(1, ["pose", guest.global_transform, guest.camera.global_transform])
	_send(1, ["action", action, id])

func _action(peer: int, action: String, id):
	if action == "interact" and fuse_sync.try_insert(peer): return
	# Resolve press-mode on the authority, including clicks before pickup ACK.
	if action == "grab_toggle":
		if held.has(peer) and not broom_players.equipped(peer):
			_release(peer, false)
			return
		action = "grab"
	if test_mode:
		print("[COOP] ACTION REQUEST ", action, " id=", id, " known=", bodies.has(id), " pose_time=", peers[peer].pose_time)
	if not peers[peer].ready or not peers[peer].pose_time:
		return
	if action == "equip":
		broom_players.equip_guest(peer, id)
		return
	if broom_players.equipped(peer):
		if remote_tools.is_remote(instance_from_id(held[peer].id)):
			remote_tools.action(peer, action)
			return
		if action in ["grab", "interact"]: broom_players.use_equipped(peer)
		return
	if action == "craft_hold":
		var node = world_actions.get(id) if id is String else instance_from_id(id) if bodies.has(id) else null
		if craft_holds.has(peer) and craft_holds[peer].node != node: _end_craft(peer)
		if node is Node3D and node.has_method("start_crafting") and node.has_method("stop_crafting") and not node.has_method("turn_on"):
			_control_action(peer, node, true)
		else:
			_end_craft(peer)
		return
	if action == "rack":
		panel_rack.action(peer, id)
		return
	var now = Time.get_ticks_msec()
	if action != "grab" and now - peers[peer].action_time < 150:
		return
	peers[peer].action_time = now
	if held.has(peer) and action in ["grab", "throw"]:
		if action == "throw" and get_node("/root/GameState").upgrades["throw"].level <= 0:
			_send(peer, ["notice", "Purchase the shared Throw upgrade first."])
			return
		if action == "throw": _release(peer, true)
		return
	if id is String:
		if world_actions.has(id) and action in ["grab", "interact"]:
			_control_action(peer, world_actions[id], action == "grab" and world_actions[id].has_method("start_crafting") and not world_actions[id].has_method("turn_on"))
		return
	if not bodies.has(id):
		return
	var body = instance_from_id(id)
	if not is_instance_valid(body) or not body.is_inside_tree():
		return
	if body.get_meta("slotted", false) or body.is_in_group("terminal_pull"): return
	if not _can_reach_body(peer, body): return
	for owner in held:
		if held[owner].id == id and (owner != peer or action != "interact"):
			_send(peer, ["notice", "Another player is holding this object."])
			return
	var host_camera = get_tree().get_first_node_in_group("main_camera")
	if host_camera and (host_camera.get("picked_object") == body or host_camera.get("equipped_item") == body):
		return
	if action in ["tune_up", "tune_down", "tune_cycle"]:
		var method = "scroll_" + action
		if not held.has(peer) and _aims_at_control(peer, body) and body.has_method(method): body.call(method)
	elif action == "grab" and body.is_in_group("draggable"):
		_begin_guest_carry(peer, body)
	elif action in ["grab", "interact"] and _is_control(body):
		_control_action(peer, body)
	elif action == "grab" and test_mode:
		print("[COOP] REJECT not draggable ", body.get_groups())
	elif action == "interact":
		var item = body.scene_file_path.get_file().trim_suffix(".tscn")
		if item in TOOL_SCENES and body.has_method("interact"):
			body.interact()
			_send(peer, ["notice", "Activated " + item])
		else:
			_send(peer, ["notice", "This interaction is host-only in this alpha."])

func _can_reach_body(peer: int, body: RigidBody3D) -> bool:
	var cam: Transform3D = peers[peer].camera
	var excluded = duck_pass.rids(peer).duplicate()
	if is_instance_valid(host_player): excluded.append(host_player.get_rid())
	# Match the native pickup ray: a visible surface can be within reach even
	# when a large tool's origin is farther away or behind its mounting surface.
	var ray = PhysicsRayQueryParameters3D.create(cam.origin, cam.origin - cam.basis.z * 5.0, 0xFFFFFFFF)
	ray.exclude = excluded
	var space = body.get_world_3d().direct_space_state
	var hit = space.intersect_ray(ray)
	if hit and hit.collider == body: return true
	# Preserve tolerance for a moving replica between network snapshots.
	if cam.origin.distance_to(body.global_position) > 5.0: return false
	ray.to = body.global_position
	ray.collision_mask = 1
	var obstruction = space.intersect_ray(ray)
	return obstruction.is_empty() or obstruction.collider == body

func _begin_guest_carry(peer: int, body: RigidBody3D):
	if held.has(peer): return
	var native_camera = host_player.get_node("CameraPivot/MainCamera")
	if native_camera.picked_object == body or native_camera.equipped_item == body: return
	for hold in held.values():
		if hold.id == body.get_instance_id(): return
	var id = body.get_instance_id()
	var cam: Transform3D = peers[peer].camera
	held[peer] = {"id": id, "distance": clampf(cam.origin.distance_to(body.global_position), 1.5, 3.5), "gravity": body.gravity_scale, "lock": body.lock_rotation, "monitor": body.contact_monitor, "contacts": body.max_contacts_reported}
	native_camera._release_from_piston(body)
	body.contact_monitor = true
	body.max_contacts_reported = maxi(body.max_contacts_reported, 8)
	if body.has_method("unplace"):
		body.unplace()
	body.freeze = false
	native_camera._disable_held_gravity(body)
	body.lock_rotation = true
	_send(peer, ["held_item", id])
	_send(peer, ["held_mode", false, 0, held[peer].distance])
	_send(peer, ["notice", "Grabbed shared object."])
	print("[COOP] GRAB peer=", peer, " object=", id)

func _release(peer: int, toss: bool):
	if not held.has(peer):
		return
	var body = instance_from_id(held[peer].id)
	if is_instance_valid(body):
		broom_players.unequip_body(peer, body)
		if held[peer].has("layer"): body.collision_layer = held[peer].layer
		body.gravity_scale = held[peer].gravity
		host_player.get_node("CameraPivot/MainCamera")._restore_held_gravity(body)
		body.freeze = false
		body.sleeping = false
		body.lock_rotation = held[peer].lock
		var snap_placed = not toss and peers.has(peer) and held_controls.place(peer, body)
		if not toss and not snap_placed and body.has_method("place"):
			body.call_deferred("place")
		# Keep contacts available until the original deferred placement has checked them.
		_restore_guest_contacts.call_deferred(body, held[peer].get("monitor", false), held[peer].get("contacts", 0))
		if toss and peers.has(peer):
			var direction: Vector3 = -peers[peer].camera.basis.z
			body.apply_central_impulse(direction * 5.0 * get_node("/root/GameState").upgrades["throw"].level)
	held.erase(peer)
	_send(peer, ["held_mode", false, 0, 2.5])
	_send(peer, ["sticky_ready", false])
	_send(peer, ["held_item", 0])
	_send(peer, ["tool_equipped", false])
	_send(peer, ["notice", "Threw shared object." if toss else "Dropped shared object."])
	print("[COOP] RELEASE peer=", peer, " throw=", toss)

func _avatar(id: int, pose: Transform3D):
	if not avatars.has(id):
		var root = Avatar.new()
		add_child(root)
		root.configure(profiles.get(id, Avatar.defaults()), true)
		avatars[id] = root
		root.global_transform = pose
	_queue_motion(avatars[id], pose)

func _refresh_avatar_profile(id):
	if avatars.has(id):
		avatars[id].configure(profiles[id], true)

func _broadcast_profiles():
	profiles[1] = profile.duplicate()
	for id in peers:
		if peers[id].hello:
			_send(id, ["profiles", profiles])
	_publish_lobby()

func _load_profile():
	var config = ConfigFile.new()
	if config.load(profile_path) == OK:
		var value = config.get_value("character", "profile", Avatar.defaults())
		if value is Dictionary:
			profile = Avatar.sanitize(value)

func _build_character_ui():
	character_editor = CharacterMenu.new()
	character_editor.name = "CharacterEditor"
	hud.add_child(character_editor)
	character_editor.saved.connect(_save_profile)
	character_editor.cancelled.connect(_close_character)
	panel.theme = character_editor.theme
	home_buttons = VBoxContainer.new()
	home_buttons.name = "CoopStartButtons"
	home_buttons.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	home_buttons.offset_left = -405
	home_buttons.offset_right = -30
	home_buttons.offset_top = -168
	home_buttons.offset_bottom = -38
	home_buttons.add_theme_constant_override("separation", 12)
	home_buttons.theme = character_editor.theme
	hud.add_child(home_buttons)
	for row in [["CHARACTER", _open_character], ["CO-OP / HOST + JOIN", _toggle_panel]]:
		var button = Button.new()
		button.name = "CharacterButton" if row[0] == "CHARACTER" else "CoopButton"
		button.text = row[0]
		button.custom_minimum_size = Vector2(365, 53)
		button.add_theme_color_override("font_color", Color("efca50"))
		button.pressed.connect(row[1])
		home_buttons.add_child(button)
	home_buttons.hide()
	# The editor is drawn above the start-screen controls.
	hud.move_child(character_editor, -1)

func _open_character():
	panel.hide()
	lobby.hide()
	if character_editor.visible:
		return
	editor_body = local_body
	if is_instance_valid(editor_body):
		editor_body_mode = editor_body.process_mode
		editor_body.process_mode = Node.PROCESS_MODE_DISABLED
	character_editor.open(profile)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _close_character():
	character_editor.close()
	if role in ["host", "waiting"] and not world_ready and not lobby_starting:
		_show_lobby()
	if is_instance_valid(editor_body):
		editor_body.process_mode = editor_body_mode
	editor_body = null
	_update_menu_mouse()

func _save_profile(value: Dictionary):
	var clean = Avatar.sanitize(value)
	var config = ConfigFile.new()
	config.set_value("character", "profile", clean)
	var error = config.save(profile_path)
	if error != OK:
		character_editor.feedback.text = "Could not save: " + error_string(error)
		return
	profile = clean
	if is_instance_valid(local_avatar):
		local_avatar.configure(profile, false)
	if role == "host":
		_broadcast_profiles()
	elif role in ["guest", "waiting", "loading"]:
		_send(1, ["profile", profile])
	_close_character()
	print("[COOP] Character saved: ", profile.name)

func _update_character(delta):
	entry_clock += delta
	if entry_clock >= 0.25:
		entry_clock = 0
		var menu = get_tree().get_first_node_in_group("MainMenu")
		var buttons = menu.get_node_or_null("Background/MenuButtons") if is_instance_valid(menu) else null
		home_buttons.visible = is_instance_valid(menu) and (buttons == null or buttons.visible) and not character_editor.visible and not panel.visible and not lobby.visible and role == "offline"
		if not is_instance_valid(local_body):
			if is_instance_valid(view_rig):
				view_rig.queue_free()
			if is_instance_valid(local_avatar):
				local_avatar.queue_free()
			view_rig = null
			local_avatar = null
			if is_instance_valid(guest):
				local_body = guest
			else:
				for body in get_tree().root.find_children("*", "CharacterBody3D", true, false):
					if not is_ancestor_of(body):
						local_body = body
						break
			if is_instance_valid(local_body):
				var eye = guest.render_camera if local_body == guest else local_body.get_node_or_null("CameraPivot/MainCamera")
				if eye is Camera3D:
					local_avatar = Avatar.new()
					local_avatar.name = "LocalCharacter"
					add_child(local_avatar)
					local_avatar.configure(profile, false)
					local_avatar.hide()
					view_rig = ThirdPerson.new()
					view_rig.name = "ThirdPersonView"
					add_child(view_rig)
					view_rig.attach(local_body, eye)
					print("[COOP] Character attached to ", local_body.get_path(), " eye=", eye.position)
	if is_instance_valid(local_avatar) and is_instance_valid(local_body):
		local_avatar.global_transform = _body_visual_pose(local_body)
		local_avatar.crouched = _is_crouched(local_body)
		local_avatar.sliding = _is_sliding(local_body)
		local_avatar.visible = is_instance_valid(view_rig) and view_rig.active

func _is_crouched(body: Node3D) -> bool:
	if body == guest: return guest.crouched
	return bool(body.get("is_crouching")) or bool(body.get("is_sliding"))

func _is_sliding(body: Node3D) -> bool:
	if broom_players.remaining > 0.0: return true
	if body == guest: return guest.slide_time > 0.0
	return bool(body.get("is_sliding"))

func _body_visual_pose(body: Node3D) -> Transform3D:
	var pose = body.global_transform
	var shape_node = body.get_node_or_null("CollisionShape3D")
	if shape_node is CollisionShape3D and shape_node.shape is CapsuleShape3D:
		pose.origin += pose.basis * Vector3(0, shape_node.position.y - shape_node.shape.height * 0.5, 0)
	return pose

func _toggle_view():
	if not is_instance_valid(view_rig):
		return
	view_rig.set_active(not view_rig.active)
	local_avatar.visible = view_rig.active
	character_test_toggle_count += 1
	print("[COOP] F5 view=", "third person" if view_rig.active else "first person")

func _character_checks():
	await get_tree().create_timer(5.0).timeout
	var trial = profile.duplicate()
	trial.name = "HOST QA" if role == "host" else "GUEST QA"
	trial.suit = 2 if role == "host" else 1
	trial.helmet = 2 if role == "host" else 1
	trial.gear = 1 if role == "host" else 2
	_save_profile(trial)
	var reloaded = ConfigFile.new()
	var persisted = reloaded.load(profile_path) == OK and reloaded.get_value("character", "profile", {}) == profile
	var before: Transform3D = view_rig.eye.transform
	var save_tick = get_node("/root/SaveManager").get("_last_save_tick")
	await _test_press_f5()
	var third_ok = view_rig.camera.current and local_avatar.visible
	var native_hidden = true
	for mesh in view_rig.original_meshes:
		native_hidden = native_hidden and not mesh.visible
	await _test_press_f5()
	var first_ok = view_rig.eye.current and not local_avatar.visible and view_rig.eye.transform == before
	var native_restored = true
	for mesh in view_rig.original_meshes:
		native_restored = native_restored and mesh.visible == view_rig.original_meshes[mesh]
	await _test_press_f5()
	var no_save = save_tick == get_node("/root/SaveManager").get("_last_save_tick")
	await get_tree().create_timer(5.0).timeout
	var remote = {}
	for id in avatars:
		remote[str(id)] = avatars[id].profile
	var report = {"profile_saved": persisted, "third_person": third_ok, "first_person_restored": first_ok, "f5_did_not_save": no_save, "quick_save_is_f6": get_node("/root/InputManager").current_bindings.get("quick_save") == KEY_F6, "local_profile": profile, "remote_profiles": remote, "role": role}
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/character-" + role + ".json"), FileAccess.WRITE)
	report.native_body_hidden = native_hidden
	report.native_body_restored = native_restored
	if file:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("[COOP] CHARACTER TEST ", JSON.stringify(report))

func _test_press_f5():
	var event = InputEventKey.new()
	event.keycode = KEY_F5
	event.physical_keycode = KEY_F5
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().process_frame

func _remove_avatar(id):
	if avatars.has(id):
		avatars[id].queue_free()
		avatars.erase(id)

func _fail(message: String):
	connection_health.record(message, 1)
	status.text = message
	info.text = message
	print("[COOP] ERROR ", message)
	if net:
		net.close()
	net = null
	role = "failed"
	lobby.hide()
	panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _quit_session():
	if net:
		net.close()
	get_tree().quit()

func _make_test_body():
	if "--fuse-test" in OS.get_cmdline_user_args(): return
	if "--corpse-test" in OS.get_cmdline_user_args(): return
	if "--magnets-test" in OS.get_cmdline_user_args():
		magnets_test.run_host.call_deferred()
		return
	if "--remote-test" in OS.get_cmdline_user_args():
		remote_test.run_host.call_deferred()
		return
	if "--duck-pass-test" in OS.get_cmdline_user_args():
		duck_pass_test.run_host.call_deferred()
		return
	if "--broom-guest-test" in OS.get_cmdline_user_args():
		broom_guest_test.run_host.call_deferred()
		return
	if "--scheduler-test" in OS.get_cmdline_user_args():
		scheduler_test.run_host.call_deferred()
		return
	if "--panel-outline-test" in OS.get_cmdline_user_args():
		panel_highlights.test_host.call_deferred()
		return
	if "--slide-test" in OS.get_cmdline_user_args():
		slide_test.run_host.call_deferred()
		return
	if "--cash-test" in OS.get_cmdline_user_args():
		cash_test.run_host.call_deferred()
		return
	if "--crouch-test" in OS.get_cmdline_user_args():
		crouch_test.run_host.call_deferred()
		return
	if "--phase-test" in OS.get_cmdline_user_args():
		phase_sync.run_test.call_deferred()
		return
	if "--status-test" in OS.get_cmdline_user_args():
		status_test.run_host.call_deferred()
		return
	if "--toggle-test" in OS.get_cmdline_user_args():
		broom_players.run_toggle_host.call_deferred()
		return
	if "--equip-test" in OS.get_cmdline_user_args():
		broom_players.run_equip_host_checks.call_deferred()
		return
	if "--holding-test" in OS.get_cmdline_user_args():
		var check = load("res://coop/holding_test.gd").new()
		check.session = self
		add_child(check)
		check.run.call_deferred()
	if "--emotes-test" in OS.get_cmdline_user_args():
		var check = load("res://coop/emote_test.gd").new()
		check.session = self
		add_child(check)
		check.run.call_deferred()
	if "--float-test" in OS.get_cmdline_user_args():
		var check = load("res://coop/float_test.gd").new()
		check.session = self
		add_child(check)
		check.run.call_deferred()
	if "--collision-test" in OS.get_cmdline_user_args():
		var check = load("res://coop/collision_test.gd").new()
		check.session = self
		add_child(check)
		check.run.call_deferred()
	if "--trading-test" in OS.get_cmdline_user_args():
		var trading_test = load("res://coop/trading_test.gd").new()
		trading_test.session = self
		add_child(trading_test)
		trading_test.run.call_deferred()
		return
	if "--tube-test" in OS.get_cmdline_user_args():
		var tube_test = load("res://coop/tube_test.gd").new()
		tube_test.session = self
		add_child(tube_test)
		tube_test.run.call_deferred()
		return
	if "--load-test" in OS.get_cmdline_user_args(): _load_stress.call_deferred()
	if "--terminal-test" in OS.get_cmdline_user_args(): guest_terminal.run_host_checks()
	get_node("/root/GameState").upgrades["throw"].level = 1
	if "--held-controls-test" in OS.get_cmdline_user_args():
		var grid_test = load("res://coop/grid_test.gd").new()
		grid_test.session = self
		add_child(grid_test)
		grid_test.run.call_deferred()
		get_node("/root/GameState").upgrades.snap_grid.level = 1
		get_node("/root/GameState").upgrades.reset_rotation.level = 1
	var body: RigidBody3D
	if "--rack-test" in OS.get_cmdline_user_args():
		get_node("/root/GameState").upgrades.panel_rack.level = 1
		var pool = get_node("/root/ObjectPoolManager")
		pool._create_pool("tool_panel", {"scene": load("res://scenes/panel.tscn"), "initial": 0, "max": 12})
		body = pool.spawn("tool_panel")
	else:
		body = load("res://scenes/duck.tscn").instantiate()
		get_tree().current_scene.add_child(body)
	body.global_position = Vector3(0, 0.6, 18) if "--floor-grab-test" in OS.get_cmdline_user_args() else Vector3(0, 7, 18)
	body.freeze = not "--floor-grab-test" in OS.get_cmdline_user_args()
	body.show()
	test_id = body.get_instance_id()
	print("[COOP] TEST BODY ", test_id)
	if "--broom-test" in OS.get_cmdline_user_args(): broom_players.run_checks.call_deferred()
	if "--sticky-test" in OS.get_cmdline_user_args(): _sticky_checks.call_deferred()
	if "--host-sticky-ui-test" in OS.get_cmdline_user_args(): get_node("StickyControls").run_host_checks.call_deferred()
	if "--sync-test" in OS.get_cmdline_user_args():
		_run_sync_host_checks.call_deferred()

func _test_grab():
	while pending_intro:
		await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout
	var target = replicas[test_id].global_position
	guest.set_physics_process(false)
	guest.global_position = target + Vector3(0, -0.5, 2)
	if "--floor-grab-test" in OS.get_cmdline_user_args(): guest.global_position.y = 0.05
	guest.camera.look_at(target)
	await get_tree().create_timer(0.3).timeout
	_test_grab_button(true)
	if "--rack-test" in OS.get_cmdline_user_args():
		_send(1, ["pose", guest.global_transform, guest.camera.global_transform])
		_send(1, ["action", "grab", test_id])
	await get_tree().create_timer(1.0).timeout
	var held_while_pressed = guest_held_id == test_id
	if "--rack-test" in OS.get_cmdline_user_args():
		await panel_rack.run_guest_checks()
		return
	if "--held-controls-test" in OS.get_cmdline_user_args(): await held_controls.run_guest_checks()
	if "--rotate-test" in OS.get_cmdline_user_args():
		var before_rotation = replicas[test_id].global_basis
		guest.rotate_motion = Vector2(30, 15)
		await get_tree().create_timer(0.7).timeout
		var rotated = not replicas[test_id].global_basis.is_equal_approx(before_rotation)
		var rotation_report = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/rotation-network.json"), FileAccess.WRITE)
		if rotation_report: rotation_report.store_string(JSON.stringify({"passed": rotated}))
	if "--floor-grab-test" in OS.get_cmdline_user_args():
		_test_grab_button(false)
		await get_tree().create_timer(1.5).timeout
		target = replicas[test_id].global_position
		guest.global_position = Vector3(target.x, 0.05, target.z + 2.0)
		guest.camera.look_at(target)
		await get_tree().create_timer(0.3).timeout
		_test_grab_button(true)
		await get_tree().create_timer(1.0).timeout
	_test_click(MOUSE_BUTTON_RIGHT)
	await get_tree().create_timer(1.0).timeout
	_test_grab_button(false)
	var passed = held_while_pressed and test_grab_confirmed and test_throw_confirmed and received_states > 0
	if "--floor-grab-test" in OS.get_cmdline_user_args(): passed = passed and test_drop_confirmed and test_grab_count >= 2
	print("[COOP] TEST ", "PASS" if passed else "FAIL", " replicas=", replicas.size(), " states=", received_states, " grabbed=", test_grab_confirmed, " threw=", test_throw_confirmed)
	var report = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/network-test.json"), FileAccess.WRITE)
	if report:
		report.store_string(JSON.stringify({"passed": passed, "held_while_pressed": held_while_pressed, "drop_confirmed": test_drop_confirmed, "grab_count": test_grab_count, "replicas": replicas.size(), "state_packets": received_states, "grab_confirmed": test_grab_confirmed, "throw_confirmed": test_throw_confirmed}, "  "))
		report.close()
	guest.camera.rotation.x = 0
	guest.set_physics_process(true)


func _build_lobby():
	lobby = PanelContainer.new()
	lobby.name = "CoopLobby"
	lobby.position = Vector2(25, 55)
	lobby.custom_minimum_size = Vector2(610, 0)
	lobby.theme = character_editor.theme
	hud.add_child(lobby)
	var margin = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	lobby.add_child(margin)
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	var title = Label.new()
	title.text = "PERSONNEL / CO-OP LOBBY"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("efca50"))
	box.add_child(title)
	lobby_note = Label.new()
	lobby_note.text = "Connecting..."
	box.add_child(lobby_note)
	lobby_roster = Label.new()
	lobby_roster.custom_minimum_size.y = 140
	box.add_child(lobby_roster)
	lobby_start = Button.new()
	lobby_start.text = "START NEW GAME / BOARD ELEVATOR"
	lobby_start.pressed.connect(_start_lobby_game)
	box.add_child(lobby_start)
	lobby_ready = Button.new()
	lobby_ready.text = "READY UP"
	lobby_ready.pressed.connect(_toggle_lobby_ready)
	box.add_child(lobby_ready)
	for item in [["HIDE LOBBY (F8 / ESC)", _hide_lobby], ["EDIT CHARACTER", _open_character], ["LEAVE LOBBY", _leave_lobby]]:
		var button = Button.new()
		button.text = item[0]
		button.pressed.connect(item[1])
		box.add_child(button)
	guest_terminal.add_restriction_control(box)
	item_collision.add_controls(box)
	lobby.hide()
	hud.move_child(character_editor, -1)

func _show_lobby():
	panel.hide()
	lobby.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_render_lobby()

func _publish_lobby():
	if role != "host":
		return
	lobby_members = [[1, profile.name, true]]
	for id in peers:
		if peers[id].hello:
			lobby_members.append([id, profiles[id].name, peers[id].get("lobby_ready", false)])
	for id in peers:
		if peers[id].hello:
			_send(id, ["lobby", lobby_members, lobby_starting])
	_render_lobby()

func _render_lobby():
	guest_terminal.refresh_restriction_controls()
	item_collision.refresh()
	if not is_instance_valid(lobby):
		return
	lobby_start.visible = role == "host"
	lobby_ready.visible = role == "waiting" and not lobby_starting
	lobby_start.disabled = lobby_starting or not _all_lobby_ready()
	lobby_note.text = "LOADING / Waiting for every intern to board..." if lobby_starting else "Invite friends using your IP / UDP 27808.\nReady up, then the host starts a new shift together."
	lobby_roster.text = "CREW MANIFEST / %d OF 4\n\n" % lobby_members.size()
	for row in lobby_members:
		lobby_roster.text += "%s    %s\n" % [row[1], "HOST" if row[0] == 1 else ("READY" if row[2] else "NOT READY")]
	lobby_ready.text = "NOT READY / CANCEL" if lobby_is_ready else "READY UP"

func _all_lobby_ready() -> bool:
	for id in peers:
		if not peers[id].hello or not peers[id].get("lobby_ready", false):
			return false
	return true

func _toggle_lobby_ready():
	if role != "waiting" or lobby_starting:
		return
	lobby_is_ready = not lobby_is_ready
	_send(1, ["lobby_ready", lobby_is_ready])
	_render_lobby()

func _leave_lobby():
	if world_ready or role in ["guest", "loading"] or lobby_starting:
		_quit_session()
		return
	if net:
		net.close()
	net = null
	role = "offline"
	peers.clear()
	profiles.clear()
	known.clear()
	lobby_members.clear()
	lobby_is_ready = false
	lobby.hide()
	var menu = get_tree().get_first_node_in_group("MainMenu")
	if menu:
		menu.show()
	status.text = "P.I.T.T. CO-OP 04 | F8: menu | F5: view"

func _update_lobby():
	if not is_instance_valid(lobby):
		return
	var menu = get_tree().get_first_node_in_group("MainMenu")
	if menu and role in ["host", "waiting", "connecting"] and not world_ready:
		menu.visible = false
	# Opening is explicit; a hidden lobby must not reopen every frame.
	if (world_ready or (role == "guest" and not pending_intro)) and lobby.visible:
		_hide_lobby()
	if lobby_test and not lobby_test_started and menu:
		if role == "waiting" and not lobby_members.is_empty():
			lobby_test_started = true
			_toggle_lobby_ready()
		elif role == "host" and peers.size() > 0 and _all_lobby_ready():
			lobby_test_started = true
			_test_start_lobby.call_deferred()

func _test_start_lobby():
	await get_tree().create_timer(5.0).timeout
	_start_lobby_game()

func _start_lobby_game():
	if role != "host" or lobby_starting or world_ready or not _all_lobby_ready():
		return
	var menu = get_tree().get_first_node_in_group("MainMenu")
	if menu == null:
		return
	var saves = get_node("/root/SaveManager")
	var selected = int(menu.get("_selected_slot"))
	if saves.slot_occupied(selected) and saves.first_free_slot() < 0:
		lobby_note.text = "All save slots are full. Leave the lobby and manage saves."
		return
	lobby_starting = true
	_hide_lobby()
	_publish_lobby()
	print("[COOP] LOBBY START crew=", lobby_members.size())
	menu.call("_on_new_game")

func _guest_spawn(id: int) -> Vector3:
	if test_mode and not lobby_test:
		return Vector3(0, 6, 20)
	var feet = _body_visual_pose(host_player).origin
	var index = peers.keys().find(id)
	var offsets = [Vector3(0.8, 0.04, 0), Vector3(-0.8, 0.04, 0), Vector3(0, 0.04, -0.85)]
	return feet + host_player.global_basis * offsets[index % 3]

func board_elevator(elevator: Node3D):
	intro_node = elevator
	elevator_waiting = true
	intro_released = false
	# World _ready is still running. Allow player discovery and guest scene loading.
	await get_tree().process_frame
	var player = get_tree().get_first_node_in_group("player")
	var previous_mode = player.process_mode if player else Node.PROCESS_MODE_INHERIT
	if player:
		player.process_mode = Node.PROCESS_MODE_DISABLED
	var started = Time.get_ticks_msec()
	while is_inside_tree() and role == "host":
		var ready = true
		for id in peers.keys():
			if not peers[id].get("ready", false):
				ready = false
				if Time.get_ticks_msec() - started > 90000:
					_send(id, ["error", "Loading timed out. Relaunch and join again."])
					net.disconnect_peer(id)
					_peer_disconnected(id)
		if world_ready and ready:
			break
		status.text = "BOARDING / Waiting for everyone to load the elevator..."
		await get_tree().process_frame
	# A short settle gives every peer initial transforms before the fade opens.
	await get_tree().create_timer(1.0).timeout
	intro_released = true
	elevator_waiting = false
	lobby.hide()
	if is_instance_valid(player):
		player.process_mode = previous_mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("[COOP] ELEVATOR BARRIER RELEASE crew=", peers.size() + 1, " host=", _body_visual_pose(host_player).origin)
	if lobby_test:
		_lobby_checks.call_deferred()

func elevator_event(event: String, elevator: Node3D):
	if get_tree().current_scene:
		_broadcast(["elevator", event, str(get_tree().current_scene.get_path_to(elevator))])
	print("[COOP] ELEVATOR ", event)

func _guest_elevator_event(event: String, path: String):
	var elevator = get_tree().current_scene.get_node_or_null(NodePath(path))
	if not elevator:
		return
	intro_node = elevator
	if event == "ride":
		lobby.hide()
		pending_intro = false
		intro_released = true
		guest.set_physics_process(true)
		if is_instance_valid(guest_fade):
			var fade = create_tween()
			fade.tween_property(guest_fade, "color:a", 0.0, 2.5)
			fade.tween_callback(guest_fade.queue_free)
		_play_elevator_audio(elevator, "ElevatorMusic", 15.0)
		_play_elevator_audio(elevator, "ElevatorSound")
		intro_local_time = Time.get_ticks_msec()
		if lobby_test:
			_lobby_checks.call_deferred()
	elif event == "open":
		var music = elevator.get_node_or_null("ElevatorMusic")
		if music: music.stop()
		_play_elevator_audio(elevator, "ElevatorDing")
		_play_elevator_audio(elevator, "DoorOpenSound")
	elif event == "close":
		_play_elevator_audio(elevator, "DoorCloseSound")
	print("[COOP] GUEST ELEVATOR ", event)

func _play_elevator_audio(elevator: Node, child: String, offset = 0.0):
	var sound = elevator.get_node_or_null(NodePath(child))
	if sound is AudioStreamPlayer3D:
		sound.play(offset)

func guest_in_elevator(elevator: Node3D) -> bool:
	var shape = elevator.get_node_or_null("ExitDetector/CollisionShape3D")
	if not shape or not shape.shape is BoxShape3D:
		return false
	for id in peers:
		if peers[id].ready:
			var point: Vector3 = shape.to_local(peers[id].pose.origin + Vector3(0, 0.9, 0))
			var half: Vector3 = shape.shape.size * 0.5
			if absf(point.x) <= half.x and absf(point.y) <= half.y and absf(point.z) <= half.z:
				return true
	return false

func _lobby_checks():
	await get_tree().create_timer(3.0).timeout
	var body = host_player if role == "host" else guest
	var report = {"role": role, "crew": lobby_members, "released": intro_released, "position": str(_body_visual_pose(body).origin), "elevator": str(intro_node.global_position), "doors_before": str(intro_node.get_node("InsideDoorR").position), "avatars": avatars.size()}
	var shape = intro_node.get_node_or_null("ExitDetector/CollisionShape3D")
	if shape:
		report.detector_position = str(shape.global_position)
		report.detector_size = str(shape.shape.size)
		report.local_in_detector = str(shape.to_local(_body_visual_pose(body).origin + Vector3(0, 0.9, 0)))
	await get_tree().create_timer(21.0).timeout
	report.doors_after = str(intro_node.get_node("InsideDoorR").position)
	report.door_moved = report.doors_after != report.doors_before
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/lobby-" + role + ".json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "  "))
	print("[COOP] LOBBY TEST ", JSON.stringify(report))
	if not visual_mode:
		get_tree().quit()

func _test_grab_button(pressed: bool):
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)

func _test_click(button: int):
	var event = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)


func _sync_presentation():
	var scope_start = Time.get_ticks_usec() if perf_enabled else 0
	if spatial_tick >= 0.5:
		spatial_tick = 0.0
		_refresh_nearby_audio()
	var priority_due = priority_tick >= 0.1
	if priority_due:
		priority_tick = 0.0
		fuse_sync.sync_host()
		remote_tools.sync()
		phase_sync.sync_host()
	var world = get_tree().current_scene
	var state: Dictionary = {}
	# Spread presentation polling across frames so a large warehouse cannot
	# monopolize a single host frame. Each slice retains per-peer change tracking.
	var end = mini(presentation_cursor + 64, presentation_sources.size())
	# State switches must not wait behind a warehouse traversal or repeated rebuilds.
	var sources = presentation_sources.slice(presentation_cursor, end)
	if priority_due: sources += priority_presentation_sources + nearby_audio_sources
	for source in sources:
		var node = source[2]
		if not is_instance_valid(node) or not node.is_inside_tree(): continue
		var path = source[0]
		match source[1]:
			"particles": state[path] = [path, "particles", [node.visible, node.emitting]]
			"tool": state[path] = [path, "tool", [str(node.object_name()), node.get("placed") == true or node.get("state") == 1]]
			"label3d": state[path] = [path, "label3d", [node.visible, node.text, node.modulate]]
			"visible":
				if not node is Light3D and not node is AudioStreamPlayer3D:
					state[path] = [path, "visible", [node.visible]]
			"light": state[path] = [path, "light", [node.visible, node.light_energy, node.light_color, node.shadow_enabled, node.light_indirect_energy]]
			"audio": state[path] = [path, "audio", [node.visible, node.playing, node.volume_db, node.pitch_scale]]
			"part":
				if not node is CollisionShape3D: state[path] = [path, "part_visible", [node.visible]]
				# Visual poses use the motion stream plus a periodic full refresh.
				if node is CollisionShape3D: state[path] = [path, "part", [node.visible, node.transform, node.disabled, node.rotation]]
	presentation_cursor = 0 if end == presentation_sources.size() else end
	var game_hud = get_tree().get_first_node_in_group("HUD")
	if game_hud:
		for label_name in ["IntroLabel", "DeathLabel", "NotificationLabel"]:
			var label = game_hud.get_node_or_null(NodePath(label_name))
			if label is Label:
				state["ui/" + label_name] = ["ui/" + label_name, "label", [label.text, label.is_visible_in_tree(), label.modulate, label.get_theme_font_size("font_size")]]
	var upgrades = {}
	for key in get_node("/root/GameState").upgrades:
		var upgrade = get_node("/root/GameState").upgrades[key]
		upgrades[key] = [int(upgrade.level), bool(upgrade.enabled)]
	for id in peers:
		if not peers[id].ready: continue
		panel_rack.sync_peer(id)
		if peers[id].get("sent_upgrades", {}) != upgrades:
			_send(id, ["upgrades", upgrades])
			peers[id].sent_upgrades = upgrades.duplicate(true)
		var batch: Array = []
		var previous: Dictionary = presentation_known.get(id, {})
		for path in state:
			if str(path).begins_with("@") and not known.get(id, {}).has(int(str(path).get_slice("/", 0).trim_prefix("@"))): continue
			var row: Array = state[path]
			if previous.get(path) == row: continue
			previous[path] = row.duplicate(true)
			var outgoing = row.duplicate(true)
			if row[1] == "part": outgoing[2].append(Time.get_ticks_msec() / 1000.0)
			if row[1] == "audio":
				var audio_node = _host_presentation_node(path)
				if not audio_node is AudioStreamPlayer3D: continue
				outgoing[2].append(audio_node.get_playback_position())
			batch.append(outgoing)
			if batch.size() == 24:
				_send(id, ["presentation", batch])
				batch = []
		if not batch.is_empty(): _send(id, ["presentation", batch])
		presentation_known[id] = previous
	if perf_enabled: perf_scopes["_sync_presentation"] = perf_scopes.get("_sync_presentation", 0) + Time.get_ticks_usec() - scope_start


func _apply_presentation(rows: Array):
	var world = get_tree().current_scene
	for row in rows:
		if row[1] == "label":
			var label = shared_labels.get(str(row[0]).trim_prefix("ui/"))
			if label:
				var fit_changed = label.text != row[2][0] or label.get_theme_font_size("font_size") != row[2][3]
				label.text = row[2][0]
				if str(row[0]) == "ui/IntroLabel" and row[2][1]: seen_intro = true
				label.visible = row[2][1]
				label.modulate = row[2][2]
				label.add_theme_font_size_override("font_size", row[2][3])
				if fit_changed: _fit_guest_message.call_deferred(label)
			continue
		var node: Node = null
		var path = str(row[0])
		if path.begins_with("@"):
			var slash = path.find("/")
			var id = int(path.substr(1, slash - 1))
			if replicas.has(id): node = replicas[id].get_node_or_null(NodePath(path.substr(slash + 1)))
		else:
			node = world.get_node_or_null(NodePath(path))
		if not node is Node3D: continue
		var values: Array = row[2]
		if row[1] == "tool":
			node.set_meta("coop_title", values[0])
			node.set_meta("coop_placed", values[1])
			continue
		if row[1] == "particles" and node is GPUParticles3D: node.emitting = values[1]
		if row[1] == "label3d" and node is Label3D:
			node.text = values[1]
			node.modulate = values[2]
		if row[1] != "part" and not node.has_meta("coop_outline"): node.visible = values[0]
		if row[1] == "part":
			if node is CollisionShape3D:
				node.transform = values[1]
				node.set_deferred("disabled", values[2])
			else:
				_queue_part_motion(node, values)
		elif row[1] == "light" and node is Light3D:
			node.light_energy = values[1]
			node.light_color = values[2]
			node.shadow_enabled = values[3]
			node.light_indirect_energy = values[4]
		elif row[1] == "audio" and node is AudioStreamPlayer3D:
			node.volume_db = values[2]
			node.pitch_scale = values[3]
			if values[1] and not node.playing: node.play(values[4])
			elif not values[1] and node.playing: node.stop()

func _is_machine_scene(node: Node) -> bool:
	return _is_control(node) or node.scene_file_path.get_file() == "gambling_terminal.tscn" or (node.has_method("sweep_products") and node.has_method("roll_or_stop"))

func _is_control(node: Node) -> bool:
	return node.has_method("interact") or node.has_method("start_crafting") or (node.has_method("turn_on") and node.has_method("turn_off"))

func _aims_at_control(peer: int, node: Node3D) -> bool:
	# Large workbenches have origins far from their usable collision surfaces.
	# Check the first surface along the guest's aim, keeping walls/range enforced.
	var eye: Transform3D = peers[peer].camera
	var query = PhysicsRayQueryParameters3D.create(eye.origin, eye.origin - eye.basis.z.normalized() * 5.0, 0xFFFFFFFF)
	query.exclude = duck_pass.rids(peer)
	var hit = node.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and (hit.collider == node or node.is_ancestor_of(hit.collider))

func _control_action(peer: int, node: Node3D, continuous = false):
	if not is_instance_valid(node) or not node.is_visible_in_tree(): return
	var own_held_tool = not continuous and held.has(peer) and held[peer].id == node.get_instance_id()
	if not own_held_tool and not _aims_at_control(peer, node):
		_send(peer, ["notice", "Aim at an unobstructed part of the control within reach."])
		return
	var script_name = node.get_script().resource_path.get_file().get_basename() if node.get_script() else ""
	if script_name == "upgrade_terminal":
		guest_terminal.open_for(peer, node)
		return
	if script_name in ["stat_sign"]:
		_send(peer, ["notice", "This menu is currently operated by the host."])
		return
	if continuous:
		for owner in craft_holds:
			if owner != peer and craft_holds[owner].node == node: return
		if node.has_meta("auto_crafter") and is_instance_valid(node.get_meta("auto_crafter")) and node.get_meta("auto_crafter") != self: return
		node.set_meta("auto_crafter", self)
		craft_holds[peer] = {"node": node, "expires": Time.get_ticks_msec() + 750}
		return
	if node.has_method("turn_on") and node.has_method("turn_off"):
		if node.get("is_turned_on"): node.turn_off()
		else: node.turn_on()
	elif node.has_method("start_crafting") and node.has_method("stop_crafting"):
		# Every manual start must own a cancellable hold, even a very short tap.
		return
	elif node.has_method("interact"):
		node.interact()
	_send(peer, ["notice", "Activated " + str(node.name)])
	print("[COOP] CONTROL peer=", peer, " node=", node.get_path())

func _copy_shared_labels(world: Node):
	for original_bar in world.find_children("*", "ProgressBar", true, false):
		if original_bar.is_in_group("WorkbenchProgress"): craft_hud.adopt_original(original_bar)
	var original_money = world.find_child("Money", true, false)
	guest_money = original_money.duplicate(0) if original_money is Label else Label.new()
	guest_money.set_script(null)
	guest_money.name = "SharedMoney"
	guest_money.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guest_money.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	guest_money.offset_left = -500
	guest_money.offset_right = -18
	guest_money.offset_top = 12
	guest_money.offset_bottom = 76
	guest_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	guest_money.text = "0$"
	hud.add_child(guest_money)
	var crosshair = Label.new()
	crosshair.text = "+"
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.offset_left = -8
	crosshair.offset_top = -10
	crosshair.add_theme_font_size_override("font_size", 20)
	hud.add_child(crosshair)
	guest_notice = Label.new()
	guest_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guest_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	guest_notice.offset_left = -400
	guest_notice.offset_right = 400
	guest_notice.offset_top = -75
	guest_notice.offset_bottom = -30
	guest_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	guest_notice.add_theme_color_override("font_color", Color("efca50"))
	hud.add_child(guest_notice)
	var layer = CanvasLayer.new()
	layer.layer = 80
	add_child(layer)
	for label_name in ["IntroLabel", "DeathLabel", "NotificationLabel"]:
		var original = world.find_child(label_name, true, false)
		if original is Label:
			var copy = original.duplicate(0)
			copy.set_script(null)
			copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
			copy.hide()
			layer.add_child(copy)
			copy.add_theme_font_override("font", load("res://assets/PublicPixel-rv0pA.ttf"))
			if not get_viewport().size_changed.is_connected(_fit_guest_messages):
				get_viewport().size_changed.connect(_fit_guest_messages)
			shared_labels[label_name] = copy

func _run_sync_host_checks():
	await get_tree().create_timer(20.0).timeout
	if "--craft-ui-test" in OS.get_cmdline_user_args(): get_node("/root/GameState").add_money(12345)
	for path in world_actions:
		var n = world_actions[path]
		print("[SYNC QA] control=", path, " script=", n.get_script().resource_path, " visible=", n.is_visible_in_tree(), " position=", n.global_position)
	get_node("/root/GameProgression").on_player_exit_elevator()
	get_node("/root/GameState").upgrades.sprint.level = 2
	get_node("/root/GameState").upgrades.jump.level = 2
	get_node("/root/GameState").products.duck.auto_machine.level = 1
	var machine = load("res://scenes/automatic_duck_workbench.tscn").instantiate()
	machine.name = "QAPurchasedMachine"
	get_tree().current_scene.add_child(machine)
	machine.global_position = Vector3(-24, 0.5, 24)
	var light = get_tree().get_first_node_in_group("light1")
	var chosen: Node3D = null
	for path in world_actions:
		var n = world_actions[path]
		if n.is_visible_in_tree() and n.has_method("start_crafting"):
			chosen = n
			break
	if chosen:
		var shapes = chosen.find_children("*", "CollisionShape3D", true, false)
		var target = shapes[0].global_position if not shapes.is_empty() else chosen.global_position
		_broadcast(["qa_control", str(get_tree().current_scene.get_path_to(chosen)), target, str(get_tree().current_scene.get_path_to(light))])
	await get_tree().create_timer(15.0).timeout
	print("[SYNC QA] HOST light=", light.visible, " sprint=", get_node("/root/GameState").upgrades.sprint.level)
	if "--hold-test" in OS.get_cmdline_user_args():
		var report = {"repeat_starts": craft_starts, "released": craft_holds.is_empty(), "stopped": not chosen.get("is_crafting"), "passed": craft_starts >= 2 and craft_holds.is_empty() and not chosen.get("is_crafting")}
		var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/hold-test.json"), FileAccess.WRITE)
		if file: file.store_string(JSON.stringify(report, "  "))
		print("[HOLD QA] ", JSON.stringify(report))

func _run_sync_guest_checks(path: String, target: Vector3, light_path: String):
	guest.set_physics_process(false)
	guest.global_position = target + Vector3(0, -1.2, 2.0)
	guest.camera.look_at(target)
	await get_tree().create_timer(0.5).timeout
	if "--hold-test" in OS.get_cmdline_user_args():
		_test_click(MOUSE_BUTTON_LEFT)
		await get_tree().create_timer(0.3).timeout
		_send(1, ["qa_tap_check", path])
		await get_tree().create_timer(0.2).timeout
		var press = InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		Input.parse_input_event(press)
		await get_tree().create_timer(8.0).timeout
		press = press.duplicate()
		press.pressed = false
		Input.parse_input_event(press)
		await get_tree().create_timer(4.0).timeout
	else:
		_test_click(MOUSE_BUTTON_LEFT)
		await get_tree().create_timer(12.0).timeout
	var light = get_tree().current_scene.get_node_or_null(NodePath(light_path))
	var purchased = get_tree().current_scene.get_node_or_null("QAPurchasedMachine")
	var report = {"guest_physics_hz": Engine.physics_ticks_per_second, "purchased_machine_synced": purchased != null, "light_on": light != null and light.is_visible_in_tree(), "intro_seen": seen_intro, "sprint_level": get_node("/root/GameState").upgrades.sprint.level, "jump_level": get_node("/root/GameState").upgrades.jump.level, "control_path": path, "control_feedback": info.text}
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/sync-test.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))
	print("[SYNC QA] GUEST ", JSON.stringify(report))
	guest.set_physics_process(true)
	if "--sfx-test" in OS.get_cmdline_user_args(): _sfx_checks.call_deferred()

func _send_shared_scenes(peer: int):
	var sent: Dictionary = peers[peer].get("shared_scenes", {})
	for node in get_tree().current_scene.get_children():
		if not node is Node3D or node is RigidBody3D or node is CharacterBody3D or node.scene_file_path.is_empty() or not _is_machine_scene(node): continue
		var path = str(node.name)
		if sent.get(path) == node.get_instance_id(): continue
		_send(peer, ["shared_scene", path, node.scene_file_path, node.global_transform])
		for key in presentation_known.get(peer, {}).keys():
			if key == path or str(key).begins_with(path + "/"): presentation_known[peer].erase(key)
		sent[path] = node.get_instance_id()
	peers[peer].shared_scenes = sent

func _spawn_shared_scene(path: String, scene: String, pose: Transform3D):
	if not allowed_scenes.has(scene) or path.contains("/") or path.contains(":") or path.contains(".."):
		return
	var world = get_tree().current_scene
	if world.get_node_or_null(NodePath(path)): return
	var packed = load(scene)
	if not packed is PackedScene: return
	var node = packed.instantiate()
	node.name = path
	if _is_control(node): node.set_meta("coop_control", path)
	for child in node.find_children("*", "Node3D", true, false):
		if _is_control(child): child.set_meta("coop_control", path + "/" + str(node.get_path_to(child)))
	_strip(node, true)
	world.add_child(node)
	node.global_transform = pose
	print("[COOP] Shared machine created: ", path)

func _queue_motion(node: Node3D, pose: Transform3D):
	if trading_sync.arcs.has(node.get_meta("coop_id",0)): return
	if part_motion.has(node.get_instance_id()): return
	if node.global_position.distance_to(pose.origin) > 8.0:
		node.global_transform = pose
	motion_targets[node.get_instance_id()] = [node, pose]

func _smooth_motion(delta: float):
	_smooth_parts(delta)
	var weight = 1.0 - exp(-25.0 * delta)
	for id in motion_targets.keys():
		var row = motion_targets[id]
		if not is_instance_valid(row[0]) or not row[0].is_inside_tree():
			motion_targets.erase(id)
			continue
		row[0].global_transform = row[0].global_transform.interpolate_with(row[1], weight)
		if row[0].global_transform.is_equal_approx(row[1]):
			row[0].global_transform = row[1]
			motion_targets.erase(id)

func _end_craft(peer: int):
	if not craft_holds.has(peer): return
	var node = craft_holds[peer].node
	craft_holds.erase(peer)
	if is_instance_valid(node) and node.get_meta("auto_crafter", null) == self:
		node.remove_meta("auto_crafter")
		if node.get("is_crafting"): node.stop_crafting()

func _update_craft_holds():
	for peer in craft_holds.keys():
		var hold = craft_holds[peer]
		var node = hold.node
		if not peers.has(peer) or not is_instance_valid(node) or not node.is_visible_in_tree() or Time.get_ticks_msec() > hold.expires:
			_end_craft(peer)
			continue
		if not _aims_at_control(peer, node):
			_end_craft(peer)
			continue
		if not node.get("is_crafting"):
			node.start_crafting()
			craft_starts += 1

func _queue_part_motion(node: Node3D, values: Array):
	var id = node.get_instance_id()
	var stamp = float(values[4])
	var prior = part_motion.get(id)
	if prior and stamp <= prior.samples.back().stamp: return
	if test_mode and node.name == "Cylinder" and node.get_parent().name == "ManualDuckWorkbench": qa_part_samples += 1
	machine_clock_offset = minf(machine_clock_offset, Time.get_ticks_msec() / 1000.0 - stamp)
	var pose: Transform3D = values[1]
	if not prior:
		node.transform = pose
		node.rotation = values[3]
		prior = {"node": node, "samples": []}
		part_motion[id] = prior
	motion_targets.erase(id)
	var rotation: Vector3 = values[3]
	if not prior.samples.is_empty():
		var last = prior.samples.back()
		var difference: Vector3 = rotation - last.raw_rotation
		var direction: Vector3 = prior.get("direction", Vector3.ZERO)
		for axis in range(3):
			# A cycle reset from a full turn to zero is the same orientation,
			# not a request to spin the wheel backwards through a whole cycle.
			if absf(difference[axis]) > PI and difference[axis] * direction[axis] < 0.0:
				difference[axis] = wrapf(difference[axis], -PI, PI)
			if absf(difference[axis]) > 0.00001: direction[axis] = difference[axis]
		prior.direction = direction
		rotation = last.rotation + difference
	if not prior.samples.is_empty() and stamp - prior.samples.back().stamp > 0.25:
		var baseline = prior.samples.back().duplicate()
		baseline.stamp = stamp - 0.05
		prior.samples.clear()
		prior.samples.append(baseline)
	prior.samples.append({"stamp": stamp, "position": pose.origin, "rotation": rotation, "raw_rotation": values[3], "scale": pose.basis.get_scale()})
	while prior.samples.size() > 12: prior.samples.pop_front()

func _smooth_parts(_delta: float):
	# Render a short, timestamped history instead of restarting an easing curve
	# on every arrival. Packet jitter no longer changes the machine's speed.
	var render_time = Time.get_ticks_msec() / 1000.0 - machine_clock_offset - MACHINE_BUFFER_SECONDS
	for id in part_motion.keys():
		var item = part_motion[id]
		var node = item.node
		if not is_instance_valid(node) or not node.is_inside_tree():
			part_motion.erase(id)
			continue
		var samples: Array = item.samples
		while samples.size() > 2 and samples[1].stamp <= render_time: samples.pop_front()
		var left = samples[0]
		var right = samples[1] if samples.size() > 1 else left
		# Bridge a short missing packet using the last measured motion. Never
		# predict indefinitely or extrapolate scale beyond the original animation.
		var interval = maxf(right.stamp - left.stamp, 0.001)
		var blend = clampf((render_time - left.stamp) / interval, 0.0, 1.0 + minf(0.075 / interval, 1.5))
		node.position = left.position.lerp(right.position, blend)
		var before_rotation = node.rotation
		# Unwrapped Euler angles retain the original wheel direction/full turns.
		node.rotation = left.rotation.lerp(right.rotation, blend)
		node.scale = left.scale.lerp(right.scale, minf(blend, 1.0))
		if test_mode and node.name == "Cylinder" and node.get_parent().name == "ManualDuckWorkbench" and not before_rotation.is_equal_approx(node.rotation): qa_part_frames += 1

func _sfx_checks():
	guest.global_position = Vector3(0, 0.15, 18)
	guest.velocity = Vector3.ZERO
	await get_tree().create_timer(1.0).timeout
	var initial = guest.footsteps_played
	guest.qa_walk = true
	await get_tree().create_timer(3.0).timeout
	guest.qa_walk = false
	await get_tree().create_timer(0.2).timeout
	var walking_steps = guest.footsteps_played - initial
	var stopped_count = guest.footsteps_played
	await get_tree().create_timer(1.0).timeout
	var report = {"audio_stream": guest.footstep_stream != null, "walking_steps": walking_steps,
		"silent_when_stopped": guest.footsteps_played == stopped_count,
		"machine_samples": qa_part_samples, "machine_animation_frames": qa_part_frames, "jittered_packets": qa_jitter_packets,
		"passed": guest.footstep_stream != null and walking_steps >= 2 and guest.footsteps_played == stopped_count and qa_part_frames > qa_part_samples}
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/sfx-motion-test.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))
	print("[SFX MOTION QA] ", JSON.stringify(report))

func _sync_machine_motion():
	var scope_start = Time.get_ticks_usec() if perf_enabled else 0
	var rows: Array = []
	var full_sync = Time.get_ticks_msec() >= machine_full_at
	if full_sync: machine_full_at = Time.get_ticks_msec() + 1000
	var stamp = Time.get_ticks_msec() / 1000.0
	for source in machine_motion_sources:
		var machine = source[1]
		var part = source[2]
		if not is_instance_valid(machine) or not is_instance_valid(part) or not part.is_inside_tree(): continue
		if not machine.is_visible_in_tree(): continue
		var values = [part.visible, part.transform, false, part.rotation]
		if not full_sync and machine_motion_sent.get(source[0]) == values and not (machine.has_method("start_crafting") and machine.get("is_crafting")): continue
		machine_motion_sent[source[0]] = values.duplicate()
		values.append(stamp)
		rows.append([source[0], "part", values])
		if rows.size() == 6:
			_broadcast(["machine_motion", rows], false)
			rows = []
	if not rows.is_empty(): _broadcast(["machine_motion", rows], false)
	if perf_enabled: perf_scopes["_sync_machine_motion"] = perf_scopes.get("_sync_machine_motion", 0) + Time.get_ticks_usec() - scope_start


func _publish_craft_activity():
	var operators: Dictionary = {}
	for peer in craft_holds:
		var machine = craft_holds[peer].node
		if is_instance_valid(machine) and machine.get("is_crafting"): operators[peer] = machine
	if not is_instance_valid(host_interact_ray):
		for ray in host_player.find_children("*", "RayCast3D", true, false):
			if ray.get_script() and ray.get_script().resource_path.get_file().get_basename() == "interact_ray":
				host_interact_ray = ray
				break
	if is_instance_valid(host_interact_ray):
		var machine = host_interact_ray.get("last_collider")
		if is_instance_valid(machine) and machine.has_method("start_crafting") and machine.get("is_crafting") and not machine.has_method("turn_on") and not machine.has_meta("auto_crafter"):
			operators[1] = machine
	var rows: Array = []
	var progress: Dictionary = {}
	for peer in operators:
		var machine = operators[peer]
		rows.append([peer, profiles.get(peer, profile if peer == 1 else Avatar.defaults()).name, machine.global_position])
		progress[peer] = 100.0 * float(machine.get("craft_progress")) / maxf(float(machine.get("active_craft_time")), 0.001)
	var other_rows: Array = []
	for row in rows:
		if row[0] != 1: other_rows.append(row)
	craft_hud.set_activity(other_rows, progress.get(1, -1.0))
	for peer in peers:
		if not peers[peer].ready: continue
		other_rows = []
		for row in rows:
			if row[0] != peer: other_rows.append(row)
		_send(peer, ["craft_activity", other_rows, progress.get(peer, -1.0)], false)

func _lobby_ui_checks():
	await get_tree().create_timer(7.0).timeout
	var key = InputEventKey.new()
	key.physical_keycode = KEY_F8
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().create_timer(0.5).timeout
	var stayed_hidden = not lobby.visible and role == "host" and net != null
	Input.parse_input_event(key)
	await get_tree().process_frame
	var reopened = lobby.visible
	key = key.duplicate()
	key.physical_keycode = KEY_ESCAPE
	Input.parse_input_event(key)
	await get_tree().create_timer(0.5).timeout
	var escape_closed = not lobby.visible and role == "host"
	_show_lobby()
	_hide_lobby()
	await get_tree().create_timer(0.5).timeout
	var button_closed = not lobby.visible and role == "host"
	var report = {"f8_stays_hidden": stayed_hidden, "f8_reopens": reopened, "escape_closes": escape_closed, "hide_button_stays_hidden": button_closed, "passed": stayed_hidden and reopened and escape_closed and button_closed}
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/lobby-ui.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))
	print("[LOBBY UI QA] ", JSON.stringify(report))
	get_tree().quit()

func _can_stick(body: RigidBody3D) -> bool:
	if not body.has_method("place") or int(get_node("/root/GameState").upgrades["sticky tools"].level) <= 0: return false
	for collider in body.get_colliding_bodies():
		if not collider.is_in_group("product") and not collider is CharacterBody3D: return true
	return false

func _restore_guest_contacts(body, monitor: bool, contacts: int):
	if not is_instance_valid(body): return
	body.contact_monitor = monitor
	body.max_contacts_reported = contacts

func _sticky_checks():
	await get_tree().create_timer(15.0).timeout
	if peers.is_empty(): return
	var peer = peers.keys()[0]
	var saved_net = net
	net = null
	var platform = StaticBody3D.new()
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(10, 0.5, 10)
	shape.shape = box
	platform.add_child(shape)
	get_tree().current_scene.add_child(platform)
	platform.global_position = Vector3(30, 10, 30)
	var body = load("res://scenes/bumper.tscn").instantiate()
	get_tree().current_scene.add_child(body)
	body.global_position = Vector3(30, 12, 30)
	body.contact_monitor = true
	body.max_contacts_reported = 8
	await get_tree().create_timer(2.0).timeout
	var id = body.get_instance_id()
	bodies[id] = body.scene_file_path
	var old_upgrade = get_node("/root/GameState").upgrades["sticky tools"].level
	get_node("/root/GameState").upgrades["sticky tools"].level = 1
	peers[peer].camera = Transform3D(Basis.IDENTITY, body.global_position + Vector3(0, 0.5, 2.0))
	peers[peer].pose_time = Time.get_ticks_msec()
	peers[peer].action_time = 0
	_action(peer, "grab", id)
	await get_tree().physics_frame
	var can_stick = _can_stick(body)
	_release(peer, false)
	await get_tree().process_frame
	await get_tree().physics_frame
	var stuck = body.freeze and body.placed
	peers[peer].action_time = 0
	_action(peer, "grab", id)
	var unplaced = not body.freeze and not body.placed
	get_node("/root/GameState").upgrades["sticky tools"].level = 0
	var locked = not _can_stick(body)
	_release(peer, false)
	await get_tree().process_frame
	var released_without_upgrade = not body.freeze
	get_node("/root/GameState").upgrades["sticky tools"].level = old_upgrade
	net = saved_net
	var report = {"contact_ready": can_stick, "placed": stuck, "pickup_unsticks": unplaced, "upgrade_required": locked and released_without_upgrade, "passed": can_stick and stuck and unplaced and locked and released_without_upgrade}
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/sticky-test.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))
	body.queue_free()
	platform.queue_free()

func _fit_guest_message(label: Label):
	if not is_instance_valid(label): return
	label.scale = Vector2.ONE
	label.pivot_offset = Vector2.ZERO
	await get_tree().process_frame
	if not is_instance_valid(label): return
	var available = get_viewport().get_visible_rect().size * 0.99
	var factor = minf(1.0, minf(available.x / maxf(label.size.x, 1.0), available.y / maxf(label.size.y, 1.0)))
	if factor < 1.0:
		label.pivot_offset = label.size / 2.0
		label.scale = Vector2.ONE * factor

func _fit_guest_messages():
	for label in shared_labels.values(): _fit_guest_message(label)

func _host_presentation_node(path: String):
	if path.begins_with("@"):
		var slash = path.find("/")
		var body = instance_from_id(int(path.substr(1, slash - 1)))
		return body.get_node_or_null(NodePath(path.substr(slash + 1))) if is_instance_valid(body) else null
	return get_tree().current_scene.get_node_or_null(NodePath(path))

func _session_log_path() -> String:
	var args = OS.get_cmdline_args()
	var index = args.find("--log-file")
	if index >= 0 and index + 1 < args.size():
		var path = str(args[index + 1])
		return path if path.is_absolute_path() else OS.get_executable_path().get_base_dir().path_join(path).simplify_path()
	var launcher_log = OS.get_executable_path().get_base_dir().path_join("../logs/play.log").simplify_path()
	return launcher_log if FileAccess.file_exists(launcher_log) else ProjectSettings.globalize_path("user://logs/godot.log")

func _open_session_log():
	OS.shell_open(_session_log_path())

func _test_log_menu():
	await get_tree().create_timer(4.0).timeout
	var report = {"path": _session_log_path(), "button": false}
	report.exists = FileAccess.file_exists(report.path)
	for button in panel.find_children("*", "Button", true, false):
		if button.text == "Open session log": report.button = true
	report.passed = report.exists and report.button
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/log-menu-test.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	panel.show()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/log-menu.png"))
	get_tree().quit()

func _request_magnets_off():
	if role == "host" and world_ready:
		_turn_all_magnets_off()
	elif role == "guest" and not pending_intro:
		_send(1, ["magnets_off"])

func _turn_all_magnets_off() -> int:
	if role != "host": return 0
	var count = 0
	for body in indexed_bodies.values():
		if not is_instance_valid(body) or not body.is_inside_tree() or not body.is_visible_in_tree(): continue
		if str(body.get("pool_id")).begins_with("tool_magnet") and body.has_method("remote_toggle"):
			body.remote_toggle(false)
			count += 1
	var message = "All magnets OFF (%d)." % count
	info.text = message
	_broadcast(["notice", message])
	return count

func _load_stress():
	await get_tree().create_timer(22.0).timeout
	var scene = load("res://scenes/duck.tscn")
	var ducks: Array = []
	for index in range(250):
		var body = scene.instantiate()
		get_tree().current_scene.add_child(body)
		body.global_position = Vector3(1000 + (index % 25) * 2, 50, 1000 + (index / 25) * 2)
		body.freeze = true
		ducks.append(body)
		if index % 25 == 0: await get_tree().process_frame
	await get_tree().create_timer(4.0).timeout
	var report = {"bodies": bodies.size(), "all_peers_sent": true}
	var duck = ducks[0]
	report.idle_callbacks_off = ducks.all(func(body): return not body.is_processing())
	duck.last_velocity = Vector3(10, 0, 0)
	duck._on_body_entered(get_tree().current_scene)
	report.impact_timer_started = duck.is_processing() and duck.collision_cooldown > 0.0
	await get_tree().create_timer(0.3).timeout
	report.impact_timer_finished = not duck.is_processing() and duck.collision_cooldown <= 0.0
	duck.collision_cooldown = 0.5
	duck.on_pool_spawn()
	report.pool_timer_started = duck.is_processing()
	await get_tree().create_timer(0.6).timeout
	report.pool_timer_finished = not duck.is_processing()
	duck.freeze = false
	duck.apply_central_impulse(Vector3(2, 0, 0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	report.physics_preserved = duck.is_physics_processing() and duck.linear_velocity.length() > 0.0
	duck.sleeping = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	report.sleeping_callback_off = not duck.is_physics_processing()
	duck.sleeping = false
	duck.apply_central_impulse(Vector3(2, 0, 0))
	duck._on_body_entered(get_tree().current_scene)
	report.wake_callback_restored = duck.is_physics_processing()
	for peer in peers:
		if peers[peer].ready: report.all_peers_sent = report.all_peers_sent and known[peer].size() == bodies.size()
	report.passed = report.bodies >= 250 and not report.values().has(false)
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/load-test.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))

func _guest_load_check():
	await get_tree().create_timer(35.0).timeout
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/load-guest.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"replicas": replicas.size(), "states": received_states, "passed": replicas.size() >= 250 and received_states > 100}, "  "))
