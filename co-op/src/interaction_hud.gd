extends Node

const OUTLINE_PATHS = {
  "anomaly": [
    "MeshInstance3D"
  ],
  "automatic_cash_workbench": [
    "Outlines"
  ],
  "automatic_duck_workbench": [
    "Outlines",
    "Outlines/Outline3",
    "Outlines/Outline5",
    "Outlines/Outline2"
  ],
  "basketball_hoop": [
    "MeshInstance3D"
  ],
  "box": [
    "MeshInstance3D2"
  ],
  "box_carry_2": [
    "MeshInstance3D6"
  ],
  "box_cushion_3": [
    "MeshInstance3D6"
  ],
  "broom": [
    "MeshInstance3D"
  ],
  "bumper": [
    "MeshInstance3D3"
  ],
  "candy": [
    "MeshInstance3D"
  ],
  "cannon": [
    "MeshInstance3D"
  ],
  "cash_register": [
    "CashRegisterBody/MeshInstance3D",
    "CashRegisterRack/MeshInstance3D"
  ],
  "crate": [
    "MeshInstance3D"
  ],
  "crown": [
    "MeshInstance3D"
  ],
  "disco_ball": [
    "RotatingPivot/MeshInstance3D"
  ],
  "duck": [
    "MeshInstance3D"
  ],
  "fan": [
    "MeshInstance3D"
  ],
  "fan_3": [
    "MeshInstance3D"
  ],
  "feed_camera": [
    "Outline"
  ],
  "feed_screen": [
    "Outline"
  ],
  "flat_duck": [
    "Meshes/MeshInstance3D"
  ],
  "flat_duck_luck": [
    "Meshes/MeshInstance3D"
  ],
  "fuse": [
    "MeshInstance3D"
  ],
  "golden_duck_statue": [
    "MeshInstance3D"
  ],
  "golf_club": [
    "Outline"
  ],
  "gravity_inverter": [
    "MeshInstance3D"
  ],
  "keycard": [
    "MeshInstance3D"
  ],
  "keypad_button": [
    "MeshInstance3D"
  ],
  "lucky_duck": [
    "MeshInstance3D"
  ],
  "magnet": [
    "MeshInstance3D"
  ],
  "manual_cash_workbench": [
    "Outlines"
  ],
  "mining_ore": [
    "MeshInstance3D"
  ],
  "orbit_tool": [
    "MeshInstance3D"
  ],
  "panel": [
    "MeshInstance3D2"
  ],
  "panel2": [
    "MeshInstance3D2"
  ],
  "pickaxe": [
    "MeshInstance3D"
  ],
  "pinata": [
    "MeshInstance3D"
  ],
  "piston": [
    "MeshInstance3D"
  ],
  "portal": [
    "MeshInstance3D"
  ],
  "press": [
    "MeshInstance3D"
  ],
  "proxy_intern": [
    "Outline"
  ],
  "qa_arm": [
    "Outline"
  ],
  "remote": [
    "Outline"
  ],
  "roomba": [
    "MeshInstance3D"
  ],
  "shift_scheduler": [
    "Outline"
  ],
  "speed_radar": [
    "MeshInstance3D"
  ],
  "sphere": [
    "MeshInstance3D2"
  ],
  "sponge": [
    "MeshInstance3D"
  ],
  "spring_pad": [
    "MeshInstance3D"
  ],
  "stat_sign": [
    "Outline"
  ],
  "torch_light": [
    "MeshInstance3D"
  ],
  "tractor_beam": [
    "MeshInstance3D"
  ],
  "upgrade_terminal": [
    "MeshInstance3D2"
  ],
  "uv_lamp": [
    "MeshInstance3D"
  ],
  "vacuum": [
    "MeshInstance3D"
  ],
  "wodd_crate": [
    "MeshInstance3D"
  ],
  "workbench": [
    "Outline1",
    "Outline2",
    "Outline3",
    "Outline3",
    "Outline2"
  ]
}

var session: Node
var title: Label
var controls: Label
var target: Node3D
var outlines: Array = []
var qa_captured = false
var host_style: Dictionary = {}

func copy_labels(world: Node):
	for label_name in ["interact_label", "controls_label"]:
		var original = world.find_child(label_name, true, false)
		var label = original.duplicate(0) if original is Label else Label.new()
		label.set_script(null)
		if original is Label:
			label.add_theme_font_override("font", load("res://assets/PublicPixel-rv0pA.ttf"))
			label.add_theme_font_size_override("font_size", original.get_theme_font_size("font_size"))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.hide()
		session.hud.add_child(label)
		if label_name == "interact_label": title = label
		else: controls = label

