extends Node3D
# Original game snap calculations, evaluated locally for the guest preview.
var POSITION_SNAP: float = 1.0
var ROTATION_SNAP: float = 45.0
var SNAP_POINT_RADIUS: float = 1.1
var snap_search_radius: float = 4.0
var _snap_extent_cache: Dictionary = {}
var _placement_box_shape: BoxShape3D
var _placement_box_center = Vector3.ZERO
var player_controller: Node
const COPLANAR_SNAP_WEIGHT = 4.0
const PANEL_DUPLICATE_EPSILON = 0.05
const PANEL_COPLANAR_DOT = 0.99
const PLACEMENT_CHECK_MARGIN = 0.5

func snap_to_grid_with_bounds(obj: Node3D, psition: Vector3, grid_size: float) -> Vector3:
	var bottom_offset = _get_collision_bottom_offset(obj, _quantized_basis(obj.global_transform.basis))
	var intended_bottom_y = psition.y + bottom_offset
	var snapped_bottom_y = round(intended_bottom_y / grid_size) * grid_size
	return Vector3(
		round(psition.x / grid_size) * grid_size, 
		snapped_bottom_y - bottom_offset, 
		round(psition.z / grid_size) * grid_size)

func get_object_aabb(obj: Node3D) -> AABB:
	var combined_aabb: = AABB()
	var first_mesh: = true

	if obj is MeshInstance3D:
		var mesh_inst: = obj as MeshInstance3D

		if mesh_inst.mesh:
			combined_aabb = mesh_inst.mesh.get_aabb()
			combined_aabb = combined_aabb.grow(0.0)
			first_mesh = false

	for child in obj.get_children():
		if child is MeshInstance3D:
			var mesh_inst: = child as MeshInstance3D

			if mesh_inst.mesh and not mesh_inst.name.contains("Outline"):
				var child_aabb = mesh_inst.mesh.get_aabb()
				var transformed_aabb = AABB(
					child.position + child_aabb.position * child.scale, 
					child_aabb.size * child.scale)

				if first_mesh:
					combined_aabb = transformed_aabb
					first_mesh = false
				else:
					combined_aabb = combined_aabb.merge(transformed_aabb)

	if first_mesh:
		combined_aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3(1, 1, 1))

	return combined_aabb

func _get_collision_aabb(obj: Node3D) -> AABB:
	var combined: = AABB()
	var first: = true

	for child in obj.get_children():
		if child is CollisionShape3D:
			var cs: = child as CollisionShape3D

			if cs.disabled or cs.shape == null:
				continue

			var transformed: AABB = cs.transform * _shape_local_aabb(cs.shape)

			if first:
				combined = transformed
				first = false
			else:
				combined = combined.merge(transformed)

	if first:

		return get_object_aabb(obj)

	return combined

