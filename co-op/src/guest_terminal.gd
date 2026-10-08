extends Node

var session: Node
var viewers: Dictionary = {}
var revision = 0
var timer = 0.0
var panel: Control
var menu_layer: CanvasLayer
var tabs: TabContainer
var funds: Label
var message: Label
var client_revision = 0
var client_rows: Array = []
var buy_pending = false
var purchases_restricted = false
var restriction_controls: Array[CheckButton] = []
var client_restricted = false
var accept_catalog = false

func add_restriction_control(parent: Node):
	var control = CheckButton.new()
	control.text = "Restrict guest purchases"
	control.tooltip_text = "Off by default. Turn on to stop guests spending shared funds."
	control.visible = session.role == "host"
	control.toggled.connect(set_restricted)
	parent.add_child(control)
	restriction_controls.append(control)

func refresh_restriction_controls():
	for control in restriction_controls:
		control.visible = session.role == "host"
		control.set_pressed_no_signal(purchases_restricted)

func set_restricted(restricted: bool):
	if session.role != "host": return
	purchases_restricted = restricted
	refresh_restriction_controls()
	for peer in viewers: publish(peer)

func active() -> bool:
	return is_instance_valid(panel) and panel.visible

func _ui():
	return get_tree().get_first_node_in_group("UpgradeUI")

func _allowed(peer: int, terminal: Node3D) -> bool:
	if not session.peers.has(peer) or not session.peers[peer].ready or not is_instance_valid(terminal): return false
	var eye: Transform3D = session.peers[peer].camera
	if eye.origin.distance_to(terminal.global_position) > 5.0: return false
	var hit = terminal.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(eye.origin, terminal.global_position, 1))
	return hit.is_empty() or hit.collider == terminal or terminal.is_ancestor_of(hit.collider)

func open_for(peer: int, terminal: Node3D):
	if not _allowed(peer, terminal) or _ui() == null: return
	session._end_craft(peer)
	if session.held.has(peer): session._release(peer, false)
	_ui().update_ui()
	viewers[peer] = {"terminal": terminal, "revision": -1, "rows": []}
	session._send(peer, ["terminal_open"])
	publish(peer)

func _rows() -> Array:
	var ui = _ui()
	var rows: Array = []
	if ui == null: return rows
	for row in ui.find_children("*", "HBoxContainer", true, false):
		if row.is_queued_for_deletion() or not row.has_meta("button") or not row.has_meta("label"): continue
		var key: Array = []
		var group = ""
		if row.has_meta("category"):
			group = str(row.get_meta("category"))
			key = ["upgrade", group, str(row.get_meta("key")), str(row.get_meta("subkey", ""))]
			ui._refresh_upgrade_row(row)
		elif row.has_meta("tool_name"):
			group = "tools"
			key = ["tool", str(row.get_meta("tool_name")), int(row.get_meta("level"))]
			ui._refresh_tool_buy_row(row)
		elif row.has_meta("toy_name"):
			group = "toys"
			key = ["toy", str(row.get_meta("toy_name"))]
			ui._refresh_toy_buy_row(row)
		else: continue
		var button = row.get_meta("button")
		rows.append({"key": key, "group": group, "text": row.get_meta("label").text, "action": button.text, "disabled": button.disabled, "node": row, "parent": str(ui.get_path_to(row.get_parent())), "tooltip": _tooltip(ui, row), "color": row.get_meta("label").get_theme_color("font_color"), "modulate": row.modulate})
	return rows

func publish(peer: int):
	if not viewers.has(peer): return
	var rows: Array = []
	for row in _rows():
		var data = row.duplicate()
		data.erase("node")
		if purchases_restricted: data.disabled = true
		rows.append(data)
	if rows != viewers[peer].rows:
		revision += 1
		viewers[peer].revision = revision
		viewers[peer].rows = rows
	session._send(peer, ["terminal_catalog", viewers[peer].revision, rows, str(get_node("/root/GameState").format_big_number(get_node("/root/GameState").money)), purchases_restricted, _layout()])

