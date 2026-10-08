extends Node
var session: Node
var report: Dictionary = {}

func floor_setup():
	var helper = load("res://coop/crouch_test.gd").new()
	add_child(helper)
	helper.platform()
	helper.queue_free()
	get_node("/root/MenuManager").settings.gameplay.crouch_toggle = false
	get_node("/root/MenuManager").settings.gameplay.sprint_toggle = false

func press(value: bool):
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for action in ["up", "sprint", "crouch"]:
		if value: Input.action_press(action)
		else: Input.action_release(action)

func run_host():
	await get_tree().create_timer(28.0).timeout
	floor_setup()
	for action in ["crouch", "sprint", "slide"]: get_node("/root/GameState").upgrades[action].level = 1
	session.host_player.global_position = Vector3(1000, 2, 1000)
	for peer in session.peers: session.peers[peer].pose.origin = Vector3(1002, 2, 1000)
	session._broadcast(["slide_qa", "setup"])
	await get_tree().create_timer(2.0).timeout
	press(true)
	session._broadcast(["slide_qa", "start"])
	await get_tree().create_timer(0.35).timeout
	report.host_sliding = session.host_player.is_sliding
	report.guest_animation = true
	for avatar in session.avatars.values(): report.guest_animation = report.guest_animation and avatar.slide_blend > 0.8 and avatar.left_leg.rotation.x > 0.9
	session._broadcast(["slide_qa", "check"])
	press(false)
	await get_tree().create_timer(2.0).timeout
	report.guest_reset = true
	for avatar in session.avatars.values(): report.guest_reset = report.guest_reset and avatar.slide_blend < 0.02
	report.host_reset = not session.host_player.is_sliding
	report.passed = not report.values().has(false)
	write_report("host")
	session._broadcast(["slide_qa", "finish"])

func receive(stage: String):
	match stage:
		"setup":
			floor_setup()
			session.guest.global_position = Vector3(1002, 2, 1000)
			session.guest.camera.rotation.y = PI
			if not session.view_rig.active: session._toggle_view()
		"start": press(true)
		"check":
			report.guest_sliding = session.guest.slide_time > 0.0
			report.local_animation = session.local_avatar.slide_blend > 0.8 and session.local_avatar.left_leg.rotation.x > 0.9
			report.host_animation = session.avatars[1].slide_blend > 0.8 and session.avatars[1].left_leg.rotation.x > 0.9
			if DisplayServer.get_name() != "headless":
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/sliding.png"))
			press(false)
		"finish":
			report.reset = session.local_avatar.slide_blend < 0.02 and session.avatars[1].slide_blend < 0.02
			session.broom_players.receive(999, Vector3(2, 0, 0), 0.5, 0.1)
			await get_tree().create_timer(0.2).timeout
			report.broom_animation = session.local_avatar.slide_blend > 0.8
			report.passed = not report.values().has(false)
			write_report("guest")

func write_report(side: String):
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/slide-" + side + ".json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))
