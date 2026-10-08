extends Node
var session: Node
var gates: Array = []
var world_id = 0
var last_state: Array = []

func sync_host():
	var world = get_tree().current_scene
	if world_id != world.get_instance_id():
		world_id = world.get_instance_id()
		gates = get_tree().get_nodes_in_group("gate_shutters")
	var rows: Array = []
	for gate in gates:
		if not is_instance_valid(gate): continue
		for i in range(gate.indicator_lights.size()):
			var lamp = gate.indicator_lights[i]
			var mat = lamp.get_active_material(0)
			if mat is StandardMaterial3D: rows.append([str(world.get_path_to(lamp)), "lamp", [mat.emission_enabled, mat.emission, mat.emission_energy_multiplier]])
		if is_instance_valid(gate.gate.barrier):
			var barrier = gate.gate.barrier
			rows.append([str(world.get_path_to(barrier)), "barrier", [barrier.collision_layer, barrier.collision_mask]])
	for body in get_tree().get_nodes_in_group("fuse"):
		if session.bodies.has(body.get_instance_id()):
			rows.append([body.get_instance_id(), "fuse", [body.get_meta("slotted", false)]])
	for peer in session.peers:
		if session.peers[peer].ready and session.peers[peer].get("fuse_state", []) != rows:
			session._send(peer, ["fuse_state", rows])
			session.peers[peer].fuse_state = rows.duplicate(true)

func receive(rows: Array):
	last_state = rows
	var world = get_tree().current_scene
	for row in rows:
		if row[1] == "fuse":
			var body = session.replicas.get(row[0])
			if not is_instance_valid(body): continue
			body.collision_layer = 0 if row[2][0] else 2
			body.set_meta("coop_grabbable", not row[2][0])
			continue
		var node = world.get_node_or_null(NodePath(row[0]))
		if not is_instance_valid(node): continue
		if row[1] == "barrier":
			node.collision_layer = row[2][0]
			node.collision_mask = row[2][1]
		elif row[1] == "lamp":
			if not node.has_meta("coop_fuse_material"):
				node.set_surface_override_material(0, node.get_active_material(0).duplicate())
				node.set_meta("coop_fuse_material", true)
			var mat = node.get_active_material(0)
			mat.emission_enabled = row[2][0]
			mat.emission = row[2][1]
			mat.emission_energy_multiplier = row[2][2]

func hint() -> String:
	return "[%s] Insert fuse into socket" % get_node("/root/InputManager").get_action_key_name("interact")

func try_insert(peer: int) -> bool:
	if session.role != "host" or not is_instance_valid(session.host_player): return false
	var eye = session.host_player.get_node("CameraPivot/MainCamera")
	var body = eye.picked_object if peer == 1 else instance_from_id(session.held[peer].id) if session.held.has(peer) else null
	if not is_instance_valid(body) or not body.is_in_group("fuse") or body.get_meta("slotted",false): return false
	var camera: Transform3D = eye.global_transform if peer == 1 else session.peers[peer].camera
	var selected: Node
	var selected_slot = -1
	var best = 0.24
	for gate in get_tree().get_nodes_in_group("gate_shutters"):
		for i in gate.fuse_slots.size():
			if gate.is_slot_filled(i): continue
			var pos: Vector3 = gate.fuse_slots[i].global_position
			var offset = pos-camera.origin
			var depth = offset.dot(-camera.basis.z)
			if depth < 0.0 or depth > 4.0 or body.global_position.distance_to(pos) > 1.25: continue
			var miss = (offset + camera.basis.z*depth).length()
			if miss >= best: continue
			var query = PhysicsRayQueryParameters3D.create(camera.origin,pos,1)
			query.exclude = [body.get_rid(),session.host_player.get_rid()]
			var hit = body.get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty() and hit.position.distance_to(pos) > 0.35: continue
			selected = gate
			selected_slot = i
			best = miss
	if is_instance_valid(selected):
		selected._on_fuse_slot_body_entered(body,selected_slot)
		if body.get_meta("slotted",false):
			sync_host()
			return true
	if peer != 1: session._send(peer,["notice","Move the fuse close to an empty socket and aim at it, then press F."])
	return false
