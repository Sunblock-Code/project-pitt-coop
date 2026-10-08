extends Node
var session: Node
func run_host():
	await get_tree().create_timer(28.0).timeout
	var scheduler = load("res://scenes/shift_scheduler.tscn").instantiate()
	get_tree().current_scene.add_child(scheduler)
	scheduler.global_position = Vector3(24, 5, 10)
	scheduler.freeze = true
	var fan = load("res://scenes/fan.tscn").instantiate()
	get_tree().current_scene.add_child(fan)
	fan.global_position = scheduler.global_position + Vector3(0.8, 0, 0)
	fan.freeze = true
	var manual = load("res://scenes/manual_duck_workbench.tscn").instantiate()
	get_tree().current_scene.add_child(manual)
	manual.global_position = Vector3(40, 5, 10)
	var report = {"manual_eligible": scheduler._is_valid_target(manual), "fan_eligible": scheduler._is_valid_target(fan)}
	scheduler.scheduler_mode = 1
	scheduler.scheduler_interval = 4.0
	scheduler.scheduler_duration = 1.0
	scheduler._reset_cycle()
	scheduler._update_screen()
	var origin = scheduler.global_position + Vector3(0, -1.65, 2)
	for peer in session.peers: session.peers[peer].pose.origin = origin
	await get_tree().create_timer(1.0).timeout
	report.latched = scheduler._target == fan
	session._broadcast(["scheduler_qa", origin, scheduler.global_position])
	await get_tree().create_timer(4.0).timeout
	report.guest_mode = scheduler.scheduler_mode == 2
	report.guest_interval = is_equal_approx(scheduler.scheduler_interval, 4.5)
	report.guest_duration = is_equal_approx(scheduler.scheduler_duration, 1.5)
	scheduler.set_physics_process(false)
	scheduler.scheduler_mode = 3
	scheduler.scheduler_interval = 6.0
	scheduler.scheduler_duration = 0.5
	scheduler._reset_cycle()
	scheduler._tick_schedule(0.1)
	report.square_off = not fan.is_active
	scheduler._tick_schedule(6.0)
	report.square_on = fan.is_active
	scheduler._tick_schedule(6.0)
	report.square_off_again = not fan.is_active
	report.passed = report.fan_eligible and not report.manual_eligible and report.latched and report.guest_mode and report.guest_interval and report.guest_duration and report.square_off and report.square_on and report.square_off_again
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/scheduler-host.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))

func run_guest(msg):
	session.guest.set_physics_process(false)
	session.guest.global_position = msg[1]
	session.guest.camera.look_at(msg[2])
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await get_tree().create_timer(0.5).timeout
	var key = InputEventAction.new()
	key.action = "interact"
	key.pressed = true
	session.guest._unhandled_input(key)
	await get_tree().create_timer(0.4).timeout
	for button in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_UP]:
		var event = InputEventMouseButton.new()
		event.button_index = button
		event.pressed = true
		session.guest._unhandled_input(event)
		await get_tree().create_timer(0.4).timeout
	await get_tree().create_timer(0.7).timeout
	var labels = []
	for replica in session.replicas.values():
		if replica.scene_file_path.contains("shift_scheduler"):
			for label in replica.find_children("*", "Label3D", true, false): labels.append(label.text)
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/scheduler-guest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"labels": labels, "passed": str(labels).contains("4.5") and str(labels).contains("1.5")}, "  "))
	print("[SCHEDULER QA] guest tuning inputs sent")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/scheduler-guest.png"))

