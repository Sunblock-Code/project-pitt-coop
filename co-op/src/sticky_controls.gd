extends Node

var session: Node

func _ready():
	process_priority = 1000

func _process(_delta):
	if session.role != "host" or not is_instance_valid(session.host_player): return
	var camera = session.host_player.get_node_or_null("CameraPivot/MainCamera")
	if camera == null: return
	var label = get_tree().current_scene.find_child("controls_label", true, false)
	if not label is Label or not label.visible: return
	var drop_key = "Release LMB" if session.grab_settings.hold_to_grab else "LMB"
	var body = camera.get("picked_object")
	if not is_instance_valid(body):
		label.text = label.text.replace("[Hold LMB] Grab", "[LMB] Grab").replace("[LMB] Grab", "[Hold LMB] Grab" if session.grab_settings.hold_to_grab else "[LMB] Grab")
		return
	var base = label.text.replace(" | Touch a surface to stick", "").replace("[Release LMB] Place / Stick", "[LMB] Drop").replace("[Release LMB] Drop", "[LMB] Drop").replace("[LMB] Place / Stick", "[LMB] Drop")
	var sticky = body.has_method("place") and int(get_node("/root/GameState").upgrades["sticky tools"].level) > 0
	if sticky and session._can_stick(body):
		label.text = base.replace("[LMB] Drop", "[%s] Place / Stick" % drop_key)
	else:
		label.text = base.replace("[LMB] Drop", "[%s] Drop" % drop_key)
		if sticky: label.text += " | Touch a surface to stick"

	if body.is_in_group("fuse") and not label.text.contains("Insert fuse into socket"):
		label.text += " | " + session.fuse_sync.hint()

func run_host_checks():
	await get_tree().create_timer(15.0).timeout
	var world = get_tree().current_scene
	var platform = StaticBody3D.new()
	var shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(10, 0.5, 10)
	shape.shape = box
	platform.add_child(shape)
	world.add_child(platform)
	platform.global_position = Vector3(30, 10, 30)
	var body = load("res://scenes/bumper.tscn").instantiate()
	world.add_child(body)
	body.global_position = Vector3(30, 12, 30)
	body.contact_monitor = true
	body.max_contacts_reported = 8
	await get_tree().create_timer(2.0).timeout
	get_node("/root/GameState").upgrades["sticky tools"].level = 1
	var player = session.host_player
	player.set_physics_process(false)
	player.global_position = Vector3(30, 10.3, 32.5)
	var camera = player.get_node("CameraPivot/MainCamera")
	camera.set_physics_process(false)
	camera.set_process_input(false)
	camera.look_at(body.global_position)
	camera.picked_object = body
	get_node("/root/GameProgression").on_player_exit_elevator()
	await get_tree().create_timer(0.4).timeout
	var label = world.find_child("controls_label", true, false)
	var ready_text = label.text
	var ready_passed = label.visible and ready_text.contains("[Release LMB] Place / Stick")
	var folder = OS.get_executable_path().get_base_dir().path_join("../logs/")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(folder + "host-sticky-ready.png")
	body.freeze = false
	body.sleeping = false
	platform.global_position.y -= 20.0
	body.global_position = Vector3(300, 50, 300)
	body.gravity_scale = 0.0
	body.linear_velocity = Vector3.ZERO
	await get_tree().create_timer(0.3).timeout
	var away_text = label.text
	var away_passed = label.visible and away_text.contains("Touch a surface to stick") and not away_text.contains("Place / Stick")
	Input.action_press("lMouse")
	camera._release_carry_if_needed()
	var held_pressed = camera.picked_object == body
	Input.action_release("lMouse")
	camera._release_carry_if_needed()
	var released = camera.picked_object == null
	camera.equipped_item = body
	camera._release_carry_if_needed()
	var equipped_preserved = camera.equipped_item == body
	camera.equipped_item = null
	var report = {"contact_hint": ready_text, "away_hint": away_text, "colliders": str(body.get_colliding_bodies()), "position": str(body.global_position), "contact_passed": ready_passed, "away_passed": away_passed, "held_while_pressed": held_pressed, "release_drops": released, "equipped_preserved": equipped_preserved, "passed": ready_passed and away_passed and held_pressed and released and equipped_preserved}
	var file = FileAccess.open(folder + "host-sticky-hints.json", FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "  "))
