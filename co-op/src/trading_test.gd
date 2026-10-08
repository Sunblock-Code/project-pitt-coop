extends Node
var session: Node

func run():
	print("[TRADING QA] start")
	await get_tree().create_timer(10).timeout
	print("[TRADING QA] spawning")
	var root = load("res://scenes/gambling_terminal.tscn").instantiate()
	root.name = "TradingQA"
	get_tree().current_scene.add_child(root)
	root.global_position = Vector3(10,5,18)
	var terminal = root if root.has_method("_arc_to_intake") else null
	for child in root.find_children("*", "Node3D", true, false):
		if child.has_method("_arc_to_intake"): terminal = child
	print("[TRADING QA] root=",root.get_class()," terminal=",terminal)
	if terminal == null: return
	await get_tree().create_timer(1.0).timeout
	print("[TRADING QA] timer resumed")
	print("[TRADING QA] scan before")
	session._scan_bodies()
	print("[TRADING QA] scan after")
	var pool = get_node("/root/ObjectPoolManager")
	if not pool._pools.has("duck"):
		await pool._create_pool("duck", {"scene":load("res://scenes/duck.tscn"),"initial":0,"max":12})
	var body = pool.spawn("duck", terminal.intake_point.global_position + Vector3(4,0,-2))
	body.freeze = true
	print("[TRADING QA] scan before")
	session._scan_bodies()
	print("[TRADING QA] scan after")
	session._broadcast(["trading_qa","TradingQA",body.get_instance_id(),terminal.gather_duration])
	await get_tree().create_timer(0.4).timeout
	var bank_before = get_node("/root/GameState").bank
	terminal._claim(body,10)
	var report = {"native_arc_started":terminal._arc_to_intake(body),"duration":terminal.gather_duration}
	await get_tree().create_timer(terminal.gather_duration+0.5).timeout
	print("[TRADING QA] timer resumed")
	report.host_consumed = not is_instance_valid(body) or not body.visible
	report.bank_once = is_equal_approx(get_node("/root/GameState").bank-bank_before,10)
	report.arc_state_cleared = session.trading_sync.host_arcs.is_empty()
	report.machine_sent = true
	for peer in session.peers: report.machine_sent = report.machine_sent and session.peers[peer].get("shared_scenes",{}).has("TradingQA")
	report.passed = not report.values().has(false)
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/trading-host.json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"  "))

func guest_check(path: String, id: int, duration: float):
	var machine = get_tree().current_scene.get_node_or_null(path)
	var report = {"purchased_machine_visible":is_instance_valid(machine) and machine.is_visible_in_tree()}
	session.pending_intro = false
	session.guest.set_physics_process(false)
	session.guest.global_position = Vector3(10,6,9)
	session.guest.camera.look_at(Vector3(10,7,18))
	var light = OmniLight3D.new()
	add_child(light)
	light.global_position = Vector3(10,9,10)
	light.omni_range = 18
	light.light_energy = 3
	var frames_before = session.trading_sync.frames
	var count_before = session.trading_sync.received
	await get_tree().create_timer(0.62).timeout
	report.curve_active = session.trading_sync.arcs.has(id)
	report.item_visible = session.replicas.has(id) and session.replicas[id].is_visible_in_tree()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/trading-suction.png"))
	await get_tree().create_timer(duration+0.8).timeout
	report.local_animation = session.trading_sync.frames-frames_before >= 6 and session.trading_sync.received-count_before == 1
	report.consumed_removed = not session.replicas.has(id) and not session.trading_sync.arcs.has(id)
	report.labels = false
	if is_instance_valid(machine):
		for node in machine.find_children("*","Label3D",true,false):
			if node.is_visible_in_tree() and not node.text.is_empty(): report.labels = true
	report.passed = not report.values().has(false)
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/trading-guest.json"),FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report,"  "))
