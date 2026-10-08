extends Node
var session: Node

func panel(at: Vector3) -> RigidBody3D:
	var body = RigidBody3D.new()
	body.freeze = true
	body.add_to_group("placable")
	var shape = CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(2, 2, 0.1)
	body.add_child(shape)
	var points = Node3D.new()
	points.name = "SnapPoints"
	body.add_child(points)
	for point in [Vector3(-1,-1,0), Vector3(1,-1,0), Vector3(1,1,0), Vector3(-1,1,0)]:
		var marker = Marker3D.new()
		points.add_child(marker)
		marker.position = point
	get_tree().current_scene.add_child(body)
	body.global_position = at
	return body

func run():
	await get_tree().create_timer(28).timeout
	var body = panel(Vector3(0, 150, 0))
	var neighbor = panel(Vector3(2, 150, 0))
	neighbor.rotation.z = 0.2
	await get_tree().physics_frame
	var camera = session.host_player.get_node("CameraPivot/MainCamera")
	var controls = session.held_controls
	var hold = {"id":body.get_instance_id(), "snap":true, "tier":0}
	var before = body.global_basis
	var host_grid = camera.POSITION_SNAP
	var host_cache = camera._placement_box_shape
	session.held[-58] = hold
	var first = controls.native_snap(body, hold, body.global_position)
	var shape = hold.bounds_shape
	var report = {"corner_found":first.has_basis, "stable":true}
	for i in 100:
		controls.target(-58, body, body.global_position)
		report.stable = report.stable and body.global_basis.is_equal_approx(before) and hold.snap_result.position.is_equal_approx(first.position)
	report.bounds_reused = hold.bounds_shape == shape
	report.host_settings_preserved = camera.POSITION_SNAP == host_grid and camera._placement_box_shape == host_cache
	hold.tier = 1
	controls.native_snap(body, hold, body.global_position)
	report.tier_refreshes_bounds = hold.bounds_shape != shape
	hold.tier = 0
	hold.distance = 2.5
	session.peers[-58] = {"camera":Transform3D(Basis.IDENTITY, body.global_position + Vector3(0,0,2.5))}
	var expected = controls.native_snap(body, hold, body.global_position)
	controls.place(-58, body)
	report.release_matches_preview = expected.valid and body.global_position.is_equal_approx(expected.position) and body.global_basis.is_equal_approx(expected.basis)
	session.peers.erase(-58)
	session.held.erase(-58)
	var source = Node3D.new()
	get_tree().current_scene.add_child(source)
	source.position = Vector3(0, 150, 10)
	var nested = Node3D.new()
	source.add_child(nested)
	nested.position = Vector3(1,2,3)
	for i in 2:
		var part = MeshInstance3D.new()
		part.mesh = BoxMesh.new()
		nested.add_child(part)
		part.position = Vector3(i,0,0)
		part.rotation.y = 0.3
		part.scale = Vector3(1,2,0.5)
	var outline = MeshInstance3D.new()
	outline.name = "outline"
	outline.mesh = BoxMesh.new()
	source.add_child(outline)
	camera.cleanup_ghost_preview()
	camera.update_ghost_preview(source, source.global_position)
	var ghost = camera.ghost_mesh
	report.all_parts = ghost.get_child_count() == 2
	report.mesh_alignment = true
	for i in 2:
		report.mesh_alignment = report.mesh_alignment and ghost.get_child(i).global_transform.is_equal_approx(nested.get_child(i).global_transform)
	report.passed = true
	for value in report.values():
		if value == false: report.passed = false
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/grid-stability.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))
	camera.cleanup_ghost_preview()
	source.queue_free()
	body.queue_free()
	neighbor.queue_free()
