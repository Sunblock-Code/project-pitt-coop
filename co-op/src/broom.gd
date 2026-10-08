extends "res://coop/original_broom.gd"
const COOP_REST = Transform3D(Basis(Vector3.UP, PI), Vector3(0.4, -1.0, -1.5))
var coop_ready_at = 0
var coop_hits: Array = []

func coop_guest_sweep(eye: Transform3D) -> bool:
	var now = Time.get_ticks_msec()
	if now < coop_ready_at: return false
	coop_ready_at = now + int((0.25 + sweep_cooldown) * 1000.0)
	_cancel_sweep()
	transform = COOP_REST
	get_parent().global_transform = eye
	sweeping = true
	_clear_preview()
	sweep_audio_3d.play()
	coop_hits.clear()
	var bodies_data = []
	# Query the authored sweep shapes at the click pose, not last frame's overlaps.
	for shape in sweep_area.get_children():
		if not shape is CollisionShape3D or shape.disabled or not shape.shape: continue
		var query = PhysicsShapeQueryParameters3D.new()
		query.shape = shape.shape
		query.transform = shape.global_transform
		query.collision_mask = sweep_area.collision_mask
		query.exclude = [get_rid()]
		for hit in get_world_3d().direct_space_state.intersect_shape(query, 2048):
			var body = hit.collider
			if not body is RigidBody3D or coop_hits.has(body.get_instance_id()): continue
			coop_hits.append(body.get_instance_id())
			body.physics_material_override = body.physics_material_override.duplicate() if body.physics_material_override else PhysicsMaterial.new()
			if not body.has_meta("broom_base_friction"): body.set_meta("broom_base_friction", body.physics_material_override.friction)
			var token = int(body.get_meta("broom_slide_token", 0)) + 1
			body.set_meta("broom_slide_token", token)
			bodies_data.append({"body": body, "token": token})
			body.physics_material_override.friction = slide_friction
			body.apply_central_impulse(-eye.basis.z.normalized() * sweep_strength * sweep_impulse_multiplier)
	_schedule_friction_restore(bodies_data, slide_duration)
	_sweep_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_sweep_tween.tween_property(self, "position", COOP_REST.origin + Vector3(0, 0, -0.4), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_sweep_tween.parallel().tween_property(self, "rotation", Vector3(deg_to_rad(-30), PI, 0), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_sweep_tween.tween_property(self, "position", COOP_REST.origin, 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sweep_tween.parallel().tween_property(self, "rotation", Vector3(0, PI, 0), 0.15).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_finish_guest_sweep(coop_ready_at)
	return true

func _finish_guest_sweep(token):
	await get_tree().create_timer(0.25 + sweep_cooldown, true).timeout
	if coop_ready_at == token: sweeping = false

func unequip(world: Node3D, drop_pos: Vector3):
	coop_ready_at = 0
	super.unequip(world, drop_pos)
