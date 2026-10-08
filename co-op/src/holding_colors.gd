extends Node
var session: Node
var owners: Dictionary = {}
var active: Dictionary = {}
var active_bodies: Dictionary = {}
const Style = preload("res://coop/interaction_hud.gd")
func _ready():
	process_priority = 2000
func publish(peer: int):
	session._send(peer,["holding_colors",owners])
func _process(_delta):
	if session.role == "host" and is_instance_valid(session.host_player):
		var next = {}
		var eye = session.host_player.get_node("CameraPivot/MainCamera")
		if is_instance_valid(eye.picked_object): next[eye.picked_object.get_instance_id()] = int(session.profile.get("holding",0))
		for peer in session.held:
			if not session.held[peer].get("equipped",false): next[session.held[peer].id] = int(session.profiles.get(peer,{}).get("holding",0))
		if next != owners:
			owners = next
			session._broadcast(["holding_colors",owners])
	elif session.role != "guest": return
	for id in active.keys():
		if not owners.has(id):
			for outline in active[id]:
				if is_instance_valid(outline):
					outline.hide()
					if outline.material_override is StandardMaterial3D: outline.material_override.albedo_color = Color.WHITE
			active.erase(id)
			active_bodies.erase(id)
	for id in owners:
		var body = instance_from_id(id) if session.role == "host" else session.replicas.get(id)
		if not is_instance_valid(body): continue
		if active_bodies.get(id,0) != body.get_instance_id(): active.erase(id)
		if not active.has(id):
			active_bodies[id] = body.get_instance_id()
			Style.preserve_outlines(body)
			var outlines = []
			for outline in body.find_children("*","MeshInstance3D",true,false):
				if not outline.get_meta("coop_outline",false): continue
				if outline.material_override is StandardMaterial3D:
					if not outline.get_meta("holding_private",false):
						outline.material_override = outline.material_override.duplicate()
						outline.set_meta("holding_private",true)
					outlines.append(outline)
			active[id] = outlines
		var color = session.Avatar.HOLD_COLORS[clampi(int(owners[id]),0,session.Avatar.HOLD_COLORS.size()-1)]
		for outline in active[id]:
			if is_instance_valid(outline):
				outline.material_override.albedo_color = color
				outline.show()