func _process(_delta):
	var next: Node3D = null
	if session.role == "guest" and is_instance_valid(session.guest) and not session.pending_intro and not session.panel.visible and not session.lobby.visible and not session.character_editor.visible and not session.guest_terminal.active():
		if session.replicas.has(session.guest_held_id):
			next = session.replicas[session.guest_held_id]
		else:
			var camera = session.view_rig.camera if is_instance_valid(session.view_rig) and session.view_rig.active else session.guest.camera
			var query = PhysicsRayQueryParameters3D.create(camera.global_position, camera.global_position - camera.global_basis.z * 5.0, 0xFFFFFFFF)
			query.exclude = session.duck_pass.rids()
			var hit = session.guest.get_world_3d().direct_space_state.intersect_ray(query)
			if hit:
				var node = hit.collider
				while node and node != get_tree().current_scene:
					if node.has_meta("coop_title"):
						next = node
						break
					node = node.get_parent()
	if next != target or not is_instance_valid(target):
		for outline in outlines:
			if is_instance_valid(outline): outline.hide()
		outlines.clear()
		target = next
		if is_instance_valid(target):
			for child in target.find_children("*", "Node3D", true, false):
				if child.has_meta("coop_outline"): outlines.append(child)
	if not is_instance_valid(target):
		title.hide()
		controls.text = session.panel_rack.hint(null) if session.role == "guest" and not session.panel.visible and not session.lobby.visible and not session.guest_terminal.active() else ""
		_layout_controls()
		controls.visible = not controls.text.is_empty()
		return
	var grabbed = target.get_meta("coop_id", 0) == session.guest_held_id and session.guest_held_id != 0
	for outline in outlines:
		outline.show()
		if outline is MeshInstance3D and outline.material_override is StandardMaterial3D:
			outline.material_override.albedo_color = session.Avatar.HOLD_COLORS[session.profile.get("holding",0)] if grabbed else Color.WHITE
	title.text = target.get_meta("coop_title", "")
	title.visible = not title.text.is_empty()
	var hints: Array[String] = []
	if session.remote_tools.equipped_guest():
		hints.append(session.remote_tools.hint())
	elif session.tool_equipped:
		hints.append("[%s] Unequip | %s" % [get_node("/root/InputManager").get_action_key_name("equip"), "[LMB / RMB] Sweep / Slide players" if session.broom_players.is_broom(target) else "[LMB] Toggle"])
	elif grabbed:
		if target.get_meta("coop_fuse", false): hints.append(session.fuse_sync.hint())
		var upgrades = get_node("/root/GameState").upgrades
		var snap = session.held_controls.guest_snap
		var drop_key = "Release LMB" if session.grab_settings.hold_to_grab else "LMB"
		hints.append(_hint("CTRL_DROP_SNAP", drop_key) if snap else "[%s] Place / Stick" % drop_key if session.sticky_ready else _hint("CTRL_DROP", drop_key))
		if int(upgrades["throw"].level) > 0: hints.append(_hint("CTRL_THROW", "RMB"))
		if not snap and int(upgrades.snap_grid.level) > 0: hints.append(_hint("CTRL_SNAP_MODE", get_node("/root/InputManager").get_action_key_name("rotate")))
		hints.append(_hint("CTRL_FREE_ROTATE", "MMB"))
		if int(upgrades.reset_rotation.level) > 0:
			hints.append(_hint("CTRL_RESET_ROTATION", "G"))
			hints.append(_hint("CTRL_DISTANCE", "Scroll"))
		if snap:
			hints.append(_hint("CTRL_SNAP_TIER", get_node("/root/InputManager").get_action_key_name("action")))
			hints.append(_hint("CTRL_EXIT_SNAP", get_node("/root/InputManager").get_action_key_name("rotate")))
		elif target.get_meta("coop_equipable", false) and int(upgrades.equip.level) > 0: hints.append("[%s] Equip" % get_node("/root/InputManager").get_action_key_name("equip"))
		if not snap and target.get_meta("coop_placeable", false) and int(upgrades["sticky tools"].level) > 0 and not session.sticky_ready:
			hints.append("Touch a surface to stick")
	elif target.get_meta("coop_grabbable", false): hints.append(_hint("CTRL_GRAB", "Hold LMB" if session.grab_settings.hold_to_grab else "LMB"))
	elif target.get_meta("coop_manual", false): hints.append(_hint("CTRL_CRAFT", "LMB"))
	elif target.get_meta("coop_toggle", false): hints.append(_hint("CTRL_TOGGLE", "LMB"))
	elif target.get_meta("coop_usable", false): hints.append(_hint("CTRL_INTERACT", get_node("/root/InputManager").get_action_key_name("interact")))
	if not grabbed and target.get_meta("coop_equipable", false) and int(get_node("/root/GameState").upgrades.equip.level) > 0:
		hints.append("[%s] Equip" % get_node("/root/InputManager").get_action_key_name("equip"))
	if target.get_meta("coop_interact_tool", false) and not session.remote_tools.equipped_guest():
		var interact_hint = _hint("CTRL_INTERACT", get_node("/root/InputManager").get_action_key_name("interact"))
		if not hints.has(interact_hint): hints.append(interact_hint)
	if not grabbed and not session.tool_equipped and target.get_meta("coop_tunable", false):
		hints.append(_hint("CTRL_TUNE", get_node("/root/InputManager").get_scroll_pair_name()))
	var rack_hint = session.panel_rack.hint(target)
	if not rack_hint.is_empty(): hints.append(rack_hint)
	controls.text = " | ".join(hints)
	_layout_controls()
	controls.visible = not hints.is_empty()
	if session.test_mode and "--interaction-ui-test" in OS.get_cmdline_user_args() and not qa_captured and target.get_meta("coop_id", 0) == session.test_id and not grabbed:
		qa_captured = true
		_capture_qa.call_deferred()

