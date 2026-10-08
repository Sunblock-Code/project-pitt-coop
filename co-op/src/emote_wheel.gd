extends Control
const NAMES = ["WAVE", "CHEER", "DANCE", "SHRUG", "SALUTE", "BOW", "ROBOT"]
var session: Node
var chosen = -1
var old_mouse = Input.MOUSE_MODE_CAPTURED
var last_sent: Dictionary = {}

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()

func available() -> bool:
	if session.role not in ["host", "guest"] or not is_instance_valid(session.local_body): return false
	# Carry starts locally before the host's held-item acknowledgement arrives.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): return false
	if session.panel.visible or session.lobby.visible or session.character_editor.visible or session.guest_terminal.active() or session.progress_menu.active() or session.guest_settings.active(): return false
	if get_node("/root/MenuManager").current_menu != null: return false
	if session.role == "guest": return not session.pending_intro and session.guest_held_id == 0 and not session.tool_equipped and not session.guest.craft_pressed
	var camera = session.host_player.get_node_or_null("CameraPivot/MainCamera")
	return camera != null and camera.picked_object == null and camera.equipped_item == null

func _process(_delta):
	# An equip response can arrive while the wheel is already open.
	if visible and not available(): finish(false)

func handle_input(event) -> bool:
	if visible and event is InputEventKey and event.pressed and event.physical_keycode in [KEY_ESCAPE, KEY_F8]:
		finish(false)
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed:
			if visible: return true
			if not available(): return false
			old_mouse = Input.mouse_mode
			chosen = -1
			show()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().warp_mouse(get_viewport_rect().size / 2)
			queue_redraw()
			return true
		elif visible:
			finish(true)
			return true
	if visible:
		if event is InputEventMouseMotion:
			var offset = event.position - get_viewport_rect().size / 2
			chosen = -1 if offset.length() < 45 else posmod(int(floor((offset.angle() + PI / 2 + PI / NAMES.size()) / (TAU / NAMES.size()))), NAMES.size())
			queue_redraw()
		return true
	return false

func finish(commit: bool):
	hide()
	Input.mouse_mode = old_mouse
	if commit and chosen >= 0:
		if session.role == "host": request(1, chosen)
		else: session._send(1, ["emote_request", chosen])
	chosen = -1

func request(peer: int, index: int):
	if index < 0 or index >= NAMES.size(): return
	if peer != 1 and (not session.peers.has(peer) or not session.peers[peer].ready or session.held.has(peer)): return
	var now = Time.get_ticks_msec()
	if now - last_sent.get(peer, -1000) < 500: return
	last_sent[peer] = now
	play(peer, index)
	session._broadcast(["emote_play", peer, index])

func play(peer: int, index: int):
	if index < 0 or index >= NAMES.size(): return
	var own = 1 if session.role == "host" else session.net.get_unique_id()
	var actor = session.local_avatar if peer == own else session.avatars.get(peer)
	if is_instance_valid(actor): actor.start_emote(index)
	if peer == own: session.info.text = NAMES[index] + " | F5 to see your character"

func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and visible: finish(false)

func _draw():
	var center = get_viewport_rect().size / 2
	var font = load("res://assets/PublicPixel-rv0pA.ttf")
	draw_circle(center, 210, Color(0.02, 0.03, 0.045, 0.95))
	for i in range(NAMES.size()):
		var angle = -PI / 2 + i * TAU / NAMES.size()
		var color = Color("efca50") if chosen == i else Color("8d998f")
		draw_arc(center, 208, angle - PI / NAMES.size() + 0.025, angle + PI / NAMES.size() - 0.025, 24, color, 4)
		var point = center + Vector2.from_angle(angle) * 153
		var width = font.get_string_size(NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(font, point + Vector2(-width / 2, 6), NAMES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
	draw_circle(center, 42, Color("152126"))
	draw_string(font, center + Vector2(-27, 5), "MMB", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("efca50"))
	draw_string(font, center + Vector2(-175, 240), "RELEASE TO EMOTE / ESC CANCEL", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
