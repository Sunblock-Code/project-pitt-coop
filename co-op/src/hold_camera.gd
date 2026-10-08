extends "res://coop/original_camera.gd"

func _begin_carry(obj: RigidBody3D, keep_hands: bool = false) -> void:
	var coop = get_node_or_null("/root/PittCoop")
	if coop and coop.role == "host":
		for hold in coop.held.values():
			if hold.id == obj.get_instance_id(): return
	if obj.get_meta("slotted", false) or obj.is_in_group("terminal_pull"): return
	super._begin_carry(obj, keep_hands)

func _rack_panel(panel: RigidBody3D) -> bool:
	var coop = get_node_or_null("/root/PittCoop")
	if coop and coop.role == "host":
		for hold in coop.held.values():
			if hold.id == panel.get_instance_id(): return false
	return super._rack_panel(panel)

func apply_screenshake(intensity: float, duration: float):
	super.apply_screenshake(intensity, duration)
	var session = get_node_or_null("/root/PittCoop")
	if not session or session.role != "host": return
	if get_node("/root/GameProgression").current_phase > session.phase_sync.finished_phase:
		session._broadcast(["phase_shake", intensity, duration])

func handle_input():
	super.handle_input()
	_release_carry_if_needed()

func _input(event: InputEvent):
	var coop_session = get_node_or_null("/root/PittCoop")
	if coop_session and is_instance_valid(coop_session.emotes) and coop_session.emotes.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.physical_keycode == KEY_M:
		var session = get_node_or_null("/root/PittCoop")
		if session:
			session.duck_pass._input(event)
			return
	if event.is_action_pressed("interact") and not event.is_echo():
		if coop_session and coop_session.role == "host" and coop_session.fuse_sync.try_insert(1):
			get_viewport().set_input_as_handled()
			return
	super._input(event)
	if event.is_action_released("lMouse"):
		_release_carry_if_needed()

func drop_object(force: bool = false):
	# Ignore the original click-to-drop branch while the grab button is down.
	if _hold_mode() and not force and Input.is_action_just_pressed("lMouse") and Input.is_action_pressed("lMouse"): return
	super.drop_object(force)

func _release_carry_if_needed():
	if _hold_mode() and equipped_item == null and picked_object != null and not Input.is_action_pressed("lMouse"):
		super.drop_object()

func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and equipped_item == null and picked_object != null:
		super.drop_object(true)

func create_ghost_preview(source_object: Node3D):
	if is_instance_valid(ghost_mesh): return
	ghost_mesh = MeshInstance3D.new()
	get_tree().current_scene.add_child(ghost_mesh)
	preload("res://coop/grid_ghost.gd").populate(ghost_mesh, source_object, ghost_material)

func update_ghost_preview(source_object: Node3D, target_position: Vector3, override_basis: Basis = Basis.IDENTITY, use_override: bool = false, is_valid: bool = true):
	super.update_ghost_preview(source_object, target_position, override_basis, use_override, is_valid)
	# Child transforms already include their original scale and offsets.
	if is_instance_valid(ghost_mesh): ghost_mesh.scale = Vector3.ONE

func _hold_mode() -> bool:
	var coop = get_node_or_null("/root/PittCoop")
	return not coop or not is_instance_valid(coop.grab_settings) or coop.grab_settings.hold_to_grab
