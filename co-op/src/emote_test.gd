extends Node
var session: Node
var report = {}
func save_result():
	report.passed = not report.values().has(false)
	FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/emotes-"+session.role+".json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
func run():
	await get_tree().create_timer(12).timeout
	if session.role != "host": return
	session.host_player.set_physics_process(false)
	var peer = session.peers.keys()[0]
	for index in [0,4,5,6]:
		session.emotes.request(1,index)
		session._send(peer,["emote_qa",index])
		await get_tree().create_timer(1.2).timeout
		report["guest_emote_"+str(index)] = session.avatars.has(peer) and session.avatars[peer].emote_id == index
	session._send(peer,["emote_gallery"])
	save_result()
func receive(index: int):
	session.pending_intro = false
	session.guest.set_physics_process(false)
	await get_tree().create_timer(0.1).timeout
	report["host_emote_"+str(index)] = session.avatars.has(1) and session.avatars[1].emote_id == index
	session._send(1,["emote_request",index])
func gallery():
	var actors = []
	for i in range(4):
		var actor = session.Avatar.new()
		add_child(actor)
		actor.global_position = Vector3(10+i*1.7,10,18)
		actor.configure(session.Avatar.defaults(),false)
		actor.start_emote([0,4,5,6][i])
		actor._process([1.0,1.0,1.9,1.4][i])
		actor.set_process(false)
		actors.append(actor)
		var label = Label3D.new()
		add_child(label)
		label.text = ["WAVE","SALUTE","BOW","ROBOT"][i]
		label.font_size = 48
		label.pixel_size = 0.004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.global_position = Vector3(10+i*1.7,9.65,18)
	var light = OmniLight3D.new()
	add_child(light)
	light.global_position = Vector3(12.5,13,14)
	light.omni_range = 16
	light.light_energy = 2.5
	session.guest.global_position = Vector3(12.55,10.3,12.2)
	session.guest.camera.look_at(Vector3(12.55,11,18))
	await get_tree().create_timer(0.3).timeout
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/emote-poses.png"))
	var actor = actors[0]
	var pose_before = actor.right_elbow.rotation.z
	actor._process(0.25)
	report.wave_forearm_moves = absf(actor.right_elbow.rotation.z-pose_before)>0.05
	actor.emote_left = 0.01
	actor._process(0.1)
	report.restores_pose = actor.right_elbow.rotation.is_zero_approx() and actor.head.rotation.is_zero_approx()
	session.emotes.set_process(false)
	session.emotes.show()
	for i in range(7):
		var motion = InputEventMouseMotion.new()
		motion.position = get_viewport().get_visible_rect().size/2 + Vector2.from_angle(-PI/2+i*TAU/7)*150
		session.emotes.handle_input(motion)
		report["wheel_sector_"+str(i)] = session.emotes.chosen == i
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/emote-wheel.png"))
	session.emotes.hide()
	session.guest_held_id = 123
	report.held_item_blocks_wheel = not session.emotes.available()
	session.guest_held_id = 0
	save_result()
