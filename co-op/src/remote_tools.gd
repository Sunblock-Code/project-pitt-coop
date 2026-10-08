extends Node
var session: Node
var remotes: Dictionary = {}
var guest_states: Dictionary = {}
var sent: Dictionary = {}
var use_times: Dictionary = {}

static func is_remote(body) -> bool:
	return is_instance_valid(body) and body.scene_file_path.get_file().get_basename() == "remote"

func track(body):
	if is_remote(body): remotes[body.get_instance_id()] = body

func equipped_guest() -> bool:
	return session.tool_equipped and is_remote(session.replicas.get(session.guest_held_id))

func action(peer: int, command: String):
	if not session.broom_players.equipped(peer): return
	var remote = instance_from_id(session.held[peer].id)
	if not is_remote(remote): return
	var now = Time.get_ticks_msec()
	if now - use_times.get(peer, -1000) < 120: return
	use_times[peer] = now
	if command == "interact":
		var eye: Transform3D = session.peers[peer].camera
		var query = PhysicsRayQueryParameters3D.create(eye.origin, eye.origin - eye.basis.z * 2.5, 0xFFFFFFFF)
		query.exclude = session.duck_pass.rids(peer)
		var hit = remote.get_world_3d().direct_space_state.intersect_ray(query)
		if hit and hit.collider.is_in_group("toggle"):
			var target = hit.collider
			var linked = remote._find_tool_channel(target) == remote.current_channel
			var success = remote.try_link_tool(target)
			session._send(peer, ["notice", ("Unlinked tool." if linked else "Linked tool. Left-click toggles this channel.") if success else "Remote channel is full. Upgrade its link capacity."])
		else: session._send(peer, ["notice", "Aim at a compatible tool within reach and press F to link it."])
	elif command == "grab": remote._toggle_channel(remote.current_channel)
	elif command == "remote_all":
		if get_node("/root/GameState").remote_max_channels > 1: remote._toggle_all_channels()
	elif command == "remote_next": remote.cycle_channel(1)
	elif command == "remote_previous": remote.cycle_channel(-1)

func sync():
	var state = get_node("/root/GameState")
	var rows = []
	for id in remotes.keys():
		var remote = remotes[id]
		if not is_instance_valid(remote):
			remotes.erase(id)
			continue
		if not session.bodies.has(id): continue
		var linked = []
		for body in state.remote_channels[remote.current_channel]:
			if is_instance_valid(body): linked.append(body.get_instance_id())
		rows.append([id, remote.current_channel, state.remote_channel_states[remote.current_channel], linked, state.remote_slots_per_channel, state.remote_max_channels])
	for peer in session.peers:
		if not session.peers[peer].ready: continue
		if sent.get(peer) != rows:
			session._send(peer, ["remote_state", rows])
			sent[peer] = rows.duplicate(true)

func receive(rows):
	for row in rows:
		guest_states[row[0]] = row
		apply_screen(row[0])

func apply_screen(id):
	if not session.replicas.has(id) or not guest_states.has(id): return
	var body = session.replicas[id]
	var row = guest_states[id]
	var path = "ScreenViewport/ScreenUI/VBoxContainer/"
	for entry in [["HBoxContainer/ChannelLabel", "CH %d" % (int(row[1]) + 1)], ["StatusLabel", "ON" if row[2] else "OFF"], ["CountLabel", "LNK %d/%d" % [row[3].size(), row[4]]]]:
		var label = body.get_node_or_null(path + entry[0])
		if label is Label: label.text = entry[1]
	var color = [Color(1, 0.2, 0.2), Color(0.3, 0.5, 1), Color(1, 0.85, 0.1), Color(0.3, 0.9, 0.4)][int(row[1]) % 4]
	var bar = body.get_node_or_null(path + "HBoxContainer/ChannelColor")
	if bar is ColorRect: bar.color = color
	var led = body.get_node_or_null("Antenna/Skeleton3D/AntennaLed")
	if led is MeshInstance3D:
		if not led.has_meta("remote_private_material"):
			led.material_override = led.material_override.duplicate() if led.material_override else StandardMaterial3D.new()
			led.set_meta("remote_private_material", true)
		if led.material_override is StandardMaterial3D:
			led.material_override.albedo_color = color
			led.material_override.emission_enabled = true
			led.material_override.emission = color

func hint() -> String:
	var row = guest_states.get(session.guest_held_id)
	var channel = int(row[1]) + 1 if row else 1
	var count = row[3].size() if row else 0
	var text = "[E] Unequip | [F] Link / Unlink | [LMB] CH %d (%d linked)" % [channel, count]
	if row and int(row[5]) > 1: text += " | [Scroll] Channel | [Shift + LMB] All"
	return text

func preserve_screen(node):
	node.set_script(null)
	for child in node.get_children(): preserve_screen(child)
