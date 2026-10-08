extends Node
var session: Node
var hole: Node
var timer = 0.0
var state: Dictionary = {}
var summary: Label
var panel: PanelContainer
var text_box: RichTextLabel

func _ready():
	if "--progress-emote-test" in OS.get_cmdline_user_args():
		var check = load("res://coop/progress_emote_test.gd").new()
		check.session = session
		add_child(check)

func active() -> bool:
	return is_instance_valid(panel) and panel.visible

func number(value) -> String:
	return get_node("/root/GameState").format_big_number(value)

func milestone_name(id: String) -> String:
	return id.trim_prefix("unlock_").replace("_lvl", " level ").replace("_", " ").capitalize()

func requirement(m: Dictionary, unlocks: Node) -> String:
	match m.get("type", ""):
		"stat_threshold":
			var raw = unlocks._get_stat(m.stat)
			var value = raw.to_float() if raw is Object and raw.has_method("to_float") else float(raw) if raw != null else 0.0
			var left = maxi(0, ceili(float(m.threshold) - value))
			var stat = str(m.stat).replace("products_consumed.", "fed ").replace("products_crafted.", "crafted ").replace("_", " ")
			if m.stat == "total_money_gained": return "$%s more lifetime earnings" % number(left)
			if m.stat == "money": return "$%s more available cash" % number(left)
			return "%s more %s (%s / %s)" % [number(left), stat, number(floor(value)), number(m.threshold)]
		"combined_stat_threshold":
			var total = 0.0
			var names: Array[String] = []
			for entry in m.stats:
				var raw = unlocks._get_stat(entry.stat)
				total += (raw.to_float() if raw is Object and raw.has_method("to_float") else float(raw)) * entry.get("weight", 1.0)
				names.append(str(entry.stat).replace("products_consumed.", "fed ").replace("_", " "))
			return "%s more combined: %s" % [number(maxi(0, ceili(m.threshold - total))), ", ".join(names)]
		"phase_reached": return "Reach warehouse tier %d" % m.phase
		"floor_product_count": return "%s products on the floor" % number(m.threshold)
		"group_all_flagged": return "Complete all %s" % str(m.group).replace("_", " ")
		"group_flagged_count": return "Complete %s %s" % [number(m.threshold), str(m.group).replace("_", " ")]
		"state_flag": return "Complete: " + str(m.flag).replace("_", " ")
	return "Complete the game's prerequisite"

func snapshot() -> Dictionary:
	if not is_instance_valid(hole):
		for candidate in get_tree().current_scene.find_children("*", "Node3D", true, false):
			if candidate.has_method("get_phase_progress"):
				hole = candidate
				break
	var phase = int(get_node("/root/GameProgression").current_phase)
	var tier = "Leave the elevator to begin"
	if is_instance_valid(hole) and hole.NUTRITION_PER_RADIUS_UNIT.has(phase):
		var bounds = hole.PHASE_RADIUS_RANGES[phase]
		var needed = (bounds.max - bounds.min) / 0.1 * hole.NUTRITION_PER_RADIUS_UNIT[phase]
		var remaining = maxi(0, ceili(needed - hole.phase_nutrition_total))
		tier = "TIER %d > %d: %d%%\nFEED VALUE LEFT: %s" % [phase, phase + 1, floori(hole.get_phase_progress() * 100), number(remaining)]
	elif phase >= 5: tier = "FINAL TIER REACHED"
	var unlocks = get_node("/root/UnlockManager")
	var upcoming: Array = []
	for id in unlocks.milestones:
		if id in unlocks.unlocked_milestones: continue
		var m: Dictionary = unlocks.milestones[id]
		var blocked: Array[String] = []
		for required in m.get("requires", []):
			if required not in unlocks.unlocked_milestones: blocked.append(milestone_name(required))
		if phase < int(m.get("min_phase", 0)): blocked.append("Warehouse tier %d" % m.min_phase)
		upcoming.append({"name": milestone_name(id), "requirement": requirement(m, unlocks), "progress": unlocks.get_progress(id), "blocked": ", ".join(blocked)})
	upcoming.sort_custom(func(a, b):
		if a.blocked.is_empty() != b.blocked.is_empty(): return a.blocked.is_empty()
		return a.progress > b.progress)
	var game = get_node("/root/GameState")
	var purchases: Array = []
	for category in ["upgrades", "tools"]:
		var items: Dictionary = game.get(category)
		for key in items:
			var item: Dictionary = items[key]
			var prices: Array = item.get("buy_prices" if category == "tools" else "prices", [])
			var levels: Array = item.get("enabled_levels", [])
			for level in range(prices.size()):
				if category == "upgrades" and level != int(item.get("level", 0)): continue
				if not item.get("enabled", false) and not levels.has(true): continue
				if not levels.is_empty() and (level >= levels.size() or not levels[level]): continue
				var cost = int(prices[level])
				var left = 0 if game.money.compare_int(cost) >= 0 else maxi(0, cost - int(game.money.to_float()))
				purchases.append({"name": str(key).replace("_", " ").capitalize() + " level %d" % (level + 1), "cost": cost, "left": left})
	purchases.sort_custom(func(a, b): return a.left < b.left)
	return {"tier": tier, "unlocks": upcoming, "purchases": purchases, "money": game.format_big_number(game.money)}

