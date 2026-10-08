extends Node
var session: Node
var report: Dictionary = {}
var directory: String

func _ready():
	directory = OS.get_executable_path().get_base_dir().path_join("../logs")
	run.call_deferred()

func capture(name):
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(directory.path_join(name + ".png"))

func button(pressed):
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_MIDDLE
	event.pressed = pressed
	Input.parse_input_event(event)

func run():
	await get_tree().create_timer(29.0).timeout
	var progress = session.progress_menu
	if session.role == "host":
		var camera = session.host_player.get_node("CameraPivot/MainCamera")
		var item = RigidBody3D.new()
		item.freeze = true
		add_child(item)
		var middle = InputEventMouseButton.new()
		middle.button_index = MOUSE_BUTTON_MIDDLE
		middle.pressed = true
		var old_pick = camera.picked_object
		var old_equip = camera.equipped_item
		camera.picked_object = item
		report.host_carry_passes_middle_input = not session.emotes.handle_input(middle) and not session.emotes.visible
		camera.picked_object = old_pick
		camera.equipped_item = item
		report.host_equipped_passes_middle_input = not session.emotes.handle_input(middle) and not session.emotes.visible
		camera.equipped_item = old_equip
		item.queue_free()
		progress.snapshot()
		var game = get_node("/root/GameState")
		get_node("/root/GameProgression").current_phase = 1
		progress.hole.current_phase = 1
		progress.hole.phase_nutrition_total = 1875.0
		game.money = BigInt.from_int(30)
		game.tools.broom.enabled = true
		game.tools.broom.enabled_levels = [true, true, false]
		var before = progress.snapshot()
		report.phase_remaining = before.tier.contains("5,625") and before.tier.contains("25%")
		game.money = BigInt.from_int(20)
		var after = progress.snapshot()
		report.spending_preserves_feed = before.tier == after.tier
		report.tool_cash_gap = after.purchases.any(func(row): return row.name == "Broom level 2" and row.left == 2730)
		report.box_requirement = after.unlocks.any(func(row): return row.name == "Box" and row.requirement.contains("8"))
		progress.receive(after)
		await get_tree().create_timer(10.0).timeout
		var peer = session.peers.keys()[0]
		report.guest_emote_received = session.emotes.last_sent.has(peer)
		report.guest_animation_received = session.avatars[peer].emote_id == 2
		button(true)
		await get_tree().process_frame
		report.host_wheel_opens = session.emotes.visible
		var motion = InputEventMouseMotion.new()
		motion.position = get_viewport().get_visible_rect().size / 2 + Vector2.from_angle(-PI / 2 + TAU / session.emotes.NAMES.size()) * 150
		if DisplayServer.get_name() == "headless": session.emotes.handle_input(motion)
		else: Input.parse_input_event(motion)
		await get_tree().process_frame
		await capture("host-wheel")
		button(false)
		await get_tree().create_timer(0.2).timeout
		report.host_wheel_releases = not session.emotes.visible and session.local_avatar.emote_id == 1
	else:
		await get_tree().create_timer(3.0).timeout
		report.synced_phase = progress.state.tier.contains("5,625")
		report.synced_cash = progress.state.money == "20"
		report.synced_tool_gap = progress.state.purchases.any(func(row): return row.name == "Broom level 2" and row.left == 2730)
		progress.open()
		await get_tree().create_timer(0.3).timeout
		report.menu_visible = progress.active() and progress.text_box.text.contains("$2,730 more needed")
		await capture("progress")
		var escape = InputEventKey.new()
		escape.physical_keycode = KEY_ESCAPE
		escape.pressed = true
		Input.parse_input_event(escape)
		await get_tree().process_frame
		report.escape_closes = not progress.active()
		session.guest_held_id = 999
		var middle = InputEventMouseButton.new()
		middle.button_index = MOUSE_BUTTON_MIDDLE
		middle.pressed = true
		report.guest_carry_passes_middle_input = not session.emotes.handle_input(middle)
		report.carry_preserves_rotate = not session.emotes.available()
		button(true)
		await get_tree().process_frame
		report.carry_blocks_wheel = not session.emotes.visible
		button(false)
		session.guest_held_id = 0
		session.tool_equipped = true
		report.guest_equipped_passes_middle_input = not session.emotes.handle_input(middle)
		report.equipped_blocks_wheel = not session.emotes.available()
		session.tool_equipped = false
		session.guest.craft_pressed = true
		report.pending_grab_blocks_wheel = not session.emotes.available()
		session.guest.craft_pressed = false
		button(true)
		await get_tree().process_frame
		session.tool_equipped = true
		await get_tree().process_frame
		await get_tree().process_frame
		report.late_equip_closes_wheel = not session.emotes.visible
		button(false)
		session.tool_equipped = false
		button(true)
		await get_tree().process_frame
		report.wheel_opens = session.emotes.visible
		var motion = InputEventMouseMotion.new()
		motion.position = get_viewport().get_visible_rect().size / 2 + Vector2.from_angle(-PI / 2 + 2 * TAU / session.emotes.NAMES.size()) * 150
		if DisplayServer.get_name() == "headless": session.emotes.handle_input(motion)
		else: Input.parse_input_event(motion)
		await get_tree().process_frame
		await capture("wheel")
		button(false)
		await get_tree().create_timer(0.4).timeout
		report.wheel_closes = not session.emotes.visible
		report.dance_playing = session.local_avatar.emote_id == 2 and session.local_avatar.emote_left > 0
		session.view_rig.set_active(true)
		await get_tree().create_timer(0.3).timeout
		await capture("dance")
		await get_tree().create_timer(9.0).timeout
		report.host_emote_received = session.avatars[1].emote_id == 1
		report.emote_finishes = session.local_avatar.emote_left == 0
	report.passed = not report.values().has(false)
	FileAccess.open(directory.path_join("progress-emote-" + session.role + ".json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("[PROGRESS EMOTE QA] ", report)
