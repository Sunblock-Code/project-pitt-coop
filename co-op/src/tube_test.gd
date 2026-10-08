extends Node
var session: Node

func make_item(at: Vector3) -> RigidBody3D:
	var body = load("res://scenes/panel.tscn").instantiate()
	get_tree().current_scene.add_child(body)
	body.global_position = at
	body.global_position += at - session.tube_rescue.center(body)
	body.force_place()
	return body

func run():
	await get_tree().create_timer(28).timeout
	get_node("/root/GameState").upgrades["sticky tools"].level = 1
	var rescue = session.tube_rescue
	var regions = rescue.volumes()
	var report = {"seven_sections":regions.size() == 7,"edge_tests":true,"centers_inside":true}
	var inside = []
	var outside = []
	for region in regions:
		var middle = (region.bottom + region.top) * 0.5
		var point: Vector3 = region.transform * Vector3(0,middle,0)
		report.centers_inside = report.centers_inside and rescue.contains(point,regions)
		inside.append(make_item(point))
		var polygon: PackedVector2Array = region.polygon
		for i in polygon.size()-1:
			var edge = (polygon[i]+polygon[i+1])*0.5
			var inward = edge - edge.normalized()*0.001
			var outward = edge + edge.normalized()*0.001
			report.edge_tests = report.edge_tests and rescue.contains(region.transform*Vector3(inward.x,middle,inward.y),regions) and not rescue.contains(region.transform*Vector3(outward.x,middle,outward.y),regions)
		outside.append(make_item(region.transform*Vector3(2.01,middle,0)))
	outside.append(make_item(Vector3(0,5.999,18)))
	outside.append(make_item(Vector3(0,1,18)))
	var protected = make_item(Vector3(0,10,18))
	await get_tree().physics_frame
	await get_tree().physics_frame
	session._scan_bodies()
	session.held[-60] = {"id":protected.get_instance_id()}
	var count = rescue.clear_tube()
	report.host_count = count == inside.size()
	report.inside_unstuck = true
	for body in inside: report.inside_unstuck = report.inside_unstuck and not body.freeze
	report.held_protected = protected.freeze
	session.held.erase(-60)
	protected.queue_free()
	report.outside_untouched = true
	for body in outside: report.outside_untouched = report.outside_untouched and body.freeze
	for body in inside: body.force_place()
	await get_tree().create_timer(1.2).timeout
	var ids = []
	var start = []
	for body in inside:
		ids.append(body.get_instance_id())
		start.append(body.global_position)
	session._broadcast(["tube_qa",ids,start])
	await get_tree().create_timer(3).timeout
	report.guest_freed = true
	for body in inside: report.guest_freed = report.guest_freed and not body.freeze
	for body in outside: report.outside_untouched = report.outside_untouched and body.freeze
	report.passed = not report.values().has(false)
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/tube-host.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"  "))

func guest_check(ids: Array, positions: Array):
	var report = {"button":false,"fall_synced":false,"replicas_present":true,"movement":[]}
	session.pending_intro = false
	session.panel.show()
	for button in session.panel.find_children("*","Button",true,false):
		if button.text == "Unstick items inside spawn tube":
			report.button = true
			button.pressed.emit()
	await get_tree().create_timer(2).timeout
	for i in ids.size():
		var body = session.replicas.get(ids[i])
		report.replicas_present = report.replicas_present and is_instance_valid(body)
		if is_instance_valid(body):
			report.movement.append(positions[i].y - body.global_position.y)
			# Panels can rest on each other; host verifies every sticky state.
			report.fall_synced = report.fall_synced or body.global_position.y < positions[i].y - 0.1
	report.passed = not report.values().has(false)
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/tube-guest.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"  "))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/tube-menu.png"))
