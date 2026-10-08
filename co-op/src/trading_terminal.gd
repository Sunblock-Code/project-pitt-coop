extends "res://coop/original_gambling_terminal.gd"
var pending_arcs: Dictionary = {}

func _arc_to_intake(body: Node, delay: float = 0.0) -> bool:
	var started = super._arc_to_intake(body, delay)
	if started: pending_arcs[body.get_instance_id()] = true
	return started

func _arc_step(p: float, body: Node, start_pos: Vector3, start_rot: Vector3, spin: Vector3):
	super._arc_step(p, body, start_pos, start_rot, spin)
	var coop = get_node_or_null("/root/PittCoop")
	if not coop or coop.role != "host" or not is_instance_valid(body): return
	var id = body.get_instance_id()
	if pending_arcs.has(id):
		pending_arcs.erase(id)
		coop.trading_sync.start(body, {"start":start_pos,"rotation":start_rot,"spin":spin,"end":intake_point.global_position,"height":arc_height,"duration":gather_duration,"p":p,"parent_basis":(body.get_parent_node_3d().global_basis if body.get_parent_node_3d() else Basis.IDENTITY),"scale":body.scale})
	elif coop.trading_sync.host_arcs.has(id): coop.trading_sync.host_arcs[id].p = p

func _despawn(body: Node):
	var coop = get_node_or_null("/root/PittCoop")
	if coop and coop.role == "host" and is_instance_valid(body): coop.trading_sync.finish(body.get_instance_id())
	super._despawn(body)

func _is_held(body: Node) -> bool:
	if super._is_held(body): return true
	var coop = get_node_or_null("/root/PittCoop")
	if coop:
		for hold in coop.held.values():
			if hold.id == body.get_instance_id(): return true
	return false