func buy(peer: int, expected: int, index: int):
	if not viewers.has(peer): return
	var state = viewers[peer]
	if purchases_restricted:
		session._send(peer, ["terminal_result", "The host has restricted guest purchases in F8."])
		publish(peer)
		return
	if not _allowed(peer, state.terminal):
		viewers.erase(peer)
		session._send(peer, ["terminal_close"])
		return
	if state.revision != expected or index < 0 or index >= state.rows.size():
		session._send(peer, ["terminal_result", "Offer refreshed. Review the current price before purchasing."])
		publish(peer)
		return
	var offered = state.rows[index]
	# Consume this catalog before executing any callback: repeated/stale clicks
	# cannot spend twice or purchase the next level at an unexpected price.
	state.revision = -1
	var purchased = false
	for row in _rows():
		if row.key != offered.key: continue
		if row.disabled or row.text != offered.text or row.action != offered.action: break
		row.node.get_meta("button").pressed.emit()
		purchased = true
		session._send(peer, ["terminal_result", "Purchase processed. Shared balance and upgrades updated."])
		break
	if not purchased: session._send(peer, ["terminal_result", "Purchase unavailable. Check the current price, unlocks and funds."])
	for id in viewers:
		viewers[id].rows = []
		publish(id)

func _process(delta):
	if session.role != "host" or viewers.is_empty(): return
	timer += delta
	if timer < 1.0: return
	timer = 0.0
	for peer in viewers.keys():
		if not _allowed(peer, viewers[peer].terminal):
			viewers.erase(peer)
			if session.peers.has(peer): session._send(peer, ["terminal_close"])
		else: publish(peer)

func copy_native_ui(world: Node):
	var native = null
	for candidate in world.find_children("*", "Control", true, false):
		if candidate.is_in_group("UpgradeUI"):
			native = candidate
			break
	if native == null: return
	if is_instance_valid(panel): panel.queue_free()
	# Preserve the authored scene, theme, font, margins and all nested tabs.
	var inherited_theme = native.theme
	var parent = native.get_parent()
	while inherited_theme == null and parent != null:
		if parent is Control: inherited_theme = parent.theme
		parent = parent.get_parent()
	native.get_parent().remove_child(native)
	native.set_script(load("res://coop/guest_terminal_view.gd"))
	native.bridge = self
	for group in native.get_groups(): native.remove_from_group(group)
	native.theme = inherited_theme
	panel = native
	panel.hide()
	if not is_instance_valid(menu_layer):
		menu_layer = CanvasLayer.new()
		menu_layer.layer = session.hud.layer + 1
		add_child(menu_layer)
	menu_layer.add_child(panel)
	tabs = panel.tab_container
	funds = panel.credits_label
	message = panel.tooltip_label
	client_rows = []

func _tooltip(ui: Node, row: Node) -> String:
	var item: Dictionary
	var level = 0
	var maximum = 0
	var state = get_node("/root/GameState")
	if row.has_meta("category"):
		item = ui._get_item_dict(row.get_meta("category"), row.get_meta("key"), row.get_meta("subkey", ""))
		level = item.get("level", 0)
		maximum = item.get("prices", []).size()
	elif row.has_meta("tool_name"):
		if row.get_meta("recall_mode", false): return tr("TT_RECALL")
		item = state.tools[row.get_meta("tool_name")]
		level = row.get_meta("level")
		maximum = item.get("buy_prices", []).size()
	else:
		item = state.toys[row.get_meta("toy_name")]
		maximum = 1
	return ui._get_tooltip_from_array(item.get("tooltip", []), level, maximum)

func _layout() -> Array:
	var result: Array = []
	for container in _ui().find_children("*", "TabContainer", true, false):
		var entries: Array = []
		for i in container.get_tab_count():
			entries.append([container.get_tab_title(i), container.is_tab_hidden(i)])
		result.append([str(_ui().get_path_to(container)), entries])
	return result

