extends Node
var session: Node
var panels: Dictionary = {}

func _ready():
	process_priority = 1000

func track(body: RigidBody3D):
	if not "pool_id" in body or not str(body.pool_id).begins_with("tool_panel"): return
	var outline = body.get_node_or_null("MeshInstance3D2")
	if not outline is MeshInstance3D: return
	if not outline.has_meta("coop_private_highlight"):
		if outline.material_override: outline.material_override = outline.material_override.duplicate()
		outline.set_meta("coop_private_highlight", true)
	panels[body.get_instance_id()] = [body, outline]

func _process(_delta):
	if session.role != "host" or not is_instance_valid(session.host_player): return
	var camera = session.host_player.get_node_or_null("CameraPivot/MainCamera")
	if not camera: return
	var ray = camera.get("interact_ray")
	var selected = ray.get_collider() if is_instance_valid(ray) and ray.is_colliding() else null
	for id in panels.keys():
		var body = panels[id][0]
		var outline = panels[id][1]
		if not is_instance_valid(body) or not is_instance_valid(outline):
			panels.erase(id)
			continue
		# Native sticky placement can enable an outline without the local player
		# ever targeting it. Only that player's aim/carry may keep it enabled.
		if body != selected and body != camera.get("picked_object"):
			outline.hide()

func test_host():
	await get_tree().create_timer(28.0).timeout
	get_node("/root/GameState").upgrades["sticky tools"].level = 1
	var objects: Array = []
	for index in range(3):
		var body = load("res://scenes/panel.tscn").instantiate()
		get_tree().current_scene.add_child(body)
		body.global_position = Vector3(1000 + index * 2.5, 50, 1000)
		track(body)
		body.force_place()
		objects.append(body)
	session._scan_bodies()
	await get_tree().create_timer(0.5).timeout
	var report = {"unselected_hidden": true, "still_sticky": true, "materials_private": objects[0].outline_mesh.material_override != objects[1].outline_mesh.material_override}
	for body in objects:
		report.unselected_hidden = report.unselected_hidden and not body.outline_mesh.visible
		report.still_sticky = report.still_sticky and body.freeze
	session.host_player.set_physics_process(false)
	var camera = session.host_player.get_node("CameraPivot/MainCamera")
	camera.global_position = objects[0].global_position + Vector3(0, 1, 1)
	camera.look_at(objects[0].global_position)
	camera.interact_ray.force_raycast_update()
	objects[0].set_highlight(true)
	await get_tree().create_timer(0.3).timeout
	report.selected_visible = objects[0].outline_mesh.visible
	print("[PANEL QA] ray=", camera.interact_ray.target_position, " hit=", camera.interact_ray.get_collider(), " camera=", camera.global_position)
	camera.look_at(camera.global_position + Vector3(0, 1, -0.1))
	camera.interact_ray.force_raycast_update()
	await get_tree().create_timer(0.3).timeout
	report.look_away_hides = not objects[0].outline_mesh.visible
	report.passed = not report.values().has(false)
	write_report("host", report)
	var ids: Array = []
	for body in objects: ids.append(body.get_instance_id())
	session._broadcast(["panel_outline_qa", ids])

func test_guest(ids: Array):
	session.guest.set_physics_process(false)
	var first = session.replicas.get(ids[0])
	if not first: return
	session.guest.global_position = first.global_position + Vector3(0, 0.35, 2)
	session.guest.camera.look_at(first.global_position)
	await get_tree().create_timer(0.5).timeout
	var report = {"selected_visible": first.get_node("MeshInstance3D2").visible, "other_panels_hidden": true}
	for id in ids.slice(1): report.other_panels_hidden = report.other_panels_hidden and not session.replicas[id].get_node("MeshInstance3D2").visible
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/panel-highlight.png"))
	session.guest.camera.look_at(session.guest.camera.global_position + Vector3(0, 1, -0.1))
	await get_tree().create_timer(0.3).timeout
	report.look_away_hides = not first.get_node("MeshInstance3D2").visible
	report.passed = not report.values().has(false)
	write_report("guest", report)

func write_report(side: String, report: Dictionary):
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/panel-outline-" + side + ".json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))
