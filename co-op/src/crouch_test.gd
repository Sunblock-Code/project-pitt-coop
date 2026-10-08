extends Node
var session: Node
var report: Dictionary = {}
var hold_key = false

func _physics_process(_delta):
	if hold_key:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		Input.action_press("crouch")

func platform():
	var floor_body = StaticBody3D.new()
	var collision = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	collision.shape = box
	floor_body.add_child(collision)
	var mesh = MeshInstance3D.new()
	var visual = BoxMesh.new()
	visual.size = box.size
	mesh.mesh = visual
	floor_body.add_child(mesh)
	get_tree().current_scene.add_child(floor_body)
	floor_body.position = Vector3(1000, -0.5, 1000)
	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	get_tree().current_scene.add_child(light)

func run_host():
	await get_tree().create_timer(28.0).timeout
	platform()
	get_node("/root/GameState").upgrades.crouch.level = 1
	get_node("/root/MenuManager").settings.gameplay.crouch_toggle = false
	session.host_player.global_position = Vector3(1000, 2, 1000)
	for peer in session.peers:
		session.peers[peer].pose.origin = Vector3(1002, 2, 1000)
	session._broadcast(["crouch_qa", "setup"])
	await get_tree().create_timer(2.0).timeout
	Input.action_press("crouch")
	session._broadcast(["crouch_qa", "down"])
	await get_tree().create_timer(1.5).timeout
	report.host_crouches = session.host_player.is_crouching
	report.guest_visible_squish = true
	for avatar in session.avatars.values():
		report.guest_visible_squish = report.guest_visible_squish and avatar.assembly.scale.y < 0.55 and avatar.assembly.scale.x > 1.2
	session._broadcast(["crouch_qa", "check_down"])
	await get_tree().create_timer(1.0).timeout
	Input.action_release("crouch")
	session._broadcast(["crouch_qa", "up"])
	await get_tree().create_timer(1.5).timeout
	report.host_stands = not session.host_player.is_crouching
	report.guest_stands = true
	for avatar in session.avatars.values(): report.guest_stands = report.guest_stands and avatar.assembly.scale.y > 0.95
	report.passed = not report.values().has(false)
	write_report("host")
	session._broadcast(["crouch_qa", "check_up"])

func key(pressed: bool):
	var event = InputEventKey.new()
	event.physical_keycode = KEY_C
	event.keycode = KEY_C
	event.pressed = pressed
	Input.parse_input_event(event)

func receive(stage: String):
	match stage:
		"setup":
			platform()
			session.guest.global_position = Vector3(1002, 2, 1000)
			get_node("/root/MenuManager").settings.gameplay.crouch_toggle = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		"down":
			hold_key = true
			key(true)
		"check_down":
			report.crouches = session.guest.crouched
			report.collider = is_equal_approx(session.guest.shape_node.shape.height, 0.95)
			report.camera = is_equal_approx(session.guest.camera.position.y, 0.8)
			report.host_visible_squish = session.avatars.has(1) and session.avatars[1].assembly.scale.y < 0.55
			report.local_squish = session.local_avatar.assembly.scale.y < 0.55
			await capture("down")
		"up":
			hold_key = false
			Input.action_release("crouch")
			key(false)
		"check_up":
			report.stands = not session.guest.crouched and session.guest.shape_node.shape.height > 1.7
			report.host_stands = session.avatars[1].assembly.scale.y > 0.95
			await capture("up")
			get_node("/root/MenuManager").settings.gameplay.crouch_toggle = true
			key(true)
			await get_tree().create_timer(0.2).timeout
			key(false)
			await get_tree().create_timer(0.4).timeout
			report.toggle_stays_down = session.guest.crouched
			key(true)
			await get_tree().create_timer(0.2).timeout
			key(false)
			await get_tree().create_timer(0.4).timeout
			report.toggle_stands = not session.guest.crouched
			report.passed = not report.values().has(false)
			write_report("guest")

func capture(stage: String):
	if DisplayServer.get_name() == "headless": return
	if not session.view_rig.active: session._toggle_view()
	# Let the real third-person spring arm reach its position before capturing.
	await get_tree().create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/crouch-" + stage + ".png"))

func write_report(side: String):
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/crouch-" + side + ".json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))