func receive(rev: int, rows: Array, money: String, restricted: bool, layout: Array = []):
	if not accept_catalog or not is_instance_valid(panel): return
	client_restricted = restricted
	panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	funds.text = tr("UI_AVAILABLE_FUNDS").replace("{amount}", money)
	buy_pending = false
	client_revision = rev
	for spec in layout:
		var container = panel.get_node_or_null(NodePath(spec[0]))
		if not container is TabContainer: continue
		for i in mini(container.get_tab_count(), spec[1].size()):
			container.set_tab_title(i, spec[1][i][0])
			container.set_tab_hidden(i, spec[1][i][1])
		panel._select_first_visible_subtab(container)
	if rows == client_rows: return
	client_rows = rows
	panel.clear_offers()
	for index in rows.size():
		var data = rows[index]
		var parent = panel.get_node_or_null(NodePath(data.parent))
		if parent == null: continue
		if parent.get_child_count() == 0: panel.spawn_separator(parent)
		var row = panel._make_base_row("Offer_%d" % index)
		parent.add_child(row)
		panel.offer_nodes.append(row)
		var label = row.get_meta("label")
		label.text = data.text
		label.add_theme_color_override("font_color", data.color)
		row.modulate = data.modulate
		var button = row.get_meta("button")
		button.text = data.action
		button.disabled = data.disabled or restricted
		button.pressed.connect(request_buy.bind(index))
		panel._wire_tooltip(row, button, data.tooltip)
	if restricted: message.text = "The host has restricted guest purchases in F8."

func request_buy(index: int):
	if buy_pending or client_restricted or not active(): return
	buy_pending = true
	message.text = "Processing purchase..."
	session._send(1, ["terminal_buy", client_revision, index])

func close(notify_host: bool = true):
	accept_catalog = false
	if is_instance_valid(panel): panel.hide()
	if notify_host: session._send(1, ["terminal_leave"])
	session._update_menu_mouse()

func _input(event):
	if active() and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ESCAPE, KEY_F8]:
		close()
		get_viewport().set_input_as_handled()

func _unlock_test_catalog(data: Dictionary):
	for key in data:
		if data[key] is Dictionary: _unlock_test_catalog(data[key])
	if data.has("enabled"): data.enabled = true
	if data.has("enabled_levels"): data.enabled_levels.fill(true)

