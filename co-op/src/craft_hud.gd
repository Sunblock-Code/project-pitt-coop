extends Control
var session: Node
var feed: PanelContainer
var caption: Label
var viewport: SubViewport
var camera: Camera3D
var progress: ProgressBar
var activity: Array = []
var expires = 0
var qa_started = false
var original_style_loaded = false

func _ready():
	process_priority = 1000
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	feed = PanelContainer.new()
	feed.position = Vector2(18, 45)
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style = StyleBoxFlat.new()
	style.bg_color = Color("142026")
	style.border_color = Color("dfbd4c")
	style.set_border_width_all(2)
	style.set_content_margin_all(2)
	feed.add_theme_stylebox_override("panel", style)
	add_child(feed)
	var video = Control.new()
	video.custom_minimum_size = Vector2(288, 150)
	video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	video.clip_contents = true
	feed.add_child(video)
	viewport = SubViewport.new()
	viewport.size = Vector2i(576, 300)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.audio_listener_enable_3d = false
	viewport.msaa_3d = get_viewport().msaa_3d
	add_child(viewport)
	camera = Camera3D.new()
	camera.fov = 62
	camera.near = 0.1
	viewport.add_child(camera)
	camera.current = true
	var picture = TextureRect.new()
	picture.texture = viewport.get_texture()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	video.add_child(picture)
	caption = Label.new()
	caption.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	caption.offset_left = 7
	caption.offset_right = -7
	caption.offset_top = 4
	caption.offset_bottom = 25
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.clip_text = true
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_size_override("font_size", 14)
	caption.add_theme_color_override("font_color", Color("efd04e"))
	caption.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	caption.add_theme_constant_override("shadow_offset_x", 2)
	caption.add_theme_constant_override("shadow_offset_y", 2)
	caption.add_theme_constant_override("outline_size", 2)
	caption.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	video.add_child(caption)
	progress = ProgressBar.new()
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(progress)
	feed.hide()
	progress.hide()

func set_activity(others: Array, own_percent: float):
	activity = others
	expires = Time.get_ticks_msec() + 750
	progress.visible = own_percent >= 0.0
	progress.value = clampf(own_percent, 0.0, 100.0)
	if "--craft-ui-test" in OS.get_cmdline_user_args() and not qa_started and (own_percent > 5.0 or not others.is_empty()):
		qa_started = true
		_qa_capture.call_deferred()

func _process(_delta):
	if session.role == "host" and session.world_ready:
		# Original machines share one global meter; prevent remote machines
		# from drawing or overwriting another player's progress.
		var original = get_tree().get_first_node_in_group("WorkbenchProgress")
		if original:
			if not original_style_loaded: adopt_original(original)
			original.hide()
	if Time.get_ticks_msec() > expires:
		activity = []
		progress.hide()
	var visible_now = not activity.is_empty() and not session.panel.visible and not session.character_editor.visible
	feed.visible = visible_now
	if not visible_now:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var row = activity[0]
	var actor = session.avatars.get(row[0])
	if not is_instance_valid(actor):
		feed.hide()
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	caption.text = str(row[1]).left(24) + " / WORKING"
	viewport.world_3d = actor.get_world_3d()
	var main_camera = get_viewport().get_camera_3d()
	if is_instance_valid(main_camera):
		camera.environment = main_camera.environment
		camera.attributes = main_camera.attributes
		camera.cull_mask = main_camera.cull_mask
	var focus = actor.global_position.lerp(row[2], 0.5) + Vector3.UP * 0.9
	camera.position = actor.global_position + actor.global_basis.x * 2.5 + actor.global_basis.z * 2.6 + Vector3.UP * 2.2
	camera.look_at(focus)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func _qa_capture():
	await get_tree().create_timer(1.0).timeout
	var report = {"font": progress.get_theme_font("font").resource_path, "font_size": progress.get_theme_font_size("font_size"), "bar_size": str(progress.size), "original_style_loaded": original_style_loaded, "role": session.role, "own_percentage_visible": progress.visible, "own_percentage": progress.value, "other_player_preview": feed.visible, "activity_count": activity.size(), "money_text": session.guest_money.text if is_instance_valid(session.guest_money) else get_tree().get_first_node_in_group("HUD").get_node("Money").text}
	if session.role == "guest":
		var messages_fit = true
		var available = get_viewport().get_visible_rect().size
		for label in session.shared_labels.values():
			if label.visible:
				var rendered_size = label.size * label.scale
				messages_fit = messages_fit and rendered_size.x <= available.x and rendered_size.y <= available.y
		var names_present = not session.avatars.is_empty()
		for avatar in session.avatars.values(): names_present = names_present and is_instance_valid(avatar.tag) and not avatar.tag.text.is_empty()
		report.guest_messages_fit = messages_fit
		report.player_names_present = names_present
		report.item_name = session.interaction_hud.title.text
		report.item_hint = session.interaction_hud.controls.text
		report.item_font_size = session.interaction_hud.title.get_theme_font_size("font_size")
		report.controls_font_size = session.interaction_hud.controls.get_theme_font_size("font_size")
		report.lobby_has_roster = session.lobby_roster.text.contains("CREW MANIFEST")
		report.guest_text_passed = messages_fit and names_present and original_style_loaded and progress.visible and report.item_hint.contains("Craft") and report.money_text == "12,345$" and report.item_font_size == 32 and report.controls_font_size == 16
	var folder = OS.get_executable_path().get_base_dir().path_join("../logs/")
	var file = FileAccess.open(folder + "craft-ui-" + session.role + ".json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(folder + "craft-ui-" + session.role + ".png")
	print("[CRAFT UI QA] ", JSON.stringify(report))

func adopt_original(original: Node):
	if original_style_loaded or not original is ProgressBar: return
	var value_before = progress.value
	var was_visible = progress.visible
	progress.queue_free()
	# Clone the authored control, including its original theme and geometry.
	# DUPLICATE_GROUPS is deliberately excluded: only the original host meter
	# belongs to WorkbenchProgress, while this one stays operator-local.
	progress = original.duplicate(0)
	progress.set_script(null)
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	progress.add_theme_color_override("font_color", Color.WHITE)
	add_child(progress)
	progress.value = value_before
	progress.visible = was_visible
	original_style_loaded = true
