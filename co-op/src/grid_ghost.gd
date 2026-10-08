extends RefCounted

# Preserve every visible mesh in object-local space, including nested offsets.
static func populate(root: MeshInstance3D, source: Node3D, material: Material):
	root.mesh = null
	root.material_override = material
	_copy(root, source, source, material)

static func _copy(root: Node3D, source: Node3D, node: Node, material: Material):
	if node is Node3D and (node.has_meta("coop_outline") or str(node.name).to_lower().contains("outline")): return
	if node is MeshInstance3D and node.mesh and node.is_visible_in_tree():
		var part = MeshInstance3D.new()
		part.mesh = node.mesh
		part.material_override = material
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(part)
		part.transform = source.global_transform.affine_inverse() * node.global_transform
	for child in node.get_children(): _copy(root, source, child, material)
