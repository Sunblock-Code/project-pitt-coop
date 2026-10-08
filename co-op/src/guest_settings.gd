extends Node

var session: Node
var manager: Node
var initialized = false

func initialize():
	manager = get_node("/root/MenuManager")
	manager.current_menu = null
	manager.previous_menu = null
	manager.menu_stack.clear()
	manager.game_paused = false
	manager.process_mode = Node.PROCESS_MODE_ALWAYS
	get_node("/root/InputManager").process_mode = Node.PROCESS_MODE_ALWAYS
	if not manager.settings_changed.is_connected(protect_save): manager.settings_changed.connect(protect_save)
	initialized = true
	if session.test_mode and "--settings-test" in OS.get_cmdline_user_args(): run_checks.call_deferred()

func active() -> bool:
	return initialized and session.role == "guest" and is_instance_valid(manager.current_menu)

func protect_save():
	if session.role != "guest": return
	get_node("/root/SaveManager").save_locked = true
	get_node("/root/SaveManager").autosave_enabled = false

func open():
	if not initialized or active(): return
	session.guest.craft_pressed = false
	session._send(1, ["craft_stop"])
	session._send(1, ["grab_release"])
	manager.open_options_menu()
	keep_running()

func keep_running():
	# Native menus own their local stack, but never stop the shared simulation.
	get_tree().paused = false
	session.hud.visible = not active() and not session.guest_terminal.active()
	if active():
		manager.current_menu.process_mode = Node.PROCESS_MODE_ALWAYS
		manager.current_menu.layer = 100
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	protect_save()

func _process(_delta):
	if initialized and session.role == "guest": keep_running()

func escape():
	var event = InputEventKey.new()
	event.physical_keycode = KEY_ESCAPE
	event.keycode = KEY_ESCAPE
	event.pressed = true
	if active(): manager.current_menu._unhandled_input(event)
	else: session._input(event)

func run_checks():
	await get_tree().create_timer(28.0).timeout
	escape()
	await get_tree().create_timer(0.3).timeout
	var report = {"escape_opens": active() and manager.current_menu.visible, "unpaused": not get_tree().paused}
	var packets = session.received_states
	var options = manager.current_menu
	options._on_controls_pressed()
	await get_tree().create_timer(0.3).timeout
	var controls = manager.current_menu
	report.hold_default = controls.grab_mode.selected == 0 and session.grab_settings.hold_to_grab
	controls.grab_mode.select(1)
	controls.grab_mode.item_selected.emit(1)
	report.press_selectable = not session.grab_settings.hold_to_grab
	controls.spin_box_sensitivity.value = 0.75
	controls.check_box_y.button_pressed = true
	await get_tree().process_frame
	var cfg = ConfigFile.new()
	report.controls_saved = cfg.load("user://settings.cfg") == OK and is_equal_approx(float(cfg.get_value("controls", "mouse_sensitivity", 0)), 0.75) and cfg.get_value("controls", "invert_y", false)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/guest-settings.png"))
	escape()
	await get_tree().process_frame
	report.escape_back = manager.current_menu == options
	options._on_visuals_pressed()
	await get_tree().create_timer(0.3).timeout
	manager.current_menu.fov_slider.value = 95
	await get_tree().create_timer(0.6).timeout
	report.fov_applied = is_equal_approx(session.guest.render_camera.fov, 95.0)
	escape()
	await get_tree().process_frame
	options._on_audio_pressed()
	await get_tree().create_timer(0.3).timeout
	report.audio_opened = manager.current_menu != options and manager.current_menu.visible
	manager.current_menu.master_slider.value = 35
	await get_tree().create_timer(0.7).timeout
	report.audio_applied = is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))), 0.35)
	report.network_running = session.received_states > packets
	escape()
	await get_tree().process_frame
	escape()
	await get_tree().create_timer(0.2).timeout
	report.closed = not active() and not get_tree().paused and (DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	report.save_protected = get_node("/root/SaveManager").save_locked and not get_node("/root/SaveManager").autosave_enabled
	var grab_test = load("res://coop/grab_mode_test.gd").new()
	grab_test.session = session
	add_child(grab_test)
	report.grab_modes = await grab_test.guest_checks()
	report.passed = not report.values().has(false) and report.grab_modes.passed
	grab_test.queue_free()
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/settings-test.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))