func _shape_local_aabb(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var box: = shape as BoxShape3D
		return AABB( - box.size * 0.5, box.size)

	if shape is SphereShape3D:
		var sph: = shape as SphereShape3D
		var r: float = sph.radius
		return AABB(Vector3( - r, - r, - r), Vector3(r, r, r) * 2.0)

	if shape is CapsuleShape3D:
		var cap: = shape as CapsuleShape3D
		return AABB(
			Vector3( - cap.radius, - cap.height * 0.5, - cap.radius), 
			Vector3(cap.radius * 2.0, cap.height, cap.radius * 2.0))

	if shape is CylinderShape3D:
		var cyl: = shape as CylinderShape3D
		return AABB(
			Vector3( - cyl.radius, - cyl.height * 0.5, - cyl.radius), 
			Vector3(cyl.radius * 2.0, cyl.height, cyl.radius * 2.0))

	if shape is ConvexPolygonShape3D:
		var pts: PackedVector3Array = (shape as ConvexPolygonShape3D).points

		if pts.size() > 0:
			var aabb: = AABB(pts[0], Vector3.ZERO)

			for i in range(1, pts.size()):
				aabb = aabb.expand(pts[i])

			return aabb


	return shape.get_debug_mesh().get_aabb()

func _quantized_basis(b: Basis) -> Basis:
	var euler: = b.get_euler()
	var step: = deg_to_rad(ROTATION_SNAP)
	euler.x = round(euler.x / step) * step
	euler.y = round(euler.y / step) * step
	euler.z = round(euler.z / step) * step
	return Basis.from_euler(euler).orthonormalized()

func _is_panel_like(obj: Object) -> bool:
	return obj is Node and (obj.has_meta("coop_snap_merged") or str(obj.get_meta("coop_pool_id", "")).begins_with("tool_panel"))


func _panel_duplicate_at(obj: Node3D, snap_pos: Vector3, snap_basis: Basis) -> bool:
	var n_held: = snap_basis.z.normalized()

	for other in get_tree().get_nodes_in_group("coop_snap_placable"):
		if other == obj: continue
		if not _is_panel_like(other): continue
		if other.global_position.distance_to(snap_pos) > PANEL_DUPLICATE_EPSILON: continue

		var n_other: Vector3 = other.global_transform.basis.z.normalized()

		if absf(n_held.dot(n_other)) > PANEL_COPLANAR_DOT:
			return true

	return false

func _is_snap_position_clear(obj: Node3D, snap_pos: Vector3, snap_basis: Basis) -> bool:
	var held_is_panel: = _is_panel_like(obj)

	if held_is_panel and _panel_duplicate_at(obj, snap_pos, snap_basis):
		return false

	if _placement_box_shape == null:
		var aabb: = _get_collision_aabb(obj)
		var margin: float = minf(PLACEMENT_CHECK_MARGIN, POSITION_SNAP * 0.5)
		var size: = aabb.size - Vector3.ONE * (margin * 2.0)
		size.x = maxf(size.x, 0.01)
		size.y = maxf(size.y, 0.01)
		size.z = maxf(size.z, 0.01)
		_placement_box_shape = BoxShape3D.new()
		_placement_box_shape.size = size
		_placement_box_center = aabb.get_center()

	var params: = PhysicsShapeQueryParameters3D.new()
	params.shape = _placement_box_shape
	params.transform = Transform3D(snap_basis, snap_pos + snap_basis * _placement_box_center)
	params.collide_with_areas = false
	params.collide_with_bodies = true
	params.exclude = [obj.get_rid()]

	var hits: = get_world_3d().direct_space_state.intersect_shape(params, 16)

	for hit in hits:
		var collider = hit.get("collider")

		if collider == null: continue
		if collider == player_controller: continue
		if collider is Node and collider.has_meta("coop_snap_product"): continue
		if held_is_panel and _is_panel_like(collider): continue

		return false

	return true

func _get_collision_bottom_offset(obj: Node3D, basis: Basis) -> float:
	var min_y: = INF
	var rot: = Transform3D(basis, Vector3.ZERO)

	for child in obj.get_children():
		if child is CollisionShape3D:
			var cs: = child as CollisionShape3D

			if cs.disabled or cs.shape == null:
				continue

			min_y = minf(min_y, _shape_min_y(cs.shape, rot * cs.transform))

	if min_y == INF:

		return get_vertical_offset(obj)

	return min_y

func _shape_min_y(shape: Shape3D, xform: Transform3D) -> float:
	if shape is ConvexPolygonShape3D:
		var pts: PackedVector3Array = (shape as ConvexPolygonShape3D).points
		var m: = INF

		for p in pts:
			m = minf(m, (xform * p).y)

		if m != INF:
			return m

	if shape is BoxShape3D:
		var he: Vector3 = (shape as BoxShape3D).size * 0.5
		var m2: = INF

		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					m2 = minf(m2, (xform * Vector3(he.x * sx, he.y * sy, he.z * sz)).y)

		return m2

	if shape is SphereShape3D:
		return xform.origin.y - (shape as SphereShape3D).radius

	if shape is CapsuleShape3D:
		var cap: = shape as CapsuleShape3D
		var half: float = cap.height * 0.5 - cap.radius
		var top_y: float = (xform * Vector3(0, half, 0)).y
		var bot_y: float = (xform * Vector3(0, - half, 0)).y
		return minf(top_y, bot_y) - cap.radius

	if shape is CylinderShape3D:
		var cyl: = shape as CylinderShape3D
		var up: Vector3 = xform.basis.y.normalized()
		var horiz: float = sqrt(maxf(0.0, 1.0 - up.y * up.y))
		return xform.origin.y - (absf(up.y) * cyl.height * 0.5 + cyl.radius * horiz)



	var aabb: = _shape_local_aabb(shape)
	var m3: = INF

	for i in 8:
		m3 = minf(m3, (xform * aabb.get_endpoint(i)).y)

	return m3

func get_vertical_offset(obj: Node3D) -> float:
	var min_y = INF
	var found_mesh = false
	var meshes = []

	if obj is MeshInstance3D: meshes.append(obj)
	for child in obj.get_children():
		if child is MeshInstance3D and not child.name.contains("Outline"):
			meshes.append(child)

	for mesh in meshes:
		if mesh.mesh:
			var world_aabb = mesh.global_transform * mesh.mesh.get_aabb()

			if world_aabb.position.y < min_y:
				min_y = world_aabb.position.y

			found_mesh = true

	if not found_mesh: return 0.0
	return min_y - obj.global_position.y

func get_snap_points(obj: Node3D) -> Array[Marker3D]:
	var root: = obj.get_node_or_null("SnapPoints")

	if not root: return []
	var points: Array[Marker3D] = []

	for c in root.get_children():
		if c is Marker3D: points.append(c)

	return points

func _get_snap_extent(obj: Node3D) -> float:
	var id: = obj.get_instance_id()

	if _snap_extent_cache.has(id):
		return _snap_extent_cache[id]

	var ext: = 0.0

	for p in get_snap_points(obj):
		ext = maxf(ext, p.global_position.distance_to(obj.global_position))

	_snap_extent_cache[id] = ext
	return ext

func _plane_normal_from_points(pts: Array[Marker3D], fallback_basis: Basis) -> Vector3:
	if pts.size() >= 3:
		var o: = pts[0].global_position
		var v1: = pts[1].global_position - o

		for i in range(2, pts.size()):
			var n: = v1.cross(pts[i].global_position - o)

			if n.length() > 0.001:
				return n.normalized()

	return fallback_basis.z.normalized()

func find_best_corner_snap(held_obj: Node3D, held_pos: Vector3) -> Dictionary:
	if SNAP_POINT_RADIUS <= 0.0:
		return {}

	var candidates: Array = []
	var held_points: = get_snap_points(held_obj)

	if held_points.is_empty(): return {}

	var held_ext: = _get_snap_extent(held_obj)

	for other in get_tree().get_nodes_in_group("coop_snap_placable"):
		if other == held_obj: continue
		var cull_r: float = SNAP_POINT_RADIUS + held_ext + _get_snap_extent(other)

		if other.global_position.distance_squared_to(held_pos) > cull_r * cull_r:
			continue

		var other_points: = get_snap_points(other)

		if other_points.is_empty(): continue

		var n_other: = _plane_normal_from_points(other_points, other.global_transform.basis)
		var other_center = other.global_position

		for hp in held_points:
			var hp_offset: = hp.global_position - held_obj.global_position

			for op in other_points:
				var target_corner: = op.global_position
				var projected_corner: = held_pos + hp_offset
				var d: = projected_corner.distance_to(target_corner)

				if d < SNAP_POINT_RADIUS:
					var tpos: = target_corner - hp_offset
					var coplanar: = absf((tpos - other_center).dot(n_other))
					candidates.append({
						"dist": d, 
						"coplanar": coplanar, 
						"held_point": hp, 
						"target_point": op, 
						"target_pos": tpos, 
						"target_obj": other
					})

	candidates.sort_custom( func(a, b): return a.coplanar * COPLANAR_SNAP_WEIGHT + a.dist < b.coplanar * COPLANAR_SNAP_WEIGHT + b.dist)

	for c in candidates:
		if not _snap_pos_overlaps_placed(held_obj, c.target_pos):
			return {
				"held_point": c.held_point, 
				"target_point": c.target_point, 
				"target_pos": c.target_pos, 
				"target_obj": c.target_obj
			}

	return {}

func _find_best_snap_with_basis(held_obj: Node3D, held_pos: Vector3, basis: Basis) -> Dictionary:
	if SNAP_POINT_RADIUS <= 0.0:
		return {}

	var candidates: Array = []
	var held_points: = get_snap_points(held_obj)

	if held_points.is_empty(): return {}

	var held_ext: = _get_snap_extent(held_obj)

	for other in get_tree().get_nodes_in_group("coop_snap_placable"):
		if other == held_obj: continue
		var cull_r: float = SNAP_POINT_RADIUS + held_ext + _get_snap_extent(other)

		if other.global_position.distance_squared_to(held_pos) > cull_r * cull_r:
			continue

		var other_points: = get_snap_points(other)

		if other_points.is_empty(): continue

		var n_other: = _plane_normal_from_points(other_points, other.global_transform.basis)
		var other_center = other.global_position

		for hp in held_points:
			var hp_offset: Vector3 = basis * hp.position

			for op in other_points:
				var target_corner: = op.global_position
				var projected_corner: = held_pos + hp_offset
				var d: = projected_corner.distance_to(target_corner)

				if d < SNAP_POINT_RADIUS:
					var tpos: = target_corner - hp_offset
					var coplanar: = absf((tpos - other_center).dot(n_other))
					candidates.append({
						"dist": d, 
						"coplanar": coplanar, 
						"held_point": hp, 
						"target_point": op, 
						"target_pos": tpos, 
						"target_obj": other
					})

	candidates.sort_custom( func(a, b): return a.coplanar * COPLANAR_SNAP_WEIGHT + a.dist < b.coplanar * COPLANAR_SNAP_WEIGHT + b.dist)

	for c in candidates:
		if not _snap_pos_overlaps_placed(held_obj, c.target_pos):
			return {
				"held_point": c.held_point, 
				"target_point": c.target_point, 
				"target_pos": c.target_pos, 
				"target_obj": c.target_obj
			}

	return {}

func _snap_pos_overlaps_placed(held_obj: Node3D, target_pos: Vector3) -> bool:


	const OVERLAP_THRESHOLD: = 0.5

	var r2: = snap_search_radius * snap_search_radius

	for other in get_tree().get_nodes_in_group("coop_snap_placable"):
		if other == held_obj: continue
		if target_pos.distance_squared_to(other.global_position) > r2:
			continue

		if target_pos.distance_to(other.global_position) < OVERLAP_THRESHOLD:
			return true

	return false

func _compute_snap(obj: Node3D, desired_pos: Vector3) -> Dictionary:
	var grid_pos: = snap_to_grid_with_bounds(obj, desired_pos, POSITION_SNAP)
	var snap: = find_best_corner_snap(obj, desired_pos)

	if not snap.is_empty():
		var target_obj: Node3D = snap.target_obj


		var relative_basis: = _snap_rotation_relative_to(obj, target_obj)


		var best_snap: = _find_best_snap_with_basis(obj, desired_pos, relative_basis)

		if not best_snap.is_empty():
			return {"position": best_snap.target_pos, "snap": best_snap, "basis": relative_basis, "has_basis": true, 
				"valid": _is_snap_position_clear(obj, best_snap.target_pos, relative_basis)}


		var hp: Marker3D = snap.held_point
		var op: Marker3D = snap.target_point
		var hp_world_offset: Vector3 = relative_basis * hp.position
		var final_pos: Vector3 = op.global_position - hp_world_offset
		return {"position": final_pos, "snap": snap, "basis": relative_basis, "has_basis": true, 
			"valid": _is_snap_position_clear(obj, final_pos, relative_basis)}



	return {"position": grid_pos, "snap": {}, "basis": Basis.IDENTITY, "has_basis": false, 
		"valid": _is_snap_position_clear(obj, grid_pos, _quantized_basis(obj.global_transform.basis))}

func _snap_rotation_relative_to(obj: Node3D, target: Node3D) -> Basis:
	var target_basis: Basis = target.global_transform.basis
	var obj_basis: Basis = obj.global_transform.basis
	var step: = deg_to_rad(ROTATION_SNAP)


	var world_euler: = obj_basis.get_euler()
	world_euler.x = round(world_euler.x / step) * step
	world_euler.y = round(world_euler.y / step) * step
	world_euler.z = round(world_euler.z / step) * step
	var world_snapped: = Basis.from_euler(world_euler).orthonormalized()


	var relative: Basis = target_basis.inverse() * world_snapped
	var rel_euler: = relative.get_euler()



	var coplanar_bias: = minf(deg_to_rad(30.0), step * 0.66)

	for i in 3:
		var angle: float = rel_euler[i]
		var dist_to_zero: = absf(angle)
		var dist_to_pi: = absf(absf(angle) - PI)

		if dist_to_zero < coplanar_bias:
			rel_euler[i] = 0.0
		elif dist_to_pi < coplanar_bias:
			rel_euler[i] = PI if angle > 0.0 else - PI
		else:
			rel_euler[i] = round(angle / step) * step

	var snapped_relative: = Basis.from_euler(rel_euler).orthonormalized()

	return (target_basis * snapped_relative).orthonormalized()
