extends RigidBody3D
const Avatar = preload("res://coop/avatar.gd")

func _ready():
	build_visual(self, get_meta("corpse_profile", Avatar.defaults()))

static func build_visual(body: Node3D, appearance: Dictionary):
	var flat = Node3D.new()
	flat.name = "FlatCharacter"
	flat.scale = Vector3(1.2, 0.1, 1.0)
	body.add_child(flat)
	var actor = Avatar.new()
	flat.add_child(actor)
	actor.configure(appearance, false)
	actor._process(0.0)
	actor.set_process(false)
	actor.rotation.x = -PI / 2
	actor.position = Vector3(0, 0.6, 1.0)
	actor.left_arm.rotation.z = 0.5
	actor.right_arm.rotation.z = -0.5
	for mesh in actor.find_children("*", "MeshInstance3D", true, false):
		var outline = MeshInstance3D.new()
		outline.name = "CorpseOutline"
		outline.mesh = mesh.mesh
		var material = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_FRONT
		material.albedo_color = Color.WHITE
		material.grow = true
		material.grow_amount = 0.015
		outline.material_override = material
		outline.set_meta("coop_outline", true)
		outline.visible = false
		mesh.add_child(outline)
	body.set_meta("coop_title", "FLATTENED " + str(appearance.get("name", "INTERN")))
	body.set_meta("coop_grabbable", true)

func object_name() -> String:
	return get_meta("coop_title", "FLATTENED INTERN")

func set_highlight(active: bool, _grabbed: bool = false):
	for mesh in find_children("*", "MeshInstance3D", true, false):
		if mesh.has_meta("coop_outline"): mesh.visible = active

func unplace():
	remove_meta("press_settling")
	freeze = false
	sleeping = false
