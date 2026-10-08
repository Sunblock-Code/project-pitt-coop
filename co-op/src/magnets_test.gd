extends Node
var session: Node
func run_host():
	await get_tree().create_timer(28.0).timeout
	var magnets = []
	for index in range(3):
		var body = load("res://scenes/magnet.tscn" if index < 2 else "res://scenes/magnet2.tscn").instantiate()
		get_tree().current_scene.add_child(body)
		body.global_position = Vector3(24 + index * 2, 7, 10)
		body.freeze = true
		body.remote_toggle(index != 1)
		magnets.append(body)
	var fan = load("res://scenes/fan.tscn").instantiate()
	get_tree().current_scene.add_child(fan)
	fan.global_position = Vector3(30, 7, 10)
	fan.freeze = true
	fan.remote_toggle(true)
	session._scan_bodies()
	var count = session._turn_all_magnets_off()
	var report = {"count": count, "host_off": true, "fan_unaffected": fan.is_active}
	for body in magnets:
		report.host_off = report.host_off and not body.is_active
		body.remote_toggle(true)
	await get_tree().create_timer(1.0).timeout
	var ids = []
	for body in magnets: ids.append(body.get_instance_id())
	session._broadcast(["magnets_qa", ids])
	await get_tree().create_timer(3.0).timeout
	report.guest_off = true
	for body in magnets: report.guest_off = report.guest_off and not body.is_active and not body.magnet_effect.visible
	report.passed = count >= 3 and report.host_off and report.guest_off and fan.is_active
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/magnets-host.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))

func run_guest(ids):
	var report = {"button": false}
	for button in session.panel.find_children("*", "Button", true, false):
		if button.text == "Turn all magnets OFF":
			report.button = true
			button.pressed.emit()
	await get_tree().create_timer(2.0).timeout
	report.effects_off = true
	for id in ids:
		var body = session.replicas.get(id)
		var effect = body.get_node_or_null("MagnetEffect") if body else null
		report.effects_off = report.effects_off and effect != null and not effect.visible
	report.passed = report.button and report.effects_off
	var file = FileAccess.open(OS.get_executable_path().get_base_dir().path_join("../logs/magnets-guest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	session.panel.show()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_executable_path().get_base_dir().path_join("../logs/magnets-menu.png"))
