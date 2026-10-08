extends Node
var session: Node

func click(pressed: bool):
	var event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	session.guest._input(event)
	if pressed: session.guest._unhandled_input(event)

func aim_at_duck():
	var body = session.replicas.get(session.test_id)
	if not is_instance_valid(body): return
	session.guest.global_position = body.global_position + Vector3(0,-1.65,2.0)
	session.guest.camera.look_at(body.global_position)
	session._send(1, ["pose", session.guest.global_transform, session.guest.camera.global_transform])

func guest_checks() -> Dictionary:
	var report = {}
	session.guest.set_physics_process(false)
	session.pending_intro = false
	var body = session.replicas.get(session.test_id)
	if not is_instance_valid(body): return {"passed":false,"missing_body":true}
	session.guest.global_position = body.global_position + Vector3(0,-1.65,2.0)
	session.guest.camera.look_at(body.global_position)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	session.grab_settings.set_hold(false)
	await get_tree().create_timer(0.3).timeout
	click(true)
	click(false)
	await get_tree().create_timer(0.5).timeout
	report.press_keeps_carry = session.guest_held_id == session.test_id
	report.press_hint = session.interaction_hud.controls.text.contains("[LMB] Drop")
	click(true)
	click(false)
	await get_tree().create_timer(0.4).timeout
	report.second_press_drops = session.guest_held_id == 0
	# Two clicks queued before either server acknowledgement must pick up/drop.
	aim_at_duck()
	var grabs_before = session.test_grab_count
	session._send(1, ["action", "grab_toggle", session.test_id])
	session._send(1, ["action", "grab_toggle", session.test_id])
	await get_tree().create_timer(0.4).timeout
	report.quick_clicks_drop = session.guest_held_id == 0 and session.test_grab_count > grabs_before
	session.grab_settings.set_hold(true)
	session._send(1, ["grab_qa_reset"])
	await get_tree().create_timer(0.4).timeout
	aim_at_duck()
	session._send(1, ["action", "grab", session.test_id])
	await get_tree().create_timer(0.3).timeout
	report.hold_picks_up = session.guest_held_id == session.test_id
	click(false)
	await get_tree().create_timer(0.3).timeout
	report.release_drops = session.guest_held_id == 0
	session.grab_settings.set_hold(false)
	var cfg = ConfigFile.new()
	report.saved_locally = cfg.load("user://pitt_controls.cfg") == OK and cfg.get_value("controls", "hold_to_grab", true) == false
	report.passed = not report.values().has(false)
	session._send(1,["grab_mode_checks"])
	return report

func host_checks():
	var report = {"guest_did_not_change_host":session.grab_settings.hold_to_grab}
	var camera = session.host_player.get_node("CameraPivot/MainCamera")
	var body = load("res://scenes/duck.tscn").instantiate()
	get_tree().current_scene.add_child(body)
	body.global_position = camera.global_position - camera.global_basis.z * 2
	session.grab_settings.set_hold(false)
	camera._begin_carry(body)
	camera._release_carry_if_needed()
	report.host_press_keeps_carry = camera.picked_object == body
	Input.action_press("lMouse")
	camera.drop_object()
	report.host_second_press_drops = camera.picked_object == null
	Input.action_release("lMouse")
	session.grab_settings.set_hold(true)
	camera._begin_carry(body)
	camera._release_carry_if_needed()
	report.host_release_drops = camera.picked_object == null
	report.passed = not report.values().has(false)
	body.queue_free()
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/grab-host.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))
