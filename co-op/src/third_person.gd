extends Node3D
## The gameplay eye camera stays in place, so grabbing and network reach do not change.
var eye: Camera3D
var player: Node3D
var arm: SpringArm3D
var camera: Camera3D
var active = false
var original_meshes: Dictionary = {}

func _ready():
	process_priority = 100
	arm = SpringArm3D.new()
	arm.spring_length = 3.1
	arm.margin = 0.2
	arm.collision_mask = 257
	var shape = SphereShape3D.new()
	shape.radius = 0.18
	arm.shape = shape
	add_child(arm)
	camera = Camera3D.new()
	camera.near = 0.05
	arm.add_child(camera)

func attach(body: Node3D, source: Camera3D):
	player = body
	eye = source
	# The host scene includes a visible capsule body and face primitives.
	# Only replace these direct body visuals, never equipped objects or lights.
	for item in player.get_children():
		if item is MeshInstance3D:
			original_meshes[item] = item.visible
	if player is CollisionObject3D:
		arm.add_excluded_object(player.get_rid())

func set_active(value: bool):
	active = value and is_instance_valid(eye)
	for item in original_meshes:
		if is_instance_valid(item):
			item.visible = false if active else original_meshes[item]
	if active:
		_update_pose()
		camera.make_current()
	elif is_instance_valid(eye):
		eye.make_current()

func _process(_delta):
	if active and is_instance_valid(eye) and is_instance_valid(player):
		_update_pose()
		if not camera.current:
			camera.make_current()
	elif active:
		active = false

func _update_pose():
	global_transform = eye.global_transform
	global_position += Vector3.UP * 0.22
	camera.fov = 75
