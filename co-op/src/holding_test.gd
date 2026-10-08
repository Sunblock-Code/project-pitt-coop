extends Node
var session: Node
var report = {}
func save_report():
	report.passed = not report.values().has(false)
	FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/holding-"+session.role+".json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
func run():
	await get_tree().create_timer(12).timeout
	var peer = session.peers.keys()[0]
	session.profile.holding = 1
	session.profiles[peer].holding = 4
	report.old_profile_default = session.Avatar.sanitize({}).holding == 0
	report.invalid_profile_clamped = session.Avatar.sanitize({"holding":999}).holding == 8
	var a = load("res://scenes/duck.tscn").instantiate()
	var b = load("res://scenes/duck.tscn").instantiate()
	get_tree().current_scene.add_child(a)
	get_tree().current_scene.add_child(b)
	a.global_position = Vector3(12,9,18)
	b.global_position = Vector3(14,9,18)
	var eye = session.host_player.get_node("CameraPivot/MainCamera")
	eye.set_process(false)
	eye.set_physics_process(false)
	Input.action_press("lMouse")
	eye._begin_carry(a)
	session._begin_guest_carry(peer,b)
	a.freeze = true
	b.freeze = true
	session._scan_bodies()
	await get_tree().create_timer(0.3).timeout
	var outline_a = session.holding_colors.active[a.get_instance_id()][0]
	var outline_b = session.holding_colors.active[b.get_instance_id()][0]
	report.host_color = outline_a.material_override.albedo_color == session.Avatar.HOLD_COLORS[1]
	report.guest_color = outline_b.material_override.albedo_color == session.Avatar.HOLD_COLORS[4]
	report.private_materials = outline_a.material_override != outline_b.material_override
	session._broadcast(["holding_qa",a.get_instance_id(),b.get_instance_id()])
	await get_tree().create_timer(1.5).timeout
	eye.drop_object(true)
	session._release(peer,false)
	Input.action_release("lMouse")
	await get_tree().create_timer(0.3).timeout
	report.cleared_on_drop = session.holding_colors.owners.is_empty()
	save_report()
func guest_check(a: int,b: int):
	await get_tree().create_timer(0.25).timeout
	report.host_color = session.holding_colors.active.has(a) and session.holding_colors.active[a][0].material_override.albedo_color == session.Avatar.HOLD_COLORS[1]
	report.guest_color = session.holding_colors.active.has(b) and session.holding_colors.active[b][0].material_override.albedo_color == session.Avatar.HOLD_COLORS[4]
	session.pending_intro = false
	session.guest.set_physics_process(false)
	session.guest.global_position = Vector3(13,8.6,13)
	session.guest.camera.look_at(Vector3(13,9,18))
	var light = OmniLight3D.new()
	add_child(light)
	light.global_position = Vector3(13,11,14)
	light.omni_range = 12
	light.light_energy = 3
	await get_tree().create_timer(0.2).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/holding-colors.png"))
	await get_tree().create_timer(1.5).timeout
	report.drop_synced = session.holding_colors.owners.is_empty()
	session.character_editor.open(session.profile)
	session.character_editor.selectors.holding.select(4)
	session.character_editor.selectors.holding.item_selected.emit(4)
	report.editor_option = session.character_editor.draft.holding == 4
	await get_tree().create_timer(0.2).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/holding-editor.png"))
	session.character_editor._save()
	var saved = ConfigFile.new()
	saved.load(session.profile_path)
	report.saved_profile = saved.get_value("character","profile",{}).get("holding",-1) == 4
	save_report()