func run_host_checks():
	await get_tree().create_timer(28.0).timeout
	if session.peers.is_empty(): return
	var peer = session.peers.keys()[0]
	var state = get_node("/root/GameState")
	state.add_money(100000)
	for category in [state.tools, state.products, state.combos, state.toys]:
		_unlock_test_catalog(category)
	state.upgrades.sprint.enabled = true
	state.upgrades.sprint.level = 0
	state.upgrades.sprint.enabled_levels.fill(true)
	var terminal = get_tree().current_scene.get_node("UpgradeTerminal")
	var eye = terminal.global_position + Vector3(0, 1.0, 2.5)
	session.peers[peer].camera = Transform3D(Basis.IDENTITY, eye).looking_at(terminal.global_position)
	session.peers[peer].pose_time = 0
	session._send(peer, ["qa_terminal", eye, terminal.global_position])
	await get_tree().create_timer(3.0).timeout
	var money_before = int(state.money.to_plain_string())
	var cost = state.upgrades.sprint.prices[0]
	await get_tree().create_timer(5.0).timeout
	var report = {"guest_opened": viewers.has(peer), "level": state.upgrades.sprint.level, "charged_once": state.money.compare_int(money_before - cost) == 0, "shared_money": state.money.to_plain_string()}
	report.passed = report.guest_opened and report.level == 1 and report.charged_once
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/terminal-host.json"), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	# Validate locked/unaffordable rows and invalid/stale requests without spending.
	if viewers.has(peer):
		var before = state.money.to_plain_string()
		var default_allowed = not purchases_restricted
		restriction_controls[0].button_pressed = true
		var restricted_rows = viewers[peer].rows.duplicate(true)
		for index in range(restricted_rows.size()):
			if restricted_rows[index].key == ["upgrade", "upgrades", "sprint", ""]:
				buy(peer, viewers[peer].revision, index)
		var restrict_ok = purchases_restricted and state.money.to_plain_string() == before and state.upgrades.sprint.level == 1
		if DisplayServer.get_name() != "headless":
			session.panel.show()
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/host-purchase-option.png"))
			session.panel.hide()
		restriction_controls[0].button_pressed = false
		var restored = not purchases_restricted
		var restored_offer = false
		for row in viewers[peer].rows:
			if row.key == ["upgrade", "upgrades", "sprint", ""]: restored_offer = not row.disabled
		var restriction_file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/purchase-permission.json"), FileAccess.WRITE)
		if restriction_file:
			restriction_file.store_string(JSON.stringify({"default_allowed": default_allowed, "restricted_blocked": restrict_ok, "unrestricted_offer_enabled": restored and restored_offer, "passed": default_allowed and restrict_ok and restored and restored_offer}))
			restriction_file.close()
		buy(peer, -99, 0)
		buy(peer, viewers[peer].revision, -1)
		state.upgrades.sprint.enabled_levels[1] = false
		_ui().update_ui()
		viewers[peer].rows = []
		publish(peer)
		for index in range(viewers[peer].rows.size()):
			if viewers[peer].rows[index].key == ["upgrade", "upgrades", "sprint", ""]:
				buy(peer, viewers[peer].revision, index)
		var locked_ok = state.money.to_plain_string() == before and state.upgrades.sprint.level == 1
		state.upgrades.sprint.enabled_levels[1] = true
		state.spend(int(state.money.to_plain_string()))
		_ui().update_ui()
		viewers[peer].rows = []
		publish(peer)
		for index in range(viewers[peer].rows.size()):
			if viewers[peer].rows[index].key == ["upgrade", "upgrades", "sprint", ""]:
				buy(peer, viewers[peer].revision, index)
		var funds_ok = state.money.is_zero() and state.upgrades.sprint.level == 1
		var guard_file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/terminal-guards.json"), FileAccess.WRITE)
		if guard_file: guard_file.store_string(JSON.stringify({"locked_blocked": locked_ok, "unaffordable_blocked": funds_ok, "passed": locked_ok and funds_ok}))

func run_guest_checks(eye: Vector3, target: Vector3):
	session.guest.set_physics_process(false)
	session.guest.global_position = eye - Vector3(0, 1.65, 0)
	session.guest.camera.look_at(target)
	await get_tree().create_timer(0.5).timeout
	session.guest_action("interact")
	await get_tree().create_timer(3.0).timeout
	var opened = active()
	if not opened: return
	var revision_before = client_revision
	for index in range(client_rows.size()):
		if client_rows[index].key == ["upgrade", "upgrades", "sprint", ""]:
			request_buy(index)
			# Same network request twice must not buy two upgrade levels.
			session._send(1, ["terminal_buy", revision_before, index])
			break
	await get_tree().create_timer(2.0).timeout
	var level = get_node("/root/GameState").upgrades.sprint.level
	var report = {"opened": opened, "row_count": client_rows.size(), "level": level, "funds_text": funds.text, "rendered_rows": panel.offer_nodes.size(), "native_tabs": tabs.get_tab_count(), "passed": opened and level == 1 and client_rows.size() == panel.offer_nodes.size() and tabs.get_tab_count() == 5}
	var folder = OS.get_executable_path().get_base_dir().path_join("../logs/")
	var file = FileAccess.open(folder + "terminal-guest.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(folder + "terminal-guest.png")
		tabs.current_tab = tabs.get_node("Tools").get_index()
		panel.tools_tab_container.current_tab = panel.tools_tab_container.get_node("Magnet").get_index()
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(folder + "terminal-magnet.png")

	await get_tree().create_timer(5.0).timeout
	var escape = InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await get_tree().process_frame
	var close_report = FileAccess.open(folder + "terminal-close.json", FileAccess.WRITE)
	receive(client_revision, client_rows, "0", false)
	if close_report: close_report.store_string(JSON.stringify({"closed": not active(), "stale_catalog_ignored": not accept_catalog and not active(), "passed": not active() and (DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)}))
