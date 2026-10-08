extends "res://coop/original_gate_shutters.gd"

func _on_fuse_slot_body_entered(body: Node3D, slot_index: int):
	if _slot_fuse_map.has(slot_index) or not body.is_in_group("fuse"): return
	if str(body.get("fuse_id")).is_empty() or body.fuse_id in _slot_fuse_map.values(): return
	var coop = get_node_or_null("/root/PittCoop")
	if coop and coop.role == "host":
		for peer in coop.held.keys():
			if coop.held[peer].id == body.get_instance_id(): coop._release(peer, false)
	super._on_fuse_slot_body_entered(body, slot_index)
	if body.get_meta("slotted", false):
		body.set("_slotted", true)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.set_highlight(false)
