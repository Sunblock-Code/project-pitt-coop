extends Node
var session: Node
var host_arcs: Dictionary = {}
var arcs: Dictionary = {}
var frames = 0
var received = 0

func publish(peer: int, id: int, data: Dictionary):
	var body = instance_from_id(id)
	if not is_instance_valid(body) or body.scene_file_path.is_empty(): return
	if not session.known[peer].has(id):
		session._send(peer,["spawn",id,body.scene_file_path,body.global_transform,body.collision_layer,body.get_meta("corpse_profile",{})])
		session.known[peer][id] = true
	session._send(peer,["trading_arc",id,data])

func start(body: RigidBody3D, data: Dictionary):
	var id = body.get_instance_id()
	host_arcs[id] = data
	for peer in session.peers:
		if session.peers[peer].ready: publish(peer,id,data)

func finish(id: int):
	host_arcs.erase(id)
	for peer in session.peers:
		if session.known[peer].has(id):
			session._send(peer,["remove",[id]])
			session.known[peer].erase(id)
	session.bodies.erase(id)
	session.transform_sent.erase(id)

func receive(id: int, data: Dictionary):
	if not session.replicas.has(id): return
	var body = session.replicas[id]
	data = data.duplicate()
	data.started = Time.get_ticks_msec()
	arcs[id] = data
	session.motion_targets.erase(body.get_instance_id())
	body.collision_layer = 0
	body.set_meta("coop_grabbable",false)
	received += 1

func _process(_delta):
	if session.role != "guest": return
	for id in arcs.keys():
		if not session.replicas.has(id):
			arcs.erase(id)
			continue
		var data = arcs[id]
		var body = session.replicas[id]
		var p = clampf(data.p + (Time.get_ticks_msec()-data.started)/1000.0/maxf(data.duration,0.001),0,1)
		var pos: Vector3 = data.start.lerp(data.end,p)
		pos.y += data.height*sin(PI*p)
		body.global_transform = Transform3D(data.parent_basis * Basis.from_euler(data.rotation+data.spin*p).scaled(data.scale),pos)
		frames += 1