func receive(value: Dictionary):
	state = value
	if is_instance_valid(summary): summary.text = state.tier + "\nF8 > PROGRESS / NEXT UNLOCKS"
	if active(): refresh()

func _process(delta):
	if not is_instance_valid(session.hud): return
	if not is_instance_valid(summary):
		summary = Label.new()
		summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
		summary.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		summary.offset_left = -500
		summary.offset_right = -18
		summary.offset_top = 88
		summary.offset_bottom = 153
		summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		summary.add_theme_font_override("font", load("res://assets/PublicPixel-rv0pA.ttf"))
		summary.add_theme_font_size_override("font_size", 12)
		summary.add_theme_color_override("font_color", Color("efca50"))
		summary.add_theme_color_override("font_shadow_color", Color.BLACK)
		summary.add_theme_constant_override("shadow_offset_x", 2)
		summary.add_theme_constant_override("shadow_offset_y", 2)
		session.hud.add_child(summary)
	var playing = session.role == "host" and session.world_ready or session.role == "guest" and not session.pending_intro
	summary.visible = playing and not active() and not session.panel.visible and not session.lobby.visible and not session.character_editor.visible and not session.guest_terminal.active() and not session.guest_settings.active() and get_node("/root/MenuManager").current_menu == null
	timer += delta
	if session.role != "host" or not playing or timer < 1.0: return
	timer = 0.0
	var value = snapshot()
	if value != state: receive(value)
	for peer in session.peers:
		if session.peers[peer].ready and session.peers[peer].get("progress_state", {}) != value:
			session._send(peer, ["progress_state", value])
			session.peers[peer].progress_state = value.duplicate(true)

func open():
	if not is_instance_valid(panel):
		panel = PanelContainer.new()
		panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		panel.offset_left = 55
		panel.offset_right = -55
		panel.offset_top = 50
		panel.offset_bottom = -50
		panel.theme = session.panel.theme
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.025, 0.035, 0.04, 0.98)
		style.border_color = Color("efca50")
		style.set_border_width_all(2)
		style.set_content_margin_all(24)
		panel.add_theme_stylebox_override("panel", style)
		session.hud.add_child(panel)
		var box = VBoxContainer.new()
		panel.add_child(box)
		text_box = RichTextLabel.new()
		text_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
		text_box.add_theme_font_override("normal_font", load("res://assets/PublicPixel-rv0pA.ttf"))
		text_box.add_theme_font_size_override("normal_font_size", 15)
		text_box.add_theme_constant_override("line_separation", 5)
		box.add_child(text_box)
		var button = Button.new()
		button.text = "CLOSE [ESC]"
		button.pressed.connect(close)
		box.add_child(button)
	session.panel.hide()
	panel.show()
	refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func refresh():
	var lines: Array[String] = ["WAREHOUSE PROGRESS", state.get("tier", "Waiting for the host..."), "", "Tier progress counts phase-adjusted product value fed to the pit.", "Spending cash does not reduce it. Older products count less in later tiers.", "", "UPGRADES / AVAILABLE TOOL LEVELS", "SHARED CASH: $" + state.get("money", "0"), ""]
	for row in state.get("purchases", []):
		lines.append("%s - $%s | %s" % [row.name, number(row.cost), "READY TO BUY" if row.left == 0 else "$%s more needed" % number(row.left)])
	lines.append("\nUPCOMING UNLOCKS (closest available first)\n")
	for row in state.get("unlocks", []):
		lines.append(row.name + " - " + row.requirement)
		if not row.blocked.is_empty(): lines.append("  First unlock: " + row.blocked)
		lines.append("")
	text_box.text = "\n".join(lines)

func close():
	if is_instance_valid(panel): panel.hide()
	session._update_menu_mouse()

func handle_input(event) -> bool:
	if active() and event is InputEventKey and event.pressed and event.physical_keycode in [KEY_ESCAPE, KEY_F8]:
		close()
		return true
	return false
