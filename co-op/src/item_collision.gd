extends Node
var session: Node
var host_disabled = false
var guests_disabled = false
var controls: Array = []
var host_exceptions: Dictionary = {}
var own_held: PhysicsBody3D

func add_controls(parent: Node):
	for spec in [["Disable item collision for host",true],["Disable item collision for guests",false]]:
		var button = CheckButton.new()
		button.text = spec[0]
		button.toggled.connect(set_disabled.bind(spec[1]))
		parent.add_child(button)
		controls.append([button,spec[1]])
	refresh()

func refresh():
	for row in controls:
		row[0].visible = session.role == "host"
		row[0].set_pressed_no_signal(host_disabled if row[1] else guests_disabled)

func set_disabled(value: bool, for_host: bool):
	if session.role != "host": return
	if for_host:
		host_disabled = value
		if not value:
			for body in host_exceptions.values():
				if is_instance_valid(body) and is_instance_valid(session.host_player): session.host_player.remove_collision_exception_with(body)
			host_exceptions.clear()
		else:
			for id in session.indexed_bodies: track(session.indexed_bodies[id])
	else:
		guests_disabled = value
		session._broadcast(["item_collision",guests_disabled])
	refresh()

func track(body):
	if not host_disabled or not is_instance_valid(session.host_player) or not is_instance_valid(body): return
	var id = body.get_instance_id()
	if not host_exceptions.has(id) and not body in session.host_player.get_collision_exceptions():
		session.host_player.add_collision_exception_with(body)
		host_exceptions[id] = body

func receive(disabled: bool):
	guests_disabled = disabled
	if is_instance_valid(session.guest): session.guest.collision_mask = 1 if disabled else 3

func update_held():
	if not is_instance_valid(session.guest): return
	if is_instance_valid(own_held): session.guest.remove_collision_exception_with(own_held)
	own_held = session.replicas.get(session.guest_held_id)
	if is_instance_valid(own_held): session.guest.add_collision_exception_with(own_held)
