extends Node
var session: Node
var last_use = -10000

func request():
	if session.role == "host" and session.world_ready: clear_tube()
	elif session.role == "guest" and not session.pending_intro: session._send(1, ["clear_spawn_tube"])

func volumes() -> Array:
	var result = []
	var tube = get_tree().get_first_node_in_group("ToolTube")
	if not is_instance_valid(tube): return result
	for segment in tube.get_children():
		if not str(segment.name).begins_with("TubeTool"): continue
		for shape in segment.get_children():
			if not shape is CollisionShape3D or shape.disabled or not shape.shape is ConcavePolygonShape3D: continue
			var faces: PackedVector3Array = shape.shape.get_faces()
			var inner = INF
			var outer = 0.0
			var bottom = INF
			var top = -INF
			for vertex in faces:
				var radius = Vector2(vertex.x, vertex.z).length()
				inner = minf(inner, radius)
				outer = maxf(outer, radius)
				bottom = minf(bottom, vertex.y)
				top = maxf(top, vertex.y)
			# Only accept a hollow, straight section with a distinct inner ring.
			if inner < 0.1 or outer - inner < 0.01 or top <= bottom: continue
			var points = PackedVector2Array()
			for vertex in faces:
				var point = Vector2(vertex.x, vertex.z)
				if point.length() < (inner + outer) * 0.5 and not points.has(point): points.append(point)
			var polygon = Geometry2D.convex_hull(points)
			if polygon.size() < 4: continue
			result.append({"transform":shape.global_transform,"polygon":polygon,"bottom":bottom,"top":top})
	return result

func contains(point: Vector3, regions: Array) -> bool:
	for region in regions:
		var local: Vector3 = region.transform.affine_inverse() * point
		if local.y < region.bottom or local.y > region.top: continue
		if Geometry2D.is_point_in_polygon(Vector2(local.x,local.z), region.polygon): return true
	return false

func center(body: RigidBody3D) -> Vector3:
	var bounds = AABB()
	var found = false
	for child in body.get_children():
		if not child is CollisionShape3D or child.disabled or child.shape == null: continue
		var box: AABB = child.transform * child.shape.get_debug_mesh().get_aabb()
		bounds = bounds.merge(box) if found else box
		found = true
	return body.global_transform * bounds.get_center() if found else body.global_position

func clear_tube() -> int:
	if session.role != "host" or not session.world_ready: return 0
	if Time.get_ticks_msec() - last_use < 1000: return 0
	last_use = Time.get_ticks_msec()
	var regions = volumes()
	if regions.is_empty():
		session.info.text = "Spawn tube not found; nothing changed."
		return 0
	var protected = {}
	for hold in session.held.values(): protected[hold.id] = true
	var camera = session.host_player.get_node("CameraPivot/MainCamera")
	for item in [camera.picked_object, camera.equipped_item]:
		if is_instance_valid(item): protected[item.get_instance_id()] = true
	var count = 0
	for body in session.indexed_bodies.values():
		if not is_instance_valid(body) or not body is RigidBody3D or not body.is_inside_tree() or not body.is_visible_in_tree(): continue
		if not body.is_in_group("draggable") or protected.has(body.get_instance_id()) or body.get_meta("slotted", false): continue
		if not contains(center(body), regions): continue
		camera._release_from_piston(body)
		if body.has_method("unplace"): body.unplace()
		body.freeze = false
		body.sleeping = false
		if body.has_method("set_highlight"): body.set_highlight(false)
		count += 1
	var message = "Spawn tube: freed %d item(s). Outside items unchanged." % count
	session.info.text = message
	session._broadcast(["notice", message])
	return count