func _layout_controls():
	controls.autowrap_mode = TextServer.AUTOWRAP_OFF
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var natural = controls.get_minimum_size()
	var viewport_size = get_viewport().get_visible_rect().size
	var fit = minf(1.0, (viewport_size.x - 32.0) / maxf(natural.x, 1.0))
	controls.size = natural
	controls.scale = Vector2.ONE * fit
	controls.position = Vector2((viewport_size.x - natural.x * fit) * 0.5, viewport_size.y - natural.y * fit - 16.0)

func _capture_qa():
	await get_tree().process_frame
	var visible_outlines = 0
	for outline in outlines:
		if is_instance_valid(outline) and outline.is_visible_in_tree(): visible_outlines += 1
	var report = {"title": title.text, "controls": controls.text, "outlines": visible_outlines, "title_font": title.get_theme_font("font").resource_path, "title_size": title.get_theme_font_size("font_size"), "controls_size": controls.get_theme_font_size("font_size"), "host_style": host_style, "passed": title.visible and controls.visible and visible_outlines > 0 and controls.text.contains("LMB")}
	var directory = OS.get_executable_path().get_base_dir().path_join("../logs")
	var file = FileAccess.open(directory.path_join("interaction-ui.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(directory.path_join("interaction-ui.png"))

func _hint(key: String, button: String) -> String:
	return tr(key).replace("{key}", button)

static func preserve_outlines(node: Node):
	var script = node.get_script()
	if not script: return
	var key = script.resource_path.get_file().get_basename()
	for path in OUTLINE_PATHS.get(key, []):
		var outline = node.get_node_or_null(NodePath(path))
		if outline is Node3D: outline.set_meta("coop_outline", true)
	for property in node.get_property_list():
		if property.name == "outlines_group":
			var group = node.get("outlines_group")
			for child in node.find_children("*", "Node3D", true, false):
				if child.is_in_group(group): child.set_meta("coop_outline", true)

# Share appearance only. Aimed item names, hints and visibility remain local.
static func read_style(world: Node) -> Dictionary:
	var result = {}
	for label_name in ["interact_label", "controls_label"]:
		var label = world.find_child(label_name, true, false)
		if not label is Label: continue
		result[label_name] = {"font": label.get_theme_font("font").resource_path, "size": label.get_theme_font_size("font_size"), "outline_size": label.get_theme_constant("outline_size"), "shadow_x": label.get_theme_constant("shadow_offset_x"), "shadow_y": label.get_theme_constant("shadow_offset_y"), "color": label.get_theme_color("font_color"), "shadow_color": label.get_theme_color("font_shadow_color"), "outline_color": label.get_theme_color("font_outline_color")}
	return result

func apply_style(style: Dictionary):
	host_style = style
	for key in ["interact_label", "controls_label"]:
		if not style.has(key): continue
		var label = title if key == "interact_label" else controls
		var settings = style[key]
		if str(settings.font).begins_with("res://") and ResourceLoader.exists(settings.font):
			var font = load(settings.font)
			if font is Font: label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", int(settings.size))
		label.add_theme_constant_override("outline_size", int(settings.outline_size))
		label.add_theme_constant_override("shadow_offset_x", int(settings.shadow_x))
		label.add_theme_constant_override("shadow_offset_y", int(settings.shadow_y))
		label.add_theme_color_override("font_color", settings.color)
		label.add_theme_color_override("font_shadow_color", settings.shadow_color)
		label.add_theme_color_override("font_outline_color", settings.outline_color)
